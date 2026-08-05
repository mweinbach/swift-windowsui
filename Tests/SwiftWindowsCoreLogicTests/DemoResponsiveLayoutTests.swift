// Not `import Foundation`: corelibs-Foundation exports its own CG geometry
// types, and `DemoLayout` is written against the stack's. See the same note at
// the top of `DemoDashboard.swift`.
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

// L7-ADAPT: the dashboard shell at every window size it can be dragged to.
//
// The shell laid out three columns at fixed widths whose sum never consulted
// the window. At 640 pt of window they asked for 964 pt; the layout engine
// answered the overflow the only way it can, by driving all three columns past
// their shrink floors, and the window filled with ellipses — "WinSwi…",
// "D3…", "Even…", "Animat…", "Inspect…" — beside a hero card whose two action
// pills had been squeezed from 38 pt tall to about 2. A column that does not
// fit is now dropped and its content moves into the column that remains.
@MainActor
final class DemoResponsiveLayoutTests: XCTestCase {

    private static let sweptWidths: [WinSwiftUI.CGFloat] = [
        640, 641, 688, 689, 690, 691, 760, 800, 900, 962, 963, 964, 965, 1024,
        1100, 1179, 1180, 1181, 1280, 1440, 1600, 1720, 1920, 2560,
    ]
    private static let sweptHeights: [WinSwiftUI.CGFloat] = [408, 480, 600, 648, 720, 760, 908, 980, 1400]

    // MARK: - The invariant that was violated

    /// Whatever the shell decides to show has to fit inside the window. This
    /// is the property the fixed-width three-column layout broke, and it is
    /// the reason every label in a narrow window truncated.
    func testColumnsNeverAskForMoreWidthThanTheWindowHas() async {
        await MainActor.run {
            for width in Self.sweptWidths {
                for height in Self.sweptHeights {
                    let layout = DemoLayout(size: WinSwiftUI.CGSize(width: width, height: height))
                    XCTAssertLessThanOrEqual(
                        layout.occupiedWidth, width,
                        "\(Int(width))x\(Int(height)): columns ask for \(layout.occupiedWidth) pt of a "
                            + "\(width) pt window, so the layout engine has to shrink them past their floors."
                    )
                    XCTAssertGreaterThanOrEqual(
                        layout.contentWidth, layout.minimumContentWidth,
                        "\(Int(width))x\(Int(height)): the centre column fell under its floor."
                    )
                }
            }
        }
    }

    /// The columns go in the order a desktop app gives them up — secondary
    /// detail first, navigation second — and a window can never end up with a
    /// rail but no sidebar.
    func testColumnsAreGivenUpInOrderAsTheWindowNarrows() async {
        await MainActor.run {
            for width in Self.sweptWidths {
                let layout = DemoLayout(size: WinSwiftUI.CGSize(width: width, height: 720))
                if layout.showsRail {
                    XCTAssertTrue(
                        layout.showsSidebar,
                        "\(Int(width)) pt shows the detail rail but not the sidebar.")
                }
            }

            XCTAssertFalse(DemoLayout(size: WinSwiftUI.CGSize(width: 640, height: 720)).showsSidebar)
            XCTAssertFalse(DemoLayout(size: WinSwiftUI.CGSize(width: 640, height: 720)).showsRail)
            XCTAssertTrue(DemoLayout(size: WinSwiftUI.CGSize(width: 900, height: 720)).showsSidebar)
            XCTAssertFalse(DemoLayout(size: WinSwiftUI.CGSize(width: 900, height: 720)).showsRail)
            XCTAssertTrue(DemoLayout(size: WinSwiftUI.CGSize(width: 1280, height: 720)).showsRail)
        }
    }

    /// The toolbar band drops its secondary chrome rather than truncating it.
    /// Four ellipsised labels in a row is what the fixed row produced at
    /// 640 pt; a desktop app keeps the title and the one control that acts.
    func testToolbarGivesUpChromeBeforeItTruncates() async {
        await MainActor.run {
            let narrow = DemoLayout(size: WinSwiftUI.CGSize(width: 640, height: 720))
            XCTAssertFalse(narrow.showsToolbarSearch)
            XCTAssertFalse(narrow.showsToolbarStatusPills)

            let medium = DemoLayout(size: WinSwiftUI.CGSize(width: 760, height: 720))
            XCTAssertFalse(medium.showsToolbarSearch)
            XCTAssertTrue(medium.showsToolbarStatusPills)

            for width in Self.sweptWidths where width >= 900 {
                let layout = DemoLayout(size: WinSwiftUI.CGSize(width: width, height: 720))
                XCTAssertTrue(
                    layout.showsToolbarSearch,
                    "\(Int(width)) pt is wide enough for the whole toolbar row.")
            }

            // A band that shows the search field must have room for the
            // pills too — the ordering that keeps the row from being a
            // patchwork.
            for width in Self.sweptWidths {
                let layout = DemoLayout(size: WinSwiftUI.CGSize(width: width, height: 720))
                if layout.showsToolbarSearch {
                    XCTAssertTrue(layout.showsToolbarStatusPills, "\(Int(width)) pt")
                }
            }
        }
    }

