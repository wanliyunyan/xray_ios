//
//  GeoAssetService.swift
//  Xray
//
//  Created by pan on 2026/8/17.
//

import Foundation

enum GeoAssetServiceError: LocalizedError, Equatable {
    case invalidDownloadURL(String)
    case invalidHTTPStatus(Int)
    case invalidContentType(String?)
    case missingDownloadedFile
    case emptyDownloadedFile
    case downloadedFileTooSmall(Int)

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL(let value):
            "无效的 geo 资源地址：\(value)"
        case .invalidHTTPStatus(let statusCode):
            "geo 资源下载失败，HTTP 状态码：\(statusCode)"
        case .invalidContentType(let contentType):
            "geo 资源返回了无效的内容类型：\(contentType ?? "未知")"
        case .missingDownloadedFile:
            "下载的 geo 临时文件不存在"
        case .emptyDownloadedFile:
            "下载的 geo 文件为空，已保留原文件"
        case .downloadedFileTooSmall(let byteCount):
            "下载的 geo 文件异常（仅 \(byteCount) 字节），已保留原文件"
        }
    }
}

struct InstalledGeoAsset: Identifiable, Equatable, Sendable {
    let fileName: String
    let byteCount: Int64

    var id: String { fileName }
}

struct GeoAssetDownloadProgress: Equatable, Sendable {
    let fileName: String
    let fileNumber: Int
    let totalFileCount: Int
    let receivedByteCount: Int64
    let expectedByteCount: Int64?
    let bytesPerSecond: Double
    let isFileComplete: Bool

    var fileFractionCompleted: Double? {
        if isFileComplete {
            return 1
        }
        guard let expectedByteCount, expectedByteCount > 0 else {
            return nil
        }
        return min(max(Double(receivedByteCount) / Double(expectedByteCount), 0), 1)
    }

    var overallFractionCompleted: Double? {
        guard totalFileCount > 0, let fileFractionCompleted else {
            return nil
        }
        let completedFileCount = max(fileNumber - 1, 0)
        return min(
            (Double(completedFileCount) + fileFractionCompleted) / Double(totalFileCount),
            1
        )
    }
}

