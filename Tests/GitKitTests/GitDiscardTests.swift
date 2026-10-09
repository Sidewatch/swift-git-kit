//
//  GitDiscardTests.swift
//  GitKitTests
//
//  Tests for the discards that must refuse: a conflicted file and a gitlink.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// The discards that must refuse: a conflicted file has no one `HEAD` version to return to, and
/// a gitlink stands for a whole checkout `restore` cannot revert.
final class GitDiscardTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitdiscard")
        try repo.write("seed\n", to: "seed.txt")
        repo.commitAll("seed")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    func testAConflictedFileIsRefusedAndLeftAlone() throws {
        repo.makeMergeConflict()
        let file = repo.url("conflict.txt")
        let before = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(before.contains("<<<<<<<"), "the fixture must hold conflict markers")
        XCTAssertFalse(Git.discard(file, kind: .conflicted, repoRoot: repo.root))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), before)
        XCTAssertEqual(repo.porcelain(), ["UU conflict.txt"])
        repo.git(["merge", "--abort"])
    }

    func testAGitlinkIsRefusedForEveryKind() throws {
        let sub = try ScratchRepo(label: "gitdiscard-sub")
        defer { sub.cleanup() }
        try sub.write("s\n", to: "s.txt")
        sub.commitAll("sub seed")
        XCTAssertNotNil(repo.git(["-c", "protocol.file.allow=always", "submodule", "add", "-q", sub.root.path, "sub"]))
        repo.commitAll("add sub")
        let inner = try XCTUnwrap(Git.repoRoot(for: repo.url("sub")))
        try "s2\n".write(to: inner.appendingPathComponent("s.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: inner)
        _ = Git.run(["commit", "-q", "-m", "bump"], in: inner)
        XCTAssertEqual(repo.porcelain(), [" M sub"], "the fixture must be a pointer bump")

        XCTAssertFalse(Git.discard(repo.url("sub"), kind: .modified, repoRoot: repo.root))
        XCTAssertFalse(Git.discard(repo.url("sub"), kind: .added, repoRoot: repo.root))
        XCTAssertFalse(Git.discard(repo.url("sub"), kind: .deleted, repoRoot: repo.root))
        XCTAssertEqual(repo.porcelain(), [" M sub"], "the submodule is exactly as it was")
        XCTAssertEqual(try String(contentsOf: inner.appendingPathComponent("s.txt"), encoding: .utf8), "s2\n")
    }
}
