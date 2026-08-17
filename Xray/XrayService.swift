//
//  XrayService.swift
//  Xray
//
//  Created by pan on 2025/9/19.
//

import Foundation
import Network
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "XrayService")

/// 提供主 App 使用的 Xray 业务操作。
///
/// 该类型不直接管理 VPN 生命周期，而是负责把界面层需求转换为 LibXray 调用或本地 Metrics
/// 请求，包括：构建并执行代理延迟测试、读取 Xray Core 版本、查询 TUN 入站累计流量、
/// 获取空闲端口，以及将用户分享链接转换为基础 Xray JSON。
///
/// 类型标记为 `@MainActor`，确保它与 `XrayConfigurationBuilder`、`AppGroupStore` 和 SwiftUI 状态更新在同一
/// 隔离域内调用；底层 LibXray 访问仍由 `LibXrayRuntime` 自己串行化。
@MainActor
struct XrayService {
    // MARK: - Diagnostics

    /// 使用当前保存的分享链接和 SOCKS 端口执行代理延迟测试。
    ///
    /// 完整流程：
    /// 1. 从 App Group 偏好读取用户最后保存的分享链接；
    /// 2. 通过 `XrayConfigurationBuilder` 生成带本地 SOCKS 入站的精简配置；
    /// 3. 将 JSON 写入 App Group 配置文件，供 LibXray 读取；
    /// 4. 读取与 SOCKS 入站一致的本地端口；
    /// 5. 调用 LibXray `ping`，让测试请求通过 `socks5://127.0.0.1:<port>` 发出；
    /// 6. 从响应 `data.delay` 中提取毫秒延迟。
    ///
    /// - Returns: LibXray 返回的延迟，单位为毫秒。
    /// - Throws: 配置缺失、JSON 构建或写入失败、端口缺失、LibXray 调用失败，或响应不包含
    ///   有效 `delay` 时抛出错误。
    func performPing() async throws -> Int {
        // 1. Ping 始终使用当前持久化的分享链接。
        guard
            let configLink = AppGroupStore.loadString(key: "configLink"),
            !configLink.isEmpty
        else {
            throw NSError(
                domain: "LatencyTestView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"]
            )
        }