/// 下载并原子安装 Xray geoip/geosite 资源。
actor GeoAssetService {
    static let shared = GeoAssetService()

    private let assetDirectoryURLProvider: @Sendable () throws -> URL
    private var resolvedAssetDirectoryURL: URL?
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        assetDirectoryURLProvider: @escaping @Sendable () throws -> URL = {
            try AppConstants.assetDirectoryURL()
        }
    ) {
        self.assetDirectoryURLProvider = assetDirectoryURLProvider
        self.fileManager = fileManager
    }

    init(
        assetDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        assetDirectoryURLProvider = { assetDirectoryURL }
        self.fileManager = fileManager
    }

    func installedFileNames() throws -> [String] {
        try installedAssets().map(\.fileName)
    }

    func installedAssets() throws -> [InstalledGeoAsset] {
        let assetDirectoryURL = try ensureAssetDirectoryExists()
        let assetURLs = try fileManager.contentsOfDirectory(
            at: assetDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return try assetURLs.compactMap { assetURL in
            let values = try assetURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                return nil
            }
            return InstalledGeoAsset(
                fileName: assetURL.lastPathComponent,
                byteCount: Int64(values.fileSize ?? 0)
            )
        }
        .sorted { $0.fileName < $1.fileName }
    }

    func updateAssets(
        progressHandler: (@Sendable (GeoAssetDownloadProgress) async -> Void)? = nil
    ) async throws {
        let stagingDirectoryURL = try makeStagingAssetDirectory()
        defer { try? fileManager.removeItem(at: stagingDirectoryURL) }

        for (sourceIndex, source) in Self.downloadSources.enumerated() {
            let temporaryFileURL = try await download(
                source,
                fileNumber: sourceIndex + 1,
                progressHandler: progressHandler
            )
            defer { try? fileManager.removeItem(at: temporaryFileURL) }

            try stageDownloadedFile(
                from: temporaryFileURL,
                as: source.destinationFileName,
                in: stagingDirectoryURL,
                minimumByteCount: 1_024
            )
        }

        try Task.checkCancellation()
        try commitStagingAssetDirectory(stagingDirectoryURL)
    }

    private func download(
        _ source: GeoAssetDownloadSource,
        fileNumber: Int,
        progressHandler: (@Sendable (GeoAssetDownloadProgress) async -> Void)?
    ) async throws -> URL {
        guard let remoteURL = URL(string: source.remoteURLString) else {
            throw GeoAssetServiceError.invalidDownloadURL(source.remoteURLString)
        }

        let totalFileCount = Self.downloadSources.count
        await progressHandler?(
            GeoAssetDownloadProgress(
                fileName: source.destinationFileName,
                fileNumber: fileNumber,
                totalFileCount: totalFileCount,
                receivedByteCount: 0,
                expectedByteCount: nil,
                bytesPerSecond: 0,
                isFileComplete: false
            )
        )

        let clock = ContinuousClock()
        var lastReportInstant = clock.now
        var lastReportedByteCount: Int64 = 0
        var latestReceivedByteCount: Int64 = 0
        var latestExpectedByteCount: Int64?
        var smoothedBytesPerSecond = 0.0
        var downloadedFileURL: URL?
        var downloadResponse: GeoAssetDownloadResponse?

        let events = GeoAssetProgressDownloader.events(for: remoteURL)
        for try await event in events {
            try Task.checkCancellation()

            switch event {
            case .progress(let receivedByteCount, let expectedByteCount):
                latestReceivedByteCount = receivedByteCount
                latestExpectedByteCount = expectedByteCount

                let now = clock.now
                let elapsed = lastReportInstant.duration(to: now)
                let hasCompletedFile = expectedByteCount.map { receivedByteCount >= $0 } ?? false
                guard elapsed >= .milliseconds(125) || hasCompletedFile else {
                    continue
                }

                let elapsedSeconds = elapsed.secondsValue
                if elapsedSeconds > 0 {
                    let currentSpeed = Double(receivedByteCount - lastReportedByteCount) / elapsedSeconds
                    smoothedBytesPerSecond = smoothedBytesPerSecond == 0
                        ? currentSpeed
                        : (smoothedBytesPerSecond * 0.7) + (currentSpeed * 0.3)
                }
                lastReportInstant = now
                lastReportedByteCount = receivedByteCount

                await progressHandler?(
                    GeoAssetDownloadProgress(
                        fileName: source.destinationFileName,
                        fileNumber: fileNumber,
                        totalFileCount: totalFileCount,
                        receivedByteCount: receivedByteCount,
                        expectedByteCount: expectedByteCount,
                        bytesPerSecond: max(smoothedBytesPerSecond, 0),
                        isFileComplete: false
                    )
                )

            case .finished(let temporaryFileURL, let response):
                downloadedFileURL = temporaryFileURL
                downloadResponse = response
            }
        }

        guard let downloadedFileURL, let downloadResponse else {
            throw GeoAssetServiceError.missingDownloadedFile
        }
        var shouldPreserveDownloadedFile = false
        defer {
            if !shouldPreserveDownloadedFile {
                try? fileManager.removeItem(at: downloadedFileURL)
            }
        }

        guard let statusCode = downloadResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(statusCode) else {
            throw GeoAssetServiceError.invalidHTTPStatus(statusCode)
        }
        if let contentType = downloadResponse.mimeType?.lowercased(),
               contentType == "text/html" || contentType == "text/plain"
        {
            throw GeoAssetServiceError.invalidContentType(downloadResponse.mimeType)
        }

        await progressHandler?(
            GeoAssetDownloadProgress(
                fileName: source.destinationFileName,
                fileNumber: fileNumber,
                totalFileCount: totalFileCount,
                receivedByteCount: latestReceivedByteCount,
                expectedByteCount: latestExpectedByteCount ?? latestReceivedByteCount,
                bytesPerSecond: max(smoothedBytesPerSecond, 0),
                isFileComplete: true
            )
        )
        shouldPreserveDownloadedFile = true
        return downloadedFileURL
    }

    /// 以完整目录事务安装一个已下载文件，失败时保留当前资源目录。
    func installDownloadedFile(from temporaryFileURL: URL, as destinationFileName: String) throws {
        try installDownloadedFiles([(temporaryFileURL, destinationFileName)])
    }

    /// 在目录副本中准备全部文件，再一次性替换当前资源目录。
    func installDownloadedFiles(_ downloadedFiles: [(URL, String)]) throws {
        for (temporaryFileURL, _) in downloadedFiles {
            try validateDownloadedFile(at: temporaryFileURL)
        }

        let stagingDirectoryURL = try makeStagingAssetDirectory()
        defer { try? fileManager.removeItem(at: stagingDirectoryURL) }

        for (temporaryFileURL, destinationFileName) in downloadedFiles {
            try stageDownloadedFile(
                from: temporaryFileURL,
                as: destinationFileName,
                in: stagingDirectoryURL
            )
        }

        try commitStagingAssetDirectory(stagingDirectoryURL)
    }

    private func validateDownloadedFile(
        at temporaryFileURL: URL,
        minimumByteCount: Int = 1
    ) throws {
        guard fileManager.fileExists(atPath: temporaryFileURL.path) else {
            throw GeoAssetServiceError.missingDownloadedFile
        }

        let resourceValues = try temporaryFileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = resourceValues.fileSize, fileSize > 0 else {
            throw GeoAssetServiceError.emptyDownloadedFile
        }
        guard fileSize >= minimumByteCount else {
            throw GeoAssetServiceError.downloadedFileTooSmall(fileSize)
        }
    }

    private func makeStagingAssetDirectory() throws -> URL {
        let assetDirectoryURL = try ensureAssetDirectoryExists()
        let stagingDirectoryURL = assetDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(assetDirectoryURL.lastPathComponent).\(UUID().uuidString).update",
                isDirectory: true
            )
        try fileManager.copyItem(at: assetDirectoryURL, to: stagingDirectoryURL)
        return stagingDirectoryURL
    }

    private func stageDownloadedFile(
        from temporaryFileURL: URL,
        as destinationFileName: String,
        in stagingDirectoryURL: URL,
        minimumByteCount: Int = 1
    ) throws {
        try validateDownloadedFile(at: temporaryFileURL, minimumByteCount: minimumByteCount)
        let stagedFileURL = stagingDirectoryURL.appendingPathComponent(destinationFileName)
        if fileManager.fileExists(atPath: stagedFileURL.path) {
            try fileManager.removeItem(at: stagedFileURL)
        }
        try fileManager.copyItem(at: temporaryFileURL, to: stagedFileURL)
    }

    private func commitStagingAssetDirectory(_ stagingDirectoryURL: URL) throws {
        let assetDirectoryURL = try assetDirectoryURL()
        _ = try fileManager.replaceItemAt(
            assetDirectoryURL,
            withItemAt: stagingDirectoryURL,
            backupItemName: nil,
            options: []
        )
    }

    func removeAllAssets() throws {
        let stagingDirectoryURL = try makeStagingAssetDirectory()
        defer { try? fileManager.removeItem(at: stagingDirectoryURL) }

        let stagedAssetURLs = try fileManager.contentsOfDirectory(
            at: stagingDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for stagedAssetURL in stagedAssetURLs {
            try fileManager.removeItem(at: stagedAssetURL)
        }

        try commitStagingAssetDirectory(stagingDirectoryURL)
    }

    private func ensureAssetDirectoryExists() throws -> URL {
        let assetDirectoryURL = try assetDirectoryURL()
        guard !fileManager.fileExists(atPath: assetDirectoryURL.path) else {
            return assetDirectoryURL
        }
        try fileManager.createDirectory(
            at: assetDirectoryURL,
            withIntermediateDirectories: true
        )
        return assetDirectoryURL
    }

    private func assetDirectoryURL() throws -> URL {
        if let resolvedAssetDirectoryURL {
            return resolvedAssetDirectoryURL
        }

        let assetDirectoryURL = try assetDirectoryURLProvider()
        resolvedAssetDirectoryURL = assetDirectoryURL
        return assetDirectoryURL
    }

    private static let downloadSources = [
        GeoAssetDownloadSource(
            remoteURLString: "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat",
            destinationFileName: "geoip.dat"
        ),
        GeoAssetDownloadSource(
            remoteURLString: "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat",
            destinationFileName: "geosite.dat"
        ),
    ]
}

