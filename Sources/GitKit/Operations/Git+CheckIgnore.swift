//
//  Git+CheckIgnore.swift
//  GitKit
//
//  Which of several paths git ignores, asked of git itself in one process.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Git's own ignore verdict for paths that may not have existed a moment ago.
public extension Git {

    /// The subset of `paths` (repository-relative) git ignores, from ONE `check-ignore --stdin -z`
    /// run — every `.gitignore`, `.git/info/exclude` and `core.excludesFile` rule as git applies
    /// it, for files created after any cached listing. A tracked file is never ignored (git's own
    /// rule). Empty when nothing is ignored or git fails.
    static func ignoredPaths(_ paths: [String], repoRoot root: URL) -> Set<String> {
        let asked = paths.filter { !$0.isEmpty && !$0.contains("\0") }
        guard !asked.isEmpty else { return [] }
        let input = Data(asked.map { $0 + "\0" }.joined().utf8)
        // Exit 1 ("none of them") comes back nil, the same empty answer as a failure. check-ignore
        // refuses the literal-pathspec magic the fixed environment sets ("pathspec magic not
        // supported"), and its stdin names paths, not patterns, so the variable is off for this call.
        guard let out = run(["check-ignore", "--stdin", "-z"], in: root, environment: ["GIT_LITERAL_PATHSPECS": "0"], input: input)
        else { return [] }
        return Set(out.split(separator: "\0").map(String.init))
    }
}
