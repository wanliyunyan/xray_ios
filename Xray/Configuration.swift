//
//  Configuration.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import LibXray

struct Configuration {

    func buildConfigurationData(config: String) throws -> Data {
        
        // 从 UserDefaults 加载端口并尝试转换为 Int
        guard let inboundPortString = Util.loadFromUserDefaults(key: "sock5Port"),
              let trafficPortString = Util.loadFromUserDefaults(key: "trafficPort"),
              let inboundPort = Int(inboundPortString),
              let trafficPort = Int(trafficPortString) else {
            throw NSError(domain: "ConfigurationError", code: 0, userInfo: [NSLocalizedDescriptionKey: "无法从 UserDefaults 加载端口或端口格式不正确"])
        }

        var configuration: [String: Any] = [:]
        
        configuration["metrics"] = self.buildMetrics()
        configuration["inbounds"] = self.buildInbound(inboundPort: inboundPort,trafficPort:trafficPort)
        
        // 获取 dataDict
        let dataDict = try self.buildOutInbound(config: config)
        
        // 合并 inbound 和 dataDict
        dataDict.forEach { configuration[$0.key] = $0.value }
        
        configuration["policy"] =  self.buildPolicy()
        configuration["routing"] =  try self.buildRoute()
        configuration["stats"] =  [:]
        
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }
    
    private func buildInbound(inboundPort: Int = Constant.sock5Port ,trafficPort: Int = Constant.trafficPort) -> [[String: Any]] {
        let inbound1: [String: Any] = [
            "listen": "127.0.0.1",
            "port": inboundPort,
            "protocol": "socks",
            "settings": [
                "udp": true
            ],
            "tag": "socks"
        ]
        
        let inbound2: [String: Any] = [
            "listen": "127.0.0.1",
            "port": trafficPort,
            "protocol": "dokodemo-door",
            "settings": [
                "address": "127.0.0.1"
            ],
            "tag": "metricsIn"
        ]
        
        return [inbound1, inbound2]
    }
    
    private func buildMetrics() -> [String: Any] {
        return [
            "tag" : "metricsOut"
        ]
    }

    private func buildPolicy() -> [String: Any] {
        return [
            "system": [
                "statsInboundDownlink": true,
                "statsInboundUplink": true,
                "statsOutboundDownlink": true,
                "statsOutboundUplink": true
            ]
        ]
    }
    
    private func buildRoute() throws -> [String: Any] {
        var route: [String: Any] = [
            "domainStrategy": "AsIs",
            "rules": [
                [
                    "inboundTag": [
                        "metricsIn"
                    ],
                    "outboundTag": "metricsOut",
                    "type": "field"
                ]
            ]
        ]

        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        let vpnMode = Util.loadFromUserDefaults(key: "VPNMode") ?? VPNMode.nonGlobal.rawValue

        if vpnMode == VPNMode.nonGlobal.rawValue,
            let files = try? fileManager.contentsOfDirectory(atPath: assetDirectoryPath), !files.isEmpty {
            // 如果有文件，添加 geosite 和 geoip 相关规则
            route["rules"] = (route["rules"] as! [[String: Any]]) + [
                [
                    "type": "field",
                    "outboundTag": "direct",
                    "domain": [
                        "geosite:cn"
                    ]
                ],
                [
                    "type": "field",
                    "outboundTag": "direct",
                    "ip": [
                        "223.5.5.5/32",
                        "114.114.114.114/32",
                        "geoip:private",
                        "geoip:cn"
                    ]
                ],
                [
                    "type": "field",
                    "port": "0-65535",
                    "outboundTag": "proxy"
                ]
            ]
        }

        return route
    }
    
    private func buildOutInbound(config: String) throws -> [String: Any] {
        // 将传入的 config 字符串进行 Base64 编码并转换为 Xray JSON
        guard let configData = config.data(using: .utf8) else {
            throw NSError(domain: "InvalidConfig", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的配置字符串"])
        }
        let base64EncodedConfig = configData.base64EncodedString()
        let xrayJsonString = LibXrayConvertShareLinksToXrayJson(base64EncodedConfig)

        // 解码 Xray JSON 字符串
        guard let decodedData = Data(base64Encoded: xrayJsonString),
              let decodedString = String(data: decodedData, encoding: .utf8),
              let jsonData = decodedString.data(using: .utf8),
              let jsonDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
              let success = jsonDict["success"] as? Bool, success,
              let dataDict = jsonDict["data"] as? [String: Any],
              var outboundsArray = dataDict["outbounds"] as? [[String: Any]] else {
            throw NSError(domain: "InvalidXrayJson", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"])
        }

        // 确保 outbounds 数组中至少有一个对象
        if var firstOutbound = outboundsArray.first {
            // 添加 tag: "proxy" 属性
            firstOutbound["tag"] = "proxy"
            
            // 更新 outbounds 数组中的第一个对象
            outboundsArray[0] = firstOutbound
        }

        // 要插入的对象
        let newObject: [String: Any] = [
            "protocol": "freedom",
            "tag": "direct"
        ]

        // 拼接新的对象到 outbounds 数组
        outboundsArray.append(newObject)

        // 更新 dataDict 中的 outbounds 数组
        var updatedDataDict = dataDict
        updatedDataDict["outbounds"] = outboundsArray

        return updatedDataDict
    }
}
