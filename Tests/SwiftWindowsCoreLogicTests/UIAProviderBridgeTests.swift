import CUIAInterop
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform

// Headless tests for the UIA provider bridge: a fake tree source drives real
// COM provider objects built by the CUIAInterop glue, exercising navigation,
// properties, runtime ids, the Invoke pattern, focus, and point hit testing
// through the actual COM vtables — no UIA client required.

@MainActor
private final class FakeTreeSource: UIAElementTreeSource {
    var snapshots: [UIAElementSnapshot]
    var invokedIDs: [UInt64] = []
    var focusRequestIDs: [UInt64] = []

    init(snapshots: [UIAElementSnapshot]) {
        self.snapshots = snapshots
    }

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        snapshots
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        invokedIDs.append(elementID)
        return true
    }

    func uiaSetFocus(elementID: UInt64) {
        focusRequestIDs.append(elementID)
    }
}

/// root(0, pane "Demo Root")
/// ├── 1: button "Save" (focusable, default action)
/// │   └── 3: text "Save Icon"
/// └── 2: text "Status"
@MainActor
private func makeUIBridgeFixture() -> (FakeTreeSource, UIAProviderBridge, UnsafeMutableRawPointer) {
    let snapshots: [UIAElementSnapshot] = [
        UIAElementSnapshot(
            id: 0, parentID: nil, name: "Demo Root",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_PANE),
            bounds: Rect(x: 0, y: 0, width: 800, height: 600),
            isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
            hasDefaultAction: false),
        UIAElementSnapshot(
            id: 1, parentID: 0, name: "Save",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_BUTTON),
            bounds: Rect(x: 10, y: 10, width: 100, height: 40),
            isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
            hasDefaultAction: true),
        UIAElementSnapshot(
            id: 2, parentID: 0, name: "Status",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_TEXT),
            bounds: Rect(x: 10, y: 60, width: 200, height: 20),
            isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
            hasDefaultAction: false),
        UIAElementSnapshot(
            id: 3, parentID: 1, name: "Save Icon",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_TEXT),
            bounds: Rect(x: 15, y: 15, width: 16, height: 16),
            isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
            hasDefaultAction: false),
    ]
    let source = FakeTreeSource(snapshots: snapshots)
    let bridge = UIAProviderBridge(source: source)
    let root = bridge.retainedRootProviderForTesting()
    XCTAssertNotNil(root)
    return (source, bridge, root!)
}

@MainActor
private func providerName(_ provider: UnsafeMutableRawPointer?) -> String? {
    guard let bstr = SWU_UIAProviderGetName(provider) else {
        return nil
    }
    defer { SWU_UIAFreeString(bstr) }
    var length = 0
    while bstr[length] != 0 {
        length += 1
    }
    return String(decoding: UnsafeBufferPointer(start: bstr, count: length), as: UTF16.self)
}

final class UIAProviderBridgeTests: XCTestCase {
    // MARK: - Navigation

    func testNavigateFirstChildAndBackToParent() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let child = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            XCTAssertNotNil(child)
            defer { SWU_UIAReleaseProvider(child) }
            XCTAssertEqual(providerName(child), "Save")

