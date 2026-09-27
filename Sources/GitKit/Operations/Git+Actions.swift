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
        return run(["add", "--", rel], in: root) != nil
    }

    /// Unstages `file` (`git restore --staged`). Returns `true` on success.
    ///
    /// Fails (returns `false`) when `file` is not located under `root`.
    ///
    /// - Note: Requires an existing `HEAD` (a repository with at least one commit).
    @discardableResult
    static func unstage(_ file: URL, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        return run(["restore", "--staged", "--", rel], in: root) != nil
    }

    /// Reverts `file` to `HEAD` by `kind`; `true` on success. **Destructive.**
    ///
    /// `.untracked` goes to the Trash (``trashUntracked(_:)``), `.added` leaves the index and
    /// disk, `.renamed` returns under its old name, anything else is restored from `HEAD`. Every
    /// kind — untracked included — is refused when `file` is not under `root`, so nothing outside
    /// the repository or a same-named file elsewhere is ever touched.
    @discardableResult
    static func discard(_ file: URL, kind: GitChangeKind, repoRoot root: URL) -> Bool {
        guard let rel = relativePathIfUnderRoot(file, root: root) else { return false }
        if kind == .untracked { return trashUntracked(file) != nil }
        // `checkout HEAD -- <path>` requires the pathspec to exist in HEAD, which a
        // staged-new file and a rename's NEW path (the path status reports) never
        // do — git exits 1 with "pathspec did not match". `restore --source=HEAD
        // --staged --worktree` reverts every kind uniformly: paths in HEAD are
        // restored, paths absent from HEAD are removed from the index and disk.
        // A rename needs BOTH paths so the old file comes back too.
        var paths = [rel]
        if kind == .renamed, let old = renameSource(of: rel, repoRoot: root) { paths.insert(old, at: 0) }
        return run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + paths, in: root) != nil
    }

    /// Moves an untracked FILE to the Trash and returns where it landed; nil when it was not a
    /// file or the Trash refused it — never a permanent delete, so the discard stays undoable.
    ///
    /// A directory (or a symlink to one) is refused: `git status -uall` reports a nested
    /// repository as one `nested/` entry, and discarding it must never become `rm -rf` of a checkout.
    static func trashUntracked(_ file: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        var trashed: NSURL?
        do { try FileManager.default.trashItem(at: file, resultingItemURL: &trashed) } catch { return nil }
        return trashed as URL?
    }

    /// The pre-rename (old) path of the staged rename/copy whose new path is
    /// `rel`, from `git status --porcelain=v1 -z` (the old path is the entry's
    /// extra NUL-terminated field, which ``status(repoRoot:)`` skips).
    private static func renameSource(of rel: String, repoRoot root: URL) -> String? {
        guard let out = run(["status", "--porcelain=v1", "-z"], in: root) else { return nil }
        let fields = out.split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < fields.count {
            let entry = String(fields[i])
            i += 1
            guard entry.count >= 4 else { continue }
            let code = entry.prefix(2)
            guard code.contains("R") || code.contains("C") else { continue }
            let newPath = String(entry.dropFirst(3))
            guard i < fields.count else { return nil }
            let old = String(fields[i])
            i += 1
            if newPath == rel { return old }
        }
        return nil
    }
}
