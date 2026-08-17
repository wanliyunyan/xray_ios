//
//  ConfigurationShareView.swift
//  Xray
//
//  Created by pan on 2024/9/29.
//

import CoreImage.CIFilterBuiltins
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConfigurationShareView")

/// 展示当前分享链接，并生成可供其他设备扫描的二维码。
///
/// 视图从 App Group 偏好读取 `configLink`，同时展示原始文本和 Core Image 生成的二维码。
/// 关闭操作通过外部绑定控制 Sheet；配置缺失或图像生成失败时保留加载提示并记录日志。
struct ConfigurationShareView: View {
    /// 父视图控制 Sheet 展示状态的绑定，点击关闭按钮时写入 `false`。
    @Binding var isPresented: Bool

    /// 当前持久化的原始分享链接，用于文本展示和二维码输入。
    @State private var shareLink: String = ""

    /// Core Image 输出转换后的 UIKit 图片；生成完成前为 `nil`。
    @State private var qrCodeImage: UIImage?

    /// 构建带标题和关闭按钮的分享界面。
    var body: some View {
        NavigationView {
            VStack {
                // 原始链接允许多行显示，便于用户同时核对或手动复制。
                if !shareLink.isEmpty {
                    Text(shareLink)
                        .font(.body)
                        .padding()
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                }

                // 二维码尚未生成时保留加载提示，成功后禁用插值保持边缘清晰。
                if let image = qrCodeImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 200, height: 200)
                        .padding()
                } else {
                    Text("正在生成二维码...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .navigationBarTitle("分享配置", displayMode: .inline)
            .navigationBarItems(trailing: Button("关闭") {
                isPresented = false
            })
            .onAppear {
                generateQRCodeImage()
            }
        }
    }

    // MARK: - QR Code

    /// 从 App Group 偏好读取分享链接，并生成二维码图像。
    ///
    /// 生成步骤：
    /// 1. 读取非空 `configLink` 并同步到文本状态；
    /// 2. 使用 UTF-8 Data 设置 `CIQRCodeGenerator` 的输入消息；
    /// 3. 将 Core Image 原始二维码按 20 倍整数比例放大；
    /// 4. 通过 `CIContext` 生成 `CGImage`，再转换为 SwiftUI 可显示的 `UIImage`。
    ///
    /// 整数倍缩放配合 `.interpolation(.none)` 可以保持二维码模块边界清晰。任何一步失败都会
    /// 记录具体原因并保持 `qrCodeImage == nil`。
    private func generateQRCodeImage() {
        // 1. 分享内容始终以 App Group 中当前保存的链接为准。
        guard let link = AppGroupStore.loadString(forKey: "configLink"),
              !link.isEmpty
        else {
            logger.error("无法生成二维码，因为没有可用的配置内容")
            return
        }

        shareLink = link

        // 2. Core Image 二维码滤镜接收原始字节消息。
        guard let data = link.data(using: .utf8) else {
            logger.error("无法将配置信息转换为数据")
            return
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")

        guard let qrCodeImage = filter.outputImage else {
            logger.error("无法生成二维码图像")
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
        }
    }
}
