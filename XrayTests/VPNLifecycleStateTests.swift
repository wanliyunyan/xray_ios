//
//  VPNLifecycleStateTests.swift
//  XrayTests
//
//  Created by pan on 2026/8/17.
//

import NetworkExtension
import XCTest
@testable import Xray

final class VPNLifecycleStateTests: XCTestCase {
    func testSystemStatusMapping() {
        XCTAssertEqual(VPNLifecycleState(systemStatus: nil), .loading)
        XCTAssertEqual(VPNLifecycleState(systemStatus: .invalid), .invalid)
        XCTAssertEqual(VPNLifecycleState(systemStatus: .disconnected), .disconnected)
        XCTAssertEqual(VPNLifecycleState(systemStatus: .connecting), .connecting)
        XCTAssertEqual(VPNLifecycleState(systemStatus: .connected), .connected)
        XCTAssertEqual(VPNLifecycleState(systemStatus: .reasserting), .reasserting)
        XCTAssertEqual(VPNLifecycleState(systemStatus: .disconnecting), .disconnecting)
    }

    func testStopWaitingStates() {
        XCTAssertTrue(VPNLifecycleState.connected.shouldWaitForStop)
        XCTAssertTrue(VPNLifecycleState.connecting.shouldWaitForStop)
        XCTAssertTrue(VPNLifecycleState.reasserting.shouldWaitForStop)
        XCTAssertTrue(VPNLifecycleState.disconnecting.shouldWaitForStop)
        XCTAssertFalse(VPNLifecycleState.disconnected.shouldWaitForStop)
        XCTAssertFalse(VPNLifecycleState.failed("failure").shouldWaitForStop)
    }

    func testConfigurationChangesAreDeferredWhileConnectionUsesSnapshot() {
        XCTAssertTrue(VPNLifecycleState.connecting.shouldDeferConfigurationChanges)
        XCTAssertTrue(VPNLifecycleState.connected.shouldDeferConfigurationChanges)
        XCTAssertTrue(VPNLifecycleState.reasserting.shouldDeferConfigurationChanges)
        XCTAssertTrue(VPNLifecycleState.disconnecting.shouldDeferConfigurationChanges)
        XCTAssertFalse(VPNLifecycleState.loading.shouldDeferConfigurationChanges)
        XCTAssertFalse(VPNLifecycleState.invalid.shouldDeferConfigurationChanges)
        XCTAssertFalse(VPNLifecycleState.disconnected.shouldDeferConfigurationChanges)
        XCTAssertFalse(VPNLifecycleState.failed("failure").shouldDeferConfigurationChanges)
    }

    func testPortPreparationStrategyPreservesPortsForPotentiallyActiveTunnel() {
        XCTAssertNil(VPNLifecycleState.loading.localPortPreparationStrategy)
        XCTAssertEqual(VPNLifecycleState.disconnected.localPortPreparationStrategy, .allocateNew)
        XCTAssertEqual(VPNLifecycleState.connected.localPortPreparationStrategy, .reusePersisted)
        XCTAssertEqual(VPNLifecycleState.connecting.localPortPreparationStrategy, .reusePersisted)
        XCTAssertEqual(VPNLifecycleState.reasserting.localPortPreparationStrategy, .reusePersisted)
        XCTAssertEqual(VPNLifecycleState.disconnecting.localPortPreparationStrategy, .reusePersisted)
        XCTAssertEqual(VPNLifecycleState.failed("failure").localPortPreparationStrategy, .reusePersisted)
    }

    func testStartGateKeepsConnectingStateUntilSystemAcknowledgesStart() throws {
        var gate = VPNStartGate()

        try gate.begin(from: .disconnected)

        XCTAssertTrue(gate.isPending)
        XCTAssertEqual(gate.reconcile(with: .disconnected), .connecting)
        XCTAssertEqual(gate.reconcile(with: .invalid), .connecting)
        XCTAssertThrowsError(try gate.begin(from: .connecting))
        XCTAssertEqual(gate.reconcile(with: .connecting), .connecting)
        XCTAssertFalse(gate.isPending)
    }

    func testStartGateCanBeCancelledWhenSystemDoesNotAcknowledgeStart() throws {
        var gate = VPNStartGate()
        try gate.begin(from: .disconnected)

        gate.cancel()

        XCTAssertFalse(gate.isPending)
        XCTAssertEqual(gate.reconcile(with: .disconnected), .disconnected)
    }
}
