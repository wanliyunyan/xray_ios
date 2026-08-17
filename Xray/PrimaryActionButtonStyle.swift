//
//  PrimaryActionButtonStyle.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 应用主操作按钮使用的统一 `ButtonStyle`。
///
/// 样式让标签横向占满可用空间，使用调用方指定的背景色、白色文字和固定圆角，
/// 并在按压期间降低透明度，为连接和断开按钮提供一致的视觉反馈。
struct PrimaryActionButtonStyle: ButtonStyle {
    /// 按钮的背景颜色，由连接状态决定，例如连接使用绿色、断开使用红色。
    var backgroundColor: Color

    /// 根据 SwiftUI 提供的标签和按压状态生成按钮外观。
    ///
    /// - Parameter configuration: 包含按钮标签及当前 `isPressed` 状态的样式配置。
    /// - Returns: 应用尺寸、颜色、圆角和按压透明度后的按钮视图。
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            // 横向填满父容器，并通过内边距提供稳定的点击区域。
            .frame(maxWidth: .infinity)
            .padding()
            // 背景色表达操作语义，白色文字保证对比度。
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            // 按压时降低透明度，明确反馈当前触摸状态。
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
