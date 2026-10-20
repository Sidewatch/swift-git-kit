//
//  DiffFileSummary.swift
//  GitKit
//
//  One file's chunk of a diff, summarised: its path, its line counts, how it changed.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One file's chunk of a diff, summarised (``DiffChunks/summary(of:)``).
public struct DiffFileSummary: Equatable, Sendable {
    /// The repository-relative path (the new path for a rename, the old one for a deletion).
    public let path: String
    /// Added lines inside its hunks.
    public let insertions: Int
    /// Removed lines inside its hunks.
    public let deletions: Int
    /// How the file changed.
    public let kind: DiffFileKind

    /// A summary.
    public init(path: String, insertions: Int, deletions: Int, kind: DiffFileKind) {
        self.path = path
        self.insertions = insertions
        self.deletions = deletions
        self.kind = kind
    }
}
