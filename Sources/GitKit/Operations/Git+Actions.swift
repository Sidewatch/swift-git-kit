//
//  Git+Actions.swift
//  GitKit
//
//  Mutating actions: stage, unstage, and discard.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Staging, unstaging and discarding changes.
public extension Git {

    /// Stages `file` (`git add`). Returns `true` on success.
    ///
    /// Fails (returns `false`) when `file` is not located under `root`.
    @discardableResult
    static func stage(_ file: URL, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        return run(["add", "--", rel], in: root, timeout: longTimeout) != nil
    }

    /// Unstages `file` (`git restore --staged`). Returns `true` on success.
    ///
    /// Fails (returns `false`) when `file` is not located under `root`.
    ///
    /// - Note: Requires an existing `HEAD` (a repository with at least one commit).
    @discardableResult
    static func unstage(_ file: URL, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        return run(["restore", "--staged", "--", rel], in: root, timeout: longTimeout) != nil
    }

    /// Reverts `file` to `HEAD` by `kind`; `true` on success. **Destructive, but undoable.**
    ///
    /// `.untracked` and `.added` go to the Trash (``trashUntracked(_:)``; `.added` also leaves
    /// the index), `.renamed` returns under its old name, anything else is restored from `HEAD`.
    /// Refused (`false`): a file not under `root`, so nothing outside the repository or a
    /// same-named file elsewhere is ever touched; a `.conflicted` file, which has no single
    /// `HEAD` version to return to; and a gitlink (``isGitlink(_:repoRoot:)``), which `restore`
    /// cannot revert and which stands for a whole checkout.
    @discardableResult
    static func discard(_ file: URL, kind: GitChangeKind, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        if kind == .untracked { return trashUntracked(file) != nil }
        guard kind != .conflicted, !isGitlink(rel, repoRoot: root) else { return false }
        if kind == .added { return discardAddition(file, rel: rel, repoRoot: root) }
        // `checkout HEAD -- <path>` requires the pathspec to exist in HEAD, which a rename's NEW
        // path (the path status reports) never does — git exits 1 with "pathspec did not match".
        // `restore --source=HEAD --staged --worktree` reverts every kind uniformly: paths in
        // HEAD are restored, paths absent from HEAD are removed from the index and disk.
        // A rename needs BOTH paths so the old file comes back too.
        var paths = [rel]
        if kind == .renamed, let old = renameSource(of: rel, repoRoot: root) { paths.insert(old, at: 0) }
        return run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths, in: root, timeout: longTimeout) != nil
    }

    /// Moves an untracked FILE to the Trash and returns where it landed; nil when it was not a
    /// file or the Trash refused it — never a permanent delete, so the discard stays undoable.
    ///
    /// A directory (or a symlink to one) is refused: `git status -uall` reports a nested
    /// repository as one `nested/` entry, and discarding it must never become `rm -rf` of a checkout.
    static func trashUntracked(_ file: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return nil }
        var trashed: NSURL?
        do { try FileManager.default.trashItem(at: file, resultingItemURL: &trashed) } catch { return nil }
        return trashed as URL?
    }

    /// Whether `file` is recorded in the index as a gitlink (mode `160000`): a submodule or an
    /// embedded repository, which status lists as one entry and no file-level action can revert.
    static func isGitlink(_ file: URL, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        return isGitlink(rel, repoRoot: root)
    }
}

extension Git {

    /// ``isGitlink(_:repoRoot:)`` for a repository-relative path.
    static func isGitlink(_ rel: String, repoRoot root: URL) -> Bool {
        run(["ls-files", "-s", "--", rel], in: root)?.hasPrefix("160000 ") ?? false
    }

    /// Discards a staged addition: the file goes to the Trash (recoverable, as an untracked
    /// discard is) and its entry leaves the index.
    private static func discardAddition(_ file: URL, rel: String, repoRoot root: URL) -> Bool {
        guard trashUntracked(file) != nil else { return false }
        return run(["rm", "--cached", "-q", "--", rel], in: root, timeout: longTimeout) != nil
    }

    /// The pre-rename (old) path of the staged rename/copy whose new path is `rel`.
    private static func renameSource(of rel: String, repoRoot root: URL) -> String? {
        statusEntries(repoRoot: root).first { $0.path == rel }?.oldPath
    }
}
