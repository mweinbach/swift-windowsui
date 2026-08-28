import CUIAInterop
import Dispatch
import Foundation
import SwiftWindowsCore
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform

// These headless fixtures drive the real COM vtables. Native UIA discovery,
// return-provider, disconnect, and event calls are replaced per bridge, so no
// HWND, UIA client, global adapter, or message pump is required.
private enum UIALifetimeHRESULT {
    static let ok: Int32 = 0
    static let unavailable = Int32(bitPattern: 0x8004_0201)
    static let pointer = Int32(bitPattern: 0x8000_4003)
    static let invalidArgument = Int32(bitPattern: 0x8007_0057)
    static let noInterface = Int32(bitPattern: 0x8000_4002)
    static let failed = Int32(bitPattern: 0x8000_4005)
}

@MainActor
private final class UIALifetimeSourceProbe {
    var calls: [String] = []
    var callbackThreadIDs: [UInt32] = []
    var callbacksOnMainThread: [Bool] = []
    var sourceReleases = 0
    var writtenValues: [String] = []
    var onSnapshots: (@MainActor () -> Void)?
    var onMutation: (@MainActor (String) -> Void)?

    func record(_ name: String) {
        calls.append(name)
        callbackThreadIDs.append(GetCurrentThreadId())
        callbacksOnMainThread.append(Thread.isMainThread)
    }

    func recordMutation(_ name: String) {
        record(name)
        let action = onMutation
        onMutation = nil
        action?(name)
    }
}

@MainActor
private final class UIALifetimeSource: UIAElementTreeSource {
    let probe: UIALifetimeSourceProbe
    var snapshots: [UIAElementSnapshot]

    init(probe: UIALifetimeSourceProbe, rootName: String) {
        self.probe = probe
        snapshots = [
            UIAElementSnapshot(
                id: 0, parentID: nil, name: rootName,
                controlType: Int32(SWU_UIA_CONTROL_TYPE_PANE),
                bounds: Rect(x: 0, y: 0, width: 800, height: 600),
                isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
                hasDefaultAction: false),
            UIAElementSnapshot(
                id: 10, parentID: 0, name: "Selection container",
                controlType: Int32(SWU_UIA_CONTROL_TYPE_LIST),
                bounds: Rect(x: 0, y: 0, width: 200, height: 100),
                isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: false,
                hasDefaultAction: false, supportsSelection: true),
            // This deliberately broad fake projection supplies several pattern
            // families on one element. It does not model a native widget.
            UIAElementSnapshot(
                id: 1, parentID: 10, name: "Lifetime control", value: "Initial value",
                controlType: Int32(SWU_UIA_CONTROL_TYPE_CUSTOM),
                bounds: Rect(x: 10, y: 10, width: 100, height: 30),
                isEnabled: true, hasKeyboardFocus: true, isKeyboardFocusable: true,
                isOffscreen: false, hasDefaultAction: true,
                supportsValue: true, isReadOnly: false, toggleState: .off,
                isSelected: true, isVirtualizedPlaceholder: true),
        ]
    }

    isolated deinit { probe.sourceReleases += 1 }

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        probe.record("snapshots")
        let action = probe.onSnapshots
        probe.onSnapshots = nil
        action?()
        // Returning valid data after the hook is intentional: the COM caller
        // must suppress a result when that hook revoked its owner.
        return snapshots
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        probe.recordMutation("invoke:\(elementID)")
        return true
    }

    func uiaSetFocus(elementID: UInt64) {
        probe.recordMutation("focus:\(elementID)")
    }

    func uiaSetValue(elementID: UInt64, value: String) -> Bool {
        probe.writtenValues.append(value)
        probe.recordMutation("value:\(elementID)")
        return true
    }

    func uiaToggle(elementID: UInt64) -> Bool {
        probe.recordMutation("toggle:\(elementID)")
        return true
    }

    func uiaSelect(elementID: UInt64) -> Bool {
        probe.recordMutation("select:\(elementID)")
        return true
    }

    func uiaAddToSelection(elementID: UInt64) -> Bool {
        probe.recordMutation("add:\(elementID)")
        return true
    }

    func uiaRemoveFromSelection(elementID: UInt64) -> Bool {
        probe.recordMutation("remove:\(elementID)")
        return true
    }

    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool {
        probe.recordMutation("realize:\(elementID)")
        return true
    }
}

private enum UIALifetimeEntry: String, CaseIterable {
    case getObject
    case focus
    case structure
    case liveRegion
}

@MainActor
private final class UIALifetimeNativeProbe {
    var listening = true
    var listeningCalls = 0
    var returnCalls = 0
    var disconnectCalls = 0
    var events: [UIALifetimeEntry] = []
    var borrowedReturnAddresses: [UInt] = []
    var borrowedDisconnectAddresses: [UInt] = []
    var returnResult: LRESULT = 701
    var disconnectResult = UIALifetimeHRESULT.ok
    var onListening: (@MainActor () -> Void)?
    var onReturn: (@MainActor (UnsafeMutableRawPointer) -> Void)?
    var onDisconnect: (@MainActor (UnsafeMutableRawPointer) -> Void)?
    var onEvent: (@MainActor (UIALifetimeEntry, UnsafeMutableRawPointer) -> Void)?

    func makeCalls() -> UIAProviderNativeCalls {
        UIAProviderNativeCalls(
            clientsAreListening: { [self] in
                listeningCalls += 1
                let action = onListening
                onListening = nil
                action?()
                return listening
            },
            returnProvider: { [self] _, _, _, provider in
                returnCalls += 1
                borrowedReturnAddresses.append(UInt(bitPattern: provider))
                let action = onReturn
                onReturn = nil
                action?(provider)
                // This adapter borrows the argument. Only an explicitly
                // retained client escape may release an additional reference.
                return returnResult
            },
            disconnectProvider: { [self] provider in
                disconnectCalls += 1
                borrowedDisconnectAddresses.append(UInt(bitPattern: provider))
                let action = onDisconnect
                onDisconnect = nil
                action?(provider)
                return disconnectResult
            },
            raiseFocusChanged: { [self] in emit(.focus, provider: $0) },
            raiseStructureChanged: { [self] in emit(.structure, provider: $0) },
            raiseLiveRegionChanged: { [self] in emit(.liveRegion, provider: $0) })
    }

