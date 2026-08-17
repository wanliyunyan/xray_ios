//
//  XrayConfigurationBuilder.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import Network

/// 从分享链接构建应用使用的完整 Xray JSON 配置。
///
/// LibXray 负责把 VLESS 等分享链接转换为包含代理出站的基础配置，本类型在此基础上：
/// - 将首个代理出站统一标记为 `proxy`，并补齐 `direct` 与 `block` 出站；
/// - 为正式 VPN 运行注入 TUN 入站、Metrics、流量统计、路由和 DNS；
/// - 为延迟测试生成只包含 SOCKS 入站的精简配置；
/// - 合并 Xray 资源目录环境变量，清理空值和不兼容的 `sendThrough` 字段；
/// - 最终序列化为可交给 LibXray 或 Packet Tunnel 扩展的 JSON 数据。
///
/// 类型运行在主 Actor，因为它会读取 App Group 偏好，并由 SwiftUI 操作流程直接调用。
@MainActor
struct XrayConfigurationBuilder {
    // MARK: - Public API

    /// 生成正式 VPN 连接使用的完整运行配置。
    ///
    /// 构建顺序：
    /// 1. 从 App Group 偏好读取 Metrics HTTP 服务端口；
    /// 2. 将分享链接转换为基础 Xray 配置并规范化出站；
    /// 3. 注入 TUN 入站、资源环境、Metrics、Policy、Routing、Stats 和 DNS；
    /// 4. 递归移除 LibXray 转换结果中的空值；
    /// 5. 移除所有出站的 `sendThrough`，避免错误绑定本机接口；
    /// 6. 使用易于排查的 pretty-printed 格式序列化为 JSON。
    ///
    /// - Parameter configLink: 用户保存的分享链接。
    /// - Returns: 可交给 Packet Tunnel 扩展的 JSON 数据。
    /// - Throws: Metrics 端口缺失、分享链接转换失败或 JSON 无法序列化时抛出错误。
    func buildRunConfigurationData(configLink: String) throws -> Data {
        // 1. Metrics 端口必须和流量视图读取的端口保持一致。
        guard let trafficPort = AppGroupStore.loadPort(key: "trafficPort") else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 从分享链接取得代理出站，并补齐应用依赖的固定出站。
        var configuration = try buildOutInbound(configLink: configLink)

        // 3. 注入正式运行所需的所有应用侧配置片段。
        configuration["inbounds"] = buildTunInbound()
        configuration["env"] = buildEnvironment(from: configuration["env"])
        configuration["metrics"] = buildMetrics(trafficPort: trafficPort)
        configuration["policy"] = buildPolicy()
        configuration["routing"] = buildRoute()
        configuration["stats"] = [:]
        configuration["dns"] = buildDNSConfiguration()

        // 4. 清理转换结果中的空值和不兼容字段。
        configuration = removeNullValues(from: configuration)
        configuration = removeSendThroughFromOutbounds(from: configuration)

        // 5. 输出可读 JSON，便于检查最终落盘配置。
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }

    /// 生成 LibXray 延迟测试使用的精简配置。
    ///
    /// 与正式运行配置不同，此配置只注入本地 SOCKS 入站和资源目录，不包含 TUN、Metrics、
    /// Policy、Routing、Stats 或 DNS。`XrayService.performPing()` 会把它写入共享文件，再让
    /// LibXray 通过该 SOCKS 代理访问测试地址。
    ///
    /// - Parameter configLink: 用户保存的分享链接。
    /// - Returns: 可写入 Ping 配置文件的 JSON 数据。
    /// - Throws: SOCKS5 端口缺失、分享链接转换失败或 JSON 无法序列化时抛出错误。
    func buildPingConfigurationData(configLink: String) throws -> Data {
        // 1. SOCKS 入站端口必须和 Ping 请求中的代理地址保持一致。
        guard let socks5Port = AppGroupStore.loadPort(key: "socks5Port")
        else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 复用与正式运行相同的代理出站规范化逻辑。
        var configuration = try buildOutInbound(configLink: configLink)

        // 3. Ping 只需要 SOCKS 入站和 Xray 资源目录。
        configuration["inbounds"] = buildSocksInbound(inboundPort: socks5Port)
        configuration["env"] = buildEnvironment(from: configuration["env"])

        // 4. 清理后输出精简 JSON。
        configuration = removeNullValues(from: configuration)
        configuration = removeSendThroughFromOutbounds(from: configuration)

        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }

    // MARK: - Normalization

