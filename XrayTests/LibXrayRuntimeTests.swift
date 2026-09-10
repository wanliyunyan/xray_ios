//
//  LibXrayRuntimeTests.swift
//  XrayTests
//

import XCTest
@testable import Xray

final class LibXrayRuntimeTests: XCTestCase {
    func testInvokeUsesSupportedAPIVersion() throws {
        let version = try LibXrayRuntime.coreVersion()

        XCTAssertFalse(version.isEmpty)
    }

    func testStartUsesCurrentJSONMethod() throws {
        try? LibXrayRuntime.stop()
        defer { try? LibXrayRuntime.stop() }

        let configurationJSON = """
        {
          "log": { "loglevel": "none" },
          "outbounds": [
            { "protocol": "freedom", "tag": "direct" }
          ]
        }
        """

        try LibXrayRuntime.start(configJSON: configurationJSON)

        XCTAssertTrue(try LibXrayRuntime.isXrayRunning())
    }

    func testParseLatencyReadsSingleBatchResult() throws {
        let latency = try XrayCoreClient.parseLatency(
            from: [
                LibXrayPingResult(success: true, delay: 123, error: nil),
            ]
        )

        XCTAssertEqual(latency, 123)
    }

    func testMeasureLatencyUsesPingBatchContract() async throws {
        let invalidConfigurationJSON = #"{"outbounds":[]}"#

        do {
            _ = try await XrayCoreClient().measureLatency(
                configurationJSON: invalidConfigurationJSON,
                timeout: 1,
                targetURL: try XCTUnwrap(URL(string: "https://127.0.0.1:1"))
            )
            XCTFail("无效出站不应返回延迟")
        } catch let error as XrayCoreClientError {
            guard case .latencyMeasurementFailed = error else {
                return XCTFail("应取得 pingBatch 单项错误，实际为：\(error)")
            }
        }
    }

    func testLatencyConfigurationPreservesSendThrough() async throws {
        let sourceJSON = """
        {
          "outbounds": [
            {
              "protocol": "vless",
              "tag": "Keep",
              "sendThrough": "0.0.0.0",
              "settings": {
                "address": "example.com",
                "port": 443,
                "id": "12345678-abcd-abcd-abcd-123456789abc",
                "encryption": "none"
              },
              "streamSettings": {
                "security": "tls",
                "tlsSettings": {
                  "serverName": "example.com"
                }
              }
            }
          ]
        }
        """

        let configurationData = try await XrayConfigurationBuilder()
            .makeLatencyTestConfigurationData(from: sourceJSON)
        let configuration = try XCTUnwrap(
            JSONSerialization.jsonObject(with: configurationData) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(configuration["outbounds"] as? [[String: Any]])
        let proxy = try XCTUnwrap(outbounds.first)

        XCTAssertEqual(proxy["tag"] as? String, "proxy")
        XCTAssertEqual(proxy["sendThrough"] as? String, "0.0.0.0")
    }

    func testLatencyConfigurationPreservesLiteralNullString() async throws {
        let sourceJSON = """
        {
          "outbounds": [
            {
              "protocol": "trojan",
              "settings": {
                "address": "127.0.0.1",
                "port": 443,
                "password": "<null>"
              }
            }
          ]
        }
        """

        let configurationData = try await XrayConfigurationBuilder()
            .makeLatencyTestConfigurationData(from: sourceJSON)
        let configuration = try XCTUnwrap(
            JSONSerialization.jsonObject(with: configurationData) as? [String: Any]
        )
        let outbounds = try XCTUnwrap(configuration["outbounds"] as? [[String: Any]])
        let proxy = try XCTUnwrap(outbounds.first)
        let settings = try XCTUnwrap(proxy["settings"] as? [String: Any])

        XCTAssertEqual(settings["password"] as? String, "<null>")
    }

    func testRoutingConfigurationUsesCurrentRuleSyntax() throws {
        let preferenceKey = "VPNMode"
        let previousMode = AppGroupStore.loadString(forKey: preferenceKey)
        AppGroupStore.saveString(VPNRoutingMode.nonGlobal.rawValue, forKey: preferenceKey)
        defer {
            if let previousMode {
                AppGroupStore.saveString(previousMode, forKey: preferenceKey)
            } else {
                AppGroupStore.removeValue(forKey: preferenceKey)
            }
        }

        let routing = XrayConfigurationBuilder()
            .makeRoutingConfiguration(geoAssetsAreAvailable: true)
        let rules = try XCTUnwrap(routing["rules"] as? [[String: Any]])
        let catchAllRule = try XCTUnwrap(rules.last)

        XCTAssertTrue(rules.allSatisfy { $0["type"] == nil })
        XCTAssertEqual(catchAllRule["network"] as? String, "tcp,udp")
        XCTAssertEqual(catchAllRule["outboundTag"] as? String, "proxy")
    }

    func testDNSConfigurationUsesExpectedIPs() throws {
        let dns = XrayConfigurationBuilder()
            .makeDNSConfiguration(geoAssetsAreAvailable: true)
        let servers = try XCTUnwrap(dns["servers"] as? [Any])
        let chinaServer = try XCTUnwrap(
            servers.compactMap { $0 as? [String: Any] }
                .first { $0["address"] as? String == "223.5.5.5" }
        )

        XCTAssertEqual(chinaServer["expectedIPs"] as? [String], ["geoip:cn"])
        XCTAssertNil(chinaServer["expectIPs"])
    }
}
