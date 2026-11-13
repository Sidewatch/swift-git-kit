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
        let remoteNames = remotes(repoRoot: repoRoot)
        /// The first of `refs` that resolves and shares history with `HEAD`.
        func firstBase(among refs: [String]) -> GitBranchBase? {
            for candidate in refs {
                // Skip a candidate that doesn't resolve, or merge-base would report the failure
                // as "no shared history" and stop the search early.
                guard run(["rev-parse", "--verify", "--quiet", candidate + "^{commit}"], in: repoRoot) != nil,
                    let commit = mergeBase(with: candidate, repoRoot: repoRoot)
                else { continue }
                return GitBranchBase(ref: candidate, commit: commit)
            }
            return nil
        }
        var preferredRefs: [String] = []
        if let preferred, !preferred.isEmpty { preferredRefs = [preferred] + remoteNames.map { $0 + "/" + preferred } }
        if let base = firstBase(among: preferredRefs) { return base }
        // The integration branch as the remote names it, then local, then on each remote: a clone of
        // one branch (`--branch topic --depth 1`, a CI checkout) has neither `origin/HEAD` nor a
        // local `main`, only `origin/main` once it is fetched.
        let defaults = ["origin/HEAD", "main", "master"] + remoteNames.flatMap { [$0 + "/main", $0 + "/master"] }
        // With nothing preferred (or a preferred base that is not in this checkout), the branch this
        // one was cut from when that is nearer than the integration branch: a branch stacked on
        // another shows its own work, not its parent's too.
        if let parent = parentBranch(repoRoot: repoRoot, defaults: defaults) { return parent }
        if let base = firstBase(among: defaults) { return base }
        let candidates = preferredRefs + defaults
        // A shallow clone (`--depth 1`, most CI checkouts) may hold no commit the two branches share.
        // The branch is then compared with the tip of the first base that resolves, and says so.
        guard run(["rev-parse", "--is-shallow-repository"], in: repoRoot)?.trimmed == "true" else { return nil }
        for candidate in candidates {
            guard let tip = run(["rev-parse", "--verify", "--quiet", candidate + "^{commit}"], in: repoRoot)?.trimmed, !tip.isEmpty
            else { continue }
            return GitBranchBase(ref: candidate, commit: tip, sharesHistory: false)
        }
        return nil
    }

    /// The most branches ``parentBranch(repoRoot:defaults:)`` weighs: past this a repository's
    /// branches are too many to count commits against one by one on every refresh.
    static let parentBranchCandidateLimit = 40

    /// The branch the current one was cut from, when it is nearer than the integration branch: of
    /// the branches whose tip is an ancestor of `HEAD` (not `HEAD` itself, not this branch or its own
    /// remote copy), the one with the fewest commits between it and `HEAD`, and only if that is
    /// fewer than the commits since the merge base with the first of `defaults` that resolves. So
    /// a branch stacked on `feature-a` is measured from `feature-a`; a branch cut from `main` is
    /// left to the default, as is one whose only ancestors are long-merged branches further back
    /// than `main`. Nothing is kept: a rebase is seen on the next read.
    static func parentBranch(repoRoot: URL, defaults: [String]) -> GitBranchBase? {
        guard let current = currentBranch(repoRoot: repoRoot), !isDetachedHead(repoRoot: repoRoot) else { return nil }
        func commits(since ref: String) -> Int? {
            run(["rev-list", "--count", ref + "..HEAD"], in: repoRoot).flatMap { Int($0.trimmed) }
        }
        // How far the integration branch is: a parent has to be nearer than this.
        var defaultDistance: Int?
        var defaultTip: String?
        for candidate in defaults {
            guard run(["rev-parse", "--verify", "--quiet", candidate + "^{commit}"], in: repoRoot) != nil,
                let base = mergeBase(with: candidate, repoRoot: repoRoot), let distance = commits(since: base)
            else { continue }
            (defaultDistance, defaultTip) = (distance, base)
            break
        }
        let remoteNames = Set(remotes(repoRoot: repoRoot))
        let own = Set([current] + remoteNames.map { $0 + "/" + current })
        let merged =
            (run(
                ["for-each-ref", "--merged", "HEAD", "--format=%(refname:short) %(objectname)", "refs/heads", "refs/remotes"], in: repoRoot)
            ?? "")
            .components(separatedBy: "\n").compactMap { line -> (ref: String, tip: String)? in
                let parts = line.trimmed.split(separator: " ")
                guard parts.count == 2 else { return nil }
                let ref = String(parts[0])
                return own.contains(ref) || ref.hasSuffix("/HEAD") || remoteNames.contains(ref) ? nil : (ref, String(parts[1]))
            }
        guard let head = run(["rev-parse", "HEAD"], in: repoRoot)?.trimmed, merged.count <= parentBranchCandidateLimit else { return nil }
        var best: (ref: String, tip: String, distance: Int)?
        for candidate in merged where candidate.tip != head && candidate.tip != defaultTip {
            guard let distance = commits(since: candidate.tip), distance > 0 else { continue }
            // Nearer wins; at the same distance a local branch before a remote's copy of it.
            if best == nil || distance < best!.distance
                || (distance == best!.distance && !candidate.ref.contains("/") && best!.ref.contains("/"))
            {
                best = (candidate.ref, candidate.tip, distance)
            }
        }
        guard let best, defaultDistance.map({ best.distance < $0 }) ?? true else { return nil }
        return GitBranchBase(ref: best.ref, commit: best.tip)
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
