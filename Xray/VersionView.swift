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

    /// 从 LibXray 获取版本号的 Base64 字符串，并进行解码、解析。
    ///
    /// 调用 `LibXrayXrayVersion()` 获取版本信息的 Base64 表示，然后解码并转为 JSON 字符串，
    /// 最后调用 `XrayManager.parseVersion(jsonString:)` 进一步解析。
    private func fetchVersion() {
        do {
            versionText = try xrayManager.getVersion()
        } catch {
            versionText = "解析版本号失败: \(error.localizedDescription)"
        }
    }
}
