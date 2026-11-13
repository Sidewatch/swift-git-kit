//
//  GitPushTests.swift
//  GitKitTests
//
//  Tests for pushing the current branch to a bare remote on disk.
//
//  Created by David Sherlock on 10/23/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// Pushing the checked-out branch: to the branch it tracks, or published to the one remote.
final class GitPushTests: XCTestCase {

    private var repo: ScratchRepo!
    private var remotes: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        repo = try ScratchRepo(label: "gitpush")
        try repo.write("one\n", to: "f.txt")
        repo.commitAll("one")
    }

    override func tearDown() {
        repo.cleanup()
        for remote in remotes { try? FileManager.default.removeItem(at: remote) }
        super.tearDown()
    }

    /// A bare repository on disk, added to the scratch repository as `name`.
    @discardableResult
    private func addRemote(_ name: String) -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gitpush-remote-\(UUID().uuidString).git")
        _ = Git.run(["init", "-q", "--bare", dir.path], in: URL(fileURLWithPath: NSTemporaryDirectory()))
        remotes.append(dir)
        repo.git(["remote", "add", name, dir.path])
        return dir
    }

    /// The commit `ref` names in `bare`, or "".
    private func head(of ref: String, in bare: URL) -> String {
        Git.run(["rev-parse", "--verify", "-q", ref], in: bare)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func testABranchThatTracksNothingIsPublishedThenPushedToItsUpstream() {
        let origin = addRemote("origin")
        let branch = repo.branch()
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("origin/\(branch)"))
        XCTAssertEqual(head(of: "refs/heads/\(branch)", in: origin), repo.head())
        XCTAssertNotNil(Git.upstream(of: branch, repoRoot: repo.root), "publishing sets the upstream")

        try? repo.write("two\n", to: "f.txt")
        repo.commitAll("two")
        XCTAssertEqual(Git.aheadBehind(repoRoot: repo.root).ahead, 1)
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("origin/\(branch)"))
        XCTAssertEqual(head(of: "refs/heads/\(branch)", in: origin), repo.head())
        XCTAssertEqual(Git.aheadBehind(repoRoot: repo.root).ahead, 0)
    }

    func testABranchTrackingALocalBranchIsPublishedNotPushedIntoThisRepository() {
        let origin = addRemote("origin")
        let main = repo.branch(), mainHead = repo.head()
        repo.git(["checkout", "-q", "-b", "topic", "--track", main])
        try? repo.write("two\n", to: "f.txt")
        repo.commitAll("two")
        XCTAssertEqual(Git.pushTarget(repoRoot: repo.root).map(\.publishes), .success(true))
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("origin/topic"))
        XCTAssertEqual(head(of: "refs/heads/topic", in: origin), repo.head(), "the commits reached the remote")
        XCTAssertEqual(head(of: "refs/heads/\(main)", in: repo.root), mainHead, "the local branch it tracks did not move")
        XCTAssertTrue(Git.tracksLocalBranch("topic", repoRoot: repo.root), "and it still tracks what it was told to")
    }

    func testABranchIsMeasuredFromThePreferredBaseAndElseTheDefault() throws {
        let origin = addRemote("origin")
        let main = repo.branch()
        repo.git(["push", "-q", "origin", main])
        // A release branch two commits on from main, then a topic branch off the release.
        repo.git(["checkout", "-q", "-b", "release/2.0"])
        try repo.write("release\n", to: "r.txt")
        let releaseHead = repo.commitAll("release work")
        repo.git(["push", "-q", "origin", "release/2.0"])
        repo.git(["checkout", "-q", "-b", "topic"])
        try repo.write("topic\n", to: "t.txt")
        repo.commitAll("topic work")
        let mainHead = head(of: "refs/heads/\(main)", in: origin)

        let automatic = try XCTUnwrap(Git.branchBase(repoRoot: repo.root))
        XCTAssertEqual(automatic.commit, mainHead, "with nothing preferred: where it left the integration branch")
        let preferred = try XCTUnwrap(Git.branchBase(repoRoot: repo.root, preferred: "release/2.0"))
        XCTAssertEqual(
            preferred, GitBranchBase(ref: "release/2.0", commit: releaseHead),
            "a pull request into the release shows the topic's work alone")

        // The release branch only on the remote, as a fresh checkout of the topic has it.
        repo.git(["branch", "-q", "-D", "release/2.0"])
        let remoteOnly = try XCTUnwrap(Git.branchBase(repoRoot: repo.root, preferred: "release/2.0"))
        XCTAssertEqual(remoteOnly, GitBranchBase(ref: "origin/release/2.0", commit: releaseHead))
        XCTAssertEqual(
            Git.branchBase(repoRoot: repo.root, preferred: "no/such/branch")?.commit, mainHead, "a base that is not there falls back")

        let candidates = Git.baseCandidates(repoRoot: repo.root)
        XCTAssertEqual(
            candidates, ["origin/\(main)", "origin/release/2.0", main],
            "the remote's branches, then local ones, without the branch checked out")
    }

    func testAShallowCloneWithNoSharedCommitIsMeasuredFromTheBasesTipAndSaysSo() throws {
        let origin = addRemote("origin")
        let main = repo.branch()
        repo.git(["push", "-q", "origin", main])
        repo.git(["checkout", "-q", "-b", "topic"])
        try repo.write("topic\n", to: "t.txt")
        repo.commitAll("topic work")
        repo.git(["push", "-q", "origin", "topic"])
        let mainTip = head(of: "refs/heads/\(main)", in: origin)

        // One commit of the topic and one of main, as a CI checkout has them: no commit in common.
        let shallow = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gitpush-shallow-\(UUID().uuidString)")
        remotes.append(shallow)
        _ = Git.run(
            ["clone", "-q", "--depth", "1", "--branch", "topic", "file://" + origin.path, shallow.path],
            in: URL(fileURLWithPath: NSTemporaryDirectory()))
        _ = Git.run(["fetch", "-q", "--depth", "1", "origin", "\(main):refs/remotes/origin/\(main)"], in: shallow)
        XCTAssertEqual(
            Git.run(["rev-parse", "--is-shallow-repository"], in: shallow)?.trimmingCharacters(in: .whitespacesAndNewlines), "true")
        XCTAssertNil(Git.mergeBase(with: "origin/\(main)", repoRoot: shallow), "the clone holds no commit the two share")

        // Nothing preferred: the clone has no `origin/HEAD` and no local main, only the remote's main.
        XCTAssertNil(Git.run(["rev-parse", "--verify", "--quiet", "origin/HEAD"], in: shallow))
        XCTAssertEqual(Git.branchBase(repoRoot: shallow)?.ref, "origin/\(main)", "the integration branch is found on the remote")
        let base = try XCTUnwrap(Git.branchBase(repoRoot: shallow, preferred: main))
        XCTAssertEqual(base.ref, "origin/\(main)")
        XCTAssertEqual(base.commit, mainTip, "the base's own tip")
        XCTAssertFalse(base.sharesHistory, "and it says the comparison is with the tip, not where the branch left it")

        // A full clone is unchanged: a real merge base, and no fallback for a ref that shares nothing.
        XCTAssertEqual(Git.branchBase(repoRoot: repo.root, preferred: main)?.sharesHistory, true)
    }

    func testAnUpstreamWithAnotherNameIsTheOnePushedTo() {
        let origin = addRemote("origin")
        repo.git(["push", "-q", "origin", "HEAD:refs/heads/trunk"])
        repo.git(["checkout", "-q", "-b", "work"])
        repo.git(["branch", "-q", "--set-upstream-to=origin/trunk"])
        try? repo.write("on work\n", to: "f.txt")
        repo.commitAll("on work")
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("origin/trunk"))
        XCTAssertEqual(head(of: "refs/heads/trunk", in: origin), repo.head())
        XCTAssertEqual(head(of: "refs/heads/work", in: origin), "", "no branch named after the local one was made")
    }

    func testWithoutOneRemoteToPublishToNothingIsSent() {
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .failure(.noRemote), "no remote")
        addRemote("upstream")
        addRemote("fork")
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .failure(.noRemote), "two remotes, neither origin")
        let origin = addRemote("origin")
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("origin/\(repo.branch())"), "origin among several")
        XCTAssertEqual(head(of: "refs/heads/\(repo.branch())", in: origin), repo.head())
    }

    func testTheOnlyRemoteIsPublishedToWhateverItsName() {
        let fork = addRemote("fork")
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("fork/\(repo.branch())"))
        XCTAssertEqual(head(of: "refs/heads/\(repo.branch())", in: fork), repo.head())
    }

    func testTheTargetSaysWhetherThePushPublishes() {
        addRemote("origin")
        let branch = repo.branch()
        XCTAssertEqual(Git.pushTarget(repoRoot: repo.root), .success(GitPushTarget(remote: "origin", branch: branch, publishes: true)))
        _ = Git.push(repoRoot: repo.root)
        XCTAssertEqual(Git.pushTarget(repoRoot: repo.root), .success(GitPushTarget(remote: "origin", branch: branch, publishes: false)))
    }

    func testThePendingPushCountsWhatWouldBeSent() {
        XCTAssertNil(Git.pendingPush(repoRoot: repo.root), "no remote: nothing to push")
        addRemote("origin")
        let branch = repo.branch()
        XCTAssertEqual(
            Git.pendingPush(repoRoot: repo.root),
            GitPendingPush(target: GitPushTarget(remote: "origin", branch: branch, publishes: true), ahead: 0),
            "an unpublished branch has itself to send")
        _ = Git.push(repoRoot: repo.root)
        XCTAssertNil(Git.pendingPush(repoRoot: repo.root), "level with its upstream")
        try? repo.write("two\n", to: "f.txt")
        repo.commitAll("two")
        try? repo.write("three\n", to: "f.txt")
        repo.commitAll("three")
        XCTAssertEqual(Git.pendingPush(repoRoot: repo.root)?.ahead, 2)
        XCTAssertEqual(Git.pendingPush(repoRoot: repo.root)?.target.publishes, false)
    }

    func testADetachedHeadIsNotPushed() {
        addRemote("origin")
        repo.git(["checkout", "-q", "--detach"])
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .failure(.detachedHead))
        XCTAssertNil(Git.pendingPush(repoRoot: repo.root))
    }

    func testARejectedPushSaysWhyInGitsWords() throws {
        let origin = addRemote("origin")
        XCTAssertEqual(Git.push(repoRoot: repo.root).map(\.name), .success("origin/\(repo.branch())"))
        // Someone else pushes first.
        let other = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gitpush-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        _ = Git.run(["clone", "-q", origin.path, other.path], in: URL(fileURLWithPath: NSTemporaryDirectory()))
        try "theirs\n".write(to: other.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        _ = Git.run(["-c", "user.name=Other", "-c", "user.email=o@example.com", "commit", "-qam", "theirs"], in: other)
        _ = Git.run(["push", "-q"], in: other)
        try repo.write("ours\n", to: "f.txt")
        repo.commitAll("ours")
        guard case .failure(.failed(let stderr)) = Git.push(repoRoot: repo.root) else { return XCTFail("the push was not refused") }
        XCTAssertTrue(stderr.contains("rejected"), stderr)
    }

    func testThePrePushHookRunsAndCanRefuse() throws {
        let origin = addRemote("origin")
        let hook = repo.root.appendingPathComponent(".git/hooks/pre-push")
        try "#!/bin/sh\necho 'tests must pass first' >&2\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        guard case .failure(.failed(let stderr)) = Git.push(repoRoot: repo.root) else { return XCTFail("the hook did not refuse") }
        XCTAssertTrue(stderr.contains("tests must pass first"), stderr)
        XCTAssertEqual(head(of: "refs/heads/\(repo.branch())", in: origin), "", "nothing reached the remote")
    }
}