    /// The centre column's floor is what makes the hero card's single-row
    /// action arrangement safe: 420 pt of column is 390 pt of card interior,
    /// against a pill row that measures about 240 at its longest module
    /// label. If this margin ever goes, the fixed-height card starts
    /// squeezing again — which is exactly how the pills reached 0.9 pt.
    func testTheContentColumnFloorLeavesRoomForTheHeroActionRow() async {
        await MainActor.run {
            let cardInteriorAtFloor: WinSwiftUI.CGFloat = 420 - 16 * 2 - 2
            XCTAssertGreaterThan(
                cardInteriorAtFloor, 260,
                "the hero's action row does not fit at the centre column's floor.")

            for width in Self.sweptWidths {
                for height in Self.sweptHeights {
                    let layout = DemoLayout(size: WinSwiftUI.CGSize(width: width, height: height))
                    XCTAssertEqual(
                        layout.heroHeight, layout.compact ? 210 : 232,
                        "\(Int(width))x\(Int(height)): the hero height is one constant.")
                }
            }
        }
    }

    // MARK: - Nothing is orphaned by a fold

    /// Dropping a column must not drop its content. Every section heading the
    /// wide window shows has to be somewhere in the narrow window's tree.
    func testNarrowWindowKeepsEverySectionTheWideWindowHas() async {
        await MainActor.run {
            let wide = renderedTexts(at: IntSize(width: 1280, height: 720))
            let narrow = renderedTexts(at: IntSize(width: 640, height: 720))

            let headings = [
                "WORKSPACE", "SESSION", "DETAIL TRACK", "QUICK ACTIONS", "RENDER PIPELINE", "ACTIVITY",
            ]
            for heading in headings {
                XCTAssertTrue(
                    wide.contains(heading), "the reference window is missing \(heading)")
                XCTAssertTrue(
                    narrow.contains(heading),
                    "a 640 pt window dropped \(heading) instead of re-flowing it into the remaining column.")
            }

            // The module list survives the sidebar's disappearance as a strip.
            for module in ["Layout", "Input", "Animation", "Controls"] {
                XCTAssertTrue(narrow.contains(module), "the collapsed workspace strip lost \(module)")
            }
        }
    }

    /// A label squeezed below the height of its own glyphs is the general
    /// form of the defect the hero pills showed: the layout engine answering
    /// an overflow by driving children past their shrink floors. No label in
    /// the dashboard may end up shorter than 8 pt at any size the window can
    /// be dragged to.
    ///
    /// (Truncation itself — the ellipsis — is resolved inside the painter
    /// from a `maxContentWidth`, not recorded on the node, so it cannot be
    /// asserted from the retained tree. This is the axis the tree does carry,
    /// and it fires on exactly the same cause.)
    func testNoLabelIsCrushedAtAnyReachableWindowSize() async {
        await MainActor.run {
            for size in [
                IntSize(width: 640, height: 480),
                IntSize(width: 640, height: 720),
                IntSize(width: 800, height: 600),
                IntSize(width: 900, height: 600),
                IntSize(width: 1000, height: 700),
                IntSize(width: 1280, height: 720),
                IntSize(width: 1720, height: 980),
            ] {
                var crushed: [String] = []
                walk(snapshot(at: size).runtime.root) { node in
                    guard let text = node.text, !text.isEmpty else {
                        return
                    }
                    let height = node.resolvedFrame.size.height
                    if height > 0, height < 8 {
                        crushed.append("\(text) (\(String(format: "%.1f", height)) pt)")
                    }
                }
                XCTAssertTrue(
                    crushed.isEmpty,
                    "\(size.width)x\(size.height) crushed: \(crushed.sorted().joined(separator: ", "))")
            }
        }
    }

    /// The hero's action pills are 38 pt tall by design. At 640 pt they came
    /// out about 2 pt — a bold 12 pt label inside a hairline — because the
    /// card's fixed height could not hold the content the narrow branch put
    /// in it.
    func testHeroActionPillsKeepTheirHeightInANarrowWindow() async {
        await MainActor.run {
            // Every module, because the primary pill's label is the module's
            // name — "Open Animation" is the widest row the card ever holds.
            for module in DemoModule.allCases {
                for size in [
                    IntSize(width: 640, height: 480),
                    IntSize(width: 640, height: 720),
                    IntSize(width: 900, height: 600),
                    IntSize(width: 1000, height: 900),
                    IntSize(width: 1280, height: 720),
                ] {
                    let heights = heightsOfNodes(withText: "Cycle mode", at: size, module: module)
                    XCTAssertFalse(
                        heights.isEmpty,
                        "\(size.width)x\(size.height) [\(module)]: no Cycle mode pill in the tree")
                    for height in heights {
                        XCTAssertGreaterThanOrEqual(
                            height, 36,
                            "\(size.width)x\(size.height) [\(module)]: the pill was crushed to \(height) pt.")
                    }
                }
            }
        }
    }

