//
//  GitHostileConfigTests.swift
//  GitKitTests
//
//  Tests that a user's diff, log, colour and blame configuration cannot change what the
//  package reads: every read API answers the same under a hostile global gitconfig as under none.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Every public read API answers the same under a hostile global gitconfig (external diff, no
/// prefixes, mnemonic prefixes, fused hunks, colour always, a missing ignore-revs file, log
/// signatures) plus a textconv driver in the repository as it does under a clean one.
final class GitHostileConfigTests: XCTestCase {

    private var repo: ScratchRepo!
    private var hostileConfig: URL!
    private var savedGlobal: String?
    private var checkpoint = ""
    private var head = ""
    private var indexDate: Date?

    /// What every read API returns, gathered under whichever configuration is in force.
    private struct Snapshot: Equatable {
        var status: [GitStatusEntry]
        var marks: [Int: GitChangeKind]
        var removed: [Int: [String]]
        var allMarks: [String: [Int: GitChangeKind]]
        var stat: (Int, Int)
        var blame: BlameInfo?
        var log: [GitCommit]
        var fileLog: [GitCommit]
        var show: String?
        var showFile: String?
        var liveDiff: String?
        var rangeDiff: String?
        var changed: [String]
        var worktrees: [GitWorktree]
        var branch: String?
        var branches: [String]
        var untracked: String

        static func == (a: Snapshot, b: Snapshot) -> Bool {
            a.status == b.status && a.marks == b.marks && a.removed == b.removed && a.allMarks == b.allMarks
                && a.stat == b.stat && a.blame == b.blame && a.log == b.log && a.fileLog == b.fileLog && a.show == b.show
                && a.showFile == b.showFile && a.liveDiff == b.liveDiff && a.rangeDiff == b.rangeDiff
                && a.changed == b.changed && a.worktrees == b.worktrees && a.branch == b.branch
                && a.branches == b.branches && a.untracked == b.untracked
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedGlobal = ProcessInfo.processInfo.environment["GIT_CONFIG_GLOBAL"]
        repo = try ScratchRepo(label: "githostile")
        hostileConfig = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hostile-\(UUID().uuidString).gitconfig")
        try """
        [diff]
        \texternal = /bin/echo
        \tnoprefix = true
        \tmnemonicPrefix = true
        \tinterHunkContext = 5
        [color]
        \tui = always
        [blame]
        \tignoreRevsFile = .missing
        [log]
        \tshowSignature = true
        """.write(to: hostileConfig, atomically: true, encoding: .utf8)

        // A textconv driver in the repository itself: it would upper-case the blob side of every
        // diff of a .txt file, shifting and rewriting every hunk.
        try repo.write("*.txt diff=shout\n", to: ".gitattributes")
        repo.git(["config", "diff.shout.textconv", "tr a-z A-Z <"])
        try repo.write("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n", to: "my file.txt")
        try repo.write("keep\n", to: "other.txt")
        repo.commitAll("seed")
        checkpoint = try XCTUnwrap(Git.createCheckpoint(repoRoot: repo.root))
        // Two hunks 6 lines apart (fused by interHunkContext=5): line 1 replaced, lines 9-10
        // replaced by one line; plus an untracked file.
        try repo.write("A\nb\nc\nd\ne\nf\ng\nh\nI\n", to: "my file.txt")
        try repo.write("brand new\n", to: "fresh.txt")
        head = repo.head()
        indexDate =
            try FileManager.default.attributesOfItem(atPath: repo.root.appendingPathComponent(".git/index").path)[.modificationDate]
            as? Date
    }

    override func tearDown() {
        if let savedGlobal { setenv("GIT_CONFIG_GLOBAL", savedGlobal, 1) } else { unsetenv("GIT_CONFIG_GLOBAL") }
        try? FileManager.default.removeItem(at: hostileConfig)
        repo.cleanup()
        super.tearDown()
    }

