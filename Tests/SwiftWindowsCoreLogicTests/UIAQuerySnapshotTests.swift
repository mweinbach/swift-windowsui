import CUIAInterop
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform

private func queryElement(
    _ id: UInt64,
    parentID: UInt64? = 0,
    name: String = "",
    bounds: Rect = Rect(x: 0, y: 0, width: 100, height: 100)
) -> UIAElementSnapshot {
    UIAElementSnapshot(
        id: id, parentID: parentID, name: name,
        controlType: Int32(SWU_UIA_CONTROL_TYPE_GROUP), bounds: bounds,
        isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
        hasDefaultAction: false)
}

private func selectionQueryElements(_ selected: Set<UInt64>) -> [UIAElementSnapshot] {
    var root = queryElement(0, parentID: nil, name: "Root")
    root.supportsSelection = true
    var first = queryElement(12, name: "First")
    first.isSelected = selected.contains(12)
    var second = queryElement(13, name: "Second")
    second.isSelected = selected.contains(13)
    return [root, first, second]
}

@MainActor
private final class QuerySnapshotTreeSource: UIAElementTreeSource {
    var elements: [UIAElementSnapshot]
    var nextSnapshots: [[UIAElementSnapshot]] = []
    var snapshotReads = 0

    init(_ elements: [UIAElementSnapshot]) {
        self.elements = elements
    }

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        snapshotReads += 1
        return nextSnapshots.isEmpty ? elements : nextSnapshots.removeFirst()
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { false }
    func uiaSetFocus(elementID: UInt64) {}
}

