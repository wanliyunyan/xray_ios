//
//  Configuration.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import LibXray
import Network

/// `Configuration` 负责生成并整合 Xray 的最终配置.
///
/// - 主要作用：
///   1. 解析用户分享的链接（如 VLESS 等）；
///   2. 加入本地 inbounds、metrics、policy、routing、stats、dns 等；
///   3. 去除特定无用字段，防止 Xray 兼容性问题；
///   4. 最终将配置序列化为 JSON Data 供 Xray 使用.
///
/// 配置生成流程包括以下主要步骤：
///  1. 从 UserDefaults 中加载 SOCKS 端口和流量统计端口；
///  2. 基于分享链接解析生成 outbounds；
///  3. 合并 inbound、metrics、policy、routing、stats、dns；
///  4. 递归移除空值；
///  5. 去除 `sendThrough`；
///  6. 将配置序列化输出。
struct Configuration {
    // MARK: - Public Methods

    /// 生成最终可用于 Xray 运行的 JSON 格式二进制配置.
    ///
    /// - Parameter config: 用户从外部复制的分享链接字符串.
    /// - Returns: 封装完成的 JSON Data，Xray 可直接使用.
    /// - Throws: 当端口加载失败、或 JSON 生成失败时抛出错误.
    func buildRunConfigurationData(config: String) throws -> Data {
        // 1. 从 UserDefaults 中获取端口并转为 NWEndpoint.Port
        guard
            let inboundPortString = Util.loadFromUserDefaults(key: "socks5Port"),
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

        // 2. 基于用户分享链接生成 Xray outbounds
        var configuration = try buildOutInbound(config: config)

        // 3. 添加自定义 inbound、metrics、policy、routing、stats、dns 等
        configuration["inbounds"] = buildInbound(inboundPort: inboundPort, trafficPort: trafficPort)
        configuration["metrics"] = buildMetrics()
        configuration["policy"] = buildPolicy()
        configuration["routing"] = try buildRoute()
        configuration["stats"] = [:]
        configuration["dns"] = buildDNSConfiguration()

        // 4. 递归移除配置中所有 NSNull 或 "<null>" 值
        configuration = removeNullValues(from: configuration)

        // 5. 去除第一个 outbound 的 sendThrough 字段
        configuration = removeSendThroughFromOutbounds(from: configuration)

        // 6. 序列化为 JSON Data 输出
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }

    /// 生成最终可用于 Xray ping的 JSON 格式二进制配置.
    ///
    /// - Parameter config: 用户从外部复制的分享链接字符串.
    /// - Returns: 封装完成的 JSON Data，Xray 可直接使用.
    /// - Throws: 当端口加载失败、或 JSON 生成失败时抛出错误.
    func buildPingConfigurationData(config: String) throws -> Data {
        // 1. 从 UserDefaults 中获取端口并转为 NWEndpoint.Port
        guard
            let inboundPortString = Util.loadFromUserDefaults(key: "socks5Port"),
            let inboundPort = NWEndpoint.Port(inboundPortString)
        else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 基于用户分享链接生成 Xray outbounds
        var configuration = try buildOutInbound(config: config)

        // 3. 添加自定义 inbound、metrics、policy、routing、stats、dns 等
        configuration["inbounds"] = buildInbound(inboundPort: inboundPort, trafficPort: nil)

        // 4. 递归移除配置中所有 NSNull 或 "<null>" 值
        configuration = removeNullValues(from: configuration)

        // 5. 去除第一个 outbound 的 sendThrough 字段
        configuration = removeSendThroughFromOutbounds(from: configuration)

        // 6. 序列化为 JSON Data 输出
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }

    // MARK: - Private Methods

    /// 删除 outbounds 中的第一个 sendThrough 字段，防止 Xray 某些版本出现兼容性问题.
    ///
    /// - Parameter configuration: 当前 Xray 配置字典.
    /// - Returns: 处理后、无 `sendThrough` 的配置字典.
    private func removeSendThroughFromOutbounds(from configuration: [String: Any]) -> [String: Any] {
        var updatedConfig = configuration

        // 如果 outbounds 不为空，则移除第一个 outbound 的 sendThrough
        if var outbounds = configuration["outbounds"] as? [[String: Any]], !outbounds.isEmpty {
            outbounds[0].removeValue(forKey: "sendThrough")
            updatedConfig["outbounds"] = outbounds
        }

        return updatedConfig
    }

