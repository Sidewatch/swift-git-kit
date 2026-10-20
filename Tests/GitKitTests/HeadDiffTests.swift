//
//  HeadDiffTests.swift
//  GitKitTests
//
//  `Git.headDiffs` and `DiffChunks`: many files from one batched diff, each its own chunk; an
//  untracked file's all-new diff; a clean file ""; an unborn HEAD; whitespace ignored.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// `Git.headDiffs` and `DiffChunks` through the real git.
final class HeadDiffTests: XCTestCase {
    private var repo: ScratchRepo!

    override func setUpWithError() throws { repo = try ScratchRepo(label: "headdiff") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo.root) }

    func testEachFileGetsItsOwnChunkUntrackedAllNewCleanEmpty() throws {
        try repo.write("one\n", to: "a.txt")
        try repo.write("two\n", to: "dir/b c.txt")
        try repo.write("same\n", to: "clean.txt")
        repo.commitAll("base")
        try repo.write("one!\n", to: "a.txt")
        try repo.write("TWO\n", to: "dir/b c.txt")
        try repo.write("brand new\n", to: "new.txt")
        let diffs = Git.headDiffs(paths: ["a.txt", "dir/b c.txt", "clean.txt", "new.txt"], repoRoot: repo.root)
        XCTAssertTrue(diffs["a.txt"]?.contains("+one!") == true && diffs["a.txt"]?.contains("TWO") == false, diffs["a.txt"] ?? "")
        XCTAssertTrue(diffs["dir/b c.txt"]?.contains("+TWO") == true, "a path with a space keys correctly: \(diffs.keys)")
        XCTAssertEqual(diffs["clean.txt"], "")
        XCTAssertTrue(diffs["new.txt"]?.contains("+brand new") == true, "untracked: all new")
    }

    func testAnUnbornHeadDiffsAgainstTheEmptyTree() throws {
        try repo.write("first\n", to: "f.txt")
        repo.git(["add", "f.txt"])
        XCTAssertTrue(Git.headDiffs(paths: ["f.txt"], repoRoot: repo.root)["f.txt"]?.contains("+first") == true)
    }

    func testWhitespaceOnlyIsCleanWhenIgnored() throws {
        try repo.write("if x {\n  go()\n}\n", to: "w.txt")
        repo.commitAll("w")
        try repo.write("if x {\n    go()\n}\n", to: "w.txt")
        XCTAssertTrue(Git.headDiffs(paths: ["w.txt"], repoRoot: repo.root)["w.txt"]?.contains("+    go()") == true)
        XCTAssertFalse(Git.headDiffs(paths: ["w.txt"], repoRoot: repo.root, ignoringWhitespace: true)["w.txt"]?.contains("go()") == true)
    }

    func testChunksKeyByNewPathOldPathOrHeader() {
        let diff = """
            diff --git a/kept.txt b/kept.txt
            --- a/kept.txt
            +++ b/kept.txt
            @@ -1 +1 @@
            -a
            +++ b/not-a-path
            diff --git a/gone.txt b/gone.txt
            deleted file mode 100644
            --- a/gone.txt
            +++ /dev/null
            diff --git a/mode.sh b/mode.sh
            old mode 100644
            new mode 100755

            """
        let chunks = DiffChunks.byPath(diff)
        XCTAssertEqual(chunks.keys.sorted(), ["gone.txt", "kept.txt", "mode.sh"])
        XCTAssertTrue(chunks["kept.txt"]?.hasSuffix("+++ b/not-a-path\n") == true, "an added line reading `++ b/…` never renames its chunk")
    }

    func testSummaryReadsPathCountsAndKind() {
        let chunks = DiffChunks.ordered(
            """
            diff --git a/My Notes.md b/My Notes.md
            --- a/My Notes.md	
            +++ b/My Notes.md	
            @@ -1,2 +1,2 @@
            --- not a header
            +new
            diff --git a/old.txt b/new.txt
            similarity index 100%
            rename from old.txt
            rename to new.txt
            diff --git a/gone.txt b/gone.txt
            deleted file mode 100644
            --- a/gone.txt
            +++ /dev/null
            @@ -1 +0,0 @@
            -bye
            diff --git "a/tab\there" "b/tab\there"
            new file mode 100644
            --- /dev/null
            +++ "b/tab\there"
            @@ -0,0 +1 @@
            +x

            """)
        let summaries = chunks.map(DiffChunks.summary)
        XCTAssertEqual(summaries[0], DiffFileSummary(path: "My Notes.md", insertions: 1, deletions: 1, kind: .modified))
        XCTAssertEqual(summaries[1], DiffFileSummary(path: "new.txt", insertions: 0, deletions: 0, kind: .renamed(from: "old.txt")))
        XCTAssertEqual(summaries[2], DiffFileSummary(path: "gone.txt", insertions: 0, deletions: 1, kind: .deleted))
        XCTAssertEqual(
            summaries[3], DiffFileSummary(path: "tab\there", insertions: 1, deletions: 0, kind: .added), "a quoted path is decoded")
        XCTAssertEqual(
            DiffChunks.byPath(chunks.flatMap { $0 }.joined(separator: "\n")).keys.sorted(),
            ["My Notes.md", "gone.txt", "new.txt", "tab\there"])
    }

    func testUnquoteDecodesOctalUTF8() {
        XCTAssertEqual(DiffChunks.unquote("\"caf\\303\\251.txt\""), "café.txt")
        XCTAssertEqual(DiffChunks.unquote("\"a\\tb\\\"c\""), "a\tb\"c", "the \\t and \\\" escapes")
        XCTAssertEqual(DiffChunks.unquote("plain.txt"), "plain.txt")
    }
}