@MainActor
private func queryProviderName(_ provider: UnsafeMutableRawPointer?) -> String? {
    guard let value = SWU_UIAProviderGetName(provider) else { return nil }
    defer { SWU_UIAFreeString(value) }
    var length = 0
    while value[length] != 0 { length += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
}

final class UIAQuerySnapshotTests: XCTestCase {
    func testCopiedValuesRemainIndependentAcrossSendableTransfer() async {
        var element = queryElement(7, name: "Before", bounds: Rect(x: 1, y: 2, width: 3, height: 4))
        element.value = "old"
        element.isEnabled = false
        var elements = [element]
        let snapshot = UIAQuerySnapshot(elements)

        elements[0].name = "After"
        elements[0].value = "new"
        elements[0].bounds = Rect(x: 10, y: 20, width: 30, height: 40)
        elements[0].isEnabled = true
        elements.append(queryElement(9, name: "Added"))

        let (name, value, bounds, enabled, added) = await Task.detached {
            (
                snapshot.stringProperty(7, property: Int32(SWU_UIA_STRING_NAME)),
                snapshot.stringProperty(7, property: Int32(SWU_UIA_STRING_VALUE)),
                snapshot.boundingRectangle(7),
                snapshot.boolProperty(7, property: Int32(SWU_UIA_BOOL_IS_ENABLED)),
                snapshot.stringProperty(9, property: Int32(SWU_UIA_STRING_NAME))
            )
        }.value
        XCTAssertEqual(name, "Before")
        XCTAssertEqual(value, "old")
        XCTAssertEqual(bounds, Rect(x: 1, y: 2, width: 3, height: 4))
        XCTAssertEqual(enabled, 0)
        XCTAssertNil(added)

        let fresh = UIAQuerySnapshot(elements)
        XCTAssertEqual(fresh.stringProperty(7, property: Int32(SWU_UIA_STRING_NAME)), "After")
        XCTAssertEqual(fresh.stringProperty(9, property: Int32(SWU_UIA_STRING_NAME)), "Added")
    }

    func testNavigationPreservesArrayOrderAndDuplicateFirstMatch() async {
        var first = queryElement(40, name: "First")
        first.isEnabled = false
        let snapshot = UIAQuerySnapshot([
            queryElement(0, parentID: nil), first, queryElement(7), queryElement(90),
            queryElement(40, parentID: 7, name: "Later"),
        ])

        XCTAssertEqual(snapshot.navigate(0, direction: Int32(SWU_UIA_NAV_FIRST_CHILD)), 40)
        XCTAssertEqual(snapshot.navigate(0, direction: Int32(SWU_UIA_NAV_LAST_CHILD)), 90)
        XCTAssertEqual(snapshot.navigate(40, direction: Int32(SWU_UIA_NAV_NEXT_SIBLING)), 7)
        XCTAssertEqual(snapshot.navigate(90, direction: Int32(SWU_UIA_NAV_PREVIOUS_SIBLING)), 7)
        XCTAssertEqual(snapshot.navigate(40, direction: Int32(SWU_UIA_NAV_PREVIOUS_SIBLING)), UInt64.max)
        XCTAssertEqual(snapshot.navigate(90, direction: Int32(SWU_UIA_NAV_NEXT_SIBLING)), UInt64.max)
        XCTAssertEqual(snapshot.navigate(40, direction: Int32(SWU_UIA_NAV_PARENT)), 0)
        XCTAssertEqual(snapshot.navigate(7, direction: Int32(SWU_UIA_NAV_FIRST_CHILD)), 40)
        XCTAssertEqual(snapshot.stringProperty(40, property: Int32(SWU_UIA_STRING_NAME)), "First")
        XCTAssertEqual(snapshot.boolProperty(40, property: Int32(SWU_UIA_BOOL_IS_ENABLED)), 0)
    }

    func testPointLookupKeepsDeepestFirstTieAndHalfOpenEdges() async {
        let parentBounds = Rect(x: 10, y: 10, width: 70, height: 70)
        let childBounds = Rect(x: 20, y: 20, width: 10, height: 10)
        var firstParent = queryElement(10, bounds: parentBounds)
        firstParent.hasKeyboardFocus = true
        var secondParent = queryElement(20, bounds: parentBounds)
        secondParent.hasKeyboardFocus = true
        var firstChild = queryElement(30, parentID: 10, bounds: childBounds)
        firstChild.isEnabled = false
        firstChild.isOffscreen = true
        let snapshot = UIAQuerySnapshot([
            queryElement(0, parentID: nil), firstParent, secondParent, firstChild,
            queryElement(40, parentID: 20, bounds: childBounds),
        ])

        XCTAssertEqual(snapshot.elementFromPoint(x: 25, y: 25), 30)
        XCTAssertEqual(snapshot.elementFromPoint(x: 20, y: 20), 30)
        XCTAssertEqual(snapshot.elementFromPoint(x: 10, y: 10), 10)
        XCTAssertEqual(snapshot.elementFromPoint(x: 30, y: 25), 10)
        XCTAssertEqual(snapshot.elementFromPoint(x: 25, y: 30), 10)
        XCTAssertEqual(snapshot.elementFromPoint(x: 100, y: 50), UInt64.max)
        XCTAssertEqual(snapshot.focusedElement(), 10)
    }

    func testSelectionUsesNearestContainerAndPreservesSelectedOrder() async {
        var root = queryElement(0, parentID: nil)
        root.supportsSelection = true
        var nested = queryElement(10)
        nested.supportsSelection = true
        var selected = queryElement(12, parentID: 11)
        selected.isSelected = true
        var unselected = queryElement(13, parentID: 10)
        unselected.isSelected = false
        var rootFirst = queryElement(21)
        rootFirst.isSelected = true
        var rootLast = queryElement(9)
        rootLast.isSelected = true
        let snapshot = UIAQuerySnapshot([
            root, nested, queryElement(11, parentID: 10), selected, unselected, rootFirst, rootLast,
        ])

        XCTAssertEqual(snapshot.selectionContainer(12), 10)
        XCTAssertEqual(snapshot.selectionContainer(13), 10)
        XCTAssertEqual(snapshot.selection(10), [12])
        XCTAssertEqual(snapshot.selection(0), [21, 9])
        XCTAssertNil(snapshot.selection(11))
        XCTAssertEqual(snapshot.selectionContainer(11), UInt64.max)
        XCTAssertNil(snapshot.selection(999))
    }

    func testBooleanAndToggleQueriesKeepMissingFalseAndTrueDistinct() async {
        let missing = queryElement(1)
        var off = queryElement(2)
        off.isEnabled = false
        off.isOffscreen = false
        off.isSelected = false
        off.supportsValue = true
        off.isReadOnly = false
        off.toggleState = .off
        var on = queryElement(3)
        on.hasKeyboardFocus = true
        on.isKeyboardFocusable = true
        on.isOffscreen = true
        on.isSelected = true
        on.supportsValue = true
        on.isPassword = true
        on.toggleState = .on
        var mixed = queryElement(4)
        mixed.toggleState = .indeterminate
        let snapshot = UIAQuerySnapshot([missing, off, on, mixed])

        for property in [SWU_UIA_BOOL_IS_OFFSCREEN, SWU_UIA_BOOL_IS_SELECTED, SWU_UIA_BOOL_IS_READ_ONLY] {
            XCTAssertEqual(snapshot.boolProperty(1, property: Int32(property)), -1)
            XCTAssertEqual(snapshot.boolProperty(2, property: Int32(property)), 0)
            XCTAssertEqual(snapshot.boolProperty(3, property: Int32(property)), 1)
        }
        XCTAssertEqual(snapshot.boolProperty(2, property: Int32(SWU_UIA_BOOL_IS_ENABLED)), 0)
        XCTAssertEqual(snapshot.boolProperty(3, property: Int32(SWU_UIA_BOOL_IS_ENABLED)), 1)
        XCTAssertEqual(snapshot.boolProperty(3, property: Int32(SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS)), 1)
        XCTAssertEqual(snapshot.boolProperty(3, property: Int32(SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE)), 1)
        XCTAssertEqual(snapshot.boolProperty(3, property: Int32(SWU_UIA_BOOL_IS_PASSWORD)), 1)
        XCTAssertEqual(snapshot.toggleState(1), -1)
        XCTAssertEqual(snapshot.toggleState(2), 0)
        XCTAssertEqual(snapshot.toggleState(3), 1)
        XCTAssertEqual(snapshot.toggleState(4), 2)
    }

    func testStringDefaultsAndPatternPredicatesKeepExistingMeaning() async {
        var element = queryElement(1, name: "Name")
        element.value = "Value"
        element.helpText = "Help"
        element.automationID = "Automation"
        element.controlType = Int32(SWU_UIA_CONTROL_TYPE_EDIT)
        element.hasDefaultAction = true
        element.supportsValue = true
        element.toggleState = .off
        element.isSelected = false
        element.supportsSelection = true
        element.isVirtualizedPlaceholder = true
        let snapshot = UIAQuerySnapshot([element])

        XCTAssertEqual(snapshot.stringProperty(1, property: Int32(SWU_UIA_STRING_NAME)), "Name")
        XCTAssertEqual(snapshot.stringProperty(1, property: Int32(SWU_UIA_STRING_VALUE)), "Value")
        XCTAssertEqual(snapshot.stringProperty(1, property: Int32(SWU_UIA_STRING_HELP_TEXT)), "Help")
        XCTAssertEqual(snapshot.stringProperty(1, property: Int32(SWU_UIA_STRING_AUTOMATION_ID)), "Automation")
        XCTAssertEqual(snapshot.stringProperty(1, property: Int32(SWU_UIA_STRING_CLASS_NAME)), "SwiftWindowsUI.View")
        XCTAssertNil(snapshot.stringProperty(1, property: -1))
        XCTAssertEqual(snapshot.controlType(1), Int32(SWU_UIA_CONTROL_TYPE_EDIT))
        XCTAssertEqual(snapshot.hasInvokeAction(1), 1)
        for pattern in [
            SWU_UIA_PATTERN_VALUE, SWU_UIA_PATTERN_TOGGLE, SWU_UIA_PATTERN_SELECTION,
            SWU_UIA_PATTERN_SELECTION_ITEM, SWU_UIA_PATTERN_VIRTUALIZED_ITEM,
        ] {
            XCTAssertEqual(snapshot.supportsPattern(1, pattern: Int32(pattern)), 1)
        }
        XCTAssertEqual(snapshot.supportsPattern(1, pattern: -1), 0)

        element.className = "Custom"
        element.isPassword = true
        let changed = UIAQuerySnapshot([element])
        XCTAssertEqual(changed.stringProperty(1, property: Int32(SWU_UIA_STRING_CLASS_NAME)), "Custom")
        XCTAssertEqual(changed.supportsPattern(1, pattern: Int32(SWU_UIA_PATTERN_VALUE)), 0)
    }

    func testMissingElementsAndEmptySelectionKeepTheirSentinels() async {
        var root = queryElement(0, parentID: nil)
        root.supportsSelection = true
        let snapshot = UIAQuerySnapshot([root])

        XCTAssertNil(snapshot.stringProperty(99, property: Int32(SWU_UIA_STRING_NAME)))
        XCTAssertEqual(snapshot.boundingRectangle(99), Rect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(snapshot.controlType(99), Int32(SWU_UIA_CONTROL_TYPE_GROUP))
        XCTAssertEqual(snapshot.boolProperty(99, property: Int32(SWU_UIA_BOOL_IS_ENABLED)), -1)
        XCTAssertEqual(snapshot.boolProperty(0, property: -1), -1)
        XCTAssertEqual(snapshot.hasInvokeAction(99), 0)
        XCTAssertEqual(snapshot.supportsPattern(99, pattern: Int32(SWU_UIA_PATTERN_VALUE)), 0)
        XCTAssertEqual(snapshot.toggleState(99), -1)
        XCTAssertEqual(snapshot.navigate(99, direction: Int32(SWU_UIA_NAV_PARENT)), UInt64.max)
        XCTAssertEqual(snapshot.navigate(0, direction: -1), UInt64.max)
        XCTAssertEqual(snapshot.navigate(0, direction: Int32(SWU_UIA_NAV_PARENT)), UInt64.max)
        XCTAssertEqual(snapshot.elementFromPoint(x: -1, y: -1), UInt64.max)
        XCTAssertEqual(snapshot.focusedElement(), UInt64.max)
        XCTAssertEqual(snapshot.selectionContainer(99), UInt64.max)
        XCTAssertNil(snapshot.selection(99))
        XCTAssertEqual(snapshot.selection(0), [])
    }

    func testBridgeCapturesFreshValuesForEachNameQuery() async throws {
        try await MainActor.run {
            let source = QuerySnapshotTreeSource([queryElement(0, parentID: nil, name: "Before")])
            let bridge = UIAProviderBridge(source: source)
            defer { withExtendedLifetime(bridge) {} }
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            defer { SWU_UIAReleaseProvider(root) }

            XCTAssertEqual(source.snapshotReads, 0)
            XCTAssertEqual(queryProviderName(root), "Before")
            XCTAssertEqual(source.snapshotReads, 1)
            source.elements[0].name = "After"
            XCTAssertEqual(queryProviderName(root), "After")
            XCTAssertEqual(source.snapshotReads, 2)
        }
    }

    func testRuntimeIDDoesNotIntroduceAProjectionRead() async throws {
        try await MainActor.run {
            let source = QuerySnapshotTreeSource([])
            let bridge = UIAProviderBridge(source: source)
            defer { withExtendedLifetime(bridge) {} }
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            defer { SWU_UIAReleaseProvider(root) }

            var count: Int32 = -1
            XCTAssertEqual(SWU_UIAProviderGetRuntimeIdResult(root, nil, 0, &count), 0)
            XCTAssertEqual(count, 0)
            XCTAssertEqual(source.snapshotReads, 0)
        }
    }

    func testSelectionCountAndFillCaptureSeparatelyAndAcceptShrinking() async throws {
        try await MainActor.run {
            let source = QuerySnapshotTreeSource(selectionQueryElements([12, 13]))
            let bridge = UIAProviderBridge(source: source)
            defer { withExtendedLifetime(bridge) {} }
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            defer { SWU_UIAReleaseProvider(root) }
            let selection = try XCTUnwrap(SWU_UIAProviderGetSelectionPattern(root))
            defer { SWU_UIAReleaseProvider(selection) }
            source.snapshotReads = 0
            source.nextSnapshots = [selectionQueryElements([12, 13]), selectionQueryElements([13])]

            var selected: UnsafeMutableRawPointer?
            XCTAssertEqual(SWU_UIASelectionProviderGetSelectedAtResult(selection, 0, &selected), 0)
            defer { SWU_UIAReleaseProvider(selected) }
            XCTAssertNotNil(selected)
            XCTAssertEqual(source.snapshotReads, 2)
            XCTAssertTrue(source.nextSnapshots.isEmpty)
            XCTAssertEqual(queryProviderName(selected), "Second")
        }
    }

    func testSelectionCountAndFillRejectGrowthInsteadOfTruncatingSuccess() async throws {
        try await MainActor.run {
            let source = QuerySnapshotTreeSource(selectionQueryElements([12]))
            let bridge = UIAProviderBridge(source: source)
            defer { withExtendedLifetime(bridge) {} }
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            defer { SWU_UIAReleaseProvider(root) }
            let selection = try XCTUnwrap(SWU_UIAProviderGetSelectionPattern(root))
            defer { SWU_UIAReleaseProvider(selection) }
            source.snapshotReads = 0
            source.nextSnapshots = [selectionQueryElements([12]), selectionQueryElements([12, 13])]

            var count: Int32 = -1
            XCTAssertEqual(
                SWU_UIASelectionProviderGetSelectedCountResult(selection, &count),
                Int32(bitPattern: 0x8013_1509))
            XCTAssertEqual(count, 0)
            XCTAssertEqual(source.snapshotReads, 2)
            XCTAssertTrue(source.nextSnapshots.isEmpty)
        }
    }

    func testEmptyAndMissingSelectionDoNotIntroduceFillReads() async throws {
        try await MainActor.run {
            let source = QuerySnapshotTreeSource(selectionQueryElements([]))
            let bridge = UIAProviderBridge(source: source)
            defer { withExtendedLifetime(bridge) {} }
            let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            defer { SWU_UIAReleaseProvider(root) }
            let selection = try XCTUnwrap(SWU_UIAProviderGetSelectionPattern(root))
            defer { SWU_UIAReleaseProvider(selection) }
            source.snapshotReads = 0

            var count: Int32 = -1
            XCTAssertEqual(SWU_UIASelectionProviderGetSelectedCountResult(selection, &count), 0)
            XCTAssertEqual(count, 0)
            XCTAssertEqual(source.snapshotReads, 1)

            source.elements = []
            source.snapshotReads = 0
            count = -1
            XCTAssertEqual(
                SWU_UIASelectionProviderGetSelectedCountResult(selection, &count),
                Int32(bitPattern: 0x8013_1509))
            XCTAssertEqual(count, 0)
            XCTAssertEqual(source.snapshotReads, 1)
        }
    }
}
