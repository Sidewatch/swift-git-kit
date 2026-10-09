//
//  GitStatusMap.swift
//  GitKit
//
//  A snapshot of `git status` shaped for O(1) per-row lookups by a file tree or a tab bar:
//  absolute file path → change kind, plus the set of every ancestor directory of a changed file
//  (so a collapsed folder can show a "contains changes" dot).
//
//  Created by David Sherlock on 7/19/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A snapshot of `git status` shaped for O(1) per-row lookups by a file tree or tab bar:
/// absolute path → change kind, plus every ancestor directory of a changed file (for a
/// collapsed folder's "contains changes" dot).
///
/// Build it off-main from ``Git/status(repoRoot:)``. Keys are inserted under every alias of the
/// repo root (standardized, symlink-resolved, `/private`-prefixed, plus any the caller passes —
/// the folder the person opened through a symlink) so an aliased row path never misses.
///
/// A deleted file keeps its ``GitChangeKind/deleted`` entry — a tab or an Open Editors row for a
/// file that is gone wants to say so — and dots its ancestors, while ``changedFilePaths`` leaves
/// it out: that list is a search scope, and a deleted file has no text to search.
///
/// Lookups fall back to a case-insensitive match when the exact path misses. The working tree
/// is usually on a case-insensitive volume (APFS by default), where `mv Foo.ts foo.ts` leaves
/// git reporting `Foo.ts` while the tree lists `foo.ts`. On a case-sensitive volume two files
/// that differ only in case can both exist; the fallback then tints the clean twin of a changed
/// file — a rare false positive accepted for the common volume's benefit.
public struct GitStatusMap: Equatable, Sendable {

    /// The map with no changed files.
    public static let empty = GitStatusMap(kinds: [:], changedDirs: [], canonicalPaths: [])

    /// Absolute file path → change kind.
    private let kinds: [String: GitChangeKind]
    /// `kinds` keyed by the lowercased path, consulted only when the exact lookup misses.
    private let foldedKinds: [String: GitChangeKind]
    /// Absolute path of every directory containing (at any depth) a changed file.
    private let changedDirs: Set<String>
    /// ONE path per changed file (the standardized-root alias). Must be used for any file
    /// LIST: `kinds` holds each file under every root alias, so listing its keys doubles files.
    private let canonicalPaths: [String]

