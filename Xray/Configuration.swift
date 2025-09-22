//
//  Configuration.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import Network

/**
 Configuration：负责**从外部分享链接生成完整且可运行的 Xray 配置**（JSON Data），并针对应用的“全局/非全局模式”与本地 geo 资源进行增强与裁剪。

 - 设计目标：
   - 将用户分享链接（如 VLESS 等）解析为基础 outbounds；
   - 合并应用侧固定的 inbounds / metrics / policy / routing / dns 等模块；
   - 清理潜在的兼容性问题（如 `sendThrough`、空值）；
   - 最终生成可直接交给 Xray 核心使用的 JSON Data。

 - 线程模型：标记为 `@MainActor`，便于与依赖的偏好读取、UI 触发流程对齐（不会在方法内部进行 UI 操作）。
 - 依赖与输入：`UserDefaults`（通过 `UtilStore` 读取端口）、`XrayManager`（解析分享链接并产出初始 JSON）。
 - 错误边界：端口缺失/非法、分享链接解析失败、JSON 序列化失败等都会抛错。
*/
@MainActor
struct Configuration {
    // MARK: - Public Methods

    /**
     生成**用于运行**（含流量统计）的 Xray 配置，并序列化为 JSON Data。

     - 流程概览：
       1. 从 `UserDefaults` 读取 `socks5Port` 与 `trafficPort`（通过 `UtilStore.loadPort`）；
       2. 调用 `buildOutInbound(configLink:)` 解析分享链接并得到初始配置（含 outbounds）；
       3. 注入应用内的 `inbounds / metrics / policy / routing / stats / dns`；
       4. 递归移除所有空值（`NSNull` / `&lt;null&gt;`）；
       5. 去除第一个 outbound 的 `sendThrough` 字段（兼容性考虑）；
       6. 输出为 JSON Data（pretty-printed，便于日志与调试）。

     - Parameter configLink: 外部复制的分享链接字符串（如 VLESS）。
     - Returns: 可直接交给 Xray 核心的 JSON 数据。
     - Throws: 当端口读取失败、分享链接解析失败或 JSON 序列化失败时抛出。
     - 注意：本方法会注入 metrics/统计相关 inbounds 与路由，适用于“运行态”。
    */
    func buildRunConfigurationData(configLink: String) throws -> Data {
        // 1. 从 UserDefaults 中获取端口
        guard
            let socks5Port = UtilStore.loadPort(key: "socks5Port"),
            let trafficPort = UtilStore.loadPort(key: "trafficPort")
        else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 基于用户分享链接生成 Xray outbounds
        var configuration = try buildOutInbound(configLink: configLink)

        // 3. 添加自定义 inbound、metrics、policy、routing、stats、dns 等
        configuration["inbounds"] = buildInbound(inboundPort: socks5Port, trafficPort: trafficPort)
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

    /**
     生成**用于 Ping 测试**的精简 Xray 配置，并序列化为 JSON Data。

     与运行配置的差异：
     - 仅注入 SOCKS inbound（不包含 metrics/统计端口）；
     - 省略 `metrics / policy / routing / stats / dns` 中与 Ping 无关的部分，仅保留必要最小集。

     - Parameter configLink: 外部复制的分享链接字符串。
     - Returns: 适用于 Ping 请求的 JSON 数据。
     - Throws: 当端口读取失败、分享链接解析失败或 JSON 序列化失败时抛出。
    */
    func buildPingConfigurationData(configLink: String) throws -> Data {
        // 1. 从 UserDefaults 中获取端口
        guard let socks5Port = UtilStore.loadPort(key: "socks5Port")
        else {
            throw NSError(
                domain: "ConfigurationError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"]
            )
        }

        // 2. 基于用户分享链接生成 Xray outbounds
        var configuration = try buildOutInbound(configLink: configLink)

        // 3. 添加自定义 inbound、metrics、policy、routing、stats、dns 等
        configuration["inbounds"] = buildInbound(inboundPort: socks5Port, trafficPort: nil)

        // 4. 递归移除配置中所有 NSNull 或 "<null>" 值
        configuration = removeNullValues(from: configuration)

        // 5. 去除第一个 outbound 的 sendThrough 字段
        configuration = removeSendThroughFromOutbounds(from: configuration)

        // 6. 序列化为 JSON Data 输出
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }

    // MARK: - Private Methods

    /**
     移除 `outbounds` 中**第一个 outbound**的 `sendThrough` 字段，以规避部分 Xray 版本的兼容性问题。

     - Parameter configuration: 待处理的配置字典。
     - Returns: 若存在 `outbounds`，将第一个条目的 `sendThrough` 清理后返回；否则原样返回。
     - 说明：仅处理第一个 outbound；若调用方追加了更多 outbounds，保持其原状。
    */
    private func removeSendThroughFromOutbounds(from configuration: [String: Any]) -> [String: Any] {
        var updatedConfig = configuration

        // 如果 outbounds 不为空，则移除第一个 outbound 的 sendThrough
        if var outbounds = configuration["outbounds"] as? [[String: Any]], !outbounds.isEmpty {
            outbounds[0].removeValue(forKey: "sendThrough")
            updatedConfig["outbounds"] = outbounds
        }

        return updatedConfig
    }

