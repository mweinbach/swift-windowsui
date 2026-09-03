import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewThatFitsGridSetterRetirementTests: XCTestCase {
    func testVerticalFixedGridStopsAfterPreferredSizeSetterRetiresItsOriginalPath() async throws {
        try checkSetterRetirement(.verticalFixed)
    }

    func testHorizontalFixedGridStopsAfterPreferredSizeSetterRetiresItsOriginalPath() async throws {
        try checkSetterRetirement(.horizontalFixed)
    }

    func testVerticalFlexibleGridStopsAfterFlexSetterRetiresItsOriginalPath() async throws {
        try checkSetterRetirement(.verticalFlexible)
    }

    func testHorizontalFlexibleGridStopsAfterFlexSetterRetiresItsOriginalPath() async throws {
        try checkSetterRetirement(.horizontalFlexible)
    }

    private func checkSetterRetirement(_ sizing: GridSetterRetirementCase) throws {
        let fixture = GridSetterRetirementFixture()
        defer { fixture.close() }
        let probe = fixture.probe
        fixture.row.onLayout = { [weak fixture] _ in
            guard let fixture, fixture.probe.isArmed else { return }
            fixture.probe.isArmed = false
            fixture.probe.armedLayoutEntries += 1
            XCTAssertTrue(fixture.runtime.isLayoutInProgress)
            XCTAssertTrue(fixture.outer.parent === fixture.root)
            XCTAssertTrue(fixture.inner.parent === fixture.outer)
            XCTAssertTrue(fixture.selectedGrid.parent === fixture.inner)
            fixture.probe.originalPath = fixture.outer.captureSelectedContentPath(in: fixture.runtime)
            XCTAssertEqual(fixture.probe.originalPath?.isCurrent, true)
            XCTAssertTrue(fixture.probe.originalPath?.physicalRoot === fixture.outer)
            XCTAssertTrue(fixture.probe.originalPath?.selectedNode === fixture.selectedGrid)

            // The native Grid publishes its track plan before visiting this row.
            // This helper returns before sizing, leaving the pending callback as
            // the only strong owner of the payload. No node property is changed
            // between this seed and the public LazyVGrid/LazyHGrid operation.
            Self.installCollisionCapture(fixture)
            XCTAssertNotNil(fixture.probe.payload)
            XCTAssertEqual(fixture.probe.retirementCalls, 0)
            fixture.probe.isApplying = true
            let context = ViewBuildContext(
                canvasSizeProvider: { GridSetterRetirementFixture.bounds.size }, invalidateHandler: {})
            let component = sizing.component(physical: fixture.outer, probe: fixture.probe, context: context)
            fixture.probe.result = component.makeNode(runtime: fixture.runtime)
            fixture.probe.isApplying = false
        }

        // One real query per case. Its layout may be invalidated by the authored
        // A -> B -> A operation; settling that layout is not this test's oracle.
        // There is no warm-up query, extra render, retry, or budget override.
        _ = fixture.runtime.resolvedLayoutFrame(of: fixture.root)

        XCTAssertEqual(probe.armedLayoutEntries, 1)
        XCTAssertEqual(probe.physicalFactoryCalls, 1)
        XCTAssertEqual(probe.laterFactoryCalls, 0)
        XCTAssertEqual(probe.retirementCalls, 1)
        XCTAssertEqual(probe.callbackBodyCalls, 0)
        XCTAssertNil(probe.payload)
        XCTAssertTrue(probe.retiredWhileApplying)
        XCTAssertTrue(probe.retiredDuringLayout)
        XCTAssertEqual(probe.pathCurrentBeforeABA, true)
        XCTAssertEqual(probe.pathCurrentAfterABA, false)
        XCTAssertEqual(probe.originalPath?.isCurrent, false)
        XCTAssertFalse(fixture.runtime.isLayoutInProgress)

        // The first setter and its native invalidation tail are already accepted.
        // The later sizing setter must not run after that tail retires the path.
        XCTAssertEqual(probe.preferredSizeAtRetirement, sizing.acceptedPreferredSize)
        XCTAssertEqual(probe.flexAtRetirement, sizing.acceptedFlex)
        XCTAssertEqual(probe.constraintsAtRetirement, GridSetterRetirementFixture.initialConstraints)
        XCTAssertEqual(fixture.selectedGrid.preferredSize, sizing.acceptedPreferredSize)
        XCTAssertEqual(fixture.selectedGrid.flexItem, sizing.acceptedFlex)
        XCTAssertEqual(fixture.selectedGrid.layoutConstraints, GridSetterRetirementFixture.initialConstraints)

        // Refusal cannot adopt, reshape, reject, or reparent the live physical
        // boundary, even though the selected objects returned to the same slots.
        let result = try XCTUnwrap(probe.result)
        XCTAssertTrue(result !== fixture.root)
        XCTAssertTrue(result !== fixture.outer)
        XCTAssertTrue(result !== fixture.inner)
        XCTAssertTrue(result !== fixture.selectedGrid)
        XCTAssertTrue(result !== fixture.replacement)
        XCTAssertTrue(result.containsRejectedRetainedSource)
        XCTAssertNil(result.selectedContentRole)
        XCTAssertNil(result.parent)
        XCTAssertTrue(result.children.isEmpty)
        XCTAssertEqual(result.preferredSize, Size.zero)
        XCTAssertEqual(fixture.root.children.count, 1)
        XCTAssertTrue(fixture.root.children.first === fixture.outer)
        XCTAssertTrue(fixture.outer.parent === fixture.root)
        XCTAssertEqual(fixture.outer.children.count, 1)
        XCTAssertTrue(fixture.outer.children.first === fixture.inner)
        XCTAssertTrue(fixture.inner.parent === fixture.outer)
        XCTAssertEqual(fixture.inner.children.count, 1)
        XCTAssertTrue(fixture.inner.children.first === fixture.selectedGrid)
        XCTAssertTrue(fixture.selectedGrid.parent === fixture.inner)
        XCTAssertTrue(fixture.outer.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(fixture.selectedGrid.retainedLazyListRuntime === fixture.runtime)
        XCTAssertEqual(fixture.outer.retainedViewIdentity, GridSetterRetirementFixture.physicalIdentity)
        XCTAssertFalse(fixture.outer.containsRejectedRetainedSource)
        XCTAssertFalse(fixture.selectedGrid.containsRejectedRetainedSource)
        XCTAssertNil(fixture.replacement.parent)
        XCTAssertNil(fixture.replacement.retainedLazyListRuntime)
        XCTAssertEqual(fixture.replacement.preferredSize, Size(width: 77, height: 79))
        for boundary in [fixture.outer, fixture.inner] {
            XCTAssertEqual(boundary.selectedContentRole, .viewThatFits)
            XCTAssertNil(boundary.preferredSize)
            XCTAssertNil(boundary.layoutConstraints)
            XCTAssertEqual(boundary.flexItem, .default)
        }
    }

    @inline(never)
    private static func installCollisionCapture(_ fixture: GridSetterRetirementFixture) {
        let payload = GridSetterRetirementPayload(fixture: fixture)
        fixture.probe.payload = payload
        let key = "grid-shared-tracks-\(ObjectIdentifier(fixture.selectedGrid))"
        fixture.runtime.scheduleAfterLayout(key: key) {
            fixture.probe.callbackBodyCalls += 1
            withExtendedLifetime(payload) {}
        }
    }
}

@MainActor
private enum GridSetterRetirementCase: Equatable {
    case verticalFixed, horizontalFixed, verticalFlexible, horizontalFlexible

    var acceptedPreferredSize: Size {
        switch self {
        case .verticalFixed: Size(width: 40, height: 13)
        case .horizontalFixed: Size(width: 11, height: 30)
        case .verticalFlexible, .horizontalFlexible: GridSetterRetirementFixture.initialPreferredSize
        }
    }

    var acceptedFlex: FlexProperties {
        switch self {
        case .verticalFixed, .horizontalFixed: GridSetterRetirementFixture.initialFlex
        case .verticalFlexible, .horizontalFlexible: FlexProperties(flex: 1)
        }
    }

    func component(physical: ViewNode, probe: GridSetterRetirementProbe, context: ViewBuildContext) -> Component {
        switch self {
        case .verticalFixed, .verticalFlexible:
            let item: GridItem =
                self == .verticalFixed
                ? GridItem(.fixed(40)) : GridItem(.flexible(minimum: 20, maximum: 90))
            return LazyVGrid(columns: [item], spacing: 0) {
                GridSetterExistingPhysicalView(physical: physical, probe: probe)
                GridSetterLaterView(probe: probe)
            }.makeComponent(context: context)
        case .horizontalFixed, .horizontalFlexible:
            let item: GridItem =
                self == .horizontalFixed
                ? GridItem(.fixed(30)) : GridItem(.flexible(minimum: 15, maximum: 70))
            return LazyHGrid(rows: [item], spacing: 0) {
                GridSetterExistingPhysicalView(physical: physical, probe: probe)
                GridSetterLaterView(probe: probe)
            }.makeComponent(context: context)
        }
    }
}

@MainActor
private struct GridSetterExistingPhysicalView: View {
    typealias Body = Never
    let physical: ViewNode
    let probe: GridSetterRetirementProbe

    var body: Never { fatalError("The existing physical node is supplied by makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            probe.physicalFactoryCalls += 1
            XCTAssertTrue(probe.isApplying)
            XCTAssertTrue(runtime.isLayoutInProgress)
            XCTAssertTrue(physical.retainedLazyListRuntime === runtime)
            XCTAssertEqual(physical.retainedViewIdentity, GridSetterRetirementFixture.physicalIdentity)
            XCTAssertEqual(probe.originalPath?.isCurrent, true)
            return physical
        }
    }
}

@MainActor
private struct GridSetterLaterView: View {
    typealias Body = Never
    let probe: GridSetterRetirementProbe

    var body: Never { fatalError("The late cell is supplied by makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            probe.laterFactoryCalls += 1
            return ViewNode(preferredSize: Size(width: 3, height: 5), isHitTestVisible: false)
        }
    }
}

@MainActor
private final class GridSetterRetirementFixture {
    static let bounds = Rect(x: 0, y: 0, width: 120, height: 60)
    static let initialPreferredSize = Size(width: 11, height: 13)
    static let initialFlex = FlexProperties(grow: 2, shrink: 3)
    static let initialConstraints = LayoutConstraints(minWidth: 3, maxWidth: 111, minHeight: 5, maxHeight: 113)
    static let physicalIdentity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])

    let row: ViewNode
    let selectedGrid: ViewNode
    let inner: ViewNode
    let outer: ViewNode
    let replacement: ViewNode
    let root: ViewNode
    let runtime: RetainedViewRuntime
    let probe = GridSetterRetirementProbe()

    init() {
        let leaf = ViewNode(preferredSize: Size(width: 10, height: 8), isHitTestVisible: false)
        let row = ViewNode(layoutMode: .gridRow(.init()), isHitTestVisible: false, children: [leaf])
        let selectedGrid = ViewNode(
            frame: Self.bounds,
            layoutMode: .grid(
                .init(
                    horizontalSpacing: 0, verticalSpacing: 0,
                    horizontalAlignment: .leading, verticalAlignment: .leading)),
            isHitTestVisible: false, children: [row])
        selectedGrid.preferredSize = Self.initialPreferredSize
        selectedGrid.flexItem = Self.initialFlex
        selectedGrid.layoutConstraints = Self.initialConstraints
        let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selectedGrid)
        let outer = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
        // The ordinary AnyView path preserves a non-nil physical identity. Its
        // wrapper therefore performs no identity assignment during the operation.
        outer.retainedViewIdentity = Self.physicalIdentity
        let root = ViewNode(frame: Self.bounds, isHitTestVisible: false, children: [outer])
        let replacement = ViewNode(preferredSize: Size(width: 77, height: 79), isHitTestVisible: false)
        self.row = row
        self.selectedGrid = selectedGrid
        self.inner = inner
        self.outer = outer
        self.replacement = replacement
        self.root = root
        runtime = RetainedViewRuntime(root: root)
    }

    func close() {
        probe.isApplying = false
        row.onLayout = nil
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        root.setChildren([])
    }
}

