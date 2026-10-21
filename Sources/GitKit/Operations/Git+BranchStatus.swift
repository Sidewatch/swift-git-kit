//
//  Git+BranchStatus.swift
//  GitKit
//
//  A checkout's branch facts in one call, and two single-question reads beside them.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension Git {
    /// The branch facts of the checkout at `root` (several `git` runs; call off the main thread).
    static func branchStatus(repoRoot root: URL) -> GitBranchStatus {
        let operation = inProgressOperation(repoRoot: root)
        let sync = aheadBehind(repoRoot: root)
        return GitBranchStatus(
            branch: currentBranch(repoRoot: root), detached: isDetachedHead(repoRoot: root), operation: operation,
            rebasing: operation == .rebase ? rebaseHeadName(repoRoot: root) : nil, ahead: sync.ahead, behind: sync.behind,
            worktrees: worktrees(repoRoot: root))
    }

    /// Whether HEAD at `root` points at a commit rather than a branch (also true outside a repository,
    /// where there is no branch to name).
    static func isDetachedHead(repoRoot root: URL) -> Bool {
        run(["symbolic-ref", "-q", "HEAD"], in: root) == nil
    }

    /// Whether `commit` names a commit that exists in `root` — false once `.git` was recreated or the
    /// folder re-cloned, when something that stored a SHA outlives it.
    static func commitExists(_ commit: String, repoRoot root: URL) -> Bool {
        run(["cat-file", "-e", commit + "^{commit}"], in: root) != nil
    }
}

public extension GitBranchStatus {
    /// Whether `root` is a LINKED worktree of its repository (one `git worktree add` made), not the main
    /// checkout. Paths compare canonically (``GitWorktree/isCurrent(relativeTo:)``), so a worktree opened
    /// through a symlink is still recognised.
    func isLinkedWorktree(_ root: URL) -> Bool {
        worktrees.first { $0.isCurrent(relativeTo: root) }.map { !$0.isMain } ?? false
    }
}
