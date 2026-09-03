import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Facade geometry through the ordinary retained host and State adoption path.
/// Fixed shapes keep these expectations independent of font metrics. These
/// fixtures create no platform window, accessibility provider, or native input.
@MainActor
final class WinSwiftUIGridLayoutTests: XCTestCase {
    func testGridSharesUnequalFixedColumnWidthsAcrossRows() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 7, verticalSpacing: 5) {
                    GridRow {
                        gridFacadeCell("a", width: 20, height: 10)
                        gridFacadeCell("b", width: 50, height: 25)
                    }
                    .accessibilityIdentifier("first-row")
                    GridRow {
                        gridFacadeCell("c", width: 60, height: 30)
                        gridFacadeCell("d", width: 30, height: 8)
                    }
                    .accessibilityIdentifier("second-row")
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        let grid = try node("grid", in: host)
        guard case .grid = grid.layoutMode else { return XCTFail("Expected a retained Grid layout") }
        for identifier in ["first-row", "second-row"] {
            guard case .gridRow = try node(identifier, in: host).layoutMode else {
                return XCTFail("Direct GridRows must participate in the shared track plan")
            }
        }
        // Independent arithmetic: widths max(20, 60) + 7 + max(50, 30),
        // heights max(10, 25) + 5 + max(30, 8).
        try assertFrame("grid", Rect(x: 0, y: 0, width: 117, height: 60), in: host)
        try assertFrame("first-row", Rect(x: 0, y: 0, width: 117, height: 25), in: host)
        try assertFrame("second-row", Rect(x: 0, y: 30, width: 117, height: 30), in: host)
        try assertFrame("a", Rect(x: 0, y: 0, width: 20, height: 10), in: host)
        try assertFrame("b", Rect(x: 67, y: 0, width: 50, height: 25), in: host)
        try assertFrame("c", Rect(x: 0, y: 30, width: 60, height: 30), in: host)
        try assertFrame("d", Rect(x: 67, y: 30, width: 30, height: 8), in: host)
    }

    func testFixedHeightCellsKeepCenteredOverflowInCompressedRowSlots() async throws {
        let host = makeHost(size: Size(width: 132, height: 160)) {
            AnyView(
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 10) {
                    GridRow {
                        gridFacadeCell("first-fixed", width: 132, height: 78)
                    }
                    .accessibilityIdentifier("first-row")
                    GridRow {
                        gridFacadeCell("second-fixed", width: 132, height: 78)
                    }
                    .accessibilityIdentifier("second-row")
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        // Local compression policy, not a native SwiftUI parity recording:
        // (160 - 10) / 2 gives two 75-point slots. Each fixed cell accepts
        // 78 points, so centering places it (75 - 78) / 2 = -1.5 points
        // above its row and 1.5 points below it. The row origins remain
        // 75 + 10 = 85 points apart; fixed measurement does not add a floor.
        try assertFrame("grid", Rect(x: 0, y: 0, width: 132, height: 160), in: host)
        try assertFrame("first-row", Rect(x: 0, y: 0, width: 132, height: 75), in: host)
        try assertFrame("second-row", Rect(x: 0, y: 85, width: 132, height: 75), in: host)
        try assertFrame("first-fixed", Rect(x: 0, y: -1.5, width: 132, height: 78), in: host)
        try assertFrame("second-fixed", Rect(x: 0, y: 83.5, width: 132, height: 78), in: host)
        for identifier in ["first-fixed", "second-fixed"] {
            let cell = try node(identifier, in: host)
            XCTAssertEqual(cell.preferredSize, Size(width: 132, height: 78))
            XCTAssertEqual(cell.children.count, 1)
            let content = try XCTUnwrap(cell.children.first)
            let contentFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: content))
            XCTAssertEqual(contentFrame.height, 78, accuracy: 0.0001)
        }
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testNilGridRowAlignmentInheritsGridVerticalComponent() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .bottomLeading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow(alignment: nil) {
                        gridFacadeCell("explicit-nil", width: 20, height: 10)
                        gridFacadeCell("first-tall", width: 10, height: 30)
                    }
                    GridRow {
                        gridFacadeCell("default-nil", width: 20, height: 15)
                        gridFacadeCell("second-tall", width: 10, height: 40)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        try assertFrame("grid", Rect(x: 0, y: 0, width: 36, height: 74), in: host)
        try assertFrame("explicit-nil", Rect(x: 0, y: 20, width: 20, height: 10), in: host)
        try assertFrame("first-tall", Rect(x: 26, y: 0, width: 10, height: 30), in: host)
        try assertFrame("default-nil", Rect(x: 0, y: 59, width: 20, height: 15), in: host)
        try assertFrame("second-tall", Rect(x: 26, y: 34, width: 10, height: 40), in: host)
    }

    func testExplicitGridRowAlignmentOverridesGridVerticalComponent() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .bottomLeading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow(alignment: .top) {
                        gridFacadeCell("top", width: 20, height: 10)
                        gridFacadeCell("top-tall", width: 10, height: 30)
                    }
                    GridRow(alignment: .center) {
                        gridFacadeCell("center", width: 20, height: 10)
                        gridFacadeCell("center-tall", width: 10, height: 30)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        try assertFrame("grid", Rect(x: 0, y: 0, width: 36, height: 64), in: host)
        try assertFrame("top", Rect(x: 0, y: 0, width: 20, height: 10), in: host)
        try assertFrame("top-tall", Rect(x: 26, y: 0, width: 10, height: 30), in: host)
        try assertFrame("center", Rect(x: 0, y: 44, width: 20, height: 10), in: host)
        try assertFrame("center-tall", Rect(x: 26, y: 34, width: 10, height: 30), in: host)
    }

    func testCellSpansUseSharedColumnsWithoutChangingAuthoredLayoutPriority() async throws {
        let host = makeHost(size: Size(width: 100, height: 36)) {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 5, verticalSpacing: 3) {
                    GridRow {
                        gridFacadeCell("reference-a", width: 30, height: 10)
                        gridFacadeCell("reference-b", width: 40, height: 10)
                        gridFacadeCell("reference-c", width: 20, height: 10)
                    }
                    GridRow {
                        gridFacadeCell("span", width: 60, height: 12)
                            .gridCellColumns(2)
                        gridFacadeCell("tail", width: 20, height: 12)
                    }
                    GridRow {
                        gridFacadeCell("priority-before", width: 60, height: 8)
                            .layoutPriority(4)
                            .gridCellColumns(2)
                        gridFacadeCell("priority-after", width: 20, height: 8)
                            .gridCellColumns(1)
                            .layoutPriority(7)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        let span = try node("span", in: host)
        let before = try node("priority-before", in: host)
        let after = try node("priority-after", in: host)
        XCTAssertEqual(span.gridCellColumns, 2)
        XCTAssertEqual(span.layoutPriority, 0)
        XCTAssertEqual(before.gridCellColumns, 2)
        XCTAssertEqual(before.layoutPriority, 4)
        XCTAssertEqual(after.gridCellColumns, 1)
        XCTAssertEqual(after.layoutPriority, 7)
        // The third column starts at 30 + 5 + 40 + 5, not after the
        // spanning view's own 60-point width. No span deficit is required.
        try assertFrame("grid", Rect(x: 0, y: 0, width: 100, height: 36), in: host)
        try assertFrame("span", Rect(x: 0, y: 13, width: 60, height: 12), in: host)
        try assertFrame("tail", Rect(x: 80, y: 13, width: 20, height: 12), in: host)
        try assertFrame("priority-before", Rect(x: 0, y: 28, width: 60, height: 8), in: host)
        try assertFrame("priority-after", Rect(x: 80, y: 28, width: 20, height: 8), in: host)
    }

    func testUnsizedDividerUsesWidthEstablishedByFixedCells() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow {
                        gridFacadeCell("top-left", width: 20, height: 10)
                        gridFacadeCell("top-right", width: 40, height: 20)
                    }
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                        .accessibilityIdentifier("divider")
                    GridRow {
                        gridFacadeCell("unsized-fixed", width: 60, height: 12)
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                        gridFacadeCell("bottom-right", width: 10, height: 8)
                    }
                }
                .environment(\.pixelLength, 1)
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        // Local fixed-content policy: the unsized bits suppress flexible
        // growth, not this explicit 60-by-12 demand. This is not native
        // characterization of every intrinsic view under every proposal.
        try assertFrame("grid", Rect(x: 0, y: 0, width: 106, height: 41), in: host)
        try assertFrame("divider", Rect(x: 0, y: 24, width: 106, height: 1), in: host)
        try assertFrame("unsized-fixed", Rect(x: 0, y: 29, width: 60, height: 12), in: host)
        try assertFrame("bottom-right", Rect(x: 66, y: 29, width: 10, height: 8), in: host)
        XCTAssertEqual(try node("divider", in: host).gridCellUnsizedAxes, .horizontal)
        XCTAssertEqual(try node("unsized-fixed", in: host).gridCellUnsizedAxes, .all)
        XCTAssertEqual(try node("grid", in: host).children.count, 3)
    }

    func testOneColumnAlignmentOverridePositionsEveryCellInColumn() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow {
                        gridFacadeCell("short-first", width: 20, height: 10)
                            .gridColumnAlignment(.trailing)
                        gridFacadeCell("wide-second", width: 40, height: 30)
                    }
                    GridRow {
                        gridFacadeCell("wide-first", width: 60, height: 20)
                        gridFacadeCell("short-second", width: 10, height: 10)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        try assertFrame("grid", Rect(x: 0, y: 0, width: 106, height: 54), in: host)
        try assertFrame("short-first", Rect(x: 40, y: 0, width: 20, height: 10), in: host)
        try assertFrame("wide-first", Rect(x: 0, y: 34, width: 60, height: 20), in: host)
        try assertFrame("wide-second", Rect(x: 66, y: 0, width: 40, height: 30), in: host)
        try assertFrame("short-second", Rect(x: 66, y: 34, width: 10, height: 10), in: host)
    }

    func testExplicitCellAnchorUsesCellAndViewNormalizedPoints() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 4, verticalSpacing: 5) {
                    GridRow {
                        gridFacadeCell("width-reference", width: 100, height: 10)
                        gridFacadeCell("other-reference", width: 30, height: 10)
                    }
                    GridRow {
                        gridFacadeCell("anchored", width: 20, height: 20)
                            .gridCellAnchor(UnitPoint(x: 0.25, y: 0.75))
                        gridFacadeCell("height-reference", width: 30, height: 60)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        // (100 - 20) * 0.25 = 20 horizontally; row origin 15 plus
        // local offset (60 - 20) * 0.75 = 30 gives y=45. Other cells remain top-leading.
        try assertFrame("grid", Rect(x: 0, y: 0, width: 134, height: 75), in: host)
        try assertFrame("anchored", Rect(x: 20, y: 45, width: 20, height: 20), in: host)
        try assertFrame("width-reference", Rect(x: 0, y: 0, width: 100, height: 10), in: host)
        try assertFrame("height-reference", Rect(x: 104, y: 15, width: 30, height: 60), in: host)
        XCTAssertEqual(try node("anchored", in: host).gridCellAnchor, Point(x: 0.25, y: 0.75))
    }

    func testGroupExpansionContributesRowsAndCellsToSharedTracks() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4) {
                    Group {
                        GridRow {
                            Group {
                                gridFacadeCell("group-a", width: 20, height: 10)
                                gridFacadeCell("group-b", width: 40, height: 20)
                            }
                        }
                        GridRow {
                            Group {
                                gridFacadeCell("group-c", width: 60, height: 15)
                                gridFacadeCell("group-d", width: 10, height: 5)
                            }
                        }
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        let grid = try node("grid", in: host)
        XCTAssertEqual(grid.children.count, 2)
        XCTAssertEqual(grid.children.map { $0.children.count }, [2, 2])
        try assertFrame("grid", Rect(x: 0, y: 0, width: 106, height: 39), in: host)
        try assertFrame("group-a", Rect(x: 0, y: 0, width: 20, height: 10), in: host)
        try assertFrame("group-b", Rect(x: 66, y: 0, width: 40, height: 20), in: host)
        try assertFrame("group-c", Rect(x: 0, y: 24, width: 60, height: 15), in: host)
        try assertFrame("group-d", Rect(x: 66, y: 24, width: 10, height: 5), in: host)
    }

    func testForEachExpansionContributesRowsAndCellsToSharedTracks() async throws {
        let widths: [[Double]] = [[20, 40], [60, 10]]
        let heights: [[Double]] = [[10, 20], [15, 5]]
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4) {
                    ForEach(0..<2) { row in
                        GridRow {
                            ForEach(0..<2) { column in
                                gridFacadeCell(
                                    "each-\(row)-\(column)", width: widths[row][column], height: heights[row][column])
                            }
                        }
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        let grid = try node("grid", in: host)
        XCTAssertEqual(grid.children.count, 2)
        XCTAssertEqual(grid.children.map { $0.children.count }, [2, 2])
        // Literal expectations, not comparison with the Group fixture or
        // another layout that might make the same structural-expansion error.
        try assertFrame("grid", Rect(x: 0, y: 0, width: 106, height: 39), in: host)
        try assertFrame("each-0-0", Rect(x: 0, y: 0, width: 20, height: 10), in: host)
        try assertFrame("each-0-1", Rect(x: 66, y: 0, width: 40, height: 20), in: host)
        try assertFrame("each-1-0", Rect(x: 0, y: 24, width: 60, height: 15), in: host)
        try assertFrame("each-1-1", Rect(x: 66, y: 24, width: 10, height: 5), in: host)
    }

    func testNestedGridHasIndependentColumnWidths() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 7, verticalSpacing: 5) {
                    GridRow {
                        Grid(alignment: .topLeading, horizontalSpacing: 3, verticalSpacing: 2) {
                            GridRow {
                                gridFacadeCell("inner-a", width: 10, height: 8)
                                gridFacadeCell("inner-b", width: 20, height: 12)
                            }
                            GridRow {
                                gridFacadeCell("inner-c", width: 30, height: 10)
                                gridFacadeCell("inner-d", width: 5, height: 6)
                            }
                        }
                        .accessibilityIdentifier("inner")
                        gridFacadeCell("outer-b", width: 40, height: 30)
                    }
                    GridRow {
                        gridFacadeCell("outer-c", width: 80, height: 10)
                        gridFacadeCell("outer-d", width: 10, height: 10)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        try assertFrame("grid", Rect(x: 0, y: 0, width: 127, height: 45), in: host)
        try assertFrame("inner", Rect(x: 0, y: 0, width: 53, height: 24), in: host)
        try assertFrame("inner-a", Rect(x: 0, y: 0, width: 10, height: 8), in: host)
        try assertFrame("inner-b", Rect(x: 33, y: 0, width: 20, height: 12), in: host)
        try assertFrame("inner-c", Rect(x: 0, y: 14, width: 30, height: 10), in: host)
        try assertFrame("inner-d", Rect(x: 33, y: 14, width: 5, height: 6), in: host)
        try assertFrame("outer-b", Rect(x: 87, y: 0, width: 40, height: 30), in: host)
        try assertFrame("outer-c", Rect(x: 0, y: 35, width: 80, height: 10), in: host)
    }

    func testReloadUpdatesSharedTracksAndPreservesRetainedCells() async throws {
        let model = GridFacadeReloadModel()
        let host = makeHost {
            AnyView(
                Grid(
                    alignment: model.alignment,
                    horizontalSpacing: model.horizontalSpacing,
                    verticalSpacing: model.verticalSpacing
                ) {
                    GridRow(alignment: model.firstRowAlignment) {
                        gridFacadeCell("mutable", width: model.firstWidth, height: 10)
                        gridFacadeCell("top-right", width: 40, height: 20)
                    }
                    .accessibilityIdentifier("first-row")
                    GridRow {
                        gridFacadeCell("other", width: model.secondWidth, height: 15)
                        gridFacadeCell("bottom-right", width: 10, height: 5)
                    }
                    .accessibilityIdentifier("second-row")
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }
        let identifiers = ["grid", "first-row", "second-row", "mutable", "top-right", "other", "bottom-right"]
        let installed = try identifiers.map { try node($0, in: host) }
        try assertFrame("grid", Rect(x: 0, y: 0, width: 106, height: 39), in: host)

        model.firstWidth = 90
        host.reload()
        host.render()

        try assertFrame("grid", Rect(x: 0, y: 0, width: 136, height: 39), in: host)
        try assertFrame("mutable", Rect(x: 0, y: 0, width: 90, height: 10), in: host)
        try assertFrame("top-right", Rect(x: 96, y: 0, width: 40, height: 20), in: host)
        try assertFrame("bottom-right", Rect(x: 96, y: 24, width: 10, height: 5), in: host)
        for (identifier, original) in zip(identifiers, installed) {
            XCTAssertTrue(try node(identifier, in: host) === original, identifier)
        }

        model.firstWidth = 12
        model.secondWidth = 30
        host.reload()
        host.render()

        try assertFrame("grid", Rect(x: 0, y: 0, width: 76, height: 39), in: host)
        try assertFrame("mutable", Rect(x: 0, y: 0, width: 12, height: 10), in: host)
        try assertFrame("other", Rect(x: 0, y: 24, width: 30, height: 15), in: host)
        try assertFrame("bottom-right", Rect(x: 36, y: 24, width: 10, height: 5), in: host)
        for (identifier, original) in zip(identifiers, installed) {
            XCTAssertTrue(try node(identifier, in: host) === original, identifier)
        }

        // The retained layout category is unchanged. New Grid settings must
        // still replace the installed configuration and invalidate shared geometry.
        model.horizontalSpacing = 10
        model.verticalSpacing = 8
        model.alignment = .bottomTrailing
        host.reload()
        host.render()

        try assertFrame("grid", Rect(x: 0, y: 0, width: 80, height: 43), in: host)
        try assertFrame("mutable", Rect(x: 18, y: 10, width: 12, height: 10), in: host)
        try assertFrame("top-right", Rect(x: 40, y: 0, width: 40, height: 20), in: host)
        try assertFrame("other", Rect(x: 0, y: 28, width: 30, height: 15), in: host)
        try assertFrame("bottom-right", Rect(x: 70, y: 38, width: 10, height: 5), in: host)
        for (identifier, original) in zip(identifiers, installed) {
            XCTAssertTrue(try node(identifier, in: host) === original, identifier)
        }

        // A GridRow configuration change also preserves the installed row and
        // cells, and removing that override restores the Grid's current default.
        model.firstRowAlignment = .top
        host.reload()
        host.render()

        try assertFrame("grid", Rect(x: 0, y: 0, width: 80, height: 43), in: host)
        try assertFrame("mutable", Rect(x: 18, y: 0, width: 12, height: 10), in: host)
        try assertFrame("bottom-right", Rect(x: 70, y: 38, width: 10, height: 5), in: host)
        for (identifier, original) in zip(identifiers, installed) {
            XCTAssertTrue(try node(identifier, in: host) === original, identifier)
        }

        model.firstRowAlignment = nil
        host.reload()
        host.render()

        try assertFrame("grid", Rect(x: 0, y: 0, width: 80, height: 43), in: host)
        try assertFrame("mutable", Rect(x: 18, y: 10, width: 12, height: 10), in: host)
        for (identifier, original) in zip(identifiers, installed) {
            XCTAssertTrue(try node(identifier, in: host) === original, identifier)
        }
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testMountedStateSurvivesFreshGridRebuildSeedsAndResizesTracks() async throws {
        let capture = GridFacadeStateCapture()
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 5, verticalSpacing: 4) {
                    GridRow {
                        GridFacadeStateCell(seed: capture.nextSeed, capture: capture)
                        gridFacadeCell("state-neighbor", width: 10, height: 12)
                    }
                    GridRow {
                        gridFacadeCell("state-reference", width: 30, height: 8)
                        gridFacadeCell("state-other", width: 10, height: 8)
                    }
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }
        let installedCell = try node("state-cell", in: host)
        let installedNeighbor = try node("state-neighbor", in: host)
        let binding = try XCTUnwrap(capture.binding)
        let initialBuilds = capture.bodyBuilds
        XCTAssertEqual(binding.wrappedValue, 20)
        XCTAssertGreaterThan(host.coordinator.registry.liveOwnerCount, 0)
        try assertFrame("grid", Rect(x: 0, y: 0, width: 45, height: 24), in: host)
        try assertFrame("state-cell", Rect(x: 0, y: 0, width: 20, height: 12), in: host)
        try assertFrame("state-neighbor", Rect(x: 35, y: 0, width: 10, height: 12), in: host)

        // This is the projected binding captured from the installed body.
        // Its ordinary coordinator invalidation must perform the reload;
        // there is no manual binding box or explicit host.reload() here.
        binding.wrappedValue = 65
        host.render()

        XCTAssertGreaterThan(capture.bodyBuilds, initialBuilds)
        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 65)
        try assertFrame("grid", Rect(x: 0, y: 0, width: 80, height: 24), in: host)
        try assertFrame("state-cell", Rect(x: 0, y: 0, width: 65, height: 12), in: host)
        try assertFrame("state-neighbor", Rect(x: 70, y: 0, width: 10, height: 12), in: host)
        XCTAssertTrue(try node("state-cell", in: host) === installedCell)
        XCTAssertTrue(try node("state-neighbor", in: host) === installedNeighbor)

        capture.nextSeed = 999
        host.reload()
        host.render()

        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 65)
        try assertFrame("grid", Rect(x: 0, y: 0, width: 80, height: 24), in: host)
        XCTAssertTrue(try node("state-cell", in: host) === installedCell)
        XCTAssertTrue(try node("state-neighbor", in: host) === installedNeighbor)

        binding.wrappedValue = 15
        host.render()

        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 15)
        try assertFrame("grid", Rect(x: 0, y: 0, width: 45, height: 24), in: host)
        try assertFrame("state-cell", Rect(x: 0, y: 0, width: 15, height: 12), in: host)
        try assertFrame("state-neighbor", Rect(x: 35, y: 0, width: 10, height: 12), in: host)
        XCTAssertTrue(try node("state-cell", in: host) === installedCell)
        XCTAssertNil(host.coordinator.latestInstallationError)
    }

    func testRTLPlacementUsesLogicalColumnPolicyWithoutReorderingChildren() async throws {
        let host = makeHost {
            AnyView(
                Grid(alignment: .topLeading, horizontalSpacing: 7, verticalSpacing: 5) {
                    GridRow {
                        gridFacadeCell("rtl-a", width: 20, height: 10)
                        gridFacadeCell("rtl-b", width: 50, height: 25)
                    }
                    .accessibilityIdentifier("rtl-first-row")
                    GridRow {
                        gridFacadeCell("rtl-c", width: 60, height: 30)
                        gridFacadeCell("rtl-d", width: 30, height: 8)
                    }
                    .accessibilityIdentifier("rtl-second-row")
                }
                .environment(\.layoutDirection, .rightToLeft)
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        // Local RTL policy, not a recorded pinned-native characterization:
        // logical column zero occupies x=57...117; leading is its right edge.
        try assertFrame("grid", Rect(x: 0, y: 0, width: 117, height: 60), in: host)
        try assertFrame("rtl-a", Rect(x: 97, y: 0, width: 20, height: 10), in: host)
        try assertFrame("rtl-b", Rect(x: 0, y: 0, width: 50, height: 25), in: host)
        try assertFrame("rtl-c", Rect(x: 57, y: 30, width: 60, height: 30), in: host)
        try assertFrame("rtl-d", Rect(x: 20, y: 30, width: 30, height: 8), in: host)
        XCTAssertEqual(
            try node("rtl-first-row", in: host).children.map(\.accessibilityIdentifier), ["rtl-a", "rtl-b"])
        XCTAssertEqual(
            try node("rtl-second-row", in: host).children.map(\.accessibilityIdentifier), ["rtl-c", "rtl-d"])
    }

    func testStandaloneGridRowPreservesUnqualifiedLegacyHStackFallback() async throws {
        let host = makeHost {
            AnyView(
                GridRow(alignment: nil) {
                    gridFacadeCell("standalone-a", width: 20, height: 10)
                    gridFacadeCell("standalone-b", width: 50, height: 30)
                }
                .accessibilityIdentifier("grid"))
        }
        defer { host.close() }

        // This intentionally protects the bounded slice's existing HStack
        // fallback. Apple's documented Group-like standalone behavior remains
        // unimplemented; these numbers must not be reported as native parity.
        guard case .stack(let layout) = try node("grid", in: host).layoutMode else {
            return XCTFail("Standalone GridRow must retain the explicitly unqualified fallback")
        }
        XCTAssertEqual(layout, .horizontal(spacing: 0, alignment: .center))
        try assertFrame("grid", Rect(x: 0, y: 0, width: 70, height: 30), in: host)
        try assertFrame("standalone-a", Rect(x: 0, y: 10, width: 20, height: 10), in: host)
        try assertFrame("standalone-b", Rect(x: 20, y: 0, width: 50, height: 30), in: host)
    }

    private func makeHost(
        size: Size = Size(width: 400, height: 300), content: @escaping @MainActor () -> AnyView
    ) -> MountedOnChangeTestHost {
        let host = MountedOnChangeTestHost(size: size, content: content)
        host.render()
        XCTAssertNil(host.coordinator.latestInstallationError)
        return host
    }

    private func node(
        _ identifier: String, in host: MountedOnChangeTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        var matches: [ViewNode] = []
        var pending = [host.runtime.root]
        while let candidate = pending.popLast() {
            if candidate.accessibilityIdentifier == identifier { matches.append(candidate) }
            pending.append(contentsOf: candidate.children)
        }
        XCTAssertEqual(matches.count, 1, "Expected one node named \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, "Missing \(identifier)", file: file, line: line)
    }

    private func assertFrame(
        _ identifier: String, _ expected: Rect, in host: MountedOnChangeTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let target = try node(identifier, in: host, file: file, line: line)
        let grid = try node("grid", in: host, file: file, line: line)
        let targetFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: target), file: file, line: line)
        let gridFrame = try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: grid), file: file, line: line)
        // Only translate the public layout-space query into Grid coordinates;
        // expected sizes and positions are authored independently above.
        XCTAssertEqual(
            targetFrame.origin.x - gridFrame.origin.x, expected.origin.x, accuracy: 0.0001,
            "\(identifier).x", file: file, line: line)
        XCTAssertEqual(
            targetFrame.origin.y - gridFrame.origin.y, expected.origin.y, accuracy: 0.0001,
            "\(identifier).y", file: file, line: line)
        XCTAssertEqual(
            targetFrame.width, expected.width, accuracy: 0.0001, "\(identifier).width", file: file, line: line)
        XCTAssertEqual(
            targetFrame.height, expected.height, accuracy: 0.0001, "\(identifier).height", file: file, line: line)
    }
}

@MainActor
private func gridFacadeCell(_ identifier: String, width: Double, height: Double) -> some View {
    Rectangle()
        .frame(width: width, height: height)
        .accessibilityIdentifier(identifier)
}

@MainActor
private final class GridFacadeReloadModel {
    var firstWidth = 20.0
    var secondWidth = 60.0
    var horizontalSpacing = 6.0
    var verticalSpacing = 4.0
    var alignment: Alignment = .topLeading
    var firstRowAlignment: VerticalAlignment?
}

@MainActor
private final class GridFacadeStateCapture {
    var nextSeed = 20.0
    var binding: Binding<Double>?
    var bodyBuilds = 0
}

@MainActor
private struct GridFacadeStateCell: View {
    @State private var width: Double
    let capture: GridFacadeStateCapture

    init(seed: Double, capture: GridFacadeStateCapture) {
        _width = State(wrappedValue: seed)
        self.capture = capture
    }

    var body: some View {
        capture.binding = $width
        capture.bodyBuilds += 1
        return gridFacadeCell("state-cell", width: width, height: 12)
    }
}
