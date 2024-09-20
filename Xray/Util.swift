//
//  Util.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import SwiftUI

struct Util {

    // MARK: - UserDefaults Handling

    static func saveToUserDefaults(value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func loadFromUserDefaults(key: String) -> String? {
        return UserDefaults.standard.string(forKey: key)
    }

    // MARK: - Clipboard Handling

    static func pasteFromClipboard() -> String? {
        if let clipboardContent = UIPasteboard.general.string, !clipboardContent.isEmpty {
            return clipboardContent
        }
        return nil
    }

    // MARK: - Parsing

    static func parseContent(_ content: String, idText: inout String, ipText: inout String, portText: inout String) {
        if let url = URLComponents(string: content) {
            ipText = url.host ?? ""
            idText = url.user ?? ""
            portText = url.port.map(String.init) ?? ""
        }
    }

    // MARK: - Mask IP Address

    static func maskIPAddress(_ ipAddress: String) -> String {
        let components = ipAddress.split(separator: ".")
        return components.count == 4 ? "*.*.*." + components[3] : ipAddress
    }
}
