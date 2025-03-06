//
//  Configuration.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import LibXray
import Network

/// 用于生成并整合 Xray 配置的核心结构体。
///
/// 通过对传入的分享链接配置进行解析、合并、插入本地的 inbound 与 metrics 设置，
/// 并根据当前的 VPN 模式（Global/非Global）来动态生成最终的 JSON 格式配置数据。
struct Configuration {
    // MARK: - 公有方法

    /// 生成最终可用于 Xray 的配置信息（JSON 格式的二进制 Data）。
    ///
    /// 1. 从 UserDefaults 中加载 SOCKS 端口和流量统计端口；
    /// 2. 对传入的 config 字符串进行解析和合并；
    /// 3. 添加自定义的 inbound、metrics、policy、routing 以及 stats 等键值；
    /// 4. 移除配置中可能的 null 值或无效字段；
    /// 5. 去除一些特定字段（如 `sendThrough`），防止兼容性问题。
    ///
    /// - Parameter config: 用于生成配置的链接字符串，一般是用户从外部复制的分享链接。
    /// - Returns: 生成后的 JSON 配置数据（`Data`），可直接写入文件或内存使用。
    /// - Throws: 当无法加载或解析端口、或解析 JSON 失败时可能抛出错误。
    func buildConfigurationData(config: String) throws -> Data {
        // 1. 从 UserDefaults 加载端口并转换为 NWEndpoint.Port
        guard let inboundPortString = Util.loadFromUserDefaults(key: "sock5Port"),
              let trafficPortString = Util.loadFromUserDefaults(key: "trafficPort"),
              let inboundPort = NWEndpoint.Port(inboundPortString),
              let trafficPort = NWEndpoint.Port(trafficPortString)
        else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 将传入的 config 分享链接解析为基础配置 (outbounds)
        var configuration = try buildOutInbound(config: config)

        // 3. 添加自定义的 inbound、metrics、policy、routing、stats 等键值
        configuration["inbounds"] = buildInbound(inboundPort: inboundPort, trafficPort: trafficPort)
        configuration["metrics"] = buildMetrics()
        configuration["policy"] = buildPolicy()
        configuration["routing"] = try buildRoute()
        configuration["stats"] = [:]

        // 4. 移除为 null 的字段（或 "<null>" 形式）
        configuration = removeNullValues(from: configuration)

        // 5. 去除 outbounds 中的 sendThrough 字段，避免 Xray 版本兼容性问题
        configuration = removeSendThroughFromOutbounds(from: configuration)

        // 6. 序列化为 JSON 格式的 Data
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }

    /// 去除配置中第一个 outbound 的 sendThrough 字段，防止 Xray 在某些版本下启动异常。
    ///
    /// - Parameter configuration: 目标配置字典。
    /// - Returns: 处理后的配置字典。
    func removeSendThroughFromOutbounds(from configuration: [String: Any]) -> [String: Any] {
        var updatedConfig = configuration

        // 如果 outbounds 存在并非空，则移除第一个 outbound 的 sendThrough
        if var outbounds = configuration["outbounds"] as? [[String: Any]], !outbounds.isEmpty {
            outbounds[0].removeValue(forKey: "sendThrough")
            updatedConfig["outbounds"] = outbounds
        }

        return updatedConfig
    }

    /// 递归地移除配置字典中所有为 `NSNull` 或 “<null>” 的字段。
    ///
    /// - Parameter dictionary: 原始配置字典。
    /// - Returns: 处理后不含空值的配置字典。
    func removeNullValues(from dictionary: [String: Any]) -> [String: Any] {
        var updatedDictionary = dictionary

        for (key, value) in dictionary {
            if value is NSNull || "\(value)" == "<null>" {
                // 值是 NSNull 或 "<null>"
                updatedDictionary.removeValue(forKey: key)
            } else if let nestedDictionary = value as? [String: Any] {
                // 如果值是字典，递归处理
                updatedDictionary[key] = removeNullValues(from: nestedDictionary)
            } else if let nestedArray = value as? [[String: Any]] {
                // 如果值是字典数组，递归处理每个元素
                updatedDictionary[key] = nestedArray.map { removeNullValues(from: $0) }
            }
        }

        return updatedDictionary
    }

    // MARK: - 私有方法

