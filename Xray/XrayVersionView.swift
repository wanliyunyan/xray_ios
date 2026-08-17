//
//  XrayVersionView.swift
//  Xray
//
//  Created by pan on 2024/9/20.
//

import SwiftUI

/// 读取并显示底层 Xray Core 版本号。
///
/// 视图出现时同步调用统一 LibXray 接口。请求完成前显示 `Loading...`；成功后显示版本号，
/// 失败时直接把本地化错误描述写入文本，便于用户和开发者定位底层库问题。
struct XrayVersionView: View {
    /// 提供 Xray Core 版本查询能力。
    private let xrayService = XrayService()

    /// 当前展示文本，初始为加载提示，随后替换为版本号或错误信息。
    @State private var versionText: String = "Loading..."

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

    /// 调用 `XrayService.getVersion()` 并更新展示状态。
    ///
    /// 方法不继续抛出错误，因为版本号是辅助信息，不应阻断主界面；错误会转换为可见文本。
    private func fetchVersion() {
        do {
            versionText = try xrayService.getVersion()
        } catch {
            versionText = "解析版本号失败: \(error.localizedDescription)"
        }
    }
}