            let parent = SWU_UIAProviderNavigate(child, Int32(SWU_UIA_NAV_PARENT))
            XCTAssertNotNil(parent)
            defer { SWU_UIAReleaseProvider(parent) }
            XCTAssertEqual(providerName(parent), "Demo Root")
        }
    }

    func testNavigateSiblings() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let first = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            defer { SWU_UIAReleaseProvider(first) }
            let last = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_LAST_CHILD))
            defer { SWU_UIAReleaseProvider(last) }
            XCTAssertEqual(providerName(first), "Save")
            XCTAssertEqual(providerName(last), "Status")

            let next = SWU_UIAProviderNavigate(first, Int32(SWU_UIA_NAV_NEXT_SIBLING))
            XCTAssertNotNil(next)
            defer { SWU_UIAReleaseProvider(next) }
            XCTAssertEqual(providerName(next), "Status")

            let previous = SWU_UIAProviderNavigate(next, Int32(SWU_UIA_NAV_PREVIOUS_SIBLING))
            XCTAssertNotNil(previous)
            defer { SWU_UIAReleaseProvider(previous) }
            XCTAssertEqual(providerName(previous), "Save")

            XCTAssertNil(SWU_UIAProviderNavigate(last, Int32(SWU_UIA_NAV_NEXT_SIBLING)))
            XCTAssertNil(SWU_UIAProviderNavigate(first, Int32(SWU_UIA_NAV_PREVIOUS_SIBLING)))
            XCTAssertNil(SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_PARENT)))
        }
    }

    func testNavigateNestedChild() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let button = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            defer { SWU_UIAReleaseProvider(button) }
            let icon = SWU_UIAProviderNavigate(button, Int32(SWU_UIA_NAV_FIRST_CHILD))
            XCTAssertNotNil(icon)
            defer { SWU_UIAReleaseProvider(icon) }
            XCTAssertEqual(providerName(icon), "Save Icon")

            let fragmentRoot = SWU_UIAProviderGetFragmentRoot(icon)
            XCTAssertNotNil(fragmentRoot)
            defer { SWU_UIAReleaseProvider(fragmentRoot) }
            XCTAssertEqual(providerName(fragmentRoot), "Demo Root")
        }
    }

    // MARK: - Properties

    func testNameControlTypeBoundsAndFlags() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let button = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            defer { SWU_UIAReleaseProvider(button) }

            XCTAssertEqual(providerName(button), "Save")
            XCTAssertEqual(SWU_UIAProviderGetControlType(button), Int32(SWU_UIA_CONTROL_TYPE_BUTTON))

            var left = 0.0
            var top = 0.0
            var width = 0.0
            var height = 0.0
            SWU_UIAProviderGetBoundingRectangle(button, &left, &top, &width, &height)
            XCTAssertEqual([left, top, width, height], [10, 10, 100, 40])

            var hasValue: Int32 = 0
            XCTAssertEqual(SWU_UIAProviderGetBoolProperty(button, Int32(SWU_UIA_BOOL_IS_ENABLED), &hasValue), 1)
            XCTAssertEqual(hasValue, 1)
            XCTAssertEqual(
                SWU_UIAProviderGetBoolProperty(button, Int32(SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE), &hasValue), 1)
            XCTAssertEqual(SWU_UIAProviderGetBoolProperty(button, Int32(SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS), &hasValue), 0)
        }
    }

    // MARK: - Runtime ids

    func testRuntimeIDs() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            var buffer = [Int32](repeating: 0, count: 8)
            let rootCount = buffer.withUnsafeMutableBufferPointer { pointer in
                SWU_UIAProviderGetRuntimeId(root, pointer.baseAddress, Int32(pointer.count))
            }
            XCTAssertEqual(rootCount, 0, "fragment roots report no runtime id")

            let button = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            defer { SWU_UIAReleaseProvider(button) }
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                SWU_UIAProviderGetRuntimeId(button, pointer.baseAddress, Int32(pointer.count))
            }
            XCTAssertEqual(count, 2)
            XCTAssertEqual(buffer[0], 0x5357)
            XCTAssertEqual(buffer[1], 1)
        }
    }

    // MARK: - Invoke pattern

    func testInvokePatternInvokesDefaultAction() async {
        await MainActor.run {
            let (source, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let button = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            defer { SWU_UIAReleaseProvider(button) }
            let invoke = SWU_UIAProviderGetInvokePattern(button)
            XCTAssertNotNil(invoke, "elements with a default action must expose IInvokeProvider")
            defer { SWU_UIAReleaseProvider(invoke) }

            SWU_UIAProviderInvoke(invoke)
            XCTAssertEqual(source.invokedIDs, [1])

            let text = SWU_UIAProviderNavigate(button, Int32(SWU_UIA_NAV_NEXT_SIBLING))
            defer { SWU_UIAReleaseProvider(text) }
            XCTAssertNil(SWU_UIAProviderGetInvokePattern(text), "elements without actions expose no Invoke pattern")
        }
    }

    // MARK: - Focus

    func testSetFocusForwardsToSource() async {
        await MainActor.run {
            let (source, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let button = SWU_UIAProviderNavigate(root, Int32(SWU_UIA_NAV_FIRST_CHILD))
            defer { SWU_UIAReleaseProvider(button) }
            SWU_UIAProviderSetFocus(button)
            XCTAssertEqual(source.focusRequestIDs, [1])
        }
    }

    func testGetFocusReflectsSnapshot() async {
        await MainActor.run {
            let (source, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            XCTAssertNil(SWU_UIAProviderGetFocus(root), "no focused element initially")

            source.snapshots[1].hasKeyboardFocus = true
            let focused = SWU_UIAProviderGetFocus(root)
            XCTAssertNotNil(focused)
            defer { SWU_UIAReleaseProvider(focused) }
            XCTAssertEqual(providerName(focused), "Save")

            var hasValue: Int32 = 0
            XCTAssertEqual(
                SWU_UIAProviderGetBoolProperty(focused, Int32(SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS), &hasValue), 1)
        }
    }

    // MARK: - Hit testing

    func testElementFromPointReturnsDeepestElement() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            // Inside the nested icon (and its button parent, and root):
            // the deepest element wins.
            let icon = SWU_UIAProviderElementFromPoint(root, 16, 16)
            XCTAssertNotNil(icon)
            defer { SWU_UIAReleaseProvider(icon) }
            XCTAssertEqual(providerName(icon), "Save Icon")

            // Inside the button but outside the icon.
            let button = SWU_UIAProviderElementFromPoint(root, 100, 40)
            XCTAssertNotNil(button)
            defer { SWU_UIAReleaseProvider(button) }
            XCTAssertEqual(providerName(button), "Save")

            // Inside the root only.
            let rootHit = SWU_UIAProviderElementFromPoint(root, 700, 500)
            XCTAssertNotNil(rootHit)
            defer { SWU_UIAReleaseProvider(rootHit) }
            XCTAssertEqual(providerName(rootHit), "Demo Root")

            // Outside everything.
            XCTAssertNil(SWU_UIAProviderElementFromPoint(root, 900, 700))
        }
    }

    // MARK: - WM_GETOBJECT gating

    func testGetObjectIgnoresNonRootObjectIDs() async {
        await MainActor.run {
            let (_, bridge, root) = makeUIBridgeFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            // lParam 0 (OBJID_CLIENT) must fall through to DefWindowProc.
            XCTAssertNil(bridge.handleAccessibilityGetObject(hwnd: nil, wParam: 0, lParam: 0))
        }
    }
}
