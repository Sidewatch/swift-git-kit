//
//  GitPendingPush.swift
//  GitKit
//
//  What a push of the current branch would send, and where.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What ``Git/push(repoRoot:)`` would send now: where it goes, and how many commits the branch
/// is ahead of it (0 for a branch that is published by the push, whose remote has nothing to
/// count against).
public struct GitPendingPush: Equatable, Sendable {
    /// Where the push goes.
    public let target: GitPushTarget
    /// Commits ahead of the tracked branch.
    public let ahead: Int

    /// A pending push.
    public init(target: GitPushTarget, ahead: Int) {
        self.target = target
        self.ahead = ahead
    }
}
