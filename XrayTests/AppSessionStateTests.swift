//
//  AppSessionStateTests.swift
//  XrayTests
//
//  Created by pan on 2026/8/17.
//

import Foundation
import XCTest
@testable import Xray

final class AppSessionStateTests: XCTestCase {
    func testLoadPortRejectsMissingAndZeroValues() throws {
        let missingKey = "tests.missing-port.\(UUID().uuidString)"
        XCTAssertNil(AppGroupStore.loadPort(forKey: missingKey))

        let zeroKey = "tests.zero-port.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        )
        defaults.set(0, forKey: zeroKey)
        defer { defaults.removeObject(forKey: zeroKey) }

        XCTAssertNil(AppGroupStore.loadPort(forKey: zeroKey))
    }

    @MainActor
    func testPrepareLocalPortsAllocatesOnlyOnce() async {
        let expectedPorts = LocalServicePorts(socksPort: 31_080, metricsPort: 31_081)
        let allocator = LocalPortAllocatorStub(ports: expectedPorts)
        let state = AppSessionState(
            portAllocator: allocator,
            portStore: LocalPortStoreStub(storedPorts: nil)
        )

        let firstPreparation = Task { @MainActor in
            await state.prepareLocalPorts(using: .allocateNew)
        }
        let secondPreparation = Task { @MainActor in
            await state.prepareLocalPorts(using: .allocateNew)
        }
        await firstPreparation.value
        await secondPreparation.value
        await state.prepareLocalPorts(using: .allocateNew)

        XCTAssertTrue(state.areLocalPortsReady)
        XCTAssertEqual(state.localPorts, expectedPorts)
        XCTAssertEqual(state.socksPort.rawValue, expectedPorts.socksPort)
        XCTAssertEqual(state.metricsPort.rawValue, expectedPorts.metricsPort)

        let allocationCount = await allocator.allocationCount
        XCTAssertEqual(allocationCount, 1)
    }

    @MainActor
    func testPrepareLocalPortsReusesPersistedPortsWithoutAllocation() async {
        let persistedPorts = LocalServicePorts(socksPort: 31_090, metricsPort: 31_091)
        let allocator = LocalPortAllocatorStub(ports: .defaultValue)
        let state = AppSessionState(
            portAllocator: allocator,
            portStore: LocalPortStoreStub(storedPorts: persistedPorts)
        )

        await state.prepareLocalPorts(using: .reusePersisted)

        XCTAssertTrue(state.areLocalPortsReady)
        XCTAssertEqual(state.localPorts, persistedPorts)
        let allocationCount = await allocator.allocationCount
        XCTAssertEqual(allocationCount, 0)
    }

    @MainActor
    func testMissingPersistedPortsDoesNotAllocateWhileTunnelMayBeActive() async {
        let allocator = LocalPortAllocatorStub(ports: .defaultValue)
        let state = AppSessionState(
            portAllocator: allocator,
            portStore: LocalPortStoreStub(storedPorts: nil)
        )

        await state.prepareLocalPorts(using: .reusePersisted)

        XCTAssertFalse(state.areLocalPortsReady)
        let allocationCount = await allocator.allocationCount
        XCTAssertEqual(allocationCount, 0)
    }

    @MainActor
    func testPersistedZeroPortIsRejected() async {
        let invalidPorts = [
            LocalServicePorts(socksPort: 0, metricsPort: 31_101),
            LocalServicePorts(socksPort: 31_100, metricsPort: 0),
        ]

        for ports in invalidPorts {
            let allocator = LocalPortAllocatorStub(ports: .defaultValue)
            let state = AppSessionState(
                portAllocator: allocator,
                portStore: LocalPortStoreStub(storedPorts: ports)
            )

            await state.prepareLocalPorts(using: .reusePersisted)

            XCTAssertFalse(state.areLocalPortsReady, "应拒绝端口组合：\(ports)")
            let allocationCount = await allocator.allocationCount
            XCTAssertEqual(allocationCount, 0)
        }
    }

    @MainActor
    func testAllocatedZeroPortIsRejected() async {
        let state = AppSessionState(
            portAllocator: LocalPortAllocatorStub(
                ports: LocalServicePorts(socksPort: 0, metricsPort: 31_111)
            ),
            portStore: LocalPortStoreStub(storedPorts: nil)
        )

        await state.prepareLocalPorts(using: .allocateNew)

        XCTAssertFalse(state.areLocalPortsReady)
        XCTAssertEqual(state.localPorts, .defaultValue)
    }

    @MainActor
    func testDuplicateAllocatedPortsAreRejected() async {
        let state = AppSessionState(
            portAllocator: LocalPortAllocatorStub(
                ports: LocalServicePorts(socksPort: 31_120, metricsPort: 31_120)
            ),
            portStore: LocalPortStoreStub(storedPorts: nil)
        )

        await state.prepareLocalPorts(using: .allocateNew)

        XCTAssertFalse(state.areLocalPortsReady)
        XCTAssertEqual(state.localPortPreparationError, "本地服务端口无效")
    }

    @MainActor
    func testAllocationFailureDoesNotMarkPortsAsReady() async {
        let expectedError = LocalPortAllocatorStubError.unavailable
        let state = AppSessionState(
            portAllocator: LocalPortAllocatorStub(result: .failure(expectedError)),
            portStore: LocalPortStoreStub(storedPorts: nil)
        )

        await state.prepareLocalPorts(using: .allocateNew)

        XCTAssertFalse(state.areLocalPortsReady)
        XCTAssertEqual(state.localPortPreparationError, expectedError.localizedDescription)
    }
}

private struct LocalPortStoreStub: LocalPortStoring {
    let storedPorts: LocalServicePorts?

    func loadLocalPorts() -> LocalServicePorts? {
        storedPorts
    }

    func saveLocalPorts(_: LocalServicePorts) {}
}

private actor LocalPortAllocatorStub: LocalPortAllocating {
    private(set) var allocationCount = 0
    private let result: Result<LocalServicePorts, Error>

    init(ports: LocalServicePorts) {
        result = .success(ports)
    }

    init(result: Result<LocalServicePorts, Error>) {
        self.result = result
    }

    func allocateLocalPorts() async throws -> LocalServicePorts {
        allocationCount += 1
        try await Task.sleep(for: .milliseconds(10))
        return try result.get()
    }
}

private enum LocalPortAllocatorStubError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "无法分配本地端口"
    }
}
