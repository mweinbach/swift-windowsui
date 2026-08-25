import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class AccessibilityProjectionRuntimePolishTests: XCTestCase {
    private func makeRoot() -> ViewNode {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300))
        root.resolvedFrame = root.frame
        return root
    }

    @discardableResult
    private func addChild(
        to parent: ViewNode,
        frame: Rect,
        label: String? = nil,
        transform: Transform2D = .identity
    ) -> ViewNode {
        let child = ViewNode(frame: frame, transform: transform)
        child.resolvedFrame = frame
        child.accessibilityLabel = label
        parent.addChild(child)
        return child
    }

    private func assertBounds(
        _ actual: Rect?,
        equal expected: Rect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected projected accessibility bounds", file: file, line: line)
            return
        }

        XCTAssertEqual(actual.minX, expected.minX, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1e-8, file: file, line: line)
    }

    func testDisabledElementDoesNotInvokeItsExplicitDefaultAction() async {
        let root = makeRoot()
        let button = addChild(
            to: root,
            frame: Rect(x: 20, y: 30, width: 80, height: 32),
            label: "Disabled action"
        )
        button.accessibilityRespondsToUserInteraction = false
        var activationCount = 0
        button.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { activationCount += 1 }
        ]

        let disabled = AccessibilityProjection.project(root: root)?.children.first
        XCTAssertEqual(disabled?.isEnabled, false)
        XCTAssertEqual(disabled?.invokeDefaultAction(), false)
        XCTAssertEqual(activationCount, 0)

        button.accessibilityRespondsToUserInteraction = true
        let enabled = AccessibilityProjection.project(root: root)?.children.first
        XCTAssertEqual(enabled?.invokeDefaultAction(), true)
        XCTAssertEqual(activationCount, 1)
    }

    func testDisabledElementDoesNotInvokeItsFallbackFirstAction() async {
        let root = makeRoot()
        let button = addChild(
            to: root,
            frame: Rect(x: 20, y: 30, width: 80, height: 32),
            label: "Disabled custom action"
        )
        button.accessibilityRespondsToUserInteraction = false
        var activationCount = 0
        button.accessibilityActions = [
            RetainedAccessibilityAction(name: "Custom action") { activationCount += 1 }
        ]

        let projection = AccessibilityProjection.project(root: root)?.children.first
        XCTAssertEqual(projection?.invokeDefaultAction(), false)
        XCTAssertEqual(activationCount, 0)
    }

    func testOwnScaleProjectsPaintedBoundsAroundViewCenter() async {
        let root = makeRoot()
        addChild(
            to: root,
            frame: Rect(x: 40, y: 60, width: 80, height: 40),
            label: "Scaled control",
            transform: .scale(x: 1.5, y: 2)
        )

        let projection = AccessibilityProjection.project(root: root)?.children.first
        assertBounds(projection?.bounds, equal: Rect(x: 20, y: 40, width: 120, height: 80))
    }

    func testOwnRotationProjectsAxisAlignedPaintedEnclosure() async {
        let root = makeRoot()
        addChild(
            to: root,
            frame: Rect(x: 40, y: 60, width: 80, height: 40),
            label: "Rotated control",
            transform: Transform2D(rotation: .pi / 2)
        )

        let projection = AccessibilityProjection.project(root: root)?.children.first
        assertBounds(projection?.bounds, equal: Rect(x: 60, y: 40, width: 40, height: 80))
    }

    func testTransparentAncestorTransformComposesBeforeChildTransform() async {
        let root = makeRoot()
        let ancestor = addChild(
            to: root,
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            transform: Transform2D(rotation: .pi / 2)
        )
        addChild(
            to: ancestor,
            frame: Rect(x: 10, y: 20, width: 40, height: 20),
            label: "Nested control",
            transform: .scale(x: 2, y: 0.5)
        )

        let projection = AccessibilityProjection.project(root: root)?.children.first
        assertBounds(projection?.bounds, equal: Rect(x: 100, y: 70, width: 40, height: 20))
    }

    func testAccessibleAncestorPassesItsTransformToProjectedChildren() async {
        let root = makeRoot()
        let ancestor = addChild(
            to: root,
            frame: Rect(x: 40, y: 60, width: 100, height: 60),
            label: "Scaled group",
            transform: .scale(x: 2, y: 1.5)
        )
        addChild(
            to: ancestor,
            frame: Rect(x: 10, y: 10, width: 20, height: 12),
            label: "Nested button"
        )

        let group = AccessibilityProjection.project(root: root)?.children.first
        assertBounds(group?.bounds, equal: Rect(x: -10, y: 45, width: 200, height: 90))
        assertBounds(group?.children.first?.bounds, equal: Rect(x: 10, y: 60, width: 40, height: 18))
    }

    func testScrollOffsetIsAppliedBeforeAncestorTransform() async {
        let root = makeRoot()
        let scroller = addChild(
            to: root,
            frame: Rect(x: 20, y: 30, width: 100, height: 80),
            transform: .scale(x: 1.5, y: 2)
        )
        scroller.scrollAxis = .vertical
        scroller.resolvedScrollOffset = 20
        addChild(
            to: scroller,
            frame: Rect(x: 10, y: 45, width: 30, height: 10),
            label: "Scrolled row"
        )

        let projection = AccessibilityProjection.project(root: root)?.children.first
        assertBounds(projection?.bounds, equal: Rect(x: 10, y: 40, width: 45, height: 20))
    }

    func testVirtualizedPlaceholderRetainsItsFullTransformedOffscreenBounds() async {
        let root = makeRoot()
        let scroller = addChild(
            to: root,
            frame: Rect(x: 20, y: 30, width: 100, height: 80),
            transform: .scale(x: 1.5, y: 2)
        )
        scroller.clipsToBounds = true
        scroller.scrollAxis = .vertical
        scroller.resolvedScrollOffset = 20
        let deferred = addChild(
            to: scroller,
            frame: Rect(x: 10, y: 145, width: 30, height: 20),
            label: "Off-screen row",
            transform: .scale(x: 2, y: 0.5)
        )
        deferred.isLayoutDeferredByVirtualization = true
        addChild(
            to: deferred,
            frame: Rect(x: 1, y: 1, width: 5, height: 5),
            label: "Unlaid-out descendant"
        )

        let placeholder = AccessibilityProjection.project(root: root)?.children.first
        XCTAssertEqual(placeholder?.isVirtualizedPlaceholder, true)
        XCTAssertEqual(placeholder?.children.isEmpty, true)
        assertBounds(placeholder?.bounds, equal: Rect(x: -12.5, y: 250, width: 90, height: 20))
    }

    func testUIASnapshotReceivesTransformedAccessibilityBounds() async {
        let root = makeRoot()
        addChild(
            to: root,
            frame: Rect(x: 40, y: 60, width: 80, height: 40),
            label: "Rotated UIA control",
            transform: Transform2D(rotation: .pi / 2)
        )
        let runtime = RetainedViewRuntime(root: root)
        let source = RuntimeUIAElementTreeSource(runtime: runtime)

        let snapshot = source.uiaElementSnapshots().first { $0.name == "Rotated UIA control" }
        assertBounds(snapshot?.bounds, equal: Rect(x: 60, y: 40, width: 40, height: 80))
    }
}
