import CUIAInterop
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

// Tests for the projection → UIA snapshot adapter: a real retained runtime
// with accessibility metadata is projected, flattened, and driven through
// the platform bridge's COM providers.

final class RuntimeUIAElementTreeSourceTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let runtime: RetainedViewRuntime
        let source: RuntimeUIAElementTreeSource
        let button: ViewNode
        let label: ViewNode
        let hidden: ViewNode
        var invokedCount = 0

        init() {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 800, height: 600))
            root.resolvedFrame = root.frame
            runtime = RetainedViewRuntime(root: root)

            button = ViewNode(frame: Rect(x: 10, y: 10, width: 100, height: 40))
            button.resolvedFrame = button.frame
            button.accessibilityLabel = "Save"
            button.accessibilityTraits = .isButton
            button.isFocusable = true
            root.addChild(button)

            label = ViewNode(frame: Rect(x: 10, y: 60, width: 200, height: 20))
            label.resolvedFrame = label.frame
            label.text = "Status"
            root.addChild(label)

            hidden = ViewNode(frame: Rect(x: 10, y: 100, width: 100, height: 20))
            hidden.resolvedFrame = hidden.frame
            hidden.accessibilityLabel = "Secret"
            hidden.isAccessibilityHidden = true
            root.addChild(hidden)

            source = RuntimeUIAElementTreeSource(runtime: runtime)
        }

        func id(forNodeNamed name: String) -> UInt64? {
            source.uiaElementSnapshots().first(where: { $0.name == name })?.id
        }
    }

    func testSnapshotsFlattenProjection() async {
        await MainActor.run {
            let fixture = Fixture()
            let snapshots = fixture.source.uiaElementSnapshots()

            XCTAssertEqual(snapshots.count, 3, "hidden subtree must be omitted")
            XCTAssertEqual(snapshots[0].id, UIAProviderBridge.rootElementID)
            XCTAssertNil(snapshots[0].parentID)
            XCTAssertEqual(snapshots[0].controlType, Int32(SWU_UIA_CONTROL_TYPE_PANE))

            guard let button = snapshots.first(where: { $0.name == "Save" }) else {
                return XCTFail("button snapshot missing")
            }
            XCTAssertEqual(button.parentID, UIAProviderBridge.rootElementID)
            XCTAssertEqual(button.controlType, Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
            XCTAssertTrue(button.isEnabled)
            XCTAssertTrue(button.isKeyboardFocusable)
            XCTAssertFalse(button.hasDefaultAction, "no actions stored yet")
            XCTAssertEqual(button.bounds, Rect(x: 10, y: 10, width: 100, height: 40))

            guard let label = snapshots.first(where: { $0.name == "Status" }) else {
                return XCTFail("label snapshot missing")
            }
            XCTAssertEqual(label.controlType, Int32(SWU_UIA_CONTROL_TYPE_TEXT))
            XCTAssertFalse(label.hasDefaultAction)
        }
    }

    func testElementIDsAreStableAcrossSnapshots() async {
        await MainActor.run {
            let fixture = Fixture()
            let first = fixture.id(forNodeNamed: "Save")
            let second = fixture.id(forNodeNamed: "Save")
            XCTAssertNotNil(first)
            XCTAssertEqual(first, second)
        }
    }

    func testInvokeDefaultActionRunsStoredHandler() async {
        await MainActor.run {
            let fixture = Fixture()
            var invoked = false
            fixture.button.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) { invoked = true }
            ]

            guard let id = fixture.id(forNodeNamed: "Save") else {
                return XCTFail("button snapshot missing")
            }
            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
            XCTAssertTrue(invoked)
        }
    }

    func testInvokeFallsBackToNodeOnActivate() async {
        await MainActor.run {
            let fixture = Fixture()
            var activated = false
            fixture.button.onActivate = { activated = true }

            guard let id = fixture.id(forNodeNamed: "Save") else {
                return XCTFail("button snapshot missing")
            }
            // No explicit accessibility actions: the control's onActivate is
            // still offered as the Invoke pattern's default action.
            let snapshot = fixture.source.uiaElementSnapshots().first(where: { $0.id == id })
            XCTAssertEqual(snapshot?.hasDefaultAction, true)

            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
            XCTAssertTrue(activated)
        }
    }

    func testSetFocusRequestsRuntimeFocus() async {
        await MainActor.run {
            let fixture = Fixture()
            guard let id = fixture.id(forNodeNamed: "Save") else {
                return XCTFail("button snapshot missing")
            }

            fixture.source.uiaSetFocus(elementID: id)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.button)

            let focused = fixture.source.uiaElementSnapshots().first(where: { $0.name == "Save" })
            XCTAssertEqual(focused?.hasKeyboardFocus, true)
        }
    }

    func testRuntimeFocusHookFiresOnFocusChange() async {
        await MainActor.run {
            let fixture = Fixture()
            var reported: [ViewNode?] = []
            fixture.runtime.onAccessibilityFocusChanged = { reported.append($0) }

            fixture.runtime.requestFocus(fixture.button)
            XCTAssertEqual(reported.count, 1)
            XCTAssertTrue(reported[0] === fixture.button)

            fixture.runtime.requestFocus(nil)
            XCTAssertEqual(reported.count, 2)
            XCTAssertNil(reported[1])
        }
    }

    func testProjectedElementIDFallsBackToProjectedAncestor() async {
        await MainActor.run {
            let fixture = Fixture()

            // A transparent (non-element) descendant: focus events target the
            // nearest projected ancestor, which is the button.
            let inner = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
            inner.resolvedFrame = inner.frame
            fixture.button.addChild(inner)

            let buttonID = fixture.id(forNodeNamed: "Save")
            XCTAssertEqual(fixture.source.projectedElementID(forNodeOrAncestor: inner), buttonID)
            XCTAssertEqual(fixture.source.projectedElementID(forNodeOrAncestor: fixture.button), buttonID)

            // A node outside the retained tree has no projected element (and
            // no projected ancestor), so no focus event target exists.
            let detached = ViewNode()
            XCTAssertNil(fixture.source.projectedElementID(forNodeOrAncestor: detached))
        }
    }

    func testBridgeNavigatesRealProjectionThroughCOM() async {
        await MainActor.run {
            let fixture = Fixture()
            fixture.button.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) {}
            ]
            let bridge = UIAProviderBridge(source: fixture.source)
            guard let root = bridge.retainedRootProviderForTesting() else {
                return XCTFail("root provider missing")
            }
            defer { SWU_UIAReleaseProvider(root) }

            let first = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            XCTAssertNotNil(first)
            defer { SWU_UIAReleaseProvider(first) }

            guard let bstr = SWU_UIAProviderGetName(first) else {
                return XCTFail("first child has no name")
            }
            defer { SWU_UIAFreeString(bstr) }
            var length = 0
            while bstr[length] != 0 {
                length += 1
            }
            XCTAssertEqual(String(decoding: UnsafeBufferPointer(start: bstr, count: length), as: UTF16.self), "Save")
            XCTAssertEqual(SWU_UIAProviderGetControlType(first), Int32(SWU_UIA_CONTROL_TYPE_BUTTON))
            XCTAssertNotNil(SWU_UIAProviderGetInvokePattern(first))
        }
    }
}
