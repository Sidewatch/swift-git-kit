//
//  GitDeletionMarkTests.swift
//  GitKitTests
//
//  Tests for where a pure deletion is marked: the line below the removal, where its ghost rows sit.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// A pure deletion is keyed at `newStart + 1` — the first surviving line below the removal, the
/// same line the ghost rows render above — in both the per-file and the all-files maps.
final class GitDeletionMarkTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitdeletion")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    private func seed(_ files: [String: String]) throws {
        for (name, contents) in files { try repo.write(contents, to: name) }
        repo.commitAll("seed")
    }

    /// `@@ -1 +0,0 @@`: the first line is gone; line 1 is the first survivor.
    func testDeletionBeforeTheFirstLineMarksLineOne() throws {
        try seed(["f.txt": "a\nb\n"])
        try repo.write("b\n", to: "f.txt")
        let diff = Git.lineDiff(for: repo.url("f.txt"), repoRoot: repo.root)
        XCTAssertEqual(diff.marks, [1: .deleted])
        XCTAssertEqual(diff.removed, [1: ["a"]])
    }

    /// `@@ -2 +1,0 @@`: line 2 of the result ("c") is the survivor below the gap, not line 1.
    func testDeletionAfterTheFirstLineMarksLineTwo() throws {
        try seed(["f.txt": "a\nb\nc\n"])
        try repo.write("a\nc\n", to: "f.txt")
        let diff = Git.lineDiff(for: repo.url("f.txt"), repoRoot: repo.root)
        XCTAssertEqual(diff.marks, [2: .deleted])
        XCTAssertEqual(diff.removed, [2: ["b"]])
    }

    /// `@@ -3 +2,0 @@`.
    func testDeletionAfterTheSecondLineMarksLineThree() throws {
        try seed(["f.txt": "a\nb\nc\nd\n"])
        try repo.write("a\nb\nd\n", to: "f.txt")
        XCTAssertEqual(Git.lineChanges(for: repo.url("f.txt"), repoRoot: repo.root), [3: .deleted])
    }

    /// `@@ -5 +4,0 @@` in a four-line result: the key is one past the last line.
    func testDeletionAtTheEndOfTheFileMarksOnePastTheLastLine() throws {
        try seed(["f.txt": "a\nb\nc\nd\ne\n"])
        try repo.write("a\nb\nc\nd\n", to: "f.txt")
        let diff = Git.lineDiff(for: repo.url("f.txt"), repoRoot: repo.root)
        XCTAssertEqual(diff.marks, [5: .deleted])
        XCTAssertEqual(diff.removed, [5: ["e"]])
    }

    /// `+0,0` and `+1,0` in one file used to collide on line 1 (`max(1, newStart)`), losing a mark
    /// and putting the surviving one a row above its ghosts.
    func testTwoDeletionsAtTheTopDoNotCollide() throws {
        try seed(["f.txt": "a\nb\nc\nd\n"])
        try repo.write("b\nd\n", to: "f.txt")
        let diff = Git.lineDiff(for: repo.url("f.txt"), repoRoot: repo.root)
        XCTAssertEqual(diff.marks, [1: .deleted, 2: .deleted])
        XCTAssertEqual(diff.removed, [1: ["a"], 2: ["c"]])
    }

    func testPerFileAndAllFilesMapsAgreeOnEveryDeletionShape() throws {
        try seed(["top.txt": "a\nb\n", "mid.txt": "a\nb\nc\n", "end.txt": "a\nb\nc\nd\ne\n", "two.txt": "a\nb\nc\nd\n"])
        try repo.write("b\n", to: "top.txt")
        try repo.write("a\nc\n", to: "mid.txt")
        try repo.write("a\nb\nc\nd\n", to: "end.txt")
        try repo.write("b\nd\n", to: "two.txt")
        let all = Git.lineChangesAll(repoRoot: repo.root)
        for name in ["top.txt", "mid.txt", "end.txt", "two.txt"] {
            XCTAssertEqual(all[name], Git.lineChanges(for: repo.url(name), repoRoot: repo.root), name)
        }
        XCTAssertEqual(all["end.txt"], [5: .deleted])
    }
}
