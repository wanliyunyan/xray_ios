//
//  Constant.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Foundation

public enum Constant {
    public static let packageName = {
        Bundle.main.infoDictionary?["APP_ID"] as? String ?? "unknown"
    }()
}

public extension Constant {
    static let groupName = "group.\(packageName)"
    static let TunnelName = "\(packageName).PacketTunnel"
    
    // Xray 配置，以 JSON 格式表示，用于配置 Xray 核心
    static let xrayConfig="""
    {
        "inbounds": [{
            "settings": {
                "udp": true,
                "auth": "noauth"
            },
            "port": "10808",
            "listen": "127.0.0.1",
            "protocol": "socks"
        }],
        "outbounds": [
            {
                "tag": "proxy",
                "protocol": "vless",
                "settings": {
                    "vnext": [{
                        "address": "address",
                        "port": 6689,
                        "users": [{
                            "encryption": "none",
                            "id": "30a8fe2b-7fd0-48bb-a03f-434c8e24e152"
                        }]
                    }]
                }
            },
            {
                "tag": "direct",
                "protocol": "freedom"
            },
            {
                "tag": "block",
                "protocol": "blackhole"
            }
        ]
    }
    """
    
    static let socks5Config = """
        tunnel:
          mtu: 1500
        
        socks5:
          port: 10808
          address: 127.0.0.1
          udp: 'udp'
        
        misc:
          task-stack-size: 20480
          connect-timeout: 5000
          read-write-timeout: 60000
          log-file: stderr
          log-level: debug
          limit-nofile: 65535
    """
}
