//
//  VersionView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 显示 Xray 版本号的视图。
struct VersionView: View {
    private let xrayManager = XrayManager()

    // MARK: - State

    /// 用于存储当前版本号。如果请求尚未完成，则显示 "Loading..."。
    @State private var versionText: String = "Loading..."

    // MARK: - Body

    var body: some View {
        VStack {
            HStack {
                Text("xray版本号:")
                Text(versionText)
            }
        }
        .onAppear {
            fetchVersion()
        }
    }

    // MARK: - 业务逻辑

    /**
     获取 Xray 的版本号并更新到界面。
     
     处理逻辑：
     - 调用 `xrayManager.getVersion()` 获取版本号；
     - 如果成功，赋值给 `versionText`，显示在界面上；
     - 如果失败，捕获错误并显示错误提示。
     
     调用时机：在 `onAppear` 生命周期方法中触发，保证界面加载时自动显示版本号。
     
     界面效果：初始值为 `"Loading..."`，完成后显示真实版本或错误信息。
     */
    private func fetchVersion() {
        do {
            versionText = try xrayManager.getVersion()
        } catch {
            versionText = "解析版本号失败: \(error.localizedDescription)"
        }
    }
}
