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
import FoundationExtensions

/// Per-line diff markers, removed-line text and diff stats.
public extension Git {

    /// Per-line change kind for one file versus `HEAD`, for editor gutter markers.
    ///
    /// Parses `git diff --unified=0`. Added and modified lines map to their 1-based
    /// working-copy line number; a pure deletion marks the line just BELOW the removal —
    /// `newStart + 1` of its hunk, the same line the ghost rows of
    /// ``removedLines(for:repoRoot:)`` sit above: `1` for a deletion before the first line
    /// (`+0,0`), and one past the last line for a deletion at the end of the file (`+4,0` in a
    /// four-line result marks line 5), which a consumer must tolerate.
    ///
    /// - Returns: A map from 1-based line number to ``GitChangeKind``.
    static func lineChanges(for file: URL, repoRoot root: URL) -> [Int: GitChangeKind] {
        lineDiff(for: file, repoRoot: root).marks
    }

    /// Both gutter maps for one file versus `HEAD` from a **single** `git diff --unified=0` run:
    /// `marks` as ``lineChanges(for:repoRoot:)`` returns it and `removed` as
    /// ``removedLines(for:repoRoot:)`` does, where calling both would run the same diff twice.
    /// Empty, without running git, for a file outside `root`.
    static func lineDiff(for file: URL, repoRoot root: URL) -> (marks: [Int: GitChangeKind], removed: [Int: [String]]) {
        guard let rel = relativePathIfUnderRoot(file, root: root),
            let diff = diffAgainstBase(["diff"] + GitDiffFlags.unifiedZero, paths: [rel], in: root)
        else { return ([:], [:]) }
        return parseLineDiff(diff)
    }

