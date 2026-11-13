//
//  GitHubJSON.swift
//  GitKit
//
//  Reads what GitHub's CLI prints: a pull request, its checks, its review comments.
//
//  Created by David Sherlock on 11/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The JSON GitHub's CLI prints, read into this package's models. The field names are GitHub's
/// (`gh pr view --json …`, the REST API's `pulls/<n>/comments`); the tests hold real output of
/// both, so a renamed field fails there.
public enum GitHubJSON {

    /// The fields ``pullRequest(from:)`` reads, as `gh pr view --json` takes them.
    public static let pullRequestFields = "number,title,url,baseRefName,headRefName,state,isDraft,statusCheckRollup"

    /// The pull request in the output of `gh pr view --json` with ``pullRequestFields``; nil for
    /// anything else (an error message, a branch with no pull request).
    public static func pullRequest(from data: Data) -> GitHubPullRequest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let number = json["number"] as? Int, let base = json["baseRefName"] as? String, !base.isEmpty
        else { return nil }
        return GitHubPullRequest(
            number: number, title: json["title"] as? String ?? "", url: json["url"] as? String ?? "", baseBranch: base,
            headBranch: json["headRefName"] as? String ?? "", state: json["state"] as? String ?? "",
            isDraft: json["isDraft"] as? Bool ?? false, checks: checks(from: json["statusCheckRollup"] as? [[String: Any]] ?? []))
    }

    /// The conclusions of a finished check that count as passed.
    static let passedConclusions: Set<String> = ["SUCCESS", "SKIPPED", "NEUTRAL"]
    /// The states of a commit status that have not concluded.
    static let waitingStates: Set<String> = ["PENDING", "EXPECTED"]

    /// One word for a `statusCheckRollup`: a check run (`status`, `conclusion`) or a commit status
    /// (`state`) each count once. Anything failed makes it ``GitHubChecks/failing``; else anything
    /// unfinished makes it ``GitHubChecks/running``.
    static func checks(from rollup: [[String: Any]]) -> GitHubChecks {
        guard !rollup.isEmpty else { return .none }
        var running = false
        for check in rollup {
            if let state = (check["state"] as? String)?.uppercased(), !state.isEmpty {
                if waitingStates.contains(state) { running = true } else if state != "SUCCESS" { return .failing }
                continue
            }
            let status = (check["status"] as? String ?? "").uppercased()
            let conclusion = (check["conclusion"] as? String ?? "").uppercased()
            if status != "COMPLETED" { running = true } else if !passedConclusions.contains(conclusion) { return .failing }
        }
        return running ? .running : .passing
    }

    /// The review comments in the output of `gh api repos/{owner}/{repo}/pulls/<n>/comments`,
    /// oldest first. With `--paginate` the CLI prints one array per page, one after another: every
    /// array is read.
    public static func reviewComments(from data: Data) -> [GitHubReviewComment] {
        let formatter = ISO8601DateFormatter()
        return arrays(in: data).flatMap { $0 }.compactMap { item -> GitHubReviewComment? in
            guard let id = item["id"] as? Int, let path = item["path"] as? String, let body = item["body"] as? String else { return nil }
            return GitHubReviewComment(
                id: id, path: path, line: item["line"] as? Int, originalLine: item["original_line"] as? Int,
                side: item["side"] as? String ?? "RIGHT", author: (item["user"] as? [String: Any])?["login"] as? String ?? "",
                body: body, createdAt: (item["created_at"] as? String).flatMap(formatter.date(from:)),
                inReplyTo: item["in_reply_to_id"] as? Int, url: item["html_url"] as? String ?? "")
        }
        .sorted { ($0.createdAt ?? .distantPast, $0.id) < ($1.createdAt ?? .distantPast, $1.id) }
    }

    /// Every top-level JSON array in `data`: one, or several written back to back.
    static func arrays(in data: Data) -> [[[String: Any]]] {
        if let one = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] { return [one] }
        // Pages back to back: `][` between two arrays, outside any string, becomes a comma.
        var joined: [UInt8] = []
        joined.reserveCapacity(data.count)
        var inString = false, escaped = false, awaitingOpen = false
        for byte in data {
            if inString {
                joined.append(byte)
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            if awaitingOpen {
                if byte == UInt8(ascii: "[") { joined.append(UInt8(ascii: ",")); awaitingOpen = false; continue }
                if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                    continue
                }
                joined.append(UInt8(ascii: "]"))
                awaitingOpen = false
            }
            if byte == UInt8(ascii: "\"") { inString = true }
            if byte == UInt8(ascii: "]") { awaitingOpen = true; continue }
            joined.append(byte)
        }
        if awaitingOpen { joined.append(UInt8(ascii: "]")) }
        return (try? JSONSerialization.jsonObject(with: Data(joined)) as? [[String: Any]]).map { [$0] } ?? []
    }
}
