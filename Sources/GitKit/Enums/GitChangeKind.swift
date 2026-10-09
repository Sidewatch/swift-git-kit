//
//  GitChangeKind.swift
//  GitKit
//
//  The kind of change git reports for a file or an individual line.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The nature of a change git reports for a working-tree file or a single line.
///
/// The same vocabulary is used at two granularities:
/// - **File level** — one value per changed file, from ``Git/status(repoRoot:)``.
/// - **Line level** — for editor gutter markers, from ``Git/lineChanges(for:repoRoot:)``.
public enum GitChangeKind: Sendable, Equatable {

    /// A file staged for addition, or a line that did not exist at `HEAD`.
    case added

    /// A tracked file or line whose contents differ from `HEAD`.
    case modified

    /// A tracked file removed from the working tree, or — at line granularity — the line directly
    /// below a pure deletion (`1` for a deletion before the first line; one past the last line for
    /// a deletion at the end of the file, which a consumer must tolerate).
    case deleted

    /// A file not yet tracked by git.
    case untracked

    /// A tracked file that git detected as renamed.
    case renamed

    /// A file with an unresolved merge, rebase or cherry-pick conflict (`UU`, `AA`, `DD`, `AU`,
    /// `UA`, `DU`, `UD` in porcelain status). Never reported at line granularity.
    case conflicted

    /// The single-letter status badge git uses in short/porcelain output
    /// (`A`/`M`/`D`/`R`/`U`), plus `C` for a conflict — for a Changes-panel or gutter badge.
    public var letter: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "U"
        case .conflicted: return "C"
        }
    }
}
