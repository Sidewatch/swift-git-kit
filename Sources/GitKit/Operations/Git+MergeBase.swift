//
//  Git+MergeBase.swift
//  GitKit
//
//  Where the current branch left its base — the anchor for "everything this branch changed".
//
//  Created by David Sherlock on 7/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Where the current branch diverged from its base.
public extension Git {

    /// The commit where the current branch diverged from `base`.
    ///
    /// - Parameters:
    ///   - base: The ref to compare against.
    ///   - repoRoot: The repository.
    /// - Returns: The merge-base commit, or `nil` when the refs share no history.
    static func mergeBase(with base: String, repoRoot: URL) -> String? {
        guard let out = run(["merge-base", "HEAD", base], in: repoRoot)?
            .trimmed, !out.isEmpty else { return nil }
        return out
    }

    /// The commit the current branch forked from its integration branch, or nil when none exists.
    ///
    /// Tries `origin/HEAD`, then `main`, then `master`: the remote's default comes first because
    /// a repo can carry a stale local `main` alongside a remote default of something else.
    static func defaultBranchMergeBase(repoRoot: URL) -> String? {
        for candidate in ["origin/HEAD", "main", "master"] {
            // Skip a candidate that doesn't resolve, or merge-base would report the failure
            // as "no shared history" and stop the search early.
            guard run(["rev-parse", "--verify", "--quiet", candidate], in: repoRoot) != nil,
                  let base = mergeBase(with: candidate, repoRoot: repoRoot) else { continue }
            // On the integration branch itself the merge-base is HEAD, so the branch scope
            // would show nothing. That's the honest answer — there is no branch work yet.
            return base
        }
        return nil
    }
}
