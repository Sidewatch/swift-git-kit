//
//  Git+Info.swift
//  GitKit
//
//  Local branches, each flagged if it's the checked-out one. `%(HEAD)` is a single leading char
//  — `*` for the current branch, a space otherwise.
//
//  Created by David Sherlock on 7/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Branches, remotes, upstream tracking, fetch and checkout.
public extension Git {

    // `currentBranch(repoRoot:)` lives in Git+Worktree.

    /// Local branches (`refs/heads`), each flagged if it's the checked-out one. None is current on
    /// a detached `HEAD` or mid-rebase — `git branch` would list a `(no branch, rebasing x)`
    /// pseudo-entry there, which is not a branch.
    static func localBranches(repoRoot root: URL) -> [(name: String, isCurrent: Bool)] {
        guard let out = run(["for-each-ref", "--format=%(refname:short)", "refs/heads"], in: root) else { return [] }
        let current = run(["symbolic-ref", "-q", "--short", "HEAD"], in: root)?.trimmed
        return out.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let name = String(line)
            return (name, name == current)
        }
    }

    /// Commits `HEAD` is ahead of / behind `ref` (default the upstream, `@{u}`). Returns
    /// `(0, 0)` when there's no upstream or the ref is unknown.
    static func aheadBehind(repoRoot root: URL, ref: String = "@{u}") -> (ahead: Int, behind: Int) {
        guard let out = run(["rev-list", "--left-right", "--count", "HEAD...\(ref)"], in: root) else { return (0, 0) }
        let parts = out.trimmed
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) else { return (0, 0) }
        return (ahead, behind)
    }

    /// True when the working tree AND index are clean (nothing to commit).
    static func isClean(repoRoot root: URL) -> Bool {
        (run(["status", "--porcelain"], in: root) ?? "")
            .trimmed.isEmpty
    }

    // MARK: - Write / network (off-main; git's stderr is discarded, so these report only success)

    /// Fetches refs from `remote` (default `origin`). Network-bound — call off the main thread.
    @discardableResult
    static func fetch(repoRoot root: URL, remote: String = "origin") -> Bool {
        run(["fetch", remote], in: root, timeout: longTimeout) != nil
    }

    /// Switches the working tree to `branch`. Returns whether it succeeded.
    @discardableResult
    static func checkout(_ branch: String, repoRoot root: URL) -> Bool {
        run(["checkout", branch], in: root, timeout: longTimeout) != nil
    }
}
