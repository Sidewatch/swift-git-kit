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
        XCTAssertNil(GitLFSPointer(data: Data(padded.utf8)), "a pointer is at most 1,024 bytes")
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
        XCTAssertNil(GitLFSPointer(fileAt: large), "a pointer is at most 1,024 bytes")
        XCTAssertNil(GitLFSPointer(fileAt: folder.appendingPathComponent("missing.png")))
    }
}
