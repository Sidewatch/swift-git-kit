//
//  GitBlobHashTests.swift
//  GitKitTests
//
//  Tests for hashing several working-tree files in one process.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Hashing several working-tree files in one `hash-object --stdin-paths` run.
final class GitBlobHashTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitblobhash")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    /// `hash-object --stdin-paths` stops at the first path it cannot open, so an unhashable path
    /// must be left out of the request rather than fail the whole batch.
    func testHashesEveryReadableFileAndSkipsTheRest() throws {
        try repo.write("alpha\n", to: "a.txt")
        try repo.write("beta\n", to: "sub/b.txt")
        try repo.write("hidden\n", to: "secret.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: repo.url("secret.txt").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: repo.url("secret.txt").path) }

        let hashes = Git.blobHashes(paths: ["a.txt", "missing.txt", "sub", "sub/b.txt", "secret.txt", "a.txt"], repoRoot: repo.root)
        XCTAssertEqual(Set(hashes.keys), ["a.txt", "sub/b.txt"])
        XCTAssertEqual(hashes["a.txt"], repo.git(["hash-object", "a.txt"])?.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(hashes["sub/b.txt"], repo.git(["hash-object", "sub/b.txt"])?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testNoHashablePathsIsEmpty() {
        XCTAssertEqual(Git.blobHashes(paths: ["missing.txt"], repoRoot: repo.root), [:])
        XCTAssertEqual(Git.blobHashes(paths: [], repoRoot: repo.root), [:])
    }
}
