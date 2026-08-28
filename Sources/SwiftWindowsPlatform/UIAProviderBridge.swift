import CUIAInterop
import Dispatch
import Foundation
import SwiftWindowsCore
import WinSDK

// UI Automation provider bridge (Stabilization Roadmap, Phase 2 — Win32 slice).
//
// This file is the renderer-neutral, projection-agnostic half of the UIA
// provider: it speaks to the C COM glue in `CUIAInterop` and answers every
// UIA query from a flat snapshot list supplied by a `UIAElementTreeSource`.
// The mapping from the retained `ViewNode` tree (via
// `AccessibilityElementProjection`) to these snapshots lives in the WinSwiftUI
// layer (`RuntimeUIAElementTreeSource`), keeping this module free of any
// SwiftWindowsUI dependency.
//
// Threading: UIA calls raw providers on its own background threads. Every
// callback hops to the main thread before touching the tree source, which is
// main-actor isolated like the rest of the UI stack. Hopping from a UIA
// worker thread preserves the existing synchronous dispatch contract. The
// main thread must remain able to service that dispatch; provider lifetime
// safety does not qualify every COM reentry or Narrator deadlock scenario.

/// A flat, screen-coordinate snapshot of one accessibility element, produced
/// by a `UIAElementTreeSource` on every UIA query. `id` values must be stable
/// across snapshots for the same underlying view; `parentID` is nil only for
/// the root element.
public enum UIAToggleState: Int32, Sendable {
    case off = 0
    case on = 1
    case indeterminate = 2
}

public struct UIAElementSnapshot {
    public var id: UInt64
    public var parentID: UInt64?
    public var name: String
    public var value: String?
    public var helpText: String?
    public var automationID: String?
    /// UIA ClassName; the bridge supplies a default when nil.
    public var className: String?
    /// UIA control type id (`SWU_UIA_CONTROL_TYPE_*` constants).
    public var controlType: Int32
    /// Bounds in screen coordinates.
    public var bounds: Rect
    public var isEnabled: Bool
    public var hasKeyboardFocus: Bool
    public var isKeyboardFocusable: Bool
    /// nil = the IsOffscreen property is not provided.
    public var isOffscreen: Bool?
    /// True when the element has an invokable default action (Invoke pattern).
    public var hasDefaultAction: Bool
    /// Secure inputs expose IsPassword but never expose the Value pattern.
    public var isPassword: Bool
    /// Editable text controls expose IValueProvider, including empty fields.
    public var supportsValue: Bool
    public var isReadOnly: Bool
    /// Non-nil only for checkboxes and switches that expose IToggleProvider.
    public var toggleState: UIAToggleState?
    /// Non-nil only for retained selection rows (ISelectionItemProvider).
    public var isSelected: Bool?
    /// Selection containers own one or more selection-item children.
    public var supportsSelection: Bool
    /// Offscreen lazy-stack placeholders expose IVirtualizedItemProvider.
    public var isVirtualizedPlaceholder: Bool

    public init(
        id: UInt64,
        parentID: UInt64?,
        name: String,
        value: String? = nil,
        helpText: String? = nil,
        automationID: String? = nil,
        className: String? = nil,
        controlType: Int32,
        bounds: Rect,
        isEnabled: Bool,
        hasKeyboardFocus: Bool,
        isKeyboardFocusable: Bool,
        isOffscreen: Bool? = nil,
        hasDefaultAction: Bool,
        isPassword: Bool = false,
        supportsValue: Bool = false,
        isReadOnly: Bool = true,
        toggleState: UIAToggleState? = nil,
        isSelected: Bool? = nil,
        supportsSelection: Bool = false,
        isVirtualizedPlaceholder: Bool = false
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.value = value
        self.helpText = helpText
        self.automationID = automationID
        self.className = className
        self.controlType = controlType
        self.bounds = bounds
        self.isEnabled = isEnabled
        self.hasKeyboardFocus = hasKeyboardFocus
        self.isKeyboardFocusable = isKeyboardFocusable
        self.isOffscreen = isOffscreen
        self.hasDefaultAction = hasDefaultAction
        self.isPassword = isPassword
        self.supportsValue = supportsValue
        self.isReadOnly = isReadOnly
        self.toggleState = toggleState
        self.isSelected = isSelected
        self.supportsSelection = supportsSelection
        self.isVirtualizedPlaceholder = isVirtualizedPlaceholder
    }
}

