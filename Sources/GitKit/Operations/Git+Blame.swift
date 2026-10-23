//
//  Git+Blame.swift
//  GitKit
//
//  Single-line blame lookup.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Per-line blame.
public extension Git {

    /// Blame for one 1-based working-tree line (fast: `blame -L n,n`), or `nil` when `line` is
    /// out of range, `file` is outside `root` (without running git), or blame fails.
    /// Uncommitted lines report ``BlameInfo/uncommittedAuthor`` (``BlameInfo/isUncommitted``).
    ///
    /// A failure is retried once with the user's global and system configuration ignored: a
    /// global `blame.ignoreRevsFile` naming a file this repository lacks makes every blame exit 128.
    static func blame(for file: URL, line: Int, repoRoot root: URL) -> BlameInfo? {
        guard line > 0, let rel = relativePathIfUnderRoot(file, root: root) else { return nil }
        let args = ["blame", "-L", "\(line),\(line)", "--line-porcelain", "--", rel]
        guard let out = run(args, in: root) ?? run(args, in: root, environment: cleanConfigEnvironment) else {
            return nil
        }
        return parseBlame(out)
    }
}

extension Git {

    /// `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`: only the repository's own configuration.
    static let cleanConfigEnvironment = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]

    /// The author, age and summary from one `--line-porcelain` record; nil without an author.
    private static func parseBlame(_ out: String) -> BlameInfo? {
        var author = "", summary = ""
        var ts: TimeInterval = 0
        for raw in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("author ") {
                author = String(raw.dropFirst(7))
            } else if raw.hasPrefix("author-time ") {
                ts = TimeInterval(raw.dropFirst(12)) ?? 0
            } else if raw.hasPrefix("summary ") {
                summary = String(raw.dropFirst(8))
            }
        }
        guard !author.isEmpty else { return nil }
        return BlameInfo(author: author, timeAgo: ts > 0 ? relativeTime(ts) : "", summary: summary)
    }
}
