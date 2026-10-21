//
//  GitBranchStatusTests.swift
//  GitKitTests
//
//  The branch facts in one call: branch, detached HEAD, linked worktrees, and commits that vanish.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// `Git.branchStatus`, `Git.isDetachedHead`, `Git.commitExists` and `GitBranchStatus.isLinkedWorktree`.
final class GitBranchStatusTests: XCTestCase {
    private var repo: ScratchRepo!

    override func setUpWithError() throws { repo = try ScratchRepo(label: "branchstatus") }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: repo.root) }

    func testABranchIsNamedAndADetachedHeadIsSaid() throws {
        try repo.write("a\n", to: "a.txt")
        let first = repo.commitAll("one")
        let onBranch = Git.branchStatus(repoRoot: repo.root)
        XCTAssertEqual(onBranch.branch, repo.branch())
        XCTAssertFalse(onBranch.detached)
        XCTAssertNil(onBranch.operation)
        _ = repo.git(["checkout", "-q", "--detach", first])
        XCTAssertTrue(Git.branchStatus(repoRoot: repo.root).detached)
    }

    func testALinkedWorktreeIsToldFromTheMainCheckout() throws {
        try repo.write("a\n", to: "a.txt")
        repo.commitAll("one")
        let linked = repo.root.deletingLastPathComponent().appendingPathComponent(repo.root.lastPathComponent + "-wt")
        _ = repo.git(["worktree", "add", "-q", "-b", "side", linked.path])
        defer { try? FileManager.default.removeItem(at: linked) }
        let status = Git.branchStatus(repoRoot: repo.root)
        XCTAssertEqual(status.worktrees.count, 2)
        XCTAssertFalse(status.isLinkedWorktree(repo.root), "the main checkout")
        XCTAssertTrue(status.isLinkedWorktree(linked))
        // A linked worktree opened through a symlink is still that worktree.
        let link = repo.root.deletingLastPathComponent().appendingPathComponent(repo.root.lastPathComponent + "-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: linked)
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertTrue(status.isLinkedWorktree(link), "compared canonically, links resolved")
    }

    func testACommitThatIsGoneIsReportedGone() throws {
        try repo.write("a\n", to: "a.txt")
        let sha = repo.commitAll("one")
        XCTAssertTrue(Git.commitExists(sha, repoRoot: repo.root))
        XCTAssertFalse(Git.commitExists(String(repeating: "0", count: 40), repoRoot: repo.root))
        let blob = repo.git(["rev-parse", "HEAD:a.txt"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertFalse(Git.commitExists(blob, repoRoot: repo.root), "a blob is not a commit")
    }
}
