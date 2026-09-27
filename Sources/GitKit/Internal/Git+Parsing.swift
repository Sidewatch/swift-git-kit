//
//  Git+Parsing.swift
//  GitKit
//
//  Internal pure-function parsers shared across operations. Kept at `internal`
//  access (not `private`) so they can be unit-tested directly.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Pure parsers shared across operations, internal so tests can reach them.
extension Git {

    /// Formats a Unix epoch timestamp as a short relative age (`"just now"`,
    /// `"5m ago"`, `"3d ago"`, `"2mo ago"`, `"1y ago"`).
    ///
    /// - Parameters:
    ///   - ts: The event time as seconds since the Unix epoch.
    ///   - now: The reference "now", defaulting to the current time. Injectable
    ///     so the formatting is deterministically unit-testable.
    static func relativeTime(_ ts: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) -> String {
        let s = Int(now - ts)
        if s < 60 { return String(localized: "just now", bundle: .module, comment: "Blame: a commit's age under a minute") }
        if s < 3600 { return String(localized: "\(s / 60)m ago", bundle: .module, comment: "Blame: a commit's age in minutes, short form") }
        if s < 86400 { return String(localized: "\(s / 3600)h ago", bundle: .module, comment: "Blame: a commit's age in hours, short form") }
        if s < 2_592_000 { return String(localized: "\(s / 86400)d ago", bundle: .module, comment: "Blame: a commit's age in days, short form") }
        if s < 31_536_000 { return String(localized: "\(s / 2_592_000)mo ago", bundle: .module, comment: "Blame: a commit's age in months, short form") }
        return String(localized: "\(s / 31_536_000)y ago", bundle: .module, comment: "Blame: a commit's age in years, short form")
    }
}
