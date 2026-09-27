//
//  Git.swift
//  GitKit
//
//  The `Git` namespace and its low-level process/path primitives.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import ProcessRunner
import FoundationExtensions
/// A thin wrapper over the `git` command-line tool: a caseless namespace of static calls
/// (status, diff, blame, staging, worktrees, checkpoints).
///
/// Every call shells out to ``executable`` synchronously; when scanning a whole repository,
/// run them off the main queue. No libgit2 — a working `git` must be installed at ``executable``.
public enum Git {

    /// Absolute path to the `git` executable used for every invocation; `/usr/bin/git` by default.
    ///
    /// Lock-guarded: background `git` calls read it while the main thread may set it, and an
    /// unsynchronized `String` swap racing a read is a memory-safety problem, not a stale path.
    public static var executable: String {
        get { lock.lock(); defer { lock.unlock() }; return storedExecutable }
        set { lock.lock(); defer { lock.unlock() }; storedExecutable = newValue }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedExecutable = "/usr/bin/git"

    /// Runs `git <args>` in `dir` and returns standard output.
    ///
    /// - Parameters:
    ///   - args: Arguments passed to `git`, e.g. `["status", "--porcelain=v1"]`.
    ///   - dir: Working directory the command runs in.
    /// - Returns: The command's standard output decoded as UTF-8, or `nil` if the
    ///   process failed to launch or exited with a non-zero status.
    public static func run(_ args: [String], in dir: URL) -> String? {
        run(args, in: dir, allowedStatuses: [])
    }

    /// Runs `git <args>` like ``run(_:in:)`` but also treats the exit statuses in
    /// `allowedStatuses` as success.
    ///
    /// Some subcommands report a result with a non-zero exit — `git diff --no-index` exits 1
    /// when the inputs differ. Returns standard output, or `nil` outside the allowed statuses.
    public static func run(_ args: [String], in dir: URL, allowedStatuses: Set<Int32>) -> String? {
        run(args, in: dir, environment: [:], allowedStatuses: allowedStatuses)
    }

    /// Runs `git <args>` like ``run(_:in:allowedStatuses:)`` with `environment` layered over the
    /// inherited one (e.g. `GIT_INDEX_FILE` for a scratch index) — the single place `git` launches.
    ///
    /// Goes through ``ProcessRunner``, which drains stdout and stderr concurrently: an undrained
    /// stderr pipe deadlocks once git writes ~64 KB of warnings. stderr is then dropped; callers
    /// want output or `nil`.
    public static func run(
        _ args: [String], in dir: URL,
        environment: [String: String],
        allowedStatuses: Set<Int32> = []
    ) -> String? {
        let result = ProcessRunner.run(
            executable, args,
            directory: dir,
            environment: environment)
        guard result.launched else { return nil }
        guard result.status == 0 || allowedStatuses.contains(result.status) else { return nil }
        return result.outputText
    }

    /// The repository root containing `dir`, or `nil` if `dir` is not inside a git repo.
    ///
    /// - Parameter dir: A file or directory URL. If a file is passed, its parent
    ///   directory is searched.
    public static func repoRoot(for dir: URL) -> URL? {
        let base = dir.hasDirectoryPath ? dir : dir.deletingLastPathComponent()
        guard
            let out = run(["rev-parse", "--show-toplevel"], in: base)?
                .trimmed, !out.isEmpty
        else { return nil }
        return URL(fileURLWithPath: out)
    }

    /// Every git repository strictly BELOW `root` (a directory holding a `.git` directory or
    /// file), walking no deeper than `maxDepth`, skipping `.git` and any `skipping` name; at most
    /// `limit` results, in walk order. `root`'s own repo is ``repoRoot(for:)``'s job.
    ///
    /// For folders that are not a repo but hold checkouts (a WordPress site's plugins). A repo
    /// inside a repo is still returned: its own status is the truth for its files. Walks the disk.
    public static func nestedRepoRoots(
        under root: URL, skipping skip: Set<String>,
        maxDepth: Int = 6, limit: Int = 64
    ) -> [URL] {
        let fm = FileManager.default
        guard
            let en = fm.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants])
        else { return [] }
        let rootPath = root.standardizedFileURL.path
        var out: [URL] = []
        for case let url as URL in en {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if name == ".git" {
                let owner = url.deletingLastPathComponent()
                if owner.standardizedFileURL.path != rootPath { out.append(owner) }
                if isDir { en.skipDescendants() }
                if out.count >= limit { break }
                continue
            }
            guard isDir else { continue }
            if skip.contains(name) || en.level >= maxDepth { en.skipDescendants() }
        }
        return out
    }

    /// The path of `file` relative to the repository `root`.
    ///
    /// Falls back to the file's last path component when `file` is not located
    /// under `root`. Mutating operations (stage/unstage/discard) never use the
    /// fallback — they refuse to act on files outside `root` instead of guessing
    /// a pathspec (see ``relativePathIfUnderRoot(_:root:)``).
    public static func relativePath(_ file: URL, root: URL) -> String {
        relativePathIfUnderRoot(file, root: root) ?? file.lastPathComponent
    }

    /// The path of `file` relative to `root`, or `nil` when `file` is not under `root`.
    ///
    /// Compares standardized paths, then canonical ones (``canonicalPath(_:)``), so a deleted
    /// file under `/var` ↔ `/private/var` still matches. Use this, not ``relativePath(_:root:)``,
    /// for paths that may come from outside the repo: an out-of-root file is refused rather than
    /// collapsed to a basename that could match an unrelated file.
    public static func relativePathIfUnderRoot(_ file: URL, root: URL) -> String? {
        func relative(_ f: String, _ r: String) -> String? {
            f.hasPrefix(r + "/") ? String(f.dropFirst(r.count + 1)) : nil
        }
        if let rel = relative(file.standardizedFileURL.path, root.standardizedFileURL.path) {
            return rel
        }
        return relative(canonicalPath(file), canonicalPath(root))
    }

    /// Canonicalizes `url` even when it no longer exists on disk: resolves
    /// symlinks over the longest existing prefix (which strips macOS's
    /// `/private` designator), then re-appends the nonexistent tail verbatim.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            tail.append(existing.lastPathComponent)
            existing = existing.deletingLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for component in tail.reversed() { resolved.appendPathComponent(component) }
        return resolved.path
    }
}
