//
//  ShareButton.swift
//  Xray
//
//  Created by pan on 2024/9/29.
//

import CoreImage.CIFilterBuiltins
import SwiftUI

struct ShareModalView: View {
    @Binding var isShowing: Bool // 控制弹窗的显示与关闭
    @State private var shareLink: String = ""
    @State private var qrCodeImage: UIImage?

    var body: some View {
        NavigationView {
            VStack {
                // 显示生成的链接并处理换行
                if !shareLink.isEmpty {
                    Text(shareLink)
                        .font(.body)
                        .padding()
                        .lineLimit(nil) // 允许换行
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 显示二维码
                if let qrCodeImage {
                    Image(uiImage: qrCodeImage)
                        .resizable()
                        .interpolation(.none) // 避免图片缩放时模糊
                        .frame(width: 200, height: 200) // 更大的尺寸
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
                generateQRCode()
            } // 在视图显示时自动生成二维码
        }
    }

    // 自动生成二维码的方法
    private func generateQRCode() {
        guard let link = Util.loadFromUserDefaults(key: "configLink"), !link.isEmpty else {
            print("无法生成二维码，因为没有可用的内容")
            return
        }

        guard let data = link.data(using: .utf8) else {
            print("无法将内容转换为数据")
            return
        }

        shareLink = link

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")

        guard let qrCodeImage = filter.outputImage else {
            print("无法生成二维码图像")
            return
        }

        // 将二维码放大为更高分辨率
        let transform = CGAffineTransform(scaleX: 20, y: 20) // 放大二维码的分辨率
        let scaledQRCodeImage = qrCodeImage.transformed(by: transform)

        let context = CIContext()
        if let cgImage = context.createCGImage(scaledQRCodeImage, from: scaledQRCodeImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            self.qrCodeImage = uiImage
        } else {
            print("无法生成二维码的 CGImage")
        }
    }
}
