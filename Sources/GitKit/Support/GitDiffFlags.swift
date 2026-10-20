//
//  GitDiffFlags.swift
//  GitKit
//
//  The flags that keep a `git diff` this package parses the shape it parses, whatever the
//  user's diff configuration says.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Flags every `git diff` here carries so the user's configuration cannot change the output
/// shape the parsers expect.
enum GitDiffFlags {

    /// For any diff: `diff.external` / `GIT_EXTERNAL_DIFF` replace the whole output, a
    /// `textconv` driver shifts line numbers, `color.ui=always` wraps everything in escapes.
    static let plain = ["--no-color", "--no-ext-diff", "--no-textconv"]

    /// For a `--unified=0` diff: `diff.interHunkContext` / `GIT_DIFF_OPTS` fuse hunks, giving a
    /// zero-context diff context lines after all.
    static let unifiedZero = plain + ["--unified=0", "--inter-hunk-context=0"]

    /// For a diff whose `---`/`+++` headers are parsed: `diff.noprefix` and `diff.mnemonicPrefix`
    /// change the `a/` and `b/` the parser strips.
    static let prefixed = ["--src-prefix=a/", "--dst-prefix=b/"]

    /// For a full unified diff handed to a renderer: context as configured, hunks never fused,
    /// headers prefixed `a/` and `b/`.
    static let patch = plain + ["--inter-hunk-context=0"] + prefixed

    /// For a diff a person reads with whitespace set aside: `--ignore-all-space`, so a re-indent
    /// or a reformat leaves only the lines whose words changed. Never for a diff whose line
    /// numbers mark a buffer (the gutter's), which must see every change.
    static let ignoringWhitespace = ["--ignore-all-space"]

    /// The reading flags: ``patch``, plus ``ignoringWhitespace`` when asked.
    static func patch(ignoringWhitespace: Bool) -> [String] { patch + (ignoringWhitespace ? Self.ignoringWhitespace : []) }

    /// `git -c core.quotePath=false`: non-ASCII paths come back verbatim in headers and
    /// `--name-status` output rather than C-quoted (`"caf\303\251"`).
    static let quotePathOff = ["-c", "core.quotePath=false"]
}
