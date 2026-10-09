//
//  Git+Status.swift
//  GitKit
//
//  Working-tree status of changed files.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Working-tree status.
public extension Git {

    /// Working-tree changes versus `HEAD`, one entry per changed path, in git's order.
    ///
    /// `-z` keeps paths verbatim (no C-style quoting); `-uall` lists each untracked file rather
    /// than collapsing a new directory to `dir/`. A rename or copy reports its new path with
    /// ``GitStatusEntry/oldPath`` set. The kind follows the `XY` code (see
    /// ``GitChangeKind/conflicted`` for the conflict codes): a file deleted from the working tree
    /// is ``GitChangeKind/deleted`` whatever was staged for it (`AD`, `MD`, `RD`).
    static func statusEntries(repoRoot root: URL) -> [GitStatusEntry] {
        guard let out = run(["status", "--porcelain=v1", "-z", "-uall"], in: root) else { return [] }
        return PorcelainStatusParser.entries(out)
    }

    /// ``statusEntries(repoRoot:)`` as repository-relative `(path, kind)` pairs.
    static func status(repoRoot root: URL) -> [(path: String, kind: GitChangeKind)] {
        statusEntries(repoRoot: root).map { (path: $0.path, kind: $0.kind) }
    }
}