    private func emit(_ event: UIALifetimeEntry, provider: UnsafeMutableRawPointer) {
        events.append(event)
        let action = onEvent
        onEvent = nil
        action?(event, provider)
    }
}

@MainActor
private final class UIALifetimeFixture {
    let probe = UIALifetimeSourceProbe()
    let native = UIALifetimeNativeProbe()
    var source: UIALifetimeSource?
    var bridge: UIAProviderBridge?
    private var clientReferences: [UnsafeMutableRawPointer] = []

    var clientReferenceCount: Int { clientReferences.count }

    init(rootName: String = "Lifetime root") {
        let source = UIALifetimeSource(probe: probe, rootName: rootName)
        self.source = source
        bridge = UIAProviderBridge(source: source, nativeCalls: native.makeCalls())
    }

    isolated deinit {
        for provider in clientReferences.reversed() { SWU_UIAReleaseProvider(provider) }
    }

    func root(file: StaticString = #filePath, line: UInt = #line) throws -> UnsafeMutableRawPointer {
        let provider = try XCTUnwrap(bridge?.retainedRootProviderForTesting(), file: file, line: line)
        clientReferences.append(provider)
        return provider
    }

    func firstChild(
        of provider: UnsafeMutableRawPointer, file: StaticString = #filePath, line: UInt = #line
    ) throws -> UnsafeMutableRawPointer {
        try ownResult(file: file, line: line) {
            SWU_UIAProviderNavigateResult(provider, Int32(SWU_UIA_NAV_FIRST_CHILD), $0)
        }
    }

