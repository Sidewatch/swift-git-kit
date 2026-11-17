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

    func testAChangeTouchesTheCheckoutsHoldingItAndNoOthers() {
        let vendor = URL(fileURLWithPath: "/work/app/vendor"), inner = URL(fileURLWithPath: "/work/app/vendor/inner")
        let plugin = URL(fileURLWithPath: "/work/app/plugins/x")
        XCTAssertEqual(
            set.checkouts(touchedBy: ["/work/app/vendor/inner/a.c"]), [inner, vendor, project],
            "each outer checkout may show the inner one as a modified submodule")
        XCTAssertEqual(set.checkouts(touchedBy: ["/work/app/plugins/x/y/z.php"]), [plugin, project])
        XCTAssertEqual(set.checkouts(touchedBy: ["/work/app/src/a.swift"]), [project])
        XCTAssertEqual(set.checkouts(touchedBy: ["/work/app/vendorette/c.c"]), [project], "a sibling with a longer name is not inside")
        XCTAssertEqual(set.checkouts(touchedBy: ["/elsewhere/d.c"]), [project], "the primary answers for outside files")
        XCTAssertEqual(set.checkouts(touchedBy: ["/work/app/vendor"]), [vendor, inner, project])
        XCTAssertEqual(set.checkouts(touchedBy: []), [])
    }

    func testAFolderEventTouchesEveryCheckoutBelowIt() {
        XCTAssertEqual(
            set.checkouts(touchedBy: ["/work/app/plugins"]), [project, URL(fileURLWithPath: "/work/app/plugins/x")],
            "a rescan of the folder holding a checkout covers that checkout")
        XCTAssertEqual(set.checkouts(touchedBy: ["/work/app"]), Set(set.all))
        XCTAssertEqual(set.checkouts(touchedBy: ["/work/app/"]), Set(set.all), "a trailing slash names the same folder")
    }

    func testAFolderEventSkipsASiblingWhoseNameSortsBetween() {
        let plugin = URL(fileURLWithPath: "/work/app/plugins/x"), old = URL(fileURLWithPath: "/work/app/plugins-old/y")
        let siblings = CheckoutSet(primary: project, nested: [old, plugin, URL(fileURLWithPath: "/work/app/plugins0/z")])
        XCTAssertEqual(siblings.checkouts(touchedBy: ["/work/app/plugins"]), [project, plugin], "'-' and '0' sort around '/'")
    }

    func testThousandsOfPathsAcrossAHundredCheckoutsCostNoDiskPerPath() {
        let roots = (0..<100).map { URL(fileURLWithPath: "/work/app/plugins/p\($0)") }
        let many = CheckoutSet(primary: project, nested: roots)
        let paths = (0..<20_000).map { "/work/app/plugins/p7/node_modules/m\($0 % 400)/lib/f\($0).js" }
        let started = Date()
        XCTAssertEqual(many.checkouts(touchedBy: paths), [project, roots[7]])
        XCTAssertLessThan(Date().timeIntervalSince(started), 1, "a burst is routed in well under a frame per thousand paths")
    }

    func testWithoutAPrimaryAPathOutsideEveryCheckoutTouchesNothing() {
        let loose = CheckoutSet(primary: nil, nested: [URL(fileURLWithPath: "/work/app/plugins/x")])
        XCTAssertEqual(loose.checkouts(touchedBy: ["/work/app/readme.md"]), [])
        XCTAssertEqual(loose.checkouts(touchedBy: ["/work/app/plugins/x/a.php"]), [URL(fileURLWithPath: "/work/app/plugins/x")])
    }

    func testAChangeNamedByItsRealPathTouchesACheckoutOpenedThroughALink() throws {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("touched-\(UUID().uuidString)")
        let real = temporary.appendingPathComponent("real")
        let plugin = real.appendingPathComponent("plugin")
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let link = temporary.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let linkedPlugin = link.appendingPathComponent("plugin")
        let checkouts = CheckoutSet(primary: link, nested: [linkedPlugin])
        let eventPath = plugin.resolvingSymlinksInPath().appendingPathComponent("a.php").path
        XCTAssertEqual(checkouts.checkouts(touchedBy: [eventPath]), [linkedPlugin, link], "the event names the link's target")
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
