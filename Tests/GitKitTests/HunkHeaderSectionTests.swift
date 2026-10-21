//
//  HunkHeaderSectionTests.swift
//  GitKitTests
//
//  A hunk's section heading, kept whole, and whitespace-only hunks.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// `HunkHeader.section(of:)` and `HunkHeader.isWhitespaceOnly(_:)`.
final class HunkHeaderSectionTests: XCTestCase {
    func testTheHeadingAfterTheSecondMarker() {
        XCTAssertEqual(HunkHeader.section(of: "@@ -10,3 +10,4 @@ func render(_ text: String) {"), "func render(_ text: String) {")
        XCTAssertNil(HunkHeader.section(of: "@@ -1 +1 @@"), "no heading")
        XCTAssertNil(HunkHeader.section(of: "@@ -1 +1 @@   "), "only spaces")
        XCTAssertNil(HunkHeader.section(of: "+@@ not a header"))
    }

    func testAHeadingHoldingMarkersIsKeptWhole() {
        XCTAssertEqual(HunkHeader.section(of: "@@ -4,2 +4,2 @@ @@property def name(self): # @@ x"), "@@property def name(self): # @@ x")
    }

    func testWhitespaceOnlyHunks() {
        XCTAssertTrue(HunkHeader.isWhitespaceOnly(["-if a {", "-  b()", "+if a {", "+    b()", " }"]), "a re-indent")
        XCTAssertTrue(HunkHeader.isWhitespaceOnly(["-a(b, c)", "+a(", "+  b,", "+  c)"]), "a re-wrap")
        XCTAssertFalse(HunkHeader.isWhitespaceOnly(["-a(b)", "+a(c)"]), "a real change")
        XCTAssertFalse(HunkHeader.isWhitespaceOnly([" context only"]), "nothing changed")
        XCTAssertFalse(HunkHeader.isWhitespaceOnly(["+new line"]), "a pure addition")
    }
}
