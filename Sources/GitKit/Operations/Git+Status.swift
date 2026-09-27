//
//  Git+Status.swift
//  GitKit
//
//  Working-tree status of changed files.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Working-tree status.
public extension Git {

    /// Working-tree changes versus `HEAD` as repository-relative `(path, kind)` pairs.
    ///
    /// `-z` keeps paths verbatim (no C-style quoting); `-uall` lists each untracked file rather
    /// than collapsing a new directory to `dir/`. A rename or copy reports its new path.
    static func status(repoRoot root: URL) -> [(path: String, kind: GitChangeKind)] {
        guard let out = run(["status", "--porcelain=v1", "-z", "-uall"], in: root) else { return [] }
        var result: [(String, GitChangeKind)] = []
        let fields = out.split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < fields.count {
            let entry = String(fields[i])
            i += 1
            guard entry.count >= 4 else { continue }
            let code = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            // Rename/copy entries carry the OLD path as the next NUL field — skip it.
            if code.contains("R") || code.contains("C") { i += 1 }
            let kind: GitChangeKind
            if code.contains("?") { kind = .untracked }
            else if code.contains("A") { kind = .added }
            else if code.contains("D") { kind = .deleted }
            else if code.contains("R") { kind = .renamed }
            else { kind = .modified }
            result.append((path, kind))
        }
        return result
    }
}
