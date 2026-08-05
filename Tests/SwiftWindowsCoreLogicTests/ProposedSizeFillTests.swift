import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// Builds `view` as the window's content view: the node is attached to a
/// root sized like a window and laid out, with no explicit frame of its own.
/// This is the geometry a real host produces, so a view that refuses to fill
/// shows up here as a node smaller than the window.
@MainActor
private func layoutAsWindowContent<V: View>(
    _ view: V,
    size: Size = Size(width: 1280, height: 720)
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
private func firstNode(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
    if predicate(node) {
        return node
    }
    for child in node.children {
        if let match = firstNode(in: child, where: predicate) {
            return match
        }
    }
    return nil
}

@MainActor
private func allNodes(in node: ViewNode, where predicate: (ViewNode) -> Bool) -> [ViewNode] {
    var matches: [ViewNode] = []
    if predicate(node) {
        matches.append(node)
    }
    for child in node.children {
        matches.append(contentsOf: allNodes(in: child, where: predicate))
    }
    return matches
}

/// Greedy ("fill") sizing: the runtime's model of SwiftUI's size proposal.
///
/// Before this existed every container shrink-wrapped its content, so an
/// idiomatic screen (NavigationStack > ScrollView > Form) occupied a third
/// of the window and the rest of the canvas was clear colour.
final class ProposedSizeFillTests: XCTestCase {

    // MARK: - The runtime primitive

    func testGreedyNodeTakesTheProposalOnBothAxes() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let content = Controls.panel(backgroundColor: .white)
            content.layoutFillAxes = .both
            runtime.root.addChild(content)
            runtime.setRootSize(IntSize(width: 1280, height: 720))
            _ = runtime.renderFrame()

            XCTAssertEqual(content.resolvedFrame.size.width, 1280, accuracy: 0.001)
            XCTAssertEqual(content.resolvedFrame.size.height, 720, accuracy: 0.001)
        }
    }

    func testGreedyNodeKeepsIntrinsicSizeUnderAnUnconstrainedProposal() async {
        await MainActor.run {
            let node = Controls.panel(preferredSize: Size(width: 200, height: 28))
            node.layoutFillAxes = .both

            // An intrinsic query has no proposal to accept, so a greedy node
            // reports its ideal rather than an infinite extent.
            let intrinsic = node.intrinsicContentSize()
            XCTAssertEqual(intrinsic.width, 200, accuracy: 0.001)
            XCTAssertEqual(intrinsic.height, 28, accuracy: 0.001)
        }
    }

    func testExplicitFrameBeatsFill() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let content = Controls.panel(frame: Rect(x: 0, y: 0, width: 120, height: 40))
            content.layoutFillAxes = .both
            runtime.root.addChild(content)
            runtime.setRootSize(IntSize(width: 1280, height: 720))
            _ = runtime.renderFrame()

            XCTAssertEqual(content.resolvedFrame.size.width, 120, accuracy: 0.001)
            XCTAssertEqual(content.resolvedFrame.size.height, 40, accuracy: 0.001)
        }
    }

    func testGreedyChildGrowsIntoAStacksLeftoverMainExtent() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let header = Controls.panel(preferredSize: Size(width: 0, height: 40), backgroundColor: .white)
            let body = Controls.panel(backgroundColor: .white)
            body.layoutFillAxes = .both
            let stack = Controls.stackPanel(
                stackLayout: .vertical(spacing: 0, alignment: .stretch),
                children: [header, body]
            )
            stack.layoutFillAxes = .both
            runtime.root.addChild(stack)
            runtime.setRootSize(IntSize(width: 400, height: 300))
            _ = runtime.renderFrame()

            XCTAssertEqual(header.resolvedFrame.size.height, 40, accuracy: 0.001)
            XCTAssertEqual(body.resolvedFrame.size.height, 260, accuracy: 0.001)
        }
    }

    func testOverSubscribedTrackShrinksTheGreedyChildBeforeItsSiblings() async {
        await MainActor.run {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let chrome = Controls.panel(preferredSize: Size(width: 0, height: 60), backgroundColor: .white)
            // A scroll view whose content is taller than the window: it asks
            // for the whole track and then some.
            let scroller = Controls.scrollPanel(
                axis: .vertical,
                stackLayout: .vertical(spacing: 0, alignment: .stretch),
                children: [Controls.panel(preferredSize: Size(width: 0, height: 900), backgroundColor: .white)]
            )
            scroller.layoutFillAxes = .both
            let stack = Controls.stackPanel(
                stackLayout: .vertical(spacing: 0, alignment: .stretch),
                children: [chrome, scroller]
            )
            stack.layoutFillAxes = .both
            runtime.root.addChild(stack)
            runtime.setRootSize(IntSize(width: 400, height: 300))
            _ = runtime.renderFrame()

            // The chrome keeps its metrics; the scroller absorbs the squeeze.
            XCTAssertEqual(chrome.resolvedFrame.size.height, 60, accuracy: 0.001)
            XCTAssertEqual(scroller.resolvedFrame.size.height, 240, accuracy: 0.001)
        }
    }

    // MARK: - The SwiftUI surface

    func testFrameMaxWidthInfinityTakesTheProposedWidth() async {
        await MainActor.run {
            let (_, node) = layoutAsWindowContent(
                Text("HELLO").frame(maxWidth: .infinity),
                size: Size(width: 600, height: 200)
            )

            XCTAssertEqual(node.resolvedFrame.size.width, 600, accuracy: 0.001)
            // Vertical stays intrinsic: only the axis given `.infinity` fills.
            XCTAssertLessThan(node.resolvedFrame.size.height, 200)
        }
    }

    func testScrollViewFillsTheWindowAndProposesItsViewportToContent() async {
        await MainActor.run {
            let (_, node) = layoutAsWindowContent(
                ScrollView {
                    Text("ROW ONE")
                    Text("ROW TWO")
                },
                size: Size(width: 800, height: 400)
            )

            XCTAssertEqual(node.resolvedFrame.size.width, 800, accuracy: 0.001)
            XCTAssertEqual(node.resolvedFrame.size.height, 400, accuracy: 0.001)
            // Content is proposed the viewport width, not left at its
            // intrinsic advance box with the scroller stranded to its right.
            for row in node.children {
                XCTAssertEqual(row.resolvedFrame.size.width, 800, accuracy: 0.001)
            }
        }
    }

    func testListFillsTheWindow() async {
        await MainActor.run {
            let (_, node) = layoutAsWindowContent(
                List {
                    Text("ONE")
                    Text("TWO")
                },
                size: Size(width: 800, height: 400)
            )

            XCTAssertEqual(node.resolvedFrame.size.width, 800, accuracy: 0.001)
            XCTAssertEqual(node.resolvedFrame.size.height, 400, accuracy: 0.001)
        }
    }

    func testNavigationStackFillsTheWindow() async {
        await MainActor.run {
            let (_, node) = layoutAsWindowContent(
                NavigationStack {
                    Text("BODY")
                        .navigationTitle("TITLE")
                },
                size: Size(width: 900, height: 500)
            )

            XCTAssertEqual(node.resolvedFrame.size.width, 900, accuracy: 0.001)
            XCTAssertEqual(node.resolvedFrame.size.height, 500, accuracy: 0.001)
        }
    }

    func testTabViewChromeIsIndependentOfTheSelectedPagesWidth() async {
        await MainActor.run {
            let narrow = layoutAsWindowContent(
                TabView {
                    Text("N").tabItem { Text("ONE") }
                },
                size: Size(width: 1000, height: 600)
            )
            let wide = layoutAsWindowContent(
                TabView {
                    Text(String(repeating: "WIDE ", count: 40)).tabItem { Text("ONE") }
                },
                size: Size(width: 1000, height: 600)
            )

            XCTAssertEqual(narrow.node.resolvedFrame.size.width, 1000, accuracy: 0.001)
            XCTAssertEqual(wide.node.resolvedFrame.size.width, 1000, accuracy: 0.001)
            // The bar band spans the window in both cases, so the tab
            // geometry no longer depends on which page is selected.
            XCTAssertEqual(
                narrow.node.children[0].resolvedFrame.size.width,
                wide.node.children[0].resolvedFrame.size.width,
                accuracy: 0.001
            )
        }
    }

    func testTabViewPageCanvasExcludesTheTabBand() async {
        await MainActor.run {
            var reported = Size.zero
            let (_, node) = layoutAsWindowContent(
                TabView {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                reported = proxy.size
                            }
                    }
                    .tabItem { Text("ONE") }
                },
                size: Size(width: 1000, height: 600)
            )

            let pageHeight = node.children[1].resolvedFrame.size.height
            XCTAssertGreaterThan(pageHeight, 0)
            // A reader inside the page is told the page's slot, not the whole
            // window, so a page laid out from the proxy stops running off the
            // bottom edge by exactly the chrome height.
            XCTAssertLessThan(reported.height, 600)
            XCTAssertEqual(reported.height, pageHeight, accuracy: 1.0)
            XCTAssertEqual(reported.width, 1000, accuracy: 0.001)
        }
    }

    /// A `Color` accepts whatever it is proposed on both axes. That is the
    /// whole of its layout behaviour in SwiftUI and it is what makes
    /// `Color.red.frame(height: 1)` a hairline rather than an invisible node:
    /// the frame pins the height and the colour takes the width.
    ///
    /// It measured its own (nonexistent) intrinsic width instead, so every
    /// rule the app drew this way was in the tree at 0pt wide and painted
    /// nothing — the settings row rules, the data table row rules and the
    /// hero's lit top edge were all present, laid out, and invisible.
    func testAColourTakesTheWidthItIsProposed() async {
        await MainActor.run {
            let (_, node) = layoutAsWindowContent(
                VStack(alignment: .leading, spacing: 0) {
                    Text("A row of content")
                    Color.red.frame(height: 1).frame(maxWidth: .infinity)
                },
                size: Size(width: 600, height: 200)
            )

            guard let rule = firstNode(in: node, where: { $0.backgroundColor?.red == 1 }) else {
                return XCTFail("Expected the rule to be in the tree")
            }
            XCTAssertEqual(rule.resolvedFrame.size.height, 1, accuracy: 0.001)
            XCTAssertEqual(rule.resolvedFrame.size.width, 600, accuracy: 0.001)
        }
    }

    /// An explicit width is the author's answer and ends the greed: a colour
    /// used as a fixed spacer stays the size it was asked for.
    func testAColourWithAStatedWidthDoesNotGrow() async {
        await MainActor.run {
            let (_, node) = layoutAsWindowContent(
                HStack(alignment: .center, spacing: 0) {
                    Color(red: 0, green: 1, blue: 0, alpha: 1).frame(width: 8, height: 8)
                    Text("Beside it")
                },
                size: Size(width: 600, height: 200)
            )

            guard let swatch = firstNode(in: node, where: { $0.backgroundColor?.green == 1 }) else {
                return XCTFail("Expected the swatch to be in the tree")
            }
            XCTAssertEqual(swatch.resolvedFrame.size.width, 8, accuracy: 0.001)
            XCTAssertEqual(swatch.resolvedFrame.size.height, 8, accuracy: 0.001)
        }
    }
}
