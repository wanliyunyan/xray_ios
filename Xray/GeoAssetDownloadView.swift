//
//  GeoAssetDownloadView.swift
//  Xray
//
//  Created by pan on 2024/10/17.
//

import Observation
import os
import SwiftUI

private let logger = Logger(subsystem: AppConstants.loggingSubsystem, category: "GeoAssetDownloadView")

/// 展示并管理 Xray 非全局模式使用的中国大陆分流资源。
struct GeoAssetDownloadView: View {
    @Environment(PacketTunnelManager.self) private var packetTunnelManager

    @State private var model = GeoAssetDownloadModel()
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ChinaGeoAssetOverview(
                    summary: model.installedSummary,
                    isReady: model.hasCompleteAssetSet
                )

                ChinaGeoAssetFileSection(assets: model.installedAssets)

                if model.operation != .idle {
                    GeoAssetOperationPanel(
                        operation: model.operation,
                        downloadProgress: model.downloadProgress
                    )
                }

                GeoAssetActionBar(
                    hasInstalledAssets: model.hasInstalledAssets,
                    isBusy: model.isBusy,
                    canCancelDownload: model.canCancelDownload,
                    onDownload: startDownload,
                    onDelete: presentDeleteConfirmation,
                    onCancel: model.cancelDownload
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("中国大陆分流资源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            await model.refreshInstalledAssets()
        }
        .onDisappear {
            model.cancelDownload()
        }
        .confirmationDialog(
            "删除中国大陆分流资源？",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除全部中国分流资源", role: .destructive) {
                model.startRemoval(using: packetTunnelManager)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，非全局模式将无法识别中国大陆 IP 与域名；更改会在下次连接或自动重连后生效。")
        }
        .alert("中国分流资源操作失败", isPresented: $model.isErrorPresented) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(model.errorMessage)
        }
    }

    private func startDownload() {
        model.startDownload(using: packetTunnelManager)
    }

    private func presentDeleteConfirmation() {
        isDeleteConfirmationPresented = true
    }
}

private enum GeoAssetOperation: Equatable {
    case idle
    case preparingDownload
    case downloading
    case restartingVPN
    case deleting
}

@MainActor
@Observable
private final class GeoAssetDownloadModel {
    private let geoAssetService: GeoAssetService

    @ObservationIgnored
    private var operationTask: Task<Void, Never>?

    private(set) var installedAssets: [InstalledGeoAsset] = []
    private(set) var operation: GeoAssetOperation = .idle
    private(set) var downloadProgress: GeoAssetDownloadProgress?
    private(set) var errorMessage = ""
    var isErrorPresented = false

    init(geoAssetService: GeoAssetService = .shared) {
        self.geoAssetService = geoAssetService
    }

    var hasInstalledAssets: Bool {
        !installedAssets.isEmpty
    }

    var hasCompleteAssetSet: Bool {
        Self.requiredFileNames.allSatisfy { requiredFileName in
            installedAssets.contains {
                $0.fileName == requiredFileName && $0.byteCount > 0
            }
        }
    }

    var installedSummary: String {
        guard hasInstalledAssets else {
            return "尚未下载"
        }
        let totalByteCount = installedAssets.reduce(Int64(0)) { $0 + $1.byteCount }
        guard hasCompleteAssetSet else {
            return "文件不完整 · \(installedRequiredAssetCount) / \(Self.requiredFileNames.count)"
        }
        return "已就绪 · \(formattedByteCount(totalByteCount))"
    }

    private var installedRequiredAssetCount: Int {
        Self.requiredFileNames.filter { requiredFileName in
            installedAssets.contains {
                $0.fileName == requiredFileName && $0.byteCount > 0
            }
        }.count
    }

    var isBusy: Bool {
        operation != .idle
    }

    var canCancelDownload: Bool {
        operation == .preparingDownload || operation == .downloading
    }