    func pattern(
        _ kind: Int32, of provider: UnsafeMutableRawPointer,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> UnsafeMutableRawPointer {
        try ownResult(file: file, line: line) { SWU_UIAProviderGetPatternResult(provider, kind, $0) }
    }

    func ownResult(
        file: StaticString = #filePath, line: UInt = #line,
        _ call: (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    ) throws -> UnsafeMutableRawPointer {
        var provider: UnsafeMutableRawPointer?
        let status = call(&provider)
        if let provider { clientReferences.append(provider) }
        XCTAssertEqual(status, UIALifetimeHRESULT.ok, file: file, line: line)
        return try XCTUnwrap(provider, file: file, line: line)
    }

    func retainBorrowedProvider(_ provider: UnsafeMutableRawPointer) {
        SWU_UIAAddRefProvider(provider)
        clientReferences.append(provider)
    }

    func release(
        _ provider: UnsafeMutableRawPointer, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let index = clientReferences.firstIndex(of: provider) else {
            XCTFail("Fixture does not own this COM reference", file: file, line: line)
            return
        }
        clientReferences.remove(at: index)
        SWU_UIAReleaseProvider(provider)
    }

    func releaseAllClientReferences() {
        let detached = clientReferences
        clientReferences = []
        for provider in detached.reversed() { SWU_UIAReleaseProvider(provider) }
    }

    func transferReferenceToWorker(
        _ provider: UnsafeMutableRawPointer, file: StaticString = #filePath, line: UInt = #line
    ) throws -> UInt {
        let index = try XCTUnwrap(clientReferences.firstIndex(of: provider), file: file, line: line)
        clientReferences.remove(at: index)
        // Removing this slot transfers its existing +1; it does not release it.
        return UInt(bitPattern: provider)
    }

    func dropOwners() {
        bridge = nil
        source = nil
    }

    func call(_ entry: UIALifetimeEntry) -> LRESULT? {
        switch entry {
        case .getObject:
            return bridge?.handleAccessibilityGetObject(hwnd: nil, wParam: 0, lParam: -25)
        case .focus:
            bridge?.raiseFocusChanged(elementID: 1)
        case .structure:
            bridge?.raiseStructureChanged()
        case .liveRegion:
            bridge?.raiseLiveRegionChanged(elementID: 1)
        }
        return nil
    }
}

// These buffer helpers have no actor isolation or shared state. A worker copies
// and frees its BSTR before returning only Sendable values to the main actor.
private func uiaLifetimeCopyAndFree(_ value: UnsafeMutablePointer<UInt16>?) -> String? {
    guard let value else { return nil }
    defer { SWU_UIAFreeString(value) }
    var count = 0
    while value[count] != 0 { count += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: count), as: UTF16.self)
}

private func uiaLifetimeReadName(_ provider: UnsafeMutableRawPointer) -> (status: Int32, name: String?) {
    var value: UnsafeMutablePointer<UInt16>?
    let status = SWU_UIAProviderGetNameResult(provider, &value)
    return (status, uiaLifetimeCopyAndFree(value))
}

@MainActor
private func uiaLifetimeSetValue(_ provider: UnsafeMutableRawPointer, to value: String) -> Int32 {
    let units = Array(value.utf16) + [0]
    return units.withUnsafeBufferPointer {
        SWU_UIAValueProviderSetValueResult(provider, $0.baseAddress, Int32($0.count - 1))
    }
}

@MainActor
private func uiaLifetimeExpectEmptyProvider(
    _ expected: Int32 = UIALifetimeHRESULT.unavailable,
    file: StaticString = #filePath, line: UInt = #line,
    _ call: (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
) {
    let untouched = UnsafeMutableRawPointer(bitPattern: 1)!
    var provider: UnsafeMutableRawPointer? = untouched
    XCTAssertEqual(call(&provider), expected, file: file, line: line)
    XCTAssertNil(provider, file: file, line: line)
    if let provider, provider != untouched { SWU_UIAReleaseProvider(provider) }
}

@MainActor
private func uiaLifetimeExpectEmptyString(
    _ expected: Int32 = UIALifetimeHRESULT.unavailable,
    file: StaticString = #filePath, line: UInt = #line,
    _ call: (UnsafeMutablePointer<UnsafeMutablePointer<UInt16>?>) -> Int32
) {
    let untouched = UnsafeMutablePointer<UInt16>(bitPattern: 1)!
    var value: UnsafeMutablePointer<UInt16>? = untouched
    XCTAssertEqual(call(&value), expected, file: file, line: line)
    XCTAssertNil(value, file: file, line: line)
    if let value, value != untouched { SWU_UIAFreeString(value) }
}

@MainActor
private func uiaLifetimeExpectZero(
    _ expected: Int32 = UIALifetimeHRESULT.unavailable,
    file: StaticString = #filePath, line: UInt = #line,
    _ call: (UnsafeMutablePointer<Int32>) -> Int32
) {
    var value: Int32 = 99
    XCTAssertEqual(call(&value), expected, file: file, line: line)
    XCTAssertEqual(value, 0, file: file, line: line)
}

@MainActor
private func uiaLifetimeExpectNoRoot(
    _ fixture: UIALifetimeFixture, file: StaticString = #filePath, line: UInt = #line
) {
    let unexpected = fixture.bridge?.retainedRootProviderForTesting()
    XCTAssertNil(unexpected, file: file, line: line)
    if let unexpected { SWU_UIAReleaseProvider(unexpected) }
}

final class UIAProviderLifetimeTests: XCTestCase {
    func testEscapedRootDoesNotKeepItsBridgeOrSourceAlive() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            weak var bridge = fixture.bridge
            weak var source = fixture.source
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            let live = uiaLifetimeReadName(root)
            XCTAssertEqual(live.status, UIALifetimeHRESULT.ok)
            XCTAssertEqual(live.name, "Lifetime root")
            let calls = fixture.probe.calls

            fixture.dropOwners()

            XCTAssertNil(bridge)
            XCTAssertNil(source)
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
            XCTAssertNotNil(context, "The escaped root must own the callback box")
            uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(root, $0) }
            XCTAssertEqual(fixture.probe.calls, calls)
            XCTAssertEqual(fixture.native.disconnectCalls, 0, "Deinit must not call outbound UIA cleanup")
            fixture.release(root)
            XCTAssertNil(context, "Releasing the last provider must release the shared box")
        }
    }

    func testEscapedChildAndValuePatternShareTheContextUntilTheirFinalRelease() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            let container = try fixture.firstChild(of: root)
            let child = try fixture.firstChild(of: container)
            let value = try fixture.pattern(Int32(SWU_UIA_PATTERN_VALUE), of: child)
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            weak var source = fixture.source
            fixture.release(root)
            fixture.release(container)
            let calls = fixture.probe.calls

            fixture.dropOwners()

            XCTAssertNil(source)
            XCTAssertNotNil(context)
            uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(child, $0) }
            fixture.release(child)
            XCTAssertNotNil(context, "The separately retained pattern still owns its provider")
            uiaLifetimeExpectEmptyString { SWU_UIAValueProviderGetValueResult(value, $0) }
            XCTAssertEqual(uiaLifetimeSetValue(value, to: "must not write"), UIALifetimeHRESULT.unavailable)
            XCTAssertEqual(fixture.probe.calls, calls)
            XCTAssertTrue(fixture.probe.writtenValues.isEmpty)
            fixture.release(value)
            XCTAssertNil(context)
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
        }
    }

    func testEveryHeldPatternFamilyRejectsWorkAfterExplicitDisconnect() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            let container = try fixture.firstChild(of: root)
            let child = try fixture.firstChild(of: container)
            let invoke = try fixture.pattern(Int32(SWU_UIA_PATTERN_INVOKE), of: child)
            let value = try fixture.pattern(Int32(SWU_UIA_PATTERN_VALUE), of: child)
            let toggle = try fixture.pattern(Int32(SWU_UIA_PATTERN_TOGGLE), of: child)
            let selection = try fixture.pattern(Int32(SWU_UIA_PATTERN_SELECTION), of: container)
            let item = try fixture.pattern(Int32(SWU_UIA_PATTERN_SELECTION_ITEM), of: child)
            let virtualized = try fixture.pattern(Int32(SWU_UIA_PATTERN_VIRTUALIZED_ITEM), of: child)
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            var liveValue: UnsafeMutablePointer<UInt16>?
            XCTAssertEqual(SWU_UIAValueProviderGetValueResult(value, &liveValue), UIALifetimeHRESULT.ok)
            XCTAssertEqual(uiaLifetimeCopyAndFree(liveValue), "Initial value")
            var selectedCount: Int32 = -1
            XCTAssertEqual(
                SWU_UIASelectionProviderGetSelectedCountResult(selection, &selectedCount), UIALifetimeHRESULT.ok)
            XCTAssertEqual(selectedCount, 1)

            fixture.bridge?.disconnect()
            let calls = fixture.probe.calls

            XCTAssertNotNil(fixture.source, "Keep the source alive to detect any forbidden callbacks")
            XCTAssertEqual(SWU_UIAProviderInvokeResult(invoke), UIALifetimeHRESULT.unavailable)
            uiaLifetimeExpectEmptyString { SWU_UIAValueProviderGetValueResult(value, $0) }
            XCTAssertEqual(uiaLifetimeSetValue(value, to: ""), UIALifetimeHRESULT.unavailable)
            uiaLifetimeExpectZero { SWU_UIAValueProviderIsReadOnlyResult(value, $0) }
            uiaLifetimeExpectZero { SWU_UIAToggleProviderGetStateResult(toggle, $0) }
            XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), UIALifetimeHRESULT.unavailable)
            uiaLifetimeExpectZero { SWU_UIASelectionItemProviderIsSelectedResult(item, $0) }
            XCTAssertEqual(SWU_UIASelectionItemProviderSelectResult(item), UIALifetimeHRESULT.unavailable)
            XCTAssertEqual(SWU_UIASelectionItemProviderAddToSelectionResult(item), UIALifetimeHRESULT.unavailable)
            XCTAssertEqual(SWU_UIASelectionItemProviderRemoveFromSelectionResult(item), UIALifetimeHRESULT.unavailable)
            uiaLifetimeExpectEmptyProvider { SWU_UIASelectionItemProviderGetSelectionContainerResult(item, $0) }
            uiaLifetimeExpectZero { SWU_UIASelectionProviderGetSelectedCountResult(selection, $0) }
            uiaLifetimeExpectEmptyProvider { SWU_UIASelectionProviderGetSelectedAtResult(selection, 0, $0) }
            uiaLifetimeExpectZero { SWU_UIASelectionProviderCanSelectMultipleResult(selection, $0) }
            uiaLifetimeExpectZero { SWU_UIASelectionProviderIsSelectionRequiredResult(selection, $0) }
            XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtualized), UIALifetimeHRESULT.unavailable)
            XCTAssertEqual(fixture.probe.calls, calls)
            XCTAssertTrue(fixture.probe.writtenValues.isEmpty)
            fixture.dropOwners()
            XCTAssertNotNil(context)
            fixture.releaseAllClientReferences()
            XCTAssertNil(context)
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
        }
    }

    func testRevokedElementQueriesClearOutputsWithoutCallingTheLiveSource() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            let container = try fixture.firstChild(of: root)
            let child = try fixture.firstChild(of: container)
            fixture.bridge?.disconnect()
            let calls = fixture.probe.calls

            for provider in [root, child] {
                uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(provider, $0) }
                uiaLifetimeExpectZero { SWU_UIAProviderGetControlTypeResult(provider, $0) }
                uiaLifetimeExpectZero { SWU_UIAProviderGetProviderOptionsResult(provider, $0) }
                uiaLifetimeExpectZero { SWU_UIAProviderGetEmbeddedFragmentRootCountResult(provider, $0) }
                uiaLifetimeExpectEmptyProvider { SWU_UIAProviderGetHostRawElementProviderResult(provider, $0) }
                uiaLifetimeExpectEmptyProvider {
                    SWU_UIAProviderNavigateResult(provider, Int32(SWU_UIA_NAV_FIRST_CHILD), $0)
                }
                uiaLifetimeExpectEmptyProvider { SWU_UIAProviderGetFragmentRootResult(provider, $0) }
                uiaLifetimeExpectEmptyProvider {
                    SWU_UIAProviderGetPatternResult(provider, Int32(SWU_UIA_PATTERN_INVOKE), $0)
                }
                XCTAssertEqual(SWU_UIAProviderSetFocusResult(provider), UIALifetimeHRESULT.unavailable)
                var left = 99.0
                var top = 99.0
                var width = 99.0
                var height = 99.0
                XCTAssertEqual(
                    SWU_UIAProviderGetBoundingRectangleResult(provider, &left, &top, &width, &height),
                    UIALifetimeHRESULT.unavailable)
                XCTAssertEqual([left, top, width, height], [0, 0, 0, 0])
                var count: Int32 = 99
                var runtimeID = [Int32](repeating: 777, count: 8)
                let status = runtimeID.withUnsafeMutableBufferPointer {
                    SWU_UIAProviderGetRuntimeIdResult(provider, $0.baseAddress, Int32($0.count), &count)
                }
                XCTAssertEqual(status, UIALifetimeHRESULT.unavailable)
                XCTAssertEqual(count, 0)
                XCTAssertEqual(runtimeID, [Int32](repeating: 777, count: 8))
                for property in [
                    SWU_UIA_BOOL_IS_ENABLED, SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS,
                    SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE, SWU_UIA_BOOL_IS_OFFSCREEN,
                    SWU_UIA_BOOL_IS_PASSWORD, SWU_UIA_BOOL_IS_READ_ONLY, SWU_UIA_BOOL_IS_SELECTED,
                ] {
                    var value: Int32 = 99
                    var hasValue: Int32 = 99
                    XCTAssertEqual(
                        SWU_UIAProviderGetBoolPropertyResult(provider, Int32(property), &value, &hasValue),
                        UIALifetimeHRESULT.unavailable)
                    XCTAssertEqual(value, 0)
                    XCTAssertEqual(hasValue, 0)
                }
            }
            uiaLifetimeExpectEmptyProvider { SWU_UIAProviderGetFocusResult(root, $0) }
            uiaLifetimeExpectEmptyProvider { SWU_UIAProviderElementFromPointResult(root, 20, 20, $0) }
            XCTAssertEqual(fixture.probe.calls, calls)
            XCTAssertNotNil(fixture.source)
        }
    }

    func testInvalidArgumentsTakePrecedenceOverRevokedAvailability() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            let container = try fixture.firstChild(of: root)
            let child = try fixture.firstChild(of: container)
            let value = try fixture.pattern(Int32(SWU_UIA_PATTERN_VALUE), of: child)
            let selection = try fixture.pattern(Int32(SWU_UIA_PATTERN_SELECTION), of: container)
            fixture.bridge?.disconnect()
            let calls = fixture.probe.calls

            let missingOutputs: [(String, @MainActor () -> Int32)] = [
                ("name", { SWU_UIAProviderGetNameResult(child, nil) }),
                ("control type", { SWU_UIAProviderGetControlTypeResult(child, nil) }),
                ("options", { SWU_UIAProviderGetProviderOptionsResult(root, nil) }),
                ("embedded roots", { SWU_UIAProviderGetEmbeddedFragmentRootCountResult(root, nil) }),
                ("host provider", { SWU_UIAProviderGetHostRawElementProviderResult(root, nil) }),
                ("navigation", { SWU_UIAProviderNavigateResult(root, Int32(SWU_UIA_NAV_FIRST_CHILD), nil) }),
                ("pattern", { SWU_UIAProviderGetPatternResult(child, Int32(SWU_UIA_PATTERN_VALUE), nil) }),
                ("runtime count", { SWU_UIAProviderGetRuntimeIdResult(child, nil, 0, nil) }),
                ("focus", { SWU_UIAProviderGetFocusResult(root, nil) }),
                ("point", { SWU_UIAProviderElementFromPointResult(root, 20, 20, nil) }),
                ("fragment root", { SWU_UIAProviderGetFragmentRootResult(child, nil) }),
                ("value", { SWU_UIAValueProviderGetValueResult(value, nil) }),
                ("read only", { SWU_UIAValueProviderIsReadOnlyResult(value, nil) }),
                ("selection count", { SWU_UIASelectionProviderGetSelectedCountResult(selection, nil) }),
                ("selected provider", { SWU_UIASelectionProviderGetSelectedAtResult(selection, 0, nil) }),
                ("QI", { SWU_UIAProviderQueryInterfaceResult(root, Int32(SWU_UIA_INTERFACE_SIMPLE), nil) }),
            ]
            for (name, call) in missingOutputs {
                XCTAssertEqual(call(), UIALifetimeHRESULT.pointer, name)
            }
            uiaLifetimeExpectEmptyProvider(UIALifetimeHRESULT.invalidArgument) {
                SWU_UIAProviderNavigateResult(root, -1, $0)
            }
            uiaLifetimeExpectEmptyProvider(UIALifetimeHRESULT.invalidArgument) {
                SWU_UIASelectionProviderGetSelectedAtResult(selection, -1, $0)
            }
            var count: Int32 = 99
            XCTAssertEqual(
                SWU_UIAProviderGetRuntimeIdResult(child, nil, -1, &count), UIALifetimeHRESULT.invalidArgument)
            XCTAssertEqual(count, 0)
            count = 99
            XCTAssertEqual(SWU_UIAProviderGetRuntimeIdResult(child, nil, 1, &count), UIALifetimeHRESULT.pointer)
            XCTAssertEqual(count, 0)
            count = 99
            XCTAssertEqual(SWU_UIAProviderGetRuntimeIdResult(child, nil, 0, &count), UIALifetimeHRESULT.unavailable)
            XCTAssertEqual(count, 0)
            XCTAssertEqual(SWU_UIAValueProviderSetValueResult(value, nil, 0), UIALifetimeHRESULT.invalidArgument)
            let units: [UInt16] = [65, 0]
            XCTAssertEqual(
                units.withUnsafeBufferPointer { SWU_UIAValueProviderSetValueResult(value, $0.baseAddress, -1) },
                UIALifetimeHRESULT.invalidArgument)
            var top = 99.0
            var width = 99.0
            var height = 99.0
            XCTAssertEqual(
                SWU_UIAProviderGetBoundingRectangleResult(child, nil, &top, &width, &height),
                UIALifetimeHRESULT.pointer)
            XCTAssertEqual([top, width, height], [0, 0, 0])
            var boolValue: Int32 = 99
            XCTAssertEqual(
                SWU_UIAProviderGetBoolPropertyResult(child, Int32(SWU_UIA_BOOL_IS_ENABLED), &boolValue, nil),
                UIALifetimeHRESULT.pointer)
            XCTAssertEqual(boolValue, 0)
            XCTAssertEqual(fixture.probe.calls, calls)
        }
    }

    func testStaticQueryInterfaceIdentitySurvivesRevocationButPatternDiscoveryDoesNot() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            let child = try fixture.firstChild(of: root)
            let kinds: [Int32] = [
                Int32(SWU_UIA_INTERFACE_UNKNOWN), Int32(SWU_UIA_INTERFACE_SIMPLE),
                Int32(SWU_UIA_INTERFACE_FRAGMENT), Int32(SWU_UIA_INTERFACE_FRAGMENT_ROOT),
                Int32(SWU_UIA_INTERFACE_INVOKE), Int32(SWU_UIA_INTERFACE_VALUE),
                Int32(SWU_UIA_INTERFACE_TOGGLE), Int32(SWU_UIA_INTERFACE_SELECTION),
                Int32(SWU_UIA_INTERFACE_SELECTION_ITEM), Int32(SWU_UIA_INTERFACE_VIRTUALIZED_ITEM),
            ]
            var liveAddresses: [[Int32: UInt]] = [[:], [:]]
            for (index, provider) in [root, child].enumerated() {
                for kind in kinds {
                    if index == 1 && kind == Int32(SWU_UIA_INTERFACE_FRAGMENT_ROOT) {
                        uiaLifetimeExpectEmptyProvider(UIALifetimeHRESULT.noInterface) {
                            SWU_UIAProviderQueryInterfaceResult(provider, kind, $0)
                        }
                    } else {
                        let interface = try fixture.ownResult {
                            SWU_UIAProviderQueryInterfaceResult(provider, kind, $0)
                        }
                        liveAddresses[index][kind] = UInt(bitPattern: interface)
                        fixture.release(interface)
                    }
                }
                XCTAssertEqual(
                    liveAddresses[index][Int32(SWU_UIA_INTERFACE_UNKNOWN)],
                    liveAddresses[index][Int32(SWU_UIA_INTERFACE_SIMPLE)])
                uiaLifetimeExpectEmptyProvider(UIALifetimeHRESULT.ok) {
                    SWU_UIAProviderGetPatternResult(provider, -1, $0)
                }
            }
            fixture.bridge?.disconnect()
            let calls = fixture.probe.calls

            for (index, provider) in [root, child].enumerated() {
                for kind in kinds {
                    if index == 1 && kind == Int32(SWU_UIA_INTERFACE_FRAGMENT_ROOT) {
                        uiaLifetimeExpectEmptyProvider(UIALifetimeHRESULT.noInterface) {
                            SWU_UIAProviderQueryInterfaceResult(provider, kind, $0)
                        }
                    } else {
                        let interface = try fixture.ownResult {
                            SWU_UIAProviderQueryInterfaceResult(provider, kind, $0)
                        }
                        XCTAssertEqual(UInt(bitPattern: interface), liveAddresses[index][kind])
                        // QI returns an interface pointer, not a concrete
                        // provider handle. Only its COM reference is used here.
                        fixture.release(interface)
                    }
                }
                uiaLifetimeExpectEmptyProvider(UIALifetimeHRESULT.noInterface) {
                    SWU_UIAProviderQueryInterfaceResult(provider, -1, $0)
                }
                uiaLifetimeExpectEmptyProvider { SWU_UIAProviderGetPatternResult(provider, -1, $0) }
                uiaLifetimeExpectEmptyProvider {
                    SWU_UIAProviderGetPatternResult(provider, Int32(SWU_UIA_PATTERN_INVOKE), $0)
                }
            }
            XCTAssertEqual(fixture.probe.calls, calls, "Static QI must not consult the model")
        }
    }

    func testDisconnectBeforeLazyRootCreationIsPermanentAndHasNoNativeEffects() async {
        await MainActor.run {
            let fixture = UIALifetimeFixture()
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            fixture.bridge?.disconnect()
            fixture.bridge?.disconnect()

            uiaLifetimeExpectNoRoot(fixture)
            for entry in UIALifetimeEntry.allCases { XCTAssertNil(fixture.call(entry)) }
            XCTAssertNil(fixture.bridge?.lastDisconnectResult)
            XCTAssertEqual(fixture.native.listeningCalls, 0)
            XCTAssertEqual(fixture.native.returnCalls, 0)
            XCTAssertEqual(fixture.native.disconnectCalls, 0)
            XCTAssertTrue(fixture.native.events.isEmpty)
            XCTAssertTrue(fixture.probe.calls.isEmpty)
            XCTAssertEqual(fixture.clientReferenceCount, 0)
            fixture.dropOwners()
            XCTAssertNil(context)
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
        }
    }

    func testNativeDisconnectFailureSeesRevocationBeforeReentryAndNeverRetries() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            fixture.native.disconnectResult = UIALifetimeHRESULT.failed
            fixture.native.onDisconnect = { [weak fixture] borrowed in
                guard let fixture else { return XCTFail("Fixture disappeared during native disconnect") }
                XCTAssertEqual(borrowed, root)
                uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(borrowed, $0) }
                uiaLifetimeExpectNoRoot(fixture)
                fixture.bridge?.disconnect()
                for entry in UIALifetimeEntry.allCases { XCTAssertNil(fixture.call(entry)) }
                XCTAssertNil(fixture.bridge?.lastDisconnectResult, "The native call has not returned yet")
            }
            let calls = fixture.probe.calls

            fixture.bridge?.disconnect()
            fixture.bridge?.disconnect()

            XCTAssertEqual(fixture.bridge?.lastDisconnectResult, UIALifetimeHRESULT.failed)
            XCTAssertEqual(fixture.native.disconnectCalls, 1)
            XCTAssertEqual(fixture.native.borrowedDisconnectAddresses, [UInt(bitPattern: root)])
            XCTAssertEqual(fixture.native.listeningCalls, 0)
            XCTAssertEqual(fixture.native.returnCalls, 0)
            XCTAssertTrue(fixture.native.events.isEmpty)
            uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(root, $0) }
            XCTAssertEqual(fixture.probe.calls, calls)
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            fixture.dropOwners()
            XCTAssertNotNil(context)
            fixture.releaseAllClientReferences()
            XCTAssertNil(context)
        }
    }

    func testReplacementBridgeWithTheSameElementIDsCannotReviveOldProviders() async throws {
        try await MainActor.run {
            let old = UIALifetimeFixture(rootName: "Old root")
            let oldRoot = try old.root()
            weak var oldContext = old.bridge?.callbackContextObjectForTesting
            weak var oldSource = old.source
            XCTAssertEqual(uiaLifetimeReadName(oldRoot).name, "Old root")
            let oldCalls = old.probe.calls
            old.dropOwners()
            XCTAssertNil(oldSource)

            let replacement = UIALifetimeFixture(rootName: "Replacement root")
            let newRoot = try replacement.root()
            weak var newContext = replacement.bridge?.callbackContextObjectForTesting
            XCTAssertNotNil(oldContext)
            XCTAssertNotNil(newContext)
            XCTAssertFalse(oldContext === newContext)
            let live = uiaLifetimeReadName(newRoot)
            XCTAssertEqual(live.status, UIALifetimeHRESULT.ok)
            XCTAssertEqual(live.name, "Replacement root")
            let replacementCalls = replacement.probe.calls

            uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(oldRoot, $0) }
            uiaLifetimeExpectEmptyProvider {
                SWU_UIAProviderNavigateResult(oldRoot, Int32(SWU_UIA_NAV_FIRST_CHILD), $0)
            }

            XCTAssertEqual(old.probe.calls, oldCalls)
            XCTAssertEqual(replacement.probe.calls, replacementCalls, "Old handles must not consult the new source")
            old.release(oldRoot)
            XCTAssertNil(oldContext)
            XCTAssertNotNil(newContext)
            XCTAssertEqual(uiaLifetimeReadName(newRoot).name, "Replacement root")
            replacement.dropOwners()
            replacement.releaseAllClientReferences()
            XCTAssertNil(newContext)
        }
    }

    func testNativeReturnBorrowsItsProviderAndBalancesTheTemporaryCallReference() async {
        await MainActor.run {
            let fixture = UIALifetimeFixture()
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            weak var source = fixture.source
            fixture.native.onReturn = { [weak fixture] borrowed in
                guard let fixture else { return XCTFail("Fixture disappeared during native return") }
                let live = uiaLifetimeReadName(borrowed)
                XCTAssertEqual(live.status, UIALifetimeHRESULT.ok)
                XCTAssertEqual(live.name, "Lifetime root")
                // Model UIA taking its own client reference. The adapter does
                // not consume the bridge's borrowed argument.
                fixture.retainBorrowedProvider(borrowed)
            }

            XCTAssertEqual(fixture.call(.getObject), LRESULT(701))

            XCTAssertEqual(fixture.native.listeningCalls, 1)
            XCTAssertEqual(fixture.native.returnCalls, 1)
            XCTAssertEqual(fixture.native.borrowedReturnAddresses.count, 1)
            XCTAssertEqual(fixture.clientReferenceCount, 1)
            fixture.dropOwners()
            XCTAssertNil(source)
            XCTAssertNotNil(context, "Only the explicit client escape should remain")
            fixture.releaseAllClientReferences()
            XCTAssertNil(context, "The temporary native-call reference must not leak")
            XCTAssertEqual(fixture.native.disconnectCalls, 0)
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
        }
    }

    func testNativeReturnThatDisconnectsAndDropsOwnersCannotPublishItsResult() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            _ = try fixture.root()
            weak var bridge = fixture.bridge
            weak var source = fixture.source
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            fixture.native.returnResult = 902
            fixture.native.onReturn = { [weak fixture] borrowed in
                guard let fixture else { return XCTFail("Fixture disappeared during native return") }
                fixture.bridge?.disconnect()
                XCTAssertNil(fixture.call(.getObject), "Reentry must not start another native return")
                fixture.releaseAllClientReferences()
                fixture.dropOwners()
                XCTAssertNotNil(bridge, "The active instance method must survive the callback")
                XCTAssertNotNil(source)
                XCTAssertNotNil(context)
                uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(borrowed, $0) }
            }
            let calls = fixture.probe.calls

            let result = fixture.call(.getObject)

            XCTAssertNil(result, "A native return value must not escape after logical revocation")
            XCTAssertEqual(fixture.native.returnCalls, 1)
            XCTAssertEqual(fixture.native.disconnectCalls, 1)
            XCTAssertEqual(fixture.native.listeningCalls, 1)
            XCTAssertEqual(fixture.clientReferenceCount, 0)
            XCTAssertEqual(fixture.probe.calls, calls)
            XCTAssertNil(bridge)
            XCTAssertNil(source)
            XCTAssertNil(context, "The borrowed native-call pin must be balanced even after reentry")
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
        }
    }

    func testListeningCallbackCanDisconnectEveryEntryBeforeItMakesNativeEffects() async throws {
        try await MainActor.run {
            for entry in UIALifetimeEntry.allCases {
                let fixture = UIALifetimeFixture()
                _ = try fixture.root()
                weak var context = fixture.bridge?.callbackContextObjectForTesting
                fixture.native.onListening = { [weak fixture] in
                    fixture?.bridge?.disconnect()
                }
                let calls = fixture.probe.calls

                XCTAssertNil(fixture.call(entry), entry.rawValue)

                XCTAssertEqual(fixture.native.listeningCalls, 1, entry.rawValue)
                XCTAssertEqual(fixture.native.disconnectCalls, 1, entry.rawValue)
                XCTAssertEqual(fixture.native.returnCalls, 0, entry.rawValue)
                XCTAssertTrue(fixture.native.events.isEmpty, entry.rawValue)
                XCTAssertEqual(fixture.probe.calls, calls, entry.rawValue)
                uiaLifetimeExpectNoRoot(fixture)
                fixture.dropOwners()
                fixture.releaseAllClientReferences()
                XCTAssertNil(context, entry.rawValue)
            }
        }
    }

    func testNativeEventCallbacksKeepBorrowedProvidersAliveAcrossOwnerRelease() async throws {
        try await MainActor.run {
            for entry in [UIALifetimeEntry.focus, .structure, .liveRegion] {
                let fixture = UIALifetimeFixture()
                _ = try fixture.root()
                weak var bridge = fixture.bridge
                weak var source = fixture.source
                weak var context = fixture.bridge?.callbackContextObjectForTesting
                fixture.native.onEvent = { [weak fixture] event, borrowed in
                    guard let fixture else { return XCTFail("Fixture disappeared during native event") }
                    XCTAssertEqual(event, entry)
                    fixture.bridge?.disconnect()
                    for nested in UIALifetimeEntry.allCases { XCTAssertNil(fixture.call(nested)) }
                    fixture.releaseAllClientReferences()
                    fixture.dropOwners()
                    XCTAssertNotNil(bridge)
                    XCTAssertNotNil(source)
                    XCTAssertNotNil(context)
                    uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(borrowed, $0) }
                }
                let calls = fixture.probe.calls

                XCTAssertNil(fixture.call(entry))

                XCTAssertEqual(fixture.native.events, [entry])
                XCTAssertEqual(fixture.native.listeningCalls, 1)
                XCTAssertEqual(fixture.native.disconnectCalls, 1)
                XCTAssertEqual(fixture.native.returnCalls, 0)
                XCTAssertEqual(fixture.probe.calls, calls)
                XCTAssertEqual(fixture.clientReferenceCount, 0)
                XCTAssertNil(bridge)
                XCTAssertNil(source)
                XCTAssertNil(context, "The event provider and temporary root pin must both be released")
                XCTAssertEqual(fixture.probe.sourceReleases, 1)
            }
        }
    }

    func testInFlightNameCallbackPinsOwnersButSuppressesDataAfterTheirLastReferencesDrop() async throws {
        try await MainActor.run {
            let fixture = UIALifetimeFixture()
            let root = try fixture.root()
            weak var bridge = fixture.bridge
            weak var source = fixture.source
            weak var context = fixture.bridge?.callbackContextObjectForTesting
            fixture.probe.onSnapshots = { [weak fixture] in
                guard let fixture else { return XCTFail("Fixture disappeared during source query") }
                fixture.releaseAllClientReferences()
                fixture.dropOwners()
                XCTAssertNotNil(bridge, "The callback must promote and pin its weak bridge")
                XCTAssertNotNil(source, "The admitted source callback must finish safely")
                XCTAssertNotNil(context)
            }

            // The helper calls GetPropertyValue directly and supplies no extra
            // provider pin. The COM method must survive losing every client ref.
            uiaLifetimeExpectEmptyString { SWU_UIAProviderGetNameResult(root, $0) }

            // root is now only a stale address; never call or release it again.
            XCTAssertEqual(fixture.probe.calls, ["snapshots"], "The source must not be retried")
            XCTAssertEqual(fixture.clientReferenceCount, 0)
            XCTAssertEqual(fixture.probe.sourceReleases, 1)
            XCTAssertEqual(fixture.native.disconnectCalls, 0)
            XCTAssertNil(bridge)
            XCTAssertNil(source)
            XCTAssertNil(context)
        }
    }

    func testInFlightInvokeAndValueCallbacksRunOnceThenSuppressSuccessAfterOwnerRelease() async throws {
        try await MainActor.run {
            for patternKind in [Int32(SWU_UIA_PATTERN_INVOKE), Int32(SWU_UIA_PATTERN_VALUE)] {
                let fixture = UIALifetimeFixture()
                let root = try fixture.root()
                let container = try fixture.firstChild(of: root)
                let child = try fixture.firstChild(of: container)
                let pattern = try fixture.pattern(patternKind, of: child)
                fixture.release(root)
                fixture.release(container)
                fixture.release(child)
                XCTAssertEqual(fixture.clientReferenceCount, 1)
                weak var bridge = fixture.bridge
                weak var source = fixture.source
                weak var context = fixture.bridge?.callbackContextObjectForTesting
                let isValue = patternKind == Int32(SWU_UIA_PATTERN_VALUE)
                let expectedAction = isValue ? "value:1" : "invoke:1"
                fixture.probe.onMutation = { [weak fixture] action in
                    guard let fixture else { return XCTFail("Fixture disappeared during source action") }
                    XCTAssertEqual(action, expectedAction)
                    fixture.releaseAllClientReferences()
                    fixture.dropOwners()
                    XCTAssertNotNil(bridge)
                    XCTAssertNotNil(source)
                    XCTAssertNotNil(context)
                }
                let text = "Åda 👩🏽‍💻 東京"

                let status =
                    isValue
                    ? uiaLifetimeSetValue(pattern, to: text)
                    : SWU_UIAProviderInvokeResult(pattern)

                // The only client reference was released inside the method.
                // Do not reuse this raw pattern address after the call.
                XCTAssertEqual(status, UIALifetimeHRESULT.unavailable)
                XCTAssertEqual(fixture.probe.calls.filter { $0 == expectedAction }.count, 1)
                XCTAssertEqual(fixture.probe.writtenValues, isValue ? [text] : [])
                XCTAssertEqual(fixture.clientReferenceCount, 0)
                XCTAssertEqual(fixture.probe.sourceReleases, 1)
                XCTAssertEqual(fixture.native.disconnectCalls, 0)
                XCTAssertNil(bridge)
                XCTAssertNil(source)
                XCTAssertNil(context)
            }
        }
    }

    func testLiveWorkerQueryMarshalsItsSourceCallbackToTheMainActor() async throws {
        try await uiaLifetimeExerciseLiveWorkerQuery()
    }

    func testFinalEscapedProviderReleaseCanDestroyTheCallbackContextOnAWorker() async throws {
        try await uiaLifetimeExerciseFinalWorkerRelease()
    }
}

