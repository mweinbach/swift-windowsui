import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Product controls should change the content they describe without moving
/// the default visual baseline or compromising the minimum supported window.
@MainActor
final class DemoProductPolishTests: XCTestCase {
    private func snapshotRoot(
        model: DemoDashboardModel,
        size: IntSize = IntSize(width: 1280, height: 720)
    ) -> ViewNode {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model),
            size: size,
            displayScale: 1,
            colorScheme: .dark
        ).runtime.root
    }

    private func firstNode(
        in root: ViewNode,
        matching predicate: (ViewNode) -> Bool
    ) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func absoluteX(of node: ViewNode) -> Double {
        var origin = node.resolvedFrame.origin.x
        var parent = node.parent
        while let ancestor = parent {
            origin += ancestor.resolvedFrame.origin.x
            parent = ancestor.parent
        }
        return origin
    }

    func testSettingsColumnShrinksAtMinimumWidthAndKeepsItsWideBaseline() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings

        let narrow = snapshotRoot(model: model, size: IntSize(width: 640, height: 480))
        guard
            let narrowField = firstNode(
                in: narrow,
                matching: { $0.accessibilityLabel == "Display Name" && $0.isFocusable }
            )
        else {
            return XCTFail("the minimum-size settings pane should contain its profile field")
        }

        let narrowTrailingEdge = absoluteX(of: narrowField) + narrowField.resolvedFrame.size.width
        XCTAssertLessThanOrEqual(
            narrowTrailingEdge, 640 - DemoMetrics.s6,
            "the trailing settings control must remain inside the minimum-width page margin"
        )

        let wide = snapshotRoot(model: model)
        guard
            let wideField = firstNode(
                in: wide,
                matching: { $0.accessibilityLabel == "Display Name" && $0.isFocusable }
            )
        else {
            return XCTFail("the normal-size settings pane should contain its profile field")
        }

        let wideTrailingEdge = absoluteX(of: wideField) + wideField.resolvedFrame.size.width
        XCTAssertGreaterThan(
            wideTrailingEdge, 700,
            "a flexible maximum must retain the existing 720-point settings column"
        )
        XCTAssertLessThanOrEqual(
            wideTrailingEdge, DemoMetrics.s6 + DemoMetrics.settingsColumnWidth,
            "the settings column remains leading-anchored at its original maximum width"
        )
    }

    func testEveryChartPeriodUsesItsOwnStableSeriesAndDescription() async {
        let legacyDaily = DemoChartCard.bars(interactions: 0)
        let daily = DemoChartCard.bars(interactions: 0, range: .day)
        let weekly = DemoChartCard.bars(interactions: 0, range: .week)
        let monthly = DemoChartCard.bars(interactions: 0, range: .all)

        XCTAssertEqual(legacyDaily, daily, "the original daily-series API and screenshot stay unchanged")
        XCTAssertEqual(daily.count, 10)
        XCTAssertEqual(daily.map(\.label), (1...10).map(String.init))
        XCTAssertEqual(DemoChartRange.day.subtitle, "Draw calls per frame — last 10 frames")

        XCTAssertEqual(weekly.count, 7)
        XCTAssertEqual(weekly.map(\.label), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(DemoChartRange.week.subtitle, "Draw calls per frame — last 7 days")

        XCTAssertEqual(monthly.count, 12)
        XCTAssertEqual(monthly.first?.label, "Jan")
        XCTAssertEqual(monthly.last?.label, "Dec")
        XCTAssertEqual(DemoChartRange.all.subtitle, "Draw calls per frame — last 12 months")

        XCTAssertNotEqual(daily.first?.value, weekly.first?.value)
        XCTAssertNotEqual(weekly.first?.value, monthly.first?.value)
    }

    func testChartPeriodsRemainDeterministicWhileInteractionDataChanges() async {
        for range in DemoChartRange.allCases {
            let first = DemoChartCard.bars(interactions: 3, range: range)
            let repeated = DemoChartCard.bars(interactions: 3, range: range)
            let updated = DemoChartCard.bars(interactions: 4, range: range)

            XCTAssertEqual(first, repeated, "\(range) should produce stable screenshots")
            XCTAssertNotEqual(first, updated, "\(range) should still react to dashboard activity")
        }
    }

    func testDefaultPageShowsEveryExistingComponent() async {
        let model = DemoDashboardModel()

        XCTAssertEqual(model.itemsPerPage, 10)
        XCTAssertEqual(model.displayedComponents, model.components)
    }

    func testPageSizeLimitsVisibleRowsAndPreservesAVisibleSelection() async {
        let model = DemoDashboardModel()
        model.selectedComponentID = model.components.last?.id

        model.itemsPerPage = 5

        XCTAssertEqual(model.displayedComponents, Array(model.components.prefix(5)))
        XCTAssertEqual(
            model.selectedComponentID, model.components.first?.id,
            "an inspector cannot retain a selection hidden by the new page limit"
        )

        model.itemsPerPage = 0
        XCTAssertEqual(model.displayedComponents.count, 1, "transient numeric edits should not empty the table")
    }

    func testFilteringFindsComponentsOutsideTheUnfilteredFirstPage() async {
        let model = DemoDashboardModel()
        model.itemsPerPage = 5

        model.componentFilter = "system probe"

        XCTAssertEqual(model.filteredComponents.map(\.name), ["System probe"])
        XCTAssertEqual(model.displayedComponents.map(\.name), ["System probe"])
        XCTAssertEqual(model.selectedComponent?.name, "System probe")

        model.clearComponentFilter()
        XCTAssertEqual(model.displayedComponents.count, 5)
        XCTAssertEqual(model.selectedComponentID, model.components.first?.id)
    }

    func testDataTableRendersOnlyTheConfiguredPageAndReportsItsCount() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .data
        model.itemsPerPage = 5

        let root = snapshotRoot(model: model)
        XCTAssertNotNil(firstNode(in: root, matching: { $0.text == "5 of 8 components" }))

        for component in model.components.prefix(5) {
            XCTAssertNotNil(
                firstNode(in: root, matching: { $0.text == component.name }),
                "\(component.name) belongs to the visible page"
            )
        }

        for component in model.components.dropFirst(5) {
            XCTAssertNil(
                firstNode(in: root, matching: { $0.text == component.name }),
                "\(component.name) should not render beyond the configured page size"
            )
        }
    }

    func testPaginationReachesEveryComponentAndKeepsSelectionVisible() async {
        let model = DemoDashboardModel()
        model.itemsPerPage = 5

        XCTAssertEqual(model.componentPageCount, 2)
        XCTAssertFalse(model.hasPreviousComponentPage)
        XCTAssertTrue(model.hasNextComponentPage)
        XCTAssertEqual(model.componentPageSummary, "Showing 1–5 of 8")

        model.selectNextComponentPage()

        XCTAssertEqual(model.componentPage, 1)
        XCTAssertEqual(model.displayedComponents, Array(model.components.dropFirst(5)))
        XCTAssertEqual(model.selectedComponentID, model.components[5].id)
        XCTAssertTrue(model.hasPreviousComponentPage)
        XCTAssertFalse(model.hasNextComponentPage)
        XCTAssertEqual(model.componentPageSummary, "Showing 6–8 of 8")

        model.selectNextComponentPage()
        XCTAssertEqual(model.componentPage, 1, "the final page cannot advance past the available rows")

        model.selectPreviousComponentPage()
        XCTAssertEqual(model.componentPage, 0)
        XCTAssertEqual(model.selectedComponentID, model.components.first?.id)
    }

    func testChangingFilterReturnsToItsFirstAvailablePage() async {
        let model = DemoDashboardModel()
        model.itemsPerPage = 5
        model.selectNextComponentPage()

        model.componentFilter = "router"

        XCTAssertEqual(model.componentPage, 0)
        XCTAssertEqual(model.componentPageCount, 1)
        XCTAssertEqual(model.displayedComponents.map(\.name), ["Input router"])
        XCTAssertEqual(model.selectedComponent?.name, "Input router")

        model.clearComponentFilter()
        XCTAssertEqual(model.componentPage, 0)
        XCTAssertEqual(model.componentPageCount, 2)
        XCTAssertEqual(
            model.selectedComponent?.name, "Input router",
            "clearing a filter should preserve a selection that is still visible on the first page"
        )
    }

    func testChangingPageSizeClampsTheCurrentPageWithoutHidingItsSelection() async {
        let model = DemoDashboardModel()
        model.itemsPerPage = 5
        model.selectNextComponentPage()

        model.itemsPerPage = 10

        XCTAssertEqual(model.componentPage, 0)
        XCTAssertEqual(model.componentPageCount, 1)
        XCTAssertEqual(model.displayedComponents, model.components)
        XCTAssertEqual(model.selectedComponentID, model.components[5].id)
    }

    func testPaginationControlsOnlyRenderWhenAdditionalPagesExist() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .data

        let normalRoot = snapshotRoot(model: model)
        XCTAssertNil(firstNode(in: normalRoot, matching: { $0.text == "Next" }))
        XCTAssertNil(firstNode(in: normalRoot, matching: { $0.text == "Previous" }))

        model.itemsPerPage = 5
        let paginatedRoot = snapshotRoot(model: model)
        XCTAssertNotNil(firstNode(in: paginatedRoot, matching: { $0.text == "Showing 1–5 of 8" }))
        XCTAssertNotNil(firstNode(in: paginatedRoot, matching: { $0.text == "Page 1 of 2" }))
        XCTAssertNotNil(firstNode(in: paginatedRoot, matching: { $0.text == "Next" }))
        XCTAssertNotNil(firstNode(in: paginatedRoot, matching: { $0.text == "Previous" }))

        model.selectNextComponentPage()
        let finalRoot = snapshotRoot(model: model)
        XCTAssertNotNil(firstNode(in: finalRoot, matching: { $0.text == "Showing 6–8 of 8" }))
        XCTAssertNotNil(firstNode(in: finalRoot, matching: { $0.text == "Page 2 of 2" }))
        XCTAssertNotNil(firstNode(in: finalRoot, matching: { $0.text == "System probe" }))
        XCTAssertNil(firstNode(in: finalRoot, matching: { $0.text == "Render host" }))
    }

    func testRestartActuallyRecoversADegradedComponent() async {
        let model = DemoDashboardModel()
        guard let degraded = model.components.first(where: { !$0.isHealthy }) else {
            return XCTFail("the default data set should include a degraded diagnostic target")
        }
        model.selectedComponentID = degraded.id

        model.restartSelectedComponent()

        guard let restarted = model.selectedComponent else {
            return XCTFail("restarting an unfiltered component should preserve its selection")
        }
        XCTAssertEqual(restarted.id, degraded.id)
        XCTAssertTrue(restarted.isHealthy)
        XCTAssertLessThan(restarted.load, degraded.load)
        XCTAssertEqual(restarted.statusLabel, "Healthy")
        XCTAssertEqual(model.lastAction, "Restarted \(degraded.name)")
    }

    func testRestartUpdatesStatusFilteredResultsAndInspectorSelection() async {
        let model = DemoDashboardModel()
        model.componentFilter = "degraded"
        XCTAssertEqual(model.displayedComponents.map(\.name), ["System probe"])

        model.restartSelectedComponent()

        XCTAssertTrue(model.filteredComponents.isEmpty)
        XCTAssertTrue(model.displayedComponents.isEmpty)
        XCTAssertNil(model.selectedComponent)
        XCTAssertEqual(model.componentPageSummary, "No components")

        model.clearComponentFilter()
        XCTAssertTrue(model.components.allSatisfy(\.isHealthy))
    }
}
