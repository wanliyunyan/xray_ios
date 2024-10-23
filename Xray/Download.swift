//
//  DownloadProgressView.swift
//  Xray
//
//  Created by pan on 2024/10/17.
//

import Foundation
import SwiftUI

struct DownloadView: View {
    @State private var isDownloading: Bool = false
    @State private var downloadedFiles: [String] = []
    @State private var completedDownloads: Int = 0 // 新增，跟踪已完成下载的文件数

    var body: some View {
        VStack {
            // 更新和清空按钮
            HStack {
                Button(action: {
                    downloadAndUpdateGeoipDat()
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("地理文件")
                    }
                }
                .padding()
                .disabled(isDownloading)
                .foregroundColor(isDownloading ? .gray : .blue)

                Button(action: {
                    clearAssetDirectory()
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .resizable()
                            .frame(width: 30, height: 30)
                        Text("清空地理")
                    }
                }
                .padding()
                .disabled(isDownloading)
                .foregroundColor(isDownloading ? .gray : .blue)
            }

            // 显示已下载的文件
            if !downloadedFiles.isEmpty {
                HStack {  // 使用 HStack 水平排列文件名
                    Text("已下载:")
                        .padding(.top)

                    ForEach(downloadedFiles, id: \.self) { file in
                        Text(file)
                            .lineLimit(1) // 限制每个文件名在一行内显示
                            .truncationMode(.tail) // 如果文件名过长，显示省略号
                            .padding(.leading, 10)
                    }
                }
            }
        }
        .onAppear {
            loadDownloadedFiles()
        }
    }

    private func loadDownloadedFiles() {
        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        do {
            let files = try fileManager.contentsOfDirectory(atPath: assetDirectoryPath)
            downloadedFiles = files
        } catch {
            print("加载文件失败: \(error.localizedDescription)")
        }
    }

    // 下载并更新 geoip.dat 和 geosite.dat 文件
    private func downloadAndUpdateGeoipDat() {
        let urls = [
            ("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat", "geoip.dat"),
            ("https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat", "geosite.dat")
        ]

        isDownloading = true
        completedDownloads = 0 // 重置计数器

        // 逐一下载文件，而不是并发
        for (urlString, fileName) in urls {
            if let url = URL(string: urlString) {
                downloadFile(from: url) { result in
                    switch result {
                    case .success(let fileURL):
                        // 调用主线程来处理文件保存
                        Task {
                            await saveFileToDirectory(fileURL: fileURL, fileName: fileName)
                            await loadDownloadedFiles() // 下载完成后刷新文件列表
                        }
                    case .failure(let error):
                        print("文件下载失败: \(error.localizedDescription)")
                    }

                    // 更新已下载文件计数
                    DispatchQueue.main.async {
                        completedDownloads += 1
                        if completedDownloads == urls.count {
                            isDownloading = false // 当两个文件都下载完成时，解除禁用按钮
                        }
                    }
                }
            }
        }
    }

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

            do {
                let fileManager = FileManager.default
                let destinationURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("filename.dat")

                try fileManager.moveItem(at: localURL, to: destinationURL)
                print("文件已成功保存到 \(destinationURL.path)")
                completion(.success(destinationURL))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    @MainActor
    private func saveFileToDirectory(fileURL: URL, fileName: String) {
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: Constant.assetDirectory.path).appendingPathComponent(fileName)

        do {
            // 确保目标文件夹存在
            if !fileManager.fileExists(atPath: Constant.assetDirectory.path) {
                try fileManager.createDirectory(at: Constant.assetDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            // 检查临时文件是否存在
            guard fileManager.fileExists(atPath: fileURL.path) else {
                print("临时文件不存在: \(fileURL.path)")
                return
            }

            // 如果目标文件存在，删除旧文件
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // 移动临时文件到目标位置
            try fileManager.moveItem(at: fileURL, to: destinationURL)
            print("\(fileName) 文件已成功移动到 \(destinationURL.path)")
        } catch {
            print("文件保存失败: \(error.localizedDescription)")
        }
    }

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

            // 清空文件列表
            downloadedFiles.removeAll()

        } catch {
            print("操作失败: \(error.localizedDescription)")
        }
    }
}