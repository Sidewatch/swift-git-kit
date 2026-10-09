//
//  GitStatusEntry.swift
//  GitKit
//
//  One changed path from `git status`, with the old path of a rename or copy.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One changed path from ``Git/statusEntries(repoRoot:)``.
public struct GitStatusEntry: Hashable, Sendable {

    /// The repository-relative path — the NEW path of a rename or copy.
    public let path: String

    /// What happened to it.
    public let kind: GitChangeKind

    /// The path a rename or copy came from; nil for every other kind.
    public let oldPath: String?

    /// Creates an entry. Normally produced by ``Git/statusEntries(repoRoot:)``; public for fixtures.
    public init(path: String, kind: GitChangeKind, oldPath: String? = nil) {
        self.path = path
        self.kind = kind
        self.oldPath = oldPath
    }
}
