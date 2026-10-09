//
//  GitStatusEntryTests.swift
//  GitKitTests
//
//  Tests for every porcelain status code the package maps, each produced by a real repository.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Every porcelain `XY` code mapped to a kind, each produced by a real repository state.
final class GitStatusEntryTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitstatus")
        try repo.write("seed\n", to: "seed.txt")
        repo.commitAll("seed")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    private func entry(_ path: String) -> GitStatusEntry? {
        Git.statusEntries(repoRoot: repo.root).first { $0.path == path }
    }

    func testPlainCodes() throws {
        try repo.write("gone\n", to: "gone.txt")
        try repo.write("rm\n", to: "rm.txt")
        repo.commitAll("two more")
        try repo.write("new\n", to: "untracked.txt")  // ??
        try repo.write("new\n", to: "added.txt")  // A
        repo.git(["add", "--", "added.txt"])
        try repo.write("seed\nmore\n", to: "seed.txt")  // ' M'
        try repo.delete("gone.txt")  // ' D'
        repo.git(["rm", "-q", "--", "rm.txt"])  // 'D '
        XCTAssertEqual(entry("untracked.txt")?.kind, .untracked)
        XCTAssertEqual(entry("added.txt")?.kind, .added)
        XCTAssertEqual(entry("seed.txt")?.kind, .modified)
        XCTAssertEqual(entry("gone.txt")?.kind, .deleted)
        XCTAssertEqual(entry("rm.txt")?.kind, .deleted)
    }

    /// `AD`: added to the index, then deleted from the working tree. The index side says added;
    /// the file is gone, so it is a deletion.
    func testAddedThenDeletedFromTheWorkingTreeIsDeleted() throws {
        try repo.write("short-lived\n", to: "ad.txt")
        repo.git(["add", "--", "ad.txt"])
        try repo.delete("ad.txt")
        XCTAssertEqual(repo.porcelain(), ["AD ad.txt"], "the fixture must be AD")
        XCTAssertEqual(entry("ad.txt")?.kind, .deleted)
    }

    /// `MD`: a staged edit, then the file removed.
    func testModifiedThenDeletedFromTheWorkingTreeIsDeleted() throws {
        try repo.write("seed\nedited\n", to: "seed.txt")
        repo.git(["add", "--", "seed.txt"])
        try repo.delete("seed.txt")
        XCTAssertEqual(repo.porcelain(), ["MD seed.txt"], "the fixture must be MD")
        XCTAssertEqual(entry("seed.txt")?.kind, .deleted)
    }

    func testRenameCarriesItsOldPath() throws {
        repo.git(["mv", "seed.txt", "moved.txt"])
        let moved = try XCTUnwrap(entry("moved.txt"))
        XCTAssertEqual(moved.kind, .renamed)
        XCTAssertEqual(moved.oldPath, "seed.txt")
        XCTAssertNil(entry("seed.txt"), "the old path is not an entry of its own")
        XCTAssertEqual(Git.status(repoRoot: repo.root).map { "\($0.kind.letter) \($0.path)" }, ["R moved.txt"])
    }

    /// `UU`, `AA` and `UD` from one merge: edited both sides, added both sides, deleted one side.
    func testMergeConflictCodesAreConflicted() throws {
        let main = repo.branch()
        try repo.write("deleted on theirs\n", to: "ud.txt")
        repo.commitAll("base")
        repo.git(["checkout", "-q", "-b", "theirs"])
        try repo.write("theirs\n", to: "seed.txt")
        try repo.write("theirs\n", to: "aa.txt")
        repo.git(["rm", "-q", "--", "ud.txt"])
        repo.commitAll("theirs")
        repo.git(["checkout", "-q", main])
        try repo.write("ours\n", to: "seed.txt")
        try repo.write("ours\n", to: "aa.txt")
        try repo.write("edited on ours\n", to: "ud.txt")
        repo.commitAll("ours")
        _ = Git.run(["merge", "theirs"], in: repo.root, allowedStatuses: [1])
        XCTAssertEqual(Set(repo.porcelain()), ["UU seed.txt", "AA aa.txt", "UD ud.txt"], "the fixture must conflict three ways")
        XCTAssertEqual(entry("seed.txt")?.kind, .conflicted)
        XCTAssertEqual(entry("aa.txt")?.kind, .conflicted)
        XCTAssertEqual(entry("ud.txt")?.kind, .conflicted, "UD is a conflict, not a deletion")
        XCTAssertEqual(GitChangeKind.conflicted.letter, "C")
        let summary = WorktreeSummary.make(
            worktree: GitWorktree(path: repo.root, branch: main, isMain: true), status: Git.status(repoRoot: repo.root))
        XCTAssertEqual(summary.conflicted, 3)
        XCTAssertEqual(summary.changeCount, 3)
    }

    /// `DD`: deleted on both sides with the file then re-added on disk; a conflict, not a deletion.
    func testDeletedBothSidesIsConflicted() throws {
        let main = repo.branch()
        repo.git(["checkout", "-q", "-b", "theirs"])
        repo.git(["rm", "-q", "--", "seed.txt"])
        try repo.write("theirs\n", to: "seed.txt")
        repo.git(["add", "--", "seed.txt"])
        repo.commitAll("theirs rewrite")
        repo.git(["checkout", "-q", main])
        repo.git(["rm", "-q", "--", "seed.txt"])
        repo.commitAll("ours delete")
        _ = Git.run(["merge", "theirs"], in: repo.root, allowedStatuses: [1])
        // Delete/modify: git reports `DU`.
        XCTAssertEqual(repo.porcelain(), ["DU seed.txt"], "the fixture must be a delete/modify conflict")
        XCTAssertEqual(entry("seed.txt")?.kind, .conflicted)
    }

    /// A nested repository with commits added as a gitlink: a pointer bump is ` M sub` (no slash),
    /// an ordinary modification of one entry.
    func testASubmodulePointerBumpIsModified() throws {
        let sub = try ScratchRepo(label: "gitstatus-sub")
        defer { sub.cleanup() }
        try sub.write("s\n", to: "s.txt")
        sub.commitAll("sub seed")
        XCTAssertNotNil(repo.git(["-c", "protocol.file.allow=always", "submodule", "add", "-q", sub.root.path, "sub"]))
        repo.commitAll("add sub")
        let inner = try XCTUnwrap(Git.repoRoot(for: repo.url("sub")))
        try "s2\n".write(to: inner.appendingPathComponent("s.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["add", "-A"], in: inner)
        _ = Git.run(["commit", "-q", "-m", "bump"], in: inner)
        XCTAssertEqual(repo.porcelain(), [" M sub"], "the fixture must be a pointer bump")
        XCTAssertEqual(entry("sub")?.kind, .modified)
        XCTAssertTrue(Git.isGitlink(repo.url("sub"), repoRoot: repo.root))
        XCTAssertFalse(Git.isGitlink(repo.url("seed.txt"), repoRoot: repo.root))
    }

    func testANestedRepositoryWithoutAGitlinkIsOneUntrackedEntry() throws {
        let nested = repo.url("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertNotNil(Git.run(["init", "-q"], in: nested))
        try repo.write("n\n", to: "nested/n.txt")
        XCTAssertEqual(Git.statusEntries(repoRoot: repo.root), [GitStatusEntry(path: "nested/", kind: .untracked)])
    }
}
