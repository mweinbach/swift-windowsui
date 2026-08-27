import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Query lifecycle and accounting are deterministic without a native device.
/// The fake keeps S_FALSE pending until a later explicit test update.
@MainActor
final class D3D11GPUFrameTimingCollectorTests: XCTestCase {
    func testAdapterSnapshotUsesOnlyTheIssuingGenerationWithoutFillingUnknownMetadata() async {
        let issuingID = BackendFrameID(deviceGeneration: 12, frameNumber: 7)
        let replacementID = BackendFrameID(deviceGeneration: 13, frameNumber: 7)
        XCTAssertEqual(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: issuingID.deviceGeneration, cachedGeneration: 12, cachedIsSoftware: false),
            false)
        XCTAssertEqual(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: issuingID.deviceGeneration, cachedGeneration: 12, cachedIsSoftware: true),
            true)
        XCTAssertNil(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: issuingID.deviceGeneration, cachedGeneration: 12, cachedIsSoftware: nil))
        XCTAssertNil(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: replacementID.deviceGeneration, cachedGeneration: 12, cachedIsSoftware: false),
            "Reusing a frame number on a new device cannot inherit the old adapter's classification")
        XCTAssertNil(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: issuingID.deviceGeneration, cachedGeneration: nil, cachedIsSoftware: false))
        XCTAssertNil(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: 0, cachedGeneration: 0, cachedIsSoftware: false))
        XCTAssertEqual(
            D3D11BatchRenderer.cachedAdapterIsSoftware(
                forDeviceGeneration: replacementID.deviceGeneration, cachedGeneration: 13, cachedIsSoftware: true),
            true)
    }

    private static let generation: UInt64 = 7
    private static let failure = Int32(bitPattern: 0x8000_4005)

    func testDisabledCollectorDoesNotAllocateIssueOrPollQueries() async {
        let collector = D3D11GPUFrameTimingCollector()
        let transport = FakeTimestampQueryTransport()

        XCTAssertEqual(collector.currentStatus, .disabled)
        XCTAssertFalse(collector.diagnostics.isEnabled)
        XCTAssertEqual(collector.beginFrame(frameID(1)), .disabled)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)

        collector.attach(transport: transport, deviceGeneration: Self.generation)

        XCTAssertEqual(collector.beginFrame(frameID(2)), .disabled)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        XCTAssertEqual(collector.ownedQueryCount, 0)
        XCTAssertEqual(transport.ownedQueryCount, 0)
        XCTAssertTrue(transport.events.isEmpty)
        XCTAssertEqual(collector.diagnostics.slotCapacity, 8)
        XCTAssertEqual(collector.diagnostics.resultCapacity, 16)
        XCTAssertEqual(collector.diagnostics.maximumGetDataCallsPerPoll, 24)
        collector.detach()
    }

    func testEnableBeforeAttachRetainsRequestAndAllocatesExactlyOneQueryRing() async {
        let collector = D3D11GPUFrameTimingCollector()
        let transport = FakeTimestampQueryTransport()

        XCTAssertFalse(collector.setEnabled(true))
        XCTAssertTrue(collector.diagnostics.isEnabled)
        XCTAssertFalse(collector.diagnostics.isSupported)
        XCTAssertEqual(collector.ownedQueryCount, 0)

        collector.attach(transport: transport, deviceGeneration: Self.generation)
        defer { collector.detach() }

        XCTAssertTrue(collector.diagnostics.isSupported)
        XCTAssertEqual(collector.ownedQueryCount, 24)
        XCTAssertEqual(transport.ownedQueryCount, 24)
        XCTAssertEqual(
            transport.createdKinds,
            (0..<8).flatMap { _ in
                [GPUTimestampQueryKind.disjoint, .timestamp, .timestamp]
            }
        )
        XCTAssertTrue(collector.setEnabled(true))
        XCTAssertEqual(transport.createCallCount, 24, "Enabling twice must not allocate a second ring")
    }

    func testBeginAndEndUseTheRequiredQueryOrderWithoutPolling() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        transport.events.removeAll()
        let id = frameID(1)

        XCTAssertEqual(collector.beginFrame(id), .pending)
        XCTAssertEqual(transport.events, [.begin(1), .end(2)])
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)

        collector.endFrame(id)

        XCTAssertEqual(transport.events, [.begin(1), .end(2), .end(3), .end(1)])
        XCTAssertTrue(transport.readHandles.isEmpty)
        XCTAssertEqual(transport.createCallCount, 24)
    }

    func testSecondFrameCannotOpenADisjointBracketUntilTheFirstFrameEnds() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let first = frameID(1)
        let second = frameID(2)
        XCTAssertEqual(collector.beginFrame(first), .pending)
        transport.events.removeAll()

        XCTAssertEqual(collector.beginFrame(second), .notIssued)

        XCTAssertTrue(transport.events.isEmpty)
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)

        collector.endFrame(first)
        XCTAssertEqual(transport.events, [.end(3), .end(1)])
        transport.events.removeAll()

        XCTAssertEqual(collector.beginFrame(second), .pending)

        XCTAssertEqual(transport.events, [.begin(4), .end(5)])
        XCTAssertEqual(collector.diagnostics.pendingCount, 2)
        collector.endFrame(second)
        XCTAssertTrue(transport.readHandles.isEmpty)
    }

    func testMismatchedGenerationAndDuplicateFrameIDDoNotIssueQueries() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        transport.events.removeAll()

        XCTAssertEqual(collector.beginFrame(frameID(1, generation: Self.generation + 1)), .notIssued)
        XCTAssertTrue(transport.events.isEmpty)
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)

        let id = frameID(1)
        XCTAssertEqual(collector.beginFrame(id), .pending)
        transport.events.removeAll()

        XCTAssertEqual(collector.beginFrame(id), .notIssued)
        XCTAssertTrue(transport.events.isEmpty)
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)
        collector.endFrame(id)
    }

    func testOpenIntervalCannotBePolledBeforeEndFrame() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(1)
        XCTAssertEqual(collector.beginFrame(id), .pending)
        transport.setReady(slot: 0)

        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        XCTAssertTrue(transport.readHandles.isEmpty)
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)

        collector.endFrame(id)

        XCTAssertEqual(collector.takeCompletedResults(), [validResult(id)])
    }

    func testNotReadyQueryIsPolledOncePerCallWithoutSpinningOrReleasingItsSlot() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        issueFrame(frameID(1), collector: collector)

        for _ in 0..<3 {
            transport.events.removeAll()

            XCTAssertTrue(collector.takeCompletedResults().isEmpty)

            XCTAssertFalse(transport.readHandles.isEmpty)
            XCTAssertLessThanOrEqual(transport.readHandles.count, 3)
            XCTAssertEqual(Set(transport.readHandles).count, transport.readHandles.count)
            XCTAssertEqual(collector.diagnostics.pendingCount, 1)
            XCTAssertEqual(collector.ownedQueryCount, 24)
            XCTAssertTrue(transport.releasedHandles.isEmpty)
        }
    }

    func testEveryQueryMustBeReadyBeforePublishingOrReusingTheSlot() async {
        for component in TimestampQueryComponent.allCases {
            let (collector, transport) = makeCollector()
            defer { collector.detach() }
            let id = frameID(1)
            issueFrame(id, collector: collector)
            transport.setReady(slot: 0)
            transport.setReadStatus(1, component: component)
            transport.events.removeAll()

            XCTAssertTrue(collector.takeCompletedResults().isEmpty, "Still waiting for \(component)")
            XCTAssertEqual(collector.diagnostics.pendingCount, 1)
            XCTAssertLessThanOrEqual(transport.readHandles.count, 3)
            XCTAssertEqual(Set(transport.readHandles).count, transport.readHandles.count)

            transport.setReadStatus(0, component: component)

            XCTAssertEqual(collector.takeCompletedResults(), [validResult(id)])
            XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        }
    }

    func testValidResultRetainsItsIssuingFrameAndIsDrainedOnlyOnce() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(42)
        issueFrame(id, collector: collector)
        transport.setReady(slot: 0, start: 100, end: 350, frequency: 1_000)

        XCTAssertEqual(collector.takeCompletedResults(), [validResult(id, seconds: 0.25)])
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        let readCount = transport.readHandles.count

        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        XCTAssertEqual(transport.readHandles.count, readCount)
        XCTAssertEqual(collector.ownedQueryCount, 24, "Completed query objects remain reusable")
    }

    func testOutOfOrderReadinessDoesNotAttributeOldWorkToANewerFrame() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let first = frameID(10)
        let second = frameID(11)
        issueFrame(first, collector: collector)
        issueFrame(second, collector: collector)
        transport.setReady(slot: 1, start: 200, end: 450, frequency: 1_000)

        XCTAssertEqual(collector.takeCompletedResults(), [validResult(second, seconds: 0.25)])
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)

        transport.setReady(slot: 0)

        XCTAssertEqual(collector.takeCompletedResults(), [validResult(first)])
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
    }

    func testDisjointIntervalHasNoElapsedTime() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(1)
        issueFrame(id, collector: collector)
        transport.setReady(slot: 0, isDisjoint: true)

        XCTAssertEqual(
            collector.takeCompletedResults(),
            [GPUFrameTimingResult(frameID: id, status: .disjoint)]
        )
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
    }

    func testDisjointAndInvalidFrequencyWaitForBothTimestampsBeforeReusingSlot() async {
        for isDisjoint in [false, true] {
            let (collector, transport) = makeCollector()
            defer { collector.detach() }
            let id = frameID(1)
            issueFrame(id, collector: collector)
            transport.setReady(slot: 0, frequency: 0, isDisjoint: isDisjoint)
            transport.setReadStatus(1, component: .end)

            XCTAssertTrue(collector.takeCompletedResults().isEmpty)
            XCTAssertEqual(collector.diagnostics.pendingCount, 1)

            transport.setReadStatus(0, component: .end)
            let results = collector.takeCompletedResults()

            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.status, isDisjoint ? .disjoint : .invalidResult)
            XCTAssertNil(results.first?.elapsedSeconds)
            XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        }
    }

    func testZeroFrequencyAndBackwardsTimestampsAreInvalidResults() async {
        let intervals: [(start: UInt64, end: UInt64, frequency: UInt64)] = [
            (100, 225, 0),
            (225, 100, 1_000),
        ]
        for interval in intervals {
            let (collector, transport) = makeCollector()
            defer { collector.detach() }
            let id = frameID(1)
            issueFrame(id, collector: collector)
            transport.setReady(
                slot: 0, start: interval.start, end: interval.end, frequency: interval.frequency
            )

            XCTAssertEqual(
                collector.takeCompletedResults(),
                [GPUFrameTimingResult(frameID: id, status: .invalidResult)]
            )
            XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        }
    }

    func testLargeCounterValuesAreSubtractedBeforeConversionToDouble() async throws {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(1)
        issueFrame(id, collector: collector)
        transport.setReady(slot: 0, start: UInt64.max - 19, end: UInt64.max - 9, frequency: 1_000)

        let result = try XCTUnwrap(collector.takeCompletedResults().first)

        XCTAssertEqual(result.frameID, id)
        XCTAssertEqual(result.status, .valid)
        XCTAssertEqual(try XCTUnwrap(result.elapsedSeconds), 0.01, accuracy: 1e-12)
    }

    func testEqualTimestampsAreAValidZeroDuration() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(1)
        issueFrame(id, collector: collector)
        transport.setReady(slot: 0, start: 250, end: 250, frequency: 1_000)

        XCTAssertEqual(collector.takeCompletedResults(), [validResult(id, seconds: 0)])
    }

    func testEveryUnexpectedGetDataHRESULTFailsAndReleasesAllPendingWork() async {
        for component in TimestampQueryComponent.allCases {
            for failure in [Self.failure, Int32(2)] {
                let (collector, transport) = makeCollector()
                defer { collector.detach() }
                let first = frameID(1)
                let second = frameID(2)
                issueFrame(first, collector: collector)
                issueFrame(second, collector: collector)
                transport.setReady(slot: 0)
                transport.setReadStatus(failure, component: component)

                let results = collector.takeCompletedResults()

                XCTAssertEqual(Set(results.map(\.frameID)), Set([first, second]))
                XCTAssertEqual(results.count, 2)
                XCTAssertTrue(results.allSatisfy { $0.status == .failed })
                XCTAssertTrue(results.allSatisfy { $0.failureCode == failure && $0.elapsedSeconds == nil })
                XCTAssertEqual(collector.diagnostics.failureCode, failure)
                XCTAssertEqual(collector.diagnostics.pendingCount, 0)
                XCTAssertFalse(collector.diagnostics.isSupported)
                XCTAssertTrue(collector.diagnostics.isEnabled)
                assertAllQueriesReleased(transport, collector: collector)
                let readCount = transport.readHandles.count

                XCTAssertTrue(collector.takeCompletedResults().isEmpty)
                XCTAssertEqual(collector.beginFrame(frameID(3)), .failed)
                XCTAssertEqual(transport.readHandles.count, readCount)
                XCTAssertEqual(transport.createCallCount, 24)
            }
        }
    }

    func testKnownDeviceLossCodesProduceDeviceLostResults() async {
        for failure in [
            DeviceLostPolicy.deviceRemoved,
            DeviceLostPolicy.deviceReset,
            DeviceLostPolicy.deviceHung,
            DeviceLostPolicy.driverInternalError,
        ] {
            let (collector, transport) = makeCollector()
            defer { collector.detach() }
            let id = frameID(1)
            issueFrame(id, collector: collector)
            transport.setReady(slot: 0)
            transport.setReadStatus(failure, component: .start)

            XCTAssertEqual(
                collector.takeCompletedResults(),
                [GPUFrameTimingResult(frameID: id, status: .deviceLost, failureCode: failure)]
            )
            XCTAssertEqual(collector.currentStatus, .deviceLost)
            assertAllQueriesReleased(transport, collector: collector)
        }
    }

    func testQueryFailureRemainsStickyAcrossEnableTogglesUntilNewGeneration() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        issueFrame(frameID(1), collector: collector)
        transport.setReadStatus(Self.failure, component: .disjoint)
        XCTAssertEqual(collector.takeCompletedResults().count, 1)

        _ = collector.setEnabled(false)
        XCTAssertEqual(collector.currentStatus, .disabled)
        XCTAssertFalse(collector.setEnabled(true))
        XCTAssertEqual(collector.currentStatus, .failed)
        XCTAssertEqual(collector.diagnostics.failureCode, Self.failure)
        XCTAssertEqual(transport.createCallCount, 24)
        XCTAssertEqual(collector.ownedQueryCount, 0)

        let replacement = FakeTimestampQueryTransport()
        collector.attach(transport: replacement, deviceGeneration: Self.generation + 1)

        XCTAssertTrue(collector.diagnostics.isSupported)
        XCTAssertNil(collector.diagnostics.failureCode)
        XCTAssertEqual(replacement.ownedQueryCount, 24)
        let id = frameID(1, generation: Self.generation + 1)
        issueFrame(id, collector: collector)
        replacement.setReady(slot: 0)
        XCTAssertEqual(collector.takeCompletedResults(), [validResult(id)])
    }

    func testFullRingSkipsNewWorkWithoutPollingAllocatingOrOverwritingQueries() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        for number in 1...8 {
            issueFrame(frameID(UInt64(number)), collector: collector)
        }
        transport.events.removeAll()

        XCTAssertEqual(collector.beginFrame(frameID(9)), .ringFull)

        XCTAssertEqual(collector.diagnostics.pendingCount, 8)
        XCTAssertEqual(collector.ownedQueryCount, 24)
        XCTAssertEqual(transport.createCallCount, 24)
        XCTAssertTrue(transport.events.isEmpty)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty, "Unissued work has no terminal result")
        XCTAssertLessThanOrEqual(transport.readHandles.count, 24)
    }

    func testOnePollReadsAtMostThreeQueriesPerPendingSlot() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let ids = (1...8).map { frameID(UInt64($0)) }
        for (slot, id) in ids.enumerated() {
            issueFrame(id, collector: collector)
            transport.setReady(slot: slot)
        }
        transport.events.removeAll()

        let results = collector.takeCompletedResults()

        XCTAssertEqual(Set(results.map(\.frameID)), Set(ids))
        XCTAssertEqual(results.count, 8)
        XCTAssertEqual(transport.readHandles.count, 24)
        XCTAssertEqual(Set(transport.readHandles).count, 24)
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)
    }

    func testOnlyCompletedSlotCanBeReusedWhenOtherSlotsRemainPending() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        for number in 1...8 {
            issueFrame(frameID(UInt64(number)), collector: collector)
        }
        transport.setReady(slot: 0)
        XCTAssertEqual(collector.takeCompletedResults(), [validResult(frameID(1))])
        XCTAssertEqual(collector.diagnostics.pendingCount, 7)
        // Reissuing a native query starts a fresh pending result. The fake
        // models that explicitly instead of leaving frame 1's ready payload.
        for component in TimestampQueryComponent.allCases {
            transport.setReadStatus(1, component: component)
        }
        transport.events.removeAll()

        XCTAssertEqual(collector.beginFrame(frameID(9)), .pending)

        XCTAssertEqual(transport.events, [.begin(1), .end(2)])
        XCTAssertEqual(transport.createCallCount, 24)
        XCTAssertEqual(collector.diagnostics.pendingCount, 8)
        collector.endFrame(frameID(9))

        XCTAssertTrue(collector.takeCompletedResults().isEmpty, "Frame 1's result cannot satisfy frame 9")
        XCTAssertEqual(collector.diagnostics.pendingCount, 8)

        transport.setReady(slot: 0, start: 700, end: 1_200, frequency: 1_000)

        XCTAssertEqual(collector.takeCompletedResults(), [validResult(frameID(9), seconds: 0.5)])
        XCTAssertEqual(collector.diagnostics.pendingCount, 7)
        XCTAssertEqual(transport.createCallCount, 24)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty, "Neither issuing frame may be delivered twice")
    }

    func testAbortClosesOpenIntervalAndReportsOnceWhileRetainingItsPendingSlot() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(1)
        transport.events.removeAll()
        XCTAssertEqual(collector.beginFrame(id), .pending)

        collector.abortFrame(id)

        XCTAssertEqual(transport.events, [.begin(1), .end(2), .end(3), .end(1)])
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)
        XCTAssertEqual(
            collector.takeCompletedResults(),
            [GPUFrameTimingResult(frameID: id, status: .aborted)]
        )
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)
        XCTAssertEqual(collector.ownedQueryCount, 24)
        transport.events.removeAll()

        collector.abortFrame(id)
        collector.endFrame(id)

        XCTAssertTrue(transport.events.isEmpty, "Ending or aborting twice must not reissue End")
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        for number in 2...8 {
            issueFrame(frameID(UInt64(number)), collector: collector)
        }
        XCTAssertEqual(collector.beginFrame(frameID(9)), .ringFull)

        transport.setReady(slot: 0)

        XCTAssertTrue(collector.takeCompletedResults().isEmpty, "Resolved abort must not publish again")
        XCTAssertEqual(collector.diagnostics.pendingCount, 7)
        XCTAssertEqual(collector.beginFrame(frameID(9)), .pending)
        collector.endFrame(frameID(9))
    }

    func testAbortAfterEndDoesNotEndQueriesAgainAndPreservesFailureCode() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let id = frameID(1)
        issueFrame(id, collector: collector)
        transport.events.removeAll()

        collector.abortFrame(id, status: .aborted, failureCode: Self.failure)

        XCTAssertTrue(transport.events.isEmpty)
        XCTAssertEqual(
            collector.takeCompletedResults(),
            [GPUFrameTimingResult(frameID: id, status: .aborted, failureCode: Self.failure)]
        )
        collector.detach()
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
    }

    func testDeviceLostAbortInvalidatesEveryIntervalWithoutEndingAnOpenBracket() async {
        let failureCodes: [Int32?] = [nil, DeviceLostPolicy.deviceRemoved]
        for failureCode in failureCodes {
            let (collector, transport) = makeCollector()
            defer { collector.detach() }
            let closedID = frameID(1)
            let openID = frameID(2)
            issueFrame(closedID, collector: collector)
            XCTAssertEqual(collector.beginFrame(openID), .pending)
            transport.events.removeAll()

            collector.abortFrame(openID, status: .deviceLost, failureCode: failureCode)

            XCTAssertTrue(
                transport.events.allSatisfy { event in
                    if case .release = event { return true }
                    return false
                },
                "A lost device may release queries but must not receive End or GetData"
            )
            assertAllQueriesReleased(transport, collector: collector)
            XCTAssertEqual(collector.diagnostics.pendingCount, 0)
            XCTAssertTrue(collector.diagnostics.isEnabled)
            XCTAssertFalse(collector.diagnostics.isSupported)
            XCTAssertNil(collector.diagnostics.failureCode)
            XCTAssertEqual(collector.currentStatus, .unsupported)
            let eventsAfterLoss = transport.events

            collector.endFrame(openID)
            collector.endFrame(closedID)
            collector.abortFrame(openID, status: .deviceLost, failureCode: failureCode)

            XCTAssertEqual(transport.events, eventsAfterLoss)
            XCTAssertEqual(
                collector.takeCompletedResults(),
                [
                    GPUFrameTimingResult(frameID: closedID, status: .deviceLost, failureCode: failureCode),
                    GPUFrameTimingResult(frameID: openID, status: .deviceLost, failureCode: failureCode),
                ]
            )
            XCTAssertTrue(collector.takeCompletedResults().isEmpty)
            XCTAssertEqual(transport.events, eventsAfterLoss)
        }
    }

    func testQueryFailureAfterAbortDoesNotPublishASecondTerminalResultForThatFrame() async {
        let (collector, transport) = makeCollector()
        defer { collector.detach() }
        let aborted = frameID(1)
        let failed = frameID(2)
        issueFrame(aborted, collector: collector)
        collector.abortFrame(aborted)
        issueFrame(failed, collector: collector)
        transport.setReadStatus(Self.failure, component: .disjoint)

        XCTAssertEqual(
            collector.takeCompletedResults(),
            [
                GPUFrameTimingResult(frameID: aborted, status: .aborted),
                GPUFrameTimingResult(frameID: failed, status: .failed, failureCode: Self.failure),
            ]
        )
        assertAllQueriesReleased(transport, collector: collector)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
    }

    func testDetachReleasesAllQueriesAndDoesNotDuplicateAnAlreadyAbortedFrame() async {
        let (collector, transport) = makeCollector()
        let aborted = frameID(1)
        let cancelled = frameID(2)
        XCTAssertEqual(collector.beginFrame(aborted), .pending)
        collector.abortFrame(aborted)
        XCTAssertEqual(collector.beginFrame(cancelled), .pending)

        collector.detach()

        XCTAssertEqual(
            collector.takeCompletedResults(),
            [
                GPUFrameTimingResult(frameID: aborted, status: .aborted),
                GPUFrameTimingResult(frameID: cancelled, status: .cancelled),
            ]
        )
        XCTAssertTrue(transport.readHandles.isEmpty)
        XCTAssertTrue(collector.diagnostics.isEnabled)
        XCTAssertFalse(collector.diagnostics.isSupported)
        XCTAssertNil(collector.diagnostics.failureCode)
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        assertAllQueriesReleased(transport, collector: collector)

        collector.detach()

        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        XCTAssertEqual(transport.releasedHandles.count, 24)
    }

    func testDisableCancelsPendingFramesAndDrainsWithoutPolling() async {
        let (collector, transport) = makeCollector()
        let first = frameID(1)
        let second = frameID(2)
        issueFrame(first, collector: collector)
        XCTAssertEqual(collector.beginFrame(second), .pending)

        _ = collector.setEnabled(false)

        XCTAssertEqual(collector.currentStatus, .disabled)
        XCTAssertFalse(collector.diagnostics.isEnabled)
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        XCTAssertEqual(
            collector.takeCompletedResults(),
            [
                GPUFrameTimingResult(frameID: first, status: .cancelled),
                GPUFrameTimingResult(frameID: second, status: .cancelled),
            ]
        )
        XCTAssertTrue(transport.readHandles.isEmpty)
        assertAllQueriesReleased(transport, collector: collector)
        XCTAssertEqual(collector.beginFrame(frameID(3)), .disabled)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        collector.detach()
    }

    func testDeviceReplacementKeepsTerminalResultsBoundToTheirOriginalGeneration() async {
        let (collector, original) = makeCollector()
        defer { collector.detach() }
        let oldID = frameID(1)
        XCTAssertEqual(collector.beginFrame(oldID), .pending)
        original.events.removeAll()
        collector.detach(status: .deviceLost)
        XCTAssertTrue(
            original.events.allSatisfy { event in
                if case .release = event { return true }
                return false
            },
            "Detaching a lost device must not close its open query bracket"
        )
        let replacement = FakeTimestampQueryTransport()
        collector.attach(transport: replacement, deviceGeneration: Self.generation + 1)
        let newID = frameID(1, generation: Self.generation + 1)
        XCTAssertEqual(collector.beginFrame(newID), .pending)
        let eventsBeforeStaleAbort = replacement.events

        collector.abortFrame(oldID, status: .deviceLost, failureCode: DeviceLostPolicy.deviceRemoved)

        XCTAssertEqual(replacement.events, eventsBeforeStaleAbort)
        XCTAssertEqual(collector.diagnostics.pendingCount, 1)
        XCTAssertTrue(collector.diagnostics.isSupported)
        XCTAssertEqual(replacement.ownedQueryCount, 24)
        collector.endFrame(newID)
        replacement.setReady(slot: 0)

        XCTAssertEqual(
            collector.takeCompletedResults(),
            [GPUFrameTimingResult(frameID: oldID, status: .deviceLost), validResult(newID)]
        )
        XCTAssertTrue(original.readHandles.isEmpty)
        XCTAssertEqual(original.ownedQueryCount, 0)
        XCTAssertEqual(original.releasedHandles.count, 24)
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
    }

    func testUndrainedResultsDropTheOldestEntriesAtTheFixedCapacity() async {
        let collector = D3D11GPUFrameTimingCollector()
        XCTAssertFalse(collector.setEnabled(true))
        var expected: [GPUFrameTimingResult] = []
        var transports: [FakeTimestampQueryTransport] = []
        for generation in UInt64(1)...UInt64(3) {
            let transport = FakeTimestampQueryTransport()
            transports.append(transport)
            collector.attach(transport: transport, deviceGeneration: generation)
            for number in UInt64(1)...UInt64(8) {
                let id = frameID(number, generation: generation)
                issueFrame(id, collector: collector)
                expected.append(GPUFrameTimingResult(frameID: id, status: .cancelled))
            }
            collector.detach()
        }

        XCTAssertEqual(collector.diagnostics.droppedResultCount, 8)
        XCTAssertEqual(collector.diagnostics.pendingCount, 0)
        XCTAssertEqual(collector.takeCompletedResults(), Array(expected.suffix(16)))
        XCTAssertTrue(collector.takeCompletedResults().isEmpty)
        XCTAssertEqual(collector.diagnostics.droppedResultCount, 8, "Draining does not erase lost-result evidence")
        XCTAssertTrue(transports.allSatisfy { $0.readHandles.isEmpty && $0.ownedQueryCount == 0 })
    }

    func testCreationFailureReleasesPartialAllocationIncludingAnUnexpectedReturnedHandle() async {
        for returnsHandle in [false, true] {
            let collector = D3D11GPUFrameTimingCollector()
            let transport = FakeTimestampQueryTransport()
            transport.creationOverride = (call: 5, hresult: Self.failure, returnsHandle: returnsHandle)
            collector.attach(transport: transport, deviceGeneration: Self.generation)
            defer { collector.detach() }

            XCTAssertFalse(collector.setEnabled(true))

            XCTAssertEqual(transport.createCallCount, 5)
            XCTAssertEqual(transport.allocatedHandles.count, returnsHandle ? 5 : 4)
            XCTAssertEqual(collector.diagnostics.failureCode, Self.failure)
            XCTAssertFalse(collector.diagnostics.isSupported)
            assertAllQueriesReleased(transport, collector: collector)
            XCTAssertTrue(collector.takeCompletedResults().isEmpty)
            XCTAssertTrue(transport.readHandles.isEmpty)

            _ = collector.setEnabled(false)
            XCTAssertFalse(collector.setEnabled(true))
            XCTAssertEqual(transport.createCallCount, 5, "Allocation failure is sticky for this device generation")
        }
    }

    func testSuccessfulCreateWithoutAHandleFailsWithEPointerAndReleasesEarlierQueries() async {
        let collector = D3D11GPUFrameTimingCollector()
        let transport = FakeTimestampQueryTransport()
        transport.creationOverride = (call: 3, hresult: 0, returnsHandle: false)
        collector.attach(transport: transport, deviceGeneration: Self.generation)
        defer { collector.detach() }

        XCTAssertFalse(collector.setEnabled(true))

        XCTAssertEqual(collector.diagnostics.failureCode, Int32(bitPattern: 0x8000_4003))
        XCTAssertEqual(transport.createCallCount, 3)
        XCTAssertEqual(transport.allocatedHandles.count, 2)
        assertAllQueriesReleased(transport, collector: collector)
    }

    func testPositiveCreateHRESULTIsNotAcceptedAsSuccessfulAllocation() async {
        for hresult in [Int32(1), Int32(2)] {
            let collector = D3D11GPUFrameTimingCollector()
            let transport = FakeTimestampQueryTransport()
            transport.creationOverride = (call: 2, hresult: hresult, returnsHandle: true)
            collector.attach(transport: transport, deviceGeneration: Self.generation)
            defer { collector.detach() }

            XCTAssertFalse(collector.setEnabled(true))

            XCTAssertEqual(collector.diagnostics.failureCode, hresult)
            XCTAssertEqual(transport.createCallCount, 2)
            XCTAssertEqual(transport.allocatedHandles.count, 2)
            assertAllQueriesReleased(transport, collector: collector)
        }
    }

    func testUnsupportedQueryCreationReportsUnavailableAndDoesNotRetryTheSameGeneration() async {
        for failure in [Int32(bitPattern: 0x8000_4001), Int32(bitPattern: 0x887A_0004)] {
            let collector = D3D11GPUFrameTimingCollector()
            let transport = FakeTimestampQueryTransport()
            transport.creationOverride = (call: 1, hresult: failure, returnsHandle: false)
            collector.attach(transport: transport, deviceGeneration: Self.generation)
            defer { collector.detach() }

            XCTAssertFalse(collector.setEnabled(true))
            XCTAssertEqual(collector.currentStatus, .unsupported)
            XCTAssertTrue(collector.diagnostics.isEnabled)
            XCTAssertFalse(collector.diagnostics.isSupported)
            XCTAssertEqual(collector.diagnostics.failureCode, failure)
            XCTAssertFalse(collector.setEnabled(true))
            XCTAssertEqual(transport.createCallCount, 1)
            assertAllQueriesReleased(transport, collector: collector)
        }
    }

    private func makeCollector() -> (D3D11GPUFrameTimingCollector, FakeTimestampQueryTransport) {
        let collector = D3D11GPUFrameTimingCollector()
        let transport = FakeTimestampQueryTransport()
        collector.attach(transport: transport, deviceGeneration: Self.generation)
        XCTAssertTrue(collector.setEnabled(true))
        return (collector, transport)
    }

    private func frameID(_ number: UInt64) -> BackendFrameID {
        frameID(number, generation: Self.generation)
    }

    private func frameID(_ number: UInt64, generation: UInt64) -> BackendFrameID {
        BackendFrameID(deviceGeneration: generation, frameNumber: number)
    }

    private func issueFrame(_ id: BackendFrameID, collector: D3D11GPUFrameTimingCollector) {
        XCTAssertEqual(collector.beginFrame(id), .pending)
        collector.endFrame(id)
    }

    private func validResult(_ id: BackendFrameID, seconds: Double = 0.125) -> GPUFrameTimingResult {
        GPUFrameTimingResult(frameID: id, status: .valid, elapsedSeconds: seconds)
    }

    private func assertAllQueriesReleased(
        _ transport: FakeTimestampQueryTransport, collector: D3D11GPUFrameTimingCollector
    ) {
        XCTAssertEqual(collector.ownedQueryCount, 0)
        XCTAssertEqual(transport.ownedQueryCount, 0)
        XCTAssertEqual(Set(transport.releasedHandles), Set(transport.allocatedHandles))
        XCTAssertEqual(transport.releasedHandles.count, transport.allocatedHandles.count)
    }
}

