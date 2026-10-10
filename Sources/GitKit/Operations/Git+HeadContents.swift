//
//  Git+HeadContents.swift
//  GitKit
//
//  The committed bytes of several files, from one cat-file run.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Committed contents of working-tree paths.
public extension Git {

    /// The bytes each of `paths` (repository-relative) holds at `HEAD`, from ONE
    /// `cat-file --batch` run — the raw blob, no filters or line-ending conversion. A path that
    /// `HEAD` does not have (untracked, new, an unborn branch), names a tree, or contains a
    /// newline (which the one-per-line protocol cannot carry) has no key.
    static func headContents(paths: [String], repoRoot root: URL) -> [String: Data] {
        var seen = Set<String>()
        let asked = paths.filter { !$0.isEmpty && !$0.contains("\n") && seen.insert($0).inserted }
        guard !asked.isEmpty else { return [:] }
        let input = Data(asked.map { "HEAD:\($0)\n" }.joined().utf8)
        guard let out = runData(["cat-file", "--batch"], in: root, input: input) else { return [:] }
        return parseBatch(out, paths: asked)
    }
}

extension Git {

    /// Reads `cat-file --batch` output, one record per asked path in order: either
    /// `<object> missing|ambiguous LF`, or `<oid> SP <type> SP <size> LF <bytes> LF`.
    static func parseBatch(_ out: Data, paths: [String]) -> [String: Data] {
        var result: [String: Data] = [:]
        var cursor = out.startIndex
        for path in paths {
            guard let newline = out[cursor...].firstIndex(of: 0x0A) else { break }
            let header = String(decoding: out[cursor..<newline], as: UTF8.self)
            cursor = out.index(after: newline)
            if header.hasSuffix(" missing") || header.hasSuffix(" ambiguous") { continue }
            let fields = header.split(separator: " ")
            guard fields.count == 3, let size = Int(fields[2]), size >= 0, out.distance(from: cursor, to: out.endIndex) >= size else {
                break
            }
            let end = out.index(cursor, offsetBy: size)
            if fields[1] == "blob" { result[path] = Data(out[cursor..<end]) }
            cursor = end < out.endIndex ? out.index(after: end) : end  // the record's trailing LF
        }
        return result
    }
}