/// Supplies accessibility element snapshots to `UIAProviderBridge`. Every
/// call re-derives the snapshot list from live state; there is no caching on
/// either side.
@MainActor
public protocol UIAElementTreeSource: AnyObject {
    /// Flat pre-order snapshot list, root first. The root element must use
    /// `UIAProviderBridge.rootElementID` and a nil `parentID`.
    func uiaElementSnapshots() -> [UIAElementSnapshot]
    /// Invokes the element's default action. Returns true when invoked.
    @discardableResult
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool
    /// Requests keyboard focus for the element (no-op when not focusable).
    func uiaSetFocus(elementID: UInt64)
    /// Replaces the full value of an editable, non-secure text control.
    @discardableResult
    func uiaSetValue(elementID: UInt64, value: String) -> Bool
    /// Toggles a checkbox/switch through its existing retained action.
    @discardableResult
    func uiaToggle(elementID: UInt64) -> Bool
    /// Selects or deselects a retained List/Table item.
    @discardableResult
    func uiaSelect(elementID: UInt64) -> Bool
    @discardableResult
    func uiaAddToSelection(elementID: UInt64) -> Bool
    @discardableResult
    func uiaRemoveFromSelection(elementID: UInt64) -> Bool
    /// Scrolls an offscreen lazy-stack placeholder into its realized window.
    @discardableResult
    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool
}

extension UIAElementTreeSource {
    public func uiaSetValue(elementID: UInt64, value: String) -> Bool { false }
    public func uiaToggle(elementID: UInt64) -> Bool {
        uiaInvokeDefaultAction(elementID: elementID)
    }
    public func uiaSelect(elementID: UInt64) -> Bool {
        uiaInvokeDefaultAction(elementID: elementID)
    }
    public func uiaAddToSelection(elementID: UInt64) -> Bool {
        uiaSelect(elementID: elementID)
    }
    public func uiaRemoveFromSelection(elementID: UInt64) -> Bool { false }
    public func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool { false }
}

/// Implemented by objects that can answer `WM_GETOBJECT` for a `Win32Window`.
@MainActor
public protocol Win32WindowAccessibilityProvider: AnyObject {
    /// Returns the LRESULT the window procedure should return for
    /// `WM_GETOBJECT`, or nil to fall through to `DefWindowProc`.
    func handleAccessibilityGetObject(
        hwnd: UnsafeMutableRawPointer?, wParam: WPARAM, lParam: LPARAM
    ) -> LRESULT?
}

/// Native effects are supplied per bridge so lifecycle tests can force failure
/// and reentry without changing process-wide UI Automation state.
@MainActor
struct UIAProviderNativeCalls {
    var clientsAreListening: @MainActor () -> Bool
    var returnProvider: @MainActor (UnsafeMutableRawPointer?, WPARAM, LPARAM, UnsafeMutableRawPointer) -> LRESULT
    var disconnectProvider: @MainActor (UnsafeMutableRawPointer) -> Int32
    var raiseFocusChanged: @MainActor (UnsafeMutableRawPointer) -> Void
    var raiseStructureChanged: @MainActor (UnsafeMutableRawPointer) -> Void
    var raiseLiveRegionChanged: @MainActor (UnsafeMutableRawPointer) -> Void

    static var live: UIAProviderNativeCalls {
        UIAProviderNativeCalls(
            clientsAreListening: { SWU_UIAClientsAreListening() != 0 },
            returnProvider: { hwnd, wParam, lParam, provider in
                LRESULT(SWU_UIAReturnRawElementProvider(hwnd, UInt(wParam), Int(lParam), provider))
            },
            disconnectProvider: { SWU_UIATryDisconnectProvider($0) },
            raiseFocusChanged: { SWU_UIARaiseAutomationFocusChanged($0) },
            raiseStructureChanged: { SWU_UIARaiseStructureChanged($0) },
            raiseLiveRegionChanged: { SWU_UIARaiseLiveRegionChanged($0) })
    }
}

/// Providers retain this box, never the bridge. Its implicit nonisolated
/// destruction only destroys weak storage and can run on any COM thread.
@MainActor
private final class UIAProviderCallbackContext {
    weak var bridge: UIAProviderBridge?
    // Borrowed, not retained: this is read only inside a callback whose native
    // provider already pins the context, never during box destruction.
    var nativeContext: OpaquePointer?

