//
//  GitPushError.swift
//  GitKit
//
//  Why a push sent nothing.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Why ``Git/push(repoRoot:)`` sent nothing.
public enum GitPushError: Error, Equatable, Sendable {

    /// HEAD is not on a branch, so there is no branch to push.
    case detachedHead

    /// The branch tracks no remote branch, and the repository has no one remote to publish it to
    /// (none at all, or several with none named `origin`).
    case noRemote

    /// git refused or failed; `stderr` is its own message (a rejected push, a pre-push hook's
    /// output, a credential it could not get).
    case failed(stderr: String)
}
