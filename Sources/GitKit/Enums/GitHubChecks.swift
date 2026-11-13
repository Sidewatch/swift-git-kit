//
//  GitHubChecks.swift
//  GitKit
//
//  A pull request's checks, as one word.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// How a pull request's checks stand, taken together.
public enum GitHubChecks: String, Equatable, Sendable {
    /// The pull request has no checks.
    case none
    /// At least one check has not finished, and none has failed.
    case running
    /// Every check finished and none failed (skipped and neutral ones count as passed).
    case passing
    /// At least one check failed, timed out, was cancelled or needs action.
    case failing
}
