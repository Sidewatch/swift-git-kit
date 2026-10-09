//
//  GitScratchIndex.swift
//  GitKit
//
//  A throwaway index file outside the repository, for calls that must not touch the real one.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// A throwaway index file, reached through `GIT_INDEX_FILE`, for the calls that must leave the
/// repository's own index exactly as the user and their agent left it: checkpoint capture, the
/// working-tree checkpoint diff, and a commit of chosen paths.
///
/// It lives outside the repository: `git add -A` into an index inside the tree would commit the
/// real index's own `.lock`. ``remove()`` deletes it and its lock.
struct GitScratchIndex {

    /// Absolute path of the index file; it does not exist until something writes it.
    let path: String

    /// A fresh, unique location in the temporary directory.
    init() {
        path =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("sidewatch-scratch-index-\(UUID().uuidString)").path
    }

    /// The environment that points git at this index.
    var environment: [String: String] { ["GIT_INDEX_FILE": path] }

    /// Copies the repository's index over this one, stat data included — `rev-parse --git-path
    /// index`, which for a linked worktree lies under the common dir, never `.git/index`.
    /// False when the repository has no index yet (nothing was ever added).
    @discardableResult
    func copyIndex(of repoRoot: URL) -> Bool {
        guard let real = Git.run(["rev-parse", "--git-path", "index"], in: repoRoot)?.trimmed, !real.isEmpty else {
            return false
        }
        let source = URL(fileURLWithPath: real, relativeTo: repoRoot).standardizedFileURL
        try? FileManager.default.removeItem(atPath: path)
        return (try? FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: path))) != nil
    }

    /// Fills this index from `tree` (`HEAD`, a checkpoint, the empty tree); false when the tree
    /// cannot be read, as `HEAD` cannot before the first commit.
    @discardableResult
    func read(tree: String, in repoRoot: URL) -> Bool {
        Git.run(["read-tree", tree], in: repoRoot, environment: environment) != nil
    }

    /// Deletes the index file and the lock git may have left beside it.
    func remove() {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + ".lock")
    }
}