        // 2. 构建 SOCKS 入站配置，并转换为 LibXray 配置文件需要的字符串。
        let configData = try XrayConfigurationBuilder().buildPingConfigurationData(configLink: configLink)
        guard let configJSON = String(data: configData, encoding: .utf8) else {
            throw NSError(
                domain: "LatencyTestView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"]
            )
        }

        // 3. 将配置写入共享容器，LibXray 的 ping 方法通过路径加载它。
        let configURL = try AppUtilities.createConfigFile(with: configJSON)

        // 4. 代理地址必须使用配置中 SOCKS 入站监听的同一个端口。
        guard let socks5Port = AppGroupStore.loadPort(key: "socks5Port") else {
            throw NSError(
                domain: "LatencyTestView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口"]
            )
        }

        // 5. 调用统一 JSON 接口，并读取响应中的 delay 字段。
        let data = try LibXrayRuntime.invoke(
            method: "ping",
            payload: [
                "configPath": configURL.path,
                "timeout": AppConstants.timeout,
                "url": AppConstants.pingUrl,
                "proxy": "socks5://127.0.0.1:\(socks5Port.rawValue)",
            ]
        )
        guard let delay = data?["delay"] as? NSNumber else {
            throw NSError(
                domain: "LatencyTestView",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LibXray 未返回有效延迟"]
            )
        }
        return delay.intValue
    }

    /// 获取底层 Xray Core 的版本号。
    ///
    /// - Returns: LibXray `xrayVersion` 响应中的非空 `version` 字符串。
    /// - Throws: LibXray 调用失败，或响应缺少有效版本号时抛出错误。
    func getVersion() throws -> String {
        let data = try LibXrayRuntime.invoke(method: "xrayVersion")
        guard let version = data?["version"] as? String, !version.isEmpty else {
            throw NSError(
                domain: "XrayService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LibXray 未返回版本号"]
            )
        }
        return version
    }

    /// 从本地 Metrics HTTP 服务读取 TUN 入站累计流量。
    ///
    /// 请求地址为 `http://127.0.0.1:<port>/debug/vars`。只有 2xx 响应会被解析，方法随后
    /// 按 `stats -> inbound -> tun-in -> downlink/uplink` 路径读取累计字节数。这里使用
    /// `NSNumber`，兼容 JSONSerialization 对不同整数宽度的桥接结果。
    ///
    /// - Parameter trafficPort: Metrics HTTP 服务监听端口。
    /// - Returns: 下行和上行字节数；请求或解析失败时返回 `nil`。
    /// - Note: 网络和解析错误会写入日志而不会向界面继续抛出，定时刷新可在下一秒重试。
    func getTrafficStats(
        trafficPort: NWEndpoint.Port
    ) async -> (downlink: Int, uplink: Int)? {
        guard let url = URL(string: "http://127.0.0.1:\(trafficPort.rawValue)/debug/vars") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200 ..< 300).contains(httpResponse.statusCode),
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let stats = root["stats"] as? [String: Any],
                let inbound = stats["inbound"] as? [String: Any],
                let tun = inbound["tun-in"] as? [String: Any],
                let downlink = tun["downlink"] as? NSNumber,
                let uplink = tun["uplink"] as? NSNumber
            else {
                return nil
            }
            return (downlink: downlink.intValue, uplink: uplink.intValue)
        } catch {
            logger.error("获取流量统计失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Configuration

    /// 获取 SOCKS 入站和 Metrics 服务使用的两个空闲端口。
    ///
    /// 调用 LibXray `getFreePorts` 并要求响应恰好包含两个可转换为 `NWEndpoint.Port` 的值。
    /// 任何调用、数量或端口转换问题都会回退到 `AppConstants.socks5Port` 和
    /// `AppConstants.trafficPort`，确保应用仍有可用配置。
    ///
    /// - Returns: 顺序为 `[socks5Port, trafficPort]` 的两个端口。
    func fetchFreePorts() -> [NWEndpoint.Port] {
        do {
            let data = try LibXrayRuntime.invoke(
                method: "getFreePorts",
                payload: ["count": 2]
            )
            guard let values = data?["ports"] as? [NSNumber], values.count == 2 else {
                return defaultPorts
            }
            let ports = values.compactMap { value in
                NWEndpoint.Port(rawValue: UInt16(truncating: value))
            }
            return ports.count == 2 ? ports : defaultPorts
        } catch {
            logger.error("获取空闲端口失败: \(error.localizedDescription)")
            return defaultPorts
        }
    }

    /// 通过 LibXray 将分享链接转换为基础 Xray 配置字典。
    ///
    /// 该方法只负责验证输入并调用 `convertShareLinksToXrayJson`；TUN/SOCKS 入站、固定出站、
    /// 路由和 DNS 等应用侧配置由 `XrayConfigurationBuilder` 在返回后继续补齐。
    ///
    /// - Parameter configLink: 用户粘贴或扫描得到的原始分享链接文本。
    /// - Returns: LibXray 响应中的基础配置字典。
    /// - Throws: 输入为空、底层转换失败或响应缺少配置数据时抛出错误。
    func convertConfigLinkToXrayJson(configLink: String) throws -> [String: Any] {
        guard !configLink.isEmpty else {
            throw NSError(
                domain: "InvalidConfig",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的配置字符串"]
            )
        }

        guard let configuration = try LibXrayRuntime.invoke(
            method: "convertShareLinksToXrayJson",
            payload: ["text": configLink]
        ) else {
            throw NSError(
                domain: "InvalidXrayJson",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"]
            )
        }
        return configuration
    }

    /// LibXray 无法分配端口时使用的稳定回退值。
    private var defaultPorts: [NWEndpoint.Port] {
        [AppConstants.socks5Port, AppConstants.trafficPort]
    }
}
