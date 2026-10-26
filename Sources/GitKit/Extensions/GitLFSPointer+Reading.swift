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

/// Read as git-lfs's own decoder reads a pointer (`DecodeFrom` and `decodeKV` in its `lfs/pointer.go`), so a file
/// is a pointer here when, and only when, Git LFS would call it one; the specification is its `docs/spec.md`.
extension GitLFSPointer {
    /// A pointer is smaller than this many bytes: the specification's "less than 1024 bytes", and git-lfs's
    /// `BlobSizeCutoff`, at or above which it never reads a file as a pointer.
    public static let sizeLimit = 1_024

    /// Reads a pointer from a file's bytes: fewer than ``sizeLimit`` of UTF-8, trimmed of surrounding white
    /// space, read as `\n` lines (a trailing `\r` dropped, empty lines skipped) of `key value` split at the
    /// first space. `version`, `oid` and `size` come in that order, once each, with `ext-<digit>-<name>`
    /// extension lines anywhere before `size` and no line after it. The version is one of git-lfs's three,
    /// compared as a plain string; the oid and every extension's value are `sha256:` and 64 lower-case hex
    /// digits; the size is a decimal of at least 0; no two extensions share a priority. Nil for anything else,
    /// so a real file is never taken for its pointer. An empty file is Git LFS's pointer to an empty file —
    /// the same empty file — and nil here.
    public init?(data: Data) {
        guard data.count < Self.sizeLimit, let text = data.utf8String else { return nil }
        var expected = Self.keys[...]
        var values: [String: Substring] = [:]
        var extensions: [Substring: Substring] = [:]
        // Split through Foundation: in a Swift String `\r\n` is ONE Character, never split by "\n".
        for raw in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n") {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : Substring(raw)
            if line.isEmpty { continue }
            guard let next = expected.first, let space = line.firstIndex(of: " ") else { return nil }
            let key = line[..<space]
            let value = line[line.index(after: space)...]
            if key == next {
                values[next] = value
                expected.removeFirst()
            } else if Self.extensionPriority(of: key) != nil {
                extensions[key] = value  // a repeated identical key keeps one entry, as git-lfs's map does
            } else {
                return nil
            }
        }
        guard let version = values["version"], Self.versions.contains(String(version)),
            let oid = values["oid"].flatMap(Self.objectID), let size = values["size"].flatMap({ Int($0) }), size >= 0,
            extensions.values.allSatisfy({ Self.objectID($0) != nil }),
            Set(extensions.keys.compactMap { Self.extensionPriority(of: $0) }).count == extensions.count
        else { return nil }
        self.init(oid: oid, size: size)
    }

    /// Reads a pointer from the file at `url` when the whole file is smaller than ``sizeLimit`` bytes, as git-lfs
    /// reads a working-tree file (which must also be a regular file there; a link is followed here, so a link to
    /// a pointer shows as one). Nil for a larger file, a real file of any size, or no file.
    public init?(fileAt url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: Self.sizeLimit), head.count < Self.sizeLimit else { return nil }
        self.init(data: head)
    }

    /// The keys every pointer has, in their order (git-lfs's `pointerKeys`).
    private static let keys = ["version", "oid", "size"]

    /// git-lfs's `v1Aliases`: the public launch's version, and the pre-release (hawser) and alpha (git-media)
    /// ones it still reads.
    private static let versions: Set<String> = [
        "https://git-lfs.github.com/spec/v1", "https://hawser.github.com/spec/v1", "http://git-media.io/v/2",
    ]

    /// The 64 digits of `sha256:<digits>`, as git-lfs's `parseOid` reads an oid; nil for anything else. ASCII
    /// only, as its `[0-9a-f]{64}`: `Character.isHexDigit` also takes full-width digits.
    private static func objectID(_ value: Substring) -> String? {
        guard value.hasPrefix("sha256:") else { return nil }
        let digits = value.dropFirst("sha256:".count).utf8
        guard digits.count == 64, digits.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else { return nil }
        return String(decoding: digits, as: UTF8.self)
    }

    /// The priority of an extension key, git-lfs's `\Aext-\d{1}-\w+`: `ext-`, one ASCII digit, `-`, then a word
    /// character (the rest of the key is free, as the pattern is anchored at its start only); nil for any other key.
    private static func extensionPriority(of key: Substring) -> UInt8? {
        let bytes = Array(key.utf8)
        guard bytes.count >= 7, bytes.starts(with: "ext-".utf8), (0x30...0x39).contains(bytes[4]), bytes[5] == UInt8(ascii: "-"),
            Self.isWordByte(bytes[6])
        else { return nil }
        return bytes[4] - 0x30
    }

    /// Whether `byte` is an ASCII word character, Go's `\w`: a letter, a digit or `_`.
    private static func isWordByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == UInt8(ascii: "_")
    }
}
