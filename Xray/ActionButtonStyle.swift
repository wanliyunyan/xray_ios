//
//  ActionButtonStyle.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 一个自定义的 `ButtonStyle`，用于为按钮提供统一的视觉样式。
/// 包括指定的背景颜色、白色文字、圆角，以及按压时透明度的变化。
struct ActionButtonStyle: ButtonStyle {
    /// 按钮的背景颜色。
    var color: Color

    /**
     根据给定配置生成按钮外观。

     - Parameters:
       - configuration: 系统提供的配置对象，包含按钮的文本标签和当前状态（是否按下）。

     - Returns: 应用指定样式的按钮视图。

     - Throws:

     - Note:
     */
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            // 让按钮在水平方向上尽量铺满
            .frame(maxWidth: .infinity)
            // 内边距，使按钮更易点按
            .padding()
            // 设置背景颜色
            .background(color)
            // 按钮文字颜色
            .foregroundColor(.white)
            // 为按钮添加圆角
            .cornerRadius(8)
            // 当按钮处于按压状态时，减小透明度
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
