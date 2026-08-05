import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A tab switch dissolves; it does not cut.
///
/// Found in pixels, not in a counter. A live motion capture of the demo
/// (`--diagnostics-capture-motion`, see `docs/Testing.md`) switching screens
/// showed one frame in which 92 % of the window changed, with twenty
/// byte-identical frames after it and nothing in flight on either side. Every
/// animation test in the suite passed while that was true, because the
/// switch installed no animation for one to observe: `TabView` built the
/// selected page as an untagged child, the reconciler matched the outgoing
/// page to the incoming one by position, and rewrote it in place.
@MainActor
final class TabPageCrossfadeTests: XCTestCase {

    private struct TabHarness {
        let runtime: RetainedViewRuntime
        /// Retained deliberately: the invalidate handler holds the host
        /// weakly, so a harness that dropped it would never rebuild.
        let host: ComponentHost
        let selectSecondTab: () -> Void
        /// The node carrying the page for a given tab index, if it is still
        /// in the retained tree.
        let page: (Int) -> ViewNode?
    }

    private func findNode(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findNode(child, where: predicate) { return found }
        }
        return nil
    }

    private func makeTabView() -> TabHarness {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        var selection = 0
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                TabView(selection: Binding(get: { selection }, set: { selection = $0 })) {
                    Text("FIRST PAGE")
                        .tabItem { Text("One") }
                        .tag(0)
                    Text("SECOND PAGE")
                        .tabItem { Text("Two") }
                        .tag(1)
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()

        return TabHarness(
            runtime: runtime,
            host: host,
            selectSecondTab: {
                selection = 1
                host.reload()
            },
            page: { index in
                self.findNode(runtime.root, where: { $0.nodeTag == "tabview-page:\(index)" })
            }
        )
    }

    /// The page that arrives starts transparent and works its way up, rather
    /// than appearing at full opacity on the frame the selection changed.
    func testTheIncomingPageFadesInRatherThanAppearingWhole() async {
        let harness = makeTabView()
        XCTAssertNotNil(harness.page(0), "the first tab's page must be tagged with its index")

        harness.selectSecondTab()
        guard let incoming = harness.page(1) else {
            return XCTFail("selecting the second tab must build a page tagged for it")
        }
        XCTAssertNil(harness.page(0), "the outgoing page leaves the retained tree")

        XCTAssertLessThan(
            incoming.opacity, 0.5,
            "the incoming page starts near transparent, not whole: \(incoming.opacity)")

        var clock = Win32Window.currentTimestampSeconds()
        var sampled: [Double] = []
        for _ in 0..<24 {
            clock += 1.0 / 60.0
            _ = harness.runtime.tickAnimations(at: clock)
            sampled.append(harness.page(1)?.opacity ?? -1)
        }

        let intermediate = sampled.filter { $0 > 0.05 && $0 < 0.95 }
        XCTAssertGreaterThanOrEqual(
            intermediate.count, 3,
            "the page has to be drawn part-way in, not switched on: \(sampled)")
        XCTAssertEqual(sampled.last ?? -1, 1.0, accuracy: 0.01, "and it arrives at full opacity")
        XCTAssertTrue(
            zip(sampled, sampled.dropFirst()).allSatisfy { $1 >= $0 - 0.001 },
            "the fade is monotonic across its span: \(sampled)")
    }

    /// The other half of a cross-fade: the page that leaves is still on
    /// screen, fading, while the new one comes up. Without this the switch is
    /// a fade-in over an empty window rather than a dissolve.
    func testTheOutgoingPageStaysOnScreenAsAFadingOverlay() async {
        let harness = makeTabView()
        harness.selectSecondTab()

        let overlays = harness.runtime.transitionOverlays
        XCTAssertEqual(
            overlays.count, 1,
            "the outgoing page becomes exactly one removal overlay")
        guard let outgoing = overlays.first else { return }
        XCTAssertEqual(
            outgoing.nodeTag, "tabview-page:0",
            "and the overlay is the page that was selected before")

        var clock = Win32Window.currentTimestampSeconds()
        var sampled: [Double] = []
        for _ in 0..<24 {
            clock += 1.0 / 60.0
            _ = harness.runtime.tickAnimations(at: clock)
            sampled.append(outgoing.opacity)
        }

        let intermediate = sampled.filter { $0 > 0.05 && $0 < 0.95 }
        XCTAssertGreaterThanOrEqual(
            intermediate.count, 3,
            "the outgoing page is drawn part-way out: \(sampled)")
        XCTAssertTrue(
            zip(sampled, sampled.dropFirst()).allSatisfy { $1 <= $0 + 0.001 },
            "and it only ever fades down: \(sampled)")
        XCTAssertTrue(
            harness.runtime.transitionOverlays.isEmpty,
            "the overlay is retired once its fade completes")
    }

    /// A state change on the page that is already showing is not a
    /// transition either — including after a switch has just happened.
    ///
    /// Caught in the motion capture, not in a counter: pressing a button on
    /// the freshly-switched-to screen dropped the whole page to near-zero
    /// opacity and faded it in again, so a button press read as a second
    /// screen switch. The page had not been marked as having appeared, and
    /// `applyNewNodeTransitionsRecursively` re-seeds an insertion transition
    /// on anything that has not.
    func testRebuildingAfterASwitchDoesNotReplayTheFade() async {
        let harness = makeTabView()
        harness.selectSecondTab()

        var clock = Win32Window.currentTimestampSeconds()
        for _ in 0..<24 {
            clock += 1.0 / 60.0
            _ = harness.runtime.tickAnimations(at: clock)
        }
        _ = harness.runtime.renderFrame()
        XCTAssertEqual(
            harness.page(1)?.opacity ?? -1, 1.0, accuracy: 0.001,
            "the switch finished with the page whole")

        // A plain rebuild, as any `@State` change on the page produces.
        harness.host.reload()

        XCTAssertEqual(
            harness.page(1)?.opacity ?? -1, 1.0, accuracy: 0.001,
            "a rebuild of the showing page must not restart its fade")
        XCTAssertTrue(
            harness.runtime.transitionOverlays.isEmpty,
            "and must not make a second removal overlay")
    }

    /// Re-selecting the tab that is already showing is not a transition. A
    /// rebuild triggered by anything else — a `@State` change on the page —
    /// must not dissolve the window.
    func testRebuildingWithoutChangingTabsPlaysNoTransition() async {
        let harness = makeTabView()
        harness.host.reload()

        XCTAssertTrue(
            harness.runtime.transitionOverlays.isEmpty,
            "a rebuild that does not change the selection leaves no overlay")
        XCTAssertEqual(
            harness.page(0)?.opacity ?? -1, 1.0, accuracy: 0.001,
            "and the showing page stays whole")
    }
}
