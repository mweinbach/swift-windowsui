import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Geometry tests for the retained shared-track implementation. The expected
/// coordinates are explicit arithmetic, not another invocation of the solver.
/// These tests neither create a platform window nor an accessibility provider.
@MainActor
final class RetainedGridLayoutTests: XCTestCase {
    func testColumnsUseMaximumCellWidthAcrossDifferentRows() async throws {
        let a = cell(20, 10)
        let b = cell(50, 25)
        let c = cell(60, 30)
        let d = cell(30, 8)
        let first = row([a, b])
        let second = row([c, d])
        let fixture = makeFixture([first, second], horizontalSpacing: 7, verticalSpacing: 5)
        try fixture.layout()

        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 117, height: 60))
        assertRect(first.resolvedFrame, Rect(x: 0, y: 0, width: 117, height: 25))
        assertRect(second.resolvedFrame, Rect(x: 0, y: 30, width: 117, height: 30))
        assertRect(a.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 10))
        assertRect(b.resolvedFrame, Rect(x: 67, y: 0, width: 50, height: 25))
        assertRect(c.resolvedFrame, Rect(x: 0, y: 0, width: 60, height: 30))
        assertRect(d.resolvedFrame, Rect(x: 67, y: 0, width: 30, height: 8))
    }

    func testFractionalAndZeroSpacingUseIndependentAxes() async throws {
        for (horizontal, vertical, expectedWidth, expectedHeight, secondX, secondY) in [
            (2.5, 3.25, 43.25, 30.0, 15.0, 13.75),
            (0.0, 0.0, 40.75, 26.75, 12.5, 10.5),
        ] {
            let first = row([cell(12.5, 10.5), cell(28.25, 8)])
            let second = row([cell(5, 16.25), cell(20, 4)])
            let fixture = makeFixture([first, second], horizontalSpacing: horizontal, verticalSpacing: vertical)
            try fixture.layout()

            XCTAssertEqual(fixture.grid.resolvedFrame.width, expectedWidth, accuracy: 0.000_001)
            XCTAssertEqual(fixture.grid.resolvedFrame.height, expectedHeight, accuracy: 0.000_001)
            XCTAssertEqual(first.children[1].resolvedFrame.minX, secondX, accuracy: 0.000_001)
            XCTAssertEqual(second.resolvedFrame.minY, secondY, accuracy: 0.000_001)
        }
    }

    func testNilRowAlignmentInheritsAndExplicitRowAlignmentOverrides() async throws {
        let inheritedShort = cell(10, 10)
        let explicitShort = cell(10, 10)
        let first = row([inheritedShort, cell(10, 30)])
        let second = row([explicitShort, cell(10, 30)], alignment: .leading)
        let fixture = makeFixture([first, second], verticalSpacing: 5, verticalAlignment: .trailing)
        try fixture.layout()

        XCTAssertEqual(fixture.grid.resolvedFrame.height, 65, accuracy: 0.000_001)
        XCTAssertEqual(inheritedShort.resolvedFrame.minY, 20, accuracy: 0.000_001)
        XCTAssertEqual(explicitShort.resolvedFrame.minY, 0, accuracy: 0.000_001)
        XCTAssertEqual(second.resolvedFrame.minY, 35, accuracy: 0.000_001)
    }

    func testSpanningDeficitUsesExplicitEqualColumnIncrementPolicy() async throws {
        let references = row([cell(35, 10), cell(25, 10), cell(15, 10)])
        let span = cell(75, 12)
        span.gridCellColumns = 2
        let tail = cell(15, 12)
        let fixture = makeFixture([references, row([span, tail])], horizontalSpacing: 5, verticalSpacing: 3)
        try fixture.layout()

        // Interim policy: 75 - (35 + 5 + 25) = 10, adding five to
        // each covered column. These values are not a native span recording.
        XCTAssertEqual(fixture.grid.resolvedFrame.width, 95, accuracy: 0.000_001)
        XCTAssertEqual(references.children[1].resolvedFrame.minX, 45, accuracy: 0.000_001)
        XCTAssertEqual(references.children[2].resolvedFrame.minX, 80, accuracy: 0.000_001)
        assertRect(span.resolvedFrame, Rect(x: 0, y: 0, width: 75, height: 12))
        assertRect(tail.resolvedFrame, Rect(x: 80, y: 0, width: 15, height: 12))
    }

    func testNonRowChildSpansAllColumnsAndCanIncreaseCombinedWidth() async throws {
        let fullWidth = cell(200, 12)
        let ordinary = row([cell(40, 10), cell(60, 20)])
        let fixture = makeFixture([fullWidth, ordinary], horizontalSpacing: 10, verticalSpacing: 4)
        try fixture.layout()

        // The full-width child's 90-point deficit is divided equally in
        // this implementation, producing tracks 85 and105 plus a10-point gap.
        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 200, height: 36))
        assertRect(fullWidth.resolvedFrame, Rect(x: 0, y: 0, width: 200, height: 12))
        assertRect(ordinary.resolvedFrame, Rect(x: 0, y: 16, width: 200, height: 20))
        XCTAssertEqual(ordinary.children[1].resolvedFrame.minX, 95, accuracy: 0.000_001)
    }

    func testShortRowsLeaveTrailingColumnsEmpty() async throws {
        let full = row([cell(20, 10), cell(30, 10), cell(40, 10)])
        let short = row([cell(10, 8)])
        let fixture = makeFixture([full, short], horizontalSpacing: 5, verticalSpacing: 2)
        try fixture.layout()

        XCTAssertEqual(fixture.grid.resolvedFrame.width, 100, accuracy: 0.000_001)
        assertRect(short.resolvedFrame, Rect(x: 0, y: 12, width: 100, height: 8))
        assertRect(short.children[0].resolvedFrame, Rect(x: 0, y: 0, width: 10, height: 8))
        XCTAssertEqual(short.children.count, 1, "Empty trailing cells must not create physical nodes")
    }

    func testUniformFlexibleColumnsShareAvailableWidth() async throws {
        let first = cell(0, 10)
        let second = cell(0, 10)
        first.layoutFillAxes = .horizontalOnly
        second.layoutFillAxes = .horizontalOnly
        let fixture = makeFixture([row([first, second])], horizontalSpacing: 10, canvas: Size(width: 200, height: 80))
        try fixture.layout()

        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 200, height: 10))
        assertRect(first.resolvedFrame, Rect(x: 0, y: 0, width: 95, height: 10))
        assertRect(second.resolvedFrame, Rect(x: 105, y: 0, width: 95, height: 10))
    }

    func testFlexibleRowReceivesExtraHeightWithoutGrowingOtherRows() async throws {
        let flexible = cell(20, 0)
        flexible.layoutFillAxes = .verticalOnly
        let first = row([flexible, cell(10, 10)])
        let second = row([cell(20, 15), cell(10, 15)])
        let fixture = makeFixture(
            [first, second], horizontalSpacing: 5, verticalSpacing: 5, canvas: Size(width: 200, height: 100))
        try fixture.layout()

        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 35, height: 100))
        assertRect(first.resolvedFrame, Rect(x: 0, y: 0, width: 35, height: 80))
        assertRect(flexible.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 80))
        assertRect(second.resolvedFrame, Rect(x: 0, y: 85, width: 35, height: 15))
    }

    func testUnsizedFlexibleCellsFillEstablishedTracksWithoutExpandingGrid() async throws {
        let vertical = cell(20, 0)
        vertical.layoutFillAxes = .verticalOnly
        vertical.gridCellUnsizedAxes = .vertical
        let divider = cell(0, 1)
        divider.layoutFillAxes = .horizontalOnly
        divider.gridCellUnsizedAxes = .horizontal
        let first = row([vertical, cell(30, 20)])
        let second = row([cell(40, 10), cell(10, 10)])
        let fixture = makeFixture([first, divider, second], horizontalSpacing: 5, verticalSpacing: 4)
        try fixture.layout()

        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 75, height: 39))
        assertRect(vertical.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 20))
        assertRect(divider.resolvedFrame, Rect(x: 0, y: 24, width: 75, height: 1))
        assertRect(second.resolvedFrame, Rect(x: 0, y: 29, width: 75, height: 10))
    }

    func testUnsizedIntrinsicCellStillContributesItsExplicitDemand() async throws {
        let unsized = cell(70, 25)
        unsized.gridCellUnsizedAxes = .all
        let fixture = makeFixture([row([cell(30, 10)]), row([unsized])], verticalSpacing: 5)
        try fixture.layout()

        // This is explicit local policy, not native characterization of every
        // intrinsic view and proposal: an unsized flag does not erase70x25.
        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 70, height: 40))
        assertRect(unsized.resolvedFrame, Rect(x: 0, y: 0, width: 70, height: 25))
    }

    func testColumnAlignmentMutationAndRemovalReflowsOtherRows() async throws {
        let small = cell(20, 10)
        let wide = cell(60, 10)
        let fixture = makeFixture([row([small]), row([wide])], verticalSpacing: 4)
        try fixture.layout()
        XCTAssertEqual(small.resolvedFrame.minX, 0)

        wide.gridColumnAlignment = .trailing
        try fixture.layout()
        XCTAssertEqual(small.resolvedFrame.minX, 40, accuracy: 0.000_001)

        wide.gridColumnAlignment = .center
        try fixture.layout()
        XCTAssertEqual(small.resolvedFrame.minX, 20, accuracy: 0.000_001)

        wide.gridColumnAlignment = nil
        try fixture.layout()
        XCTAssertEqual(small.resolvedFrame.minX, 0, accuracy: 0.000_001)
    }

    func testAnchorMutationAndRemovalUpdatesPlacementWithoutChangingTracks() async throws {
        let subject = cell(20, 10)
        let fixture = makeFixture([row([cell(60, 10), cell(10, 10)]), row([subject, cell(10, 30)])])
        try fixture.layout()
        assertRect(subject.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 10))

        subject.gridCellAnchor = Point(x: 0.25, y: 0.75)
        try fixture.layout()
        assertRect(subject.resolvedFrame, Rect(x: 10, y: 15, width: 20, height: 10))
        XCTAssertEqual(fixture.grid.resolvedFrame.width, 70, accuracy: 0.000_001)

        subject.gridCellAnchor = nil
        try fixture.layout()
        assertRect(subject.resolvedFrame, Rect(x: 0, y: 0, width: 20, height: 10))
    }

    func testExplicitBaselineGuidesContributeBothSidesOfRowHeight() async throws {
        let first = cell(10, 30)
        first.alignmentGuides = [.init(axis: .vertical, guide: "firstTextBaseline", value: 5)]
        let second = cell(10, 40)
        second.alignmentGuides = [.init(axis: .vertical, guide: "firstTextBaseline", value: 30)]
        let fixture = makeFixture([row([first, second], alignment: .firstTextBaseline)], horizontalSpacing: 5)
        try fixture.layout()

        // Shared baseline30 with25 points below it requires55 points, even
        // though neither individual cell is that tall. No font metric is read.
        XCTAssertEqual(fixture.grid.resolvedFrame.height, 55, accuracy: 0.000_001)
        assertRect(first.resolvedFrame, Rect(x: 0, y: 25, width: 10, height: 30))
        assertRect(second.resolvedFrame, Rect(x: 15, y: 0, width: 10, height: 40))
        XCTAssertEqual(first.resolvedFrame.minY + 5, second.resolvedFrame.minY + 30, accuracy: 0.000_001)
    }

    func testNestedGridOwnsIndependentColumnTracks() async throws {
        let innerFirst = row([cell(10, 8), cell(20, 12)])
        let innerSecond = row([cell(30, 10), cell(5, 6)])
        let inner = grid([innerFirst, innerSecond], horizontalSpacing: 3, verticalSpacing: 2)
        let fixture = makeFixture(
            [row([inner, cell(40, 30)]), row([cell(80, 10), cell(10, 10)])],
            horizontalSpacing: 7, verticalSpacing: 5)
        try fixture.layout()

        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 127, height: 45))
        assertRect(inner.resolvedFrame, Rect(x: 0, y: 0, width: 53, height: 24))
        XCTAssertEqual(innerFirst.children[1].resolvedFrame.minX, 33, accuracy: 0.000_001)
        XCTAssertEqual(innerSecond.children[1].resolvedFrame.minX, 33, accuracy: 0.000_001)
        XCTAssertEqual(innerSecond.resolvedFrame.minY, 14, accuracy: 0.000_001)
    }

    func testSizeAndSpanChangesInvalidateAllSharedTracks() async throws {
        let growing = cell(20, 10)
        let reference = cell(60, 10)
        let first = row([growing, cell(40, 10)])
        let second = row([reference, cell(10, 10)])
        let fixture = makeFixture([first, second], horizontalSpacing: 5)
        try fixture.layout()
        XCTAssertEqual(second.children[1].resolvedFrame.minX, 65, accuracy: 0.000_001)

        growing.preferredSize = Size(width: 90, height: 10)
        try fixture.layout()
        XCTAssertEqual(second.children[1].resolvedFrame.minX, 95, accuracy: 0.000_001)

        growing.preferredSize = Size(width: 10, height: 10)
        reference.preferredSize = Size(width: 30, height: 10)
        try fixture.layout()
        XCTAssertEqual(second.children[1].resolvedFrame.minX, 35, accuracy: 0.000_001)
        XCTAssertEqual(fixture.grid.resolvedFrame.width, 75, accuracy: 0.000_001)

        growing.gridCellColumns = 2
        try fixture.layout()
        // Row one now occupies columns0...1 and2. Row two establishes30
        // and10 for columns0 and1; column2 keeps the40-point trailing cell.
        XCTAssertEqual(first.children[1].resolvedFrame.minX, 50, accuracy: 0.000_001)
        XCTAssertEqual(second.children[1].resolvedFrame.minX, 35, accuracy: 0.000_001)
        XCTAssertEqual(fixture.grid.resolvedFrame.width, 90, accuracy: 0.000_001)

        growing.gridCellColumns = 1
        try fixture.layout()
        XCTAssertEqual(first.children[1].resolvedFrame.minX, 35, accuracy: 0.000_001)
        XCTAssertEqual(fixture.grid.resolvedFrame.width, 75, accuracy: 0.000_001)
    }

    func testGridConfigurationMutationUsesCurrentSpacingAndAlignment() async throws {
        let short = cell(10, 10)
        let first = row([short, cell(20, 30)])
        let second = row([cell(40, 10), cell(10, 10)])
        let fixture = makeFixture([first, second], horizontalSpacing: 2, verticalSpacing: 3)
        try fixture.layout()
        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 62, height: 43))

        fixture.grid.layoutMode = .grid(
            .init(
                horizontalSpacing: 7, verticalSpacing: 5, horizontalAlignment: .trailing, verticalAlignment: .trailing))
        try fixture.layout()
        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 67, height: 45))
        assertRect(short.resolvedFrame, Rect(x: 30, y: 20, width: 10, height: 10))
        XCTAssertEqual(first.children[1].resolvedFrame.minX, 47, accuracy: 0.000_001)

        first.layoutMode = .gridRow(.init(alignment: .leading))
        try fixture.layout()
        XCTAssertEqual(short.resolvedFrame.minY, 0, accuracy: 0.000_001)
    }

    func testConstrainedWidthRemeasuresWrappedContentBeforeChoosingRowHeight() async throws {
        let previous = NativeTextRenderer.testingOverrides
        defer { NativeTextRenderer.testingOverrides = previous }
        var widths: [Double] = []
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
        NativeTextRenderer.testingOverrides.measure = { _, _, _, maxWidth in
            let width = min(120, maxWidth ?? 120)
            widths.append(width)
            return Size(width: width, height: width < 120 ? 20 : 10)
        }
        let text = ViewNode(
            text: "wrapping words",
            textStyle: PixelTextStyle(color: .white, lineBreakMode: .wrap))
        let neighbor = cell(40, 10)
        let fixture = makeFixture([row([text, neighbor])], canvas: Size(width: 100, height: 200))
        try fixture.layout()

        // The explicit proportional-slack policy assigns75 and25; the
        // synthetic independent text measurer requires20 points at width75.
        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 100, height: 20))
        assertRect(text.resolvedFrame, Rect(x: 0, y: 0, width: 75, height: 20))
        assertRect(neighbor.resolvedFrame, Rect(x: 75, y: 0, width: 25, height: 10))
        XCTAssertTrue(widths.contains(120))
        XCTAssertTrue(widths.contains(75))
    }

    func testDeclaredMinimumRemainsInSharedContentExtentUnderSmallProposal() async throws {
        let minimum = cell(0, 20)
        minimum.layoutConstraints = LayoutConstraints(minWidth: 100)
        let fixture = makeFixture([row([minimum])], canvas: Size(width: 50, height: 100))
        try fixture.layout()

        XCTAssertEqual(fixture.grid.resolvedFrame.width, 50, accuracy: 0.000_001)
        XCTAssertEqual(minimum.resolvedFrame.width, 100, accuracy: 0.000_001)
        XCTAssertEqual(fixture.grid.resolvedContentSize.width, 100, accuracy: 0.000_001)
        XCTAssertEqual(fixture.grid.children[0].resolvedFrame.width, 100, accuracy: 0.000_001)
    }

    func testSpanningHardMinimumSurvivesUnequalTrackCompression() async throws {
        let references = row([cell(100, 10), cell(10, 10)])
        let minimum = cell(0, 20)
        minimum.layoutConstraints = LayoutConstraints(minWidth: 100)
        minimum.gridCellColumns = 2
        let fixture = makeFixture([references, row([minimum])], canvas: Size(width: 80, height: 100))
        try fixture.layout()

        XCTAssertEqual(fixture.grid.resolvedFrame.width, 80, accuracy: 0.000_001)
        XCTAssertEqual(minimum.resolvedFrame.width, 100, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(fixture.grid.resolvedContentSize.width, 100)
        XCTAssertGreaterThanOrEqual(references.resolvedFrame.width, 100)
        XCTAssertLessThanOrEqual(
            minimum.resolvedFrame.maxX, fixture.grid.resolvedContentSize.width,
            "A hard span must not extend beyond the size recorded by the shared tracks")
    }

    func testEmptyHiddenAndHugeSpanInputsStayFiniteWithoutPhysicalPlaceholderCells() async throws {
        let empty = makeFixture([])
        try empty.layout()
        XCTAssertEqual(empty.grid.resolvedFrame.size, .zero)

        let hidden = cell(500, 500)
        hidden.isHidden = true
        let visible = cell(20, 10)
        let hiddenFixture = makeFixture([row([hidden, visible])], horizontalSpacing: 5)
        try hiddenFixture.layout()
        XCTAssertEqual(hidden.resolvedFrame, .zero)
        XCTAssertEqual(hiddenFixture.grid.resolvedFrame.size, Size(width: 20, height: 10))

        let huge = cell(10, 10)
        huge.gridCellColumns = .max
        let overflow = cell(5, 5)
        overflow.gridCellColumns = .max
        let hugeRow = row([huge, overflow])
        let hugeFixture = makeFixture([hugeRow], horizontalSpacing: .infinity, verticalSpacing: .nan)
        try hugeFixture.layout()
        XCTAssertEqual(hugeRow.children.count, 2)
        for node in [hugeFixture.grid, hugeRow, huge, overflow] {
            XCTAssertTrue(node.resolvedFrame.minX.isFinite)
            XCTAssertTrue(node.resolvedFrame.minY.isFinite)
            XCTAssertTrue(node.resolvedFrame.width.isFinite)
            XCTAssertTrue(node.resolvedFrame.height.isFinite)
            XCTAssertGreaterThanOrEqual(node.resolvedFrame.width, 0)
            XCTAssertGreaterThanOrEqual(node.resolvedFrame.height, 0)
        }
        // Numerical fallback, not native behavior for invalid/huge spans.
        // Sparse boundary storage is additionally reviewed in source; there
        // are no physical placeholder views for the requested empty columns.
    }

    func testRowCallbackMutationSettlesSharedWidthsBeforeAcceptingGeometry() async throws {
        let growing = cell(20, 10)
        let firstTail = cell(10, 10)
        let secondTail = cell(10, 10)
        let first = row([growing, firstTail])
        let second = row([cell(30, 10), secondTail])
        let fixture = makeFixture([first, second], horizontalSpacing: 5, verticalSpacing: 4)
        var callbacks = 0
        second.onLayout = { _ in
            callbacks += 1
            if callbacks == 1 { growing.preferredSize = Size(width: 70, height: 10) }
        }
        let firstPass = fixture.runtime.layoutPassID
        try fixture.layout()

        XCTAssertGreaterThanOrEqual(fixture.runtime.layoutPassID - firstPass, 2)
        XCTAssertLessThan(fixture.runtime.layoutPassID - firstPass, 8)
        assertRect(fixture.grid.resolvedFrame, Rect(x: 0, y: 0, width: 85, height: 24))
        XCTAssertEqual(firstTail.resolvedFrame.minX, 75, accuracy: 0.000_001)
        XCTAssertEqual(secondTail.resolvedFrame.minX, 75, accuracy: 0.000_001)
        XCTAssertEqual(growing.resolvedFrame.width, 70, accuracy: 0.000_001)
        guard case .settled = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("The first accepted geometry query must reflect the final shared columns")
        }
    }

    func testUnchangedQueriesDoNotRequestExtraGridSettlementPasses() async throws {
        let first = row([cell(20, 10), cell(40, 20)])
        let second = row([cell(60, 10), cell(10, 10)])
        let fixture = makeFixture([first, second], horizontalSpacing: 5, verticalSpacing: 4)
        try fixture.layout()
        _ = fixture.runtime.renderFrame()
        let baseline = fixture.runtime.layoutPassID
        let firstFrame = first.children[1].resolvedFrame
        for _ in 0..<4 {
            let before = fixture.runtime.layoutPassID
            try fixture.layout()
            XCTAssertEqual(fixture.runtime.layoutPassID, before + 1)
        }

        // A public geometry query always performs one existing layout walk;
        // the Grid must not add a second settlement walk to any of them.
        XCTAssertEqual(
            fixture.runtime.layoutPassID, baseline + 4, "Unchanged queries must not enqueue a grid follow-up")
        XCTAssertEqual(first.children[1].resolvedFrame, firstFrame)
        guard case .settled = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("Stable Grid geometry must retain a settled receipt")
        }
    }

    private func cell(_ width: Double, _ height: Double) -> ViewNode {
        ViewNode(preferredSize: Size(width: width, height: height))
    }

    private func row(_ cells: [ViewNode], alignment: StackCrossAlignment? = nil) -> ViewNode {
        ViewNode(layoutMode: .gridRow(.init(alignment: alignment)), isHitTestVisible: false, children: cells)
    }

    private func grid(
        _ children: [ViewNode], horizontalSpacing: Double = 0, verticalSpacing: Double = 0,
        verticalAlignment: StackCrossAlignment = .leading
    ) -> ViewNode {
        ViewNode(
            layoutMode: .grid(
                .init(
                    horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing,
                    horizontalAlignment: .leading, verticalAlignment: verticalAlignment)),
            isHitTestVisible: false, children: children)
    }

    private func makeFixture(
        _ children: [ViewNode], horizontalSpacing: Double = 0, verticalSpacing: Double = 0,
        verticalAlignment: StackCrossAlignment = .leading,
        canvas: Size = Size(width: 400, height: 300)
    ) -> RetainedGridTestFixture {
        RetainedGridTestFixture(
            grid: grid(
                children, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing,
                verticalAlignment: verticalAlignment), canvas: canvas)
    }

    private func assertRect(
        _ actual: Rect, _ expected: Rect, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000_001, "x", file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000_001, "y", file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_001, "width", file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_001, "height", file: file, line: line)
    }
}

@MainActor
private final class RetainedGridTestFixture {
    let grid: ViewNode
    let runtime: RetainedViewRuntime

    init(grid: ViewNode, canvas: Size) {
        self.grid = grid
        runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(origin: .zero, size: canvas)))
        runtime.root.addChild(grid)
    }

    func layout(file: StaticString = #filePath, line: UInt = #line) throws {
        _ = try XCTUnwrap(runtime.resolvedLayoutFrame(of: grid), file: file, line: line)
    }
}
