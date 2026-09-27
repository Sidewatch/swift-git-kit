//
//  Git+Diff.swift
//  GitKit
//
//  Line-level diff parsing: gutter markers and phantom removed rows.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Per-line diff markers, removed-line text and diff stats.
public extension Git {

    /// Per-line change kind for one file versus `HEAD`, for editor gutter markers.
    ///
    /// Parses `git diff --unified=0`. Added and modified lines map to their
    /// 1-based working-copy line number; a pure deletion marks the surviving line
    /// just below the removal.
    ///
    /// - Returns: A map from 1-based line number to ``GitChangeKind``.
    static func lineChanges(for file: URL, repoRoot root: URL) -> [Int: GitChangeKind] {
        lineDiff(for: file, repoRoot: root).marks
    }

    /// Both gutter maps for one file versus `HEAD` from a **single** `git diff --unified=0` run:
    /// `marks` as ``lineChanges(for:repoRoot:)`` returns it and `removed` as
    /// ``removedLines(for:repoRoot:)`` does, where calling both would run the same diff twice.
    static func lineDiff(for file: URL, repoRoot root: URL) -> (marks: [Int: GitChangeKind], removed: [Int: [String]]) {
        let rel = relativePath(file, root: root)
        guard let diff = run(["diff", "--unified=0", "--no-color", "HEAD", "--", rel], in: root) else {
            return ([:], [:])
        }
        var marks: [Int: GitChangeKind] = [:]
        var removed: [Int: [String]] = [:]
        var pending: [String] = []
        var anchor = 1
        var inHunk = false  // real `---`/`+++` file headers only precede the first @@
        func flush() {
            if !pending.isEmpty { removed[anchor, default: []].append(contentsOf: pending); pending = [] }
        }
        // `components(separatedBy:)` (a UTF-16 split), never `split(separator: "\n")`: `"\r\n"`
        // is ONE Character, so a Character split leaves a CRLF file's lines joined and the
        // marks stop after the first hunk.
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                flush()
                inHunk = true
                guard let hunk = HunkHeader.parse(line) else { continue }
                if hunk.changeKind == .deleted {
                    marks[max(1, hunk.newStart)] = .deleted  // pure deletion
                    anchor = max(1, hunk.newStart + 1)  // after a pure deletion
                } else {
                    for l in hunk.newLineRange { marks[l] = hunk.changeKind }
                    anchor = hunk.newStart  // above the first new line
                }
            } else if inHunk, line.hasPrefix("-") {
                // Removed content (even if it starts with "--"). A CRLF file's lines end in `\r`
                // here; the ghost row shows the text, not the terminator.
                var text = line.dropFirst()
                if text.hasSuffix("\r") { text = text.dropLast() }
                pending.append(String(text))
            }
        }
        flush()
        return (marks, removed)
    }

    /// A unified diff presenting an untracked file as all-new content, which `git diff HEAD`
    /// cannot show; `""` when `file` is outside `root` or unreadable.
    ///
    /// Runs `git diff --no-index /dev/null <path>` (exit 1 means "differs", so it is accepted).
    /// The output is a regular diff that splices into any combined-diff rendering.
    static func untrackedDiff(for file: URL, repoRoot root: URL) -> String {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return "" }
        return run(
            ["-c", "core.quotePath=false", "diff", "--no-color", "--no-index", "--", "/dev/null", rel],
            in: root, allowedStatuses: [1]) ?? ""
    }

    /// ``lineChanges(for:repoRoot:)`` for every changed file versus `HEAD`, from one process
    /// instead of one per file.
    ///
    /// Keys are repository-relative paths (the new path for a rename, the old for a deletion).
    /// Untracked files are absent, as they are from `git diff`.
    static func lineChangesAll(repoRoot root: URL) -> [String: [Int: GitChangeKind]] {
        // core.quotePath=false keeps non-ASCII paths verbatim in the ---/+++
        // headers instead of C-style octal-escaped.
        guard
            let diff = run(
                ["-c", "core.quotePath=false", "diff", "--unified=0", "--no-color", "HEAD"],
                in: root)
        else { return [:] }
        var all: [String: [Int: GitChangeKind]] = [:]
        var aPath: String?, bPath: String?
        var inHunk = false  // real ---/+++ headers only appear between `diff --git` and the first @@
        func headerPath(_ s: Substring) -> String? {
            guard s != "/dev/null" else { return nil }
            let p = (s.hasPrefix("a/") || s.hasPrefix("b/")) ? s.dropFirst(2) : s
            return String(p)
        }
        // A UTF-16 split, as in `lineDiff`: a Character split lets a CRLF file's last line swallow
        // the next `diff --git` header, filing the following file's hunks under the wrong path.
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") { inHunk = false; aPath = nil; bPath = nil; continue }
            if !inHunk, line.hasPrefix("--- ") { aPath = headerPath(line.dropFirst(4)); continue }
            if !inHunk, line.hasPrefix("+++ ") { bPath = headerPath(line.dropFirst(4)); continue }
            guard line.hasPrefix("@@") else { continue }
            inHunk = true
            guard let path = bPath ?? aPath, let hunk = HunkHeader.parse(line) else { continue }
            if hunk.changeKind == .deleted {
                all[path, default: [:]][max(1, hunk.newStart)] = .deleted
            } else {
                for l in hunk.newLineRange { all[path, default: [:]][l] = hunk.changeKind }
            }
        }
        return all
    }

    /// Removed lines to ghost inline as phantom rows, keyed by the 1-based new-file line they
    /// render *above* (for a pure deletion, the line just below the removal), text in order.
    static func removedLines(for file: URL, repoRoot root: URL) -> [Int: [String]] {
        lineDiff(for: file, repoRoot: root).removed
    }

    /// Total insertions/deletions in the working tree versus `HEAD` (staged +
    /// unstaged tracked changes), summed across all files.
    ///
    /// Parses `git diff --numstat HEAD`. Untracked files are not counted (they're
    /// absent from `git diff`); binary files contribute nothing. Returns `(0, 0)`
    /// on an unborn `HEAD` or any failure.
    static func diffStat(repoRoot root: URL) -> (insertions: Int, deletions: Int) {
        guard let out = run(["diff", "--numstat", "--no-color", "HEAD"], in: root) else { return (0, 0) }
        return parseNumstat(out)
    }

    /// Total insertions/deletions from commit `from` to `to`, or to the live working tree when
    /// `to` is nil (so the result moves as the tree is edited).
    ///
    /// Untracked and binary files count nothing; `(0, 0)` on any failure.
    static func diffStat(repoRoot root: URL, from: String, to: String?) -> (insertions: Int, deletions: Int) {
        var args = ["diff", "--numstat", "--no-color", from]
        if let to { args.append(to) }
        guard let out = run(args, in: root) else { return (0, 0) }
        return parseNumstat(out)
    }

    /// Sums a `git diff --numstat` body. Each line is `<added>\t<deleted>\t<path>`;
    /// binary files report `-` in both count columns and are skipped. Pure — exposed
    /// for testing without a repo.
    static func parseNumstat(_ text: String) -> (insertions: Int, deletions: Int) {
        var insertions = 0, deletions = 0
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2 else { continue }
            if let a = Int(cols[0]) { insertions += a }  // "-" (binary) → nil → skipped
            if let d = Int(cols[1]) { deletions += d }
        }
        return (insertions, deletions)
    }
}
