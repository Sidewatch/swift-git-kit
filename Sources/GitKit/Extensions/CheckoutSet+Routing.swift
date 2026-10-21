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

    /// Whether `root` holds `url`: the root itself, or anything under it (standardized or canonical).
    private static func holds(_ root: URL, _ url: URL) -> Bool {
        url.standardizedFileURL.path == root.standardizedFileURL.path || Git.relativePathIfUnderRoot(url, root: root) != nil
    }
}