    func refreshInstalledAssets() async {
        do {
            installedAssets = try await geoAssetService.installedAssets()
        } catch {
            present(error)
        }
    }

    func startDownload(using packetTunnelManager: PacketTunnelManager) {
        guard !isBusy else {
            return
        }

        operation = .preparingDownload
        downloadProgress = nil
        operationTask = Task { @MainActor [weak self, weak packetTunnelManager] in
            guard let self, let packetTunnelManager else {
                return
            }
            await performDownload(using: packetTunnelManager)
        }
    }

    func cancelDownload() {
        guard canCancelDownload else {
            return
        }
        operationTask?.cancel()
    }

    func startRemoval(using packetTunnelManager: PacketTunnelManager) {
        guard !isBusy, hasInstalledAssets else {
            return
        }

        operation = .deleting
        operationTask = Task { @MainActor [weak self, weak packetTunnelManager] in
            guard let self, let packetTunnelManager else {
                return
            }
            await performRemoval(using: packetTunnelManager)
        }
    }

    private func performDownload(using packetTunnelManager: PacketTunnelManager) async {
        do {
            try await geoAssetService.updateAssets { [weak self] progress in
                await self?.receive(progress)
            }
            try Task.checkCancellation()

            installedAssets = try await geoAssetService.installedAssets()
            if packetTunnelManager.lifecycleState.isConnected {
                operation = .restartingVPN
                try await packetTunnelManager.restart()
            }

            operation = .idle
            downloadProgress = nil
        } catch {
            handleOperationError(error)
        }
        operationTask = nil
    }

    private func performRemoval(using packetTunnelManager: PacketTunnelManager) async {
        do {
            try await geoAssetService.removeAllAssets()
            installedAssets = try await geoAssetService.installedAssets()

            if packetTunnelManager.lifecycleState.isConnected {
                operation = .restartingVPN
                try await packetTunnelManager.restart()
            }

            operation = .idle
        } catch {
            handleOperationError(error)
        }
        operationTask = nil
    }

    private func receive(_ progress: GeoAssetDownloadProgress) {
        downloadProgress = progress
        operation = .downloading
    }

    private func handleOperationError(_ error: Error) {
        operation = .idle
        downloadProgress = nil

        if Task.isCancelled
            || error is CancellationError
            || (error as? URLError)?.code == .cancelled
        {
            return
        }
        present(error)
    }

    private func present(_ error: Error) {
        logger.error("中国大陆分流资源操作失败: \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }

    private static let requiredFileNames = ["geoip.dat", "geosite.dat"]
}

private struct ChinaGeoAssetOverview: View {
    let summary: String
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.tint, in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isReady ? "中国大陆分流已就绪" : "用于中国大陆智能分流")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: isReady ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(isReady ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
            }

            Text("这些文件供非全局模式识别中国大陆与私有网络流量，使其直接连接；其余流量继续通过 VPN，并拦截常见广告域名。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                isReady ? "连接时会自动使用这些规则" : "两个文件都下载完成后才会启用",
                systemImage: isReady ? "checkmark.shield" : "info.circle"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(isReady ? Color.green : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ChinaGeoAssetFileSection: View {
    let assets: [InstalledGeoAsset]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("中国分流文件")
                    .font(.headline)
                Text("分别提供 IP 地址和域名的匹配规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeoAssetFileList(assets: assets)
        }
    }
}

private struct GeoAssetFileList: View {
    let assets: [InstalledGeoAsset]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(GeoAssetDescriptor.required) { descriptor in
                GeoAssetFileRow(
                    descriptor: descriptor,
                    asset: assets.first { $0.fileName == descriptor.fileName }
                )
            }
        }
    }
}

private struct GeoAssetDescriptor: Identifiable {
    let fileName: String
    let description: String

    var id: String { fileName }