    func withBridge<Result: Sendable>(
        unavailable: Result, _ work: @MainActor (UIAProviderBridge) -> Result
    ) -> Result {
        guard let nativeContext else { return unavailable }
        guard SWU_UIAProviderContextIsAvailable(nativeContext) != 0, let bridge else {
            // Weak zeroing can precede an isolated bridge deinitializer. Make
            // that failure terminal before the C caller publishes any result.
            SWU_UIARevokeProviderContext(nativeContext)
            return unavailable
        }
        defer { withExtendedLifetime(bridge) {} }
        return work(bridge)
    }
}

private func releaseUIAProviderCallbackContext(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<UIAProviderCallbackContext>.fromOpaque(context).release()
}

/// Serves UIA provider objects for one window's accessibility tree.
///
/// The bridge owns the root fragment provider (one per window, handed to UIA
/// via `UiaReturnRawElementProvider`); child providers are created on demand
/// by the C glue during navigation and are reference-counted COM objects
/// whose callbacks all funnel back into this bridge. The bridge must outlive
/// every source callback it admits. Escaped providers instead own a shared
/// native context whose weak Swift bridge reference becomes unavailable.
@MainActor
public final class UIAProviderBridge: Win32WindowAccessibilityProvider {
    /// Element token reserved for the fragment root.
    public static let rootElementID: UInt64 = 0

    private static let noElement = UInt64.max
    /// First runtime-id component marking ids as ours (arbitrary constant).
    private static let runtimeIDPrefix: Int32 = 0x5357
    /// OBJID value UIA clients pass as `lParam` in `WM_GETOBJECT`.
    private static let uiaRootObjectID: Int32 = -25
    private static let defaultClassName = "SwiftWindowsUI.View"

    private let source: any UIAElementTreeSource
    private let nativeCalls: UIAProviderNativeCalls
    private let callbackContext: UIAProviderCallbackContext
    private let nativeContext: OpaquePointer?
    private var hwnd: UnsafeMutableRawPointer?
    private var rootProvider: UnsafeMutableRawPointer?
    private var didDisconnect = false
    internal private(set) var lastDisconnectResult: Int32?

    public convenience init(source: any UIAElementTreeSource) {
        self.init(source: source, nativeCalls: .live)
    }

    internal init(source: any UIAElementTreeSource, nativeCalls: UIAProviderNativeCalls) {
        self.source = source
        self.nativeCalls = nativeCalls
        let callbackContext = UIAProviderCallbackContext()
        self.callbackContext = callbackContext
        let retainedBox = Unmanaged.passRetained(callbackContext).toOpaque()
        var callbacks = Self.makeCallbacks(context: retainedBox)
        let nativeContext = SWU_UIACreateProviderContext(&callbacks, releaseUIAProviderCallbackContext)
        self.nativeContext = nativeContext
        if nativeContext == nil {
            // Creation adopts the retained box only when it succeeds.
            releaseUIAProviderCallbackContext(retainedBox)
        }
        callbackContext.nativeContext = nativeContext
        callbackContext.bridge = self
    }

    isolated deinit {
        // Local revocation is sufficient for safety even when Windows cannot
        // disconnect providers. Never make an outbound COM call from deinit.
        if let nativeContext { SWU_UIARevokeProviderContext(nativeContext) }
        callbackContext.bridge = nil
        if let rootProvider {
            SWU_UIAReleaseProvider(rootProvider)
        }
        if let nativeContext { SWU_UIAReleaseProviderContext(nativeContext) }
    }

    private var isAvailable: Bool {
        nativeContext.map { SWU_UIAProviderContextIsAvailable($0) != 0 } ?? false
    }

    internal var callbackContextObjectForTesting: AnyObject { callbackContext }

    // MARK: - WM_GETOBJECT

    public func handleAccessibilityGetObject(
        hwnd: UnsafeMutableRawPointer?, wParam: WPARAM, lParam: LPARAM
    ) -> LRESULT? {
        guard isAvailable else { return nil }
        self.hwnd = hwnd
        guard Int32(truncatingIfNeeded: lParam) == Self.uiaRootObjectID else {
            return nil
        }
        // Only pay projection/provider costs while an assistive client exists.
        guard isClientListening, isAvailable, let nativeContext else {
            return nil
        }
        if rootProvider == nil {
            rootProvider = SWU_UIACreateRootProviderWithContext(nativeContext, hwnd)
        }
        guard isAvailable, let rootProvider else {
            return nil
        }
        // The native call borrows its provider. Pin it across reentry, then
        // balance only our temporary reference; UIA owns any references it takes.
        SWU_UIAAddRefProvider(rootProvider)
        defer { SWU_UIAReleaseProvider(rootProvider) }
        let result = nativeCalls.returnProvider(hwnd, wParam, lParam, rootProvider)
        return isAvailable ? result : nil
    }

