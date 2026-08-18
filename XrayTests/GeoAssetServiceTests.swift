//
//  GeoAssetServiceTests.swift
//  XrayTests
//
//  Created by pan on 2026/8/17.
//

import Foundation
import XCTest
@testable import Xray

final class GeoAssetServiceTests: XCTestCase {
    func testSharedDirectoryFailureIsReportedWithoutCrashing() async {
        let expectedError = AppGroupDirectoryError.containerUnavailable(
            identifier: AppConstants.appGroupIdentifier
        )
        let service = GeoAssetService(assetDirectoryURLProvider: {
            throw expectedError
        })

        do {
            _ = try await service.installedFileNames()
            XCTFail("Expected an App Group directory error")
        } catch let error as AppGroupDirectoryError {
            XCTAssertEqual(error, expectedError)
            XCTAssertTrue(error.localizedDescription.contains("App Groups capability"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testXrayDirectoryFailureIsReportedWithoutCrashing() {
        XCTAssertThrowsError(
            try AppConstants.xrayDirectoryURL(containerURL: nil)
        ) { error in
            XCTAssertEqual(
                error as? AppGroupDirectoryError,
                .containerUnavailable(identifier: AppConstants.appGroupIdentifier)
            )
        }
    }

    func testInstallDownloadedFilesReplacesCompleteAssetSet() async throws {
        let fixture = try GeoAssetFixture()
        defer { fixture.remove() }
        let geoIPURL = fixture.assetDirectoryURL.appendingPathComponent("geoip.dat")
        let geoSiteURL = fixture.assetDirectoryURL.appendingPathComponent("geosite.dat")
        let downloadedGeoIPURL = fixture.rootURL.appendingPathComponent("downloaded-geoip.dat")
        let downloadedGeoSiteURL = fixture.rootURL.appendingPathComponent("downloaded-geosite.dat")
        try Data("old-geoip".utf8).write(to: geoIPURL)
        try Data("old-geosite".utf8).write(to: geoSiteURL)
        try Data("new-geoip".utf8).write(to: downloadedGeoIPURL)
        try Data("new-geosite".utf8).write(to: downloadedGeoSiteURL)
        let service = GeoAssetService(assetDirectoryURL: fixture.assetDirectoryURL)

        try await service.installDownloadedFiles([
            (downloadedGeoIPURL, "geoip.dat"),
            (downloadedGeoSiteURL, "geosite.dat"),
        ])

        XCTAssertEqual(try Data(contentsOf: geoIPURL), Data("new-geoip".utf8))
        XCTAssertEqual(try Data(contentsOf: geoSiteURL), Data("new-geosite".utf8))
        let installedFileNames = try await service.installedFileNames()
        XCTAssertEqual(installedFileNames, ["geoip.dat", "geosite.dat"])
    }

    func testInstalledAssetsIncludeFileSizesAndSkipHiddenFiles() async throws {
        let fixture = try GeoAssetFixture()
        defer { fixture.remove() }
        try Data(repeating: 1, count: 2_048).write(
            to: fixture.assetDirectoryURL.appendingPathComponent("geoip.dat")
        )
        try Data(repeating: 2, count: 4_096).write(
            to: fixture.assetDirectoryURL.appendingPathComponent("geosite.dat")
        )
        try Data("metadata".utf8).write(
            to: fixture.assetDirectoryURL.appendingPathComponent(".metadata")
        )
        let service = GeoAssetService(assetDirectoryURL: fixture.assetDirectoryURL)

        let installedAssets = try await service.installedAssets()

        XCTAssertEqual(
            installedAssets,
            [
                InstalledGeoAsset(fileName: "geoip.dat", byteCount: 2_048),
                InstalledGeoAsset(fileName: "geosite.dat", byteCount: 4_096),
            ]
        )
    }

    func testDownloadProgressMapsCurrentFileToOverallProgress() {
        let progress = GeoAssetDownloadProgress(
            fileName: "geosite.dat",
            fileNumber: 2,
            totalFileCount: 2,
            receivedByteCount: 25,
            expectedByteCount: 100,
            bytesPerSecond: 1_024,
            isFileComplete: false
        )

        XCTAssertEqual(progress.fileFractionCompleted, 0.25)
        XCTAssertEqual(progress.overallFractionCompleted, 0.625)
    }

    func testCompletedDownloadProgressReachesEndWithoutExpectedSize() {
        let progress = GeoAssetDownloadProgress(
            fileName: "geosite.dat",
            fileNumber: 2,
            totalFileCount: 2,
            receivedByteCount: 100,
            expectedByteCount: nil,
            bytesPerSecond: 1_024,
            isFileComplete: true
        )

        XCTAssertEqual(progress.fileFractionCompleted, 1)
        XCTAssertEqual(progress.overallFractionCompleted, 1)
    }

    func testInstallDownloadedFilesPreservesCompleteAssetSetWhenOneFileIsEmpty() async throws {
        let fixture = try GeoAssetFixture()
        defer { fixture.remove() }
        let geoIPURL = fixture.assetDirectoryURL.appendingPathComponent("geoip.dat")
        let geoSiteURL = fixture.assetDirectoryURL.appendingPathComponent("geosite.dat")
        let downloadedGeoIPURL = fixture.rootURL.appendingPathComponent("downloaded-geoip.dat")
        let emptyGeoSiteURL = fixture.rootURL.appendingPathComponent("empty-geosite.dat")
        let originalGeoIPData = Data("old-geoip".utf8)
        let originalGeoSiteData = Data("old-geosite".utf8)
        try originalGeoIPData.write(to: geoIPURL)
        try originalGeoSiteData.write(to: geoSiteURL)
        try Data("new-geoip".utf8).write(to: downloadedGeoIPURL)
        XCTAssertTrue(FileManager.default.createFile(atPath: emptyGeoSiteURL.path, contents: Data()))
        let service = GeoAssetService(assetDirectoryURL: fixture.assetDirectoryURL)

        do {
            try await service.installDownloadedFiles([
                (downloadedGeoIPURL, "geoip.dat"),
                (emptyGeoSiteURL, "geosite.dat"),
            ])
            XCTFail("Expected an emptyDownloadedFile error")
        } catch let error as GeoAssetServiceError {
            XCTAssertEqual(error, .emptyDownloadedFile)
        }

        XCTAssertEqual(try Data(contentsOf: geoIPURL), originalGeoIPData)
        XCTAssertEqual(try Data(contentsOf: geoSiteURL), originalGeoSiteData)
    }

    func testRemoveAllAssetsReplacesDirectoryWithEmptyDirectory() async throws {
        let fixture = try GeoAssetFixture()
        defer { fixture.remove() }
        try Data("geoip".utf8).write(
            to: fixture.assetDirectoryURL.appendingPathComponent("geoip.dat")
        )
        try Data("metadata".utf8).write(
            to: fixture.assetDirectoryURL.appendingPathComponent(".metadata")
        )
        let service = GeoAssetService(assetDirectoryURL: fixture.assetDirectoryURL)

        try await service.removeAllAssets()

        let remainingURLs = try FileManager.default.contentsOfDirectory(
            at: fixture.assetDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingURLs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.assetDirectoryURL.path))
    }
}

private struct GeoAssetFixture {
    let rootURL: URL
    let assetDirectoryURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeoAssetServiceTests-\(UUID().uuidString)", isDirectory: true)
        assetDirectoryURL = rootURL.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assetDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
