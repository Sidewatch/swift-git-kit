//
//  IntralineDiffTests.swift
//  GitKitTests
//
//  Tests for `IntralineDiff`: the changed word in a long line, whitespace-separated changes as
//  one span, a rewrite gets nothing, UTF-16 ranges, and pairing inside a unified diff.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Tests for `IntralineDiff`: the changed word in a long line, whitespace-separated changes as
/// one span, a rewrite gets nothing, UTF-16 ranges, and pairing inside a unified diff.
final class IntralineDiffTests: XCTestCase {
    private func text(_ s: String, _ ranges: [NSRange]) -> [String] { ranges.map { (s as NSString).substring(with: $0) } }

    func testOneChangedArgumentInALongLine() throws {
        let old = "let response = try await client.fetch(url: endpoint, timeout: 30, retries: 3, cache: .default)"
        let new = "let response = try await client.fetch(url: endpoint, timeout: 60, retries: 3, cache: .default)"
        let r = try XCTUnwrap(IntralineDiff.ranges(old: old, new: new))
        XCTAssertEqual(text(old, r.old), ["30"])
        XCTAssertEqual(text(new, r.new), ["60"])
    }

    func testChangesSeparatedOnlyBySpaceAreOneSpan() throws {
        let old = "return first second third"
        let new = "return alpha beta third"
        let r = try XCTUnwrap(IntralineDiff.ranges(old: old, new: new))
        XCTAssertEqual(text(old, r.old), ["first second"])
        XCTAssertEqual(text(new, r.new), ["alpha beta"])
    }

    func testAnInsertionMarksOnlyTheNewSide() throws {
        let old = "call(a, b)"
        let new = "call(a, extra, b)"
        let r = try XCTUnwrap(IntralineDiff.ranges(old: old, new: new))
        XCTAssertEqual(r.old, [])
        // Either alignment of the inserted space is right; the inserted word is the fact.
        XCTAssertEqual(text(new, r.new).map { $0.trimmingCharacters(in: .whitespaces) }, ["extra,"])
    }

    func testAReindentMarksTheIndentation() throws {
        let r = try XCTUnwrap(IntralineDiff.ranges(old: "    total += value", new: "        total += value"))
        XCTAssertEqual(r.old, [NSRange(location: 0, length: 4)])
        XCTAssertEqual(r.new, [NSRange(location: 0, length: 8)])
    }

    func testARewriteGetsNothing() {
        XCTAssertNil(IntralineDiff.ranges(old: "import Foundation", new: "func main() { run() }"))
    }

    func testIdenticalLinesGetNothing() {
        XCTAssertNil(IntralineDiff.ranges(old: "same", new: "same"))
    }

    func testRangesAreUTF16() throws {
        let old = "let name = \"café 🙂 one\""
        let new = "let name = \"café 🙂 two\""
        let r = try XCTUnwrap(IntralineDiff.ranges(old: old, new: new))
        XCTAssertEqual(text(old, r.old), ["one"])
        XCTAssertEqual(text(new, r.new), ["two"])
    }

    func testDiffMarksPairRemovedWithAddedInsideHunksOnly() {
        let lines = [
            "diff --git a/f b/f", "--- a/f", "+++ b/f", "@@ -1,4 +1,4 @@",
            " context", "-let timeout = 30", "\\ No newline at end of file", "+let timeout = 60", "-only removed",
            " tail",
        ]
        let marks = IntralineDiff.marks(in: lines)
        XCTAssertEqual(marks.keys.sorted(), [5, 7], "the file headers and the unpaired removal get nothing")
        XCTAssertEqual(text(lines[5], marks[5] ?? []), ["30"], "ranges are in the raw line, past the marker")
        XCTAssertEqual(text(lines[7], marks[7] ?? []), ["60"])
    }

    func testARemovedRunAfterAnAddedRunStartsAFreshPair() {
        // The unpartnered "+extra" must not pull "-beta one" into pairing with it.
        let lines = ["@@ -1,2 +1,3 @@", "-alpha one", "+alpha two", "+an extra line entirely", "-beta one", "+beta two"]
        let marks = IntralineDiff.marks(in: lines)
        XCTAssertEqual(text(lines[4], marks[4] ?? []), ["one"])
        XCTAssertEqual(text(lines[5], marks[5] ?? []), ["two"])
    }

    func testAMinifiedLineIsNotCompared() {
        let old = (0..<600).map { "a\($0)" }.joined(separator: ",")
        let new = old + ",z"
        XCTAssertNil(IntralineDiff.ranges(old: old, new: new))
    }
}
