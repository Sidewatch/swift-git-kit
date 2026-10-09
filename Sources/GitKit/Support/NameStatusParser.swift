//
//  NameStatusParser.swift
//  GitKit
//
//  `git diff --name-status -z` into status entries.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Parses `git diff --name-status -z`: `<status>\0<path>\0`, or `R<score>\0<old>\0<new>\0` for a
/// rename (`C<score>` for a copy). `-z` keeps every path verbatim — a `"` or `\` in a name is not
/// quoted — which the newline form cannot promise.
enum NameStatusParser {

    /// Every entry in `out`, in git's order; a rename is reported under its new path with
    /// ``GitStatusEntry/oldPath`` set.
    static func entries(_ out: String) -> [GitStatusEntry] {
        let tokens = out.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var result: [GitStatusEntry] = []
        var i = 0
        while i < tokens.count {
            let status = tokens[i]
            i += 1
            guard let letter = status.first else { continue }
            if letter == "R" || letter == "C" {
                guard i + 1 < tokens.count else { break }
                result.append(GitStatusEntry(path: tokens[i + 1], kind: kind(for: letter), oldPath: tokens[i]))
                i += 2
            } else {
                guard i < tokens.count else { break }
                result.append(GitStatusEntry(path: tokens[i], kind: kind(for: letter)))
                i += 1
            }
        }
        return result
    }

    /// The kind for a `--name-status` letter.
    static func kind(for letter: Character) -> GitChangeKind {
        switch letter {
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "U": return .conflicted
        default: return .modified  // M, T, C (a copy is new content under a new name)
        }
    }
}
