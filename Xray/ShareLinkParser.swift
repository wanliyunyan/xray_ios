//
//  ShareLinkParser.swift
//  Xray
//

import Foundation

/// The node details shown in the dashboard after parsing a share link.
struct NodeSummary {
    let identifier: String
    let host: String
    let port: String
}

/// Parses the displayable fields from an Xray share link.
enum ShareLinkParser {
    /// Returns a node summary when the input can be represented as URL components.
    static func parse(_ shareLink: String) -> NodeSummary? {
        guard let components = URLComponents(string: shareLink) else {
            return nil
        }

        return NodeSummary(
            identifier: components.user ?? "",
            host: components.host ?? "",
            port: components.port.map(String.init) ?? ""
        )
    }
}
