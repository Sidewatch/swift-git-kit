//
//  GitHeadContentsTests.swift
//  GitKitTests
//
//  Tests for reading several files' committed bytes in one process.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Committed bytes of several paths from one `cat-file --batch` run.
final class GitHeadContentsTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "githeadcontents")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    func testCommittedBytesForTrackedPathsAndNothingForTheRest() throws {
        try repo.write("one\n", to: "a.txt")
        try repo.write("in a folder with a space\n", to: "sub dir/b.txt")
        let binary = Data([0x00, 0x0A, 0xFF, 0x0A, 0x0A, 0x20])  // newlines and NULs inside the blob
        try repo.write(binary, to: "blob.bin")
        try repo.write(Data([0xE9, 0x74, 0xE9, 0x0A]), to: "latin1.txt")
        _ = repo.commitAll("initial")
        try repo.write("two\n", to: "a.txt")  // the working tree moves on; HEAD keeps "one"
        try repo.write("untracked\n", to: "new.txt")

        let got = Git.headContents(
            paths: ["a.txt", "new.txt", "sub dir/b.txt", "sub dir", "bad\nname", "blob.bin", "latin1.txt", "a.txt"], repoRoot: repo.root)
        XCTAssertEqual(Set(got.keys), ["a.txt", "sub dir/b.txt", "blob.bin", "latin1.txt"])
        XCTAssertEqual(got["a.txt"], Data("one\n".utf8))
        XCTAssertEqual(got["sub dir/b.txt"], Data("in a folder with a space\n".utf8))
        XCTAssertEqual(got["blob.bin"], binary, "the bytes are undecoded and exact")
        XCTAssertEqual(got["latin1.txt"], Data([0xE9, 0x74, 0xE9, 0x0A]), "bytes that are not UTF-8 survive")
    }

    func testAnUnbornBranchHasNothing() throws {
        try repo.write("one\n", to: "a.txt")
        XCTAssertEqual(Git.headContents(paths: ["a.txt"], repoRoot: repo.root), [:])
    }

    func testRecordsAfterAMissingOrTreeRecordStillLineUp() {
        let out = Data("HEAD:gone missing\nabc tree 5\nxxxxx\ndef blob 3\nhi\n\n".utf8)
        XCTAssertEqual(Git.parseBatch(out, paths: ["gone", "dir", "f"]), ["f": Data("hi\n".utf8)])
    }
}
