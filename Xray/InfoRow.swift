//
//  InfoRow.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 用于展示节点摘要的标签和值行。
///
/// 标签和值水平排列；值限制为单行，空间不足时从尾部省略，避免较长的 UUID、域名或
/// 地址撑破主界面布局。
struct InfoRow: View {
    /// 左侧固定标签，例如 `ID:`、`IP地址:` 或 `端口:`。
    var label: String

    /// 右侧由分享链接解析得到的实际内容。
    var text: String

    /// 构建单行标签和值布局。
    var body: some View {
        HStack {
            Text(label)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