    /// 递归移除字典中所有为 NSNull 或 "<null>" 的值.
    ///
    /// - Parameter dictionary: 待处理的 Xray 配置字典.
    /// - Returns: 移除空值后的新字典.
    private func removeNullValues(from dictionary: [String: Any]) -> [String: Any] {
        var updatedDictionary = dictionary

        for (key, value) in dictionary {
            if value is NSNull || "\(value)" == "<null>" {
                updatedDictionary.removeValue(forKey: key)
            } else if let nestedDictionary = value as? [String: Any] {
                // 递归处理字典
                updatedDictionary[key] = removeNullValues(from: nestedDictionary)
            } else if let nestedArray = value as? [[String: Any]] {
                // 递归处理字典数组
                updatedDictionary[key] = nestedArray.map { removeNullValues(from: $0) }
            }
        }

        return updatedDictionary
    }

    /// 将用户分享的配置链接（如 VLESS）解析为基础 Xray JSON，同时添加自定义 outbounds.
    ///
    /// 步骤：
    /// 1. 将原始字符串转成 Data，并 Base64 编码；
    /// 2. 调用 LibXrayConvertShareLinksToXrayJson 转换；
    /// 3. 对转换结果再次 Base64 解码并转为字典；
    /// 4. 将第一个 outbound 的 tag 改为 "proxy"；
    /// 5. 追加 freedom("direct")、blackhole("block") 作为额外 outbounds；
    ///
    /// - Parameter config: 配置分享链接.
    /// - Returns: 含 outbounds 的 Xray 配置字典.
    /// - Throws: 当链接字符串无效或解析 Xray JSON 失败时抛出.
    private func buildOutInbound(config: String) throws -> [String: Any] {
        // 1. 将原始字符串转为 Data
        guard let configData = config.data(using: .utf8) else {
            throw NSError(
                domain: "InvalidConfig",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的配置字符串"]
            )
        }

        // 2. Base64 编码后调用 LibXray 进行转换
        let base64EncodedConfig = configData.base64EncodedString()
        let xrayJsonString = LibXrayConvertShareLinksToXrayJson(base64EncodedConfig)

        // 3. 对转换后的字符串再次 Base64 解码，并解析为字典
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

        // 4. 将第一个 outbound 的 tag 改为 "proxy"
        if var firstOutbound = outboundsArray.first {
            firstOutbound["tag"] = "proxy"
            outboundsArray[0] = firstOutbound
        }

        // 5. 追加 freedom 和 blackhole
        let freedomObject: [String: Any] = [
            "protocol": "freedom",
            "tag": "direct",
        ]
        outboundsArray.append(freedomObject)

        let blockObject: [String: Any] = [
            "protocol": "blackhole",
            "tag": "block",
        ]
        outboundsArray.append(blockObject)

        // 6. 更新 outbounds
        dataDict["outbounds"] = outboundsArray
        return dataDict
    }

    /// 构建两个 inbound 配置：一个用于 SOCKS 代理服务，一个用于流量统计.
    ///
    /// - Parameters:
    ///   - inboundPort: SOCKS 代理端口.
    ///   - trafficPort: 流量统计端口.
    /// - Returns: 含 socks、metricsIn 的 inbound 数组.
    private func buildInbound(
        inboundPort: NWEndpoint.Port,
        trafficPort: NWEndpoint.Port?
    ) -> [[String: Any]] {
        let socksInbound: [String: Any] = [
            "listen": "127.0.0.1",
            "port": Int(inboundPort.rawValue),
            "protocol": "socks",
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": false,
            ],
            "settings": [
                "udp": true,
            ],
            "tag": "socks",
        ]

        if trafficPort == nil {
            return [socksInbound]
        }

        let metricsInbound: [String: Any] = [
            "listen": "127.0.0.1",
            "port": Int(trafficPort!.rawValue),
            "protocol": "dokodemo-door",
            "settings": [
                "address": "127.0.0.1",
            ],
            "tag": "metricsIn",
        ]

