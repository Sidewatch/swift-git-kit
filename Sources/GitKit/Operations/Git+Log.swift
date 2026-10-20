//
//  Git+Log.swift
//  GitKit
//
//  One commit from `git log`.
//
//  Created by David Sherlock on 7/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One commit from `git log`.
public struct GitCommit: Equatable, Sendable {
    /// The full 40-character SHA.
    public let hash: String
    /// The abbreviated SHA.
    public let shortHash: String
    /// The author's name.
    public let author: String
    /// The author date as `YYYY-MM-DD`.
    public let date: String
    /// The first line of the message.
    public let subject: String

    /// Creates a commit record.
    public init(hash: String, shortHash: String, author: String, date: String, subject: String) {
        self.hash = hash; self.shortHash = shortHash; self.author = author
        self.date = date; self.subject = subject
    }
}

/// Commit history and past file contents.
public extension Git {

    /// Up to `limit` of the most recent commits on the current branch, newest first.
    ///
    /// Fields are `%x1f`-delimited so a subject with any punctuation parses cleanly;
    /// `--no-show-signature` keeps a `log.showSignature` user's gpg lines out of the records.
    static func log(repoRoot root: URL, limit: Int = 300) -> [GitCommit] {
        guard
            let out = run(
                [
                    "log", "-n", "\(max(1, limit))", "--date=short", "--no-show-signature",
                    "--pretty=format:\(Self.commitFormat)",
                ], in: root)
        else { return [] }
        return parseCommits(out)
    }

    /// Commit history touching `path` (repository-relative), newest first — the History of
    /// a single file. Follows across renames.
    static func fileLog(path: String, repoRoot root: URL, limit: Int = 100) -> [GitCommit] {
        guard
            let out = run(
                [
                    "log", "-n", "\(max(1, limit))", "--date=short", "--follow", "--no-show-signature",
                    "--pretty=format:\(Self.commitFormat)", "--", path,
                ], in: root)
        else { return [] }
        return parseCommits(out)
    }

    /// The commits that changed `path` (repository-relative), newest first, each with the patch
    /// it made to the file — across renames (`--follow`). For "how did this file get here".
    static func fileHistory(path: String, repoRoot root: URL, limit: Int = 50, ignoringWhitespace: Bool = false) -> [GitHistoryEntry] {
        let out = run(
            GitDiffFlags.quotePathOff
                + [
                    "log", "-n", "\(max(1, limit))", "--date=short", "--follow", "--no-show-signature", "-p",
                    "--pretty=format:%x1e\(Self.commitFormat)",
                ]
                + GitDiffFlags.patch(ignoringWhitespace: ignoringWhitespace) + ["--", path],
            in: root)
        return parseHistory(out ?? "")
    }

    /// The commits that changed lines `lines` (1-based, inclusive) of `path` as they stand now,
    /// newest first, each with the patch it made to that range (`git log -L`), the range followed
    /// back through every edit that moved it. For "how did this function get here".
    static func lineHistory(path: String, lines: ClosedRange<Int>, repoRoot root: URL, limit: Int = 50) -> [GitHistoryEntry] {
        let range = "\(max(1, lines.lowerBound)),\(max(1, lines.upperBound)):\(path)"
        let out = run(
            GitDiffFlags.quotePathOff
                + [
                    "log", "-n", "\(max(1, limit))", "--date=short", "--no-show-signature",
                    "--pretty=format:%x1e\(Self.commitFormat)",
                ]
                + GitDiffFlags.plain + GitDiffFlags.prefixed + ["-L", range],
            in: root)
        return parseHistory(out ?? "")
    }

    /// Splits `%x1e`-led records into entries: the first line of each is the commit, the rest its patch.
    private static func parseHistory(_ out: String) -> [GitHistoryEntry] {
        out.components(separatedBy: "\u{1e}").compactMap { record in
            guard !record.isEmpty else { return nil }
            let (head, rest) =
                record.firstIndex(of: "\n").map { (String(record[..<$0]), String(record[record.index(after: $0)...])) }
                ?? (record, "")
            guard let commit = parseCommits(head).first else { return nil }
            return GitHistoryEntry(commit: commit, patch: rest.trimmingCharacters(in: .newlines))
        }
    }

    /// The full patch for one commit (`git show`), for the History detail view. `nil` on error.
    static func showCommit(_ hash: String, repoRoot root: URL, ignoringWhitespace: Bool = false) -> String? {
        run(
            ["show", "--no-show-signature", "--stat", "--patch"] + GitDiffFlags.patch(ignoringWhitespace: ignoringWhitespace) + [hash],
            in: root)
    }

    /// A file's content at `revision` (`git show <rev>:<path>`), for viewing a past version
    /// or building an arbitrary-revision diff. `nil` if the path didn't exist there.
    static func showFile(revision: String, path: String, repoRoot root: URL) -> String? {
        run(["show", "\(revision):\(path)"], in: root)
    }

    /// The unit-separator pretty-format shared by ``log`` and ``fileLog``.
    private static var commitFormat: String { "%H%x1f%h%x1f%an%x1f%ad%x1f%s" }

    /// Parses newline-separated `commitFormat` records into ``GitCommit``s.
    private static func parseCommits(_ out: String) -> [GitCommit] {
        out.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 5 else { return nil }
            return GitCommit(hash: f[0], shortHash: f[1], author: f[2], date: f[3], subject: f[4])
        }
    }
}
