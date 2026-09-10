//
//  LibXrayRuntimeTests.swift
//  XrayTests
//

import XCTest
@testable import Xray

final class LibXrayRuntimeTests: XCTestCase {
    func testInvokeUsesSupportedAPIVersion() throws {
        let data = try LibXrayRuntime.invoke(method: "xrayVersion")
        let version = try XCTUnwrap(data?["version"] as? String)

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
                "results": [
                    ["success": true, "delay": 123],
                ],
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
}