        return [socksInbound, metricsInbound]
    }

    /// 构建 metrics 配置（仅含一个简单的 tag）.
    ///
    /// - Returns: 带 `metricsOut` tag 的字典.
    private func buildMetrics() -> [String: Any] {
        return [
            "tag": "metricsOut",
        ]
    }

    /// 构建 policy 配置，用于统计上下行流量.
    ///
    /// - Returns: 包含策略设置的字典.
    private func buildPolicy() -> [String: Any] {
        return [
            "system": [
                "statsInboundDownlink": true,
                "statsInboundUplink": true,
                "statsOutboundDownlink": true,
                "statsOutboundUplink": true,
            ],
        ]
    }

    /// 根据 VPN 模式构建路由规则，主要针对非全局模式添加一些直连或屏蔽策略.
    ///
    /// - Throws: 访问文件失败时抛出.
    /// - Returns: 包含 routing 配置信息的字典.
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
        let vpnMode = Util.loadFromUserDefaults(key: "VPNMode") ?? VPNMode.nonGlobal.rawValue

        // 在非全局模式下，如果本地有地理规则文件，则执行额外的路由配置
        if vpnMode == VPNMode.nonGlobal.rawValue,
           let files = try? fileManager.contentsOfDirectory(atPath: assetDirectoryPath),
           !files.isEmpty
        {
            var rulesArray = route["rules"] as? [[String: Any]] ?? []

            // 屏蔽广告
            rulesArray.append([
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "geosite:category-ads-all",
                ],
            ])

            // 国内域名直连
            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "domain": [
                    "geosite:private",
                    "geosite:cn",
                ],
            ])

            // 国内 IP、私有 IP 直连
            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "ip": [
                    "geoip:private",
                    "geoip:cn",
                ],
            ])

            // 特定 IP 列表直连
            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "ip": [
                    "223.5.5.5",
                    "223.6.6.6",
                    "2400:3200::1",
                    "2400:3200:baba::1",
                    "119.29.29.29",
                    "1.12.12.12",
                    "120.53.53.53",
                    "2402:4e00::",
                    "2402:4e00:1::",
                    "180.76.76.76",
                    "2400:da00::6666",
                    "114.114.114.114",
                    "114.114.115.115",
                    "114.114.114.119",
                    "114.114.115.119",
                    "114.114.114.110",
                    "114.114.115.110",
                    "180.184.1.1",
                    "180.184.2.2",
                    "101.226.4.6",
                    "218.30.118.6",
                    "123.125.81.6",
                    "140.207.198.6",
                    "1.2.4.8",
                    "210.2.4.8",
                    "52.80.66.66",
                    "117.50.22.22",
                    "2400:7fc0:849e:200::4",
                    "2404:c2c0:85d8:901::4",
                    "117.50.10.10",
                    "52.80.52.52",
                    "2400:7fc0:849e:200::8",
                    "2404:c2c0:85d8:901::8",
                    "117.50.60.30",
                    "52.80.60.30",
                ],
            ])

            // 其他所有端口流量默认走 "proxy"
            rulesArray.append([
                "type": "field",
                "port": "0-65535",
                "outboundTag": "proxy",
            ])

            route["rules"] = rulesArray
        }

        return route
    }

    /// 构建 DNS 配置，包含 hosts 映射与自定义的 DNS 服务器.
    ///
    /// - Returns: 包含 hosts、servers 字段的 DNS 配置字典.
    private func buildDNSConfiguration() -> [String: Any] {
        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path
        let files = (try? fileManager.contentsOfDirectory(atPath: assetDirectoryPath)) ?? []
        let useGeoFiles = !files.isEmpty

        var servers: [Any] = []

        // 第一组：指定 googleapis.cn 与 gstatic.com
        servers.append([
            "address": "1.1.1.1",
            "skipFallback": true,
            "domains": [
                "domain:googleapis.cn",
                "domain:gstatic.com",
            ],
        ])

        // 第二组：中国地理规则 + 预期 IP
        if useGeoFiles {
            servers.append([
                "address": "223.5.5.5",
                "skipFallback": true,
                "domains": [
                    "geosite:cn",
                ],
                "expectIPs": [
                    "geoip:cn",
                ],
            ])
        }

        // 第三组：纯地址字符串，默认 DNS fallback
        servers.append(contentsOf: [
            "1.1.1.1",
            "8.8.8.8",
            "https://dns.google/dns-query",
        ])

        return [
            "hosts": ["dns.google": "8.8.8.8"],
            "servers": servers,
        ]
    }
}
