//
//  CheckoutSet+Routing.swift
//  GitKit
//
//  Which repository a file belongs to, and files grouped per repository for one git call each.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension CheckoutSet {
    /// The primary repository first, then every nested one — the order to merge per-repository status
    /// maps in, so a nested map lays over the primary's view of it.
    var all: [URL] { [primary].compactMap { $0 } + nested }

    /// The repository `url` belongs to: the deepest nested checkout holding it (a nested root holds
    /// itself), else the primary — which also answers for a file outside the opened folder — else nil.
    func root(for url: URL) -> URL? {
        nested.first { Self.holds($0, url) } ?? primary
    }

    /// The checkouts a change at any of `paths` may have moved, so a refresh asks git about those
    /// alone: every checkout holding a path (an outer repository's status shows an inner one as a
    /// modified submodule), the primary (which answers for every path, as in ``root(for:)``), and
    /// every nested checkout below a path that names a folder (a coalesced or rescanned event covers
    /// what is under it).
    ///
    /// Each root is spelled two ways, worked out once per call: as written, and with links resolved
    /// (the file-system events name the real path). A path then costs a dictionary lookup per folder
    /// above it and one binary search, whatever the number of checkouts: one call can carry thousands
    /// of paths (an install in one plugin), it runs on the caller's thread, and it never touches the
    /// disk per path.
    func checkouts(touchedBy paths: some Sequence<String>) -> Set<URL> {
        var byName: [String: URL] = [:]
        for root in nested { for name in Self.spellings(of: root) { byName[name] = root } }
        let names = byName.keys.sorted()
        var touched: Set<URL> = []
        let everything = all.count
        for path in paths {
            if let primary { touched.insert(primary) }
            let changed = URL(fileURLWithPath: path).standardizedFileURL.path
            var folder = Substring(changed)
            while !folder.isEmpty {
                if let root = byName[String(folder)] { touched.insert(root) }
                folder = folder[..<(folder.lastIndex(of: "/") ?? folder.startIndex)]
            }
            let below = changed + "/"
            var index = Self.firstIndex(notBefore: below, in: names)
            while index < names.count, names[index].hasPrefix(below), let root = byName[names[index]] {
                touched.insert(root)
                index += 1
            }
            if touched.count == everything { break }
        }
        return touched
    }

    /// The index of the first of the sorted `names` that does not sort before `key`.
    private static func firstIndex(notBefore key: String, in names: [String]) -> Int {
        var low = 0, high = names.count
        while low < high {
            let middle = (low + high) / 2
            if names[middle] < key { low = middle + 1 } else { high = middle }
        }
        return low
    }

    /// `urls` grouped by the repository each belongs to, with its repository-relative path — one batched
    /// git call per repository instead of one per file — and the URLs under no repository.
    func grouped(_ urls: [URL]) -> (byRoot: [URL: [URL: String]], outside: [URL]) {
        var byRoot: [URL: [URL: String]] = [:]
        var outside: [URL] = []
        for url in urls {
            guard let root = root(for: url) else { outside.append(url); continue }
            if byRoot[root]?[url] == nil { byRoot[root, default: [:]][url] = Git.relativePath(url, root: root) }
        }
        return (byRoot, outside)
    }

    /// The opened folder as an alias of the primary root: when the two name the same directory once
    /// links are resolved but are spelled differently (a project opened through a symlink — git
    /// reports the real path). Empty otherwise; a subfolder of the repository is not an alias of it.
    func aliases(ofOpened opened: URL?) -> [URL] {
        guard let primary, let opened else { return [] }
        guard Git.canonicalPath(opened) == Git.canonicalPath(primary) else { return [] }
        return opened.standardizedFileURL.path == primary.standardizedFileURL.path ? [] : [opened]
    }

    /// `root`'s path as written and with its links resolved, once each.
    private static func spellings(of root: URL) -> [String] {
        let written = root.standardizedFileURL.path
        let resolved = Git.canonicalPath(root)
        return written == resolved ? [written] : [written, resolved]
    }

    /// Whether `root` holds `url`: the root itself, or anything under it (standardized or canonical).
    private static func holds(_ root: URL, _ url: URL) -> Bool {
        url.standardizedFileURL.path == root.standardizedFileURL.path || Git.relativePathIfUnderRoot(url, root: root) != nil
    }
}
