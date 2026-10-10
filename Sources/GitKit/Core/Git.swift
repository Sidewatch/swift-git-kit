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

    /// Seconds a read-only call may run before it is terminated and reported as failed (`nil`).
    public static let defaultTimeout: TimeInterval = 60

    /// Seconds a mutating or network call may run — commit, add, restore, checkpoint capture,
    /// clone, fetch — before it is terminated.
    public static let longTimeout: TimeInterval = 600

    /// Variables every call runs under, whatever the user's configuration says.
    ///
    /// - `GIT_LITERAL_PATHSPECS`: `app/[id]/page.tsx` names that file, not every `app/?/page.tsx`,
    ///   and `:colon.txt` is a path, not pathspec magic. Harmless for every subcommand used here.
    /// - `GIT_OPTIONAL_LOCKS=0`: `git status` must not rewrite `.git/index` on a read — an
    ///   agent's own `git commit` racing that lock fails.
    /// - `GIT_TERMINAL_PROMPT=0`: never hang on a credential prompt nobody can answer.
    /// - `diff.autoRefreshIndex=false` (the env form of `-c`, so raw calls get it too): every
    ///   `git diff` form otherwise refreshes stat-stale entries and writes the index; the user's
    ///   own next git command refreshes it instead. `--name-status` and `--raw` list a stat-stale
    ///   file as `M` under this setting; patch and `--numstat` forms do not.
    /// - `core.fsmonitor=false`: a repository's `core.fsmonitor` names a COMMAND git runs on every
    ///   status and diff to ask what changed. A checkout's own `.git/config` can set it, so a
    ///   status over a cloned repository would run whatever the clone chose; the setting is
    ///   off for every call.
    ///
    /// The env form (`GIT_CONFIG_COUNT` / `KEY_n` / `VALUE_n`) outranks every config file.
    /// Hooks a call runs (`commit`) inherit these; ``environment(hooks:)`` adds the hooks rule.
    static let fixedEnvironment: [String: String] = [
        "GIT_LITERAL_PATHSPECS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "diff.autoRefreshIndex",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.fsmonitor",
        "GIT_CONFIG_VALUE_1": "false",
    ]

    /// ``fixedEnvironment``, with `core.hooksPath=/dev/null` added unless `hooks` is true.
    ///
    /// A repository's hooks are its own executable code: `post-index-change` runs on a `git add`,
    /// `post-checkout` on a restore, and a clone can ship any of them. A read, a stage, a restore
    /// or a checkpoint through this package never runs one. `commit` does — a person expects
    /// their pre-commit hook to run when they commit — so it alone passes `hooks: true`.
    static func environment(hooks: Bool) -> [String: String] {
        guard !hooks else { return fixedEnvironment }
        var env = fixedEnvironment
        env["GIT_CONFIG_COUNT"] = "3"
        env["GIT_CONFIG_KEY_2"] = "core.hooksPath"
        env["GIT_CONFIG_VALUE_2"] = "/dev/null"
        return env
    }

    /// Inherited variables no call may see: a `GIT_DIR` or `GIT_INDEX_FILE` exported by the
    /// launching shell would redirect every call to another repository or index, and the
    /// pathspec and diff overrides would undo ``fixedEnvironment`` and the diff flags.
    static let strippedVariables: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
        "GIT_NAMESPACE", "GIT_DIFF_OPTS", "GIT_EXTERNAL_DIFF", "GIT_CONFIG_PARAMETERS",
        "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS",
    ]

    /// Runs `git <args>` in `dir` and returns standard output.
    ///
    /// - Parameters:
    ///   - args: Arguments passed to `git`, e.g. `["status", "--porcelain=v1"]`.
    ///   - dir: Working directory the command runs in.
    ///   - timeout: Seconds before a still-running call is terminated; ``defaultTimeout`` unless
    ///     the call mutates or talks to a network (``longTimeout``), nil to wait indefinitely.
    /// - Returns: The command's standard output decoded as UTF-8 (lossily: one stray byte in a
    ///   diff does not blank the whole result), or `nil` if the process failed to launch, timed
    ///   out, or exited with a non-zero status.
    public static func run(_ args: [String], in dir: URL, timeout: TimeInterval? = defaultTimeout) -> String? {
        run(args, in: dir, allowedStatuses: [], timeout: timeout)
    }

    /// Runs `git <args>` like ``run(_:in:timeout:)`` but also treats the exit statuses in
    /// `allowedStatuses` as success.
    ///
    /// Some subcommands report a result with a non-zero exit — `git diff --no-index` exits 1
    /// when the inputs differ. Returns standard output, or `nil` outside the allowed statuses.
    public static func run(
        _ args: [String], in dir: URL, allowedStatuses: Set<Int32>, timeout: TimeInterval? = defaultTimeout
    ) -> String? {
        run(args, in: dir, environment: [:], allowedStatuses: allowedStatuses, timeout: timeout)
    }

    /// Runs `git <args>` like ``run(_:in:allowedStatuses:timeout:)`` with `environment` layered
    /// over ``fixedEnvironment`` (e.g. `GIT_INDEX_FILE` for a scratch index — a caller's variable
    /// wins), and `input` written to its stdin. `hooks` lets the repository's hooks run; off
    /// unless the call is the person's own commit (``environment(hooks:)``).
    ///
    /// stderr is dropped; callers want output or `nil`. ``runCapturingError(_:in:environment:timeout:input:hooks:)``
    /// keeps it.
    public static func run(
        _ args: [String], in dir: URL,
        environment: [String: String],
        allowedStatuses: Set<Int32> = [],
        timeout: TimeInterval? = defaultTimeout,
        input: Data? = nil,
        hooks: Bool = false
    ) -> String? {
        let result = runCapturingError(args, in: dir, environment: environment, timeout: timeout, input: input, hooks: hooks)
        guard result.launched, !result.timedOut else { return nil }
        guard result.status == 0 || allowedStatuses.contains(result.status) else { return nil }
        return result.stdout
    }

    /// Runs `git <args>` and returns everything it produced, decoded.
    ///
    /// For the calls whose failure the user must read in git's own words (a commit refused by a
    /// hook). Launches through `launch`, the one place `git` starts: ``ProcessRunner`` drains
    /// stdout and stderr concurrently, since an undrained stderr pipe deadlocks once git writes
    /// ~64 KB of warnings.
    public static func runCapturingError(
        _ args: [String], in dir: URL,
        environment: [String: String] = [:],
        timeout: TimeInterval? = defaultTimeout,
        input: Data? = nil,
        hooks: Bool = false
    ) -> GitRunResult {
        let result = launch(args, in: dir, environment: environment, timeout: timeout, input: input, hooks: hooks)
        return GitRunResult(
            status: result.status,
            stdout: String(decoding: result.stdout, as: UTF8.self),
            stderr: String(decoding: result.stderr, as: UTF8.self),
            timedOut: result.timedOut)
    }

    /// Runs `git <args>` like ``run(_:in:environment:allowedStatuses:timeout:input:hooks:)`` and
    /// returns standard output as BYTES, undecoded — for output that carries file contents
    /// (`cat-file --batch`). `nil` when git failed to launch, timed out or exited non-zero.
    static func runData(_ args: [String], in dir: URL, timeout: TimeInterval? = defaultTimeout, input: Data? = nil) -> Data? {
        let result = launch(args, in: dir, environment: [:], timeout: timeout, input: input, hooks: false)
        guard result.status == 0, !result.timedOut else { return nil }
        return result.stdout
    }

    /// The single place `git` launches: through ``ProcessRunner``, which drains stdout and stderr
    /// concurrently, under ``environment(hooks:)`` with ``strippedVariables`` removed and
    /// `environment` layered last.
    private static func launch(
        _ args: [String], in dir: URL, environment: [String: String], timeout: TimeInterval?, input: Data?, hooks: Bool
    ) -> ProcessRunner.Result {
        ProcessRunner.run(
            executable, args,
            directory: dir,
            input: input,
            environment: Self.environment(hooks: hooks).merging(environment) { _, caller in caller },
            removing: strippedVariables,
            timeout: timeout)
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
    /// Falls back to the file's last path component when `file` is not located under `root`.
    /// No operation in this package uses the fallback: reads (``lineDiff(for:repoRoot:)``,
    /// ``blame(for:line:repoRoot:)``) and mutations alike go through
    /// ``relativePathIfUnderRoot(_:root:)`` and refuse a file outside `root` instead of guessing
    /// a pathspec. Kept for callers that want a display name.
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
