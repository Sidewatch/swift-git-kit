//
//  GitPathspecTests.swift
//  GitKitTests
//
//  Tests that a path is a path: `app/[id]/page.tsx` names one file, not every `app/?/page.tsx`,
//  and `:colon.txt` is a file, not pathspec magic.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Tests that a path is a path: `app/[id]/page.tsx` names one file, not every `app/?/page.tsx`,
/// and `:colon.txt` is a file, not pathspec magic.
final class GitPathspecTests: XCTestCase {

    private var repo: ScratchRepo!
    private let dynamic = "app/[id]/page.tsx"
    private let sibling = "app/i/page.tsx"

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitpathspec")
        // Distinct contents: with identical files `--follow` would take `[id]` for a copy of `i`.
        try repo.write("one\ntwo\nthree\nfour\nfive\n", to: sibling)
        repo.commitAll("add i")
        try repo.write("export default function Page() {}\ntwo\nthree\nfour\nfive\n", to: dynamic)
        repo.commitAll("add [id]")
        try repo.write("export default function Page() { return null }\ntwo\nthree\nfour\nfive\n", to: dynamic)  // line 1
        try repo.write("one\ntwo\nthree\nfour\nFIVE\n", to: sibling)  // line 5
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    /// Globbed, `app/[id]/page.tsx` also matches `app/i/page.tsx`, and the sibling's hunk lands
    /// in this file's gutter.
    func testLineDiffOfABracketedPathCoversOnlyThatFile() {
        XCTAssertEqual(Git.lineChanges(for: repo.url(dynamic), repoRoot: repo.root), [1: .modified])
    }

    func testStagingABracketedPathLeavesItsGlobSiblingUnstaged() {
        XCTAssertTrue(Git.stage(repo.url(dynamic), repoRoot: repo.root))
        let staged = (repo.git(["diff", "--cached", "--name-only"]) ?? "").split(separator: "\n").map(String.init)
        XCTAssertEqual(staged, [dynamic])
    }

    func testFileLogOfABracketedPathFollowsOnlyThatFile() {
        XCTAssertEqual(Git.fileLog(path: dynamic, repoRoot: repo.root).map(\.subject), ["add [id]"])
    }

    func testBlameOfABracketedPathWorks() {
        XCTAssertEqual(Git.blame(for: repo.url(dynamic), line: 2, repoRoot: repo.root)?.summary, "add [id]")
    }

    /// A leading colon starts pathspec magic (`:(glob)`, `:/`); as a literal it is a file name.
    func testAColonPrefixedFileIsAPath() throws {
        try repo.write("x\n", to: ":colon.txt")
        XCTAssertEqual(Git.statusEntries(repoRoot: repo.root).first { $0.path == ":colon.txt" }?.kind, .untracked)
        XCTAssertTrue(Git.stage(repo.url(":colon.txt"), repoRoot: repo.root))
        XCTAssertEqual(Git.statusEntries(repoRoot: repo.root).first { $0.path == ":colon.txt" }?.kind, .added)
        XCTAssertEqual(Git.lineChanges(for: repo.url(":colon.txt"), repoRoot: repo.root), [1: .added])
    }
}