    /// True while an assistive-technology client is attached. Cheap to call;
    /// use to gate work (like re-projection) that only matters for UIA.
    public var isClientListening: Bool {
        nativeCalls.clientsAreListening()
    }

    // MARK: - UIA events

    /// Raises `UIA_AutomationFocusChangedEventId` for the given element.
    /// No-op when no UIA client is listening.
    public func raiseFocusChanged(elementID: UInt64) {
        defer { withExtendedLifetime(self) {} }
        guard isAvailable, isClientListening, isAvailable, let nativeContext else {
            return
        }
        guard let provider = SWU_UIACreateElementProviderWithContext(nativeContext, hwnd, elementID) else {
            return
        }
        defer { SWU_UIAReleaseProvider(provider) }
        guard isAvailable else { return }
        nativeCalls.raiseFocusChanged(provider)
    }

    /// Raises `UIA_StructureChangedEventId` (ChildrenInvalidated) on the root.
    /// No-op when no client is listening or UIA has never attached.
    public func raiseStructureChanged() {
        defer { withExtendedLifetime(self) {} }
        guard isAvailable, isClientListening, isAvailable, let rootProvider else {
            return
        }
        SWU_UIAAddRefProvider(rootProvider)
        defer { SWU_UIAReleaseProvider(rootProvider) }
        nativeCalls.raiseStructureChanged(rootProvider)
    }

    /// Announces a changed live region to Narrator and other UIA clients.
    /// The provider is projected at call time; no second accessibility tree
    /// or observer work is retained when no assistive client is attached.
    public func raiseLiveRegionChanged(elementID: UInt64) {
        defer { withExtendedLifetime(self) {} }
        guard isAvailable, isClientListening, isAvailable, let nativeContext,
            let provider = SWU_UIACreateElementProviderWithContext(nativeContext, hwnd, elementID)
        else {
            return
        }
        defer { SWU_UIAReleaseProvider(provider) }
        guard isAvailable else { return }
        nativeCalls.raiseLiveRegionChanged(provider)
    }

    /// Revokes the entire provider family before attempting native cleanup.
    /// A failed native disconnect never restores availability or starts a retry.
    public func disconnect() {
        guard !didDisconnect else { return }
        didDisconnect = true
        if let nativeContext { SWU_UIARevokeProviderContext(nativeContext) }
        callbackContext.bridge = nil
        guard let rootProvider else {
            return
        }
        SWU_UIAAddRefProvider(rootProvider)
        defer { SWU_UIAReleaseProvider(rootProvider) }
        lastDisconnectResult = nativeCalls.disconnectProvider(rootProvider)
    }

    /// Test seam: the lazily created root provider, without requiring a
    /// listening UIA client or a window handle. Returns a retained reference
    /// the caller must release with `SWU_UIAReleaseProvider`.
    internal func retainedRootProviderForTesting() -> UnsafeMutableRawPointer? {
        guard isAvailable, let nativeContext else { return nil }
        if rootProvider == nil {
            rootProvider = SWU_UIACreateRootProviderWithContext(nativeContext, hwnd)
        }
        guard isAvailable, let rootProvider else {
            return nil
        }
        SWU_UIAAddRefProvider(rootProvider)
        return rootProvider
    }

    // MARK: - Callback installation

