//
//  GitCheckpointIndexTests.swift
//  GitKitTests
//
//  Tests for the index a checkpoint is captured and diffed through: a scratch copy of the real
//  one, never the real one itself.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// The index a checkpoint is captured and diffed through: a scratch copy of the real one, with
/// untracked files as intent-to-add for the working-tree diff, never the real index itself.
final class GitCheckpointIndexTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitckptindex")
        try repo.write("orig\n", to: "tracked.txt")
        repo.commitAll("base")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    private func changed(from: String) -> [String: GitChangeKind] {
        Dictionary(uniqueKeysWithValues: Git.checkpointChangedFiles(from: from, to: nil, repoRoot: repo.root).map { ($0.path, $0.kind) })
    }

    /// An untracked file that existed BEFORE the checkpoint is in the checkpoint's tree but not
    /// in the real index; a `git diff <checkpoint>` against the real index read it as `D` and the
    /// untracked splice re-added it as `A`. Untouched, it is not a change at all. A file staged
    /// after the checkpoint is a change, and so is a tracked edit.
    func testWorkingTreeDiffIgnoresAnUntouchedPreexistingUntrackedFileAndSeesStagedAndTrackedEdits() throws {
        try repo.write("already here\n", to: "brandnew.txt")
        let checkpoint = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        try repo.write("staged\n", to: "stagednew.txt")
        repo.git(["add", "--", "stagednew.txt"])
        try repo.write("edited\n", to: "tracked.txt")

        XCTAssertEqual(changed(from: checkpoint), ["stagednew.txt": .added, "tracked.txt": .modified])
        let diff = try XCTUnwrap(Git.checkpointDiff(from: checkpoint, to: nil, repoRoot: repo.root))
        XCTAssertFalse(diff.contains("brandnew"), diff)
        XCTAssertTrue(diff.contains("+staged\n"), "a staged new file is in the working tree")
        XCTAssertTrue(diff.contains("+edited\n"))
        XCTAssertFalse(diff.contains("deleted file"), diff)
        XCTAssertEqual(
            repo.porcelain().sorted(), ["A  stagednew.txt", " M tracked.txt", "?? brandnew.txt"].sorted(), "the real index is untouched")
    }

    func testWorkingTreeDiffReportsAnEditToAPreexistingUntrackedFile() throws {
        try repo.write("v1\n", to: "loose.txt")
        let checkpoint = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        try repo.write("v2\n", to: "loose.txt")
        XCTAssertEqual(changed(from: checkpoint), ["loose.txt": .modified])
        XCTAssertTrue(Git.checkpointDiff(from: checkpoint, to: nil, repoRoot: repo.root)?.contains("-v1\n+v2\n") ?? false)
    }

    /// `git add -A` exits 128 on one file it cannot read, or on a nested repository that has no
    /// commit yet, and the whole capture came back nil.
    func testCaptureSurvivesAnUnreadableFileAndACommitlessNestedRepo() throws {
        try repo.write("secret\n", to: "secret.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: repo.url("secret.txt").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: repo.url("secret.txt").path) }
        let nested = repo.url("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertNotNil(Git.run(["init", "-q"], in: nested))
        try repo.write("n\n", to: "nested/n.txt")
        try repo.write("edited\n", to: "tracked.txt")

        let checkpoint = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        let paths = Set(Git.checkpointChangedFiles(from: "HEAD", to: checkpoint, repoRoot: repo.root).map(\.path))
        XCTAssertEqual(paths, ["tracked.txt"], "the edit is captured; the unreadable file and the nested repo are left out")
        // The working-tree diff copes with the same tree.
        XCTAssertEqual(changed(from: "HEAD"), ["tracked.txt": .modified])
    }

    /// Captured from a copy of the real index: a half-staged file is captured as it is on disk
    /// and the real index keeps its staged hunk; an index with unmerged entries captures too.
    func testCaptureLeavesPartialStagingAloneAndWorksOnAConflictedIndex() throws {
        try repo.write("staged\n", to: "tracked.txt")
        repo.git(["add", "--", "tracked.txt"])
        try repo.write("staged\nand more\n", to: "tracked.txt")
        let stagedBefore = repo.git(["diff", "--cached"])
        let first = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        XCTAssertEqual(repo.git(["show", "\(first):tracked.txt"]), "staged\nand more\n")
        XCTAssertEqual(repo.git(["diff", "--cached"]), stagedBefore)

        repo.git(["checkout", "-q", "--", "tracked.txt"])
        repo.git(["reset", "-q", "--hard"])
        repo.makeMergeConflict()
        XCTAssertEqual(repo.porcelain(), ["UU conflict.txt"], "the fixture must be conflicted")
        let second = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root), "a conflicted index must still capture")
        XCTAssertTrue(repo.git(["show", "\(second):conflict.txt"])?.contains("<<<<<<<") ?? false, "captured as it stands on disk")
        XCTAssertEqual(repo.porcelain(), ["UU conflict.txt"], "and the real index is still conflicted")
        XCTAssertEqual(changed(from: second), [:], "nothing changed since the capture")
        repo.git(["merge", "--abort"])
    }

    /// Without `-z`, a path with a `"` or `\` comes back C-quoted (`"we\"ird\\name.txt"`), which
    /// no caller can open.
    func testChangedFilesKeepQuotableNamesVerbatimAndReportRenamesUnderTheNewPath() throws {
        let first = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        try repo.write("x\n", to: "we\"ird\\name.txt")
        let second = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        XCTAssertEqual(
            Git.checkpointChangedFiles(from: first, to: second, repoRoot: repo.root).map { "\($0.kind.letter) \($0.path)" },
            ["A we\"ird\\name.txt"])
        XCTAssertEqual(changed(from: first), ["we\"ird\\name.txt": .added])

        repo.git(["mv", "tracked.txt", "moved \"quoted\".txt"])
        let third = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        let renamed = Git.checkpointChangedFiles(from: second, to: third, repoRoot: repo.root)
        XCTAssertEqual(renamed.map { "\($0.kind.letter) \($0.path)" }, ["R moved \"quoted\".txt"])
    }
}
