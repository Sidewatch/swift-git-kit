//
//  GitCheckIgnoreTests.swift
//  GitKitTests
//
//  Tests for asking git which paths it ignores.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Git's ignore verdict for several paths in one `check-ignore` run.
final class GitCheckIgnoreTests: XCTestCase {

    private var repo: ScratchRepo!

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitcheckignore")
    }

    override func tearDown() {
        repo.cleanup()
        super.tearDown()
    }

    func testPathsCreatedAfterAnyListingAreJudgedByGitsRules() throws {
        try repo.write("*.log\nbuild/\n!keep.log\n", to: ".gitignore")
        try repo.write("tracked\n", to: "forced.log")
        _ = repo.git(["add", "-f", "forced.log", ".gitignore"])
        _ = repo.commitAll("ignore rules")
        try repo.write("x\n", to: "sub dir/new.log")
        try repo.write("x\n", to: "build/out.txt")
        try repo.write("x\n", to: "keep.log")
        try repo.write("x\n", to: "plain.txt")
        let ignored = Git.ignoredPaths(
            ["sub dir/new.log", "build/out.txt", "keep.log", "plain.txt", "forced.log", "not-yet-created.log"], repoRoot: repo.root)
        XCTAssertEqual(ignored, ["sub dir/new.log", "build/out.txt", "not-yet-created.log"])
    }

    func testNothingIgnoredIsAnEmptySetNotAFailure() throws {
        try repo.write("*.log\n", to: ".gitignore")
        XCTAssertEqual(Git.ignoredPaths(["a.txt", "b/c.swift"], repoRoot: repo.root), [])
    }
}
