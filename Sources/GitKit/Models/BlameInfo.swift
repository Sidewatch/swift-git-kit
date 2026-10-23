//
//  BlameInfo.swift
//  GitKit
//
//  Authorship information for a single blamed line.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Authorship information for a single line, produced by ``Git/blame(for:line:repoRoot:)``.
public struct BlameInfo: Sendable, Equatable {

    /// The author's name, or ``uncommittedAuthor`` for uncommitted lines.
    public let author: String

    /// A short human-readable age of the commit (e.g. `"3d ago"`), or `""` when unavailable.
    public let timeAgo: String

    /// The commit's summary line (its first line).
    public let summary: String

    /// Creates a blame record. Normally produced by ``Git/blame(for:line:repoRoot:)``;
    /// public for constructing fixtures in tests and previews.
    public init(author: String, timeAgo: String, summary: String) {
        self.author = author
        self.timeAgo = timeAgo
        self.summary = summary
    }

    /// The author git's blame names for a line no commit has: `"Not Committed Yet"`.
    public static let uncommittedAuthor = "Not Committed Yet"

    /// A line no commit has, with no age or summary — what a caller shows when blame has no answer.
    public static let uncommitted = BlameInfo(author: uncommittedAuthor, timeAgo: "", summary: "")

    /// Whether no commit has this line yet.
    public var isUncommitted: Bool { author == Self.uncommittedAuthor }
}
