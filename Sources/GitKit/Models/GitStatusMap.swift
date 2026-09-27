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
/// collapsed folder's "contains changes" dot). Deleted files are excluded.
///
/// Build it off-main from ``Git/status(repoRoot:)``. Keys are inserted under every alias of the
/// repo root (standardized, symlink-resolved, `/private`-prefixed) so `/var` aliasing never misses.
public struct GitStatusMap: Equatable, Sendable {

    /// The map with no changed files.
    public static let empty = GitStatusMap(kinds: [:], changedDirs: [], canonicalPaths: [])

    /// Absolute file path → change kind (no `.deleted` entries).
    private let kinds: [String: GitChangeKind]
    /// Absolute path of every directory containing (at any depth) a changed file.
    private let changedDirs: Set<String>
    /// ONE path per changed file (the standardized-root alias). Must be used for any file
    /// LIST: `kinds` holds each file under every root alias, so listing its keys doubles files.
    private let canonicalPaths: [String]

    init(kinds: [String: GitChangeKind], changedDirs: Set<String>, canonicalPaths: [String]) {
        self.kinds = kinds
        self.changedDirs = changedDirs
        self.canonicalPaths = canonicalPaths
    }

    /// The change kind for a file URL, or nil when the file is unchanged.
    public func kind(for url: URL) -> GitChangeKind? {
        kinds.isEmpty ? nil : kinds[url.standardizedFileURL.path]
    }

    /// Absolute paths of every changed file — the "search the agent's changes"
    /// scope. Sorted so consumers get a stable order.
    public var changedFilePaths: [String] { canonicalPaths }

    /// Whether the directory at `url` contains (at any depth) a changed file.
    public func directoryContainsChanges(_ url: URL) -> Bool {
        !changedDirs.isEmpty && changedDirs.contains(url.standardizedFileURL.path)
    }

    /// Builds the lookup from repo-relative `git status` paths. Runs off-main
    /// (touches disk to resolve the repo root's symlink aliases, once per build).
    public static func build(status: [(path: String, kind: GitChangeKind)], repoRoot: URL) -> GitStatusMap {
        let live = status.filter { $0.kind != .deleted }
        guard !live.isEmpty else { return .empty }

        // Every alias the repo root may appear under in row/tab URLs: as given
        // (standardized), symlink-resolved (strips macOS's /private designator),
        // and explicitly /private-prefixed (adds it back) — so a lookup keyed via
        // either side of the /private/var ↔ /var symlink hits.
        var roots: Set<String> = [repoRoot.standardizedFileURL.path]
        roots.insert((repoRoot.standardizedFileURL.path as NSString).resolvingSymlinksInPath)
        for r in Array(roots) where !r.hasPrefix("/private/") {
            let aliased = "/private" + r
            if FileManager.default.fileExists(atPath: aliased) { roots.insert(aliased) }
        }

        var kinds: [String: GitChangeKind] = [:]
        var dirs: Set<String> = []
        let canonicalRoot = repoRoot.standardizedFileURL.path
        var canonical: [String] = []
        for entry in live {
            // Defensive: without `-uall`, `git status` collapses an untracked directory to
            // one trailing-slash entry ("?? NewFeature/"). Such a key never matches a lookup and
            // `deletingLastPathComponent` of it is "", so it is decorated as a folder instead.
            let isDirEntry = entry.path.hasSuffix("/")
            let path = isDirEntry ? String(entry.path.dropLast()) : entry.path
            guard !path.isEmpty else { continue }
            if !isDirEntry { canonical.append(canonicalRoot + "/" + path) }
            for root in roots {
                if isDirEntry {
                    dirs.insert(root + "/" + path)  // the untracked folder itself gets a dot
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

    /// One map over several repositories — nested checkouts laid over the folder that
    /// holds them. Later maps win on a path: pass the outer repo first and the nested
    /// repos after, so a nested file's real kind replaces the outer repo's blanket
    /// "untracked directory". Each map's dots stop at its own repo root, so with
    /// `propagatingTo` set (the opened folder) every changed directory's ancestors up
    /// to it are dotted too — a changed plugin still lights `wp-content` in the tree.
    public static func merge(_ maps: [GitStatusMap], propagatingTo top: URL? = nil) -> GitStatusMap {
        var kinds: [String: GitChangeKind] = [:]
        var dirs: Set<String> = []
        var canonical = Set<String>()
        for m in maps {
            kinds.merge(m.kinds) { _, newer in newer }
            dirs.formUnion(m.changedDirs)
            canonical.formUnion(m.canonicalPaths)
        }
        if let top {
            let topPath = top.standardizedFileURL.path
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
        return GitStatusMap(kinds: kinds, changedDirs: dirs, canonicalPaths: canonical.sorted())
    }
}