    /**
     递归移除配置中所有“空值”，包括 `NSNull` 与字符串 `"<null>"`。

     - 算法要点：
       - 对字典：逐键检查；对子字典/字典数组递归处理；
       - 对标量：若为 `NSNull` 或字面量为 `"<null>";` 则剔除该键；
       - 其他类型保持不变。

     - Parameter dictionary: 原始配置字典。
     - Returns: 已清理空值的新字典（不修改入参）。
    */
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

    /**
     将用户分享的配置链接（如 VLESS）解析为**基础 Xray JSON**，并注入标准化的 outbounds。

     - 步骤：
       1. 使用 `XrayManager().convertConfigLinkToXrayJson(configLink:)` 解析分享链接，得到初始字典；
       2. 确保存在 `outbounds` 数组，若缺失则抛出“解析失败”错误；
       3. 将第一个 outbound 的 `tag` 规范为 `"proxy"`；
       4. 追加两个内置 outbound：`freedom`（tag: `"direct"`）与 `blackhole`（tag: `"block"`）；
       5. 回填到配置字典并返回。

     - Parameter configLink: 分享链接原文。
     - Returns: 至少包含规范化 `outbounds` 的配置字典。
     - Throws: 分享链接无效、或无法解析为合法的 Xray JSON 时抛出。
    */
    private func buildOutInbound(configLink: String) throws -> [String: Any] {
        // 1. 使用 XrayManager 将用户分享的配置链接解析为基础 Xray JSON
        var dataDict = try XrayManager().convertConfigLinkToXrayJson(configLink: configLink)

        // 2. 校验解析结果中是否包含 outbounds 数组；若缺失则视为配置无效并抛错
        guard var outboundsArray = dataDict["outbounds"] as? [[String: Any]] else {
            throw NSError(
                domain: "InvalidXrayJson",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败，未找到 outbounds"]
            )
        }

        // 3. 将第一个 outbound 的 tag 标准化为 "proxy"，确保后续路由规则能够正确匹配
        if var firstOutbound = outboundsArray.first {
            firstOutbound["tag"] = "proxy"
            outboundsArray[0] = firstOutbound
        }

        // 4. 追加内置出站配置：
        //    - freedom：直连（tag: direct）
        //    - blackhole：阻断（tag: block）
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

        // 5. 更新配置字典中的 outbounds，并返回最终结果
        dataDict["outbounds"] = outboundsArray
        return dataDict
    }

    /**
     构建应用的 inbounds 集合：**SOCKS 代理**与（可选）**流量统计入口**。

     - socksInbound：
       - 监听 `0.0.0.0`，端口为 `inboundPort`；
       - 开启 sniffing（`http/tls/quic`），`udp=true`；
       - `tag = "socks"`，供路由/出站匹配使用。

     - metricsInbound（可选）：
       - 当 `trafficPort != nil` 时启用；
       - 使用 `dokodemo-door` 监听 `127.0.0.1:trafficPort`，`tag = "metricsIn"`；
       - 与路由中的 `metricsOut` 搭配，将度量数据引出到独立出站。

     - Parameters:
       - inboundPort: SOCKS 代理端口。
       - trafficPort: 流量统计端口；传入 `nil` 则不创建。
     - Returns: `[socksInbound]` 或 `[socksInbound, metricsInbound]`。
    */
    private func buildInbound(
        inboundPort: NWEndpoint.Port,
        trafficPort: NWEndpoint.Port?
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

    /**
     构建 metrics 出站占位配置（`tag = "metricsOut"`），用于与路由规则联动。
     实际上不包含复杂字段，仅用于将 `metricsIn` 的流量分流到该出站。
    */
    private func buildMetrics() -> [String: Any] {
        [
            "tag": "metricsOut",
        ]
    }

    /**
     构建 `policy` 配置，开启入站/出站的上下行统计开关，便于后续做流量/连接度量。
    */
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

    /**
     构建路由规则集（`routing`）。

     - 基线规则：
       - 设置 `domainStrategy = "AsIs"`；
       - 将 `metricsIn` 的流量转发到 `metricsOut`。

     - 非全局模式（`VPNMode.nonGlobal`）下的增强（要求本地 `Constant.assetDirectory` 存在 geo 资源）：
       - 屏蔽广告域名：`geosite:category-ads-all -&gt; block`；
       - 国内域名直连：`geosite:private`、`geosite:cn -&gt; direct`；
       - 国内/私有 IP 直连：`geoip:private`、`geoip:cn -&gt; direct`；
       - 常见公共 DNS/加速 IP 直连（内置清单）；
       - 其余端口范围默认走 `"proxy"`。

     - Returns: 完整的 routing 字典。
     - Throws: 访问本地资源目录失败时抛出。
     - 注意：全局模式仅保留基线规则；增强规则受本地 geo 资源是否存在的影响。
    */
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
        let vpnMode = UtilStore.loadString(key: "VPNMode") ?? VPNMode.nonGlobal.rawValue

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

    /**
     构建 DNS 配置，兼顾国内可达性与通用回退。

     - hosts：
       - 将 `dns.google` 映射到 `8.8.8.8`。

     - servers：
       1. 第一条：选择 `1.1.1.1`，并仅对 `googleapis.cn / gstatic.com` 生效（`skipFallback=true`）；
       2. 若存在本地 geo 文件，追加：
          - `223.5.5.5` + `geosite:cn` 域名且 `expectIPs=geoip:cn`（提高国内域名解析可控性）；
       3. 通用回退：`1.1.1.1`、`8.8.8.8`、`https://dns.google/dns-query`。

     - Returns: 包含 `hosts` 与 `servers` 的 DNS 配置字典。
    */
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
