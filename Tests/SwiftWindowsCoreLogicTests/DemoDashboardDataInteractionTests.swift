import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public view composition with real retained inputs and observed invalidation.
/// These do not attest native windows, the production frame scheduler, macOS,
/// composited screenshots, renderer recovery, or performance qualification.
@MainActor
final class DemoDashboardDataInteractionTests: XCTestCase {
    // Synchronous XCTest class hooks touch only the nonactor diagnostic observer.
    nonisolated override class func setUp() {
        super.setUp()
        if let observer = DashboardInteractionTraceObserver.configured {
            XCTestObservationCenter.shared.addTestObserver(observer)
            observer.recordRegistered()
        }
    }

    nonisolated override class func tearDown() {
        if let observer = DashboardInteractionTraceObserver.configured {
            XCTestObservationCenter.shared.removeTestObserver(observer)
            observer.recordRemoved()
        }
        super.tearDown()
    }

    func testInitialPreviewKeepsTheExistingChartAndFocusableInputControls() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        XCTAssertTrue(fixture.texts.contains("Render pipeline"))
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Preview data"])
        XCTAssertTrue(fixture.hasNode("dashboard.data.plot"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.empty"))
        let plotTexts = try fixture.texts(in: "dashboard.data.plot")
        for bar in DemoChartCard.bars(interactions: 0) { XCTAssertTrue(plotTexts.contains(bar.label)) }
        for label in ["0", "10", "40"] { XCTAssertTrue(plotTexts.contains(label)) }
        for sample in DemoDashboardDataSample.allCases {
            XCTAssertEqual(try fixture.enabledButtons(in: "dashboard.data.sample.\(sample.rawValue)").count, 1)
        }
        XCTAssertEqual(try fixture.enabledButtons(in: "dashboard.data.refresh").count, 1)
        XCTAssertFalse(fixture.hasNode("dashboard.data.cancel"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.retry"))
        XCTAssertTrue(fixture.observedObjectIDs.contains(ObjectIdentifier(harness.model)))
        XCTAssertTrue(fixture.observedObjectIDs.contains(ObjectIdentifier(fixture.dashboard)))
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
    }

    func testKeyboardRefreshShowsLoadingAndPublishesOnlyActuallyDecodedPoints() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let diagnostics = DemoDashboardTaskAwaitDiagnostics.configuredForRefresh()
        let fixture = DemoDashboardDataFixture(model: harness.model, taskAwaitDiagnostics: diagnostics)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.refresh")
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Loading local data"])
        XCTAssertEqual(try fixture.enabledButtons(in: "dashboard.data.cancel").count, 1)
        XCTAssertTrue(fixture.hasNode("dashboard.data.plot"), "Loading retains the current preview")
        try await harness.starts(1)
        let payload = try dashboardDataJSON(day: [
            ["label": "Read A", "fraction": 0.25], ["label": "Read B", "fraction": 0.875],
        ])
        try await harness.finish(0, bytes: payload, diagnostics: diagnostics)
        // No manual reload: the mounted ObservedObject notification owns it.
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Local data loaded"])
        XCTAssertTrue(fixture.texts.contains("2 local samples \u{2014} 24h"))
        let plot = try fixture.texts(in: "dashboard.data.plot")
        XCTAssertTrue(plot.contains("Read A"))
        XCTAssertTrue(plot.contains("Read B"))
        XCTAssertTrue(plot.contains("35"))
        XCTAssertFalse(plot.contains("1"), "The original preview labels cannot stand in for decoded values")
        XCTAssertFalse(fixture.hasNode("dashboard.data.cancel"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.retry"))
        XCTAssertTrue(fixture.observedNotifications.contains(ObjectIdentifier(harness.model)))
        XCTAssertEqual(try harness.report().day.map(\.fraction), [0.25, 0.875])
    }

    func testEmptyInputRemovesThePlotAndValidRefreshRestoresActualData() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.sample.empty")
        XCTAssertEqual(harness.model.snapshot.selectedSample, .empty)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        XCTAssertEqual(harness.gate.snapshot.starts[0].sample, .empty)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.empty))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Local data is empty"])
        XCTAssertTrue(fixture.hasNode("dashboard.data.empty"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.plot"))
        XCTAssertTrue(fixture.texts.contains("No samples for 24h"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.retry"))
        try fixture.activateLabel("7d")
        XCTAssertTrue(fixture.texts.contains("No samples for 7d"))
        try fixture.activate("dashboard.data.sample.valid")
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(2)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.valid))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Local data loaded"])
        XCTAssertFalse(fixture.hasNode("dashboard.data.empty"))
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("Mon"))
        XCTAssertTrue(fixture.texts.contains("7 local samples \u{2014} 7d"))
    }

    func testMalformedInputAndRetryShowRealErrorsUntilNewInputSucceeds() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.sample.malformed")
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.malformed))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Unable to load local data"])
        XCTAssertTrue(
            try fixture.texts(in: "dashboard.data.detail").joined().contains(
                DemoDashboardDataError.malformedJSON.message))
        XCTAssertEqual(try fixture.enabledButtons(in: "dashboard.data.retry").count, 1)
        let failedID = harness.model.snapshot.requestID
        try fixture.activate("dashboard.data.retry")
        XCTAssertNotEqual(harness.model.snapshot.requestID, failedID)
        try await harness.starts(2)
        XCTAssertEqual(harness.gate.snapshot.starts[1].sample, .malformed)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.malformed))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Unable to load local data"])
        try fixture.activate("dashboard.data.sample.valid")
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(3)
        try await harness.finish(2, bytes: DemoDashboardDataService.encodedSample(.valid))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Local data loaded"])
        XCTAssertFalse(fixture.hasNode("dashboard.data.retry"))
        XCTAssertFalse(fixture.texts.contains("Unable to load local data"))
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.malformed, .malformed, .valid])
    }

    func testKeyboardCancelRevokesPublicationAndRetryStartsAFreshRead() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        let cancelledID = harness.model.snapshot.requestID
        try fixture.activate("dashboard.data.cancel")
        try await harness.cancelled(0)
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Load cancelled"])
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.detail").joined().contains("physical read"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.cancel"))
        XCTAssertEqual(try fixture.enabledButtons(in: "dashboard.data.retry").count, 1)
        XCTAssertTrue(harness.model.isReading)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Load cancelled"])
        XCTAssertEqual(harness.model.snapshot.content, .preview)
        XCTAssertEqual(harness.model.snapshot.requestID, cancelledID)
        XCTAssertFalse(harness.model.isReading)
        try fixture.activate("dashboard.data.retry")
        try await harness.starts(2)
        XCTAssertNotEqual(harness.model.snapshot.requestID, cancelledID)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.valid))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Local data loaded"])
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
    }

    func testRepeatedRefreshButtonsWaitForTheOldReadAndKeepOnlyLatestIntent() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        try fixture.activate("dashboard.data.sample.malformed")
        try fixture.activate("dashboard.data.refresh")
        try fixture.activate("dashboard.data.sample.empty")
        try fixture.activate("dashboard.data.refresh")
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Waiting for previous read"])
        XCTAssertEqual(harness.model.pendingRequestCount, 1)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
        let newest = harness.model.snapshot.requestID
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        try await harness.starts(2)
        fixture.render()
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.sample), [.valid, .empty])
        XCTAssertEqual(harness.model.snapshot.requestID, newest)
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Loading local data"])
        XCTAssertEqual(harness.model.snapshot.content, .preview)
        try await harness.finish(1, bytes: DemoDashboardDataService.encodedSample(.empty))
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Local data is empty"])
        XCTAssertFalse(fixture.hasNode("dashboard.data.plot"))
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
    }

    func testTheExistingRangeButtonsPreserveSelectionAndUseDecodedSeries() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activateLabel("7d")
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("Mon"))
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        let payload = try dashboardDataJSON(
            week: [["label": "Week read", "fraction": 0.5]], all: [["label": "Year read", "fraction": 0.9]])
        try await harness.finish(0, bytes: payload)
        fixture.render()
        XCTAssertTrue(fixture.texts.contains("1 local sample \u{2014} 7d"))
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("Week read"))
        try fixture.activateLabel("All")
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("Year read"))
        XCTAssertFalse(try fixture.texts(in: "dashboard.data.plot").contains("Week read"))
        try fixture.activateLabel("24h")
        XCTAssertTrue(fixture.hasNode("dashboard.data.empty"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.plot"))
        XCTAssertEqual(harness.model.snapshot.phase, .ready, "Only this range is empty; the decoded report is not")
        try fixture.activateLabel("7d")
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("Week read"))
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1, "Range filters do not start unrelated reads")
    }

    func testDecodedChartMarksStillRespondToRetainedPointerHover() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        try await harness.finish(
            0,
            bytes: dashboardDataJSON(day: [
                ["label": "Low", "fraction": 0.33], ["label": "High", "fraction": 0.77],
            ]))
        fixture.render()
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("31"))
        XCTAssertFalse(try fixture.texts(in: "dashboard.data.plot").contains("13"))
        let marks = DemoDashboardDataFixture.descendants(try fixture.node("dashboard.data.plot"))
            .filter { $0.onPointerEnter != nil && $0.onPointerExit != nil }
            .sorted { fixture.bounds(of: $0).minX < fixture.bounds(of: $1).minX }
        XCTAssertEqual(marks.count, 2)
        let first = fixture.bounds(of: try XCTUnwrap(marks.first))
        XCTAssertGreaterThan(first.size.width, 0)
        XCTAssertGreaterThan(first.size.height, 0)
        fixture.runtime.pointerMoved(to: Point(x: first.midX, y: first.midY))
        fixture.render()
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("13"))
        XCTAssertFalse(try fixture.texts(in: "dashboard.data.plot").contains("31"))
        fixture.runtime.pointerExitedWindow()
        fixture.render()
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("31"))
        XCTAssertFalse(try fixture.texts(in: "dashboard.data.plot").contains("13"))
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
    }

    func testInputAndRefreshControlsStayInsideTheMinimumWindowInBothAppearances() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        for scheme in [ColorScheme.light, .dark] {
            for scale in [1.0, 1.5] {
                let harness = DemoDashboardDataHarness()
                let size = IntSize(width: 640, height: 480)
                let fixture = DemoDashboardDataFixture(model: harness.model, size: size, scheme: scheme, scale: scale)
                defer {
                    fixture.close()
                    harness.close()
                }
                for identifier in [
                    "dashboard.data.sample.valid", "dashboard.data.sample.empty", "dashboard.data.sample.malformed",
                    "dashboard.data.refresh",
                ] {
                    let controls = try fixture.enabledButtons(in: identifier)
                    XCTAssertEqual(controls.count, 1)
                    let bounds = fixture.bounds(of: try XCTUnwrap(controls.first))
                    XCTAssertGreaterThan(bounds.size.width, 0)
                    XCTAssertGreaterThanOrEqual(bounds.size.height, 12)
                    XCTAssertGreaterThanOrEqual(bounds.minX, 0)
                    XCTAssertGreaterThanOrEqual(bounds.minY, 0)
                    XCTAssertLessThanOrEqual(bounds.maxX, Double(size.width) + 0.5)
                    XCTAssertLessThanOrEqual(bounds.maxY, Double(size.height) + 0.5)
                }
                try fixture.activate("dashboard.data.sample.empty")
                XCTAssertEqual(harness.model.snapshot.selectedSample, .empty)
                XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
            }
        }
    }

    func testClosedOwnerReleasesThePlotAndDisablesPublicLoadControls() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        try await harness.finish(0, bytes: DemoDashboardDataService.encodedSample(.valid))
        harness.model.close()
        fixture.render()
        XCTAssertEqual(try fixture.texts(in: "dashboard.data.status"), ["Data loader closed"])
        XCTAssertFalse(fixture.hasNode("dashboard.data.plot"))
        XCTAssertTrue(fixture.hasNode("dashboard.data.empty"))
        XCTAssertEqual(harness.model.snapshot.content, .released)
        for identifier in [
            "dashboard.data.refresh", "dashboard.data.sample.valid", "dashboard.data.sample.empty",
            "dashboard.data.sample.malformed",
        ] {
            XCTAssertTrue(try fixture.enabledButtons(in: identifier).isEmpty)
        }
        XCTAssertFalse(fixture.hasNode("dashboard.data.cancel"))
        XCTAssertFalse(fixture.hasNode("dashboard.data.retry"))
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
    }

    func testInjectedDataInTheOrdinaryDashboardStillRespondsToExistingActivity() async throws {
        DashboardInteractionDiagnostics.recordBodyEntry(self)
        let harness = DemoDashboardDataHarness()
        let fixture = DemoDashboardDataFixture(
            model: harness.model, size: IntSize(width: 1280, height: 900), wholeRoot: true)
        defer {
            fixture.close()
            harness.close()
        }
        XCTAssertTrue(fixture.dashboard.dashboardData === harness.model)
        XCTAssertEqual(fixture.dashboard.interactionCount, 0)
        try fixture.activate("dashboard.data.refresh")
        try await harness.starts(1)
        try await harness.finish(
            0,
            bytes: dashboardDataJSON(day: [
                ["label": "First", "fraction": 0.5], ["label": "Peak", "fraction": 0.8],
            ]))
        fixture.render()
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("32"))
        let report = try harness.report()
        fixture.dashboard.performAction("Dashboard sample update")
        fixture.render()
        XCTAssertEqual(fixture.dashboard.interactionCount, 1)
        XCTAssertEqual(fixture.dashboard.lastAction, "Dashboard sample update")
        XCTAssertTrue(try fixture.texts(in: "dashboard.data.plot").contains("33"))
        XCTAssertEqual(
            harness.model.snapshot.content, .report(report), "Activity changes presentation, not decoded bytes")
        XCTAssertEqual(fixture.dashboard.displayName, "Operator")
        XCTAssertEqual(fixture.dashboard.selectedScreen, .dashboard)
        XCTAssertEqual(fixture.dashboard.selectedModule, .layout)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
        XCTAssertTrue(fixture.observedNotifications.contains(ObjectIdentifier(fixture.dashboard)))
    }
}

/// This immutable observer retains only the diagnostic writer, never a test case.
final class DashboardInteractionTraceObserver: XCTestObservation, Sendable {
    static let configured: DashboardInteractionTraceObserver? = {
        guard let writer = DashboardInteractionDiagnostics.writer else { return nil }
        return DashboardInteractionTraceObserver(writer: writer)
    }()

    private let writer: RetainedConstructionTraceWriter

    init(writer: RetainedConstructionTraceWriter) { self.writer = writer }

    func recordRegistered() { writer.record("observer.registered") }
    func recordRemoved() { writer.record("observer.removed") }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard testCase is DemoDashboardDataInteractionTests else { return }
        DashboardInteractionDiagnostics.recordCase("case.enter", testCase: testCase, writer: writer)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard testCase is DemoDashboardDataInteractionTests else { return }
        // This callback is an observation, not an assertion or passing test result.
        DashboardInteractionDiagnostics.recordCase("case.exit", testCase: testCase, writer: writer)
    }
}
