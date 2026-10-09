//
//  GitCommitError.swift
//  GitKit
//
//  Why `Git.commit` did not produce a commit.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Why ``Git/commit(entries:message:repoRoot:)`` produced no commit.
public enum GitCommitError: Error, Equatable, Sendable {

    /// A merge, rebase, cherry-pick, revert, bisect or `am` is under way; committing around it
    /// would lose its state or record conflict markers. Finish or abort it in git first.
    case operationInProgress(GitOperation)

    /// No entry was given, or the given entries leave the tree exactly as `HEAD` has it.
    case nothingToCommit

    /// git refused or failed; `stderr` is its own message (a hook's output included).
    case failed(stderr: String)
}
