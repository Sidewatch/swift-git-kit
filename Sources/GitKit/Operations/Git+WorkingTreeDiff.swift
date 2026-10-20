//
//  Git+WorkingTreeDiff.swift
//  GitKit
//
//  One diff of the whole working tree — untracked files included — against any commit, without
//  touching the real index.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The working tree, untracked files included, against a commit.
public extension Git {

    /// The unified diff from `from` (a commit, a checkpoint, or ``diffBase(repoRoot:)``) to the
    /// working tree as it stands, every untracked unignored file included as new content, in
    /// ONE process; optionally narrowed to `paths`. Empty when nothing differs, nil on failure.
    ///
    /// Reads through a scratch index (``GitScratchIndex``): a copy of the real one — so staged
    /// and partly staged files count and the stat cache is kept — with every untracked file
    /// marked intent-to-add, so a new file is an `A` with its content, and a file `from` holds
    /// that is untracked now and unchanged is not reported at all. The real index is never
    /// written; the scratch one is deleted afterwards. With `nameStatus` the output is
    /// `--name-status -z` (``workingTreeChangedFiles(repoRoot:from:paths:)`` parses it). With
    /// `ignoringWhitespace` a patch leaves out changes that are only whitespace.
    static func workingTreeDiff(
        repoRoot: URL, from: String, paths: [String] = [], nameStatus: Bool = false, ignoringWhitespace: Bool = false
    ) -> String? {
        let scratch = GitScratchIndex()
        defer { scratch.remove() }
        scratch.copyIndex(of: repoRoot)  // a repository with no index yet starts empty
        markIntentToAdd(untrackedReadableFiles(repoRoot: repoRoot), in: scratch, repoRoot: repoRoot)
        // `--name-status` lists a stat-stale file as `M` under the package-wide
        // `diff.autoRefreshIndex=false`; turning it back on here refreshes the SCRATCH index only.
        let config = nameStatus ? ["-c", "diff.autoRefreshIndex=true"] : []
        let flags = nameStatus ? ["--name-status", "-z"] : GitDiffFlags.patch(ignoringWhitespace: ignoringWhitespace)
        let pathspec = paths.isEmpty ? [] : ["--"] + paths
        return run(
            GitDiffFlags.quotePathOff + config + ["diff"] + flags + [from] + pathspec,
            in: repoRoot, environment: scratch.environment)
    }

    /// The files that differ between `from` and the working tree, untracked files included, in
    /// git's order — ``workingTreeDiff(repoRoot:from:paths:nameStatus:)`` parsed. A rename is
    /// reported under its new path with ``GitStatusEntry/oldPath`` set.
    static func workingTreeChangedFiles(repoRoot: URL, from: String, paths: [String] = []) -> [GitStatusEntry] {
        NameStatusParser.entries(workingTreeDiff(repoRoot: repoRoot, from: from, paths: paths, nameStatus: true) ?? "")
    }
}

extension Git {

    /// Untracked, unignored files git can read, from `ls-files --others --exclude-standard`.
    /// Dropped: a nested repository (listed as `nested/`, which `add` would record as a gitlink
    /// and `diff` then fail to hash) and an unreadable file (which `diff` fails to hash too).
    private static func untrackedReadableFiles(repoRoot: URL) -> [String] {
        let out = run(GitDiffFlags.quotePathOff + ["ls-files", "--others", "--exclude-standard", "-z"], in: repoRoot) ?? ""
        return out.split(separator: "\0").map(String.init).filter { file in
            !file.hasSuffix("/") && FileManager.default.isReadableFile(atPath: repoRoot.appendingPathComponent(file).path)
        }
    }

    /// `git add -N` of `files` into `scratch`, the list fed through stdin so its length is not
    /// bounded by the argument limit.
    private static func markIntentToAdd(_ files: [String], in scratch: GitScratchIndex, repoRoot: URL) {
        guard !files.isEmpty else { return }
        _ = run(
            ["add", "-N", "--ignore-errors", "--pathspec-from-file=-", "--pathspec-file-nul"],
            in: repoRoot, environment: scratch.environment, allowedStatuses: [1],
            input: Data(files.map { $0 + "\0" }.joined().utf8))
    }
}
