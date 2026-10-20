//
//  DiffChunks.swift
//  GitKit
//
//  A multi-file unified diff split back into one chunk per file, and each chunk summarised.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A multi-file unified diff split back into one chunk per file, and each chunk read for its path,
/// line counts and kind — so one batched `git diff` can feed many per-file views, with ONE rule for
/// what a chunk's path is.
public enum DiffChunks {
    /// The diff's file chunks in order, each the lines from its `diff --git` line up to the next.
    /// Anything before the first `diff --git` is dropped.
    public static func ordered(_ diff: String) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []
        var lines = diff.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        for line in lines {
            if line.hasPrefix("diff --git ") {
                if !current.isEmpty { chunks.append(current) }
                current = [line]
            } else if !current.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Each file's chunk of `diff`, keyed by its path (``summary(of:)``), each keeping its trailing newline.
    public static func byPath(_ diff: String) -> [String: String] {
        var out: [String: String] = [:]
        for chunk in ordered(diff) { out[summary(of: chunk).path] = chunk.joined(separator: "\n") + "\n" }
        return out
    }

    /// One chunk's path, counts and kind. The path is the `+++ b/` header's, else `--- a/`'s for a
    /// deletion, else `rename to`'s, else the `diff --git … b/` line's — header lines are read only
    /// BEFORE the first `@@`, so a hunk line that happens to read `+++ b/x` (an added `++ b/x`) never
    /// renames the chunk. A path git C-quotes (`"a/tab\there"`) is decoded; the tab git appends after
    /// a path with a space is dropped. The counts are the `+`/`-` lines inside hunks only.
    public static func summary(of chunk: [String]) -> DiffFileSummary {
        var path = "(unknown)"
        if let head = chunk.first, head.hasPrefix("diff --git "), let r = head.range(of: " b/") {
            path = clean(String(head[r.upperBound...]))
        }
        var insertions = 0, deletions = 0, inHunk = false
        var kind = DiffFileKind.modified
        var renameFrom: String?
        for line in chunk {
            if line.hasPrefix("@@") { inHunk = true; continue }
            if inHunk {
                if line.hasPrefix("+") { insertions += 1 } else if line.hasPrefix("-") { deletions += 1 }
                continue
            }
            if let p = headerPath(line, prefix: "+++ ", side: "b/") {
                path = p
            } else if let p = headerPath(line, prefix: "--- ", side: "a/") {
                path = p
            } else if line.hasPrefix("new file mode") {
                kind = .added
            } else if line.hasPrefix("deleted file mode") {
                kind = .deleted
            } else if line.hasPrefix("rename from ") {
                renameFrom = unquote(String(line.dropFirst(12)))
            } else if line.hasPrefix("rename to ") {
                path = unquote(String(line.dropFirst(10)))
            }
        }
        if let renameFrom { kind = .renamed(from: renameFrom) }
        return DiffFileSummary(path: path, insertions: insertions, deletions: deletions, kind: kind)
    }

    // MARK: - Paths

    /// The path a `---`/`+++` header names under `side` (`a/` or `b/`), quoted or not; nil for
    /// `/dev/null` or another line.
    private static func headerPath(_ line: String, prefix: String, side: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let rest = clean(String(line.dropFirst(prefix.count)))
        let path = rest.hasPrefix("\"") ? unquote(rest) : rest
        guard path.hasPrefix(side) else { return nil }
        return String(path.dropFirst(side.count))
    }

    /// `path` without the tab (and trailing spaces) git appends to a header path containing a space,
    /// decoded when quoted.
    private static func clean(_ path: String) -> String {
        var out = Substring(path)
        while out.hasSuffix("\t") || out.hasSuffix(" ") { out = out.dropLast() }
        return out.hasPrefix("\"") ? unquote(String(out)) : String(out)
    }

    /// A git C-quoted path (`"a/x\ty"`, octal bytes for anything else) decoded; an unquoted one unchanged.
    static func unquote(_ path: String) -> String {
        guard path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        var bytes: [UInt8] = []
        var chars = Array(path.utf8.dropFirst().dropLast())[...]
        while let c = chars.popFirst() {
            guard c == UInt8(ascii: "\\"), let next = chars.popFirst() else { bytes.append(c); continue }
            switch next {
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "\""): bytes.append(0x22)
            case UInt8(ascii: "\\"): bytes.append(0x5C)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = Int(next - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let d = chars.first, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(d) else { break }
                    value = value * 8 + Int(d - UInt8(ascii: "0"))
                    chars = chars.dropFirst()
                }
                bytes.append(UInt8(value & 0xFF))
            default: bytes.append(next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
