//
//  GitHubDiscussionComment.swift
//  GitKit
//
//  Something said about a pull request as a whole.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A comment on a pull request that is not on a line of its diff: one in its conversation, or the
/// summary a reviewer wrote with a review. Read from `gh pr view --json comments,reviews`.
public struct GitHubDiscussionComment: Equatable, Sendable {
    /// The author's login.
    public let author: String
    /// The comment, as Markdown.
    public let body: String
    /// When it was written.
    public let createdAt: Date?
    /// Its page on GitHub; empty for a review's summary, which `gh` gives no address.
    public let url: String
    /// For a review's summary, how the review ended (`APPROVED`, `CHANGES_REQUESTED`, `COMMENTED`); nil
    /// for a comment in the conversation.
    public let reviewState: String?

    /// A comment.
    public init(author: String, body: String, createdAt: Date?, url: String, reviewState: String?) {
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.url = url
        self.reviewState = reviewState
    }
}
