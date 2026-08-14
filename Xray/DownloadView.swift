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

/// 下载、替换和清理 Xray 的 geoip/geosite 资源文件。
///
/// `Configuration` 的非全局路由和国内 DNS 规则依赖这些文件。视图会从固定发布地址顺序
/// 下载 `geoip.dat` 与 `geosite.dat`，保存到 App Group 的共享资源目录，并展示当前文件名。
/// 如果资源在 VPN 已连接时发生变化，会等待隧道重启，让 Xray 重新加载最新资源。
struct DownloadView: View {
    /// 下载流程是否正在执行；为 `true` 时禁用下载和清空按钮，避免并发修改目录。
    @State private var isDownloading: Bool = false

    /// 当前共享资源目录中的文件名，用于在界面确认已安装资源。
    @State private var downloadedFiles: [String] = []

    /// 提供资源更新、清理操作以及已下载文件列表。
    var body: some View {
        VStack {
            // 操作区：更新资源与清空资源互斥，下载期间同时禁用。
            HStack {
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

            // 目录为空时不显示占位行；存在文件时横向列出名称。
            if !downloadedFiles.isEmpty {
                HStack {
                    Text("已下载:")
                        .padding(.top)

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

    // MARK: - Asset Management

    /// 刷新共享资源目录中的文件名列表。
    ///
    /// 读取 `Constant.assetDirectory` 的直接子项并替换 `downloadedFiles`。读取失败不会清空
    /// 现有界面状态，也不会向外抛出，只记录文件系统错误供排查。
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

    /// 顺序更新 geoip 和 geosite 文件，并在需要时重启已连接的 VPN。
    ///
    /// 流程如下：
    /// 1. 将 `isDownloading` 设为 `true`，阻止重复操作；
    /// 2. 依次下载 geoip 与 geosite 到 URLSession 临时目录；
    /// 3. 将临时文件移动到共享资源目录并替换同名旧文件；
    /// 4. 每保存一个文件后刷新界面列表；
    /// 5. 全部完成后，如果 VPN 正在连接，则重启使新资源生效；
    /// 6. 无论成功或失败，最后恢复按钮可用状态。
    ///
    /// 下载或保存错误在本方法统一记录，不继续抛给 SwiftUI 按钮任务。
    @MainActor
    private func downloadAndUpdateGeoipDat() async {
        let urls = [
            ("https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat", "geoip.dat"),
            ("https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat", "geosite.dat"),
        ]

        isDownloading = true

        do {
            // 两个文件顺序处理，避免同时替换共享目录内容。
            for (urlString, fileName) in urls {
                guard let url = URL(string: urlString) else {
                    logger.error("无效的下载链接: \(urlString)")
                    continue
                }

                // URLSession 先把响应保存到系统管理的临时文件。
                let downloadedTempURL = try await downloadFile(from: url)

                // 移动到 Xray 共享资源目录，并刷新已下载列表。
                saveFileToDirectory(fileURL: downloadedTempURL, fileName: fileName)
                loadDownloadedFiles()
            }

            // 已运行的 Xray 不会自动重新加载 geo 文件，需要重启隧道。
            if PacketTunnelManager.shared.status == .connected {
                do {
                    try await PacketTunnelManager.shared.restart()
                    logger.info("VPN 已成功重启")
                } catch {
                    logger.error("VPN 重启失败：\(error.localizedDescription)")
                }
            } else {
                logger.info("VPN 未处于连接状态，跳过重启")
            }
        } catch {
            logger.error("文件下载或保存失败: \(error.localizedDescription)")
        }

        isDownloading = false
    }

    /// 下载文件到系统临时目录，并校验 HTTP 响应。
    ///
    /// - Parameter url: 资源文件的远程下载地址。
    /// - Returns: URLSession 创建的临时文件 URL；调用方必须在任务结束前移动该文件。
    /// - Throws: 网络下载失败，或响应不是 HTTP 200 时抛出错误。
    private func downloadFile(from url: URL) async throws -> URL {
        let (tempLocalURL, response) = try await URLSession.shared.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        return tempLocalURL
    }

    /// 将临时文件移动到共享资源目录，并替换同名旧文件。
    ///
    /// - Parameters:
    ///   - fileURL: URLSession 返回的临时文件位置。
    ///   - fileName: 目标文件名，例如 `geoip.dat` 或 `geosite.dat`。
    /// - Note: 方法会在目录缺失时创建目录；临时文件不存在或文件操作失败时记录日志并返回。
    @MainActor
    private func saveFileToDirectory(fileURL: URL, fileName: String) {
        let fileManager = FileManager.default
        let destinationURL = URL(fileURLWithPath: Constant.assetDirectory.path).appendingPathComponent(fileName)

        do {
            // 正常情况下 Constant 已创建目录；这里保留防御性检查，应对目录被外部删除。
            if !fileManager.fileExists(atPath: Constant.assetDirectory.path) {
                try fileManager.createDirectory(at: Constant.assetDirectory, withIntermediateDirectories: true)
            }

            guard fileManager.fileExists(atPath: fileURL.path) else {
                logger.error("临时文件不存在: \(fileURL.path)")
                return
            }

            // FileManager.moveItem 不覆盖已有文件，因此先删除旧版本。
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: fileURL, to: destinationURL)
            logger.info("\(fileName) 文件已成功移动到 \(destinationURL.path)")
        } catch {
            logger.error("文件保存失败: \(error.localizedDescription)")
        }
    }

    /// 清空并重建共享资源目录，必要时重启已连接的 VPN。
    ///
    /// 方法先删除整个资源目录，再以空目录重新创建，并同步清空界面文件列表。删除目录而不是
    /// 逐个删除文件，可确保未知的附加资源也被清理。若 VPN 已连接，则重启 Xray，让路由和
    /// DNS 构建回到不依赖 geo 文件的分支。
    ///
    /// 文件操作和 VPN 重启错误只写入日志，不继续抛给 SwiftUI 按钮任务。
    private func clearAssetDirectory() async {
        let fileManager = FileManager.default
        let assetDirectoryPath = Constant.assetDirectory.path

        do {
            // 删除全部旧资源后立即重建，保持 Constant.assetDirectory 始终可写。
            if fileManager.fileExists(atPath: assetDirectoryPath) {
                try fileManager.removeItem(atPath: assetDirectoryPath)
                logger.info("已删除文件夹: \(assetDirectoryPath)")
            }

            try fileManager.createDirectory(atPath: assetDirectoryPath, withIntermediateDirectories: true)
            logger.info("已重新创建文件夹: \(assetDirectoryPath)")

            downloadedFiles.removeAll()

            // 已运行实例需要重启才能释放旧资源并采用无 geo 文件的配置。
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
