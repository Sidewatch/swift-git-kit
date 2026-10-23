//
//  Git+Push.swift
//  GitKit
//
//  Push the checked-out branch: to the branch it tracks, or published to the one remote.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Pushing the current branch.
public extension Git {

    /// Where a push of the checked-out branch would go — the branch it tracks, or, for a branch
    /// that tracks nothing, the same name on the repository's only remote (or `origin` among
    /// several). No network: configuration only.
    static func pushTarget(repoRoot root: URL) -> Result<GitPushTarget, GitPushError> {
        guard !isDetachedHead(repoRoot: root), let branch = currentBranch(repoRoot: root) else { return .failure(.detachedHead) }
        if let upstream = upstream(of: branch, repoRoot: root) {
            let name = upstream.merge.hasPrefix("refs/heads/") ? String(upstream.merge.dropFirst("refs/heads/".count)) : upstream.merge
            return .success(GitPushTarget(remote: upstream.remote, branch: name, publishes: false))
        }
        guard let remote = publishRemote(repoRoot: root) else { return .failure(.noRemote) }
        return .success(GitPushTarget(remote: remote, branch: branch, publishes: true))
    }

    /// What a push would send now, or nil when there is nothing to: a tracked branch level with
    /// (or behind) its upstream, no remote to publish to, a detached HEAD. A branch that tracks
    /// nothing always has something to send — the branch itself. No network.
    static func pendingPush(repoRoot root: URL) -> GitPendingPush? {
        guard case .success(let target) = pushTarget(repoRoot: root) else { return nil }
        if target.publishes { return GitPendingPush(target: target, ahead: 0) }
        let ahead = aheadBehind(repoRoot: root).ahead
        return ahead > 0 ? GitPendingPush(target: target, ahead: ahead) : nil
    }

    /// Pushes the checked-out branch to ``pushTarget(repoRoot:)`` and returns it.
    ///
    /// A tracked branch is pushed to exactly that branch (`HEAD:refs/heads/<branch>` on its
    /// remote), so the commits counted as ahead are the ones sent, whatever `push.default` says.
    /// A branch that tracks nothing is published with `-u`. The repository's pre-push hook runs,
    /// as a person pushing expects; credentials come from git's own helpers and agent — nothing
    /// prompts, so one that is missing fails with git's words.
    static func push(repoRoot root: URL) -> Result<GitPushTarget, GitPushError> {
        let target: GitPushTarget
        switch pushTarget(repoRoot: root) {
        case .success(let found): target = found
        case .failure(let error): return .failure(error)
        }
        let args = target.publishes ? ["push", "-u", target.remote, "HEAD"] : ["push", target.remote, "HEAD:refs/heads/\(target.branch)"]
        let result = runCapturingError(args, in: root, timeout: longTimeout, hooks: true)
        return result.succeeded ? .success(target) : .failure(.failed(stderr: result.message))
    }
}

extension Git {

    /// The remote and merge ref `branch` tracks (`branch.<name>.remote` / `.merge`), or nil.
    static func upstream(of branch: String, repoRoot root: URL) -> (remote: String, merge: String)? {
        guard let remote = run(["config", "--get", "branch.\(branch).remote"], in: root)?.trimmed, !remote.isEmpty,
            let merge = run(["config", "--get", "branch.\(branch).merge"], in: root)?.trimmed, !merge.isEmpty
        else { return nil }
        return (remote, merge)
    }

    /// The remote a branch that tracks nothing is published to: the only one, else `origin`.
    static func publishRemote(repoRoot root: URL) -> String? {
        let remotes = (run(["remote"], in: root) ?? "").split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
        if remotes.count == 1 { return remotes[0] }
        return remotes.contains("origin") ? "origin" : nil
    }
}