    static let required = [
        GeoAssetDescriptor(
            fileName: "geoip.dat",
            description: "中国大陆与私有 IP 地址规则"
        ),
        GeoAssetDescriptor(
            fileName: "geosite.dat",
            description: "中国大陆、私有与广告域名规则"
        ),
    ]
}

private struct GeoAssetFileRow: View {
    let descriptor: GeoAssetDescriptor
    let asset: InstalledGeoAsset?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                fileIdentity
                Spacer(minLength: 12)
                installationStatus
            }

            VStack(alignment: .leading, spacing: 10) {
                fileIdentity
                installationStatus
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var fileIdentity: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 6))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.fileName)
                    .font(.subheadline.monospaced().weight(.semibold))
                Text(descriptor.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let asset {
                    Text(formattedByteCount(asset.byteCount))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var installationStatus: some View {
        Label(
            asset == nil ? "未下载" : "已安装",
            systemImage: asset == nil ? "circle" : "checkmark.circle.fill"
        )
            .font(.caption.weight(.semibold))
            .foregroundStyle(asset == nil ? Color.secondary : Color.green)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct GeoAssetOperationPanel: View {
    let operation: GeoAssetOperation
    let downloadProgress: GeoAssetDownloadProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch operation {
            case .downloading:
                if let downloadProgress {
                    downloadContent(downloadProgress)
                }
            case .preparingDownload:
                indeterminateContent(
                    title: "正在连接中国分流资源下载源",
                    systemImage: "network"
                )
            case .restartingVPN:
                indeterminateContent(
                    title: "正在重新加载 VPN",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            case .deleting:
                indeterminateContent(
                    title: "正在删除中国分流资源",
                    systemImage: "trash"
                )
            case .idle:
                EmptyView()
            }
        }
        .padding(12)
        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func downloadContent(_ progress: GeoAssetDownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.fileName)
                        .font(.subheadline.monospaced().weight(.semibold))
                    Text("第 \(progress.fileNumber) / \(progress.totalFileCount) 个文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if let fraction = progress.overallFractionCompleted {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
            }

            if let fraction = progress.overallFractionCompleted {
                ProgressView(value: fraction)
                    .tint(.accentColor)
                    .animation(.linear(duration: 0.15), value: fraction)
                    .accessibilityLabel("中国分流文件下载进度")
                    .accessibilityValue(Text(fraction, format: .percent))
            } else {
                ProgressView()
                    .tint(.accentColor)
                    .accessibilityLabel("正在下载中国分流文件")
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(downloadedByteSummary(progress))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                let speed = formattedDownloadSpeed(progress.bytesPerSecond)
                Text(speed)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tint)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("下载速度")
                    .accessibilityValue(speed)
            }
        }
    }

    private func indeterminateContent(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func downloadedByteSummary(_ progress: GeoAssetDownloadProgress) -> String {
        let received = formattedByteCount(progress.receivedByteCount)
        guard let expectedByteCount = progress.expectedByteCount, expectedByteCount > 0 else {
            return received
        }
        return "\(received) / \(formattedByteCount(expectedByteCount))"
    }
}

private struct GeoAssetActionBar: View {
    let hasInstalledAssets: Bool
    let isBusy: Bool
    let canCancelDownload: Bool
    let onDownload: @MainActor () -> Void
    let onDelete: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    var body: some View {
        if canCancelDownload {
            Button(action: onCancel) {
                Label("取消下载", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)
        } else if !isBusy {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    actions
                }

                VStack(spacing: 10) {
                    actions
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: onDownload) {
            Label(
                hasInstalledAssets ? "更新文件" : "下载文件",
                systemImage: "arrow.down.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.accentColor)

        Button(role: .destructive, action: onDelete) {
            Label("删除文件", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!hasInstalledAssets)
    }
}

private func formattedByteCount(_ byteCount: Int64) -> String {
    byteCount.formatted(.byteCount(style: .file))
}

private func formattedDownloadSpeed(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond >= 1 else {
        return "计算中"
    }
    return "\(formattedByteCount(Int64(bytesPerSecond)))/s"
}
