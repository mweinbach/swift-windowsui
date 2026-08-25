import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A compact window should reveal useful, actionable content rather than
/// spending its first screenful on oversized decorative surfaces.
@MainActor
final class DemoResponsiveProductPolishTests: XCTestCase {
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

    private func firstNode(in root: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) {
                return node
            }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func textNode(in root: ViewNode, _ value: String) -> ViewNode? {
        firstNode(in: root) { $0.text?.lowercased() == value.lowercased() }
    }

    private func absoluteY(of node: ViewNode) -> Double {
        var origin = node.resolvedFrame.origin.y
        var parent = node.parent
        while let ancestor = parent {
            origin += ancestor.resolvedFrame.origin.y
            parent = ancestor.parent
        }
        return origin
    }

    func testShortWindowsCompressPresentationWithoutChangingTheHeroContract() async {
        let compact = DemoLayout(size: WinSwiftUI.CGSize(width: 1280, height: 680))
        let spacious = DemoLayout(size: WinSwiftUI.CGSize(width: 1280, height: 900))

        XCTAssertTrue(compact.verticallyCompact)
        XCTAssertFalse(spacious.verticallyCompact)
        XCTAssertEqual(compact.heroHeight, 172)
        XCTAssertEqual(spacious.heroHeight, 172)
        XCTAssertLessThan(compact.presentationHeroHeight, spacious.presentationHeroHeight)
        XCTAssertLessThan(compact.heroContentPadding, spacious.heroContentPadding)
        XCTAssertLessThan(compact.chartPlotHeight, spacious.chartPlotHeight)
        XCTAssertLessThan(compact.chartCardPadding, spacious.chartCardPadding)
    }

    func testDefaultWindowShowsActivityAndItsMostRecentEvent() async {
        let model = DemoDashboardModel()
        let root = snapshotRoot(model: model)

        guard
            let heading = textNode(in: root, "Activity"),
            let latest = textNode(in: root, "System ready")
        else {
            return XCTFail("the dashboard should contain its activity feed and latest event")
        }

        XCTAssertLessThan(absoluteY(of: heading), 720, "the activity heading belongs above the fold")
        XCTAssertLessThan(
            absoluteY(of: latest) + latest.resolvedFrame.size.height,
            720,
            "at least the latest activity should be readable without scrolling"
        )
        XCTAssertNotNil(textNode(in: root, "3 recent"))
    }

    func testActivityPrecedesDetailsWhenTheRailFoldsIntoTheDashboard() async {
        let model = DemoDashboardModel()
        let root = snapshotRoot(model: model, size: IntSize(width: 900, height: 720))

        guard
            let activity = textNode(in: root, "Activity"),
            let details = textNode(in: root, "Detail track")
        else {
            return XCTFail("a folded dashboard should retain both activity and detail content")
        }

        XCTAssertLessThan(
            absoluteY(of: activity),
            absoluteY(of: details),
            "relocated rail cards must not bury the live activity feed"
        )
    }

    func testSettingsPrimaryActionIsImmediatelyAvailableAtMinimumWindowSize() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = snapshotRoot(model: model, size: IntSize(width: 640, height: 480))

        guard
            let save = textNode(in: root, "Save Settings"),
            let profile = textNode(in: root, "Profile")
        else {
            return XCTFail("the settings header should expose its primary action")
        }

        XCTAssertLessThan(
            absoluteY(of: save),
            absoluteY(of: profile),
            "saving belongs in the visible page header, ahead of scrolling settings groups"
        )

        let matchingButtons = firstNode(in: root) {
            $0.text == "Save Settings" && $0.textStyle.nativeFontSize != nil
        }
        XCTAssertNotNil(matchingButtons)
    }

    func testCompactSettingsRevealTheResourceGroupInAStandardWindow() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .settings
        let root = snapshotRoot(model: model)

        guard
            let resources = textNode(in: root, "Resources"),
            let storage = textNode(in: root, "Storage Used"),
            let sync = textNode(in: root, "Sync Progress")
        else {
            return XCTFail("the settings pane should retain its resource controls")
        }

        XCTAssertLessThan(absoluteY(of: resources), 720)
        XCTAssertLessThan(absoluteY(of: storage), 720)
        XCTAssertLessThan(
            absoluteY(of: sync) + sync.resolvedFrame.size.height,
            720,
            "denser settings rows should keep both resource meters readable above the fold"
        )
    }
}
