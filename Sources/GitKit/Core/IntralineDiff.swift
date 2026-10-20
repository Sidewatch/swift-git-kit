//
//  IntralineDiff.swift
//  GitKit
//
//  The words that changed inside a changed line: a removed line and the added line that
//  replaced it, compared token by token.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The words that changed inside a changed line, so a renderer can tint them over the line's
/// own tint: one argument changed in a 140-character line reads at a glance.
///
/// A line is split into tokens — a run of letters, digits and underscores, a run of whitespace,
/// or one other character — and the two token lists are aligned by their longest common
/// subsequence. Whatever is left over on each side is what changed. A pair that shares too
/// little (under ``minimumSharedFraction`` of the longer line) is a rewrite, not an edit, and
/// gets no ranges: the whole-line tint already says everything.
///
/// Ranges are UTF-16 `NSRange`s, ready for an attributed string.
public enum IntralineDiff {
    /// The changed spans of one removed/added pair.
    public struct Ranges: Equatable, Sendable {
        /// In the removed (old) line.
        public let old: [NSRange]
        /// In the added (new) line.
        public let new: [NSRange]

        /// The spans of a pair.
        public init(old: [NSRange], new: [NSRange]) {
            self.old = old
            self.new = new
        }
    }

    /// Below this share of unchanged characters (of the longer line) a pair is a rewrite.
    public static let minimumSharedFraction = 0.4
    /// Token-grid cells beyond which a pair is not compared (a minified line).
    static let maximumCells = 250_000

    /// The changed spans of `old` against `new`, or nil when the pair is identical, a rewrite,
    /// or too long to compare.
    public static func ranges(old: String, new: String) -> Ranges? {
        guard old != new else { return nil }
        let a = tokens(old), b = tokens(new)
        guard a.count * b.count <= maximumCells else { return nil }
        let (keptA, keptB) = commonTokens(a, b)
        let shared = keptA.reduce(0) { $0 + a[$1].range.length }
        let longer = max(old.utf16.count, new.utf16.count)
        guard longer > 0, Double(shared) / Double(longer) >= minimumSharedFraction else { return nil }
        return Ranges(old: spans(a, kept: keptA), new: spans(b, kept: keptB))
    }

    /// The changed spans for the lines of a unified diff, keyed by line index in `lines`, each
    /// range in the RAW line (its `-`/`+` marker at offset 0). Inside a hunk, a run of removed
    /// lines directly followed by a run of added lines pairs index-wise, as ``SideBySideDiff``
    /// pairs them; a `\ No newline` line between them does not break the run. Lines outside a
    /// hunk (file headers) and unpaired lines get nothing.
    public static func marks(in lines: [String]) -> [Int: [NSRange]] {
        var marks: [Int: [NSRange]] = [:]
        var removed: [Int] = [], added: [Int] = []
        var inHunk = false
        func flush() {
            for (r, a) in zip(removed, added) {
                guard let pair = ranges(old: String(lines[r].dropFirst()), new: String(lines[a].dropFirst())) else { continue }
                if !pair.old.isEmpty { marks[r] = pair.old.map(shifted) }
                if !pair.new.isEmpty { marks[a] = pair.new.map(shifted) }
            }
            removed = []
            added = []
        }
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("diff --git ") {
                flush()
                inHunk = false
            } else if line.hasPrefix("@@") {
                flush()
                inHunk = true
            } else if !inHunk || line.hasPrefix("\\") {
                continue
            } else if line.hasPrefix("-") {
                if !added.isEmpty { flush() }  // a new removed run after an added one
                removed.append(i)
            } else if line.hasPrefix("+") {
                added.append(i)
            } else {
                flush()
            }
        }
        flush()
        return marks
    }

    /// A content range moved past the line's one-character marker.
    private static func shifted(_ range: NSRange) -> NSRange { NSRange(location: range.location + 1, length: range.length) }

    // MARK: - Tokens

    /// One token of a line: its text, where it sits (UTF-16), and whether it is whitespace.
    private struct Token {
        /// The token's characters, compared for equality across the two lines.
        let text: Substring
        /// Its span in the line, in UTF-16 units.
        let range: NSRange
        /// True for a run of whitespace, which may sit between two changed spans without splitting them.
        let isSpace: Bool
    }

    /// What a character contributes to: a word run, a whitespace run, or a token of its own.
    private enum Kind: Equatable { case word, space, other }

    /// The kind of `c`: letters, digits and `_` build words; whitespace builds runs; anything else stands alone.
    private static func kind(_ c: Character) -> Kind {
        if c.isWhitespace { return .space }
        if c.isLetter || c.isNumber || c == "_" { return .word }
        return .other
    }

    /// Words, whitespace runs, and every other character on its own.
    private static func tokens(_ s: String) -> [Token] {
        var out: [Token] = []
        var start = s.startIndex
        var startOffset = 0
        var offset = 0
        var current: Kind?
        func close(at end: String.Index) {
            guard let current, start < end else { return }
            out.append(
                Token(text: s[start..<end], range: NSRange(location: startOffset, length: offset - startOffset), isSpace: current == .space)
            )
        }
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let k = kind(c)
            if k != current || k == .other {
                close(at: i)
                start = i
                startOffset = offset
                current = k
            }
            offset += c.utf16.count
            i = s.index(after: i)
        }
        close(at: s.endIndex)
        return out
    }

    // MARK: - Alignment

    /// The indices, on each side, of the tokens in the longest common subsequence.
    private static func commonTokens(_ a: [Token], _ b: [Token]) -> (Set<Int>, Set<Int>) {
        let n = a.count, m = b.count
        guard n > 0, m > 0 else { return ([], []) }
        // lcs[i][j] = length of the LCS of a[i...] and b[j...], in one flat buffer.
        var lcs = [Int](repeating: 0, count: (n + 1) * (m + 1))
        let w = m + 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i * w + j] = a[i].text == b[j].text ? lcs[(i + 1) * w + j + 1] + 1 : max(lcs[(i + 1) * w + j], lcs[i * w + j + 1])
            }
        }
        var keptA = Set<Int>(), keptB = Set<Int>()
        var i = 0, j = 0
        while i < n, j < m {
            if a[i].text == b[j].text {
                keptA.insert(i)
                keptB.insert(j)
                i += 1
                j += 1
            } else if lcs[(i + 1) * w + j] >= lcs[i * w + j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return (keptA, keptB)
    }

    /// The changed tokens merged into spans. Two changed spans with only unchanged whitespace
    /// between them are one span: "foo bar" → "baz qux" is one change, not two with a gap.
    private static func spans(_ tokens: [Token], kept: Set<Int>) -> [NSRange] {
        var out: [NSRange] = []
        var pendingSpace: NSRange?
        for (i, t) in tokens.enumerated() {
            if !kept.contains(i) {
                if let last = out.last, let gap = pendingSpace, NSMaxRange(last) == gap.location {
                    out[out.count - 1] = NSRange(location: last.location, length: NSMaxRange(t.range) - last.location)
                } else if let last = out.last, NSMaxRange(last) == t.range.location {
                    out[out.count - 1] = NSRange(location: last.location, length: NSMaxRange(t.range) - last.location)
                } else {
                    out.append(t.range)
                }
                pendingSpace = nil
            } else {
                pendingSpace = t.isSpace ? t.range : nil
            }
        }
        return out
    }
}
