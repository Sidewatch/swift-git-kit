//
//  Git+Worktree.swift
//  GitKit
//
//  Branch identity and worktree enumeration.
//
//  Created by David Sherlock on 7/16/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Branch identity and worktree enumeration.
public extension Git {

    /// The short name of the branch checked out at `root`, the short SHA on a detached `HEAD`,
    /// or `nil` when git fails (e.g. an unborn `HEAD` in a repository with no commits).
    static func currentBranch(repoRoot root: URL) -> String? {
        guard
            let name = run(["rev-parse", "--abbrev-ref", "HEAD"], in: root)?
                .trimmed, !name.isEmpty
        else { return nil }
        guard name == "HEAD" else { return name }
        // Detached HEAD — identify the checkout by its short commit SHA instead.
        guard
            let sha = run(["rev-parse", "--short", "HEAD"], in: root)?
                .trimmed, !sha.isEmpty
        else { return nil }
        return sha
    }

    /// All worktrees of the repository containing `root` (any worktree, main or linked), main
    /// first; `[]` on failure.
    ///
    /// Parses `git worktree list --porcelain`. Branches lose their `refs/heads/` prefix; detached
    /// and bare entries have a `nil` branch. git lists the main worktree first (``GitWorktree/isMain``).
    static func worktrees(repoRoot root: URL) -> [GitWorktree] {
        guard let out = run(["worktree", "list", "--porcelain"], in: root) else { return [] }
        var result: [GitWorktree] = []
        var path: URL?
        var branch: String?
        func flush() {
            if let path {
                result.append(GitWorktree(path: path, branch: branch, isMain: result.isEmpty))
            }
            path = nil
            branch = nil
        }
        for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {  // blank line terminates an entry
                flush()
            } else if line.hasPrefix("worktree ") {
                path = URL(
                    fileURLWithPath: String(line.dropFirst("worktree ".count)),
                    isDirectory: true)
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch =
                    ref.hasPrefix("refs/heads/")
                    ? String(ref.dropFirst("refs/heads/".count))
                    : ref
            }
            // "HEAD", "detached", "bare", "locked", "prunable" need no handling:
            // detached/bare entries simply never receive a `branch` line.
        }
        flush()  // porcelain output may or may not end with a trailing blank line
        return result
    }

    /// Every worktree of the repository containing `root`, main first, each with a tally of its
    /// uncommitted changes — the data for a parallel-agent review rail.
    ///
    /// Runs `git status` and a diff stat per worktree, so cost scales with their number. Call off-main.
    static func worktreeSummaries(repoRoot root: URL) -> [WorktreeSummary] {
        worktrees(repoRoot: root).map {
            let stat = diffStat(repoRoot: $0.path)
            return WorktreeSummary.make(
                worktree: $0, status: status(repoRoot: $0.path),
                insertions: stat.insertions, deletions: stat.deletions)
        }
    }

    /// Removes a linked worktree and **deletes its directory** (`git worktree remove`); `true` on
    /// success. Refuses a dirty, submodule-bearing or locked worktree, and always the main one.
    ///
    /// `force` passes `--force --force` — git needs the doubled flag to override a lock — and
    /// discards uncommitted changes.
    @discardableResult
    static func removeWorktree(_ worktree: URL, repoRoot root: URL, force: Bool = false) -> Bool {
        var args = ["worktree", "remove"]
        if force { args.append("--force"); args.append("--force") }  // -f -f overrides a lock too
        args.append(worktree.path)
        return run(args, in: root) != nil
    }
}