    /// 移除所有出站的 `sendThrough`，避免将分享链接名称误作本机出站接口。
    ///
    /// - Parameter configuration: 待规范化的完整配置字典。
    /// - Returns: 包含清理后 `outbounds` 的新字典；没有出站数组时原样返回。
    private func removeSendThroughFromOutbounds(from configuration: [String: Any]) -> [String: Any] {
        var updatedConfig = configuration

        if let outbounds = configuration["outbounds"] as? [[String: Any]] {
            updatedConfig["outbounds"] = outbounds.map { outbound in
                var normalized = outbound
                normalized.removeValue(forKey: "sendThrough")
                return normalized
            }
        }

        return updatedConfig
    }

    /// 递归移除字典和字典数组中的空值。
    ///
    /// LibXray 转换结果可能同时包含真正的 `NSNull`，以及打印形式为 `"<null>"` 的值。
    /// 方法会遍历嵌套字典与字典数组并删除对应键，其他标量和数组保持不变。
    ///
    /// - Parameter dictionary: 原始配置字典。
    /// - Returns: 清理后的新字典，不修改传入对象。
    private func removeNullValues(from dictionary: [String: Any]) -> [String: Any] {
        var updatedDictionary = dictionary

        for (key, value) in dictionary {
            if value is NSNull || "\(value)" == "<null>" {
                updatedDictionary.removeValue(forKey: key)
            } else if let nestedDictionary = value as? [String: Any] {
                updatedDictionary[key] = removeNullValues(from: nestedDictionary)
            } else if let nestedArray = value as? [[String: Any]] {
                updatedDictionary[key] = nestedArray.map { removeNullValues(from: $0) }
            }
        }

        return updatedDictionary
    }

    // MARK: - Configuration Components

    /// 解析分享链接并规范化应用依赖的三个出站标签。
    ///
    /// 处理步骤：
    /// 1. 使用 `XrayService` 调用 LibXray 转换分享链接；
    /// 2. 校验转换结果包含非空 `outbounds`；
    /// 3. 将第一个出站的 tag 统一改为 `proxy`；
    /// 4. 缺少时分别追加 `freedom/direct` 和 `blackhole/block`。
    ///
    /// - Parameter configLink: 原始分享链接文本。
    /// - Returns: 保留 LibXray 其他字段、并具有稳定出站标签的配置字典。
    /// - Throws: 分享链接转换失败，或结果缺少有效出站时抛出错误。
    private func buildOutInbound(configLink: String) throws -> [String: Any] {
        var dataDict = try XrayService().convertConfigLinkToXrayJson(configLink: configLink)

        guard var outboundsArray = dataDict["outbounds"] as? [[String: Any]] else {
            throw NSError(
                domain: "InvalidXrayJson",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败，未找到 outbounds"]
            )
        }

        guard var firstOutbound = outboundsArray.first else {
            throw NSError(
                domain: "InvalidXrayJson",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败，outbounds 为空"]
            )
        }
        firstOutbound["tag"] = "proxy"
        outboundsArray[0] = firstOutbound

        let freedomObject: [String: Any] = [
            "protocol": "freedom",
            "tag": "direct",
        ]
        let blockObject: [String: Any] = [
            "protocol": "blackhole",
            "tag": "block",
        ]

        if !outboundsArray.contains(where: { $0["tag"] as? String == "direct" }) {
            outboundsArray.append(freedomObject)
        }
        if !outboundsArray.contains(where: { $0["tag"] as? String == "block" }) {
            outboundsArray.append(blockObject)
        }

        dataDict["outbounds"] = outboundsArray
        return dataDict
    }

    /// 构建仅供 Ping 测试使用的 SOCKS 入站。
    ///
    /// 入站监听全部本地地址，启用 TCP/UDP 嗅探和 UDP 转发，tag 固定为 `socks`。
    ///
    /// - Parameter inboundPort: SOCKS 服务监听端口。
    /// - Returns: 可直接写入 Xray `inbounds` 的单元素数组。
    private func buildSocksInbound(
        inboundPort: NWEndpoint.Port
    ) -> [[String: Any]] {
        let socksInbound: [String: Any] = [
            "listen": "0.0.0.0",
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

        return [socksInbound]
    }

    /// 构建直接消费 NetworkExtension utun 的 TUN 入站。
    ///
    /// 配置本身不包含文件描述符，因为 utun 只有在扩展应用网络设置后才存在。实际 FD 由
    /// `PacketTunnelProvider` 在启动时写入 `env.xray.tun.fd`。入站 tag 固定为 `tun-in`，
    /// Metrics 流量查询依赖该名称。
    ///
    /// - Returns: 可直接写入 Xray `inbounds` 的单元素数组。
    private func buildTunInbound() -> [[String: Any]] {
        let tunInbound: [String: Any] = [
            "protocol": "tun",
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": false,
            ],
            "settings": [
                "mtu": 1500,
                "userLevel": 0,
            ],
            "tag": "tun-in",
        ]

        return [tunInbound]
    }

