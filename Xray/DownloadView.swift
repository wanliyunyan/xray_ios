//
//  DownloadView.swift
//  Xray
//
//  Created by pan on 2024/10/17.
//

import os
import SwiftUI

// MARK: - Logger

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DownloadView")

/**
 下载并管理地理数据库文件的视图

 - 显示并管理地理数据库（geoip、geosite）文件的下载和清理
 - 下载完成后可自动重启 VPN（若当前已连接）
 */
struct DownloadView: View {
    /// 是否正在下载，控制按钮的禁用状态
    @State private var isDownloading: Bool = false

    /// 已下载的文件列表
    @State private var downloadedFiles: [String] = []

    // MARK: - 界面布局

    var body: some View {
        VStack {
            // 按钮
            HStack {
                // 下载/更新按钮
                Button(action: {
                    Task {
                        await downloadAndUpdateGeoipDat()
                    }
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

                // 清空文件按钮
                Button(action: {
                    Task {
                        await clearAssetDirectory()
                    }
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
                HStack {
                    Text("已下载:")
                        .padding(.top)

                    // 水平展示多个文件名
                    ForEach(downloadedFiles, id: \.self) { file in
                        Text(file)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, 10)
                    }
                }
            }
        }
        .onAppear {
            loadDownloadedFiles()
        }
    }

    // MARK: - 加载已下载文件列表

    /**
     从应用内的 `Constant.assetDirectory` 路径中，获取当前所有下载后的地理数据库文件名，并更新到 `downloadedFiles`.

     - Note: 如果读取失败会在控制台打印错误信息，但不会抛出异常。
     */
    private func loadDownloadedFiles() {
        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        do {
            let files = try fileManager.contentsOfDirectory(atPath: assetDirectoryPath)
            downloadedFiles = files
        } catch {
            logger.error("加载文件失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 使用 async/await 顺序下载并更新 geoip.dat & geosite.dat

    /**
     顺序下载两个地理数据库文件（geoip.dat, geosite.dat），并在下载完成后根据 VPN 状态决定是否重启。

     - Important: 此方法会将 `isDownloading` 置为 `true` 并在结束时还原为 `false`，以便界面更新下载按钮的可用状态。
     - Note: 若当前 VPN 已连接，则下载完成后会调用 `PacketTunnelManager.shared.restart()` 进行重启。
     */
    @MainActor
    private func downloadAndUpdateGeoipDat() async {
        let urls = [
            ("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat", "geoip.dat"),
            ("https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat", "geosite.dat"),
        ]

        isDownloading = true // 禁用按钮，避免重复点击

        do {
            // 逐一下载文件（顺序执行）
            for (urlString, fileName) in urls {
                guard let url = URL(string: urlString) else {
                    logger.error("无效的下载链接: \(urlString)")
                    continue
                }

                // 1) 下载到临时目录
                let downloadedTempURL = try await downloadFile(from: url)

                // 2) 将临时文件移动到指定位置并改名
                saveFileToDirectory(fileURL: downloadedTempURL, fileName: fileName)

                // 3) 刷新文件列表
                loadDownloadedFiles()
            }

            // 下载全部完成后，检查 VPN 状态，决定是否重启
            if PacketTunnelManager.shared.status == .connected {
                do {
                    try await PacketTunnelManager.shared.restart()
                    logger.info("VPN 已成功重启")
                } catch {
                    logger.error("VPN 重启失败：\(error.localizedDescription)")
                }
            } else {
                logger.error("VPN 未处于连接状态，跳过重启")
            }
        } catch {
            logger.error("文件下载或保存失败: \(error.localizedDescription)")
        }

        // 恢复按钮可点击
        isDownloading = false
    }

    // MARK: - 利用 URLSession 的异步下载

    /**
     从远程地址下载文件到本地临时目录，返回临时文件的本地 URL。

     - Parameter url: 文件下载链接
     - Throws: 若网络响应非 200 或下载中遇到网络错误，会抛出 `URLError`
     - Returns: 下载成功后，位于本地临时目录的临时文件 `URL`
     */
    private func downloadFile(from url: URL) async throws -> URL {
        // 使用 async/await 的 download(from:) API
        let (tempLocalURL, response) = try await URLSession.shared.download(from: url)

        // 检查 HTTP 响应码
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        // tempLocalURL 指向临时文件位置
        return tempLocalURL
    }

    // MARK: - 移动下载后的临时文件到自定义目录

    /**
     将临时文件移动到 `Constant.assetDirectory` 指定的文件夹中，并改名为 `fileName`。

     - Parameter fileURL: 下载所得的临时文件路径
     - Parameter fileName: 目标文件名
     - Note: 若目标位置已存在同名文件，会先删除旧文件后再进行替换。
     */
    @MainActor
    private func saveFileToDirectory(fileURL: URL, fileName: String) {
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: Constant.assetDirectory.path).appendingPathComponent(fileName)

        do {
            // 如果文件夹不存在就创建
            if !fileManager.fileExists(atPath: Constant.assetDirectory.path) {
                try fileManager.createDirectory(at: Constant.assetDirectory, withIntermediateDirectories: true)
            }

            // 检查临时文件是否确实存在
            guard fileManager.fileExists(atPath: fileURL.path) else {
                logger.error("临时文件不存在: \(fileURL.path)")
                return
            }

            // 如果目标位置已有同名文件，先删除旧文件
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // 将临时文件移动到目标路径
            try fileManager.moveItem(at: fileURL, to: destinationURL)
            logger.info("\(fileName) 文件已成功移动到 \(destinationURL.path)")
        } catch {
            logger.error("文件保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 清空地理文件夹

    /**
     清空 `Constant.assetDirectory` 文件夹，并在完成后根据 VPN 状态决定是否重启。

     - Important: 会先删除整个文件夹，再新建一个空文件夹，最后刷新 `downloadedFiles` 列表。
     - Note: 若当前 VPN 已连接，则清空后会尝试重启 VPN。
     */
    private func clearAssetDirectory() async {
        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        do {
            // 删除整个文件夹
            if fileManager.fileExists(atPath: assetDirectoryPath) {
                try fileManager.removeItem(atPath: assetDirectoryPath)
                logger.info("已删除文件夹: \(assetDirectoryPath)")
            }

            // 重新创建文件夹
            try fileManager.createDirectory(atPath: assetDirectoryPath, withIntermediateDirectories: true)
            logger.info("已重新创建文件夹: \(assetDirectoryPath)")

            // 清空文件列表
            downloadedFiles.removeAll()

            // 清空完成后，检查 VPN 状态，决定是否重启
            if PacketTunnelManager.shared.status == .connected {
                do {
                    try await PacketTunnelManager.shared.restart()
                    logger.info("VPN 已成功重启")
                } catch {
                    logger.error("VPN 重启失败：\(error.localizedDescription)")
                }
            } else {
                logger.error("VPN 未处于连接状态，跳过重启")
            }
        } catch {
            logger.error("操作失败: \(error.localizedDescription)")
        }
    }
}