private struct GeoAssetDownloadSource: Sendable {
    let remoteURLString: String
    let destinationFileName: String
}

private struct GeoAssetDownloadResponse: Sendable {
    let statusCode: Int?
    let mimeType: String?
}

private enum GeoAssetDownloadEvent: Sendable {
    case progress(receivedByteCount: Int64, expectedByteCount: Int64?)
    case finished(temporaryFileURL: URL, response: GeoAssetDownloadResponse)
}

private enum GeoAssetProgressDownloader {
    static func events(for remoteURL: URL) -> AsyncThrowingStream<GeoAssetDownloadEvent, Error> {
        let coordinator = GeoAssetDownloadCoordinator()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable [weak coordinator] termination in
                guard case .cancelled = termination else {
                    return
                }
                coordinator?.cancel()
            }
            coordinator.start(remoteURL: remoteURL, continuation: continuation)
        }
    }
}

private final class GeoAssetDownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let ownedTemporaryFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("GeoAssetDownload-\(UUID().uuidString).dat")

    private var continuation: AsyncThrowingStream<GeoAssetDownloadEvent, Error>.Continuation?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var downloadedFileURL: URL?
    private var terminalError: Error?

    func start(
        remoteURL: URL,
        continuation: AsyncThrowingStream<GeoAssetDownloadEvent, Error>.Continuation
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        let task = session.downloadTask(with: remoteURL)

        lock.lock()
        self.continuation = continuation
        self.session = session
        self.task = task
        lock.unlock()

        task.resume()
    }

    func cancel() {
        lock.lock()
        let continuation = self.continuation
        let session = self.session
        let task = self.task
        self.continuation = nil
        self.session = nil
        self.task = nil
        lock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.finish(throwing: CancellationError())
        try? fileManager.removeItem(at: ownedTemporaryFileURL)
    }

    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expectedByteCount = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : nil

        lock.lock()
        let continuation = self.continuation
        lock.unlock()

        continuation?.yield(
            .progress(
                receivedByteCount: totalBytesWritten,
                expectedByteCount: expectedByteCount
            )
        )
    }

    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? fileManager.removeItem(at: ownedTemporaryFileURL)
            try fileManager.moveItem(at: location, to: ownedTemporaryFileURL)

            lock.lock()
            downloadedFileURL = ownedTemporaryFileURL
            lock.unlock()
        } catch {
            lock.lock()
            terminalError = error
            lock.unlock()
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let continuation = self.continuation
        let downloadedFileURL = self.downloadedFileURL
        let terminalError = self.terminalError
        self.continuation = nil
        self.session = nil
        self.task = nil
        lock.unlock()

        if let terminalError {
            continuation?.finish(throwing: terminalError)
            try? fileManager.removeItem(at: ownedTemporaryFileURL)
        } else if let error {
            continuation?.finish(throwing: error)
            try? fileManager.removeItem(at: ownedTemporaryFileURL)
        } else if let downloadedFileURL {
            let httpResponse = task.response as? HTTPURLResponse
            continuation?.yield(
                .finished(
                    temporaryFileURL: downloadedFileURL,
                    response: GeoAssetDownloadResponse(
                        statusCode: httpResponse?.statusCode,
                        mimeType: httpResponse?.mimeType
                    )
                )
            )
            continuation?.finish()
        } else {
            continuation?.finish(throwing: GeoAssetServiceError.missingDownloadedFile)
        }

        session.finishTasksAndInvalidate()
    }
}

private extension Duration {
    var secondsValue: Double {
        let components = self.components
        return Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
