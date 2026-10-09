//
//  GitIndexUntouchedTests.swift
//  GitKitTests
//
//  Tests that no read through the package writes `.git/index`, even when a file's stat data is stale.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// No read through the package writes `.git/index`. A tracked file whose mtime changed while its
/// content did not is "stat-stale": `git status` and every `git diff` form refresh its entry and
/// rewrite the index on the way, and an agent's own `git commit` racing that lock fails.
final class GitIndexUntouchedTests: XCTestCase {

    private var repo: ScratchRepo!
    private var indexPath = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitindex")
        try repo.write("same\ncontent\n", to: "stale.txt")
        try repo.write("other\n", to: "other.txt")
        repo.commitAll("seed")
        indexPath = repo.url(".git/index").path
        // git's racy-file check is whole-second, so the file's mtime must land in another second
        // than the index's — two minutes ago does it, and differs from the recorded stat.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: repo.url("stale.txt").path)
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    private func indexDate() throws -> Date {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: indexPath)[.modificationDate] as? Date)
    }

    func testStatusAndEveryDiffFormLeaveAStatStaleIndexAlone() throws {
        let before = try indexDate()
        XCTAssertEqual(Git.statusEntries(repoRoot: repo.root), [])
        XCTAssertEqual(Git.lineDiff(for: repo.url("stale.txt"), repoRoot: repo.root).marks, [:])
        XCTAssertEqual(Git.lineChangesAll(repoRoot: repo.root), [:])
        XCTAssertTrue(Git.diffStat(repoRoot: repo.root) == (0, 0))
        XCTAssertEqual(Git.run(["diff", "--no-color", "HEAD", "--", "stale.txt"], in: repo.root), "", "the raw form the app uses")
        XCTAssertEqual(Git.run(["diff", "--numstat", "HEAD"], in: repo.root), "")
        XCTAssertTrue(Git.isClean(repoRoot: repo.root))
        XCTAssertEqual(try indexDate(), before)
    }

    func testCheckpointReadsLeaveAStatStaleIndexAlone() throws {
        let checkpoint = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        let before = try indexDate()
        XCTAssertEqual(Git.checkpointChangedFiles(from: checkpoint, to: nil, repoRoot: repo.root).map(\.path), [])
        XCTAssertEqual(Git.checkpointDiff(from: checkpoint, to: nil, repoRoot: repo.root), "")
        XCTAssertTrue(Git.diffStat(repoRoot: repo.root, from: checkpoint, to: nil) == (0, 0))
        XCTAssertEqual(try indexDate(), before)
    }
}