private struct UIALifetimeWorkerResult: Sendable {
    let status: Int32
    let name: String?
    let threadID: UInt32
    let isMainThread: Bool
}

// This function is intentionally outside every MainActor-isolated type. Its
// queue closure captures only a Sendable address carrying an owned COM +1 and
// the continuation. No source, bridge, raw pointer, or actor closure crosses.
private func uiaLifetimeReadAndReleaseOnWorker(ownedAddress: UInt) async -> UIALifetimeWorkerResult {
    await withCheckedContinuation { (continuation: CheckedContinuation<UIALifetimeWorkerResult, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
            let threadID = GetCurrentThreadId()
            let isMainThread = Thread.isMainThread
            guard let provider = UnsafeMutableRawPointer(bitPattern: ownedAddress) else {
                continuation.resume(
                    returning: UIALifetimeWorkerResult(
                        status: UIALifetimeHRESULT.pointer, name: nil, threadID: threadID, isMainThread: isMainThread))
                return
            }
            let value = uiaLifetimeReadName(provider)
            let result = UIALifetimeWorkerResult(
                status: value.status, name: value.name, threadID: threadID, isMainThread: isMainThread)
            // Complete both the BSTR cleanup above and the COM release before
            // resuming. A defer after resume would race the lifetime assertions.
            SWU_UIAReleaseProvider(provider)
            continuation.resume(returning: result)
        }
    }
}

