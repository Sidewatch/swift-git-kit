//
//  GitBranchBase.swift
//  GitKit
//
//  What a branch is compared against, and where it left it.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The base of a branch's work: the ref it is compared against and the commit where the branch
/// left it (their merge base). A diff from ``commit`` to the working tree is everything the branch
/// changed, which is what a pull request into ``ref`` shows.
public struct GitBranchBase: Equatable, Sendable {
    /// The ref compared against, as it resolved (`origin/HEAD`, `main`, `origin/release/2.0`).
    public let ref: String
    /// The merge base of that ref and `HEAD`.
    public let commit: String

    /// A base.
    public init(ref: String, commit: String) {
        self.ref = ref
        self.commit = commit
    }
}
