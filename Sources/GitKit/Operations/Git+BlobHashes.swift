//
//  Git+BlobHashes.swift
//  GitKit
//
//  The blob id git would store for each of several working-tree files, in one process.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Content hashes of working-tree files.
public extension Git {

    /// The blob id git would store for each of `paths` (repository-relative), from one
    /// `hash-object --stdin-paths` run — filters such as line-ending conversion applied, as
    /// `add` would. A path that is missing, unreadable, a directory, or contains a newline
    /// (which the one-per-line protocol cannot carry) has no key.
    static func blobHashes(paths: [String], repoRoot root: URL) -> [String: String] {
        var seen = Set<String>()
        let hashable = paths.filter { seen.insert($0).inserted && isHashableFile($0, repoRoot: root) }
        guard !hashable.isEmpty,
            let out = run(
                ["hash-object", "--stdin-paths"], in: root,
                environment: [:], input: Data((hashable.joined(separator: "\n") + "\n").utf8))
        else { return [:] }
        let hashes = out.split(separator: "\n").map(String.init)
        return Dictionary(uniqueKeysWithValues: zip(hashable, hashes))
    }
}

extension Git {

    /// Whether `rel` names a readable non-directory `hash-object` can take from stdin.
    private static func isHashableFile(_ rel: String, repoRoot root: URL) -> Bool {
        guard !rel.contains("\n") else { return false }
        let path = root.appendingPathComponent(rel).path
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isReadableFile(atPath: path)
    }
}
