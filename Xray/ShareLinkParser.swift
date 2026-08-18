//
//  ShareLinkParser.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Foundation

/// 解析分享链接后在仪表盘中显示的节点详情。
struct NodeSummary: Equatable, Sendable {
    let identifier: String
    let host: String
    let port: String

    static let empty = NodeSummary(identifier: "", host: "", port: "")
}

/// 解析 Xray 分享链接中可显示的字段。
enum ShareLinkParser {
    /// 输入内容可以表示为 URL 组件时返回节点摘要。
    static func parse(_ shareLink: String) -> NodeSummary? {
        let normalizedShareLink = shareLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: normalizedShareLink),
            let scheme = components.scheme,
            !scheme.isEmpty
        else {
            return nil
        }

        return NodeSummary(
            identifier: components.user ?? "",
            host: components.host ?? "",
            port: components.port.map(String.init) ?? ""
        )
    }
}
