//
//  GitHistoryTests.swift
//  GitKitTests
//
//  File and line-range history through the real git: newest first, each commit with its own
//  patch, a rename followed, a line range traced through the edits that moved it, and the
//  whitespace option on every reading diff.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// File and line-range history through the real git, and the whitespace option.
final class GitHistoryTests: XCTestCase {
    private var repo: ScratchRepo!

    override func setUpWithError() throws { repo = try ScratchRepo(label: "history") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo.root) }

    /// Three commits to `a.swift`, then a rename to `b.swift` with one more edit.
    private func buildHistory() throws {
        try repo.write("func one() {}\nfunc two() {\n    return 1\n}\n", to: "a.swift")
        repo.commitAll("add a")
        try repo.write("func one() {}\nfunc two() {\n    return 2\n}\n", to: "a.swift")
        repo.commitAll("two returns 2")
        try repo.write("unrelated\n", to: "other.txt")
        repo.commitAll("other file")
        repo.git(["mv", "a.swift", "b.swift"])
        try repo.write("func one() { print(1) }\nfunc two() {\n    return 2\n}\n", to: "b.swift")
        repo.commitAll("rename, one prints")
    }

    func testFileHistoryIsNewestFirstWithEachCommitsPatchAcrossARename() throws {
        try buildHistory()
        let history = Git.fileHistory(path: "b.swift", repoRoot: repo.root)
        XCTAssertEqual(
            history.map(\.commit.subject), ["rename, one prints", "two returns 2", "add a"], "the other file's commit is not in it")
        XCTAssertTrue(history[1].patch.contains("-    return 1") && history[1].patch.contains("+    return 2"), history[1].patch)
        XCTAssertFalse(history[1].patch.contains("unrelated"))
        XCTAssertTrue(history[0].patch.hasPrefix("diff --git"), "the patch starts at its header: \(history[0].patch.prefix(60))")
    }

    func testLineHistoryTracesOneFunctionOnly() throws {
        try buildHistory()
        // `two()` is lines 2–4 now; the rename commit touched only line 1.
        let history = Git.lineHistory(path: "b.swift", lines: 2...4, repoRoot: repo.root)
        XCTAssertEqual(history.map(\.commit.subject), ["two returns 2", "add a"], "\(history.map(\.commit.subject))")
        XCTAssertTrue(history[0].patch.contains("+    return 2"), history[0].patch)
        XCTAssertFalse(history[0].patch.contains("print(1)"), "only the range's lines")
    }

    func testANewFileHasNoHistory() throws {
        try repo.write("x\n", to: "seed.txt")
        repo.commitAll("seed")
        try repo.write("new\n", to: "fresh.txt")
        XCTAssertEqual(Git.fileHistory(path: "fresh.txt", repoRoot: repo.root), [])
        XCTAssertEqual(Git.lineHistory(path: "fresh.txt", lines: 1...1, repoRoot: repo.root), [])
    }

    func testIgnoringWhitespaceDropsAReindentButKeepsARealChange() throws {
        let old = "func f() {\n    let a = 1\n    let b = 2\n}\n"
        let new = "func f() {\n        let a = 1\n    let b = 3\n}\n"
        let exact = Git.unifiedDiff(old: old, new: new, oldName: "f", newName: "f")
        let loose = Git.unifiedDiff(old: old, new: new, oldName: "f", newName: "f", ignoringWhitespace: true)
        XCTAssertTrue(exact.contains("+        let a = 1"), exact)
        XCTAssertFalse(loose.contains("let a = 1\n+"), loose)
        XCTAssertFalse(loose.contains("-    let a = 1"), "the re-indent is gone: \(loose)")
        XCTAssertTrue(loose.contains("+    let b = 3"), "the real change stays: \(loose)")
        XCTAssertEqual(
            Git.unifiedDiff(old: "a\n  b\n", new: "a\n    b\n", oldName: "x", newName: "x", ignoringWhitespace: true), "",
            "whitespace only: nothing")
    }

    func testTheWorkingTreeAndCommitDiffsTakeTheOption() throws {
        try repo.write("if x {\n  go()\n}\n", to: "c.txt")
        repo.commitAll("c")
        try repo.write("if x {\n      go()\n}\n", to: "c.txt")
        let head = repo.head()
        XCTAssertTrue((Git.workingTreeDiff(repoRoot: repo.root, from: head) ?? "").contains("+      go()"))
        XCTAssertFalse((Git.workingTreeDiff(repoRoot: repo.root, from: head, ignoringWhitespace: true) ?? "").contains("go()"))
        XCTAssertFalse((Git.checkpointDiff(from: head, to: nil, repoRoot: repo.root, ignoringWhitespace: true) ?? "").contains("go()"))
        repo.commitAll("reindent")
        XCTAssertTrue((Git.showCommit(repo.head(), repoRoot: repo.root) ?? "").contains("+      go()"))
        XCTAssertFalse((Git.showCommit(repo.head(), repoRoot: repo.root, ignoringWhitespace: true) ?? "").contains("+      go()"))
    }
}
