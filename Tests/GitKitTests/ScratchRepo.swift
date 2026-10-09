//
//  ScratchRepo.swift
//  GitKitTests
//
//  A throwaway repository for one test: created in the temporary directory with a fixed
//  identity and signing off, driven through `Git.run`, removed in tearDown.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import XCTest
@testable import GitKit

/// A throwaway repository for one test.
final class ScratchRepo {

    /// The repository root as git reports it (`/private/var/...` on macOS).
    let root: URL

    /// A fresh repository with one configured identity, signing off, no commits.
    init(label: String = "gitkit", file: StaticString = #filePath, line: UInt = #line) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNotNil(Git.run(["init", "-q"], in: dir), "git init failed", file: file, line: line)
        _ = Git.run(["config", "user.email", "test@example.com"], in: dir)
        _ = Git.run(["config", "user.name", "Test Author"], in: dir)
        _ = Git.run(["config", "commit.gpgsign", "false"], in: dir)
        root = try XCTUnwrap(Git.repoRoot(for: dir), "repoRoot returned nil", file: file, line: line)
    }

    /// The URL of a repository-relative path.
    func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    /// Writes `contents` to `name`, creating directories on the way.
    func write(_ contents: String, to name: String) throws {
        try FileManager.default.createDirectory(at: url(name).deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url(name), atomically: true, encoding: .utf8)
    }

    /// Writes raw bytes to `name`.
    func write(_ data: Data, to name: String) throws {
        try data.write(to: url(name))
    }

    /// Deletes `name` from the working tree.
    func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: url(name))
    }

    /// `git <args>` here.
    @discardableResult
    func git(_ args: [String]) -> String? { Git.run(args, in: root) }

    /// `git add -A` then `git commit`; the new HEAD.
    @discardableResult
    func commitAll(_ message: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertNotNil(git(["add", "-A"]), "git add failed", file: file, line: line)
        XCTAssertNotNil(git(["commit", "-q", "-m", message]), "git commit failed", file: file, line: line)
        return head()
    }

    /// The full SHA of `HEAD`.
    func head() -> String {
        git(["rev-parse", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The name of the checked-out branch, whatever `init.defaultBranch` says.
    func branch() -> String {
        git(["symbolic-ref", "--short", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// `git status --porcelain=v1` as `XY path` lines.
    func porcelain() -> [String] {
        (git(["status", "--porcelain=v1"]) ?? "").split(separator: "\n").map(String.init)
    }

    /// Leaves the repository mid-merge with `file` in conflict (`UU`): two branches editing one
    /// line two ways.
    func makeMergeConflict(in file: String = "conflict.txt") {
        try? write("base\n", to: file)
        commitAll("conflict base")
        let main = branch()
        git(["checkout", "-q", "-b", "theirs"])
        try? write("theirs\n", to: file)
        commitAll("theirs")
        git(["checkout", "-q", main])
        try? write("ours\n", to: file)
        commitAll("ours")
        _ = Git.run(["merge", "theirs"], in: root, allowedStatuses: [1])
    }

    /// Removes the repository.
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
