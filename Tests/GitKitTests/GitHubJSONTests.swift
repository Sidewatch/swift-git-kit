//
//  GitHubJSONTests.swift
//  GitKitTests
//
//  What GitHub's CLI prints, read: a pull request, its checks as one word, its review comments.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import GitKit

/// The fixtures are real output of `gh pr view --json` and `gh api …/pulls/<n>/comments` (gh 2.103,
/// November 2026) with every key kept as GitHub wrote it; the people, repository, texts and
/// addresses are replaced with invented ones. A field GitHub renames fails here.
final class GitHubJSONTests: XCTestCase {

    private let pullRequestJSON = #"""
        {
          "baseRefName": "release/2.0",
          "headRefName": "fix/status-errors",
          "isDraft": false,
          "number": 42,
          "reviewDecision": "APPROVED",
          "state": "OPEN",
          "statusCheckRollup": [
            {
              "__typename": "CheckRun",
              "completedAt": "2026-11-10T10:31:13Z",
              "conclusion": "SUCCESS",
              "detailsUrl": "https://github.com/example-org/harbour/actions/runs/1/job/1",
              "name": "build",
              "startedAt": "2026-11-10T10:28:05Z",
              "status": "COMPLETED",
              "workflowName": "CI"
            },
            {
              "__typename": "CheckRun",
              "completedAt": "2026-11-10T10:30:02Z",
              "conclusion": "SKIPPED",
              "detailsUrl": "https://github.com/example-org/harbour/actions/runs/1/job/2",
              "name": "lint",
              "startedAt": "2026-11-10T10:28:07Z",
              "status": "COMPLETED",
              "workflowName": "CI"
            },
            {
              "__typename": "CheckRun",
              "completedAt": "2026-11-10T10:31:05Z",
              "conclusion": "SUCCESS",
              "detailsUrl": "https://github.com/example-org/harbour/actions/runs/1/job/3",
              "name": "unit-tests",
              "startedAt": "2026-11-10T10:28:09Z",
              "status": "COMPLETED",
              "workflowName": "CI"
            }
          ],
          "title": "Report the underlying error in the status output",
          "url": "https://github.com/example-org/harbour/pull/42"
        }
        """#

    private let commentsJSON = #"""
        [
          {
            "id": 4523565956,
            "path": "Sources/Status/Status.swift",
            "line": null,
            "original_line": 403,
            "side": "RIGHT",
            "start_line": null,
            "start_side": "RIGHT",
            "created_at": "2026-11-10T10:08:38Z",
            "updated_at": "2026-11-10T10:09:08Z",
            "html_url": "https://github.com/example-org/harbour/pull/42#discussion_r4523565956",
            "body": "This belongs in `Entry.describe`, not at the call site.",
            "user": {
              "login": "mira-okafor",
              "id": 1000,
              "type": "User"
            },
            "diff_hunk": "@@ -400,3 +400,6 @@ func render()\n+    print(error)",
            "subject_type": "line",
            "position": 1,
            "original_position": 6,
            "commit_id": "1111111111111111111111111111111111111111",
            "pull_request_review_id": 5840066601
          },
          {
            "id": 4523608564,
            "path": "Sources/Status/Status.swift",
            "line": null,
            "original_line": 403,
            "side": "RIGHT",
            "start_line": null,
            "start_side": "RIGHT",
            "in_reply_to_id": 4523565956,
            "created_at": "2026-11-10T10:13:21Z",
            "updated_at": "2026-11-10T10:13:21Z",
            "html_url": "https://github.com/example-org/harbour/pull/42#discussion_r4523608564",
            "body": "Moved in the next commit.",
            "user": {
              "login": "tomas-lindqvist",
              "id": 1001,
              "type": "User"
            },
            "diff_hunk": "@@ -400,3 +400,6 @@ func render()\n+    print(error)",
            "subject_type": "line",
            "position": 1,
            "original_position": 6,
            "commit_id": "1111111111111111111111111111111111111111",
            "pull_request_review_id": 5840121014
          },
          {
            "id": 4523665955,
            "path": "README.md",
            "line": 12,
            "original_line": 12,
            "side": "RIGHT",
            "start_line": null,
            "start_side": "RIGHT",
            "created_at": "2026-11-11T09:00:00Z",
            "updated_at": "2026-11-10T10:09:08Z",
            "html_url": "https://github.com/example-org/harbour/pull/42#discussion_r4523665955",
            "body": "Say which version this starts in.",
            "user": {
              "login": "mira-okafor",
              "id": 1000,
              "type": "User"
            },
            "diff_hunk": "@@ -400,3 +400,6 @@ func render()\n+    print(error)",
            "subject_type": "line",
            "position": 1,
            "original_position": 6,
            "commit_id": "1111111111111111111111111111111111111111",
            "pull_request_review_id": 5840066601
          }
        ]
        """#

    func testAPullRequestIsReadFromGhPrView() throws {
        let pr = try XCTUnwrap(GitHubJSON.pullRequest(from: Data(pullRequestJSON.utf8)))
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Report the underlying error in the status output")
        XCTAssertEqual(pr.url, "https://github.com/example-org/harbour/pull/42")
        XCTAssertEqual(pr.baseBranch, "release/2.0", "the branch it merges into, which its diff is against")
        XCTAssertEqual(pr.headBranch, "fix/status-errors")
        XCTAssertTrue(pr.isOpen)
        XCTAssertFalse(pr.isDraft)
        XCTAssertEqual(pr.checks, .passing, "two successes and a skipped check")
        for field in GitHubJSON.pullRequestFields.split(separator: ",") {
            XCTAssertTrue(pullRequestJSON.contains("\"\(field)\""), "gh's real output carries \(field)")
        }
    }

    func testWhatIsNotAPullRequestIsNil() {
        XCTAssertNil(GitHubJSON.pullRequest(from: Data("no pull requests found for branch \"topic\"".utf8)))
        XCTAssertNil(GitHubJSON.pullRequest(from: Data("{}".utf8)))
        XCTAssertNil(GitHubJSON.pullRequest(from: Data()))
    }

    func testChecksAreOneWord() {
        func run(_ status: String, _ conclusion: String) -> [String: Any] {
            ["__typename": "CheckRun", "name": "x", "status": status, "conclusion": conclusion]
        }
        func context(_ state: String) -> [String: Any] { ["__typename": "StatusContext", "context": "x", "state": state] }
        XCTAssertEqual(GitHubJSON.checks(from: []), .none)
        XCTAssertEqual(
            GitHubJSON.checks(from: [run("COMPLETED", "SUCCESS"), run("COMPLETED", "SKIPPED"), run("COMPLETED", "NEUTRAL")]), .passing)
        XCTAssertEqual(GitHubJSON.checks(from: [run("COMPLETED", "SUCCESS"), run("IN_PROGRESS", "")]), .running)
        XCTAssertEqual(GitHubJSON.checks(from: [run("QUEUED", "")]), .running)
        for failed in ["FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"] {
            XCTAssertEqual(GitHubJSON.checks(from: [run("COMPLETED", "SUCCESS"), run("COMPLETED", failed)]), .failing, failed)
        }
        XCTAssertEqual(
            GitHubJSON.checks(from: [run("IN_PROGRESS", ""), run("COMPLETED", "FAILURE")]), .failing,
            "a failure outranks a check still running")
        // A commit status (an older integration) reports a `state`, no `status` or `conclusion`.
        XCTAssertEqual(GitHubJSON.checks(from: [context("SUCCESS")]), .passing)
        XCTAssertEqual(GitHubJSON.checks(from: [context("SUCCESS"), context("PENDING")]), .running)
        XCTAssertEqual(GitHubJSON.checks(from: [context("ERROR")]), .failing)
        XCTAssertEqual(GitHubJSON.checks(from: [context("FAILURE"), run("COMPLETED", "SUCCESS")]), .failing)
    }

    func testReviewCommentsAreReadOldestFirst() throws {
        let comments = GitHubJSON.reviewComments(from: Data(commentsJSON.utf8))
        XCTAssertEqual(comments.count, 3)
        let first = try XCTUnwrap(comments.first)
        XCTAssertEqual(first.path, "Sources/Status/Status.swift")
        XCTAssertEqual(first.author, "mira-okafor")
        XCTAssertEqual(first.body, "This belongs in `Entry.describe`, not at the call site.")
        XCTAssertNil(first.line, "GitHub gives an outdated comment no line")
        XCTAssertTrue(first.isOutdated)
        XCTAssertEqual(first.originalLine, 403)
        XCTAssertTrue(first.isOnNewSide)
        XCTAssertNotNil(first.createdAt)
        XCTAssertEqual(comments[1].inReplyTo, first.id, "a reply names the comment it answers")
        XCTAssertEqual(comments[2].path, "README.md")
        XCTAssertEqual(comments[2].line, 12)
        XCTAssertFalse(comments[2].isOutdated)
        XCTAssertTrue(comments[2].url.hasPrefix("https://github.com/example-org/harbour/pull/42#discussion_r"))
    }

    func testPagesPrintedBackToBackAreAllRead() {
        // `gh api --paginate` prints one array per page with nothing between them.
        let one = #"[{"id": 1, "path": "a]b.swift", "body": "has ][ in \"it\"", "user": {"login": "x"}}]"#
        let two = #"[{"id": 2, "path": "c.swift", "body": "second", "user": {"login": "y"}, "tags": ["m", "n"]}]"#
        let comments = GitHubJSON.reviewComments(from: Data((one + two).utf8))
        XCTAssertEqual(comments.map(\.id), [1, 2])
        XCTAssertEqual(comments.first?.path, "a]b.swift")
        XCTAssertEqual(comments.first?.body, "has ][ in \"it\"")
        XCTAssertEqual(GitHubJSON.reviewComments(from: Data((one + "\n" + two + "\n[]").utf8)).count, 2)
        XCTAssertTrue(GitHubJSON.reviewComments(from: Data("not json".utf8)).isEmpty)
    }

    func testTheCLIReadsThroughItsRunnerAndAsksOnlyToRead() {
        let asked = Asked()
        let prData = Data(pullRequestJSON.utf8), commentData = Data(commentsJSON.utf8)
        let run: GitHubCLI.Runner = { arguments, _ in
            asked.add(arguments)
            return arguments.first == "pr" ? prData : commentData
        }
        let here = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertEqual(GitHubCLI.pullRequest(cwd: here, run: run)?.number, 42)
        XCTAssertEqual(GitHubCLI.reviewComments(number: 42, cwd: here, run: run).count, 3)
        XCTAssertEqual(
            asked.all,
            [["pr", "view", "--json", GitHubJSON.pullRequestFields], ["api", "--paginate", "repos/{owner}/{repo}/pulls/42/comments"]])
        XCTAssertNil(GitHubCLI.pullRequest(cwd: here, run: { _, _ in nil }), "no gh, no network, no pull request: nothing")
        XCTAssertTrue(GitHubCLI.reviewComments(number: 42, cwd: here, run: { _, _ in nil }).isEmpty)
    }
}

/// The argument lists a runner was called with, readable from any thread.
private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var lists: [[String]] = []
    func add(_ arguments: [String]) { lock.withLock { lists.append(arguments) } }
    var all: [[String]] { lock.withLock { lists } }
}
