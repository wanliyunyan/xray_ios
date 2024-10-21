//
//  DownloadProgressView.swift
//  Xray
//
//  Created by pan on 2024/10/17.
//

import Foundation
import SwiftUI

struct DownloadView: View {

    var body: some View {
        // 更新按钮
        Button(action: {
            downloadAndUpdateGeoipDat()
        }) {
            HStack {
                Image(systemName: "arrow.down.circle") // 下载图标
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("更新geoip.dat与geosite.dat") // 按钮文本
            }
        }
    }

    
    // 下载并更新 geoip.dat 和 geosite.dat 文件
    @MainActor
    private func saveFileToDirectory(fileURL: URL, fileName: String) {
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: Constant.assetDirectory.path).appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL) // 如果文件存在，则删除
            }
            try fileManager.moveItem(at: fileURL, to: destinationURL)
            print("\(fileName) 文件已成功移动到 \(destinationURL.path)")
        } catch {
            print("文件保存失败: \(error.localizedDescription)")
        }
    }

    private func downloadAndUpdateGeoipDat() {
        let urls = [
            ("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat", "geoip.dat"),
            ("https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat", "geosite.dat"),
//            ("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat", "geosite.dat")   // 内存溢出
        ]

        for (urlString, fileName) in urls {
            if let url = URL(string: urlString) {
                downloadFile(from: url) { result in
                    switch result {
                    case .success(let fileURL):
                        // 直接调用主 actor 隔离的方法
                        Task {
                            await saveFileToDirectory(fileURL: fileURL, fileName: fileName)
                        }
                    case .failure(let error):
                        print("文件下载失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // 下载文件
    private func downloadFile(from url: URL, completion: @escaping @Sendable (Result<URL, Swift.Error>) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let localURL = localURL else {
                completion(.failure(NSError(domain: "DownloadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取本地文件 URL"])))
                return
            }
            completion(.success(localURL))
        }
        task.resume()
    }
}