    init(kinds: [String: GitChangeKind], changedDirs: Set<String>, canonicalPaths: [String]) {
        self.kinds = kinds
        self.foldedKinds = Dictionary(kinds.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.changedDirs = changedDirs
        self.canonicalPaths = canonicalPaths
    }

    /// The change kind for a file URL, or nil when the file is unchanged. Exact first, then
    /// case-insensitive (see the type note).
    public func kind(for url: URL) -> GitChangeKind? {
        guard !kinds.isEmpty else { return nil }
        let path = url.standardizedFileURL.path
        return kinds[path] ?? foldedKinds[path.lowercased()]
    }

    /// Absolute paths of every changed file that still exists — the "search the agent's
    /// changes" scope, so deleted files are left out. Sorted so consumers get a stable order.
    public var changedFilePaths: [String] { canonicalPaths }

    /// Whether the directory at `url` contains (at any depth) a changed file.
    public func directoryContainsChanges(_ url: URL) -> Bool {
        !changedDirs.isEmpty && changedDirs.contains(url.standardizedFileURL.path)
    }

    /// Builds the lookup from repo-relative `git status` paths. Runs off-main (touches disk to
    /// resolve the repo root's symlink aliases once per build, and to tell a submodule entry —
    /// a path that is a directory — from a file).
    ///
    /// `aliases` are further paths the repo root is known by: the folder the person opened
    /// when it reaches the repo through a symlink git resolved away.
    public static func build(status: [(path: String, kind: GitChangeKind)], repoRoot: URL, aliases: [URL] = []) -> GitStatusMap {
        guard !status.isEmpty else { return .empty }
        let roots = rootAliases(of: repoRoot, extra: aliases)
        var kinds: [String: GitChangeKind] = [:]
        var dirs: Set<String> = []
        let canonicalRoot = repoRoot.standardizedFileURL.path
        var canonical: [String] = []
        for entry in status {
            // Without `-uall`, `git status` collapses an untracked directory to one
            // trailing-slash entry ("?? NewFeature/"); a submodule pointer bump is ` M sub`
            // with no slash but names a directory. Neither is a file: the folder gets a dot.
            let isDirEntry = entry.path.hasSuffix("/") || isDirectory(canonicalRoot + "/" + entry.path, kind: entry.kind)
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            guard !path.isEmpty else { continue }
            if !isDirEntry, entry.kind != .deleted { canonical.append(canonicalRoot + "/" + path) }
            for root in roots {
                if isDirEntry {
                    dirs.insert(root + "/" + path)
                } else {
                    kinds[root + "/" + path] = entry.kind
                }
                var dir = (path as NSString).deletingLastPathComponent
                while !dir.isEmpty {
                    dirs.insert(root + "/" + dir)
                    dir = (dir as NSString).deletingLastPathComponent
                }
                dirs.insert(root)  // the root folder itself contains changes
            }
        }
        return GitStatusMap(kinds: kinds, changedDirs: dirs, canonicalPaths: canonical.sorted())
    }

    /// Every path the repo root may appear under in row/tab URLs: as given (standardized),
    /// symlink-resolved (strips macOS's /private designator), explicitly /private-prefixed
    /// (adds it back) — so a lookup keyed via either side of the /private/var ↔ /var symlink
    /// hits — and each caller-supplied alias, standardized.
    private static func rootAliases(of repoRoot: URL, extra: [URL]) -> Set<String> {
        var roots: Set<String> = [repoRoot.standardizedFileURL.path]
        roots.insert((repoRoot.standardizedFileURL.path as NSString).resolvingSymlinksInPath)
        for alias in extra { roots.insert(alias.standardizedFileURL.path) }
        for r in Array(roots) where !r.hasPrefix("/private/") {
            let aliased = "/private" + r
            if FileManager.default.fileExists(atPath: aliased) { roots.insert(aliased) }
        }
        return roots
    }

    /// Whether a status entry names a directory on disk — a submodule, whose pointer bump git
    /// reports as a plain modified path. Only a tracked, present entry can be one; untracked
    /// directories arrive with their own trailing slash and a deleted path is gone.
    private static func isDirectory(_ absolutePath: String, kind: GitChangeKind) -> Bool {
        guard kind != .untracked, kind != .deleted else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: absolutePath, isDirectory: &isDir) && isDir.boolValue
    }

    /// One map over several repositories — nested checkouts laid over the folder that
    /// holds them. Later maps win on a path: pass the outer repo first and the nested
    /// repos after, so a nested file's real kind replaces the outer repo's blanket
    /// "untracked directory". Each map's dots stop at its own repo root, so with
    /// `propagatingTo` set (the opened folder) every changed directory's ancestors up
    /// to it are dotted too — a changed plugin still lights `wp-content` in the tree.
    /// `aliases` are further paths the opened folder is known by (the repo root git
    /// resolved a symlink to), each propagated to the same way.
    public static func merge(_ maps: [GitStatusMap], propagatingTo top: URL? = nil, aliases: [URL] = []) -> GitStatusMap {
        var kinds: [String: GitChangeKind] = [:]
        var dirs: Set<String> = []
        var canonical = Set<String>()
        for m in maps {
            kinds.merge(m.kinds) { _, newer in newer }
            dirs.formUnion(m.changedDirs)
            canonical.formUnion(m.canonicalPaths)
        }
        for top in [top].compactMap({ $0 }) + aliases {
            propagate(&dirs, upTo: top.standardizedFileURL.path)
        }
        return GitStatusMap(kinds: kinds, changedDirs: dirs, canonicalPaths: canonical.sorted())
    }

    /// Dots every ancestor of a dotted directory under `topPath`, up to and including it.
    private static func propagate(_ dirs: inout Set<String>, upTo topPath: String) {
        let prefix = topPath.hasSuffix("/") ? topPath : topPath + "/"
        for dir in dirs where dir.hasPrefix(prefix) {
            var parent = (dir as NSString).deletingLastPathComponent
            while parent.count >= topPath.count, !dirs.contains(parent) {
                dirs.insert(parent)
                if parent == topPath { break }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
    }
}
