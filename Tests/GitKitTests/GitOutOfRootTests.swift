//
//  GitOutOfRootTests.swift
//  GitKitTests
//
//  Tests that a read of a file outside the repository answers empty without running git.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// A read of a file outside the repository answers empty without running git: the basename
/// fallback of `relativePath` could otherwise diff or blame an unrelated same-named file.
final class GitOutOfRootTests: XCTestCase {

    private var repo: ScratchRepo!
    private var marker: URL!
    private var spy: URL!
    private var savedExecutable = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitoutofroot")
        try repo.write("x\n", to: "thing.txt")
        repo.commitAll("seed")
        // A stand-in for git that leaves a marker whenever it is launched.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gitspy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        marker = dir.appendingPathComponent("launched")
        spy = dir.appendingPathComponent("git")
        try "#!/bin/sh\ntouch '\(marker.path)'\nexit 1\n".write(to: spy, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: spy.path)
        savedExecutable = Git.executable
        Git.executable = spy.path
    }

    override func tearDown() {
        Git.executable = savedExecutable
        try? FileManager.default.removeItem(at: spy.deletingLastPathComponent())
        repo.cleanup()
        super.tearDown()
    }

    func testLineDiffOfAFileOutsideTheRootIsEmptyWithoutRunningGit() {
        let outside = URL(fileURLWithPath: "/elsewhere/thing.txt")
        let diff = Git.lineDiff(for: outside, repoRoot: repo.root)
        XCTAssertEqual(diff.marks, [:])
        XCTAssertEqual(diff.removed, [:])
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "git was launched for a file outside the repository")
    }

    func testBlameOfAFileOutsideTheRootIsNilWithoutRunningGit() {
        let outside = URL(fileURLWithPath: "/elsewhere/thing.txt")
        XCTAssertNil(Git.blame(for: outside, line: 1, repoRoot: repo.root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "git was launched for a file outside the repository")
    }

    func testTheSpyIsLaunchedForAFileInsideTheRoot() {
        _ = Git.lineDiff(for: repo.url("thing.txt"), repoRoot: repo.root)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: marker.path), "the spy must see an in-root call, or the other two tests prove nothing")
    }
}
