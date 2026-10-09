//
//  Git+Commit.swift
//  GitKit
//
//  A commit of chosen paths that leaves the rest of the index as it was.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Committing a chosen set of changed paths.
public extension Git {

    /// Commits exactly `entries` — each path as it stands in the working tree, a rename with
    /// both of its paths — with `message`, and returns the new `HEAD`.
    ///
    /// The commit is built in a scratch index seeded from `HEAD` (the empty tree before the
    /// first commit): the real index is read only to sync the committed paths afterwards
    /// (`git reset -- <paths>`), so a partial staging of a path that was NOT chosen survives
    /// untouched. `git commit` itself runs, so hooks and `commit.gpgsign` apply as configured;
    /// a refusal comes back as ``GitCommitError/failed(stderr:)`` in git's own words.
    ///
    /// Refused: while a merge, rebase, cherry-pick, revert, bisect or `am` is under way
    /// (``GitCommitError/operationInProgress(_:)`` — a commit around it would drop `MERGE_HEAD` or
    /// record conflict markers); a path that is a directory, as a nested repository is (a
    /// gitlink is never created by accident); and a set of entries that changes nothing.
    static func commit(entries: [GitStatusEntry], message: String, repoRoot root: URL) -> Result<String, GitCommitError> {
        if let operation = inProgressOperation(repoRoot: root) { return .failure(.operationInProgress(operation)) }
        let paths = commitPaths(of: entries)
        guard !paths.isEmpty else { return .failure(.nothingToCommit) }
        if let directory = paths.first(where: { isDirectory(root.appendingPathComponent($0)) }) {
            return .failure(.failed(stderr: "\(directory) is a directory, not a file; a nested repository is not committed as one entry"))
        }
        let scratch = GitScratchIndex()
        defer { scratch.remove() }
        let base = diffBase(repoRoot: root)
        guard scratch.read(tree: base, in: root) else { return .failure(.failed(stderr: "could not read \(base) into the commit index")) }
        if case .failure(let error) = stage(paths, into: scratch, base: base, repoRoot: root) { return .failure(error) }

        // The one call that runs the repository's hooks: a person committing expects their
        // pre-commit hook to run. The stage and the sync around it run none.
        let commit = runCapturingError(
            ["commit", "-q", "-m", message], in: root, environment: scratch.environment, timeout: longTimeout, hooks: true)
        guard commit.succeeded else { return .failure(.failed(stderr: commit.message)) }
        _ = run(["reset", "-q", "--"] + paths, in: root, timeout: longTimeout)
        guard let head = run(["rev-parse", "HEAD"], in: root)?.trimmed, !head.isEmpty else {
            return .failure(.failed(stderr: "committed, but HEAD could not be read back"))
        }
        return .success(head)
    }
}

extension Git {

    /// Every path the commit touches — each entry's path and, for a rename or copy, its old
    /// path — in order, once each.
    private static func commitPaths(of entries: [GitStatusEntry]) -> [String] {
        var seen = Set<String>()
        return entries.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) }.filter { seen.insert($0).inserted }
    }

    /// Whether `url` is a directory itself (a symlink to one is a symlink, which git stores as such).
    private static func isDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }

    /// `git add -- <paths>` into `scratch`, then a check that the index now differs from `base`.
    ///
    /// A path gone from disk and absent from `base` has nothing to record, and `add` would refuse
    /// its pathspec outright, so such paths are left out; a path gone from disk but in `base`
    /// is added so its deletion is recorded.
    private static func stage(
        _ paths: [String], into scratch: GitScratchIndex, base: String, repoRoot root: URL
    ) -> Result<Void, GitCommitError> {
        let addable = paths.filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
        let missing = paths.filter { !addable.contains($0) }
        let known = missing.isEmpty ? [] : knownPaths(missing, in: scratch, repoRoot: root)
        let staged = addable + missing.filter(known.contains)
        if !staged.isEmpty {
            let add = runCapturingError(["add", "--"] + staged, in: root, environment: scratch.environment, timeout: longTimeout)
            guard add.succeeded else { return .failure(.failed(stderr: add.message)) }
        }
        let changed = runCapturingError(["diff-index", "--cached", "--quiet", base], in: root, environment: scratch.environment)
        switch changed.status {
        case 1: return .success(())  // differs from `base`: there is something to commit
        case 0: return .failure(.nothingToCommit)
        default: return .failure(.failed(stderr: changed.message))
        }
    }

    /// The subset of `paths` recorded in `scratch`.
    private static func knownPaths(_ paths: [String], in scratch: GitScratchIndex, repoRoot root: URL) -> Set<String> {
        let out = run(["ls-files", "-z", "--"] + paths, in: root, environment: scratch.environment) ?? ""
        return Set(out.split(separator: "\0").map(String.init))
    }
}
