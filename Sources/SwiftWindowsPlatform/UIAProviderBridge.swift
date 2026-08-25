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
// worker thread is deadlock-safe here because UIA clients (Narrator etc.)
// are out of process; the main thread never blocks on a UIA callback.

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

/// Serves UIA provider objects for one window's accessibility tree.
///
/// The bridge owns the root fragment provider (one per window, handed to UIA
/// via `UiaReturnRawElementProvider`); child providers are created on demand
/// by the C glue during navigation and are reference-counted COM objects
/// whose callbacks all funnel back into this bridge. The bridge must outlive
/// every provider it created — in practice it is owned by the window for the
/// window's lifetime.
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
    private var callbacks: SWUUIACallbacks
    private var hwnd: UnsafeMutableRawPointer?
    private var rootProvider: UnsafeMutableRawPointer?

    public init(source: any UIAElementTreeSource) {
        self.source = source
        self.callbacks = SWUUIACallbacks()
        installCallbacks()
    }

    isolated deinit {
        if let rootProvider {
            SWU_UIAReleaseProvider(rootProvider)
        }
    }

    // MARK: - WM_GETOBJECT

    public func handleAccessibilityGetObject(
        hwnd: UnsafeMutableRawPointer?, wParam: WPARAM, lParam: LPARAM
    ) -> LRESULT? {
        self.hwnd = hwnd
        guard Int32(truncatingIfNeeded: lParam) == Self.uiaRootObjectID else {
            return nil
        }
        // Only pay projection/provider costs while an assistive client exists.
        guard isClientListening else {
            return nil
        }
        if rootProvider == nil {
            rootProvider = SWU_UIACreateRootProvider(&callbacks, hwnd)
        }
        guard let rootProvider else {
            return nil
        }
        // UiaReturnRawElementProvider takes ownership of one reference; keep
        // ours so the bridge can keep answering and raising events.
        SWU_UIAAddRefProvider(rootProvider)
        return LRESULT(SWU_UIAReturnRawElementProvider(hwnd, UInt(wParam), Int(lParam), rootProvider))
    }

    /// True while an assistive-technology client is attached. Cheap to call;
    /// use to gate work (like re-projection) that only matters for UIA.
    public var isClientListening: Bool {
        SWU_UIAClientsAreListening() != 0
    }

    // MARK: - UIA events

    /// Raises `UIA_AutomationFocusChangedEventId` for the given element.
    /// No-op when no UIA client is listening.
    public func raiseFocusChanged(elementID: UInt64) {
        guard isClientListening else {
            return
        }
        guard let provider = SWU_UIACreateElementProvider(&callbacks, hwnd, elementID) else {
            return
        }
        SWU_UIARaiseAutomationFocusChanged(provider)
        SWU_UIAReleaseProvider(provider)
    }

    /// Raises `UIA_StructureChangedEventId` (ChildrenInvalidated) on the root.
    /// No-op when no client is listening or UIA has never attached.
    public func raiseStructureChanged() {
        guard isClientListening, let rootProvider else {
            return
        }
        SWU_UIARaiseStructureChanged(rootProvider)
    }

    /// Announces a changed live region to Narrator and other UIA clients.
    /// The provider is projected at call time; no second accessibility tree
    /// or observer work is retained when no assistive client is attached.
    public func raiseLiveRegionChanged(elementID: UInt64) {
        guard isClientListening,
            let provider = SWU_UIACreateElementProvider(&callbacks, hwnd, elementID)
        else {
            return
        }
        SWU_UIARaiseLiveRegionChanged(provider)
        SWU_UIAReleaseProvider(provider)
    }

    /// Disconnects the root provider; call when the window is going away so
    /// UIA stops calling into the tree.
    public func disconnect() {
        guard let rootProvider else {
            return
        }
        SWU_UIADisconnectProvider(rootProvider)
    }

    /// Test seam: the lazily created root provider, without requiring a
    /// listening UIA client or a window handle. Returns a retained reference
    /// the caller must release with `SWU_UIAReleaseProvider`.
    internal func retainedRootProviderForTesting() -> UnsafeMutableRawPointer? {
        if rootProvider == nil {
            rootProvider = SWU_UIACreateRootProvider(&callbacks, hwnd)
        }
        guard let rootProvider else {
            return nil
        }
        SWU_UIAAddRefProvider(rootProvider)
        return rootProvider
    }

    // MARK: - Callback installation

    private func installCallbacks() {
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.navigate = { context, element, direction in
            UIAProviderBridge.unmanaged(from: context).navigateForUIA(element, direction: direction)
        }
        callbacks.getRuntimeId = { context, element, buffer, capacity in
            UIAProviderBridge.unmanaged(from: context).runtimeIDForUIA(element, buffer: buffer, capacity: capacity)
        }
        callbacks.getBoundingRectangle = { context, element, left, top, width, height in
            UIAProviderBridge.unmanaged(from: context).boundingRectangleForUIA(
                element, left: left, top: top, width: width, height: height)
        }
        callbacks.copyStringProperty = { context, element, property in
            UIAProviderBridge.unmanaged(from: context).stringPropertyForUIA(element, property: property)
        }
        callbacks.getControlType = { context, element in
            UIAProviderBridge.unmanaged(from: context).controlTypeForUIA(element)
        }
        callbacks.getBoolProperty = { context, element, property in
            UIAProviderBridge.unmanaged(from: context).boolPropertyForUIA(element, property: property)
        }
        callbacks.hasInvokeAction = { context, element in
            UIAProviderBridge.unmanaged(from: context).hasInvokeActionForUIA(element)
        }
        callbacks.invokeDefaultAction = { context, element in
            UIAProviderBridge.unmanaged(from: context).invokeDefaultActionForUIA(element)
        }
        callbacks.supportsPattern = { context, element, pattern in
            UIAProviderBridge.unmanaged(from: context).supportsPatternForUIA(element, pattern: pattern)
        }
        callbacks.setValue = { context, element, value, length in
            UIAProviderBridge.unmanaged(from: context).setValueForUIA(element, value: value, length: length)
        }
        callbacks.getToggleState = { context, element in
            UIAProviderBridge.unmanaged(from: context).toggleStateForUIA(element)
        }
        callbacks.toggle = { context, element in
            UIAProviderBridge.unmanaged(from: context).toggleForUIA(element)
        }
        callbacks.select = { context, element in
            UIAProviderBridge.unmanaged(from: context).selectForUIA(element)
        }
        callbacks.addToSelection = { context, element in
            UIAProviderBridge.unmanaged(from: context).addToSelectionForUIA(element)
        }
        callbacks.removeFromSelection = { context, element in
            UIAProviderBridge.unmanaged(from: context).removeFromSelectionForUIA(element)
        }
        callbacks.getSelectionContainer = { context, element in
            UIAProviderBridge.unmanaged(from: context).selectionContainerForUIA(element)
        }
        callbacks.getSelection = { context, element, buffer, capacity in
            UIAProviderBridge.unmanaged(from: context).selectionForUIA(element, buffer: buffer, capacity: capacity)
        }
        callbacks.realizeVirtualizedItem = { context, element in
            UIAProviderBridge.unmanaged(from: context).realizeVirtualizedItemForUIA(element)
        }
        callbacks.setFocus = { context, element in
            UIAProviderBridge.unmanaged(from: context).setFocusForUIA(element)
        }
        callbacks.elementFromPoint = { context, x, y in
            UIAProviderBridge.unmanaged(from: context).elementFromPointForUIA(x: x, y: y)
        }
        callbacks.focusedElement = { context in
            UIAProviderBridge.unmanaged(from: context).focusedElementForUIA()
        }
    }

    private static func unmanaged(from context: UnsafeMutableRawPointer?) -> UIAProviderBridge {
        guard let context else {
            fatalError("UIAProviderBridge callback invoked with no context")
        }
        return Unmanaged<UIAProviderBridge>.fromOpaque(context).takeUnretainedValue()
    }

    /// Runs main-actor work from a (possibly background) UIA callback thread.
    private static func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(work)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(work)
        }
    }

    // MARK: - Tree queries (main-actor, called via onMain)

    private func navigateForUIA(_ element: UInt64, direction: Int32) -> UInt64 {
        Self.onMain {
            let list = source.uiaElementSnapshots()
            guard let current = list.first(where: { $0.id == element }) else {
                return Self.noElement
            }
            switch direction {
            case Int32(SWU_UIA_NAV_PARENT):
                return current.parentID ?? Self.noElement
            case Int32(SWU_UIA_NAV_FIRST_CHILD):
                return list.first(where: { $0.parentID == element })?.id ?? Self.noElement
            case Int32(SWU_UIA_NAV_LAST_CHILD):
                return list.last(where: { $0.parentID == element })?.id ?? Self.noElement
            case Int32(SWU_UIA_NAV_NEXT_SIBLING), Int32(SWU_UIA_NAV_PREVIOUS_SIBLING):
                guard let parentID = current.parentID else {
                    return Self.noElement
                }
                let siblings = list.filter { $0.parentID == parentID }
                guard let index = siblings.firstIndex(where: { $0.id == element }) else {
                    return Self.noElement
                }
                let target = direction == Int32(SWU_UIA_NAV_NEXT_SIBLING) ? index + 1 : index - 1
                guard siblings.indices.contains(target) else {
                    return Self.noElement
                }
                return siblings[target].id
            default:
                return Self.noElement
            }
        }
    }

    private func runtimeIDForUIA(
        _ element: UInt64, buffer: UnsafeMutablePointer<Int32>?, capacity: Int32
    ) -> Int32 {
        Self.onMain {
            guard element != Self.rootElementID, capacity >= 2, let buffer else {
                return 0
            }
            buffer[0] = Self.runtimeIDPrefix
            buffer[1] = Int32(truncatingIfNeeded: element)
            return 2
        }
    }

    private func boundingRectangleForUIA(
        _ element: UInt64,
        left: UnsafeMutablePointer<Double>?,
        top: UnsafeMutablePointer<Double>?,
        width: UnsafeMutablePointer<Double>?,
        height: UnsafeMutablePointer<Double>?
    ) {
        Self.onMain {
            let bounds =
                source.uiaElementSnapshots().first(where: { $0.id == element })?.bounds
                ?? Rect(x: 0, y: 0, width: 0, height: 0)
            left?.pointee = bounds.origin.x
            top?.pointee = bounds.origin.y
            width?.pointee = bounds.size.width
            height?.pointee = bounds.size.height
        }
    }

    private func stringPropertyForUIA(_ element: UInt64, property: Int32) -> UnsafeMutablePointer<UInt16>? {
        // The BSTR pointer itself is created on the main thread and handed to
        // COM, which frees it with SysFreeString; box it for the short trip
        // back across the thread hop.
        struct BSTRBox: @unchecked Sendable {
            let bstr: UnsafeMutablePointer<UInt16>?
        }
        return Self.onMain { () -> BSTRBox in
            guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }) else {
                return BSTRBox(bstr: nil)
            }
            let value: String?
            switch property {
            case Int32(SWU_UIA_STRING_NAME):
                value = snapshot.name
            case Int32(SWU_UIA_STRING_VALUE):
                value = snapshot.value
            case Int32(SWU_UIA_STRING_HELP_TEXT):
                value = snapshot.helpText
            case Int32(SWU_UIA_STRING_AUTOMATION_ID):
                value = snapshot.automationID
            case Int32(SWU_UIA_STRING_CLASS_NAME):
                value = snapshot.className ?? Self.defaultClassName
            default:
                value = nil
            }
            guard let value else {
                return BSTRBox(bstr: nil)
            }
            var utf16 = Array(value.utf16)
            if utf16.isEmpty {
                utf16 = [0]
            }
            let bstr = utf16.withUnsafeMutableBufferPointer { buffer in
                SWU_UIACreateBSTR(buffer.baseAddress, Int32(value.utf16.count))
            }
            return BSTRBox(bstr: bstr)
        }.bstr
    }

    private func controlTypeForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaElementSnapshots().first(where: { $0.id == element })?.controlType
                ?? Int32(SWU_UIA_CONTROL_TYPE_GROUP)
        }
    }

    private func boolPropertyForUIA(_ element: UInt64, property: Int32) -> Int32 {
        Self.onMain {
            guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }) else {
                return -1
            }
            switch property {
            case Int32(SWU_UIA_BOOL_IS_ENABLED):
                return snapshot.isEnabled ? 1 : 0
            case Int32(SWU_UIA_BOOL_HAS_KEYBOARD_FOCUS):
                return snapshot.hasKeyboardFocus ? 1 : 0
            case Int32(SWU_UIA_BOOL_IS_KEYBOARD_FOCUSABLE):
                return snapshot.isKeyboardFocusable ? 1 : 0
            case Int32(SWU_UIA_BOOL_IS_OFFSCREEN):
                guard let isOffscreen = snapshot.isOffscreen else {
                    return -1
                }
                return isOffscreen ? 1 : 0
            case Int32(SWU_UIA_BOOL_IS_PASSWORD):
                return snapshot.isPassword ? 1 : 0
            case Int32(SWU_UIA_BOOL_IS_READ_ONLY):
                guard snapshot.supportsValue else {
                    return -1
                }
                return snapshot.isReadOnly ? 1 : 0
            case Int32(SWU_UIA_BOOL_IS_SELECTED):
                guard let isSelected = snapshot.isSelected else {
                    return -1
                }
                return isSelected ? 1 : 0
            default:
                return -1
            }
        }
    }

    private func hasInvokeActionForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaElementSnapshots().first(where: { $0.id == element })?.hasDefaultAction == true ? 1 : 0
        }
    }

    private func invokeDefaultActionForUIA(_ element: UInt64) {
        _ = Self.onMain {
            source.uiaInvokeDefaultAction(elementID: element)
        }
    }

    private func supportsPatternForUIA(_ element: UInt64, pattern: Int32) -> Int32 {
        Self.onMain {
            guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }) else {
                return 0
            }
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
    }

    private func setValueForUIA(_ element: UInt64, value: UnsafePointer<UInt16>?, length: Int32) -> Int32 {
        guard length >= 0, length <= 1_048_576, let value else {
            return 0
        }
        let decoded = String(decoding: UnsafeBufferPointer(start: value, count: Int(length)), as: UTF16.self)
        return Self.onMain {
            guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }),
                snapshot.isEnabled, snapshot.supportsValue, !snapshot.isPassword, !snapshot.isReadOnly
            else {
                return 0
            }
            return source.uiaSetValue(elementID: element, value: decoded) ? 1 : 0
        }
    }

    private func toggleStateForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaElementSnapshots().first(where: { $0.id == element })?.toggleState?.rawValue ?? -1
        }
    }

    private func toggleForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaToggle(elementID: element) ? 1 : 0
        }
    }

    private func selectForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaSelect(elementID: element) ? 1 : 0
        }
    }

    private func addToSelectionForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaAddToSelection(elementID: element) ? 1 : 0
        }
    }

    private func removeFromSelectionForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaRemoveFromSelection(elementID: element) ? 1 : 0
        }
    }

    private func selectionContainerForUIA(_ element: UInt64) -> UInt64 {
        Self.onMain {
            let snapshots = source.uiaElementSnapshots()
            guard let snapshot = snapshots.first(where: { $0.id == element }), snapshot.isSelected != nil else {
                return Self.noElement
            }
            var parentID = snapshot.parentID
            while let candidate = parentID,
                let parent = snapshots.first(where: { $0.id == candidate })
            {
                if parent.supportsSelection {
                    return parent.id
                }
                parentID = parent.parentID
            }
            return Self.noElement
        }
    }

    private func selectionForUIA(
        _ element: UInt64, buffer: UnsafeMutablePointer<UInt64>?, capacity: Int32
    ) -> Int32 {
        Self.onMain {
            guard capacity >= 0 else {
                return -1
            }
            let snapshots = source.uiaElementSnapshots()
            guard snapshots.first(where: { $0.id == element })?.supportsSelection == true else {
                return -1
            }
            let selected = snapshots.filter { snapshot in
                guard snapshot.isSelected == true else {
                    return false
                }
                var parentID = snapshot.parentID
                while let candidate = parentID,
                    let parent = snapshots.first(where: { $0.id == candidate })
                {
                    if parent.supportsSelection {
                        return parent.id == element
                    }
                    parentID = parent.parentID
                }
                return false
            }
            if let buffer {
                for (index, snapshot) in selected.prefix(Int(capacity)).enumerated() {
                    buffer[index] = snapshot.id
                }
            }
            return Int32(clamping: selected.count)
        }
    }

    private func realizeVirtualizedItemForUIA(_ element: UInt64) -> Int32 {
        Self.onMain {
            source.uiaRealizeVirtualizedItem(elementID: element) ? 1 : 0
        }
    }

    private func setFocusForUIA(_ element: UInt64) {
        Self.onMain {
            source.uiaSetFocus(elementID: element)
        }
    }

    private func elementFromPointForUIA(x: Double, y: Double) -> UInt64 {
        Self.onMain {
            let list = source.uiaElementSnapshots()
            var best: UIAElementSnapshot?
            var bestDepth = -1
            for snapshot in list {
                let bounds = snapshot.bounds
                guard x >= bounds.origin.x, x < bounds.origin.x + bounds.size.width,
                    y >= bounds.origin.y, y < bounds.origin.y + bounds.size.height
                else {
                    continue
                }
                let depth = depthOfElement(snapshot, in: list)
                if depth > bestDepth {
                    best = snapshot
                    bestDepth = depth
                }
            }
            return best?.id ?? Self.noElement
        }
    }

    private func focusedElementForUIA() -> UInt64 {
        Self.onMain {
            source.uiaElementSnapshots().first(where: { $0.hasKeyboardFocus })?.id ?? Self.noElement
        }
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
