//
//  HunkRevertEdit.swift
//  GitKit
//
//  The edit that puts one hunk of a file back as its base has it.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The edit that undoes one hunk: replace `range` of the file's text with `replacement`, and the
/// hunk's lines read as the base (`HEAD`) has them. A text view applies it as an ordinary,
/// undoable edit.
public struct HunkRevertEdit: Equatable, Sendable {
    /// What to replace, in UTF-16 units of the current text (empty for a deletion put back).
    public let range: NSRange
    /// The base's lines, each with its line feed (the last without one when the base's file
    /// ended without a newline).
    public let replacement: String
    /// The hunk undone.
    public let hunk: HunkHeader

    /// An edit.
    public init(range: NSRange, replacement: String, hunk: HunkHeader) {
        self.range = range
        self.replacement = replacement
        self.hunk = hunk
    }
}
