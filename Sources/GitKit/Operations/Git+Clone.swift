//
//  Git+Clone.swift
//  GitKit
//
//  The outcome of a clone: the created directory on success, or git's error text.
//
//  Created by David Sherlock on 7/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions
import ProcessRunner

/// Cloning a remote repository.
public extension Git {

    /// The outcome of a clone: the created directory on success, or git's error text.
    struct CloneResult: Equatable, Sendable {
        /// The cloned directory, or nil when the clone failed.
        public let path: URL?
        /// git's error text when the clone failed.
        public let error: String?
        /// Whether the clone produced a directory.
        public var succeeded: Bool { path != nil }
    }

    /// Clones `url` into `parent` (under `name`, or git's default directory name).
    ///
    /// Blocking and network-bound — call OFF the main thread. Unlike ``run(_:in:)`` this
    /// captures git's stderr so a failure (bad URL, auth, network) surfaces a real message.
    ///
    /// - Returns: `.path` = the cloned directory on success; `.error` = git's stderr otherwise.
    static func clone(from url: String, into parent: URL, name: String? = nil) -> CloneResult {
        var args = ["clone", url]
        let trimmedName = name?.trimmed
        if let trimmedName, !trimmedName.isEmpty { args.append(trimmedName) }

        let result = ProcessRunner.run(executable, args, directory: parent, augmentPATH: false)
        guard result.launched else {
            return CloneResult(
                path: nil,
                error: String(
                    localized: "Couldn't launch git.", bundle: .module,
                    comment: "Clone Failed alert: the git program could not be started"))
        }
        guard result.succeeded else {
            let text = result.errorText.trimmed
            return CloneResult(
                path: nil,
                error: text.isEmpty
                    ? String(
                        localized: "git clone failed (exit \(result.status))", bundle: .module,
                        comment: "Clone Failed alert when git printed nothing; the number is git's exit status")
                    : text)
        }
        let dir = (trimmedName?.isEmpty == false ? trimmedName! : defaultCloneDirectoryName(for: url))
        return CloneResult(path: parent.appendingPathComponent(dir), error: nil)
    }

    /// The directory `git clone <url>` creates by default: the last path component of the
    /// URL, minus a trailing `.git`. Handles both `https://…/owner/repo.git` and scp-style
    /// `git@host:owner/repo.git`. Pure — covered by `GitCloneTests`.
    static func defaultCloneDirectoryName(for url: String) -> String {
        var s = url.trimmed
        while s.hasSuffix("/") { s.removeLast() }
        // Take everything after the last "/" or ":" (scp form has no slash before the repo).
        if let cut = s.lastIndex(where: { $0 == "/" || $0 == ":" }) {
            s = String(s[s.index(after: cut)...])
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        return s.isEmpty ? "repository" : s
    }
}
