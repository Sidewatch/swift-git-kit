//
//  GitInitTests.swift
//  GitKitTests
//
//  Tests for `Git.initRepository`: a folder becomes its own repository, nested checkouts
//  included, and a folder that is not there fails with a result rather than a repository elsewhere.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Tests for `Git.initRepository`.
final class GitInitTests: XCTestCase {

    private func tempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("init-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func resolved(_ url: URL?) -> String? { url?.resolvingSymlinksInPath().standardizedFileURL.path }

    func testAnEmptyFolderBecomesARepository() throws {
        let dir = try tempDir()
        XCTAssertNil(Git.repoRoot(for: dir), "precondition: the temporary directory is in no repository")
        let result = Git.initRepository(at: dir)
        XCTAssertTrue(result.succeeded, result.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git/HEAD").path))
        XCTAssertEqual(resolved(Git.repoRoot(for: dir)), resolved(dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [".git"], "no files beside .git")
    }

    func testAFolderInsideAnotherCheckoutBecomesItsOwnRepository() throws {
        let outer = try ScratchRepo(label: "init-outer")
        // A directory URL: repoRoot(for:) reads a file URL's parent.
        let inner = outer.root.appendingPathComponent("packages/new", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        XCTAssertEqual(resolved(Git.repoRoot(for: inner)), resolved(outer.root), "precondition: inside the outer checkout")
        XCTAssertTrue(Git.initRepository(at: inner).succeeded)
        XCTAssertEqual(resolved(Git.repoRoot(for: inner)), resolved(inner))
    }

    func testAMissingFolderFailsAndCreatesNothing() throws {
        let parent = try tempDir()
        let missing = parent.appendingPathComponent("not-here", isDirectory: true)
        let result = Git.initRepository(at: missing)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent(".git").path), "no repository beside it")
    }
}