    /// 合并现有环境变量，并指定共享的 Xray 资源目录。
    ///
    /// - Parameter existingValue: LibXray 基础配置中已有的 `env` 值；非字典时按空字典处理。
    /// - Returns: 保留原字段并写入 `xray.location.asset` 的环境字典。
    private func buildEnvironment(from existingValue: Any?) -> [String: Any] {
        var environment = existingValue as? [String: Any] ?? [:]
        environment["xray.location.asset"] = AppConstants.assetDirectory.path
        return environment
    }

    /// 构建只监听回环地址的 Metrics HTTP 服务配置。
    ///
    /// - Parameter trafficPort: App 随机分配并持久化的监听端口。
    /// - Returns: Xray `metrics` 配置；流量视图通过 `/debug/vars` 读取统计值。
    private func buildMetrics(trafficPort: NWEndpoint.Port) -> [String: Any] {
        [
            "tag": "Metrics",
            "listen": "127.0.0.1:\(trafficPort.rawValue)"
        ]
    }

    /// 开启入站和出站的上下行流量统计。
    ///
    /// - Returns: 写入 Xray `policy.system` 的四个统计开关。
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

    /// 根据用户选择和本地 geo 资源构建路由规则。
    ///
    /// - 全局模式：不添加分流规则，所有 TCP/UDP 最终匹配 `proxy`；
    /// - 非全局模式且 geo 文件可用：广告域名走 `block`，中国/私有域名与 IP 走
    ///   `direct`，常见国内公共 DNS 地址也直接连接；
    /// - 非全局模式但 geo 文件缺失：跳过依赖 `geoip/geosite` 的规则，避免 Xray 因资源
    ///   不存在而启动失败；
    /// - 最后一条兜底规则始终把其余 TCP/UDP 流量交给 `proxy`。
    ///
    /// - Returns: 可写入 Xray `routing` 字段的字典。
    private func buildRoute() -> [String: Any] {
        var route: [String: Any] = [
            "domainStrategy": "AsIs",
            "rules": [

            ],
        ]

        let fileManager = FileManager.default
        let assetDirectoryPath = AppConstants.assetDirectory.path
        let vpnMode = AppGroupStore.loadString(key: "VPNMode") ?? VPNMode.nonGlobal.rawValue

        // geo 规则依赖本地资源文件，仅在非全局模式下启用。
        if vpnMode == VPNMode.nonGlobal.rawValue,
           let files = try? fileManager.contentsOfDirectory(atPath: assetDirectoryPath),
           !files.isEmpty
        {
            var rulesArray = route["rules"] as? [[String: Any]] ?? []

            rulesArray.append([
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "geosite:category-ads-all",
                ],
            ])

            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "domain": [
                    "geosite:private",
                    "geosite:cn",
                ],
            ])

            rulesArray.append([
                "type": "field",
                "outboundTag": "direct",
                "ip": [
                    "geoip:private",
                    "geoip:cn",
                ],
            ])

            // 常见国内公共 DNS 地址直连。
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

            route["rules"] = rulesArray
        }

        var rulesArray = route["rules"] as? [[String: Any]] ?? []
        rulesArray.append([
            "type": "field",
            "network": ["tcp", "udp"],
            "outboundTag": "proxy",
        ])
        route["rules"] = rulesArray

        return route
    }

    /// 构建兼顾国外解析与国内分流的 DNS 配置。
    ///
    /// 规则顺序如下：
    /// 1. `googleapis.cn` 和 `gstatic.com` 使用 `1.1.1.1` 且不进入 fallback；
    /// 2. 本地 geo 文件可用时，中国域名使用 `223.5.5.5`，并要求结果匹配 `geoip:cn`；
    /// 3. 其余查询依次回退到 Cloudflare、Google DNS 和 Google DoH；
    /// 4. `dns.google` 固定映射到 `8.8.8.8`，避免解析 DoH 主机时产生循环依赖。
    ///
    /// - Returns: 包含 `hosts` 与 `servers` 的 Xray DNS 字典。
    private func buildDNSConfiguration() -> [String: Any] {
        let fileManager = FileManager.default
        let assetDirectoryPath = AppConstants.assetDirectory.path
        let files = (try? fileManager.contentsOfDirectory(atPath: assetDirectoryPath)) ?? []
        let useGeoFiles = !files.isEmpty

        var servers: [Any] = []

        // 为 Google 静态资源指定可直接访问的解析器。
        servers.append([
            "address": "1.1.1.1",
            "skipFallback": true,
            "domains": [
                "domain:googleapis.cn",
                "domain:gstatic.com",
            ],
        ])

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

        // 通用回退解析器。
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
