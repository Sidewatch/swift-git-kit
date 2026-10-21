//
//  CheckoutSet.swift
//  GitKit
//
//  The repositories one opened folder holds: the one it is in, and the checkouts nested below it.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Every repository an opened folder involves: the `primary` one the folder is in (if any) and the
/// checkouts `nested` below it — plugins, vendored libraries — kept DEEPEST first, so the first one
/// holding a file is the one it belongs to.
public struct CheckoutSet: Sendable, Equatable {
    /// The repository the opened folder is in, or nil for a plain folder.
    public let primary: URL?
    /// The checkouts below the opened folder, longest path first.
    public let nested: [URL]

    /// A set of `primary` and `nested` (sorted longest path first here).
    public init(primary: URL?, nested: [URL]) {
        self.primary = primary
        self.nested = nested.sorted { $0.standardizedFileURL.path.count > $1.standardizedFileURL.path.count }
    }
}
