//
//  GitBranchStatus.swift
//  GitKit
//
//  Everything a branch indicator shows about a checkout, read in one go.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A checkout's branch facts, for a status-bar branch segment: what is checked out, whether HEAD is
/// detached, an operation in progress, how far the branch is from its upstream, and its worktrees.
public struct GitBranchStatus: Sendable, Equatable {
    /// The branch name, or a short SHA on a detached HEAD; nil outside a repository.
    public let branch: String?
    /// Whether HEAD points at a commit rather than a branch.
    public let detached: Bool
    /// The merge, rebase, cherry-pick, revert, bisect or `git am` in progress, if any.
    public let operation: GitOperation?
    /// During a rebase, the branch being rebased.
    public let rebasing: String?
    /// Commits ahead of the upstream.
    public let ahead: Int
    /// Commits behind the upstream.
    public let behind: Int
    /// Every worktree of the repository, the main one included.
    public let worktrees: [GitWorktree]

    /// A status from its parts (for tests and previews; ``Git/branchStatus(repoRoot:)`` reads a real one).
    public init(
        branch: String?, detached: Bool, operation: GitOperation?, rebasing: String?, ahead: Int, behind: Int, worktrees: [GitWorktree]
    ) {
        self.branch = branch
        self.detached = detached
        self.operation = operation
        self.rebasing = rebasing
        self.ahead = ahead
        self.behind = behind
        self.worktrees = worktrees
    }
}
