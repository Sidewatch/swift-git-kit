//
//  GitRunResult.swift
//  GitKit
//
//  Everything one `git` invocation produced: status, stdout, stderr.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Everything one `git` invocation produced, from ``Git/runCapturingError(_:in:environment:timeout:input:)``.
public struct GitRunResult: Equatable, Sendable {

    /// Exit status; `-1` when git could not be launched.
    public let status: Int32

    /// Standard output, decoded as UTF-8 lossily.
    public let stdout: String

    /// Standard error, decoded as UTF-8 lossily.
    public let stderr: String

    /// True when the call outlived its timeout and was terminated.
    public let timedOut: Bool

    /// Creates a result; normally produced by `Git`.
    public init(status: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    /// False when git could not be started at all.
    public var launched: Bool { status != -1 }

    /// True when git exited 0 within its time.
    public var succeeded: Bool { status == 0 && !timedOut }

    /// git's own words for the outcome: stderr, else stdout (a hook's refusal is printed there),
    /// trimmed; a fixed phrase when both are empty.
    public var message: String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return out }
        if timedOut { return "git did not finish in time" }
        return launched ? "git exited \(status)" : "git could not be launched"
    }
}
