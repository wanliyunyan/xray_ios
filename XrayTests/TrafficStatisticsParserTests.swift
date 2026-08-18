//
//  TrafficStatisticsParserTests.swift
//  XrayTests
//
//  Created by pan on 2026/8/17.
//

import Foundation
import XCTest
@testable import Xray

final class TrafficStatisticsParserTests: XCTestCase {
    func testParseReturnsTunnelTraffic() throws {
        let responseData = Data(
            #"{"stats":{"inbound":{"tun-in":{"downlink":123456,"uplink":7890}}}}"#.utf8
        )

        let statistics = try TrafficStatisticsParser.parse(responseData)

        XCTAssertEqual(
            statistics,
            TrafficStatistics(downlinkBytes: 123_456, uplinkBytes: 7_890)
        )
    }

    func testParseRejectsIncompleteResponse() {
        let responseData = Data(#"{"stats":{"inbound":{}}}"#.utf8)

        XCTAssertThrowsError(try TrafficStatisticsParser.parse(responseData))
    }
}
