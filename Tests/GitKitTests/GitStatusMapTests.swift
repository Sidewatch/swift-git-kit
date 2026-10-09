//
//  GitStatusMapTests.swift
//  GitKitTests
//
//  Tests for `GitStatusMap` and `GitChangeKind`: porcelain parsing, kind letters, and a build
//  that only touches disk to resolve the root.
//
//  Created by David Sherlock on 7/19/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Tests for `GitStatusMap` and `GitChangeKind`: porcelain parsing, kind letters, and a build
/// that only touches disk to resolve the root.
final class GitStatusMapTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/repo")

    // MARK: - letter

    func testChangeKindLetters() {
        XCTAssertEqual(GitChangeKind.added.letter, "A")
        XCTAssertEqual(GitChangeKind.modified.letter, "M")
        XCTAssertEqual(GitChangeKind.deleted.letter, "D")
        XCTAssertEqual(GitChangeKind.renamed.letter, "R")
        XCTAssertEqual(GitChangeKind.untracked.letter, "U")
    }

    // MARK: - build: lookups

    /// The changed-file LIST must be canonical: `kinds` keys each file under
    /// every root alias (/tmp + /private/tmp) for O(1) lookups, but a list with
    /// one entry per alias doubled search rows and made targeted replace report
    /// phantom failures.
    func testChangedFilePathsAreDeduplicatedAcrossRootAliases() throws {
        // A REAL root behind the /private/var ↔ /var symlink — the fabricated
        // "/repo" fixture has one alias, which let a broken (alias-expanded)
        // list pass this test. Skip only if this system somehow doesn't alias.
        let aliasedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitmap-dedupe-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: aliasedRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aliasedRoot) }
        let std = aliasedRoot.standardizedFileURL.path
        let resolved = (std as NSString).resolvingSymlinksInPath
        try XCTSkipIf(
            std == resolved && !FileManager.default.fileExists(atPath: "/private" + std),
            "root does not alias on this system")

        let map = GitStatusMap.build(
            status: [("src/a.swift", .modified), ("b.swift", .added)],
            repoRoot: aliasedRoot)
        XCTAssertEqual(
            map.changedFilePaths.count, 2,
            "one entry per FILE, not per root alias: \(map.changedFilePaths)")
        for p in map.changedFilePaths {
            XCTAssertNotNil(map.kind(for: URL(fileURLWithPath: p)), p)
        }
    }

    func testKindLookupByAbsolutePath() {
        let map = GitStatusMap.build(status: [("src/main.swift", .modified)], repoRoot: root)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("src/main.swift")), .modified)
        XCTAssertNil(map.kind(for: root.appendingPathComponent("src/other.swift")))
    }

    func testAncestorDirectoriesMarked() {
        let map = GitStatusMap.build(status: [("a/b/c/file.swift", .added)], repoRoot: root)
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("a")))
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("a/b")))
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("a/b/c")))
        XCTAssertTrue(map.directoryContainsChanges(root))  // root itself
        XCTAssertFalse(map.directoryContainsChanges(root.appendingPathComponent("z")))
    }

    /// A deleted file keeps its kind (a tab for a file that is gone says "D") and dots the
    /// folder it was in — a folder whose only change is a deletion used to show nothing —
    /// while the search scope leaves it out: there is no text to search.
    func testDeletedFileKeptForLookupsAndDotsButNotListed() {
        let map = GitStatusMap.build(status: [("src/gone.swift", .deleted)], repoRoot: root)
        XCTAssertNotEqual(map, .empty)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("src/gone.swift")), .deleted)
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("src")))
        XCTAssertTrue(map.directoryContainsChanges(root))
        XCTAssertEqual(map.changedFilePaths, [])
    }

    func testDeletedMixedWithLiveListsLiveOnly() {
        let map = GitStatusMap.build(
            status: [("keep.swift", .modified), ("gone.swift", .deleted)], repoRoot: root)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("keep.swift")), .modified)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("gone.swift")), .deleted)
        XCTAssertEqual(map.changedFilePaths, [root.appendingPathComponent("keep.swift").path])
    }

    /// `mv Foo.ts foo.ts` on the default case-insensitive volume: git keeps reporting `Foo.ts`
    /// while the tree lists `foo.ts`. The exact lookup misses; the folded one hits.
    func testCaseOnlyRenameStillFindsTheEntry() {
        let map = GitStatusMap.build(status: [("src/Foo.ts", .modified)], repoRoot: root)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("src/foo.ts")), .modified)
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("SRC/FOO.TS")), .modified)
        XCTAssertNil(map.kind(for: root.appendingPathComponent("src/bar.ts")))
    }

    /// A project opened through a symlink: git resolves the root to the real path, rows carry
    /// the symlink path. The opened folder passed as an alias keys every entry under it too.
    func testOpenedFolderAliasKeysEntriesAndDots() {
        let opened = URL(fileURLWithPath: "/Users/someone/link")
        let map = GitStatusMap.build(status: [("src/a.swift", .modified)], repoRoot: root, aliases: [opened])
        XCTAssertEqual(map.kind(for: opened.appendingPathComponent("src/a.swift")), .modified)
        XCTAssertTrue(map.directoryContainsChanges(opened.appendingPathComponent("src")))
        XCTAssertTrue(map.directoryContainsChanges(opened))
        XCTAssertEqual(map.kind(for: root.appendingPathComponent("src/a.swift")), .modified)
        XCTAssertEqual(map.changedFilePaths.count, 1, "one list entry per file, not per alias")
    }

    /// `merge(propagatingTo:aliases:)` dots the ancestors up to each alias of the opened folder.
    func testMergePropagatesToEveryTopAlias() {
        let nested = root.appendingPathComponent("plugins/one")
        let map = GitStatusMap.build(status: [("lib/x.swift", .modified)], repoRoot: nested)
        let alias = URL(fileURLWithPath: "/elsewhere")
        let aliasNested = GitStatusMap.build(status: [("lib/y.swift", .added)], repoRoot: alias.appendingPathComponent("plugins/two"))
        let merged = GitStatusMap.merge([map, aliasNested], propagatingTo: root, aliases: [alias])
        XCTAssertTrue(merged.directoryContainsChanges(root.appendingPathComponent("plugins")))
        XCTAssertTrue(merged.directoryContainsChanges(root))
        XCTAssertTrue(merged.directoryContainsChanges(alias.appendingPathComponent("plugins")))
        XCTAssertTrue(merged.directoryContainsChanges(alias))
    }

    /// A submodule pointer bump is ` M sub` with no slash, yet `sub` is a directory on disk:
    /// the folder gets a dot and nothing is listed as a file.
    func testSubmoduleEntryIsADirectoryNotAFile() throws {
        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitmap-submodule-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("vendor/sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let map = GitStatusMap.build(status: [("vendor/sub", .modified)], repoRoot: real)
        XCTAssertNil(map.kind(for: real.appendingPathComponent("vendor/sub")))
        XCTAssertTrue(map.directoryContainsChanges(real.appendingPathComponent("vendor/sub")))
        XCTAssertTrue(map.directoryContainsChanges(real.appendingPathComponent("vendor")))
        XCTAssertEqual(map.changedFilePaths, [])
    }

    func testUntrackedDirectoryEntryMarksFolderNotFile() {
        // The collapsed "?? NewFeature/" form: the folder gets a dot, but there's
        // no file kind to look up.
        let map = GitStatusMap.build(status: [("NewFeature/", .untracked)], repoRoot: root)
        XCTAssertTrue(map.directoryContainsChanges(root.appendingPathComponent("NewFeature")))
        XCTAssertNil(map.kind(for: root.appendingPathComponent("NewFeature")))
    }

    func testEmptyStatusYieldsEmptyMap() {
        XCTAssertEqual(GitStatusMap.build(status: [], repoRoot: root), .empty)
    }

    func testPrivateVarAliasingResolvesUnderTempDir() throws {
        // A real temp dir lives under /var → /private/var (a macOS symlink). A
        // lookup keyed via the /private side must still hit an entry built from
        // the /var side (and vice-versa).
        let realRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitStatusMapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: realRoot) }

        let map = GitStatusMap.build(status: [("f.swift", .modified)], repoRoot: realRoot)
        let stripped = URL(fileURLWithPath: (realRoot.path as NSString).resolvingSymlinksInPath).appendingPathComponent("f.swift")
        XCTAssertEqual(map.kind(for: stripped), .modified)
    }
}
