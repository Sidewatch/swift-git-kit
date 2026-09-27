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
    /// out of range or blame fails. Uncommitted lines report author `"Not Committed Yet"`.
    static func blame(for file: URL, line: Int, repoRoot root: URL) -> BlameInfo? {
        guard line > 0 else { return nil }
        let rel = relativePath(file, root: root)
        guard let out = run(["blame", "-L", "\(line),\(line)", "--line-porcelain", "--", rel], in: root) else { return nil }
        var author = "", summary = ""
        var ts: TimeInterval = 0
        for raw in out.split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("author ") { author = String(raw.dropFirst(7)) }
            else if raw.hasPrefix("author-time ") { ts = TimeInterval(raw.dropFirst(12)) ?? 0 }
            else if raw.hasPrefix("summary ") { summary = String(raw.dropFirst(8)) }
        }
        guard !author.isEmpty else { return nil }
        return BlameInfo(author: author, timeAgo: ts > 0 ? relativeTime(ts) : "", summary: summary)
    }
}
