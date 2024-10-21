import Foundation
import SwiftUI

struct DownloadView: View {

    var body: some View {
        VStack {
            // 将“更新”和“清空”按钮放在一行
            HStack {
                // 更新按钮
                Button(action: {
                    downloadAndUpdateGeoipDat()
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle") // 下载图标
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("地理文件") // 按钮文本
                    }
                }
                .padding()

                Spacer() // 添加空隙

                // 清空按钮
                Button(action: {
                    clearAssetDirectory()
                }) {
                    HStack {
                        Image(systemName: "trash") // 垃圾桶图标
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("清空") // 按钮文本
                    }
                }
                .padding()
            }
        }
        .padding() // 外层的 padding 调整整体布局
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
            ("https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat", "geosite.dat")
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

    // 清空 Constant.assetDirectory 文件夹
    private func clearAssetDirectory() {
        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        do {
            // 删除整个文件夹
            if fileManager.fileExists(atPath: assetDirectoryPath) {
                try fileManager.removeItem(atPath: assetDirectoryPath)
                print("已删除文件夹: \(assetDirectoryPath)")
            }

            // 重新创建文件夹
            try fileManager.createDirectory(atPath: assetDirectoryPath, withIntermediateDirectories: true, attributes: nil)
            print("已重新创建文件夹: \(assetDirectoryPath)")

        } catch {
            print("操作失败: \(error.localizedDescription)")
        }
    }
}
