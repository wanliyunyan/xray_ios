//
//  ShareLinkParserTests.swift
//  XrayTests
//
//  Created by pan on 2026/8/17.
//

import XCTest
@testable import Xray

final class ShareLinkParserTests: XCTestCase {
    func testParseReturnsDisplayableVLESSFields() throws {
        let summary = try XCTUnwrap(
            ShareLinkParser.parse("vless://user-id@example.com:443?security=tls")
        )

        XCTAssertEqual(summary.identifier, "user-id")
        XCTAssertEqual(summary.host, "example.com")
        XCTAssertEqual(summary.port, "443")
    }

    func testParseTrimsSurroundingWhitespace() throws {
        let summary = try XCTUnwrap(
            ShareLinkParser.parse("  \nvless://user-id@192.0.2.1:8443\n")
        )

        XCTAssertEqual(summary.host, "192.0.2.1")
        XCTAssertEqual(summary.port, "8443")
    }

    func testParseRejectsTextWithoutScheme() {
        XCTAssertNil(ShareLinkParser.parse("not a share link"))
    }
}
