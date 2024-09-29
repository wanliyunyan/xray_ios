//
//  Configuration.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import LibXray

struct Configuration {

    func buildConfigurationData(inboundPort: Int, trafficPort: Int, config: String) throws -> Data {
        var configuration: [String: Any] = [:]
        
        configuration["metrics"] = self.buildMetrics()
        configuration["inbounds"] = self.buildInbound(inboundPort: inboundPort,trafficPort:trafficPort)
        
        // 获取 dataDict
        let dataDict = try self.buildOutInbound(config: config)
        
        // 合并 inbound 和 dataDict
        dataDict.forEach { configuration[$0.key] = $0.value }
        
        configuration["policy"] =  self.buildPolicy()
        configuration["routing"] =  self.buildRoute()
        configuration["stats"] =  [:]
        
        return try JSONSerialization.data(withJSONObject: configuration, options: .prettyPrinted)
    }
    
    private func buildInbound(inboundPort: Int,trafficPort: Int = 10085) -> [[String: Any]] {
        let inbound1: [String: Any] = [
            "listen": "127.0.0.1",
            "port": inboundPort,
            "protocol": "socks",
            "settings": [
                "auth": "noauth",
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
    
    private func buildRoute() -> [String: Any] {
        return [
            "domainStrategy": "IpIfNonMatch",
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
              let dataDict = jsonDict["data"] as? [String: Any] else {
            throw NSError(domain: "InvalidXrayJson", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析 Xray JSON 失败"])
        }

        return dataDict
    }
}
