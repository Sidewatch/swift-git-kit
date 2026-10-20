//
//  Git+HeadDiff.swift
//  GitKit
//
//  Per-file diffs against HEAD for many files in one batched git diff.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Per-file diffs against `HEAD`, the content of a file's own diff view.
public extension Git {
    /// Each of `paths` (repository-relative) diffed against `HEAD` in ONE `git diff`, split back
    /// per file (``DiffChunks``), keyed by path: the file's chunk; for an untracked file, which
    /// `git diff HEAD` cannot see, its all-new diff (``untrackedDiff(for:repoRoot:)``); otherwise
    /// `""`, a clean file. On an unborn `HEAD` (no commits yet) the base is the empty tree, so a
    /// staged new file shows its content. With `ignoringWhitespace` a change that is only
    /// whitespace leaves no hunk.
    static func headDiffs(paths: [String], repoRoot root: URL, ignoringWhitespace: Bool = false) -> [String: String] {
        guard !paths.isEmpty else { return [:] }
        let flags = GitDiffFlags.patch(ignoringWhitespace: ignoringWhitespace)
        let combined =
            run(GitDiffFlags.quotePathOff + ["diff"] + flags + ["HEAD", "--"] + paths, in: root)
            ?? run(GitDiffFlags.quotePathOff + ["diff"] + flags + [diffBase(repoRoot: root), "--"] + paths, in: root) ?? ""
        let chunks = DiffChunks.byPath(combined)
        let tracked = Set(
            (run(GitDiffFlags.quotePathOff + ["ls-files", "-z", "--"] + paths, in: root) ?? "")
                .split(separator: "\0").map(String.init))
        var diffs: [String: String] = [:]
        for path in paths {
            let file = root.appendingPathComponent(path)
            if let chunk = chunks[path] {
                diffs[path] = chunk
            } else if !tracked.contains(path), FileManager.default.fileExists(atPath: file.path) {
                diffs[path] = untrackedDiff(for: file, repoRoot: root)
            } else {
                diffs[path] = ""
            }
        }
        return diffs
    }
}
