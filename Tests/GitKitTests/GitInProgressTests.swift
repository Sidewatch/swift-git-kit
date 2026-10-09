//
//  GitInProgressTests.swift
//  GitKitTests
//
//  Tests for detecting a merge, rebase or cherry-pick left half-done.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Detecting a merge, rebase or cherry-pick left half-done, from git's own state files.
final class GitInProgressTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitinprogress")
        try repo.write("base\n", to: "f.txt")
        repo.commitAll("base")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    /// Two branches editing the same line two ways, with `other` checked out last.
    private func divergeOnLine(branch other: String) throws -> String {
        let main = repo.branch()
        repo.git(["checkout", "-q", "-b", other])
        try repo.write("\(other)\n", to: "f.txt")
        repo.commitAll(other)
        repo.git(["checkout", "-q", main])
        try repo.write("main side\n", to: "f.txt")
        repo.commitAll("main side")
        return main
    }

    func testACleanRepositoryHasNoOperationInProgress() {
        XCTAssertNil(Git.inProgressOperation(repoRoot: repo.root))
        XCTAssertNil(Git.rebaseHeadName(repoRoot: repo.root))
    }

    func testAConflictedMergeIsAMerge() throws {
        _ = try divergeOnLine(branch: "theirs")
        _ = Git.run(["merge", "theirs"], in: repo.root, allowedStatuses: [1])
        XCTAssertEqual(Git.inProgressOperation(repoRoot: repo.root), .merge)
        repo.git(["merge", "--abort"])
        XCTAssertNil(Git.inProgressOperation(repoRoot: repo.root))
    }

    func testAStoppedRebaseIsARebaseAndNamesItsBranch() throws {
        let main = try divergeOnLine(branch: "rb")
        repo.git(["checkout", "-q", "rb"])
        _ = Git.run(["rebase", main], in: repo.root, allowedStatuses: [1, 128])
        XCTAssertEqual(Git.inProgressOperation(repoRoot: repo.root), .rebase)
        XCTAssertEqual(Git.rebaseHeadName(repoRoot: repo.root), "rb")
        repo.git(["rebase", "--abort"])
    }

    func testAConflictedCherryPickIsACherryPick() throws {
        _ = try divergeOnLine(branch: "pick")
        _ = Git.run(["cherry-pick", "pick"], in: repo.root, allowedStatuses: [1])
        XCTAssertEqual(Git.inProgressOperation(repoRoot: repo.root), .cherryPick)
        repo.git(["cherry-pick", "--abort"])
    }
}