private enum TimestampQueryComponent: CaseIterable, Equatable {
    case disjoint
    case start
    case end
}

@MainActor
private final class FakeTimestampQueryTransport: GPUTimestampQueryTransport {
    enum Event: Equatable {
        case create(GPUTimestampQueryKind, Int32, Int?)
        case release(Int)
        case begin(Int)
        case end(Int)
        case readTimestamp(Int)
        case readDisjoint(Int)
    }

    var events: [Event] = []
    var creationOverride: (call: Int, hresult: Int32, returnsHandle: Bool)?
    private(set) var createCallCount = 0
    private(set) var allocatedHandles: [Int] = []
    private(set) var releasedHandles: [Int] = []
    private(set) var createdKinds: [GPUTimestampQueryKind] = []
    private var nextHandle = 1
    private var ownedQueries: [Int: GPUTimestampQueryKind] = [:]
    private var timestamps: [Int: (hresult: Int32, value: UInt64)] = [:]
    private var disjoints: [Int: (hresult: Int32, frequency: UInt64, isDisjoint: Bool)] = [:]

    var ownedQueryCount: Int { ownedQueries.count }

    var readHandles: [Int] {
        events.compactMap { event in
            switch event {
            case .readTimestamp(let handle), .readDisjoint(let handle): return handle
            default: return nil
            }
        }
    }

