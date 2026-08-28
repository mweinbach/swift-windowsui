import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class UIARuntimeOwnershipTests: XCTestCase {
    private final class Invocations {
        var explicit = 0
        var fallback = 0
    }

    private final class RuntimeOwner {
        var runtime: RetainedViewRuntime?
    }

    private func makeRuntime() -> RetainedViewRuntime {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 120))
        root.resolvedFrame = root.frame
        let explicit = ViewNode(frame: Rect(x: 10, y: 10, width: 120, height: 40))
        explicit.resolvedFrame = explicit.frame
        explicit.accessibilityLabel = "Explicit"
        explicit.accessibilityTraits = .isButton
        explicit.isFocusable = true
        let fallback = ViewNode(frame: Rect(x: 150, y: 10, width: 120, height: 40))
        fallback.resolvedFrame = fallback.frame
        fallback.accessibilityLabel = "Fallback"
        fallback.accessibilityTraits = .isButton
        fallback.isFocusable = true
        root.addChild(explicit)
        root.addChild(fallback)
        return RetainedViewRuntime(root: root)
    }

    func testSourceAndBridgeDoNotKeepAnUnownedRuntimeOrItsNodesAlive() async throws {
        var runtime: RetainedViewRuntime? = makeRuntime()
        weak var releasedRuntime = runtime
        weak var releasedRoot = runtime?.root
        weak var releasedButton = runtime?.root.children.first
        let source = RuntimeUIAElementTreeSource(runtime: try XCTUnwrap(runtime))
        let bridge = UIAProviderBridge(source: source)
        XCTAssertEqual(source.uiaElementSnapshots().count, 3)

        runtime = nil

        withExtendedLifetime((source, bridge)) {
            XCTAssertNil(releasedRuntime)
            XCTAssertNil(releasedRoot)
            XCTAssertNil(releasedButton)
            XCTAssertTrue(source.uiaElementSnapshots().isEmpty)
        }
    }

    func testRetainedNodesAndAssignedIDsCannotInvokeAfterRuntimeRelease() async throws {
        var runtime: RetainedViewRuntime? = makeRuntime()
        weak var releasedRuntime = runtime
        let explicit = try XCTUnwrap(runtime?.root.children.first)
        let fallback = try XCTUnwrap(runtime?.root.children.last)
        let invocations = Invocations()
        explicit.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { invocations.explicit += 1 }
        ]
        fallback.onActivate = { invocations.fallback += 1 }
        let source = RuntimeUIAElementTreeSource(runtime: try XCTUnwrap(runtime))
        let bridge = UIAProviderBridge(source: source)
        let snapshots = source.uiaElementSnapshots()
        let explicitID = try XCTUnwrap(snapshots.first { $0.name == "Explicit" }?.id)
        let fallbackID = try XCTUnwrap(snapshots.first { $0.name == "Fallback" }?.id)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: explicitID))
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: fallbackID))
        XCTAssertEqual(invocations.explicit, 1)
        XCTAssertEqual(invocations.fallback, 1)

        runtime = nil

        XCTAssertNil(releasedRuntime)
        XCTAssertTrue(source.uiaElementSnapshots().isEmpty)
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: explicitID))
        XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: fallbackID))
        XCTAssertNil(source.projectedElementID(forNodeOrAncestor: explicit))
        XCTAssertNil(source.projectedElementID(forNodeOrAncestor: fallback))
        source.uiaSetFocus(elementID: explicitID)
        XCTAssertFalse(explicit.isFocused)
        XCTAssertFalse(source.uiaSetValue(elementID: explicitID, value: "Unowned"))
        XCTAssertFalse(source.uiaToggle(elementID: explicitID))
        XCTAssertFalse(source.uiaSelect(elementID: explicitID))
        XCTAssertFalse(source.uiaAddToSelection(elementID: explicitID))
        XCTAssertFalse(source.uiaRemoveFromSelection(elementID: explicitID))
        XCTAssertFalse(source.uiaRealizeVirtualizedItem(elementID: explicitID))
        XCTAssertEqual(invocations.explicit, 1)
        XCTAssertEqual(invocations.fallback, 1)
        withExtendedLifetime((source, bridge, explicit, fallback)) {}
    }

    func testLiveOwnerPreservesSnapshotsStableIDsInvocationAndFocus() async throws {
        let runtime = makeRuntime()
        let explicit = try XCTUnwrap(runtime.root.children.first)
        let invocations = Invocations()
        explicit.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { invocations.explicit += 1 }
        ]
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let bridge = UIAProviderBridge(source: source)
        let first = source.uiaElementSnapshots()
        let id = try XCTUnwrap(first.first { $0.name == "Explicit" }?.id)

        withExtendedLifetime((runtime, source, bridge)) {
            XCTAssertEqual(source.uiaElementSnapshots().map(\.id), first.map(\.id))
            XCTAssertEqual(source.projectedElementID(forNodeOrAncestor: explicit), id)
            XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: id))
            XCTAssertEqual(invocations.explicit, 1)
            source.uiaSetFocus(elementID: id)
            XCTAssertTrue(runtime.focusedNode === explicit)
            XCTAssertEqual(source.uiaElementSnapshots().first { $0.id == id }?.hasKeyboardFocus, true)
        }
    }

    func testSnapshotPinsItsEntryRuntimeThroughReentrantBoundsMapping() async throws {
        let owner = RuntimeOwner()
        owner.runtime = makeRuntime()
        weak var releasedRuntime = owner.runtime
        var mappingSawLiveRuntime: [Bool] = []
        let source = RuntimeUIAElementTreeSource(runtime: try XCTUnwrap(owner.runtime)) { bounds in
            owner.runtime = nil
            mappingSawLiveRuntime.append(releasedRuntime != nil)
            return bounds
        }

        let snapshots = source.uiaElementSnapshots()

        withExtendedLifetime((source, owner)) {
            XCTAssertEqual(snapshots.count, 3)
            XCTAssertNil(owner.runtime)
            XCTAssertEqual(mappingSawLiveRuntime, [true, true, true, true])
            XCTAssertNil(releasedRuntime)
            XCTAssertTrue(source.uiaElementSnapshots().isEmpty)
            XCTAssertEqual(mappingSawLiveRuntime, [true, true, true, true])
        }
    }
}
