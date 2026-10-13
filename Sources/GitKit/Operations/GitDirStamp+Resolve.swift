//
//  GitDirStamp+Resolve.swift
//  GitKit
//
//  Resolving a repository's stamp paths (three `rev-parse` spawns, off-main) and stat'ing them.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

extension GitDirStamp {
    /// Resolves the stamp for `repoRoot`: the git dir, the common dir, the upstream ref and the
    /// remote / linked-worktree listings. Spawns git, so call off-main; nil when `repoRoot` is
    /// not a repository.
    public static func resolve(repoRoot: URL) -> GitDirStamp? {
        guard let gitDir = Git.run(["rev-parse", "--absolute-git-dir"], in: repoRoot).map({ URL(fileURLWithPath: $0.trimmed) })
        else { return nil }
        let common =
            Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repoRoot)
            .map { URL(fileURLWithPath: $0.trimmed) } ?? gitDir
        // Fails (nil) when the branch has no upstream, which is a fact, not an error.
        let upstream = Git.run(["rev-parse", "--symbolic-full-name", "@{u}"], in: repoRoot)?.trimmed
        var stamp = GitDirStamp(
            repoRoot: repoRoot, gitDir: gitDir, commonDir: common,
            upstreamRef: upstream.flatMap { $0.isEmpty ? nil : $0 },
            remoteDirs: [], worktreeDirs: [])
        stamp.relistRemotes()
        stamp.relistWorktrees()
        return stamp
    }

    /// The mtimes of every watched path, in a fixed order; any difference from the previous
    /// call means git state moved. Stat-only — no spawn. Re-lists the remotes and worktrees
    /// when their parent dir's mtime moved (a `git remote add`, a `git worktree add`).
    public mutating func stat() -> [Date?] {
        if Self.modificationDate(of: commonDir.appendingPathComponent("refs/remotes")) != remotesListedAt { relistRemotes() }
        if Self.modificationDate(of: commonDir.appendingPathComponent("worktrees")) != worktreesListedAt { relistWorktrees() }
        let exclude = Self.modificationDate(of: commonDir.appendingPathComponent("info/exclude"))
        infoExcludeMoved = exclude != infoExcludeDate
        infoExcludeDate = exclude
        return watchedPaths.map(Self.modificationDate)
    }

    /// Every path whose mtime the stamp compares.
    public var watchedPaths: [URL] {
        var paths = Self.perWorktreeNames.map(gitDir.appendingPathComponent)
        paths += ["packed-refs", "FETCH_HEAD", "info/exclude", "refs/remotes", "worktrees"].map(commonDir.appendingPathComponent)
        if let upstreamRef {
            paths.append(commonDir.appendingPathComponent(upstreamRef))
            paths.append(commonDir.appendingPathComponent("logs/" + upstreamRef))
        }
        paths += remoteDirs
        for dir in worktreeDirs { paths += ["HEAD", "index", "logs/HEAD"].map(dir.appendingPathComponent) }
        return paths
    }

    /// The per-worktree files: branch moves, staging, every HEAD-moving op's reflog append,
    /// a fetch, and the in-progress markers of a merge, rebase, cherry-pick, revert or bisect.
    private static let perWorktreeNames = [
        "HEAD", "index", "logs/HEAD", "FETCH_HEAD", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
        "rebase-merge", "rebase-apply",
    ]

    private mutating func relistRemotes() {
        let dir = commonDir.appendingPathComponent("refs/remotes")
        remotesListedAt = Self.modificationDate(of: dir)
        remoteDirs = Self.subdirectories(of: dir)
    }

    private mutating func relistWorktrees() {
        let dir = commonDir.appendingPathComponent("worktrees")
        worktreesListedAt = Self.modificationDate(of: dir)
        worktreeDirs = Self.subdirectories(of: dir)
    }

    /// The immediate subdirectories of `dir`, sorted; empty when it does not exist.
    private static func subdirectories(of dir: URL) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().map { dir.appendingPathComponent($0, isDirectory: true) }
    }

    /// The mtime of a path, nil when it does not exist.
    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
