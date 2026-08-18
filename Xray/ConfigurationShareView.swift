//
//  ConfigurationShareView.swift
//  Xray
//
//  Created by pan on 2024/9/29.
//

import CoreImage.CIFilterBuiltins
import os
import SwiftUI

// MARK: - 日志

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "ConfigurationShareView")

/// 展示当前分享链接，并生成可供其他设备扫描的二维码。
///
/// 调用方负责传入已经校验的分享链接，视图同时展示原始文本和 Core Image 生成的二维码。
/// 关闭操作使用环境中的 dismiss；图像生成失败时展示明确的错误状态并记录日志。
struct ConfigurationShareView: View {
    @Environment(\.dismiss) private var dismiss

    /// 已经由分享入口校验的原始分享链接。
    let shareLink: String

    /// Core Image 输出转换后的 UIKit 图片；生成完成前为 `nil`。
    @State private var qrCodeImage: UIImage?

    /// 标记配置失效或 Core Image 生成失败，避免界面永久停留在加载文案。
    @State private var didFailToGenerate = false

    /// 构建带标题和关闭按钮的分享界面。
    var body: some View {
        NavigationStack {
            VStack {
                // 原始链接允许多行显示，便于用户同时核对或手动复制。
                Text(shareLink)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 成功后禁用插值保持边缘清晰；失败时提供可恢复的明确提示。
                if let image = qrCodeImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 200, height: 200)
                        .padding()
                } else if didFailToGenerate {
                    ContentUnavailableView(
                        "无法生成二维码",
                        systemImage: "qrcode",
                        description: Text("配置内容无效，请重新导入后再试。")
                    )
                } else {
                    ProgressView("正在生成二维码...")
                        .font(.caption)
                }

                Spacer()
            }
            .navigationTitle("分享配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("关闭")
                }
            }
            .task {
                generateQRCodeImage()
            }
        }
    }

    // MARK: - 二维码

    /// 校验传入的分享链接并生成二维码图像。
    ///
    /// 生成步骤：
    /// 1. 确认分享链接仍然可以解析；
    /// 2. 使用 UTF-8 Data 设置 `CIQRCodeGenerator` 的输入消息；
    /// 3. 将 Core Image 原始二维码按 20 倍整数比例放大；
    /// 4. 通过 `CIContext` 生成 `CGImage`，再转换为 SwiftUI 可显示的 `UIImage`。
    ///
    /// 整数倍缩放配合 `.interpolation(.none)` 可以保持二维码模块边界清晰。任何一步失败都会
    /// 记录具体原因并切换到错误状态。
    private func generateQRCodeImage() {
        guard ShareLinkParser.parse(shareLink) != nil else {
            logger.error("无法生成二维码，因为配置内容无效")
            didFailToGenerate = true
            return
        }

        // 2. Core Image 二维码滤镜接收原始字节消息。
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(shareLink.utf8)

        guard let qrCodeImage = filter.outputImage else {
            logger.error("无法生成二维码图像")
            didFailToGenerate = true
            return
        }

        // 3. 使用整数比例放大，避免生成低分辨率二维码后再进行模糊插值。
        let transform = CGAffineTransform(scaleX: 20, y: 20)
        let scaledQRCodeImage = qrCodeImage.transformed(by: transform)

        // 4. 将 CIImage 渲染为 UIKit 图片并更新 SwiftUI 状态。
        let context = CIContext()
        if let cgImage = context.createCGImage(scaledQRCodeImage,
                                               from: scaledQRCodeImage.extent)
        {
            let uiImage = UIImage(cgImage: cgImage)
            self.qrCodeImage = uiImage
        } else {
            logger.error("无法将二维码转换为 CGImage")
            didFailToGenerate = true
        }
    }
}
