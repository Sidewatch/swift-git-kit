//
//  GitDiffStatRangeTests.swift
//  GitKit
//
//  Tests for `Git.diffStat(repoRoot:from:to:)`: the line counts for a span between two
//  commits, and for a commit against the working tree as it stands.
//
//  Created by David Sherlock on 9/13/26.
//

import XCTest
@testable import GitKit

/// Tests for `Git.diffStat(repoRoot:from:to:)`. A closed span cannot move; an open one
/// tracks the working tree, which is the whole reason the API takes an optional `to`.
final class GitDiffStatRangeTests: XCTestCase {

    private var scratchDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in scratchDirs { try? FileManager.default.removeItem(at: dir) }
        scratchDirs.removeAll()
    }

    private func makeRepo() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gitcli-numstat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirs.append(dir)
        XCTAssertNotNil(Git.run(["init", "-q"], in: dir), "git init failed")
        _ = Git.run(["config", "user.email", "test@example.com"], in: dir)
        _ = Git.run(["config", "user.name", "Test Author"], in: dir)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: dir)
        return try XCTUnwrap(Git.repoRoot(for: dir))
    }

    private func commit(_ lines: [String], to name: String, in root: URL, message: String) throws -> String {
        try lines.joined(separator: "\n").appending("\n")
            .write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: root)
        _ = Git.run(["commit", "-q", "-m", message], in: root)
        return try XCTUnwrap(Git.run(["rev-parse", "HEAD"], in: root))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Three lines become five with one rewritten: +3 −1 against the first commit.
    func testClosedSpanCountsOnlyThatSpan() throws {
        let root = try makeRepo()
        let first = try commit(["one", "two", "three"], to: "f.txt", in: root, message: "base")
        let second = try commit(["one", "CHANGED", "three", "four", "five"],
                                to: "f.txt", in: root, message: "edit")

        let stat = Git.diffStat(repoRoot: root, from: first, to: second)
        XCTAssertEqual(stat.insertions, 3)
        XCTAssertEqual(stat.deletions, 1)

        // A later commit must not leak into the earlier span.
        _ = try commit(["one"], to: "f.txt", in: root, message: "gut it")
        let unchanged = Git.diffStat(repoRoot: root, from: first, to: second)
        XCTAssertEqual(unchanged.insertions, 3, "a closed span cannot move")
        XCTAssertEqual(unchanged.deletions, 1, "a closed span cannot move")
    }

    /// With no `to`, the span runs to the working tree and moves as the tree is edited.
    func testOpenSpanFollowsTheWorkingTree() throws {
        let root = try makeRepo()
        let first = try commit(["one", "two"], to: "f.txt", in: root, message: "base")

        XCTAssertEqual(Git.diffStat(repoRoot: root, from: first, to: nil).insertions, 0)

        try "one\ntwo\nthree\n".write(to: root.appendingPathComponent("f.txt"),
                                     atomically: true, encoding: .utf8)
        let stat = Git.diffStat(repoRoot: root, from: first, to: nil)
        XCTAssertEqual(stat.insertions, 1)
        XCTAssertEqual(stat.deletions, 0)
    }
}
