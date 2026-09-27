//
//  GitHubCLI.swift
//  GitKit
//
//  Thin, best-effort wrapper around the GitHub CLI (`gh`).
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import ProcessRunner

/// Thin, best-effort wrapper around the GitHub CLI (`gh`). Deliberately minimal and OPTIONAL:
/// it opens a pull-request page in the browser and tells you whether `gh` exists — it never
/// authors a PR body, never merges. If `gh` isn't installed, every call degrades gracefully.
public enum GitHubCLI {
    /// Where `gh` might live. A sandboxed or GUI process often has a bare PATH, so the common
    /// Homebrew and system locations are probed directly before falling back to `which`.
    public static let candidatePaths = [
        "/opt/homebrew/bin/gh",  // Apple Silicon Homebrew
        "/usr/local/bin/gh",  // Intel Homebrew
        "/usr/bin/gh",
        "/run/current-system/sw/bin/gh",  // nix
    ]

    /// Absolute path to `gh`, or nil if it can't be found.
    public static func executablePath(
        candidates: [String] = candidatePaths,
        which: (String) -> String? = ProcessRunner.which
    ) -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) { return path }
        return which("gh")
    }

    /// Whether `gh` is available on this machine.
    public static var isAvailable: Bool { executablePath() != nil }

    /// Opens the branch's EXISTING pull request in the browser (`gh pr view --web`). Blocking.
    ///
    /// Never falls back to `gh pr create --web`: authoring a pull request belongs to the agent in
    /// the terminal, which can write it from the work it just did. False when `gh` is missing,
    /// the branch has no pull request, or the command failed.
    @discardableResult
    public static func openPullRequestInBrowser(cwd: URL) -> Bool {
        guard let gh = executablePath() else { return false }
        return ProcessRunner.run(gh, ["pr", "view", "--web"], directory: cwd).succeeded
    }
}