@MainActor
private func uiaLifetimeExerciseLiveWorkerQuery() async throws {
    let fixture = UIALifetimeFixture()
    let root = try fixture.root()
    weak var context = fixture.bridge?.callbackContextObjectForTesting
    let mainThreadID = GetCurrentThreadId()
    XCTAssertTrue(Thread.isMainThread)
    XCTAssertTrue(fixture.probe.calls.isEmpty)
    // The fixture still owns its reference. This separate +1 belongs solely to
    // the worker, which releases it before the await finishes.
    SWU_UIAAddRefProvider(root)
    let address = UInt(bitPattern: root)

    let result = await uiaLifetimeReadAndReleaseOnWorker(ownedAddress: address)

    XCTAssertFalse(result.isMainThread)
    XCTAssertNotEqual(result.threadID, mainThreadID)
    XCTAssertEqual(result.status, UIALifetimeHRESULT.ok)
    XCTAssertEqual(result.name, "Lifetime root")
    XCTAssertEqual(fixture.probe.calls, ["snapshots"])
    XCTAssertEqual(fixture.probe.callbackThreadIDs, [mainThreadID])
    XCTAssertEqual(fixture.probe.callbacksOnMainThread, [true])
    XCTAssertNotNil(fixture.bridge, "Keep the live bridge owned across the suspended actor")
    XCTAssertEqual(fixture.clientReferenceCount, 1)
    let stillLive = uiaLifetimeReadName(root)
    XCTAssertEqual(stillLive.status, UIALifetimeHRESULT.ok)
    XCTAssertEqual(stillLive.name, "Lifetime root")
    fixture.dropOwners()
    fixture.releaseAllClientReferences()
    XCTAssertNil(context)
    XCTAssertEqual(fixture.probe.sourceReleases, 1)
}

