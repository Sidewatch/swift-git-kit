//
//  GitOperation.swift
//  GitKit
//
//  A multi-step git operation that can be left half-done in a repository.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A multi-step operation git records in its directory while it is under way, from
/// ``Git/inProgressOperation(repoRoot:)``. While one is in progress a commit from outside git's
/// own flow would drop its state (a merge's second parent) or record conflict markers.
public enum GitOperation: String, Sendable, Equatable, CaseIterable {

    /// `MERGE_HEAD` exists: a merge waiting to be committed or resolved.
    case merge

    /// `rebase-merge/` or `rebase-apply/` exists: a rebase stopped on a conflict or an edit.
    case rebase

    /// `CHERRY_PICK_HEAD` exists.
    case cherryPick

    /// `REVERT_HEAD` exists.
    case revert

    /// `BISECT_LOG` exists.
    case bisect

    /// `rebase-apply/applying` exists: `git am` stopped on a patch.
    case am
}
