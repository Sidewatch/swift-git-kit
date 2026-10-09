//
//  GitWorkingTreeDiffTests.swift
//  GitKitTests
//
//  Tests for the one-process diff of the whole working tree, untracked files included.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// One process diffs the whole working tree — three untracked files, a staged new file and an
/// edited file — against a commit, where the previous recipe spawned `diff --no-index` once per
/// untracked file and read a captured untracked file as `D`.
final class GitWorkingTreeDiffTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitworkingtree")
        try repo.write("orig\n", to: "tracked.txt")
        repo.commitAll("base")
        try repo.write("u1\n", to: "one.txt")
        try repo.write("u2\n", to: "sub/two.txt")
        try repo.write("u3\n", to: "three.txt")
        try repo.write("staged\n", to: "staged.txt")
        repo.git(["add", "--", "staged.txt"])
        try repo.write("edited\n", to: "tracked.txt")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    func testAllFiveChangesComeBackFromOneCallWithNoDeletions() throws {
        let entries = Git.workingTreeChangedFiles(repoRoot: repo.root, from: "HEAD")
        let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.kind) })
        XCTAssertEqual(
            byPath,
            ["one.txt": .added, "sub/two.txt": .added, "three.txt": .added, "staged.txt": .added, "tracked.txt": .modified])

        let diff = try XCTUnwrap(Git.workingTreeDiff(repoRoot: repo.root, from: "HEAD"))
        XCTAssertEqual(diff.components(separatedBy: "\ndiff --git ").count, 5, diff)
        for text in ["+u1\n", "+u2\n", "+u3\n", "+staged\n", "-orig\n+edited\n", "+++ b/sub/two.txt"] {
            XCTAssertTrue(diff.contains(text), "missing \(text.debugDescription)")
        }
        XCTAssertFalse(diff.contains("deleted file"), diff)
        XCTAssertEqual(repo.porcelain().sorted(), ["A  staged.txt", " M tracked.txt", "?? one.txt", "?? sub/", "?? three.txt"].sorted())
    }

    func testPathsNarrowTheDiff() throws {
        let diff = try XCTUnwrap(Git.workingTreeDiff(repoRoot: repo.root, from: "HEAD", paths: ["sub/two.txt", "tracked.txt"]))
        XCTAssertTrue(diff.contains("+u2\n"))
        XCTAssertTrue(diff.contains("+edited\n"))
        XCTAssertFalse(diff.contains("u1"))
        XCTAssertEqual(Git.workingTreeChangedFiles(repoRoot: repo.root, from: "HEAD", paths: ["one.txt"]).map(\.path), ["one.txt"])
    }

    /// Against the empty tree, before the first commit, every file is new content.
    func testWorksAgainstTheDiffBaseOfAnUnbornHead() throws {
        let fresh = try ScratchRepo(label: "gitworkingtree-unborn")
        defer { fresh.cleanup() }
        try fresh.write("a\n", to: "a.txt")
        try fresh.write("b\n", to: "b.txt")
        fresh.git(["add", "--", "b.txt"])
        let base = Git.diffBase(repoRoot: fresh.root)
        XCTAssertEqual(Git.workingTreeChangedFiles(repoRoot: fresh.root, from: base).map(\.path).sorted(), ["a.txt", "b.txt"])
        XCTAssertTrue(Git.workingTreeDiff(repoRoot: fresh.root, from: base)?.contains("+a\n") ?? false)
    }
}
