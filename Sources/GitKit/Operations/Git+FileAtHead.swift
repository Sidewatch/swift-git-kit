//
//  Git+FileAtHead.swift
//  GitKit
//
//  One working-tree file against HEAD: its text there, and the lines it added since.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One working-tree file against `HEAD`, for facts about what a change ADDED (a credential, a
/// destructive statement, a new dependency) rather than what the file holds.
public extension Git {
    /// `file`'s text at `HEAD`, or nil when it is not in `HEAD`, lies outside `root`, or git fails.
    /// The repository-relative path goes through ``relativePathIfUnderRoot(_:root:)``, so a file
    /// reached as `/var/…` under a repo opened as `/private/var/…` (or the other way) still resolves.
    static func headText(of file: URL, repoRoot root: URL) -> String? {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return nil }
        return showFile(revision: "HEAD", path: rel, repoRoot: root)
    }

    /// The 1-based lines of `file` that are new or changed against `HEAD` (``lineChanges(for:repoRoot:)``
    /// keeps the deletions too; these are only the lines a change put there). Empty for a clean file.
    static func addedLines(for file: URL, repoRoot root: URL) -> Set<Int> {
        Set(lineChanges(for: file, repoRoot: root).filter { $0.value == .added || $0.value == .modified }.keys)
    }
}
