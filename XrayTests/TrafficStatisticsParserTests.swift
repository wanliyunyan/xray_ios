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

    func testPollingContextRequiresConnectedTunnelAndPreparedPort() {
        XCTAssertNil(
            TrafficPollingContext(
                isConnected: false,
                areLocalPortsReady: true,
                metricsPort: 31_080
            ).resolvedMetricsPort
        )
        XCTAssertNil(
            TrafficPollingContext(
                isConnected: true,
                areLocalPortsReady: false,
                metricsPort: 31_080
            ).resolvedMetricsPort
        )
        XCTAssertNil(
            TrafficPollingContext(
                isConnected: true,
                areLocalPortsReady: true,
                metricsPort: 0
            ).resolvedMetricsPort
        )
        XCTAssertEqual(
            TrafficPollingContext(
                isConnected: true,
                areLocalPortsReady: true,
                metricsPort: 31_080
            ).resolvedMetricsPort?.rawValue,
            31_080
        )
    }

    func testPollingFailureTrackerReportsOnlyAtThresholdAndResetsAfterSuccess() {
        var tracker = TrafficPollingFailureTracker(reportingThreshold: 3)

        XCTAssertFalse(tracker.recordFailure())
        XCTAssertFalse(tracker.recordFailure())
        XCTAssertTrue(tracker.recordFailure())
        XCTAssertFalse(tracker.recordFailure())
        XCTAssertEqual(tracker.consecutiveFailureCount, 4)

        tracker.recordSuccess()

        XCTAssertEqual(tracker.consecutiveFailureCount, 0)
        XCTAssertFalse(tracker.recordFailure())
    }
}
