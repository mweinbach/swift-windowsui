import CUIAInterop
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class PatternTreeSource: UIAElementTreeSource {
    var snapshots: [UIAElementSnapshot]
    private(set) var writtenValues: [String] = []
    private(set) var toggledIDs: [UInt64] = []
    private(set) var realizedIDs: [UInt64] = []

    init(snapshots: [UIAElementSnapshot]) {
        self.snapshots = snapshots
    }

    func uiaElementSnapshots() -> [UIAElementSnapshot] { snapshots }
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { true }
    func uiaSetFocus(elementID: UInt64) {}

    func uiaSetValue(elementID: UInt64, value: String) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id == elementID }) else { return false }
        snapshots[index].value = value
        writtenValues.append(value)
        return true
    }

    func uiaToggle(elementID: UInt64) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id == elementID }),
            let state = snapshots[index].toggleState
        else { return false }
        snapshots[index].toggleState = state == .on ? .off : .on
        toggledIDs.append(elementID)
        return true
    }

    func uiaSelect(elementID: UInt64) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id == elementID }) else { return false }
        let parentID = snapshots[index].parentID
        for candidate in snapshots.indices where snapshots[candidate].parentID == parentID {
            if snapshots[candidate].isSelected != nil {
                snapshots[candidate].isSelected = snapshots[candidate].id == elementID
            }
        }
        return true
    }

    func uiaAddToSelection(elementID: UInt64) -> Bool {
        uiaSelect(elementID: elementID)
    }

    func uiaRemoveFromSelection(elementID: UInt64) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id == elementID }) else { return false }
        snapshots[index].isSelected = false
        return true
    }

    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id == elementID }) else { return false }
        snapshots[index].isVirtualizedPlaceholder = false
        snapshots[index].isOffscreen = false
        realizedIDs.append(elementID)
        return true
    }
}

@MainActor
private func makePatternFixture() -> (PatternTreeSource, UIAProviderBridge, UnsafeMutableRawPointer) {
    let bounds = Rect(x: 0, y: 0, width: 200, height: 30)
    let source = PatternTreeSource(snapshots: [
        UIAElementSnapshot(
            id: 0, parentID: nil, name: "Root", controlType: Int32(SWU_UIA_CONTROL_TYPE_PANE),
            bounds: Rect(x: 0, y: 0, width: 800, height: 600), isEnabled: true,
            hasKeyboardFocus: false, isKeyboardFocusable: false, hasDefaultAction: false),
        UIAElementSnapshot(
            id: 1, parentID: 0, name: "Name", value: "Ada", controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT),
            bounds: bounds, isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
            hasDefaultAction: false, supportsValue: true, isReadOnly: false),
        // Even a malformed snapshot that claims supportsValue must never
        // expose a password's contents through the Value COM interface.
        UIAElementSnapshot(
            id: 2, parentID: 0, name: "Password", value: "must remain private",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT), bounds: bounds, isEnabled: true,
            hasKeyboardFocus: false, isKeyboardFocusable: true, hasDefaultAction: false,
            isPassword: true, supportsValue: true, isReadOnly: false),
        UIAElementSnapshot(
            id: 3, parentID: 0, name: "Wi-Fi", controlType: Int32(SWU_UIA_CONTROL_TYPE_CHECK_BOX),
            bounds: bounds, isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
            hasDefaultAction: true, toggleState: .off),
        UIAElementSnapshot(
            id: 4, parentID: 0, name: "Accounts", controlType: Int32(SWU_UIA_CONTROL_TYPE_LIST),
            bounds: bounds, isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
            hasDefaultAction: false, supportsSelection: true),
        UIAElementSnapshot(
            id: 5, parentID: 4, name: "First", controlType: Int32(SWU_UIA_CONTROL_TYPE_LIST_ITEM),
            bounds: bounds, isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
            hasDefaultAction: true, isSelected: false),
        UIAElementSnapshot(
            id: 6, parentID: 4, name: "Second", controlType: Int32(SWU_UIA_CONTROL_TYPE_LIST_ITEM),
            bounds: bounds, isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
            hasDefaultAction: true, isSelected: true),
        UIAElementSnapshot(
            id: 7, parentID: 0, name: "Deferred row", controlType: Int32(SWU_UIA_CONTROL_TYPE_LIST_ITEM),
            bounds: Rect(x: 0, y: 2400, width: 200, height: 30), isEnabled: true,
            hasKeyboardFocus: false, isKeyboardFocusable: false, isOffscreen: true,
            hasDefaultAction: false, isVirtualizedPlaceholder: true),
        UIAElementSnapshot(
            id: 8, parentID: 0, name: "Read only", value: "fixed",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT), bounds: bounds, isEnabled: true,
            hasKeyboardFocus: false, isKeyboardFocusable: false, hasDefaultAction: false,
            supportsValue: true, isReadOnly: true),
        UIAElementSnapshot(
            id: 9, parentID: 0, name: "Disabled Wi-Fi",
            controlType: Int32(SWU_UIA_CONTROL_TYPE_CHECK_BOX), bounds: bounds, isEnabled: false,
            hasKeyboardFocus: false, isKeyboardFocusable: false, hasDefaultAction: true,
            toggleState: .on),
        UIAElementSnapshot(
            id: 10, parentID: 0, name: "Empty", controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT),
            bounds: bounds, isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
            hasDefaultAction: false, supportsValue: true, isReadOnly: false),
    ])
    let bridge = UIAProviderBridge(source: source)
    guard let root = bridge.retainedRootProviderForTesting() else {
        fatalError("pattern fixture must create a root UIA provider")
    }
    return (source, bridge, root)
}