    /// A unified diff presenting an untracked file as all-new content, which `git diff HEAD`
    /// cannot show; `""` when `file` is outside `root` or unreadable.
    ///
    /// Runs `git diff --no-index /dev/null <path>` (exit 1 means "differs", so it is accepted).
    /// The output is a regular diff that splices into any combined-diff rendering.
    static func untrackedDiff(for file: URL, repoRoot root: URL) -> String {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return "" }
        return run(
            GitDiffFlags.quotePathOff + ["diff"] + GitDiffFlags.patch + ["--no-index", "--", "/dev/null", rel],
            in: root, allowedStatuses: [1]) ?? ""
    }

    /// ``lineChanges(for:repoRoot:)`` for every changed file versus `HEAD`, from one process
    /// instead of one per file.
    ///
    /// Keys are repository-relative paths (the new path for a rename, the old for a deletion).
    /// Untracked files are absent, as they are from `git diff`.
    static func lineChangesAll(repoRoot root: URL) -> [String: [Int: GitChangeKind]] {
        guard
            let diff = diffAgainstBase(
                GitDiffFlags.quotePathOff + ["diff"] + GitDiffFlags.unifiedZero + GitDiffFlags.prefixed,
                paths: [], in: root)
        else { return [:] }
        return parseLineChangesAll(diff)
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
    /// absent from `git diff`); binary files contribute nothing. On an unborn `HEAD` every
    /// staged file counts as new. Returns `(0, 0)` on any failure.
    static func diffStat(repoRoot root: URL) -> (insertions: Int, deletions: Int) {
        guard let out = diffAgainstBase(["diff", "--numstat"] + GitDiffFlags.plain, paths: [], in: root) else {
            return (0, 0)
        }
        return parseNumstat(out)
    }

    /// Total insertions/deletions from commit `from` to `to`, or to the live working tree when
    /// `to` is nil (so the result moves as the tree is edited).
    ///
    /// Untracked and binary files count nothing; `(0, 0)` on any failure.
    static func diffStat(repoRoot root: URL, from: String, to: String?) -> (insertions: Int, deletions: Int) {
        var args = ["diff", "--numstat"] + GitDiffFlags.plain + [from]
        if let to { args.append(to) }
        guard let out = run(args, in: root) else { return (0, 0) }
        return parseNumstat(out)
    }

    /// What a diff "versus `HEAD`" compares against: `"HEAD"` when it is a commit, else the id of
    /// the empty tree, so a repository with no commits yet shows every staged file as new instead
    /// of failing with `bad revision 'HEAD'`. For callers building their own diff commands.
    static func diffBase(repoRoot root: URL) -> String {
        if run(["rev-parse", "--verify", "-q", "HEAD"], in: root) != nil { return "HEAD" }
        return emptyTree(repoRoot: root)
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

extension Git {

    /// The empty tree's id under the repository's hash algorithm (SHA-1 or SHA-256).
    static func emptyTree(repoRoot root: URL) -> String {
        guard let id = run(["hash-object", "-t", "tree", "/dev/null"], in: root)?.trimmed, !id.isEmpty else {
            return "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        }
        return id
    }

    /// `git <leading> HEAD -- <paths>`, retried against ``diffBase(repoRoot:)`` when `HEAD` is
    /// not a commit yet; nil on failure. The retry costs a spawn only in the unborn case.
    static func diffAgainstBase(_ leading: [String], paths: [String], in root: URL) -> String? {
        let tail = paths.isEmpty ? [] : ["--"] + paths
        if let out = run(leading + ["HEAD"] + tail, in: root) { return out }
        let base = diffBase(repoRoot: root)
        guard base != "HEAD" else { return nil }
        return run(leading + [base] + tail, in: root)
    }

    /// Marks and ghost rows from one file's `--unified=0` diff.
    static func parseLineDiff(_ diff: String) -> (marks: [Int: GitChangeKind], removed: [Int: [String]]) {
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
                mark(hunk, into: &marks)
                anchor = hunk.changeKind == .deleted ? hunk.deletionLine : hunk.newStart  // above the first new line
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

    /// Per-path marks from a whole-tree `--unified=0` diff with `a/`/`b/` headers.
    static func parseLineChangesAll(_ diff: String) -> [String: [Int: GitChangeKind]] {
        var all: [String: [Int: GitChangeKind]] = [:]
        var aPath: String?, bPath: String?
        var inHunk = false  // real ---/+++ headers only appear between `diff --git` and the first @@
        // A UTF-16 split, as in `parseLineDiff`: a Character split lets a CRLF file's last line
        // swallow the next `diff --git` header, filing the following file's hunks under the wrong path.
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") { inHunk = false; aPath = nil; bPath = nil; continue }
            if !inHunk, line.hasPrefix("--- ") { aPath = headerPath(line.dropFirst(4)); continue }
            if !inHunk, line.hasPrefix("+++ ") { bPath = headerPath(line.dropFirst(4)); continue }
            guard line.hasPrefix("@@") else { continue }
            inHunk = true
            guard let path = bPath ?? aPath, let hunk = HunkHeader.parse(line) else { continue }
            mark(hunk, into: &all[path, default: [:]])
        }
        return all
    }

    /// Writes one hunk's marks: its new lines by kind, or ``HunkHeader/deletionLine`` for a pure deletion.
    private static func mark(_ hunk: HunkHeader, into marks: inout [Int: GitChangeKind]) {
        if hunk.changeKind == .deleted {
            marks[hunk.deletionLine] = .deleted
        } else {
            for l in hunk.newLineRange { marks[l] = hunk.changeKind }
        }
    }

    /// The path in a `--- a/path` / `+++ b/path` header, prefix stripped; nil for `/dev/null`.
    ///
    /// git appends a TAB to the header of a path containing spaces (`--- a/my file.ts\t`), so a
    /// trailing tab is not part of the name.
    static func headerPath(_ s: Substring) -> String? {
        var p = s
        if p.hasSuffix("\t") { p = p.dropLast() }
        guard p != "/dev/null" else { return nil }
        if p.hasPrefix("a/") || p.hasPrefix("b/") { p = p.dropFirst(2) }
        return String(p)
    }
}
