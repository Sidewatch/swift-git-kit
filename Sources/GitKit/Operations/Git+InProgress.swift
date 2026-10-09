//
//  Git+InProgress.swift
//  GitKit
//
//  Whether a merge, rebase, cherry-pick, revert, bisect or am is under way.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Operations git has left half-done in the repository.
public extension Git {

    /// The multi-step operation under way at `root`, or nil when there is none — from the state
    /// files git keeps in its directory (`MERGE_HEAD`, `rebase-merge/`, …; for a linked worktree,
    /// that worktree's own directory under the common dir).
    static func inProgressOperation(repoRoot root: URL) -> GitOperation? {
        guard let gitDir = absoluteGitDir(repoRoot: root) else { return nil }
        func present(_ name: String) -> Bool { FileManager.default.fileExists(atPath: gitDir.appendingPathComponent(name).path) }
        if present("rebase-merge") { return .rebase }
        if present("rebase-apply") { return present("rebase-apply/applying") ? .am : .rebase }
        if present("MERGE_HEAD") { return .merge }
        if present("CHERRY_PICK_HEAD") { return .cherryPick }
        if present("REVERT_HEAD") { return .revert }
        if present("BISECT_LOG") { return .bisect }
        return nil
    }

    /// The short name of the branch being rebased (`rebase-merge/head-name`, or
    /// `rebase-apply/head-name`), for "rebasing <branch>"; nil when no rebase is under way or it
    /// started from a detached `HEAD`.
    static func rebaseHeadName(repoRoot root: URL) -> String? {
        guard let gitDir = absoluteGitDir(repoRoot: root) else { return nil }
        for state in ["rebase-merge", "rebase-apply"] {
            let file = gitDir.appendingPathComponent("\(state)/head-name")
            guard let ref = try? String(contentsOf: file, encoding: .utf8).trimmed, !ref.isEmpty else { continue }
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
        }
        return nil
    }
}

extension Git {

    /// `git rev-parse --absolute-git-dir`: the directory holding this worktree's state files.
    static func absoluteGitDir(repoRoot root: URL) -> URL? {
        guard let out = run(["rev-parse", "--absolute-git-dir"], in: root)?.trimmed, !out.isEmpty else { return nil }
        return URL(fileURLWithPath: out, isDirectory: true)
    }
}