    func createQuery(_ kind: GPUTimestampQueryKind) -> (hresult: Int32, handle: Int?) {
        createCallCount += 1
        createdKinds.append(kind)
        let response = creationOverride?.call == createCallCount ? creationOverride : nil
        let hresult = response?.hresult ?? 0
        var handle: Int?
        if response?.returnsHandle != false {
            handle = nextHandle
            ownedQueries[nextHandle] = kind
            allocatedHandles.append(nextHandle)
            nextHandle += 1
        }
        events.append(.create(kind, hresult, handle))
        return (hresult, handle)
    }

    func releaseQuery(_ handle: Int) {
        XCTAssertNotNil(ownedQueries.removeValue(forKey: handle), "A query must be released exactly once")
        releasedHandles.append(handle)
        events.append(.release(handle))
    }

    func beginQuery(_ handle: Int) {
        XCTAssertEqual(ownedQueries[handle], .disjoint, "Timestamp queries must use End, never Begin")
        events.append(.begin(handle))
    }

    func endQuery(_ handle: Int) {
        XCTAssertNotNil(ownedQueries[handle], "End must not access a released query")
        events.append(.end(handle))
    }

    func readTimestamp(_ handle: Int) -> (hresult: Int32, value: UInt64) {
        XCTAssertEqual(ownedQueries[handle], .timestamp)
        events.append(.readTimestamp(handle))
        return timestamps[handle] ?? (1, 0)
    }

    func readDisjoint(_ handle: Int) -> (hresult: Int32, frequency: UInt64, isDisjoint: Bool) {
        XCTAssertEqual(ownedQueries[handle], .disjoint)
        events.append(.readDisjoint(handle))
        return disjoints[handle] ?? (1, 0, false)
    }

    func setReady(
        slot: Int, start: UInt64 = 100, end: UInt64 = 225, frequency: UInt64 = 1_000,
        isDisjoint: Bool = false
    ) {
        let first = slot * 3 + 1
        disjoints[first] = (0, frequency, isDisjoint)
        timestamps[first + 1] = (0, start)
        timestamps[first + 2] = (0, end)
    }

    func setReadStatus(_ hresult: Int32, component: TimestampQueryComponent, slot: Int = 0) {
        let first = slot * 3 + 1
        switch component {
        case .disjoint:
            let previous = disjoints[first] ?? (hresult: 1, frequency: 0, isDisjoint: false)
            disjoints[first] = (hresult, previous.frequency, previous.isDisjoint)
        case .start, .end:
            let handle = first + (component == .start ? 1 : 2)
            let previous = timestamps[handle] ?? (hresult: 1, value: 0)
            timestamps[handle] = (hresult, previous.value)
        }
    }
}
