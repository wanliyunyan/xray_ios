//
//  Constant.swift
//  Xray
//
//  Created by pan on 2024/9/14.
//

import Foundation

public enum Constant {
    public static let packageName: String = Bundle.main.bundleIdentifier ?? "unknown"
}

public extension Constant {
    static let groupName = "group.\(Constant.packageName)"
    static let tunnelName = "\(Constant.packageName).PacketTunnel"
    
    // Xray 配置，以 JSON 格式表示，用于配置 Xray 核心
    static let xrayConfig = """
    {
        "inbounds": [{
            "settings": {
                "udp": true,
                "auth": "noauth"
            },
            "port": "10808",
            "listen": "127.0.0.1",
            "protocol": "socks"
        }]
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
