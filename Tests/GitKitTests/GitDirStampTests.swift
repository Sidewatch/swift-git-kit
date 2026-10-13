//
//  GitDirStampTests.swift
//  GitKitTests
//
//  The git-dir stamp against real repositories: what moves it, what does not, and the listings
//  it keeps for remotes and linked worktrees.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import XCTest
@testable import GitKit

final class GitDirStampTests: XCTestCase {

    private func committedRepo() throws -> ScratchRepo {
        let repo = try ScratchRepo(label: "gitdirstamp")
        try repo.write("one\n", to: "a.txt")
        repo.commitAll("first")
        return repo
    }

    func testResolveIsNilOutsideARepository() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNil(GitDirStamp.resolve(repoRoot: dir))
    }

    func testAnUnchangedRepositoryKeepsItsStamp() throws {
        let repo = try committedRepo()
        var stamp = try XCTUnwrap(GitDirStamp.resolve(repoRoot: repo.root))
        let first = stamp.stat()
        XCTAssertEqual(stamp.stat(), first, "nothing happened, so nothing moved")
        XCTAssertFalse(stamp.infoExcludeMoved, "the exclude file did not move between two stats")
    }

    func testACommitMovesTheStamp() throws {
        let repo = try committedRepo()
        var stamp = try XCTUnwrap(GitDirStamp.resolve(repoRoot: repo.root))
        let before = stamp.stat()
        try repo.write("two\n", to: "a.txt")
        repo.commitAll("second")
        XCTAssertNotEqual(stamp.stat(), before, "a commit outside the app moves HEAD's reflog")
    }

    func testAnEditToInfoExcludeIsReportedOnce() throws {
        let repo = try committedRepo()
        var stamp = try XCTUnwrap(GitDirStamp.resolve(repoRoot: repo.root))
        _ = stamp.stat()
        let exclude = stamp.commonDir.appendingPathComponent("info/exclude")
        try FileManager.default.createDirectory(at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "*.log\n".write(to: exclude, atomically: true, encoding: .utf8)
        _ = stamp.stat()
        XCTAssertTrue(stamp.infoExcludeMoved, "the ignore rules changed")
        _ = stamp.stat()
        XCTAssertFalse(stamp.infoExcludeMoved, "and the next stat, with no further edit, says so no more")
    }

    func testANewRemoteTrackingRefIsListedAndWatched() throws {
        let repo = try committedRepo()
        var stamp = try XCTUnwrap(GitDirStamp.resolve(repoRoot: repo.root))
        XCTAssertTrue(stamp.remoteDirs.isEmpty)
        _ = stamp.stat()
        repo.git(["update-ref", "refs/remotes/origin/main", "HEAD"])
        _ = stamp.stat()
        XCTAssertEqual(stamp.remoteDirs.map(\.lastPathComponent), ["origin"], "a remote's refs folder appearing re-lists the remotes")
        XCTAssertTrue(stamp.watchedPaths.contains { $0.lastPathComponent == "origin" })
    }

    func testALinkedWorktreeIsListedAndItsHeadWatched() throws {
        let repo = try committedRepo()
        var stamp = try XCTUnwrap(GitDirStamp.resolve(repoRoot: repo.root))
        _ = stamp.stat()
        let linked = repo.root.deletingLastPathComponent().appendingPathComponent("linked-\(UUID().uuidString)")
        repo.git(["worktree", "add", "-q", "-b", "side", linked.path])
        let afterAdd = stamp.stat()
        XCTAssertEqual(stamp.worktreeDirs.count, 1, "a `git worktree add` re-lists the worktrees")
        let head = try XCTUnwrap(stamp.worktreeDirs.first).appendingPathComponent("HEAD")
        XCTAssertTrue(stamp.watchedPaths.contains(head), "the linked worktree's HEAD is watched")
        try "two\n".write(to: linked.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(Git.run(["commit", "-qam", "side"], in: linked))
        XCTAssertNotEqual(stamp.stat(), afterAdd, "a commit in the linked worktree moves the main checkout's stamp")
    }

    func testALinkedWorktreeSharesItsCommonDir() throws {
        let repo = try committedRepo()
        let linked = repo.root.deletingLastPathComponent().appendingPathComponent("linked-\(UUID().uuidString)")
        repo.git(["worktree", "add", "-q", "-b", "other", linked.path])
        let main = try XCTUnwrap(GitDirStamp.resolve(repoRoot: repo.root))
        let side = try XCTUnwrap(GitDirStamp.resolve(repoRoot: linked))
        XCTAssertEqual(side.commonDir.resolvingSymlinksInPath(), main.commonDir.resolvingSymlinksInPath())
        XCTAssertNotEqual(side.gitDir.resolvingSymlinksInPath(), main.gitDir.resolvingSymlinksInPath())
    }
}
