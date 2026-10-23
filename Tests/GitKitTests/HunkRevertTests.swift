//
//  HunkRevertTests.swift
//  GitKitTests
//
//  Tests for undoing one hunk against git's own diffs.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Undoing one hunk: the edit computed from git's real `--unified=0` diff of a real file, applied
/// to the text, puts that hunk back as `HEAD` has it and leaves every other change alone.
final class HunkRevertTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "hunkrevert")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    /// Commits `head` as `f.txt`, writes `now` over it, and returns the outcome at `line`.
    private func outcome(head: String, now: String, line: Int) throws -> HunkRevertOutcome {
        try repo.write(Data(head.utf8), to: "f.txt")
        repo.commitAll("head")
        try repo.write(Data(now.utf8), to: "f.txt")
        let diff = try XCTUnwrap(Git.gutterDiff(for: repo.url("f.txt"), repoRoot: repo.root))
        return HunkRevert.edit(at: line, in: now, diff: diff)
    }

    /// `text` with `outcome`'s edit applied, or nil when there is none.
    private func applied(_ outcome: HunkRevertOutcome, to text: String) -> String? {
        guard case .edit(let edit) = outcome else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testOneModifiedHunkIsUndoneAndTheOtherKept() throws {
        let head = "a\nb\nc\nd\ne\nf\ng\n", now = "a\nB\nc\nd\ne\nF\ng\n"
        XCTAssertEqual(applied(try outcome(head: head, now: now, line: 2), to: now), "a\nb\nc\nd\ne\nF\ng\n")
    }

    func testAnAddedRunIsTakenOut() throws {
        let head = "a\nb\n", now = "a\nnew one\nnew two\nb\n"
        XCTAssertEqual(applied(try outcome(head: head, now: now, line: 3), to: now), head)
    }

    func testADeletionIsPutBackAtTheLineBelowTheGap() throws {
        let head = "a\nb\nc\nd\n", now = "a\nd\n"
        XCTAssertEqual(applied(try outcome(head: head, now: now, line: 2), to: now), head, "the gutter marks line 2, the line below")
    }

    func testDeletionsAtTheTopAndTheEndArePutBack() throws {
        XCTAssertEqual(applied(try outcome(head: "x\ny\nz\n", now: "z\n", line: 1), to: "z\n"), "x\ny\nz\n")
        repo.cleanup()
        repo = try ScratchRepo(label: "hunkrevert")
        XCTAssertEqual(applied(try outcome(head: "x\ny\nz\n", now: "x\n", line: 2), to: "x\n"), "x\ny\nz\n")
    }

    func testACRLFFileKeepsItsLineEndings() throws {
        let head = "a\r\nb\r\nc\r\n", now = "a\r\nB\r\nc\r\n"
        XCTAssertEqual(applied(try outcome(head: head, now: now, line: 2), to: now), head)
    }

    func testABaseWithoutAFinalNewlineGetsNoneBack() throws {
        let head = "a\nb", now = "a\nb\nc\n"
        XCTAssertEqual(applied(try outcome(head: head, now: now, line: 3), to: now), head)
    }

    func testANewlineTakenOffTheLastLineIsPutBack() throws {
        let head = "a\nb\n", now = "a\nB"
        XCTAssertEqual(applied(try outcome(head: head, now: now, line: 2), to: now), head)
    }

    func testAnUnchangedLineHasNothingToUndo() throws {
        XCTAssertEqual(try outcome(head: "a\nb\nc\n", now: "a\nB\nc\n", line: 3), .noChange)
    }

    func testTextThatMovedOnSinceTheDiffIsNotTouched() throws {
        try repo.write("a\nb\nc\n", to: "f.txt")
        repo.commitAll("head")
        try repo.write("a\nB\nc\n", to: "f.txt")
        let diff = try XCTUnwrap(Git.gutterDiff(for: repo.url("f.txt"), repoRoot: repo.root))
        XCTAssertEqual(HunkRevert.edit(at: 2, in: "a\nB again\nc\n", diff: diff), .textChanged)
        XCTAssertEqual(HunkRevert.edit(at: 2, in: "a\n", diff: diff), .textChanged, "shorter than the hunk")
    }

    func testHunksWithContextAreUndoneToo() {
        // A diff with three lines of context, as a diff tab shows it.
        let diff = "--- a/f.txt\n+++ b/f.txt\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n"
        guard case .edit(let edit) = HunkRevert.edit(at: 2, in: "a\nB\nc\n", diff: diff) else { return XCTFail("no edit") }
        XCTAssertEqual(("a\nB\nc\n" as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "a\nb\nc\n")
    }

    /// Random edits to a random file, then every change undone one at a time (re-diffing after
    /// each, as the app does after saving): the file ends exactly as HEAD has it.
    func testUndoingEveryChangeInTurnRestoresHead() throws {
        var generator = SeededGenerator(seed: 23)
        for round in 0..<12 {
            let head = (0..<Int.random(in: 1...12, using: &generator)).map { "line \($0)" }
            var now = head
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                switch Int.random(in: 0...2, using: &generator) {
                case 0 where !now.isEmpty: now.remove(at: Int.random(in: 0..<now.count, using: &generator))
                case 1:
                    now.insert("added \(Int.random(in: 0...99, using: &generator))", at: Int.random(in: 0...now.count, using: &generator))
                default: if !now.isEmpty { now[Int.random(in: 0..<now.count, using: &generator)] += " edited" }
                }
            }
            let headText = head.map { $0 + "\n" }.joined()
            var text = now.map { $0 + "\n" }.joined()
            try repo.write(Data(headText.utf8), to: "f.txt")
            repo.commitAll("round \(round)")
            for _ in 0..<20 {
                try repo.write(Data(text.utf8), to: "f.txt")
                let diff = try XCTUnwrap(Git.gutterDiff(for: repo.url("f.txt"), repoRoot: repo.root))
                guard let first = HunkRevert.hunks(in: diff).first?.header else { break }
                let line = first.newCount > 0 ? first.newStart : first.deletionLine
                guard let next = applied(HunkRevert.edit(at: line, in: text, diff: diff), to: text) else {
                    return XCTFail("round \(round): no edit at line \(line) of \(text.debugDescription)")
                }
                text = next
            }
            XCTAssertEqual(text, headText, "round \(round): \(head) → \(now)")
        }
    }
}

/// A small deterministic generator, so a failing round can be replayed.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
