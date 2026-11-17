//
//  CheckoutResultsTests.swift
//  GitKitTests
//
//  Which checkouts a refresh asks git about again.
//
//  Created by David Sherlock on 11/17/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// `CheckoutResults`.
final class CheckoutResultsTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/work/a"), b = URL(fileURLWithPath: "/work/b"), c = URL(fileURLWithPath: "/work/c")

    func testEveryCheckoutIsAskedOnceThenOnlyWhatAChangeTouched() {
        var results = CheckoutResults<Int>()
        XCTAssertEqual(results.takeStale(of: [a, b, c]), [a, b, c], "nothing asked yet: all of them")
        results.store([a: 1, b: 2, c: 3])
        XCTAssertEqual(results.takeStale(of: [a, b, c]), [], "nothing changed: nothing to ask")
        results.invalidate([b])
        XCTAssertEqual(results.takeStale(of: [a, b, c]), [b])
        XCTAssertEqual(results.takeStale(of: [a, b, c]), [], "taking it clears the mark")
    }

    func testANeverAnsweredCheckoutIsAskedAgain() {
        var results = CheckoutResults<Int>()
        XCTAssertEqual(results.takeStale(of: [a, b]), [a, b])
        results.store([a: 1])
        XCTAssertEqual(results.takeStale(of: [a, b]), [b], "an ask whose answer never came is asked again")
    }

    func testAChangeDuringTheAskIsAskedNextTime() {
        var results = CheckoutResults<Int>()
        _ = results.takeStale(of: [a])
        results.invalidate([a])  // lands while git is being asked
        results.store([a: 1])
        XCTAssertEqual(results.takeStale(of: [a]), [a])
    }

    func testACheckoutThatLeftIsForgottenAndOneThatArrivedIsAsked() {
        var results = CheckoutResults<Int>()
        _ = results.takeStale(of: [a, b])
        results.store([a: 1, b: 2])
        XCTAssertEqual(results.takeStale(of: [a, c]), [c])
        XCTAssertNil(results.values[b], "an answer for a checkout no longer in the set is dropped")
        results.store([c: 3])
        XCTAssertEqual(results.values, [a: 1, c: 3])
        results.removeAll()
        XCTAssertEqual(results.takeStale(of: [a, c]), [a, c])
    }

    func testFreshAnswersReplaceOldOnes() {
        var results = CheckoutResults<Int>()
        results.store([a: 1, b: 2])
        results.store([a: 5])
        XCTAssertEqual(results.values, [a: 5, b: 2])
    }
}
