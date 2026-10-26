//
//  GitLFSPointer.swift
//  GitKit
//
//  The small text file Git LFS leaves where a large file was not downloaded.
//
//  Created by David Sherlock on 10/26/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The pointer Git LFS checks out in place of a large file it has not downloaded: the object's
/// SHA-256 and the real file's size in bytes. ``init?(data:)`` reads one.
public struct GitLFSPointer: Equatable, Sendable {
    /// The object's SHA-256, 64 lower-case hex digits.
    public let oid: String
    /// The real file's size, in bytes.
    public let size: Int

    /// A pointer to the object `oid` of `size` bytes.
    public init(oid: String, size: Int) {
        self.oid = oid
        self.size = size
    }
}