    private func snapshot() -> Snapshot {
        let file = repo.url("my file.txt")
        let diff = Git.lineDiff(for: file, repoRoot: repo.root)
        return Snapshot(
            status: Git.statusEntries(repoRoot: repo.root),
            marks: diff.marks, removed: diff.removed,
            allMarks: Git.lineChangesAll(repoRoot: repo.root),
            stat: Git.diffStat(repoRoot: repo.root),
            blame: Git.blame(for: file, line: 2, repoRoot: repo.root),
            log: Git.log(repoRoot: repo.root),
            fileLog: Git.fileLog(path: "my file.txt", repoRoot: repo.root),
            show: Git.showCommit(head, repoRoot: repo.root),
            showFile: Git.showFile(revision: "HEAD", path: "my file.txt", repoRoot: repo.root),
            liveDiff: Git.checkpointDiff(from: checkpoint, to: nil, repoRoot: repo.root),
            rangeDiff: Git.checkpointDiff(from: checkpoint, to: head, repoRoot: repo.root),
            changed: Git.checkpointChangedFiles(from: checkpoint, to: nil, repoRoot: repo.root).map(\.path),
            worktrees: Git.worktrees(repoRoot: repo.root),
            branch: Git.currentBranch(repoRoot: repo.root),
            branches: Git.localBranches(repoRoot: repo.root).map(\.name),
            untracked: Git.untrackedDiff(for: repo.url("fresh.txt"), repoRoot: repo.root))
    }

    func testEveryReadAnswersTheSameUnderAHostileGlobalConfig() throws {
        setenv("GIT_CONFIG_GLOBAL", hostileConfig.path, 1)
        let hostile = snapshot()
        setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
        let clean = snapshot()
        XCTAssertEqual(hostile, clean)

        // And the clean answers are the real ones, not two empty results agreeing.
        XCTAssertEqual(clean.marks, [1: .modified, 9: .modified], "two hunks, not one fused by interHunkContext")
        XCTAssertEqual(clean.removed, [1: ["a"], 9: ["i", "j"]])
        XCTAssertEqual(clean.allMarks["my file.txt"], clean.marks, "the `--- a/my file.txt<TAB>` header names the file")
        XCTAssertTrue(clean.stat == (2, 3), "\(clean.stat)")
        XCTAssertEqual(clean.blame?.summary, "seed")
        XCTAssertEqual(clean.log.map(\.subject), ["seed"])
        XCTAssertEqual(clean.showFile, "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
        XCTAssertTrue(clean.show?.contains("+a\n") ?? false, "a real patch, lower case")
        XCTAssertTrue(clean.liveDiff?.contains("--- a/my file.txt") ?? false, clean.liveDiff ?? "nil")
        XCTAssertTrue(clean.liveDiff?.contains("+++ b/fresh.txt") ?? false, "the untracked file appears as new content")
        XCTAssertEqual(clean.rangeDiff, "", "the checkpoint and HEAD hold the same tree")
        XCTAssertEqual(Set(clean.changed), ["my file.txt", "fresh.txt"])
        XCTAssertEqual(clean.worktrees.count, 1)
        XCTAssertEqual(clean.branch, repo.branch())
        XCTAssertEqual(clean.branches, [repo.branch()])
        XCTAssertTrue(clean.untracked.hasPrefix("diff --git a/fresh.txt b/fresh.txt"), clean.untracked)
    }

    /// Both snapshots read the repository many times, with `diff.autoRefreshIndex` left at its
    /// default in both configurations; none of it may write the index.
    func testReadsLeaveTheIndexUntouchedWhateverTheConfig() throws {
        setenv("GIT_CONFIG_GLOBAL", hostileConfig.path, 1)
        _ = snapshot()
        setenv("GIT_CONFIG_GLOBAL", "/dev/null", 1)
        _ = snapshot()
        let after =
            try FileManager.default.attributesOfItem(atPath: repo.root.appendingPathComponent(".git/index").path)[.modificationDate]
            as? Date
        XCTAssertEqual(after, indexDate)
    }
}
