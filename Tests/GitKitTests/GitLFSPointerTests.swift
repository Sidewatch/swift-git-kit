//
//  GitLFSPointerTests.swift
//  GitKitTests
//
//  A Git LFS pointer told from the file it stands for.
//
//  Created by David Sherlock on 10/26/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import GitKit

final class GitLFSPointerTests: XCTestCase {
    private let oid = "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393"

    func testAPointerGivesItsObjectAndTheRealSize() {
        let text = "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\nsize 12345\n"
        XCTAssertEqual(GitLFSPointer(data: Data(text.utf8)), GitLFSPointer(oid: oid, size: 12_345))
    }

    func testTheOlderVersionURLExtensionLinesAndCRLFAreAPointerToo() {
        let text = "version https://hawser.github.com/spec/v1\r\next-0-foo sha256:\(oid)\r\noid sha256:\(oid)\r\nsize 7\r\n"
        XCTAssertEqual(GitLFSPointer(data: Data(text.utf8))?.size, 7)
    }

    func testAnythingElseIsNotAPointer() {
        for text in [
            "version https://git-lfs.github.com/spec/v1\nsize 1\n",  // no oid
            "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\n",  // no size
            "version https://git-lfs.github.com/spec/v2\noid sha256:\(oid)\nsize 1\n",  // an unknown version
            "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid.uppercased())\nsize 1\n",  // upper-case hex
            "version https://git-lfs.github.com/spec/v1\noid md5:\(oid)\nsize 1\n",  // another hash
            "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\nsize -1\n",
            "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\nsize 1\nname photo.png\n",  // an unknown key
            "PNG and some bytes", "",
        ] {
            XCTAssertNil(GitLFSPointer(data: Data(text.utf8)), text)
        }
        XCTAssertNil(GitLFSPointer(data: Data([0x89, 0x50, 0x4E, 0x47, 0, 0xFF])), "binary")
        let padded = "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\nsize 1\n" + String(repeating: "\n", count: 2_000)
        XCTAssertNil(GitLFSPointer(data: Data(padded.utf8)), "a pointer is fewer than 1,024 bytes")
    }

    /// The rules below are git-lfs's own decoder's (`lfs/pointer.go`), each one a file the earlier, looser
    /// reading took for a pointer or refused.
    private func pointer(_ lines: [String], ending: String = "\n") -> GitLFSPointer? {
        GitLFSPointer(data: Data(lines.map { $0 + ending }.joined().utf8))
    }

    private var plain: [String] { ["version https://git-lfs.github.com/spec/v1", "oid sha256:\(oid)", "size 12"] }

    func testAPointerIsFewerThan1024Bytes() {
        let text = plain.map { $0 + "\n" }.joined()
        let under = text + String(repeating: "\n", count: 1_023 - text.utf8.count)
        XCTAssertEqual(GitLFSPointer(data: Data(under.utf8))?.size, 12, "1,023 bytes, the trailing lines trimmed")
        XCTAssertNil(GitLFSPointer(data: Data((under + "\n").utf8)), "1,024 bytes is git-lfs's cut-off")
    }

    func testTheAlphaVersionAndSurroundingWhiteSpaceAreAPointerToo() {
        XCTAssertEqual(pointer(["version http://git-media.io/v/2", "oid sha256:\(oid)", "size 3"])?.size, 3)
        let spaced = "\n  version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\n\nsize 3  \n\n"
        XCTAssertEqual(GitLFSPointer(data: Data(spaced.utf8))?.size, 3, "the whole text trimmed, empty lines skipped")
    }

    func testTheKeysComeInOrderOnceEach() {
        let ext = "ext-0-foo sha256:\(oid)"
        XCTAssertNil(pointer([plain[0], plain[2], plain[1]]), "size before oid")
        XCTAssertNil(pointer([plain[0], plain[1], plain[1], plain[2]]), "oid twice")
        XCTAssertNil(pointer(plain + [ext]), "nothing after size, not even an extension")
        XCTAssertEqual(pointer([plain[0], plain[1], ext, plain[2]])?.size, 12, "an extension anywhere before size")
    }

    func testAnExtensionIsExtDigitNameWithAnOidAndItsOwnPriority() {
        for key in ["ext-10-foo", "ext-a-foo", "ext-1xfoo", "ext-0-.x", "ext-0-", "ext-0"] {
            XCTAssertNil(pointer([plain[0], "\(key) sha256:\(oid)", plain[1], plain[2]]), key)
        }
        XCTAssertNil(pointer([plain[0], "ext-0-foo bar", plain[1], plain[2]]), "an extension's value is an oid")
        XCTAssertNil(pointer([plain[0], "ext-0-foo sha256:\(oid)", "ext-0-bar sha256:\(oid)", plain[1], plain[2]]), "one priority")
        XCTAssertEqual(pointer([plain[0], "ext-0-foo.x sha256:\(oid)", "ext-1-bar sha256:\(oid)", plain[1], plain[2]])?.size, 12)
    }

    func testOnlyANewlineEndsALineAndOnlyASCIIDigitsAreHex() {
        XCTAssertNil(pointer(plain, ending: "\r"), "a bare carriage return does not end a line")
        let wide = String(oid.dropLast()) + "\u{FF41}"
        XCTAssertNil(pointer([plain[0], "oid sha256:\(wide)", plain[2]]), "a full-width a is not a hex digit")
        let packed = String(oid.prefix(61)) + "\u{FF41}"  // 64 bytes: only the ASCII rule can refuse it
        XCTAssertNil(pointer([plain[0], "oid sha256:\(packed)", plain[2]]), "64 bytes with a full-width digit")
    }

    func testOnlyASmallFileIsReadAsOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lfs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pointer = "version https://git-lfs.github.com/spec/v1\noid sha256:\(oid)\nsize 98765\n"
        let small = folder.appendingPathComponent("hero.png")
        try pointer.write(to: small, atomically: true, encoding: .utf8)
        XCTAssertEqual(GitLFSPointer(fileAt: small)?.size, 98_765)
        let large = folder.appendingPathComponent("large.png")
        try (pointer + String(repeating: " ", count: 2_000)).write(to: large, atomically: true, encoding: .utf8)
        XCTAssertNil(GitLFSPointer(fileAt: large), "a pointer is fewer than 1,024 bytes")
        XCTAssertNil(GitLFSPointer(fileAt: folder.appendingPathComponent("missing.png")))
    }
}
