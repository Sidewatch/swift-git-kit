//
//  PorcelainStatusParser.swift
//  GitKit
//
//  `git status --porcelain=v1 -z` into status entries.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Parses `git status --porcelain=v1 -z`: `XY path\0`, with a rename or copy carrying its
/// old path as one more NUL field (`R  new\0old\0`).
enum PorcelainStatusParser {

    /// Every entry in `out`, in git's order.
    static func entries(_ out: String) -> [GitStatusEntry] {
        var result: [GitStatusEntry] = []
        let fields = out.split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < fields.count {
            let entry = String(fields[i])
            i += 1
            guard entry.count >= 4 else { continue }
            let code = String(entry.prefix(2))
            let path = String(entry.dropFirst(3))
            var oldPath: String?
            if code.contains("R") || code.contains("C"), i < fields.count {
                oldPath = String(fields[i])
                i += 1
            }
            result.append(GitStatusEntry(path: path, kind: kind(forCode: code), oldPath: oldPath))
        }
        return result
    }

    /// The kind for a two-letter `XY` code (X the index side, Y the working tree).
    ///
    /// Conflicts first: `DD` and `UD` have a `D` on the working-tree side and would otherwise read
    /// as deletions. Then a working-tree deletion of any index state (` D`, `AD`, `MD`, `RD`):
    /// the file is gone, whatever was staged. Then the index side decides.
    static func kind(forCode code: String) -> GitChangeKind {
        if code.contains("U") || code == "AA" || code == "DD" { return .conflicted }
        if code.last == "D" { return .deleted }
        if code == "??" { return .untracked }
        switch code.first {
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        default: return .modified  // M, T, C (copy) and the ` M` of a submodule pointer bump
        }
    }
}
