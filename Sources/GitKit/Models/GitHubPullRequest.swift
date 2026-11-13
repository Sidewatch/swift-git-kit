//
//  GitHubPullRequest.swift
//  GitKit
//
//  The pull request a branch belongs to, as GitHub's CLI reports it.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The pull request of a branch: what `gh pr view --json` says of it. A fact read, never written.
public struct GitHubPullRequest: Equatable, Sendable {
    /// The pull request's number.
    public let number: Int
    /// Its title.
    public let title: String
    /// Its page on GitHub.
    public let url: String
    /// The branch it merges INTO (`main`, `release/2.0`): what its diff is against.
    public let baseBranch: String
    /// The branch it merges from.
    public let headBranch: String
    /// `OPEN`, `MERGED` or `CLOSED`, as GitHub writes it.
    public let state: String
    /// Whether it is a draft.
    public let isDraft: Bool
    /// Its checks, taken together.
    public let checks: GitHubChecks

    /// A pull request.
    public init(
        number: Int, title: String, url: String, baseBranch: String, headBranch: String, state: String, isDraft: Bool, checks: GitHubChecks
    ) {
        self.number = number
        self.title = title
        self.url = url
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.state = state
        self.isDraft = isDraft
        self.checks = checks
    }

    /// Whether it is still open.
    public var isOpen: Bool { state.uppercased() == "OPEN" }
}