    /// 尝试将用户分享的配置链接字符串（如 VLESS、VMess 链接）转换为 Xray JSON，并在其中添加新的 outbound。
    ///
    /// - Parameter config: 原始的分享链接字符串。
    /// - Returns: 包含 outbounds 等信息的配置字典。
    /// - Throws: 当字符串无效或解析失败时抛出错误。
    private func buildOutInbound(config: String) throws -> [String: Any] {
        // 1. 将原始字符串转换为 Data
        guard let configData = config.data(using: .utf8) else {
            throw NSError(
                domain: "InvalidConfig",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的配置字符串"]
            )
        }

        // 2. Base64 编码后再调用 LibXrayConvertShareLinksToXrayJson
        let base64EncodedConfig = configData.base64EncodedString()
        let xrayJsonString = LibXrayConvertShareLinksToXrayJson(base64EncodedConfig)

        // 3. 对返回的字符串做二次 Base64 解码，并转为 JSON 字典
        guard
            let decodedData = Data(base64Encoded: xrayJsonString),
            let decodedString = String(data: decodedData, encoding: .utf8),
            let jsonData = decodedString.data(using: .utf8),
            let jsonDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
            let success = jsonDict["success"] as? Bool, success,
            var dataDict = jsonDict["data"] as? [String: Any],
            var outboundsArray = dataDict["outbounds"] as? [[String: Any]]
        else {
            throw NSError(
                domain: "InvalidXrayJson",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"]
            )
        }

        // 4. 修改第一个 outbound 的 "tag" 为 "proxy"
        if var firstOutbound = outboundsArray.first {
            firstOutbound["tag"] = "proxy"
            outboundsArray[0] = firstOutbound
        }

        // 5. 新增一个 "freedom" 协议的 outbound，tag 为 "direct"
        let newObject: [String: Any] = [
            "protocol": "freedom",
            "tag": "direct",
        ]
        outboundsArray.append(newObject)

        // 6. 将修改后的 outbounds 写回 dataDict
        dataDict["outbounds"] = outboundsArray

        return dataDict
    }

    /// 构建两个 inbound 配置：一个用于 SOCKS 代理服务，一个用于流量统计接口。
    ///
    /// - Parameters:
    ///   - inboundPort: SOCKS 代理使用的端口。
    ///   - trafficPort: 用于收集或查看流量统计的端口。
    /// - Returns: 包含两个 inbound 配置的数组。
    private func buildInbound(inboundPort: NWEndpoint.Port = Constant.sock5Port,
                              trafficPort: NWEndpoint.Port = Constant.trafficPort) -> [[String: Any]]
    {
        let socksInbound: [String: Any] = [
            "listen": "127.0.0.1",
            "port": Int(inboundPort.rawValue),
            "protocol": "socks",
            "settings": [
                "udp": true,
            ],
            "tag": "socks",
        ]

        let metricsInbound: [String: Any] = [
            "listen": "127.0.0.1",
            "port": Int(trafficPort.rawValue),
            "protocol": "dokodemo-door",
            "settings": [
                "address": "127.0.0.1",
            ],
            "tag": "metricsIn",
        ]

        return [socksInbound, metricsInbound]
    }

    /// 为流量统计的 outbound 添加必要配置（仅包含一个简单的 tag）。
    ///
    /// - Returns: 一个带 "metricsOut" tag 的字典。
    private func buildMetrics() -> [String: Any] {
        [
            "tag": "metricsOut",
        ]
    }

    /// 为系统设置构建 policy（策略），使其支持统计上下行流量等信息。
    ///
    /// - Returns: 包含统计相关设置的字典。
    private func buildPolicy() -> [String: Any] {
        [
            "system": [
                "statsInboundDownlink": true,
                "statsInboundUplink": true,
                "statsOutboundDownlink": true,
                "statsOutboundUplink": true,
            ],
        ]
    }

    /// 根据当前的 VPN 模式（全局 / 非全局），构建路由策略并匹配本地资源（如地理规则）。
    ///
    /// - Throws: 读取 assetDirectory 时遇到 I/O 错误或者无法读取文件时可能抛出错误。
    /// - Returns: 包含路由策略的字典。
    private func buildRoute() throws -> [String: Any] {
        var route: [String: Any] = [
            "domainStrategy": "AsIs",
            "rules": [
                [
                    "inboundTag": ["metricsIn"],
                    "outboundTag": "metricsOut",
                    "type": "field",
                ],
            ],
        ]

        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        // 从 UserDefaults 读取 VPN 模式
        let vpnMode = Util.loadFromUserDefaults(key: "VPNMode") ?? VPNMode.nonGlobal.rawValue

        // 如果处于非全局模式且本地有地理规则文件，则加入一些 CN/私有 IP 走直连的规则
        if vpnMode == VPNMode.nonGlobal.rawValue,
           let files = try? fileManager.contentsOfDirectory(atPath: assetDirectoryPath),
           !files.isEmpty
        {
            // 非全局规则设置
            var rulesArray = route["rules"] as? [[String: Any]] ?? []

            // 添加国内域名直连规则
            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "domain": ["geosite:cn"],
            ])

            // 添加国内 IP 及私有 IP 直连规则
            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "ip": [
                    "223.5.5.5/32",
                    "114.114.114.114/32",
                    "geoip:private",
                    "geoip:cn",
                ],
            ])

            // 最后所有端口流量均走 "proxy"
            rulesArray.append([
                "type": "field",
                "port": "0-65535",
                "outboundTag": "proxy",
            ])

            route["rules"] = rulesArray
        }

        return route
    }
}
