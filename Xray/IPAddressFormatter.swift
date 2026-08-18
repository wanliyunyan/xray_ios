//
//  IPAddressFormatter.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

/// 格式化用于显示的 IP 地址，避免暴露完整的 IPv4 地址。
enum IPAddressFormatter {
    /// 隐藏 IPv4 地址的前三个八位组，其他地址格式保持不变。
    static func masked(_ address: String) -> String {
        let octets = address.split(separator: ".")
        guard octets.count == 4 else {
            return address
        }
        return "*.*.*." + octets[3]
    }
}
