//
//  XrayManager.swift
//  Xray
//
//  Created by pan on 2025/9/19.
//

import LibXray
import Network
import os

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "XrayManager")

@MainActor
struct XrayManager {
    // MARK: - 辅助方法

    /**
     构造一个 `PingRequest` 请求对象，包含配置文件路径、端口、超时和代理信息。
     该请求对象常用于发起底层的 Ping 测试。

     - Parameters:
       - configPath: 配置文件在本地的路径。
       - socks5Port: SOCKS5 代理使用的端口号。

     - Returns: 生成的 `PingRequest` 对象。

     - Throws: 当参数无效时可能抛出错误。

     - Note:
     */
    func createPingRequest(configPath: String, socks5Port: NWEndpoint.Port) throws -> PingRequest {
        PingRequest(
            datDir: Constant.assetDirectory.path, // 数据文件目录
            configPath: configPath, // Xray 配置文件路径
            timeout: Constant.timeout, // 超时时间（秒）
            url: Constant.pingUrl, // 用于检测的网络地址
            proxy: "socks5://127.0.0.1:\(socks5Port)" // 使用的代理地址
        )
    }

    /**
     将底层返回的 Base64 编码结果解码并解析为 JSON，从中提取 Ping 延迟值。

     解析过程分为三步：
     1. Base64 解码字符串；
     2. 将解码后的字符串转换为 JSON；
     3. 从 JSON 中提取 `success` 字段并判断是否成功，若成功则返回 `data` 字段中的延迟值。

     - Parameters:
       - base64String: Base64 编码的字符串，包含 Ping 测试结果。

     - Returns: 若成功解析且 success 字段为 true，则返回表示 Ping 延迟（ms）的整数；如果 success 字段为 false 或解析失败，则返回 nil。

     - Throws:

     - Note: 这是异步方法，适合在后台线程调用，以避免阻塞主线程。
     */
    func decodePingResponse(base64String: String) async -> Int? {
        // Base64 解码和字符串转 Data 的检查。
        guard let decodedData = Data(base64Encoded: base64String),
              let decodedString = String(data: decodedData, encoding: .utf8),
              let jsonData = decodedString.data(using: .utf8)
        else {
            logger.error("Base64 解码或字符串转 Data 失败")
            return nil
        }

        do {
            // JSON 解析成功与否，以及字段 `success` 和 `data` 的校验。
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
               let success = jsonObject["success"] as? Bool,
               success,
               let data = jsonObject["data"] as? Int
            {
                return data
            }
        } catch {
            // 捕获错误时的日志记录。
            logger.error("解析 JSON 失败: \(error.localizedDescription)")
        }

        return nil
    }

    /**
     将 JSON 格式的配置传入 LibXray 并返回 Base64 编码字符串。
     遇到错误时会抛出异常。

     - Parameters:
       - datDir: 数据目录路径。
       - configJSON: 配置的 JSON 字符串。

     - Returns: Base64 编码的字符串结果。

     - Throws: 传入的参数无效或调用底层库失败时抛出错误。

     - Note:
     */
    func makeRunFromJSONRequest(datDir: String, configJSON: String) throws -> String {
        var error: NSError?
        let base64String = LibXrayNewXrayRunFromJSONRequest(datDir, configJSON, &error)
        if let err = error {
            throw err
        }
        return base64String
    }

