//
//  Git+TextDiff.swift
//  GitKit
//
//  A unified diff between two texts that are not in any repository.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension Git {
    /// The unified diff from `old` to `new`, headed `a/<oldName>` and `b/<newName>`, through
    /// `git diff --no-index` — the same engine and output shape as every other diff git gives
    /// back, so a caller that renders repository diffs renders this one too. Empty when the texts
    /// are the same or git cannot run.
    public static func unifiedDiff(old: String, new: String, oldName: String, newName: String) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitkit-textdiff-\(getpid())-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a"), b = dir.appendingPathComponent("b")
        guard (try? old.write(to: a, atomically: true, encoding: .utf8)) != nil,
              (try? new.write(to: b, atomically: true, encoding: .utf8)) != nil,
              let text = run(["-c", "core.quotePath=false", "diff", "--no-color", "--no-index", "--", a.path, b.path],
                             in: dir, allowedStatuses: [1])   // 1 = "they differ"
        else { return "" }
        // git names the temp files — "a/var/…/a", the leading slash dropped under its prefix —
        // and the reader wants the texts' own names.
        let aPath = String(a.path.drop(while: { $0 == "/" })), bPath = String(b.path.drop(while: { $0 == "/" }))
        return text.replacingOccurrences(of: "a/\(aPath)", with: "a/\(oldName)")
            .replacingOccurrences(of: "b/\(bPath)", with: "b/\(newName)")
    }
}
