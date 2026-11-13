//
//  GitHubReviewComment.swift
//  GitKit
//
//  One comment a reviewer left on a line of a pull request.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A review comment on a pull request's diff: who said what about which line. Read from GitHub's
/// `pulls/<n>/comments`; never posted from here.
public struct GitHubReviewComment: Equatable, Sendable, Identifiable {
    /// GitHub's id for the comment.
    public let id: Int
    /// The file it is about, relative to the repository.
    public let path: String
    /// The line it is on in the pull request's head, or nil once the code under it has changed
    /// (GitHub calls the comment outdated and keeps only ``originalLine``).
    public let line: Int?
    /// The first line of the range it is about when it covers several (``line`` is the last); nil for a
    /// comment on one line.
    public let startLine: Int?
    /// The line it was written on, in the commit it was written against.
    public let originalLine: Int?
    /// `RIGHT` for the new side of the diff, `LEFT` for a removed line.
    public let side: String
    /// The author's login.
    public let author: String
    /// The comment, as Markdown.
    public let body: String
    /// When it was written.
    public let createdAt: Date?
    /// The comment this one answers, when it is a reply in a thread.
    public let inReplyTo: Int?
    /// Its page on GitHub.
    public let url: String

    /// A review comment.
    public init(
        id: Int, path: String, line: Int?, startLine: Int? = nil, originalLine: Int?, side: String, author: String, body: String,
        createdAt: Date?, inReplyTo: Int?, url: String
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.startLine = startLine
        self.originalLine = originalLine
        self.side = side
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.inReplyTo = inReplyTo
        self.url = url
    }

    /// The lines it is about in the pull request's head: one line, or the range a multi-line comment
    /// covers. Nil for an outdated comment.
    public var lines: ClosedRange<Int>? {
        guard let line else { return nil }
        return min(startLine ?? line, line)...line
    }

    /// Whether the code it was written on has changed since: it has no line in the head any more.
    public var isOutdated: Bool { line == nil }
    /// Whether it sits on the new side of the diff, the side a checkout of the branch holds.
    public var isOnNewSide: Bool { side.uppercased() != "LEFT" }
}
