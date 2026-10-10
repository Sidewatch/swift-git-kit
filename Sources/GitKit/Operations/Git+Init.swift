//
//  Git+Init.swift
//  GitKit
//
//  Starting a repository: `git init` in a folder, with git's own words when it fails.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Starting a new repository.
public extension Git {

    /// Runs `git init` in `dir`, making it a repository of its own, even inside another
    /// checkout. Blocking — call off the main thread.
    ///
    /// The fixed environment applies (no prompts, inherited `GIT_DIR` and friends dropped), so
    /// the repository is made in `dir` and nowhere else. The person's `init.defaultBranch` and
    /// template directory are honoured, as `git init` in a terminal would.
    ///
    /// - Returns: The run's result: ``GitRunResult/succeeded`` on success, else git's `stderr`
    ///   (``GitRunResult/launched`` is false when git, or `dir`, was not there to run in).
    @discardableResult
    static func initRepository(at dir: URL) -> GitRunResult {
        runCapturingError(["init", "--quiet"], in: dir)
    }
}
