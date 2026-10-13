//
//  GitDirStamp.swift
//  GitKit
//
//  The paths under one repository's git dir whose modification times say "git state moved".
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The paths under one repository's git dir whose modification times say "git state moved" —
/// what the 5 s tick stats instead of spawning git on an idle repo. Resolved once per root
/// change (`GitDirStamp.resolve`), stat'ed on every tick (`stat()`).
///
/// Per-worktree state lives in the git dir (`HEAD`, `index`, `logs/HEAD`, the merge / rebase /
/// cherry-pick / revert markers, `FETCH_HEAD`); shared state in the common dir (`packed-refs`,
/// `refs/remotes/<remote>` — a push or fetch moves only the remote-tracking ref and its reflog —
/// `info/exclude`, and `worktrees/<name>/{HEAD,index,logs/HEAD}` for every linked worktree). From
/// inside a linked worktree the git dir is `<common>/worktrees/<name>`, which is why the two are
/// held apart.
public struct GitDirStamp: Sendable {
    /// The checkout the stamp watches.
    public let repoRoot: URL
    /// `rev-parse --absolute-git-dir`: a linked worktree's `.git` is a file pointing here.
    public let gitDir: URL
    /// `rev-parse --git-common-dir`: the main worktree's git dir, shared by every linked one.
    public let commonDir: URL
    /// The upstream's full ref name (`refs/remotes/origin/main`); nil without an upstream.
    public let upstreamRef: String?
    /// `<common>/refs/remotes/<remote>` for every remote, re-listed when the parent's mtime moves.
    public internal(set) var remoteDirs: [URL]
    /// `<common>/worktrees/<name>` for every linked worktree, re-listed when the parent's mtime moves.
    public internal(set) var worktreeDirs: [URL]
    /// The `refs/remotes` dir's mtime at the last listing.
    public internal(set) var remotesListedAt: Date?
    /// The `worktrees` dir's mtime at the last listing.
    public internal(set) var worktreesListedAt: Date?
    /// `info/exclude`'s mtime at the last stat — its move invalidates the ignore rules.
    public internal(set) var infoExcludeDate: Date?
    /// Set by `stat()` when `info/exclude` moved since the previous stat.
    public internal(set) var infoExcludeMoved = false

    init(repoRoot: URL, gitDir: URL, commonDir: URL, upstreamRef: String?, remoteDirs: [URL], worktreeDirs: [URL]) {
        self.repoRoot = repoRoot
        self.gitDir = gitDir
        self.commonDir = commonDir
        self.upstreamRef = upstreamRef
        self.remoteDirs = remoteDirs
        self.worktreeDirs = worktreeDirs
    }
}
