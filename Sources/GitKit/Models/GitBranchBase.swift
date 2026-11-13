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
    /// The merge base of that ref and `HEAD`; the ref's own tip when ``sharesHistory`` is false.
    public let commit: String
    /// False in a shallow clone whose history stops before the two branches meet: ``commit`` is then
    /// the tip of ``ref``, and a diff from it also holds whatever landed on ``ref`` after the branch
    /// left it. True everywhere else.
    public let sharesHistory: Bool

    /// A base.
    public init(ref: String, commit: String, sharesHistory: Bool = true) {
        self.ref = ref
        self.commit = commit
        self.sharesHistory = sharesHistory
    }
}
