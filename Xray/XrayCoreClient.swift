//
//  XrayCoreClient.swift
//  Xray
//

import Foundation

/// The named local ports used by the SOCKS and Metrics services.
struct LocalServicePorts: Sendable {
    let socksPort: UInt16
    let metricsPort: UInt16
}

/// Async access to the process-local LibXray API.
actor XrayCoreClient {
    static let shared = XrayCoreClient()

    /// Converts a share link into the base Xray JSON returned by LibXray.
    func convertShareLinkToXrayJSON(_ shareLink: String) throws -> Data {
        guard !shareLink.isEmpty else {
            throw NSError(
                domain: "XrayCoreClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的配置字符串"]
            )
        }

        guard let configuration = try LibXrayRuntime.invoke(
            method: "convertShareLinksToXrayJson",
            payload: ["text": shareLink]
        ) else {
            throw NSError(
                domain: "XrayCoreClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"]
            )
        }

        return try JSONSerialization.data(withJSONObject: configuration)
    }

    /// Returns the installed Xray Core version.
    func fetchCoreVersion() throws -> String {
        let data = try LibXrayRuntime.invoke(method: "xrayVersion")
        guard let version = data?["version"] as? String, !version.isEmpty else {
            throw NSError(
                domain: "XrayCoreClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LibXray 未返回版本号"]
            )
        }
        return version
    }

    /// Allocates the two local ports required by the app.
    func allocateLocalPorts() -> LocalServicePorts {
        do {
            let responseData = try LibXrayRuntime.invoke(
                method: "getFreePorts",
                payload: ["count": 2]
            )
            guard let portNumbers = responseData?["ports"] as? [NSNumber], portNumbers.count == 2 else {
                return defaultPorts
            }

            let ports = portNumbers.map { UInt16(truncating: $0) }
            guard ports.allSatisfy({ $0 != 0 }) else {
                return defaultPorts
            }
            return LocalServicePorts(socksPort: ports[0], metricsPort: ports[1])
        } catch {
            return defaultPorts
        }
    }

    /// Runs a LibXray latency request through the supplied local SOCKS proxy.
    func measureLatency(
        configurationFileURL: URL,
        timeout: Int,
        targetURL: URL,
        proxyURL: URL
    ) throws -> Int {
        let responseData = try LibXrayRuntime.invoke(
            method: "ping",
            payload: [
                "configPath": configurationFileURL.path,
                "timeout": timeout,
                "url": targetURL.absoluteString,
                "proxy": proxyURL.absoluteString,
            ]
        )

        guard let delayMilliseconds = responseData?["delay"] as? NSNumber else {
            throw NSError(
                domain: "XrayCoreClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LibXray 未返回有效延迟"]
            )
        }
        return delayMilliseconds.intValue
    }

    private var defaultPorts: LocalServicePorts {
        LocalServicePorts(
            socksPort: AppConstants.defaultSocksPort.rawValue,
            metricsPort: AppConstants.defaultMetricsPort.rawValue
        )
    }
}
