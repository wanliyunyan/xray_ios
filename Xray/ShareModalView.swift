//
//  ShareModalView.swift
//  Xray
//
//  Created by pan on 2024/9/29.
//

import CoreImage.CIFilterBuiltins
import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ShareModalView")

/// 一个用于展示配置信息并生成二维码以供分享的视图。
struct ShareModalView: View {
    // MARK: - 绑定变量

    /// 是否显示该弹窗视图的状态，由外部进行绑定与控制。
    @Binding var isShowing: Bool

    // MARK: - 本地状态

    /// 用于存储将要分享（展示）的配置信息字符串。
    @State private var shareLink: String = ""

    /// 通过 CoreImage 生成的二维码图片。
    @State private var qrCodeImage: UIImage?

    // MARK: - 主视图

    var body: some View {
        NavigationView {
            VStack {
                // 如果已经成功获取到文本信息，则进行展示
                if !shareLink.isEmpty {
                    Text(shareLink)
                        .font(.body)
                        .padding()
                        .lineLimit(nil) // 允许多行显示
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                }

                // 如果已经生成二维码，则显示；否则显示加载提示
                if let image = qrCodeImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none) // 避免二维码缩放时的模糊
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
                isShowing = false
            })
            .onAppear {
                // 视图出现后触发二维码生成逻辑
                generateQRCode()
            }
        }
    }

    // MARK: - 业务逻辑

    /// 从本地加载配置信息并生成二维码。
    ///
    /// 1. 从 `UserDefaults` 中读取保存的配置信息；
    /// 2. 若有值则更新 `shareLink`；
    /// 3. 使用 CoreImage 生成二维码并放大；
    /// 4. 将生成的二维码写入 `qrCodeImage` 状态以供显示。
    private func generateQRCode() {
        // 1. 从 UserDefaults 加载配置信息
        guard let link = Util.loadFromUserDefaults(key: "configLink"),
              !link.isEmpty
        else {
            logger.error("无法生成二维码，因为没有可用的配置内容")
            return
        }

        // 2. 将配置内容存储到本地状态用于 UI 显示
        shareLink = link

        // 3. 将字符串转换为 Data
        guard let data = link.data(using: .utf8) else {
            logger.error("无法将配置信息转换为数据")
            return
        }

        // 4. 创建二维码滤镜并设置输入
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")

        // 5. 判断是否成功生成初步二维码图像
        guard let qrCodeImage = filter.outputImage else {
            logger.error("无法生成二维码图像")
            return
        }

        // 6. 放大二维码，使其分辨率更高
        let transform = CGAffineTransform(scaleX: 20, y: 20) // 数字越大，最终分辨率越高
        let scaledQRCodeImage = qrCodeImage.transformed(by: transform)

        // 7. 转换为可在 SwiftUI 中使用的 UIImage
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
