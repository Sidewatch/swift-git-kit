//
//  FileAtHeadTests.swift
//  GitKitTests
//
//  `Git.headText` and `Git.addedLines` through the real git.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// `Git.headText(of:repoRoot:)` and `Git.addedLines(for:repoRoot:)`.
final class FileAtHeadTests: XCTestCase {
    private var repo: ScratchRepo!

    override func setUpWithError() throws { repo = try ScratchRepo(label: "fileathead") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo.root) }

    func testHeadTextIsTheCommittedVersion() throws {
        try repo.write("old\n", to: "deps.json")
        repo.commitAll("deps")
        try repo.write("new\n", to: "deps.json")
        XCTAssertEqual(Git.headText(of: repo.url("deps.json"), repoRoot: repo.root), "old\n")
        try repo.write("x\n", to: "fresh.txt")
        XCTAssertNil(Git.headText(of: repo.url("fresh.txt"), repoRoot: repo.root), "not in HEAD")
    }

    func testAddedLinesAreOnlyTheNewAndChangedOnes() throws {
        try repo.write("one\ntwo\nthree\n", to: "f.txt")
        repo.commitAll("f")
        try repo.write("one\nTWO\nthree\nfour\n", to: "f.txt")
        XCTAssertEqual(Git.addedLines(for: repo.url("f.txt"), repoRoot: repo.root), [2, 4])
        try repo.write("one\nthree\n", to: "g.txt")
        repo.commitAll("g")
        try repo.write("three\n", to: "g.txt")
        XCTAssertEqual(Git.addedLines(for: repo.url("g.txt"), repoRoot: repo.root), [], "a pure deletion adds nothing")
    }

    func testHeadCommitAndWorkTree() throws {
        XCTAssertNil(Git.headCommit(repoRoot: repo.root), "no commits yet")
        XCTAssertTrue(Git.isInsideWorkTree(repo.root))
        try repo.write("x\n", to: "x.txt")
        let sha = repo.commitAll("x")
        XCTAssertEqual(Git.headCommit(repoRoot: repo.root), sha)
        XCTAssertFalse(Git.isInsideWorkTree(URL(fileURLWithPath: NSTemporaryDirectory())), "the temporary folder is no checkout")
    }
}
