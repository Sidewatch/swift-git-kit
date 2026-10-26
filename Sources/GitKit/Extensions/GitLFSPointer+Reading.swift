//
//  GitLFSPointer+Reading.swift
//  GitKit
//
//  Telling a Git LFS pointer from the file it stands for, by its bytes.
//
//  Created by David Sherlock on 10/26/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

extension GitLFSPointer {
    /// The most bytes a pointer file has (the specification's limit).
    public static let maximumSize = 1_024

    /// Reads a pointer from a file's bytes, as the Git LFS specification writes one: UTF-8 lines of
    /// `key value`, `version` first (`https://git-lfs.github.com/spec/v1`, or the older
    /// `https://hawser.github.com/spec/v1`), then an `oid` of `sha256:` and 64 hex digits and a
    /// `size` in decimal, with any `ext-` lines between; at most ``maximumSize`` bytes. Nil for
    /// anything else, so a real file is never taken for its pointer.
    public init?(data: Data) {
        guard data.count <= Self.maximumSize, let text = data.utf8String else { return nil }
        // `\r\n` is ONE Character: split on newlines, or a CRLF pointer is one long line.
        let lines = text.split(whereSeparator: \.isNewline)
        guard let first = lines.first, Self.versions.contains(String(first)) else { return nil }
        var oid: String?
        var size: Int?
        for line in lines.dropFirst() {
            guard let space = line.firstIndex(of: " ") else { return nil }
            let key = line[..<space]
            let value = line[line.index(after: space)...]
            switch key {
            case "oid":
                guard value.hasPrefix("sha256:") else { return nil }
                let digits = value.dropFirst("sha256:".count)
                guard digits.count == 64, digits.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
                oid = String(digits)
            case "size":
                guard let bytes = Int(value), bytes >= 0 else { return nil }
                size = bytes
            default:
                guard key.hasPrefix("ext-") else { return nil }
            }
        }
        guard let oid, let size else { return nil }
        self.init(oid: oid, size: size)
    }

    /// Reads a pointer from the file at `url`: its first ``maximumSize`` bytes, and only when the
    /// whole file is that small. Nil for a larger file, a real file of any size, or no file.
    public init?(fileAt url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: Self.maximumSize + 1), head.count <= Self.maximumSize else { return nil }
        self.init(data: head)
    }

    private static let versions: Set<String> = [
        "version https://git-lfs.github.com/spec/v1", "version https://hawser.github.com/spec/v1",
    ]
}
