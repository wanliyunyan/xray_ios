//
//  VersionView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import LibXray
import SwiftUI

/// 显示 Xray 版本号的视图。
///
/// 内部调用 `LibXray` 提供的方法获取版本信息，并解析为可读的字符串。
/// 若遇到错误，则以 Alert 的形式进行提示。
struct VersionView: View {
    // MARK: - State

    /// 用于存储当前版本号。如果请求尚未完成，则显示 "Loading..."。
    @State private var versionText: String = "Loading..."

    /// 用于显示错误提示的弹窗。
    @State private var showErrorAlert: Bool = false

    /// 错误信息内容，配合 `showErrorAlert` 一起使用。
    @State private var errorMessage: String = ""

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
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text("错误"),
                message: Text(errorMessage),
                dismissButton: .default(Text("确定"))
            )
        }
    }

    // MARK: - 业务逻辑

    /// 从 LibXray 获取版本号的 Base64 字符串，并进行解码、解析。
    ///
    /// 调用 `LibXrayXrayVersion()` 获取版本信息的 Base64 表示，然后解码并转为 JSON 字符串，
    /// 最后调用 `parseVersion(jsonString:)` 进一步解析。
    private func fetchVersion() {
        // 1. 从 LibXray 获取版本号的 Base64 字符串
        let base64Version = LibXrayXrayVersion()

        // 2. 解码 Base64
        if let decodedData = Data(base64Encoded: base64Version),
           let decodedString = String(data: decodedData, encoding: .utf8)
        {
            // 3. 解析 JSON 获取版本号
            parseVersion(jsonString: decodedString)
        } else {
            showError("版本号解码失败")
        }
    }

    /// 解析 JSON 格式的版本信息，将其转为易读的字符串并更新界面。
    ///
    /// - Parameter jsonString: Base64 解码后得到的 JSON 字符串。
    ///
    /// JSON 示例结构：
    /// ```json
    /// {
    ///   "success": true,
    ///   "data": "1.0.0"
    /// }
    /// ```
    private func parseVersion(jsonString: String) {
        // 定义一个内部使用的结构，用于匹配 JSON。
        struct VersionResponse: Codable {
            let success: Bool
            let data: String
        }

        do {
            // 1. 将 JSON 字符串转换为 Data
            let jsonData = Data(jsonString.utf8)
            // 2. 使用 JSONDecoder 解析
            let versionResponse = try JSONDecoder().decode(VersionResponse.self, from: jsonData)

            // 3. 根据 success 字段判断是否成功
            if versionResponse.success {
                versionText = versionResponse.data
            } else {
                showError("获取版本号失败：success 为 false")
            }
        } catch {
            showError("解析版本号失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 辅助方法

    /// 设置错误信息并弹出错误提示。
    ///
    /// - Parameter message: 需要显示给用户的错误详情。
    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}
