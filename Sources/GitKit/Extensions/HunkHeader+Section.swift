//
//  HunkHeader+Section.swift
//  GitKit
//
//  The function or section heading git appends to a hunk header.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension HunkHeader {
    /// The section heading after a `@@ -a,b +c,d @@` header's second marker — the enclosing function
    /// or class git found (`func render(…) {`) — trimmed; nil when there is none or `line` is not a
    /// header. Everything after the second `@@` is the heading, so one that itself contains `@@` (an
    /// annotation, a decorator) is kept whole.
    static func section(of line: some StringProtocol) -> String? {
        guard line.hasPrefix("@@"), let close = line.dropFirst(2).range(of: "@@") else { return nil }
        let heading = line[close.upperBound...].trimmingCharacters(in: .whitespaces)
        return heading.isEmpty ? nil : heading
    }

    /// Whether a hunk's body lines (`+`, `-` and context, the header excluded) only change WHITESPACE:
    /// something was removed or added, and the removed and added text are the same once every
    /// whitespace character is dropped — a re-indent, a re-wrap, trailing spaces.
    static func isWhitespaceOnly(_ body: [String]) -> Bool {
        let removed = body.filter { $0.hasPrefix("-") }.map { $0.dropFirst() }
        let added = body.filter { $0.hasPrefix("+") }.map { $0.dropFirst() }
        guard !removed.isEmpty || !added.isEmpty else { return false }
        func squeezed(_ lines: [Substring]) -> String { lines.joined().filter { !$0.isWhitespace } }
        return squeezed(removed) == squeezed(added)
    }
}