@MainActor
private func patternProviderName(_ provider: UnsafeMutableRawPointer?) -> String? {
    guard let value = SWU_UIAProviderGetName(provider) else { return nil }
    defer { SWU_UIAFreeString(value) }
    var length = 0
    while value[length] != 0 { length += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
}

/// Recursively locates an element and returns an independently retained
/// concrete provider handle, so every branch can safely release its walk.
@MainActor
private func retainedPatternProvider(
    in parent: UnsafeMutableRawPointer?, named name: String
) -> UnsafeMutableRawPointer? {
    guard let parent else { return nil }
    if patternProviderName(parent) == name {
        SWU_UIAAddRefProvider(parent)
        return parent
    }

    var child = SWU_UIAProviderNavigate(parent, Int32(SWU_UIA_NAV_FIRST_CHILD))
    while let current = child {
        let next = SWU_UIAProviderNavigate(current, Int32(SWU_UIA_NAV_NEXT_SIBLING))
        let found = retainedPatternProvider(in: current, named: name)
        SWU_UIAReleaseProvider(current)
        if let found {
            SWU_UIAReleaseProvider(next)
            return found
        }
        child = next
    }
    return nil
}

@MainActor
private func readPatternValue(_ provider: UnsafeMutableRawPointer?) -> String? {
    guard let value = SWU_UIAValueProviderGetValue(provider) else { return nil }
    defer { SWU_UIAFreeString(value) }
    var length = 0
    while value[length] != 0 { length += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
}

@MainActor
private func setPatternValue(_ provider: UnsafeMutableRawPointer?, to value: String) -> Int32 {
    var units = Array(value.utf16)
    units.append(0)
    return units.withUnsafeBufferPointer { buffer in
        SWU_UIAValueProviderSetValue(provider, buffer.baseAddress, Int32(buffer.count - 1))
    }
}

final class UIAAdvancedPatternTests: XCTestCase {
    func testValuePatternReadsAndWritesUnicodeThroughRealCOMVtable() async {
        await MainActor.run {
            let (source, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let edit = retainedPatternProvider(in: root, named: "Name")
            defer { SWU_UIAReleaseProvider(edit) }

            let pattern = SWU_UIAProviderGetValuePattern(edit)
            XCTAssertNotNil(pattern)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(readPatternValue(pattern), "Ada")
            XCTAssertEqual(SWU_UIAValueProviderIsReadOnly(pattern), 0)

            let updated = "Åda 👩🏽‍💻 東京"
            XCTAssertEqual(setPatternValue(pattern, to: updated), 1)
            XCTAssertEqual(source.writtenValues, [updated])
            XCTAssertEqual(readPatternValue(pattern), updated)
            XCTAssertEqual(setPatternValue(pattern, to: ""), 1)
            XCTAssertEqual(readPatternValue(pattern), "")
        }
    }

    func testEmptyTextFieldStillExposesEditableValuePattern() async {
        await MainActor.run {
            let (_, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let edit = retainedPatternProvider(in: root, named: "Empty")
            defer { SWU_UIAReleaseProvider(edit) }
            let pattern = SWU_UIAProviderGetValuePattern(edit)
            XCTAssertNotNil(pattern)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(readPatternValue(pattern), "")
        }
    }

    func testPasswordNeverExposesValuePatternEvenForMalformedSnapshot() async {
        await MainActor.run {
            let (_, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let password = retainedPatternProvider(in: root, named: "Password")
            defer { SWU_UIAReleaseProvider(password) }
            XCTAssertNil(SWU_UIAProviderGetValuePattern(password))

            var hasValue: Int32 = 0
            XCTAssertEqual(
                SWU_UIAProviderGetBoolProperty(password, Int32(SWU_UIA_BOOL_IS_PASSWORD), &hasValue), 1)
            XCTAssertEqual(hasValue, 1)
        }
    }

    func testReadOnlyValueRejectsMutation() async {
        await MainActor.run {
            let (source, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let edit = retainedPatternProvider(in: root, named: "Read only")
            defer { SWU_UIAReleaseProvider(edit) }
            let pattern = SWU_UIAProviderGetValuePattern(edit)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIAValueProviderIsReadOnly(pattern), 1)
            XCTAssertEqual(setPatternValue(pattern, to: "changed"), 0)
            XCTAssertTrue(source.writtenValues.isEmpty)
            XCTAssertEqual(readPatternValue(pattern), "fixed")
        }
    }

    func testTogglePatternReadsStateAndActivatesRetainedAction() async {
        await MainActor.run {
            let (source, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let toggle = retainedPatternProvider(in: root, named: "Wi-Fi")
            defer { SWU_UIAReleaseProvider(toggle) }
            let pattern = SWU_UIAProviderGetTogglePattern(toggle)
            XCTAssertNotNil(pattern)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIAToggleProviderGetState(pattern), Int32(SWU_UIA_TOGGLE_OFF))
            XCTAssertEqual(SWU_UIAToggleProviderToggle(pattern), 1)
            XCTAssertEqual(SWU_UIAToggleProviderGetState(pattern), Int32(SWU_UIA_TOGGLE_ON))
            XCTAssertEqual(source.toggledIDs, [3])
        }
    }

    func testDisabledTogglePatternCannotMutateState() async {
        await MainActor.run {
            let (source, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let toggle = retainedPatternProvider(in: root, named: "Disabled Wi-Fi")
            defer { SWU_UIAReleaseProvider(toggle) }
            let pattern = SWU_UIAProviderGetTogglePattern(toggle)
            XCTAssertNotNil(pattern)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIAToggleProviderToggle(pattern), 0)
            XCTAssertEqual(SWU_UIAToggleProviderGetState(pattern), Int32(SWU_UIA_TOGGLE_ON))
            XCTAssertTrue(source.toggledIDs.isEmpty)
        }
    }

    func testSelectionContainerReturnsSelectedRetainedItems() async {
        await MainActor.run {
            let (_, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let container = retainedPatternProvider(in: root, named: "Accounts")
            defer { SWU_UIAReleaseProvider(container) }
            let selection = SWU_UIAProviderGetSelectionPattern(container)
            XCTAssertNotNil(selection)
            defer { SWU_UIAReleaseProvider(selection) }
            XCTAssertEqual(SWU_UIASelectionProviderGetSelectedCount(selection), 1)

            let selected = SWU_UIASelectionProviderGetSelectedAt(selection, 0)
            XCTAssertNotNil(selected)
            defer { SWU_UIAReleaseProvider(selected) }
            XCTAssertEqual(patternProviderName(selected), "Second")
            XCTAssertNil(SWU_UIASelectionProviderGetSelectedAt(selection, 1))
        }
    }

    func testSelectionItemSelectionUpdatesContainerAndReportsParent() async {
        await MainActor.run {
            let (_, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let first = retainedPatternProvider(in: root, named: "First")
            defer { SWU_UIAReleaseProvider(first) }
            let pattern = SWU_UIAProviderGetSelectionItemPattern(first)
            XCTAssertNotNil(pattern)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIASelectionItemProviderIsSelected(pattern), 0)

            let container = SWU_UIASelectionItemProviderGetSelectionContainer(pattern)
            XCTAssertNotNil(container)
            defer { SWU_UIAReleaseProvider(container) }
            XCTAssertEqual(patternProviderName(container), "Accounts")

            XCTAssertEqual(SWU_UIASelectionItemProviderSelect(pattern), 1)
            XCTAssertEqual(SWU_UIASelectionItemProviderIsSelected(pattern), 1)
            let selection = SWU_UIAProviderGetSelectionPattern(container)
            defer { SWU_UIAReleaseProvider(selection) }
            XCTAssertEqual(SWU_UIASelectionProviderGetSelectedCount(selection), 1)
            let selected = SWU_UIASelectionProviderGetSelectedAt(selection, 0)
            defer { SWU_UIAReleaseProvider(selected) }
            XCTAssertEqual(patternProviderName(selected), "First")
        }
    }

    func testSelectionItemCanBeAddedAndRemoved() async {
        await MainActor.run {
            let (_, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let first = retainedPatternProvider(in: root, named: "First")
            defer { SWU_UIAReleaseProvider(first) }
            let pattern = SWU_UIAProviderGetSelectionItemPattern(first)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIASelectionItemProviderAddToSelection(pattern), 1)
            XCTAssertEqual(SWU_UIASelectionItemProviderIsSelected(pattern), 1)
            XCTAssertEqual(SWU_UIASelectionItemProviderRemoveFromSelection(pattern), 1)
            XCTAssertEqual(SWU_UIASelectionItemProviderIsSelected(pattern), 0)
        }
    }

    func testVirtualizedItemRealizesAndRefreshesOffscreenState() async {
        await MainActor.run {
            let (source, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let row = retainedPatternProvider(in: root, named: "Deferred row")
            defer { SWU_UIAReleaseProvider(row) }

            var hasValue: Int32 = 0
            XCTAssertEqual(SWU_UIAProviderGetBoolProperty(row, Int32(SWU_UIA_BOOL_IS_OFFSCREEN), &hasValue), 1)
            XCTAssertEqual(hasValue, 1)
            let pattern = SWU_UIAProviderGetVirtualizedItemPattern(row)
            XCTAssertNotNil(pattern)
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealize(pattern), 1)
            XCTAssertEqual(source.realizedIDs, [7])
            XCTAssertEqual(SWU_UIAProviderGetBoolProperty(row, Int32(SWU_UIA_BOOL_IS_OFFSCREEN), &hasValue), 0)
            XCTAssertNil(SWU_UIAProviderGetVirtualizedItemPattern(row))
        }
    }

    func testNonMatchingControlsDoNotAdvertisePatterns() async {
        await MainActor.run {
            let (_, bridge, root) = makePatternFixture()
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }
            let edit = retainedPatternProvider(in: root, named: "Name")
            defer { SWU_UIAReleaseProvider(edit) }
            XCTAssertNil(SWU_UIAProviderGetTogglePattern(edit))
            XCTAssertNil(SWU_UIAProviderGetSelectionItemPattern(edit))
            XCTAssertNil(SWU_UIAProviderGetVirtualizedItemPattern(edit))
            XCTAssertNil(SWU_UIAProviderGetSelectionPattern(edit))
        }
    }

    func testRealTextFieldValuePatternMutatesBindingWithoutExposingSecureField() async {
        await MainActor.run {
            final class ValueBox {
                var plain = "Ada"
                var secret = "hunter2"
            }
            let box = ValueBox()
            let rootNode = ViewNode(frame: Rect(x: 0, y: 0, width: 420, height: 200))
            let runtime = RetainedViewRuntime(root: rootNode)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 420, height: 200) },
                invalidateHandler: {})
            let plain = TextField(
                "Name", text: Binding(get: { box.plain }, set: { box.plain = $0 })
            ).makeComponent(context: context).makeNode(runtime: runtime)
            let secure = SecureField(
                "Password", text: Binding(get: { box.secret }, set: { box.secret = $0 })
            ).makeComponent(context: context).makeNode(runtime: runtime)
            rootNode.addChild(plain)
            rootNode.addChild(secure)
            _ = runtime.renderScene()

            let source = RuntimeUIAElementTreeSource(runtime: runtime)
            let bridge = UIAProviderBridge(source: source)
            guard let root = bridge.retainedRootProviderForTesting() else {
                return XCTFail("root provider missing")
            }
            defer { withExtendedLifetime(bridge) {} }
            defer { SWU_UIAReleaseProvider(root) }

            let edit = retainedPatternProvider(in: root, named: "Name")
            defer { SWU_UIAReleaseProvider(edit) }
            let value = SWU_UIAProviderGetValuePattern(edit)
            XCTAssertNotNil(value)
            defer { SWU_UIAReleaseProvider(value) }
            XCTAssertEqual(setPatternValue(value, to: "Grace 東京"), 1)
            XCTAssertEqual(box.plain, "Grace 東京")
            XCTAssertEqual(readPatternValue(value), "Grace 東京")

            let password = retainedPatternProvider(in: root, named: "Password")
            defer { SWU_UIAReleaseProvider(password) }
            XCTAssertNil(SWU_UIAProviderGetValuePattern(password))
            XCTAssertEqual(box.secret, "hunter2")
            var hasValue: Int32 = 0
            XCTAssertEqual(
                SWU_UIAProviderGetBoolProperty(password, Int32(SWU_UIA_BOOL_IS_PASSWORD), &hasValue), 1)
            XCTAssertEqual(hasValue, 1)
        }
    }

    func testSelectableRowsMapToListItemsAndExposeSelectionState() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
            root.resolvedFrame = root.frame
            let runtime = RetainedViewRuntime(root: root)
            let first = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 24))
            first.resolvedFrame = first.frame
            first.accessibilityLabel = "First"
            first.accessibilityTraits = [.isSelectable]
            let second = ViewNode(frame: Rect(x: 0, y: 24, width: 120, height: 24))
            second.resolvedFrame = second.frame
            second.accessibilityLabel = "Second"
            second.accessibilityTraits = [.isSelectable, .isSelected]
            root.addChild(first)
            root.addChild(second)

            let source = RuntimeUIAElementTreeSource(runtime: runtime)
            let snapshots = source.uiaElementSnapshots()
            XCTAssertEqual(snapshots.first?.supportsSelection, true)
            XCTAssertEqual(snapshots.first(where: { $0.name == "First" })?.isSelected, false)
            XCTAssertEqual(snapshots.first(where: { $0.name == "Second" })?.isSelected, true)
            XCTAssertEqual(
                snapshots.first(where: { $0.name == "First" })?.controlType,
                Int32(SWU_UIA_CONTROL_TYPE_LIST_ITEM))
        }
    }

    func testOffscreenBoundsAreDerivedFromWindowViewport() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
            root.resolvedFrame = root.frame
            let runtime = RetainedViewRuntime(root: root)
            let outside = ViewNode(frame: Rect(x: 0, y: 180, width: 60, height: 20))
            outside.resolvedFrame = outside.frame
            outside.accessibilityLabel = "Outside"
            root.addChild(outside)

            let source = RuntimeUIAElementTreeSource(runtime: runtime)
            XCTAssertEqual(source.uiaElementSnapshots().first(where: { $0.name == "Outside" })?.isOffscreen, true)
        }
    }
}