    /**
     执行完整的 Ping 测试流程。

     流程包括：
     1. 加载配置链接；
     2. 构建 Ping 配置数据；
     3. 写入临时配置文件；
     4. 获取 SOCKS5 代理端口；
     5. 构造 Ping 请求对象；
     6. 调用底层 Ping 方法；
     7. 解析并返回延迟值。

     - Parameters:

     - Returns: Ping 延迟值（毫秒）。

     - Throws: 读取配置、转换数据、调用底层或解析失败时抛出错误。

     - Note:
     */
    func performPing() async throws -> Int {
        // 1. 读取配置
        guard let savedConfigLink = UtilStore.loadString(key: "configLink"),
              !savedConfigLink.isEmpty
        else {
            throw NSError(domain: "PingView",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可用的配置"])
        }

        // 2. 构造配置
        let configData = try Configuration().buildPingConfigurationData(configLink: savedConfigLink)
        guard let mergedConfigString = String(data: configData, encoding: .utf8) else {
            throw NSError(domain: "PingView",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法将配置数据转换为字符串"])
        }

        // 3. 写入临时文件
        let fileUrl = try Util.createConfigFile(with: mergedConfigString)

        // 4. 读取端口
        guard let socks5Port = UtilStore.loadPort(key: "socks5Port") else {
            throw NSError(domain: "PingView",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口"])
        }

        // 5. 构造请求
        let pingRequest = try createPingRequest(configPath: fileUrl.path, socks5Port: socks5Port)
        let pingBase64String = try JSONEncoder().encode(pingRequest).base64EncodedString()

        // 6. 调用底层
        let pingResponseBase64 = LibXrayPing(pingBase64String)

        // 7. 解析返回
        guard let pingResult = await decodePingResponse(base64String: pingResponseBase64) else {
            throw NSError(domain: "PingView",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Ping 解码失败"])
        }
        return pingResult
    }

    /**
     获取底层 LibXray 的版本号。

     流程包括 Base64 解码和 JSON 解析，若成功返回版本字符串，否则抛出错误。

     - Parameters:

     - Returns: 版本号字符串。

     - Throws: 版本号解码或解析失败时抛出错误。

     - Note:
     */
    func getVersion() throws -> String {
        // 1. 从 LibXray 获取版本号的 Base64 字符串
        let base64Version = LibXrayXrayVersion()

        // 2. 解码 Base64
        guard let decodedData = Data(base64Encoded: base64Version),
              let decodedString = String(data: decodedData, encoding: .utf8)
        else {
            throw NSError(
                domain: "XrayManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "版本号解码失败"]
            )
        }

        // 3. 解析 JSON 获取版本号
        let jsonData = Data(decodedString.utf8)
        let versionResponse = try JSONDecoder().decode(VersionResponse.self, from: jsonData)
        if versionResponse.success {
            return versionResponse.data
        } else {
            throw NSError(
                domain: "XrayManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "获取版本号失败：success 为 false"]
            )
        }
    }

    /**
     查询当前流量统计信息（上下行字节数）。

     该方法解析多层嵌套 JSON，若成功则返回元组 `(downlink, uplink)` 表示流量统计。

     - Parameters:
       - trafficPort: 监听流量统计的端口。

     - Returns: 包含下行和上行流量的元组，失败时返回 nil。

     - Throws:

     - Note:
     */
    func getTrafficStats(trafficPort: NWEndpoint.Port) -> (downlink: Int, uplink: Int)? {
        // 组装可访问的流量查询地址
        let trafficQueryString = "http://127.0.0.1:\(trafficPort)/debug/vars"

        // 转为 Data 并进行 Base64 编码
        guard let trafficData = trafficQueryString.data(using: .utf8) else {
            logger.error("无法将字符串转换为 Data")
            return nil
        }
        let base64TrafficString = trafficData.base64EncodedString()

        // 使用已保存的 base64TrafficString 向 LibXray 发送查询请求
        let responseBase64 = LibXrayQueryStats(base64TrafficString)

        // 对返回结果做 Base64 解码
        guard let decodedData = Data(base64Encoded: responseBase64),
              let decodedString = String(data: decodedData, encoding: .utf8)
        else {
            logger.error("无法解码 LibXrayQueryStats 返回的数据")
            return nil
        }

        // 将字符串转换为 JSON Data
        guard let jsonData = decodedString.data(using: .utf8) else {
            logger.error("无法将响应字符串转换为 JSON Data")
            return nil
        }

        do {
            // 将 JSON Data 转换为字典结构
            guard let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                logger.error("JSON 对象不是字典类型")
                return nil
            }

            // 判断 success 是否为 1，表示请求成功
            guard let success = jsonObject["success"] as? Int, success == 1 else {
                logger.error("解析失败: success 字段不是 1")
                return nil
            }

            // 获取 "data" 字段并确保其为字符串
            guard let dataValue = jsonObject["data"] else {
                logger.error("在 JSON 对象中找不到 data 字段")
                return nil
            }

            guard let dataString = dataValue as? String else {
                logger.error("data 字段不是字符串类型")
                return nil
            }

            // 对 data 字段内嵌套的字符串再进行一次 JSON 解析
            guard let nestedJsonData = dataString.data(using: .utf8) else {
                logger.error("无法将 data 字符串转换为 Data")
                return nil
            }

            guard let dataDict = try JSONSerialization.jsonObject(with: nestedJsonData, options: []) as? [String: Any] else {
                logger.error("无法解析嵌套的 JSON 数据")
                return nil
            }

            // 读取 "stats -> inbound -> socks" 对象
            guard let stats = dataDict["stats"] as? [String: Any],
                  let inbound = stats["inbound"] as? [String: Any],
                  let socks = inbound["socks"] as? [String: Any]
            else {
                logger.error("在 dataDict 中找不到 stats 或 inbound 或 socks 节点")
                return nil
            }

            // 分别获取下行和上行流量，并转换为字符串存储
            guard let socksDownlink = socks["downlink"] as? Int,
                  let socksUplink = socks["uplink"] as? Int
            else {
                logger.error("无法获取 socks 下行或上行流量字段")
                return nil
            }

            return (downlink: socksDownlink, uplink: socksUplink)

        } catch {
            logger.error("解析 JSON 时出错: \(error)")
            return nil
        }
    }

    /**
     调用底层获取两个空闲端口。

     解析流程为 Base64 解码 → JSON 解析 → 端口数组提取。
     若获取失败，则返回默认端口数组。

     - Parameters:

     - Returns: 两个空闲端口的数组，失败时返回默认端口。

     - Throws:

     - Note:
     */
    func fetchFreePorts() -> [NWEndpoint.Port] {
        // 1. 从 LibXray 获取两个空闲端口 (Base64 编码的字符串)
        let freePortsBase64String = LibXrayGetFreePorts(2)

        // 2. 解析 Base64 并转为 JSON 字符串
        guard
            let decodedData = Data(base64Encoded: freePortsBase64String),
            let decodedString = String(data: decodedData, encoding: .utf8)
        else {
            logger.error("Base64 解码失败")
            return [Constant.socks5Port, Constant.trafficPort]
        }

        // 3. 解析 JSON 并提取端口
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: Data(decodedString.utf8), options: []) as? [String: Any] {
                guard let success = jsonObject["success"] as? Bool, success else {
                    print("success 字段不是 Bool 或值不为 true: \(jsonObject["success"] ?? "nil")")
                    return [Constant.socks5Port, Constant.trafficPort]
                }

                guard let dataDict = jsonObject["data"] as? [String: Any] else {
                    print("data 字段缺失或类型错误: \(jsonObject["data"] ?? "nil")")
                    return [Constant.socks5Port, Constant.trafficPort]
                }

                guard let portsInt = dataDict["ports"] as? [Int], portsInt.count == 2 else {
                    print("ports 字段缺失或类型错误: \(dataDict["ports"] ?? "nil")")
                    return [Constant.socks5Port, Constant.trafficPort]
                }

                // 转换成 NWEndpoint.Port
                let ports = portsInt.compactMap { NWEndpoint.Port(rawValue: UInt16($0)) }
                return ports
            }
        } catch {
            logger.error("JSON 解析错误: \(error.localizedDescription)")
        }
        return [Constant.socks5Port, Constant.trafficPort]
    }

    /**
     将分享链接转换为 Xray JSON 配置，解析并返回字典。
     遇到错误时会抛出异常。

     - Parameters:
       - configLink: 原始分享配置字符串。

     - Returns: 转换后的 Xray JSON 字典。

     - Throws: 解码或解析失败时抛出错误。

     - Note:
     */
    func convertConfigLinkToXrayJson(configLink: String) throws -> [String: Any] {
        // 1. 将原始字符串转为 Data
        guard let configData = configLink.data(using: .utf8) else {
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
            let dataDict = jsonDict["data"] as? [String: Any]
        else {
            throw NSError(
                domain: "InvalidXrayJson",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"]
            )
        }

        return dataDict
    }
}
