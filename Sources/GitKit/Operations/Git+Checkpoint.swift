//
//  Git+Checkpoint.swift
//  GitKit
//
//  Non-destructive snapshots of the working tree, so a range of edits can be diffed exactly
//  rather than inferred.
//
//  Created by David Sherlock on 7/25/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// Checkpoints: whole-tree snapshots as anchored dangling commits, diffed to see what a turn changed.
public extension Git {

    /// The ref namespace checkpoints are anchored under.
    ///
    /// Namespaced away from `refs/heads` and `refs/tags` so checkpoints never appear in
    /// `git branch`, `git tag`, or a branch picker — they are Sidewatch bookkeeping, invisible
    /// to normal use of the repo.
    static var checkpointRefPrefix: String { "refs/sidewatch/checkpoints/" }

    /// Captures the whole working tree (honouring `.gitignore`) as a dangling commit parented on
    /// `HEAD`, **without touching the working tree, the index, or the stash list**; nil on failure.
    ///
    /// Built through a scratch index (``GitScratchIndex``) seeded with a copy of the real one,
    /// so `git add -A` re-hashes only the files whose stat data changed and keeps a
    /// tracked-but-ignored file (one committed before its path was ignored — `.vscode/settings.json`,
    /// a checked-in `dist/`), which `add` into an empty index would skip, leaving it a phantom
    /// deletion in every checkpoint. A conflicted index copies fine: `add -A` resolves each entry
    /// to the working tree. A repository with no index yet starts empty, which is right.
    /// The commit is unreferenced — pass it to ``anchorCheckpoint(_:id:repoRoot:)`` before
    /// `git gc` prunes it.
    static func createCheckpoint(repoRoot: URL) -> String? {
        let scratch = GitScratchIndex()
        defer { scratch.remove() }
        if !scratch.copyIndex(of: repoRoot) { scratch.read(tree: "HEAD", in: repoRoot) }

        // `--ignore-errors` (exit 1) carries on past a file git cannot read or a nested
        // repository with no commit; the tree is written without them instead of not at all.
        guard
            run(
                ["add", "-A", "--ignore-errors"], in: repoRoot, environment: scratch.environment,
                allowedStatuses: [1], timeout: longTimeout) != nil,
            let tree = trimmed(run(["write-tree"], in: repoRoot, environment: scratch.environment, timeout: longTimeout))
        else { return nil }

        // An identity is required to write a commit object, and the repo may not configure one
        // (or may configure one we shouldn't borrow). These -c flags apply to this call only.
        var args = [
            "-c", "user.name=Sidewatch", "-c", "user.email=checkpoint@sidewatch.local",
            "commit-tree", tree, "-m", "sidewatch checkpoint",
        ]
        // Parent on HEAD when there is one — a repository with no commits yet has none, and
        // passing `-p` with an empty value fails outright.
        if let head = trimmed(run(["rev-parse", "HEAD"], in: repoRoot)) { args += ["-p", head] }
        return trimmed(run(args, in: repoRoot, timeout: longTimeout))
    }

    /// Anchors `commit` at ``checkpointRefPrefix`` + `id` so git's own `gc` cannot prune it;
    /// `true` when the ref was written.
    @discardableResult
    static func anchorCheckpoint(_ commit: String, id: String, repoRoot: URL) -> Bool {
        guard let id = sanitizedCheckpointID(id) else { return false }
        return run(["update-ref", checkpointRefPrefix + id, commit], in: repoRoot) != nil
    }

    /// Drops a checkpoint's anchor, making its commit collectable again.
    ///
    /// - Parameters:
    ///   - id: The checkpoint identifier passed to ``anchorCheckpoint(_:id:repoRoot:)``.
    ///   - repoRoot: The repository holding the ref.
    /// - Returns: `true` when the ref was removed.
    @discardableResult
    static func removeCheckpoint(id: String, repoRoot: URL) -> Bool {
        guard let id = sanitizedCheckpointID(id) else { return false }
        return run(["update-ref", "-d", checkpointRefPrefix + id], in: repoRoot) != nil
    }

