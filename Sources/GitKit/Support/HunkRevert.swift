//
//  HunkRevert.swift
//  GitKit
//
//  Undo one hunk: the edit that puts the lines of a change back as the base has them.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Undo one hunk of a file's diff against its base, as an edit to the file's current text — so
/// the host applies it the way it applies any edit (undoable, saved through its own writer)
/// instead of letting `git apply` rewrite the file behind it.
///
/// The hunk is the one covering a 1-based line of the current text — its new-side lines, or for a
/// pure deletion the line just below the gap (``HunkHeader/deletionLine``, where a gutter marks
/// it). Before anything is replaced the text must still hold the hunk's new-side lines exactly;
/// otherwise the answer is ``HunkRevertOutcome/textChanged``. Lines are split on `\n`, so a CRLF
/// file's `\r` stays part of each line on both sides, and `\ No newline at end of file` is
/// honoured on the base's side.
public enum HunkRevert {

    /// The edit that undoes the hunk of `diff` (one file's unified diff, any context) covering
    /// `line` of `text`, or why there is none.
    public static func edit(at line: Int, in text: String, diff: String) -> HunkRevertOutcome {
        guard let hunk = hunks(in: diff).first(where: { covers($0.header, line: line) }) else { return .noChange }
        let lines = LineTable(text)
        let header = hunk.header
        let first = header.newCount > 0 ? header.newStart - 1 : header.newStart  // 0-based
        guard first >= 0, first + header.newCount <= lines.count else { return .textChanged }
        for offset in 0..<header.newCount where lines.text(of: first + offset) != hunk.new[offset] {
            return .textChanged
        }
        let start = lines.start(of: first), end = lines.start(of: first + header.newCount)
        var replacement = hunk.old.map { $0 + "\n" }.joined()
        if hunk.oldEndsWithoutNewline, end == lines.length { replacement.removeLast() }
        return .edit(HunkRevertEdit(range: NSRange(location: start, length: end - start), replacement: replacement, hunk: header))
    }

    /// One hunk: its header and both sides' lines (context lines on both).
    struct Hunk {
        var header: HunkHeader
        var old: [String] = []
        var new: [String] = []
        var oldEndsWithoutNewline = false
    }

    /// The hunks of one file's unified diff, in order; file headers before the first `@@` skipped.
    static func hunks(in diff: String) -> [Hunk] {
        var result: [Hunk] = []
        var lastSide: Character?
        for line in diff.components(separatedBy: "\n") {
            if let header = HunkHeader.parse(line) {
                result.append(Hunk(header: header))
                lastSide = nil
                continue
            }
            guard !result.isEmpty, let marker = line.first else { continue }
            let body = String(line.dropFirst())
            switch marker {
            case " ":
                result[result.count - 1].old.append(body)
                result[result.count - 1].new.append(body)
                lastSide = " "
            case "-":
                result[result.count - 1].old.append(body)
                lastSide = "-"
            case "+":
                result[result.count - 1].new.append(body)
                lastSide = "+"
            case "\\":
                // `\ No newline at end of file` follows the line it is about.
                if lastSide == "-" || lastSide == " " { result[result.count - 1].oldEndsWithoutNewline = true }
            default:
                continue
            }
        }
        return result
    }

    /// Whether `header`'s hunk is the change at `line` (1-based) of the new side.
    static func covers(_ header: HunkHeader, line: Int) -> Bool {
        header.newCount > 0 ? header.newLineRange.contains(line) : line == header.deletionLine
    }
}

/// A text's lines by UTF-16 start offset: what a hunk's line numbers index.
private struct LineTable {
    let string: NSString
    let starts: [Int]
    let length: Int
    let endsWithNewline: Bool

    init(_ text: String) {
        string = text as NSString
        length = string.length
        var starts = [0]
        for index in 0..<length where string.character(at: index) == 0x0A { starts.append(index + 1) }
        self.starts = starts
        endsWithNewline = length > 0 && string.character(at: length - 1) == 0x0A
    }

    /// Lines as git counts them: a final line feed ends the last line rather than starting one.
    var count: Int { length == 0 ? 0 : (endsWithNewline ? starts.count - 1 : starts.count) }

    /// Where line `index` (0-based) starts; the text's end past the last line.
    func start(of index: Int) -> Int { index < starts.count ? starts[index] : length }

    /// Line `index`'s text without its line feed.
    func text(of index: Int) -> String {
        let from = start(of: index)
        var to = start(of: index + 1)
        if to > from, to <= length, string.character(at: to - 1) == 0x0A { to -= 1 }
        return string.substring(with: NSRange(location: from, length: to - from))
    }
}
