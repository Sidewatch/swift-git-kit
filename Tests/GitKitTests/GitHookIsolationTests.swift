//
//  GitHookIsolationTests.swift
//  GitKitTests
//
//  A repository's own code — its fsmonitor command and its hooks — never runs on a read, a
//  stage or a restore; only the person's commit runs the hooks.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// A cloned repository's `.git/config` can name a `core.fsmonitor` command and its `.git/hooks`
/// can hold any executable. `git status` runs the former; `git add` runs `post-index-change`.
/// Every call here except `Git.commit` runs with `core.fsmonitor=false` and
/// `core.hooksPath=/dev/null`, so the repository's code runs only when the person commits.
final class GitHookIsolationTests: XCTestCase {
    private var repo: ScratchRepo!
    private var markers: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "githooks")
        markers = FileManager.default.temporaryDirectory.appendingPathComponent("githooks-markers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: markers, withIntermediateDirectories: true)
        try repo.write("one\n", to: "a.txt")
        repo.commitAll("seed")
    }

    override func tearDown() {
        repo.cleanup()
        try? FileManager.default.removeItem(at: markers)
        super.tearDown()
    }

    private func marker(_ name: String) -> URL { markers.appendingPathComponent(name) }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: marker(name).path) }

    /// Installs `.git/hooks/<hook>` touching `markerName` when it runs.
    private func installHook(_ hook: String, touching markerName: String) throws {
        let url = repo.url(".git/hooks/\(hook)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\ntouch '\(marker(markerName).path)'\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func testAnFsmonitorCommandInTheRepositoryNeverRunsOnARead() throws {
        repo.git(["config", "core.fsmonitor", "touch '\(marker("fsmonitor").path)'"])
        try repo.write("two\n", to: "a.txt")
        _ = Git.statusEntries(repoRoot: repo.root)
        _ = Git.lineChanges(for: repo.url("a.txt"), repoRoot: repo.root)
        _ = Git.workingTreeDiff(repoRoot: repo.root, from: "HEAD")
        XCTAssertFalse(exists("fsmonitor"), "status and diffs ran without consulting the repository's monitor command")
        XCTAssertEqual(Git.statusEntries(repoRoot: repo.root).map(\.path), ["a.txt"], "and still saw the change")
        // The same command run by git itself, outside the package's environment, does fire — so
        // the check above is not vacuous.
        let bare = Process()
        bare.executableURL = URL(fileURLWithPath: Git.executable)
        bare.arguments = ["status", "--porcelain"]
        bare.currentDirectoryURL = repo.root
        try bare.run()
        bare.waitUntilExit()
        XCTAssertEqual(bare.terminationStatus, 0)
        XCTAssertTrue(exists("fsmonitor"), "git on its own runs the configured command")
    }

    func testAStageOrRestoreRunsNoHookWhileACommitRunsPreCommit() throws {
        try installHook("post-index-change", touching: "index-change")
        try installHook("pre-commit", touching: "pre-commit")
        try installHook("post-checkout", touching: "checkout")
        try repo.write("two\n", to: "a.txt")
        XCTAssertTrue(Git.stage(repo.url("a.txt"), repoRoot: repo.root))
        XCTAssertFalse(exists("index-change"), "git add wrote the index and ran no hook")
        XCTAssertTrue(Git.unstage(repo.url("a.txt"), repoRoot: repo.root))
        XCTAssertTrue(Git.discard(repo.url("a.txt"), kind: .modified, repoRoot: repo.root))
        XCTAssertFalse(exists("index-change") || exists("checkout"), "restore ran no hook either")

        try repo.write("three\n", to: "a.txt")
        let entries = Git.statusEntries(repoRoot: repo.root)
        XCTAssertEqual(entries.map(\.path), ["a.txt"])
        guard case .success = Git.commit(entries: entries, message: "the person's commit", repoRoot: repo.root) else {
            return XCTFail("the commit failed")
        }
        XCTAssertTrue(exists("pre-commit"), "the person's own commit runs their pre-commit hook")
    }

    func testTheEnvironmentNamesBothRules() {
        let read = Git.environment(hooks: false)
        XCTAssertEqual(read["GIT_CONFIG_COUNT"], "3")
        XCTAssertEqual(read["GIT_CONFIG_KEY_1"], "core.fsmonitor")
        XCTAssertEqual(read["GIT_CONFIG_VALUE_1"], "false")
        XCTAssertEqual(read["GIT_CONFIG_KEY_2"], "core.hooksPath")
        XCTAssertEqual(read["GIT_CONFIG_VALUE_2"], "/dev/null")
        let commit = Git.environment(hooks: true)
        XCTAssertEqual(commit["GIT_CONFIG_COUNT"], "2", "a commit keeps the monitor off and the hooks on")
        XCTAssertNil(commit["GIT_CONFIG_KEY_2"])
    }
}