@MainActor
private final class GridSetterRetirementProbe {
    weak var payload: GridSetterRetirementPayload?
    var isArmed = true
    var isApplying = false
    var armedLayoutEntries = 0
    var physicalFactoryCalls = 0
    var laterFactoryCalls = 0
    var retirementCalls = 0
    var callbackBodyCalls = 0
    var retiredWhileApplying = false
    var retiredDuringLayout = false
    var pathCurrentBeforeABA: Bool?
    var pathCurrentAfterABA: Bool?
    var preferredSizeAtRetirement: Size?
    var flexAtRetirement: FlexProperties?
    var constraintsAtRetirement: LayoutConstraints?
    var originalPath: RetainedSelectedContentPath?
    var result: ViewNode?
}

@MainActor
private final class GridSetterRetirementPayload {
    private weak var fixture: GridSetterRetirementFixture?

    init(fixture: GridSetterRetirementFixture) {
        self.fixture = fixture
    }

    deinit {
        MainActor.assumeIsolated {
            guard let fixture else { return }
            let probe = fixture.probe
            probe.retirementCalls += 1
            probe.retiredWhileApplying = probe.isApplying
            probe.retiredDuringLayout = fixture.runtime.isLayoutInProgress
            guard probe.isApplying else { return }
            probe.preferredSizeAtRetirement = fixture.selectedGrid.preferredSize
            probe.flexAtRetirement = fixture.selectedGrid.flexItem
            probe.constraintsAtRetirement = fixture.selectedGrid.layoutConstraints
            probe.pathCurrentBeforeABA = probe.originalPath?.isCurrent
            fixture.inner.setChildren([fixture.replacement])
            fixture.inner.setChildren([fixture.selectedGrid])
            probe.pathCurrentAfterABA = probe.originalPath?.isCurrent
        }
    }
}
