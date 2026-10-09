//
//  GitRunTests.swift
//  GitKitTests
//
//  Tests for the one launch point: the environment every call runs under, lossy decoding, the
//  timeout, and the error-capturing form.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Tests for `Git.run`: the environment every call runs under, lossy decoding, the timeout, and
/// the error-capturing form.
final class GitRunTests: XCTestCase {

    private var repos: [ScratchRepo] = []

    override func tearDown() {
        repos.forEach { $0.cleanup() }
        repos.removeAll()
        super.tearDown()
    }

    private func repo() throws -> ScratchRepo {
        let r = try ScratchRepo(label: "gitrun")
        repos.append(r)
        return r
    }

    /// A `GIT_DIR` exported by the shell that launched the app would point every call at another
    /// repository; the inherited variable must not reach git.
    func testAnInheritedGitDirIsStripped() throws {
        let r = try repo()
        setenv("GIT_DIR", "/nonexistent/elsewhere/.git", 1)
        defer { unsetenv("GIT_DIR") }
        XCTAssertEqual(Git.repoRoot(for: r.root)?.standardizedFileURL, r.root.standardizedFileURL)
        XCTAssertNotNil(Git.run(["status", "--porcelain"], in: r.root))
    }

    /// One byte that is not UTF-8 anywhere in a diff used to turn the whole result into `""`.
    func testStdoutIsDecodedLossily() throws {
        let r = try repo()
        try r.write(Data([0x61, 0x0A]), to: "bin.txt")  // "a\n"
        r.commitAll("seed")
        try r.write(Data([0x61, 0xFF, 0x0A]), to: "bin.txt")  // "a" + a lone 0xFF byte
        let diff = try XCTUnwrap(Git.run(["diff", "--no-color", "--text", "HEAD", "--", "bin.txt"], in: r.root))
        XCTAssertTrue(diff.hasPrefix("diff --git a/bin.txt b/bin.txt"), diff)
        XCTAssertTrue(diff.contains("\u{FFFD}"), "the stray byte becomes a replacement character, not an empty result")
    }

    /// A wedged git releases the caller at the default timeout; the run reports failure (`nil`).
    func testATimedOutRunReturnsNilPromptly() throws {
        let saved = Git.executable
        defer { Git.executable = saved }
        Git.executable = "/bin/sh"
        let start = Date()
        let out = Git.run(["-c", "sleep 5; echo late"], in: URL(fileURLWithPath: NSTemporaryDirectory()), timeout: 0.3)
        XCTAssertNil(out)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "released at the timeout, not after the 5 s sleep")
    }

    /// The commit path shows git's own words, so stderr and the status must survive.
    func testRunCapturingErrorKeepsStderrAndStatus() throws {
        let r = try repo()
        try r.write("x\n", to: "f.txt")
        r.commitAll("seed")
        let result = Git.runCapturingError(["rev-parse", "--verify", "no-such-ref"], in: r.root)
        XCTAssertTrue(result.launched)
        XCTAssertFalse(result.succeeded)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.message.lowercased().contains("fatal"), result.message)
    }

    /// A caller's `GIT_INDEX_FILE` must win over the stripped inherited one — it is how every
    /// scratch-index call works.
    func testACallersEnvironmentIsLayeredLast() throws {
        let r = try repo()
        try r.write("x\n", to: "a.txt")
        let scratch = NSTemporaryDirectory() + "gitrun-index-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        XCTAssertNotNil(Git.run(["add", "--", "a.txt"], in: r.root, environment: ["GIT_INDEX_FILE": scratch]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch), "the add went to the scratch index")
        XCTAssertEqual(r.porcelain(), ["?? a.txt"], "and not to the real one")
    }
}
