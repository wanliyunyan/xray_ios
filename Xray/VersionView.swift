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

     - Parameters:

     - Returns:

     - Throws:

     - Note:
     调用 `xrayManager.getVersion()` 获取版本号；成功更新 `versionText`，失败时显示错误提示；调用时机在 `onAppear`，界面效果初始为 `"Loading..."`，完成后显示结果或错误信息。
     */
    private func fetchVersion() {
        do {
            versionText = try xrayManager.getVersion()
        } catch {
            versionText = "解析版本号失败: \(error.localizedDescription)"
        }
    }
}
