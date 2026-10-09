//
//  GitDiffBaseTests.swift
//  GitKitTests
//
//  Tests for diffs "versus HEAD" in a repository that has no HEAD yet.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Before the first commit `git diff HEAD` exits 128 (`bad revision`); the diff base is then the
/// empty tree, and every staged file is new content.
final class GitDiffBaseTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitdiffbase")
        try repo.write("one\ntwo\n", to: "a.txt")
        repo.git(["add", "--", "a.txt"])
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    func testDiffBaseIsTheEmptyTreeBeforeTheFirstCommitAndHeadAfter() {
        XCTAssertEqual(Git.diffBase(repoRoot: repo.root), "4b825dc642cb6eb9a060e54bf8d69288fbee4904")
        repo.commitAll("first")
        XCTAssertEqual(Git.diffBase(repoRoot: repo.root), "HEAD")
    }

    func testLineDiffOnAnUnbornHeadMarksTheStagedFileAsAdded() {
        let diff = Git.lineDiff(for: repo.url("a.txt"), repoRoot: repo.root)
        XCTAssertEqual(diff.marks, [1: .added, 2: .added])
        XCTAssertEqual(diff.removed, [:])
    }

    func testLineChangesAllOnAnUnbornHeadListsTheStagedFile() {
        XCTAssertEqual(Git.lineChangesAll(repoRoot: repo.root), ["a.txt": [1: .added, 2: .added]])
    }

    func testDiffStatOnAnUnbornHeadCountsTheStagedLines() {
        XCTAssertTrue(Git.diffStat(repoRoot: repo.root) == (2, 0))
    }
}
