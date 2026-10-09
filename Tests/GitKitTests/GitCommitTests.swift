//
//  GitCommitTests.swift
//  GitKitTests
//
//  Tests for committing a chosen set of paths without disturbing the rest of the index.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Committing a chosen set of paths: the rest of the index — including a partial staging of a
/// file that was not chosen — stays as it was; hooks and git's own refusals come through.
final class GitCommitTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitcommit")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    private func entries(_ paths: String...) -> [GitStatusEntry] {
        Git.statusEntries(repoRoot: repo.root).filter { paths.contains($0.path) }
    }

    private func committed(_ sha: String = "HEAD") -> [String] {
        (repo.git(["show", "--name-status", "--format=", sha]) ?? "").split(separator: "\n").map(String.init)
    }

    /// `shared.txt` has one hunk staged (line 1) and one not (line 30); `ticked.txt` is edited.
    /// Committing only `ticked.txt` must leave that half-staging exactly as it was.
    func testPartialStagingOfAnUntickedFileSurvives() throws {
        let lines = (1...30).map { "line \($0)" }
        try repo.write(lines.joined(separator: "\n") + "\n", to: "shared.txt")
        try repo.write("ticked\n", to: "ticked.txt")
        repo.commitAll("seed")
        var staged = lines
        staged[0] = "line 1 STAGED"
        try repo.write(staged.joined(separator: "\n") + "\n", to: "shared.txt")
        repo.git(["add", "--", "shared.txt"])
        var both = staged
        both[29] = "line 30 UNSTAGED"
        try repo.write(both.joined(separator: "\n") + "\n", to: "shared.txt")
        try repo.write("ticked edited\n", to: "ticked.txt")
        let stagedBefore = repo.git(["diff", "--cached"])
        XCTAssertEqual(repo.porcelain().sorted(), ["MM shared.txt", " M ticked.txt"].sorted(), "the fixture must be half-staged")

        let result = Git.commit(entries: entries("ticked.txt"), message: "only ticked", repoRoot: repo.root)
        XCTAssertEqual(result, .success(repo.head()))
        XCTAssertEqual(committed(), ["M\tticked.txt"])
        XCTAssertEqual(repo.git(["diff", "--cached"]), stagedBefore, "the staged hunk of shared.txt is untouched")
        XCTAssertEqual(repo.porcelain(), ["MM shared.txt"])
    }

    /// A chosen file is committed as it is on disk, staged part and unstaged part together.
    func testATickedFileIsCommittedWhole() throws {
        try repo.write("a\nb\n", to: "f.txt")
        repo.commitAll("seed")
        try repo.write("A\nb\n", to: "f.txt")
        repo.git(["add", "--", "f.txt"])
        try repo.write("A\nB\n", to: "f.txt")
        XCTAssertEqual(repo.porcelain(), ["MM f.txt"])
        XCTAssertNotNil(try Git.commit(entries: entries("f.txt"), message: "whole", repoRoot: repo.root).get())
        XCTAssertEqual(repo.git(["show", "HEAD:f.txt"]), "A\nB\n")
        XCTAssertEqual(repo.porcelain(), [])
    }

    func testARenameIsRecordedAsARename() throws {
        try repo.write("stable contents that git can match on rename\n", to: "old.txt")
        repo.commitAll("seed")
        repo.git(["mv", "old.txt", "new.txt"])
        XCTAssertNotNil(try Git.commit(entries: entries("new.txt"), message: "move", repoRoot: repo.root).get())
        XCTAssertEqual(committed(), ["R100\told.txt\tnew.txt"])
        XCTAssertEqual(repo.porcelain(), [])
    }

    func testADeletionIsRecorded() throws {
        try repo.write("gone\n", to: "gone.txt")
        try repo.write("stay\n", to: "stay.txt")
        repo.commitAll("seed")
        try repo.delete("gone.txt")
        XCTAssertNotNil(try Git.commit(entries: entries("gone.txt"), message: "remove", repoRoot: repo.root).get())
        XCTAssertEqual(committed(), ["D\tgone.txt"])
        XCTAssertEqual(repo.porcelain(), [])
    }

    func testAMessageWithNewlinesIsKept() throws {
        try repo.write("x\n", to: "f.txt")
        repo.commitAll("seed")
        try repo.write("y\n", to: "f.txt")
        XCTAssertNotNil(
            try Git.commit(entries: entries("f.txt"), message: "Subject line\n\nBody, second paragraph.", repoRoot: repo.root).get())
        XCTAssertEqual(
            repo.git(["log", "-1", "--format=%B"])?.trimmingCharacters(in: .whitespacesAndNewlines),
            "Subject line\n\nBody, second paragraph.")
    }

    func testTheFirstCommitOfARepositoryWorks() throws {
        try repo.write("first\n", to: "a.txt")
        try repo.write("second\n", to: "b.txt")
        let result = Git.commit(entries: entries("a.txt"), message: "first", repoRoot: repo.root)
        XCTAssertEqual(result, .success(repo.head()))
        XCTAssertEqual(repo.git(["log", "--format=%s"]), "first\n")
        XCTAssertEqual(committed(), ["A\ta.txt"])
        XCTAssertEqual(repo.porcelain(), ["?? b.txt"])
    }

    func testMidMergeIsRefused() throws {
        repo.makeMergeConflict()
        XCTAssertEqual(Git.inProgressOperation(repoRoot: repo.root), .merge, "the fixture must be mid-merge")
        let head = repo.head()
        let result = Git.commit(entries: Git.statusEntries(repoRoot: repo.root), message: "no", repoRoot: repo.root)
        XCTAssertEqual(result, .failure(.operationInProgress(.merge)))
        XCTAssertEqual(repo.head(), head)
        repo.git(["merge", "--abort"])
    }

    func testAFailingPreCommitHookReportsItsOwnWords() throws {
        try repo.write("x\n", to: "f.txt")
        repo.commitAll("seed")
        let hook = repo.url(".git/hooks/pre-commit")
        try "#!/bin/sh\necho 'hook says no'\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        try repo.write("y\n", to: "f.txt")
        let head = repo.head()
        let result = Git.commit(entries: entries("f.txt"), message: "blocked", repoRoot: repo.root)
        guard case .failure(.failed(let stderr)) = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertTrue(stderr.contains("hook says no"), stderr)
        XCTAssertEqual(repo.head(), head)
        XCTAssertEqual(repo.porcelain(), [" M f.txt"], "the real index is untouched by the refused commit")
    }

    func testNothingToCommit() throws {
        try repo.write("x\n", to: "f.txt")
        repo.commitAll("seed")
        XCTAssertEqual(Git.commit(entries: [], message: "empty", repoRoot: repo.root), .failure(.nothingToCommit))
        let unchanged = [GitStatusEntry(path: "f.txt", kind: .modified)]
        XCTAssertEqual(Git.commit(entries: unchanged, message: "same", repoRoot: repo.root), .failure(.nothingToCommit))
    }

    /// A nested repository is one status entry, `nested/`; committing it would record a gitlink.
    func testADirectoryIsRefusedWithAMessage() throws {
        try repo.write("x\n", to: "f.txt")
        repo.commitAll("seed")
        let nested = repo.url("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertNotNil(Git.run(["init", "-q"], in: nested))
        try repo.write("n\n", to: "nested/n.txt")
        _ = Git.run(["add", "-A"], in: nested)
        _ = Git.run(["commit", "-q", "-m", "n"], in: nested)
        let result = Git.commit(entries: Git.statusEntries(repoRoot: repo.root), message: "nested", repoRoot: repo.root)
        guard case .failure(.failed(let stderr)) = result else { return XCTFail("expected .failed, got \(result)") }
        XCTAssertTrue(stderr.contains("directory"), stderr)
        XCTAssertEqual(repo.git(["ls-files", "-s", "--", "nested"]), "", "no gitlink was recorded")
    }
}
