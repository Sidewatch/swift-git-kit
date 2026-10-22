//
//  GitFileVersionsTests.swift
//  GitKitTests
//
//  Tests for reading one file at several commits.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// One file at several commits from two `cat-file` runs, in the commits' order.
final class GitFileVersionsTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitfileversions")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    func testEachCommitsVersionInOrderAndNilWhereTheFileWasNot() throws {
        try repo.write("other\n", to: "other.txt")
        let before = repo.commitAll("before the file")
        try repo.write("one\n", to: "sub dir/f.txt")
        let first = repo.commitAll("first")
        try repo.write("two\n", to: "sub dir/f.txt")
        let second = repo.commitAll("second")
        try repo.delete("sub dir/f.txt")
        let gone = repo.commitAll("gone")

        let got = Git.fileVersions(path: "sub dir/f.txt", commits: [second, before, first, gone, first], repoRoot: repo.root)
        XCTAssertEqual(got, [Data("two\n".utf8), nil, Data("one\n".utf8), nil, Data("one\n".utf8)])
    }

    func testASnapshotCommitThatIsNoBranchIsRead() throws {
        try repo.write("committed\n", to: "f.txt")
        repo.commitAll("base")
        try repo.write("in progress\n", to: "f.txt")
        let snapshot = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        XCTAssertEqual(Git.fileVersions(path: "f.txt", commits: [snapshot], repoRoot: repo.root), [Data("in progress\n".utf8)])
    }

    func testANameThatIsNotAnObjectIDIsNeverAsked() throws {
        try repo.write("x\n", to: "f.txt")
        let head = repo.commitAll("base")
        // "HEAD" and "HEAD~0" would read; "--batch" would be an option. Only object ids are asked.
        let got = Git.fileVersions(path: "f.txt", commits: ["HEAD", head, "--batch", "", head + "\n"], repoRoot: repo.root)
        XCTAssertEqual(got, [nil, Data("x\n".utf8), nil, nil, nil])
    }

    func testAPathGitCannotCarryHasNoVersions() throws {
        try repo.write("x\n", to: "f.txt")
        try repo.write("not this one\n", to: "bad")  // what the first half of "bad\nname" would read
        let head = repo.commitAll("base")
        XCTAssertEqual(Git.fileVersions(path: "bad\nname", commits: [head], repoRoot: repo.root), [nil])
        XCTAssertEqual(Git.fileVersions(path: "", commits: [head, head], repoRoot: repo.root), [nil, nil])
        XCTAssertEqual(Git.fileVersions(path: "f.txt", commits: [], repoRoot: repo.root), [])
    }

    func testAFolderIsNotAFile() throws {
        try repo.write("x\n", to: "dir/f.txt")
        let head = repo.commitAll("base")
        XCTAssertEqual(Git.fileVersions(path: "dir", commits: [head], repoRoot: repo.root), [nil])
        XCTAssertEqual(Git.blobIDs(path: "dir", commits: [head], repoRoot: repo.root), [nil], "a tree is never read as a version")
    }
}
