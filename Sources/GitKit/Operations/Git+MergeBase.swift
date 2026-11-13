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
        guard
            let out = run(["merge-base", "HEAD", base], in: repoRoot)?
                .trimmed, !out.isEmpty
        else { return nil }
        return out
    }

    /// The base a branch's work is measured from: `preferred` when it is given and resolves (a pull
    /// request's base branch, a choice the person made), else the first of the integration
    /// branches that does. Nil when nothing resolves or the branch shares no history with it.
    ///
    /// `preferred` is tried as written and then on each remote (`release/2.0`, then
    /// `origin/release/2.0`): a pull request names its base without the remote, and a checkout
    /// often has that branch only as the remote's.
    static func branchBase(repoRoot: URL, preferred: String? = nil) -> GitBranchBase? {
        var candidates: [String] = []
        if let preferred, !preferred.isEmpty {
            candidates.append(preferred)
            candidates += remotes(repoRoot: repoRoot).map { $0 + "/" + preferred }
        }
        candidates += ["origin/HEAD", "main", "master"]
        for candidate in candidates {
            // Skip a candidate that doesn't resolve, or merge-base would report the failure
            // as "no shared history" and stop the search early.
            guard run(["rev-parse", "--verify", "--quiet", candidate + "^{commit}"], in: repoRoot) != nil,
                let commit = mergeBase(with: candidate, repoRoot: repoRoot)
            else { continue }
            return GitBranchBase(ref: candidate, commit: commit)
        }
        return nil
    }

    /// The branches a branch could be compared against: the remote's branches, then local ones,
    /// each list in name order, without the branch checked out and without a remote's `HEAD` alias.
    static func baseCandidates(repoRoot: URL) -> [String] {
        let current = currentBranch(repoRoot: repoRoot)
        func refs(_ namespace: String) -> [String] {
            (run(["for-each-ref", "--format=%(refname:short)", "--sort=refname", namespace], in: repoRoot) ?? "")
                .components(separatedBy: "\n").map(\.trimmed).filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") && $0 != current }
        }
        // A remote's own name alone (`origin`) is how git prints its HEAD alias in short form.
        let remoteNames = Set(remotes(repoRoot: repoRoot))
        return refs("refs/remotes").filter { !remoteNames.contains($0) } + refs("refs/heads")
    }

    /// The names of the repository's remotes.
    static func remotes(repoRoot: URL) -> [String] {
        (run(["remote"], in: repoRoot) ?? "").components(separatedBy: "\n").map(\.trimmed).filter { !$0.isEmpty }
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
                let base = mergeBase(with: candidate, repoRoot: repoRoot)
            else { continue }
            // On the integration branch itself the merge-base is HEAD, so the branch scope
            // would show nothing. That's the honest answer — there is no branch work yet.
            return base
        }
        return nil
    }
}
