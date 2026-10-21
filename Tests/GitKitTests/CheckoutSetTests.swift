//
//  CheckoutSetTests.swift
//  GitKitTests
//
//  The repositories an opened folder holds: deepest-first lookup, grouping, and the symlink alias.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

/// `CheckoutSet`.
final class CheckoutSetTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/work/app")
    private var set: CheckoutSet {
        CheckoutSet(
            primary: project,
            nested: [
                URL(fileURLWithPath: "/work/app/vendor"), URL(fileURLWithPath: "/work/app/vendor/inner"),
                URL(fileURLWithPath: "/work/app/plugins/x"),
            ])
    }

    func testNestedCheckoutsAreKeptDeepestFirst() {
        XCTAssertEqual(set.nested.first?.path, "/work/app/vendor/inner")
        XCTAssertEqual(set.all.first, project, "the primary leads the merge order")
    }

    func testAFileBelongsToTheDeepestCheckoutHoldingIt() {
        XCTAssertEqual(set.root(for: URL(fileURLWithPath: "/work/app/vendor/inner/a.c"))?.path, "/work/app/vendor/inner")
        XCTAssertEqual(set.root(for: URL(fileURLWithPath: "/work/app/vendor/b.c"))?.path, "/work/app/vendor")
        XCTAssertEqual(set.root(for: URL(fileURLWithPath: "/work/app/vendor"))?.path, "/work/app/vendor", "a nested root holds itself")
        XCTAssertEqual(
            set.root(for: URL(fileURLWithPath: "/work/app/vendorette/c.c")), project, "a sibling with a longer name is not inside")
        XCTAssertEqual(set.root(for: URL(fileURLWithPath: "/elsewhere/d.c")), project, "the primary answers for outside files")
        XCTAssertNil(CheckoutSet(primary: nil, nested: []).root(for: URL(fileURLWithPath: "/x")))
    }

    func testFilesGroupPerRepositoryWithRelativePaths() {
        let urls = ["/work/app/src/a.swift", "/work/app/vendor/lib.c", "/work/app/src/a.swift"].map { URL(fileURLWithPath: $0) }
        let (byRoot, outside) = set.grouped(urls)
        XCTAssertEqual(byRoot[project]?[urls[0]], "src/a.swift")
        XCTAssertEqual(byRoot[URL(fileURLWithPath: "/work/app/vendor")]?[urls[1]], "lib.c")
        XCTAssertEqual(byRoot[project]?.count, 1, "a duplicate is grouped once")
        XCTAssertTrue(outside.isEmpty)
        XCTAssertEqual(CheckoutSet(primary: nil, nested: []).grouped(urls).outside.count, 3)
    }

    func testAFolderOpenedThroughALinkIsAnAliasOfItsRepository() throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("checkouts-\(UUID().uuidString)")
        let real = temporary.appendingPathComponent("repo")
        let sub = real.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let link = temporary.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let checkouts = CheckoutSet(primary: real, nested: [])
        XCTAssertEqual(checkouts.aliases(ofOpened: link), [link])
        XCTAssertEqual(checkouts.aliases(ofOpened: real), [], "the same spelling is not an alias")
        XCTAssertEqual(checkouts.aliases(ofOpened: sub), [], "a subfolder is not an alias")
    }
}
