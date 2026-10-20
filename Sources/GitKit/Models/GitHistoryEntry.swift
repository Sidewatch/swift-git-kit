//
//  GitHistoryEntry.swift
//  GitKit
//
//  One commit in a file's or a line range's history, with its patch.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One commit in a file's or a line range's history (``Git/fileHistory(path:repoRoot:limit:ignoringWhitespace:)``,
/// ``Git/lineHistory(path:lines:repoRoot:limit:)``), with the patch it made to that file or range.
public struct GitHistoryEntry: Equatable, Sendable {
    /// The commit.
    public let commit: GitCommit
    /// Its unified diff for the file (or the range), file headers included; empty when the
    /// commit changed only whitespace and whitespace was ignored.
    public let patch: String

    /// An entry.
    public init(commit: GitCommit, patch: String) {
        self.commit = commit
        self.patch = patch
    }
}
