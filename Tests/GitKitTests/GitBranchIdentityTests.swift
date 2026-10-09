//
//  GitBranchIdentityTests.swift
//  GitKitTests
//
//  Tests for branch listing and worktree enumeration in the states where git invents entries:
//  detached, mid-rebase, and a worktree whose directory is gone.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Branch listing and worktree enumeration where git invents entries: detached, mid-rebase, and
/// a worktree whose directory is gone.
final class GitBranchIdentityTests: XCTestCase {

    private var repo: ScratchRepo!
    private var scratchDirs: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitbranches")
        try repo.write("x\n", to: "f.txt")
        repo.commitAll("seed")
    }

    override func tearDown() {
        repo.cleanup()
        scratchDirs.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    /// `git branch` lists `(HEAD detached at abc123)` as if it were a branch.
    func testLocalBranchesOnADetachedHeadListNoPseudoEntryAndNoCurrent() {
        repo.git(["checkout", "-q", "--detach", "HEAD"])
        let branches = Git.localBranches(repoRoot: repo.root)
        XCTAssertEqual(branches.map(\.name), [repo.branchAtSeed])
        XCTAssertTrue(branches.allSatisfy { !$0.isCurrent })
    }

    /// Mid-rebase, `git branch` lists `(no branch, rebasing rb)`.
    func testLocalBranchesMidRebaseListOnlyRealBranches() throws {
        let main = repo.branch()
        repo.git(["checkout", "-q", "-b", "rb"])
        try repo.write("rb\n", to: "f.txt")
        repo.commitAll("rb")
        repo.git(["checkout", "-q", main])
        try repo.write("main\n", to: "f.txt")
        repo.commitAll("main")
        repo.git(["checkout", "-q", "rb"])
        _ = Git.run(["rebase", main], in: repo.root, allowedStatuses: [1, 128])
        XCTAssertEqual(Git.inProgressOperation(repoRoot: repo.root), .rebase, "the fixture must be mid-rebase")
        let names = Git.localBranches(repoRoot: repo.root).map(\.name)
        XCTAssertEqual(Set(names), [main, "rb"])
        XCTAssertFalse(names.contains { $0.contains("(") }, "\(names)")
        repo.git(["rebase", "--abort"])
    }

    func testLocalBranchesFlagTheCheckedOutBranch() {
        repo.git(["branch", "feature"])
        let branches = Git.localBranches(repoRoot: repo.root)
        XCTAssertEqual(branches.filter(\.isCurrent).map(\.name), [repo.branch()])
        XCTAssertEqual(branches.first { $0.name == "feature" }?.isCurrent, false)
    }

    /// `worktree list --porcelain` keeps listing a worktree whose directory was deleted, marked
    /// `prunable`; it is not somewhere a review can happen.
    func testWorktreesSkipPrunableEntries() throws {
        let linked = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gitwt-prunable-\(UUID().uuidString)")
        scratchDirs.append(linked)
        XCTAssertNotNil(repo.git(["worktree", "add", "-q", linked.path, "-b", "wt"]))
        XCTAssertEqual(Git.worktrees(repoRoot: repo.root).count, 2)
        try FileManager.default.removeItem(at: linked)
        let trees = Git.worktrees(repoRoot: repo.root)
        XCTAssertEqual(trees.count, 1)
        XCTAssertTrue(trees[0].isMain)
    }
}

extension ScratchRepo {
    /// The branch `init` created, read back from the one commit's reflog-free truth: `for-each-ref`.
    fileprivate var branchAtSeed: String {
        (git(["for-each-ref", "--format=%(refname:short)", "refs/heads"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
