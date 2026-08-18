//
//  XrayVersionView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 读取并显示底层 Xray Core 版本号。
///
/// 视图出现时异步调用统一 LibXray 接口。请求完成前显示 `Loading...`；成功后显示版本号，
/// 失败时直接把本地化错误描述写入文本，便于用户和开发者定位底层库问题。
struct XrayVersionView: View {
    /// 提供 Xray Core 版本查询能力。
    private let xrayService = XrayService()

    /// 当前展示文本，初始为加载提示，随后替换为版本号或错误信息。
    @State private var versionText: String = "Loading..."

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text("xray版本号:")
                    .fixedSize(horizontal: true, vertical: false)
                Text(versionText)
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(spacing: 4) {
                Text("xray版本号:")
                Text(versionText)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .task {
            do {
                versionText = try await xrayService.fetchCoreVersion()
            } catch {
                versionText = "解析版本号失败: \(error.localizedDescription)"
            }
        }
    }
}
