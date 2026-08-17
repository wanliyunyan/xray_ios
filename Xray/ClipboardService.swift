//
//  ClipboardService.swift
//  Xray
//

import UIKit

/// Reads user-provided text from the system clipboard.
enum ClipboardService {
    /// Returns the current non-empty clipboard string.
    static func readString() -> String? {
        guard let value = UIPasteboard.general.string, !value.isEmpty else {
            return nil
        }
        return value
    }
}
