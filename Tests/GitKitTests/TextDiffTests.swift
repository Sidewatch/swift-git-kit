//
//  TextDiffTests.swift
//  GitKitTests
//
//  Two texts compared through the real git: the diff, its headers named for the texts, and
//  nothing at all for identical texts.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

final class TextDiffTests: XCTestCase {
    func testDifferentTextsGiveAUnifiedDiffNamedForTheTexts() {
        let diff = Git.unifiedDiff(old: "one\ntwo\n", new: "one\n2\n", oldName: "x (saved)", newName: "x")
        XCTAssertTrue(diff.contains("--- a/x (saved)"), diff)
        XCTAssertTrue(diff.contains("+++ b/x"), diff)
        XCTAssertTrue(diff.contains("-two"))
        XCTAssertTrue(diff.contains("+2"))
        XCTAssertFalse(diff.contains("gitkit-textdiff"), "the temp paths never reach the reader")
    }

    func testIdenticalTextsGiveNothing() {
        XCTAssertEqual(Git.unifiedDiff(old: "same\n", new: "same\n", oldName: "a", newName: "b"), "")
    }
}
