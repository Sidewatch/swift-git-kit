//
//  DiffFileKind.swift
//  GitKit
//
//  How one file in a diff changed, read from its header lines.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// How one file in a diff changed, read from its header lines (`new file mode`, `deleted file
/// mode`, `rename from`).
public enum DiffFileKind: Equatable, Sendable {
    /// Edited in place.
    case modified
    /// New in this diff.
    case added
    /// Removed in this diff.
    case deleted
    /// Moved, from this repository-relative path.
    case renamed(from: String)
}
