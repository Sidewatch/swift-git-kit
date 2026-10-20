//
//  DiffChunks.swift
//  GitKit
//
//  A multi-file unified diff split back into one chunk per file.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A multi-file unified diff split back into one chunk per file, so one batched `git diff`
/// can feed many per-file views.
public enum DiffChunks {
    /// Each file's chunk of `diff`, keyed by its repository-relative path: the `+++ b/` path,
    /// else (a deletion) the `--- a/` path, else the `diff --git … b/` path. Only the lines
    /// before a chunk's first `@@` are read for the path, so a hunk line that happens to start
    /// `+++ b/` cannot rename it. A chunk keeps its trailing newline.
    public static func byPath(_ diff: String) -> [String: String] {
        var chunks: [String: String] = [:]
        var current: [String] = []
        func flush() {
            guard !current.isEmpty else { return }
            if let path = path(of: current) { chunks[path] = current.joined(separator: "\n") + "\n" }
            current = []
        }
        var lines = diff.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        for line in lines {
            if line.hasPrefix("diff --git ") { flush() }
            if !current.isEmpty || line.hasPrefix("diff --git ") { current.append(line) }
        }
        flush()
        return chunks
    }

    /// The path a chunk's headers name; a trailing tab (git's marker for a path with spaces) is dropped.
    private static func path(of chunk: [String]) -> String? {
        var path: String?
        for line in chunk {
            if line.hasPrefix("@@") { break }  // headers only precede the first hunk
            if line.hasPrefix("+++ b/") {
                path = String(line.dropFirst(6))
            } else if path == nil, line.hasPrefix("--- a/") {
                path = String(line.dropFirst(6))
            } else if path == nil, line.hasPrefix("diff --git "), let r = line.range(of: " b/") {
                path = String(line[r.upperBound...])
            }
        }
        return path.map { $0.hasSuffix("\t") ? String($0.dropLast()) : $0 }
    }
}
