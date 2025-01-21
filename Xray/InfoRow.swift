//
//  InfoRow.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 一个展示两段文本信息的行视图：左侧是标签，右侧是主要信息。
struct InfoRow: View {
    // MARK: - 属性

    /// 左侧标签文本
    var label: String

    /// 右侧展示的主要文本
    var text: String

    // MARK: - 主视图

    var body: some View {
        HStack {
            Text(label)
            Text(text)
                .lineLimit(1) // 限制为单行显示
                .truncationMode(.tail) // 超出长度时尾部省略
        }
    }
}