    nonisolated private static func makeCallbacks(context: UnsafeMutableRawPointer) -> SWUUIACallbacks {
        var callbacks = SWUUIACallbacks()
        callbacks.context = context
        callbacks.navigate = { context, element, direction in
            UIAProviderBridge.withBridge(from: context, unavailable: UInt64.max) {
                $0.navigateForUIA(element, direction: direction)
            }
        }
        callbacks.getRuntimeId = { context, element, buffer, capacity in
            guard capacity >= 2, let buffer else { return 0 }
            let values = UIAProviderBridge.withBridge(from: context, unavailable: [Int32]()) {
                $0.runtimeIDForUIA(element)
            }
            for (index, value) in values.prefix(Int(capacity)).enumerated() { buffer[index] = value }
            return Int32(clamping: values.count)
        }
        callbacks.getBoundingRectangle = { context, element, left, top, width, height in
            let bounds = UIAProviderBridge.withBridge(
                from: context, unavailable: Rect(x: 0, y: 0, width: 0, height: 0)
            ) {
                $0.boundingRectangleForUIA(element)
            }
            left?.pointee = bounds.origin.x
            top?.pointee = bounds.origin.y
            width?.pointee = bounds.size.width
            height?.pointee = bounds.size.height
        }
        callbacks.copyStringProperty = { context, element, property in
            let value = UIAProviderBridge.withBridge(from: context, unavailable: String?.none) {
                $0.stringPropertyForUIA(element, property: property)
            }
            guard let value else { return nil }
            var utf16 = Array(value.utf16)
            if utf16.isEmpty { utf16 = [0] }
            return utf16.withUnsafeBufferPointer { buffer in
                SWU_UIACreateBSTR(buffer.baseAddress, Int32(value.utf16.count))
            }
        }
        callbacks.getControlType = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(SWU_UIA_CONTROL_TYPE_GROUP)) {
                $0.controlTypeForUIA(element)
            }
        }
        callbacks.getBoolProperty = { context, element, property in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(-1)) {
                $0.boolPropertyForUIA(element, property: property)
            }
        }
        callbacks.hasInvokeAction = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) {
                $0.hasInvokeActionForUIA(element)
            }
        }
        callbacks.invokeDefaultAction = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: ()) {
                $0.invokeDefaultActionForUIA(element)
            }
        }
        callbacks.supportsPattern = { context, element, pattern in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) {
                $0.supportsPatternForUIA(element, pattern: pattern)
            }
        }
        callbacks.setValue = { context, element, value, length in
            guard length >= 0, length <= 1_048_576, let value else { return 0 }
            let decoded = String(decoding: UnsafeBufferPointer(start: value, count: Int(length)), as: UTF16.self)
            return UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) {
                $0.setValueForUIA(element, value: decoded)
            }
        }
        callbacks.getToggleState = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(-1)) {
                $0.toggleStateForUIA(element)
            }
        }
        callbacks.toggle = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) { $0.toggleForUIA(element) }
        }
        callbacks.select = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) { $0.selectForUIA(element) }
        }
        callbacks.addToSelection = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) { $0.addToSelectionForUIA(element) }
        }
        callbacks.removeFromSelection = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) { $0.removeFromSelectionForUIA(element) }
        }
        callbacks.getSelectionContainer = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: UInt64.max) {
                $0.selectionContainerForUIA(element)
            }
        }
        callbacks.getSelection = { context, element, buffer, capacity in
            guard capacity >= 0 else { return -1 }
            let selected = UIAProviderBridge.withBridge(from: context, unavailable: [UInt64]?.none) {
                $0.selectionForUIA(element)
            }
            guard let selected else { return -1 }
            if let buffer {
                for (index, elementID) in selected.prefix(Int(capacity)).enumerated() { buffer[index] = elementID }
            }
            return Int32(clamping: selected.count)
        }
        callbacks.realizeVirtualizedItem = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) {
                $0.realizeVirtualizedItemForUIA(element)
            }
        }
        callbacks.setFocus = { context, element in
            UIAProviderBridge.withBridge(from: context, unavailable: ()) { $0.setFocusForUIA(element) }
        }
        callbacks.elementFromPoint = { context, x, y in
            UIAProviderBridge.withBridge(from: context, unavailable: UInt64.max) {
                $0.elementFromPointForUIA(x: x, y: y)
            }
        }
        callbacks.focusedElement = { context in
            UIAProviderBridge.withBridge(from: context, unavailable: UInt64.max) { $0.focusedElementForUIA() }
        }
        return callbacks
    }

    nonisolated private static func withBridge<Result: Sendable>(
        from context: UnsafeMutableRawPointer?, unavailable: Result,
        _ work: @MainActor (UIAProviderBridge) -> Result
    ) -> Result {
        guard let context else { return unavailable }
        // The native invocation pins its provider/context. Merely retaining
        // this Sendable box reads no actor-isolated state on the COM thread.
        let box = Unmanaged<UIAProviderCallbackContext>.fromOpaque(context).takeUnretainedValue()
        return onMain { box.withBridge(unavailable: unavailable, work) }
    }

    /// Preserve the existing synchronous main dispatch, but perform the weak
    /// bridge read and promotion only after entering the main actor.
    nonisolated private static func onMain<Result: Sendable>(_ work: @MainActor () -> Result) -> Result {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(work)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(work)
        }
    }

    // MARK: - Tree queries (main actor; C memory stays in the trampolines)

    private func navigateForUIA(_ element: UInt64, direction: Int32) -> UInt64 {
        let list = source.uiaElementSnapshots()
        guard let current = list.first(where: { $0.id == element }) else { return Self.noElement }
        switch direction {
        case Int32(SWU_UIA_NAV_PARENT):
            return current.parentID ?? Self.noElement
        case Int32(SWU_UIA_NAV_FIRST_CHILD):
            return list.first(where: { $0.parentID == element })?.id ?? Self.noElement
        case Int32(SWU_UIA_NAV_LAST_CHILD):
            return list.last(where: { $0.parentID == element })?.id ?? Self.noElement
        case Int32(SWU_UIA_NAV_NEXT_SIBLING), Int32(SWU_UIA_NAV_PREVIOUS_SIBLING):
            guard let parentID = current.parentID else { return Self.noElement }
            let siblings = list.filter { $0.parentID == parentID }
            guard let index = siblings.firstIndex(where: { $0.id == element }) else { return Self.noElement }
            let target = direction == Int32(SWU_UIA_NAV_NEXT_SIBLING) ? index + 1 : index - 1
            guard siblings.indices.contains(target) else { return Self.noElement }
            return siblings[target].id
        default:
            return Self.noElement
        }
    }

    private func runtimeIDForUIA(_ element: UInt64) -> [Int32] {
        guard element != Self.rootElementID else { return [] }
        return [Self.runtimeIDPrefix, Int32(truncatingIfNeeded: element)]
    }

    private func boundingRectangleForUIA(_ element: UInt64) -> Rect {
        source.uiaElementSnapshots().first(where: { $0.id == element })?.bounds
            ?? Rect(x: 0, y: 0, width: 0, height: 0)
    }

    private func stringPropertyForUIA(_ element: UInt64, property: Int32) -> String? {
        guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }) else { return nil }
        switch property {
        case Int32(SWU_UIA_STRING_NAME):
            return snapshot.name
        case Int32(SWU_UIA_STRING_VALUE):
            return snapshot.value
        case Int32(SWU_UIA_STRING_HELP_TEXT):
            return snapshot.helpText
        case Int32(SWU_UIA_STRING_AUTOMATION_ID):
            return snapshot.automationID
        case Int32(SWU_UIA_STRING_CLASS_NAME):
            return snapshot.className ?? Self.defaultClassName
        default:
            return nil
        }
    }

    private func controlTypeForUIA(_ element: UInt64) -> Int32 {
        source.uiaElementSnapshots().first(where: { $0.id == element })?.controlType
            ?? Int32(SWU_UIA_CONTROL_TYPE_GROUP)
    }

    private func boolPropertyForUIA(_ element: UInt64, property: Int32) -> Int32 {
        guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }) else { return -1 }
        switch property {
        case Int32(SWU_UIA_BOOL_IS_ENABLED):
            return snapshot.isEnabled ? 1 : 0
        case Int32(SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS):
            return snapshot.hasKeyboardFocus ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE):
            return snapshot.isKeyboardFocusable ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_OFFSCREEN):
            guard let isOffscreen = snapshot.isOffscreen else { return -1 }
            return isOffscreen ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_PASSWORD):
            return snapshot.isPassword ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_READ_ONLY):
            guard snapshot.supportsValue else { return -1 }
            return snapshot.isReadOnly ? 1 : 0
        case Int32(SWU_UIA_BOOL_IS_SELECTED):
            guard let isSelected = snapshot.isSelected else { return -1 }
            return isSelected ? 1 : 0
        default:
            return -1
        }
    }

    private func hasInvokeActionForUIA(_ element: UInt64) -> Int32 {
        source.uiaElementSnapshots().first(where: { $0.id == element })?.hasDefaultAction == true ? 1 : 0
    }

    private func invokeDefaultActionForUIA(_ element: UInt64) {
        _ = source.uiaInvokeDefaultAction(elementID: element)
    }

    private func supportsPatternForUIA(_ element: UInt64, pattern: Int32) -> Int32 {
        guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }) else { return 0 }
        switch pattern {
        case Int32(SWU_UIA_PATTERN_VALUE):
            return snapshot.supportsValue && !snapshot.isPassword ? 1 : 0
        case Int32(SWU_UIA_PATTERN_TOGGLE):
            return snapshot.toggleState != nil ? 1 : 0
        case Int32(SWU_UIA_PATTERN_SELECTION):
            return snapshot.supportsSelection ? 1 : 0
        case Int32(SWU_UIA_PATTERN_SELECTION_ITEM):
            return snapshot.isSelected != nil ? 1 : 0
        case Int32(SWU_UIA_PATTERN_VIRTUALIZED_ITEM):
            return snapshot.isVirtualizedPlaceholder ? 1 : 0
        default:
            return 0
        }
    }

    private func setValueForUIA(_ element: UInt64, value: String) -> Int32 {
        guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }),
            isAvailable, snapshot.isEnabled, snapshot.supportsValue, !snapshot.isPassword, !snapshot.isReadOnly
        else { return 0 }
        return source.uiaSetValue(elementID: element, value: value) ? 1 : 0
    }

    private func toggleStateForUIA(_ element: UInt64) -> Int32 {
        source.uiaElementSnapshots().first(where: { $0.id == element })?.toggleState?.rawValue ?? -1
    }

    private func toggleForUIA(_ element: UInt64) -> Int32 {
        source.uiaToggle(elementID: element) ? 1 : 0
    }

    private func selectForUIA(_ element: UInt64) -> Int32 {
        source.uiaSelect(elementID: element) ? 1 : 0
    }

    private func addToSelectionForUIA(_ element: UInt64) -> Int32 {
        source.uiaAddToSelection(elementID: element) ? 1 : 0
    }

    private func removeFromSelectionForUIA(_ element: UInt64) -> Int32 {
        source.uiaRemoveFromSelection(elementID: element) ? 1 : 0
    }

    private func selectionContainerForUIA(_ element: UInt64) -> UInt64 {
        let snapshots = source.uiaElementSnapshots()
        guard let snapshot = snapshots.first(where: { $0.id == element }), snapshot.isSelected != nil else {
            return Self.noElement
        }
        var parentID = snapshot.parentID
        while let candidate = parentID, let parent = snapshots.first(where: { $0.id == candidate }) {
            if parent.supportsSelection { return parent.id }
            parentID = parent.parentID
        }
        return Self.noElement
    }

    private func selectionForUIA(_ element: UInt64) -> [UInt64]? {
        let snapshots = source.uiaElementSnapshots()
        guard snapshots.first(where: { $0.id == element })?.supportsSelection == true else { return nil }
        return snapshots.filter { snapshot in
            guard snapshot.isSelected == true else { return false }
            var parentID = snapshot.parentID
            while let candidate = parentID, let parent = snapshots.first(where: { $0.id == candidate }) {
                if parent.supportsSelection { return parent.id == element }
                parentID = parent.parentID
            }
            return false
        }.map(\.id)
    }

    private func realizeVirtualizedItemForUIA(_ element: UInt64) -> Int32 {
        source.uiaRealizeVirtualizedItem(elementID: element) ? 1 : 0
    }

    private func setFocusForUIA(_ element: UInt64) {
        source.uiaSetFocus(elementID: element)
    }

    private func elementFromPointForUIA(x: Double, y: Double) -> UInt64 {
        let list = source.uiaElementSnapshots()
        var best: UIAElementSnapshot?
        var bestDepth = -1
        for snapshot in list {
            let bounds = snapshot.bounds
            guard x >= bounds.origin.x, x < bounds.origin.x + bounds.size.width,
                y >= bounds.origin.y, y < bounds.origin.y + bounds.size.height
            else { continue }
            let depth = depthOfElement(snapshot, in: list)
            if depth > bestDepth {
                best = snapshot
                bestDepth = depth
            }
        }
        return best?.id ?? Self.noElement
    }

    private func focusedElementForUIA() -> UInt64 {
        source.uiaElementSnapshots().first(where: { $0.hasKeyboardFocus })?.id ?? Self.noElement
    }

    private func depthOfElement(_ snapshot: UIAElementSnapshot, in list: [UIAElementSnapshot]) -> Int {
        var depth = 0
        var parentID = snapshot.parentID
        while let current = parentID {
            depth += 1
            parentID = list.first(where: { $0.id == current })?.parentID
        }
        return depth
    }
}