    /// Every anchored checkpoint, oldest ref first.
    ///
    /// - Parameter repoRoot: The repository to list.
    /// - Returns: Pairs of checkpoint id and commit SHA.
    static func checkpoints(repoRoot: URL) -> [(id: String, commit: String)] {
        guard
            let out = run(
                ["for-each-ref", "--format=%(refname)%09%(objectname)", checkpointRefPrefix],
                in: repoRoot)
        else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2, parts[0].hasPrefix(checkpointRefPrefix) else { return nil }
            return (String(parts[0].dropFirst(checkpointRefPrefix.count)), parts[1])
        }
    }

    /// The unified diff from checkpoint `from` to `to`, or to the **live working tree** when `to`
    /// is nil (a turn still in progress), optionally narrowed to one repo-relative `path`.
    /// Empty when nothing changed, nil on failure.
    ///
    /// The working-tree comparison is ``workingTreeDiff(repoRoot:from:paths:nameStatus:)``: one
    /// process through a scratch index, untracked files included, and the real index never
    /// written — nothing is hashed into a throwaway commit on every refresh.
    static func checkpointDiff(
        from: String, to: String?, path: String? = nil, repoRoot: URL, ignoringWhitespace: Bool = false
    ) -> String? {
        let paths = path.map { [$0] } ?? []
        guard let target = to else {
            return workingTreeDiff(repoRoot: repoRoot, from: from, paths: paths, ignoringWhitespace: ignoringWhitespace)
        }
        return run(
            GitDiffFlags.quotePathOff + ["diff"] + GitDiffFlags.patch(ignoringWhitespace: ignoringWhitespace) + [from, target]
                + (paths.isEmpty ? [] : ["--"] + paths),
            in: repoRoot)
    }

    /// The repo-relative files changed from checkpoint `from` to `to` (or the live working tree
    /// when nil), with their kind, in git's order — what a turn actually touched, not what the
    /// transcript says it touched. A rename is reported under its new path.
    ///
    /// The working-tree comparison is ``workingTreeChangedFiles(repoRoot:from:paths:)``: a file
    /// the checkpoint captured while untracked, unchanged since, is not reported, where a diff
    /// against the real index read it as `D` and then re-added it as untracked.
    static func checkpointChangedFiles(
        from: String, to: String?,
        repoRoot: URL
    ) -> [(path: String, kind: GitChangeKind)] {
        let entries: [GitStatusEntry]
        if let target = to {
            let out = run(GitDiffFlags.quotePathOff + ["diff", "--name-status", "-z", from, target], in: repoRoot)
            entries = NameStatusParser.entries(out ?? "")
        } else {
            entries = workingTreeChangedFiles(repoRoot: repoRoot, from: from)
        }
        return entries.map { (path: $0.path, kind: $0.kind) }
    }

    /// Drops the oldest anchors, keeping the `keeping` (at least 0) newest by commit time, and
    /// returns the dropped ids. Each checkpoint pins a whole tree, so they must not accumulate.
    @discardableResult
    static func pruneCheckpoints(keeping: Int, repoRoot: URL) -> [String] {
        // Newest first, so everything past the keep count is the tail to drop.
        guard
            let out = run(
                [
                    "for-each-ref", "--sort=-committerdate", "--format=%(refname)",
                    checkpointRefPrefix,
                ], in: repoRoot)
        else { return [] }
        let refs = out.split(separator: "\n").map(String.init)
        let doomed = refs.dropFirst(max(0, keeping))
        var dropped: [String] = []
        for ref in doomed where run(["update-ref", "-d", ref], in: repoRoot) != nil {
            dropped.append(String(ref.dropFirst(checkpointRefPrefix.count)))
        }
        return dropped
    }
}

extension Git {

    /// `out` stripped of surrounding whitespace, or `nil` when it is absent or empty.
    private static func trimmed(_ out: String?) -> String? {
        guard let s = out?.trimmed, !s.isEmpty else { return nil }
        return s
    }

    /// `id` reduced to characters that are safe in a ref name, or `nil` when nothing survives.
    ///
    /// Ids reach here from transcript-derived turn identifiers, so they are not trusted to be
    /// ref-safe: git rejects a ref containing a space, `~`, `^`, `:`, `?`, `*`, `[`, `\`, or a
    /// `..` sequence, and a crafted one could otherwise escape the namespace entirely.
    private static func sanitizedCheckpointID(_ id: String) -> String? {
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        let joined = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return joined.isEmpty ? nil : joined
    }
}
