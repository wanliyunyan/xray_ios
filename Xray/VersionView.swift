//
//  VersionView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import Foundation
import SwiftUI
import LibXray

struct VersionView: View {
    @State private var versionText: String = "Loading..."
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack {
            HStack {
                Text("版本号:")
                    .padding(.leading, 10)
                Text(versionText)
                    .padding(.leading, 5)
            }
            .padding(.top, 20)
        }
        .onAppear {
            fetchVersion()
        }
        .alert(isPresented: $showErrorAlert) {
            Alert(title: Text("错误"), message: Text(errorMessage), dismissButton: .default(Text("确定")))
        }
    }

    // MARK: - 获取版本号
    private func fetchVersion() {
        let base64Version = LibXrayXrayVersion()  // 调用库方法获取版本号的 Base64 字符串

        // 将 Base64 解码为 JSON 字符串
        if let decodedData = Data(base64Encoded: base64Version),
           let decodedString = String(data: decodedData, encoding: .utf8) {
            parseVersion(jsonString: decodedString)
        } else {
            showError("版本号解码失败")
        }
    }

    // MARK: - 解析 JSON 格式的版本号
    private func parseVersion(jsonString: String) {
        struct VersionResponse: Codable {
            let success: Bool
            let data: String
        }

        do {
            let jsonData = Data(jsonString.utf8)
            let versionResponse = try JSONDecoder().decode(VersionResponse.self, from: jsonData)

            if versionResponse.success {
                versionText = versionResponse.data  // 将版本号显示到页面上
            } else {
                showError("获取版本号失败")
            }
        } catch {
            showError("解析版本号失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Handling
    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}
