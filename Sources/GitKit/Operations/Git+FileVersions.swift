//
//  Git+FileVersions.swift
//  GitKit
//
//  One file as each of several commits holds it, from two cat-file runs.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One file across several commits.
public extension Git {

    /// The bytes `path` (repository-relative) holds at each of `commits`, in the same order:
    /// nil where that commit does not have the file, names a tree there, or the commit is not a
    /// plain object id. Raw blobs, no filters or line-ending conversion.
    ///
    /// Two processes whatever the count: `cat-file --batch-check` names each version's blob, and
    /// one `cat-file --batch` reads each DISTINCT blob once — a file most commits share is read
    /// once, not once per commit. Empty when `path` is empty or holds a newline (which the
    /// one-per-line protocol cannot carry).
    static func fileVersions(path: String, commits: [String], repoRoot root: URL) -> [Data?] {
        guard !path.isEmpty, !path.contains("\n") else { return Array(repeating: nil, count: commits.count) }
        let blobs = blobIDs(path: path, commits: commits, repoRoot: root)
        var seen = Set<String>()
        let distinct = blobs.compactMap { $0 }.filter { seen.insert($0).inserted }
        guard !distinct.isEmpty,
            let out = runData(["cat-file", "--batch"], in: root, input: Data(distinct.map { $0 + "\n" }.joined().utf8))
        else { return Array(repeating: nil, count: commits.count) }
        let bytes = parseBatch(out, paths: distinct)
        return blobs.map { $0.flatMap { bytes[$0] } }
    }
}

extension Git {

    /// The blob id of `path` at each of `commits` (nil where there is none), from one
    /// `cat-file --batch-check` run whose output is one line per asked object, in order.
    static func blobIDs(path: String, commits: [String], repoRoot root: URL) -> [String?] {
        let asked = commits.map { isObjectID($0) ? $0 : nil }
        let specs = asked.compactMap { $0.map { "\($0):\(path)\n" } }
        guard !specs.isEmpty, let out = runData(["cat-file", "--batch-check"], in: root, input: Data(specs.joined().utf8)) else {
            return Array(repeating: nil, count: commits.count)
        }
        var answers = String(decoding: out, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        return asked.map { commit in
            guard commit != nil, let line = answers.next() else { return nil }
            let fields = line.split(separator: " ")
            return fields.count == 3 && fields[1] == "blob" ? String(fields[0]) : nil
        }
    }

    /// Whether `text` is a hexadecimal object id (SHA-1 or SHA-256), so it can stand before
    /// the `:` of a `<commit>:<path>` name without being read as anything else.
    static func isObjectID(_ text: String) -> Bool {
        (40...64).contains(text.count) && text.allSatisfy(\.isHexDigit)
    }
}
