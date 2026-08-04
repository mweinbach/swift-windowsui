import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// A `GeometryReader` is supposed to report the slot it actually occupies.
/// Build order cannot know that slot — the reader's siblings have not been
/// measured yet — so the reader seeds its body with the canvas and the
/// runtime re-invokes the body once the layout has resolved its frame.
/// These tests pin the resolved half: what the body was *finally* built
/// with, read back off the retained tree after a render.
@MainActor
private func windowContent<V: View>(
    _ view: V,
    size: Size = Size(width: 1000, height: 600)
) -> (runtime: RetainedViewRuntime, node: ViewNode) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
    return (runtime, node)
}

@MainActor
private func firstText(in node: ViewNode, matching prefix: String) -> String? {
    if let text = node.text, text.hasPrefix(prefix) {
        return text
    }
    for child in node.children {
        if let match = firstText(in: child, matching: prefix) {
            return match
        }
    }
    return nil
}

/// Renders `proxy.size` into a probe string the tests can read back off the
/// retained tree, so the assertion sees the body the runtime finally kept
/// rather than whichever one happened to fire an `onAppear`.
@MainActor
private func sizeProbe(_ proxy: GeometryProxy) -> Text {
    Text("SLOT \(Int(proxy.size.width.rounded())) \(Int(proxy.size.height.rounded()))")
}

final class GeometryReaderSlotTests: XCTestCase {

    func testReaderAloneStillReportsTheWholeCanvas() async {
        await MainActor.run {
            let (_, node) = windowContent(
                GeometryReader { proxy in
                    sizeProbe(proxy)
                }
            )

            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 1000 600")
        }
    }

    /// The reported height comes off the header, and off nothing else: the
    /// reader is the only flexible child, so its slot is the window minus the
    /// header and the stack spacing.
    func testReaderUnderAStackReportsItsResolvedSlotNotTheCanvas() async {
        await MainActor.run {
            let (_, node) = windowContent(
                VStack(spacing: 0) {
                    Color.red.frame(height: 100)
                    GeometryReader { proxy in
                        sizeProbe(proxy)
                    }
                }
            )

            let readerNode = node.children[1]
            XCTAssertEqual(readerNode.resolvedFrame.size.height, 500, accuracy: 0.5)
            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 1000 500")
        }
    }

    func testReaderBesideASidebarReportsTheNarrowedWidth() async {
        await MainActor.run {
            let (_, node) = windowContent(
                HStack(spacing: 0) {
                    Color.red.frame(width: 240)
                    GeometryReader { proxy in
                        sizeProbe(proxy)
                    }
                }
            )

            let readerNode = node.children[1]
            XCTAssertEqual(readerNode.resolvedFrame.size.width, 760, accuracy: 0.5)
            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 760 600")
        }
    }

    /// Nested readers each converge to their own slot in the same frame: the
    /// outer one narrows, and the inner one sees the narrowed result rather
    /// than either the canvas or a half-resolved intermediate.
    func testNestedReadersEachReportTheirOwnSlot() async {
        await MainActor.run {
            let (_, node) = windowContent(
                VStack(spacing: 0) {
                    Color.red.frame(height: 100)
                    GeometryReader { outer in
                        VStack(spacing: 0) {
                            Color.blue.frame(height: 50)
                            GeometryReader { inner in
                                Text(
                                    "INNER \(Int(outer.size.height.rounded())) "
                                        + "\(Int(inner.size.height.rounded()))"
                                )
                            }
                        }
                    }
                }
            )

            XCTAssertEqual(firstText(in: node, matching: "INNER"), "INNER 500 450")
        }
    }

    /// Convergence, not oscillation: a second render of an unchanged tree
    /// re-uses the body the first one settled on and does not rebuild it.
    func testResolvedSlotIsStableAcrossRenders() async {
        await MainActor.run {
            let (runtime, node) = windowContent(
                VStack(spacing: 0) {
                    Color.red.frame(height: 100)
                    GeometryReader { proxy in
                        sizeProbe(proxy)
                    }
                }
            )

            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 1000 500")
            let settledResolveCount = runtime.geometryReaderResolveCount
            XCTAssertGreaterThan(settledResolveCount, 0)

            // Re-lay out the same tree from scratch: the reader is already on
            // its slot, so the loop must find nothing to do.
            node.children[0].backgroundColor = .green
            _ = runtime.renderFrame()

            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 1000 500")
            XCTAssertEqual(runtime.geometryReaderResolveCount, settledResolveCount)
        }
    }

    /// The case the loop guard exists for: along a scroll axis the proposal is
    /// unbounded, so the reader's slot can depend on the body its own proxy
    /// produced. It has to settle on *something* finite in a bounded number of
    /// rounds rather than ping-pong, and the cross axis — which is bounded —
    /// still has to come out right.
    func testReaderInsideAScrollViewSettlesWithoutRunningTheLoopOut() async {
        await MainActor.run {
            let (runtime, node) = windowContent(
                ScrollView {
                    GeometryReader { proxy in
                        sizeProbe(proxy)
                    }
                }
            )

            let settled = firstText(in: node, matching: "SLOT")
            XCTAssertNotNil(settled)
            XCTAssertTrue(settled?.hasPrefix("SLOT 1000 ") == true, "cross axis kept its bound: \(settled ?? "-")")

            let settledResolveCount = runtime.geometryReaderResolveCount
            _ = runtime.renderFrame()
            XCTAssertEqual(firstText(in: node, matching: "SLOT"), settled)
            XCTAssertEqual(runtime.geometryReaderResolveCount, settledResolveCount)
        }
    }

    /// A window resize moves the slot, so the body follows it.
    func testResizeMovesTheReportedSlot() async {
        await MainActor.run {
            let (runtime, node) = windowContent(
                VStack(spacing: 0) {
                    Color.red.frame(height: 100)
                    GeometryReader { proxy in
                        sizeProbe(proxy)
                    }
                }
            )

            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 1000 500")

            runtime.setRootSize(IntSize(width: 800, height: 400))
            _ = runtime.renderFrame()

            XCTAssertEqual(firstText(in: node, matching: "SLOT"), "SLOT 800 300")
        }
    }
}
