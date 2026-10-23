//
//  GitPushTarget.swift
//  GitKit
//
//  Where a push of the current branch goes.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Where ``Git/push(repoRoot:)`` sends the current branch: a remote and a branch on it, and
/// whether the push publishes the branch (it tracks nothing yet, so the push sets the upstream).
public struct GitPushTarget: Equatable, Sendable {
    /// The remote's name (`origin`).
    public let remote: String
    /// The branch on the remote (`main`).
    public let branch: String
    /// True when the local branch tracks nothing and the push publishes it with `-u`.
    public let publishes: Bool

    /// `origin/main`.
    public var name: String { remote + "/" + branch }

    /// A target.
    public init(remote: String, branch: String, publishes: Bool) {
        self.remote = remote
        self.branch = branch
        self.publishes = publishes
    }
}