    // MARK: - The declared window minimum

    /// The size `WM_GETMINMAXINFO` stops the user's drag at has to be a size
    /// the shell actually has a layout for — otherwise the minimum is just a
    /// different broken state.
    func testTheDeclaredWindowMinimumIsASizeTheShellSurvives() async {
        await MainActor.run {
            let minimum = DemoWindowMetrics.minimumSize
            let screen = WinSwiftUI.CGSize(
                width: minimum.width,
                height: minimum.height - DemoWindowMetrics.tabBarAllowance
            )
            let layout = DemoLayout(size: screen)

            XCTAssertLessThanOrEqual(layout.occupiedWidth, screen.width)
            XCTAssertGreaterThanOrEqual(layout.contentWidth, layout.minimumContentWidth)

            // The body band is what the three columns are given; below its
            // floor the columns overflow the window instead of scrolling.
            let availableBodyHeight =
                screen.height - layout.outerPadding * 2 - layout.toolbarHeight - layout.gap
            XCTAssertEqual(
                layout.bodyHeight, availableBodyHeight,
                accuracy: 0.5,
                "at the declared minimum the body band must still be the space that is actually there, "
                    + "not a floor larger than the window."
            )

            let snapshot = snapshot(at: IntSize(width: 640, height: 480))
            XCTAssertGreaterThan(snapshot.scene.primitiveCount, 0)
        }
    }

    /// And the other end of the same wire: the logical minimum the demo
    /// declares becomes a *physical* track size that scales with the monitor,
    /// so 640x480 logical stops the drag at 800x600 device pixels on a 125 %
    /// display rather than at 640x480 — which would be 512x384 logical, half
    /// a column short of anything the shell has a layout for.
    func testTheDeclaredMinimumReachesTheWindowsTrackSizeAtEveryDPI() async {
        await MainActor.run {
            let logical = IntSize(
                width: Int32(DemoWindowMetrics.minimumSize.width),
                height: Int32(DemoWindowMetrics.minimumSize.height)
            )
            let window = Win32Window(
                title: "Test",
                clientSize: logical,
                configuration: Win32WindowConfiguration(minimumClientSize: logical)
            )

            for (dpi, scale) in [(UINT(96), 1.0), (UINT(120), 1.25), (UINT(144), 1.5), (UINT(192), 2.0)] {
                guard let minimum = window.trackSizeLimits(dpi: dpi).minimum else {
                    return XCTFail("no minimum track size reported at \(dpi) DPI")
                }
                let expectedClient = Win32Window.physicalClientSize(forLogicalClientSize: logical, dpi: dpi)
                XCTAssertEqual(
                    expectedClient.width, Int32((Double(logical.width) * scale).rounded()),
                    "at \(dpi) DPI the client floor is \(scale)x the logical one")
                XCTAssertGreaterThanOrEqual(
                    minimum.width, expectedClient.width,
                    "the outer track size has to hold the client floor plus the frame")
                XCTAssertGreaterThanOrEqual(minimum.height, expectedClient.height)
            }
        }
    }

    // MARK: - Helpers

    private func snapshot(at size: IntSize, module: DemoModule = .layout) -> WinSwiftUIRenderSnapshot {
        let model = DemoDashboardModel()
        model.selectedScreen = .dashboard
        model.selectedModule = module
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model), size: size, displayScale: 1)
    }

    private func renderedTexts(at size: IntSize) -> Set<String> {
        var texts: Set<String> = []
        walk(snapshot(at: size).runtime.root) { node in
            if let text = node.text {
                texts.insert(text)
            }
        }
        return texts
    }

    private func heightsOfNodes(
        withText text: String, at size: IntSize, module: DemoModule = .layout
    ) -> [Double] {
        var heights: [Double] = []
        walk(snapshot(at: size, module: module).runtime.root) { node in
            if node.text == text {
                heights.append(node.resolvedFrame.size.height)
            }
        }
        return heights
    }

    private func walk(_ node: ViewNode, _ visit: (ViewNode) -> Void) {
        var stack = [node]
        while let current = stack.popLast() {
            visit(current)
            stack.append(contentsOf: current.children)
        }
    }
}