@MainActor
private func uiaLifetimeExerciseFinalWorkerRelease() async throws {
    let fixture = UIALifetimeFixture()
    let root = try fixture.root()
    weak var bridge = fixture.bridge
    weak var source = fixture.source
    weak var context = fixture.bridge?.callbackContextObjectForTesting
    let mainThreadID = GetCurrentThreadId()
    let address = try fixture.transferReferenceToWorker(root)
    fixture.dropOwners()
    XCTAssertNil(bridge)
    XCTAssertNil(source)
    XCTAssertEqual(fixture.probe.sourceReleases, 1)
    XCTAssertEqual(fixture.clientReferenceCount, 0)
    XCTAssertNotNil(context, "The transferred COM reference is now the only context owner")
    let calls = fixture.probe.calls

    let result = await uiaLifetimeReadAndReleaseOnWorker(ownedAddress: address)

    // The worker saw a revoked provider without dispatching into a dead source,
    // then performed the family's final release before resuming this actor.
    XCTAssertFalse(result.isMainThread)
    XCTAssertNotEqual(result.threadID, mainThreadID)
    XCTAssertEqual(result.status, UIALifetimeHRESULT.unavailable)
    XCTAssertNil(result.name)
    XCTAssertEqual(fixture.probe.calls, calls)
    XCTAssertEqual(fixture.probe.sourceReleases, 1)
    XCTAssertEqual(fixture.native.disconnectCalls, 0)
    XCTAssertNil(context)
}
