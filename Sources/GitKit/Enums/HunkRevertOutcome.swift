//
//  HunkRevertOutcome.swift
//  GitKit
//
//  What undoing the change at a line came to.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What ``HunkRevert/edit(at:in:diff:)`` found at a line.
public enum HunkRevertOutcome: Equatable, Sendable {
    /// The edit that undoes the hunk covering the line.
    case edit(HunkRevertEdit)
    /// No hunk covers the line: nothing there differs from the base.
    case noChange
    /// The text no longer holds the hunk's lines (it changed after the diff was taken); nothing
    /// is undone rather than the wrong lines.
    case textChanged
}
