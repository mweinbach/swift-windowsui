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
// callback enters the main actor before touching the tree source. A callback
// already in the main dispatch queue's context must not synchronously dispatch
// back to that queue, even when Thread.isMainThread is false. Other UIA worker
// callbacks preserve the existing synchronous dispatch contract. The main
// queue must remain able to service that dispatch; provider lifetime
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

public struct UIAElementSnapshot: Sendable {
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
    /// Logical data items can be enumerated without constructing their views.
    public var supportsItemContainer: Bool

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
        isVirtualizedPlaceholder: Bool = false,
        supportsItemContainer: Bool = false
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
        self.supportsItemContainer = supportsItemContainer
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
    /// Projects live retained state using one owner-published geometry value.
    /// Sources that already supply screen coordinates may keep the default.
    /// A runtime-backed source must not ask the native owner to map each rect.
    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot]
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
    public func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        uiaElementSnapshots()
    }

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

/// An ItemContainer lookup produces only the next logical identity. It never
/// promises a name, a control role, or geometry for an unconstructed item.
public enum UIAItemContainerResult: Equatable, Sendable {
    case item(UInt64)
    case end
    case unavailable
    case invalidStart
}

public enum UIALogicalItemState: Int32, Sendable {
    case unavailable = -1
    case ordinary = 0
    case placeholder = 1
}

/// Optional logical-item support. The native provider implements property-zero
/// enumeration only; named/property searches are explicitly unsupported. State
/// reads may reconstruct native receipts from identity metadata, but never
/// settle layout or invoke row factories. The normal snapshot callback still
/// copies one current tree.
@MainActor
public protocol UIAItemContainerSource: UIAElementTreeSource {
    func uiaFindItem(containerID: UInt64, afterElementID: UInt64?) -> UIAItemContainerResult
    /// Native lookup must use copied geometry and finish without native-owner
    /// progress. A legacy lookup may use an HWND mapper and is not a fallback.
    func uiaFindItem(
        containerID: UInt64, afterElementID: UInt64?, geometry: NativeWindowGeometry
    ) throws -> UIAItemContainerResult
    func uiaLogicalItemState(elementID: UInt64) -> UIALogicalItemState
}

extension UIAItemContainerSource {
    public func uiaFindItem(
        containerID: UInt64, afterElementID: UInt64?, geometry: NativeWindowGeometry
    ) throws -> UIAItemContainerResult {
        throw UIAProviderRequestFailure.unsupportedNativeItemLookup
    }
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

/// One process-lifetime identity, with no window, provider, or other UI state.
/// The unchecked conformance covers only this immutable owner: static
/// initialization installs its private key once, and subsequent concurrent
/// access only uses Dispatch's public, read-only current-context lookup.
/// The key never escapes or changes, and the scalar value is never replaced.
private final class UIAMainQueueContext: @unchecked Sendable {
    static let shared = UIAMainQueueContext()

    private let key = DispatchSpecificKey<UInt8>()

    private init() {
        DispatchQueue.main.setSpecific(key: key, value: 1)
    }

    var isCurrent: Bool {
        DispatchQueue.getSpecific(key: key) == 1
    }
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

    /// First runtime-id component marking ids as ours (arbitrary constant).
    private static let runtimeIDPrefix: Int32 = 0x5357
    /// OBJID value UIA clients pass as `lParam` in `WM_GETOBJECT`.
    private static let uiaRootObjectID: Int32 = -25
    // One actor transaction at a time across provider families. A nested
    // provider call must not pump another window's pending input for freshness.
    private static var nativeRequestInProgress = false

    private let source: any UIAElementTreeSource
    private let nativeCalls: UIAProviderNativeCalls
    private let callbackContext: UIAProviderCallbackContext
    private let nativeContext: OpaquePointer?
    private let nativeSession: UIANativeProviderSession?
    private let nativeCallbackContext: UIANativeCallbackContext?
    private let beforeNativeRequest:
        (@MainActor (NativeWindowKey, UInt64, NativeWindowGeometry) -> Result<Void, NativeWindowOwnerFailure>)?
    private var hwnd: UnsafeMutableRawPointer?
    private var rootProvider: UnsafeMutableRawPointer?
    private var didDisconnect = false
    private var legacyDisconnectResult: Int32?
    internal var lastDisconnectResult: Int32? {
        if let nativeSession { return nativeSession.disconnectResult }
        return legacyDisconnectResult
    }
    package var lastNativeFailure: NativeWindowOwnerFailure? { nativeSession?.diagnostics.failure }

    public convenience init(source: any UIAElementTreeSource) {
        self.init(source: source, nativeCalls: .live)
    }

    internal init(source: any UIAElementTreeSource, nativeCalls: UIAProviderNativeCalls) {
        self.source = source
        self.nativeCalls = nativeCalls
        nativeSession = nil
        nativeCallbackContext = nil
        beforeNativeRequest = nil
        let callbackContext = UIAProviderCallbackContext()
        self.callbackContext = callbackContext
        let retainedBox = Unmanaged.passRetained(callbackContext).toOpaque()
        var callbacks = Self.makeCallbacks(
            context: retainedBox, supportsLogicalItems: source is any UIAItemContainerSource)
        let nativeContext = SWU_UIACreateProviderContextWithInvokeResult(
            &callbacks, releaseUIAProviderCallbackContext,
            { context, element in
                UIAProviderBridge.withBridge(from: context, unavailable: Int32(0)) {
                    $0.invokeDefaultActionForUIA(element)
                }
            })
        self.nativeContext = nativeContext
        if nativeContext == nil {
            // Creation adopts the retained box only when it succeeds.
            releaseUIAProviderCallbackContext(retainedBox)
        }
        callbackContext.nativeContext = nativeContext
        callbackContext.bridge = self
    }

    /// The production split keeps native resources in an owner attachment.
    /// The hook drains already-copied events and validates the captured window
    /// key/surface generation against the actor facade; it must never wait for
    /// N. Same-generation geometry remains the request's published observation.
    package init(
        source: any UIAElementTreeSource,
        nativeWindowKey: NativeWindowKey,
        nativeSnapshotSource: any NativeWindowSnapshotSource,
        nativeCommandSink: any NativeWindowCommandSink,
        beforeRequest:
            @escaping @MainActor (NativeWindowKey, UInt64, NativeWindowGeometry) ->
            Result<Void, NativeWindowOwnerFailure>
    ) {
        self.source = source
        nativeCalls = .live
        callbackContext = UIAProviderCallbackContext()
        nativeContext = nil
        let nativeSession = UIANativeProviderSession(
            windowKey: nativeWindowKey, commandSink: nativeCommandSink)
        self.nativeSession = nativeSession
        let nativeCallbackContext = UIANativeCallbackContext(
            windowKey: nativeWindowKey, snapshotSource: nativeSnapshotSource,
            diagnostics: nativeSession.diagnostics)
        self.nativeCallbackContext = nativeCallbackContext
        beforeNativeRequest = beforeRequest
        nativeCallbackContext.bridge = self
    }

    package func makeNativeAttachmentFactory() -> (any NativeWindowOwnerAttachmentFactory)? {
        makeNativeAttachmentFactory(nativeCalls: .live)
    }

    internal func makeNativeAttachmentFactory(
        nativeCalls: UIANativeCalls
    ) -> (any NativeWindowOwnerAttachmentFactory)? {
        guard let nativeSession, let nativeCallbackContext else { return nil }
        return UIANativeProviderFactory(
            session: nativeSession, callbackContext: nativeCallbackContext, nativeCalls: nativeCalls,
            supportsLogicalItems: source is any UIAItemContainerSource)
    }

    /// Immediate, local admission revocation. The native attachment owns OS
    /// disconnection and resource release after the complete C call drains.
    package func revokeNativeRequests() {
        nativeSession?.revoke()
        nativeCallbackContext?.bridge = nil
        if let nativeContext { SWU_UIARevokeProviderContext(nativeContext) }
        callbackContext.bridge = nil
    }

    isolated deinit {
        // Local revocation is sufficient for safety even when Windows cannot
        // disconnect providers. Never make an outbound COM call from deinit.
        nativeSession?.revoke()
        nativeCallbackContext?.bridge = nil
        if let nativeContext { SWU_UIARevokeProviderContext(nativeContext) }
        callbackContext.bridge = nil
        if let rootProvider {
            SWU_UIAReleaseProvider(rootProvider)
        }
        if let nativeContext { SWU_UIAReleaseProviderContext(nativeContext) }
    }

    private var isAvailable: Bool {
        if let nativeSession { return nativeSession.isAvailable }
        return nativeContext.map { SWU_UIAProviderContextIsAvailable($0) != 0 } ?? false
    }

    /// Local ownership only, not native readiness. Existing terminal revocation
    /// clears the actor callback's weak bridge; it is never rebound afterward.
    /// Native requests still require their session and complete-call admission.
    package var permitsHeldTextReads: Bool {
        if let nativeCallbackContext { return nativeCallbackContext.bridge === self }
        return callbackContext.bridge === self
    }

    internal var callbackContextObjectForTesting: AnyObject { callbackContext }

    // MARK: - WM_GETOBJECT

    public func handleAccessibilityGetObject(
        hwnd: UnsafeMutableRawPointer?, wParam: WPARAM, lParam: LPARAM
    ) -> LRESULT? {
        // Production WM_GETOBJECT is handled entirely by the native attachment.
        guard nativeSession == nil else { return nil }
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

    /// Legacy bridges perform the native query. A split bridge returns the
    /// last owner observation (false before the first observation), never a
    /// fresh OS result. Native event delivery always checks actual listening.
    public var isClientListening: Bool {
        if let nativeSession { return nativeSession.clientListeningObservation ?? false }
        return nativeCalls.clientsAreListening()
    }

    // MARK: - UIA events

    /// Raises `UIA_AutomationFocusChangedEventId` for the given element.
    /// No-op when no UIA client is listening.
    public func raiseFocusChanged(elementID: UInt64) {
        if let nativeSession {
            nativeSession.submit(.focusChanged(element: elementID))
            return
        }
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
        if let nativeSession {
            nativeSession.submit(.structureChanged)
            return
        }
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
        if let nativeSession {
            nativeSession.submit(.liveRegionChanged(element: elementID))
            return
        }
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
        if let nativeSession {
            revokeNativeRequests()
            nativeSession.submitDisconnect()
            return
        }
        if let nativeContext { SWU_UIARevokeProviderContext(nativeContext) }
        callbackContext.bridge = nil
        guard let rootProvider else {
            return
        }
        SWU_UIAAddRefProvider(rootProvider)
        defer { SWU_UIAReleaseProvider(rootProvider) }
        legacyDisconnectResult = nativeCalls.disconnectProvider(rootProvider)
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

    nonisolated private static func makeCallbacks(
        context: UnsafeMutableRawPointer, supportsLogicalItems: Bool
    ) -> SWUUIACallbacks {
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
                _ = $0.invokeDefaultActionForUIA(element)
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
        if supportsLogicalItems {
            callbacks.getLogicalItemState = { context, element in
                UIAProviderBridge.withBridge(from: context, unavailable: Int32(SWU_UIA_LOGICAL_ITEM_UNAVAILABLE)) {
                    ($0.source as? any UIAItemContainerSource)?.uiaLogicalItemState(elementID: element).rawValue
                        ?? Int32(SWU_UIA_LOGICAL_ITEM_ORDINARY)
                }
            }
            callbacks.findItem = { context, container, after, target in
                guard let target else { return Int32(SWU_UIA_ITEM_LOOKUP_INVALID_START) }
                target.pointee = UInt64.max
                let result = UIAProviderBridge.withBridge(
                    from: context, unavailable: UIAItemContainerResult.unavailable
                ) {
                    ($0.source as? any UIAItemContainerSource)?.uiaFindItem(
                        containerID: container, afterElementID: after == UInt64.max ? nil : after) ?? .unavailable
                }
                switch result {
                case .item(let element):
                    target.pointee = element
                    return Int32(SWU_UIA_ITEM_LOOKUP_FOUND)
                case .end:
                    return Int32(SWU_UIA_ITEM_LOOKUP_END)
                case .unavailable:
                    return Int32(SWU_UIA_ITEM_LOOKUP_UNAVAILABLE)
                case .invalidStart:
                    return Int32(SWU_UIA_ITEM_LOOKUP_INVALID_START)
                }
            }
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

    /// Includes queues that target main. This observation does not replace
    /// the actor assertion performed before admitting a source callback.
    nonisolated static var isInMainDispatchQueueContext: Bool {
        UIAMainQueueContext.shared.isCurrent
    }

    /// Preserve synchronous results and the native entry-thread fast path.
    /// Main dispatch may execute on a thread Foundation does not call main;
    /// dispatching synchronously from that context back to main would self-wait.
    /// Both paths still assert actor isolation before reading the weak bridge.
    nonisolated static func onMain<Result: Sendable>(_ work: @MainActor () -> Result) -> Result {
        if Thread.isMainThread || isInMainDispatchQueueContext {
            return MainActor.assumeIsolated(work)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(work)
        }
    }

    /// One non-suspending retained transaction. The native call token stays
    /// owned by both the C method and its queued/running actor request.
    internal func receiveNativeRequest(
        _ envelope: UIAProviderRequestEnvelope, lease: UIANativeCallLease
    ) -> UIAProviderReply? {
        guard let nativeSession, envelope.windowKey == nativeSession.windowKey,
            nativeSession.isAvailable, lease.isAvailable
        else {
            lease.fail(UIANativeHRESULT.elementNotAvailable)
            return nil
        }
        guard !Self.nativeRequestInProgress else {
            nativeSession.recordFailure(.execution("A UIA actor transaction is already in progress"))
            lease.fail(UIANativeHRESULT.failed)
            return nil
        }
        Self.nativeRequestInProgress = true
        defer { Self.nativeRequestInProgress = false }
        if let beforeNativeRequest {
            if case .failure(let failure) = beforeNativeRequest(
                envelope.windowKey, envelope.surfaceGeneration, envelope.geometry)
            {
                nativeSession.recordFailure(failure)
                lease.fail(UIANativeHRESULT.forOwnerFailure(failure))
                return nil
            }
        }
        // Flushing earlier native events can close the window or replace its
        // retained tree. Recheck admission before touching the source.
        guard nativeSession.isAvailable, lease.isAvailable else {
            lease.fail(UIANativeHRESULT.elementNotAvailable)
            return nil
        }
        do {
            let reply = try replyForNativeRequest(
                envelope.request, geometry: envelope.geometry,
                isAvailable: { nativeSession.isAvailable && lease.isAvailable })
            guard nativeSession.isAvailable, lease.isAvailable else {
                lease.fail(UIANativeHRESULT.elementNotAvailable)
                return nil
            }
            return reply
        } catch {
            nativeSession.recordFailure(.execution("UIA retained request failed: \(error)"))
            lease.fail(UIANativeHRESULT.failed)
            return nil
        }
    }

    /// This resolver is also the headless test seam. Existing query cases
    /// capture a new projection at the same boundary as their legacy peers.
    /// Internal text content uses its optional source, with no metadata fallback.
    /// Neither path batches callbacks or caches a previous projection.
    package func replyForNativeRequest(
        _ request: UIAProviderRequest, geometry: NativeWindowGeometry,
        isAvailable: @MainActor () -> Bool
    ) throws -> UIAProviderReply {
        switch request {
        case .navigate(let element, let direction):
            return .element(
                try nativeQuerySnapshot(geometry).navigate(element, direction: direction))
        case .runtimeID(let element):
            return .runtimeID(runtimeIDForUIA(element))
        case .boundingRectangle(let element):
            return .bounds(try nativeQuerySnapshot(geometry).boundingRectangle(element))
        case .stringProperty(let element, let property):
            return .string(
                try nativeQuerySnapshot(geometry).stringProperty(element, property: property))
        case .textContent(let element):
            guard isAvailable(), let textSource = source as? any UIATextSnapshotSource else {
                return .string(nil)
            }
            let snapshot = textSource.uiaTextSnapshot(elementID: element)
            guard isAvailable() else { return .string(nil) }
            return .string(snapshot?.text)
        case .textDocument(let element):
            guard isAvailable(), permitsHeldTextReads, let textSource = source as? any UIATextDocumentSource,
                let document = textSource.uiaTextDocument(elementID: element), document.bind(to: self),
                isAvailable(), document.isCurrent
            else { return .textDocument(nil) }
            return .textDocument(document)
        case .textRangeContent(let range, let maximumUTF16Length):
            guard isAvailable(), permitsHeldTextReads, range.isOwned(by: self) else { return .string(nil) }
            let text = try range.getText(maximumUTF16Length: maximumUTF16Length)
            guard isAvailable(), range.isCurrent else { return .string(nil) }
            return .string(text)
        case .controlType(let element):
            return .integer(try nativeQuerySnapshot(geometry).controlType(element))
        case .boolProperty(let element, let property):
            return .integer(
                try nativeQuerySnapshot(geometry).boolProperty(element, property: property))
        case .hasInvokeAction(let element):
            return .integer(try nativeQuerySnapshot(geometry).hasInvokeAction(element))
        case .invokeDefaultAction(let element):
            return .integer(invokeDefaultActionForUIA(element))
        case .supportsPattern(let element, let pattern):
            return .integer(
                try nativeQuerySnapshot(geometry).supportsPattern(element, pattern: pattern))
        case .setValue(let element, let value):
            guard
                let snapshot = try source.uiaElementSnapshots(geometry: geometry).first(where: {
                    $0.id == element
                }), isAvailable(), snapshot.isEnabled, snapshot.supportsValue,
                !snapshot.isPassword, !snapshot.isReadOnly
            else { return .integer(0) }
            return .integer(source.uiaSetValue(elementID: element, value: value) ? 1 : 0)
        case .toggleState(let element):
            return .integer(try nativeQuerySnapshot(geometry).toggleState(element))
        case .toggle(let element):
            return .integer(toggleForUIA(element))
        case .select(let element):
            return .integer(selectForUIA(element))
        case .addToSelection(let element):
            return .integer(addToSelectionForUIA(element))
        case .removeFromSelection(let element):
            return .integer(removeFromSelectionForUIA(element))
        case .selectionContainer(let element):
            return .element(try nativeQuerySnapshot(geometry).selectionContainer(element))
        case .selection(let element):
            return .selection(try nativeQuerySnapshot(geometry).selection(element))
        case .logicalItemState(let element):
            return .integer(
                (source as? any UIAItemContainerSource)?.uiaLogicalItemState(elementID: element).rawValue
                    ?? UIALogicalItemState.unavailable.rawValue)
        case .findItem(let container, let afterElement):
            guard let itemSource = source as? any UIAItemContainerSource else { return .itemLookup(.unavailable) }
            return .itemLookup(
                try itemSource.uiaFindItem(
                    containerID: container, afterElementID: afterElement, geometry: geometry))
        case .realizeVirtualizedItem(let element):
            return .integer(realizeVirtualizedItemForUIA(element))
        case .setFocus(let element):
            setFocusForUIA(element)
            return .completed
        case .elementFromPoint(let x, let y):
            return .element(try nativeQuerySnapshot(geometry).elementFromPoint(x: x, y: y))
        case .focusedElement:
            return .element(try nativeQuerySnapshot(geometry).focusedElement())
        }
    }

    private func nativeQuerySnapshot(_ geometry: NativeWindowGeometry) throws -> UIAQuerySnapshot {
        UIAQuerySnapshot(try source.uiaElementSnapshots(geometry: geometry))
    }

    // MARK: - Tree queries (main actor; C memory stays in the trampolines)

    private func navigateForUIA(_ element: UInt64, direction: Int32) -> UInt64 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).navigate(element, direction: direction)
    }

    private func runtimeIDForUIA(_ element: UInt64) -> [Int32] {
        guard element != Self.rootElementID else { return [] }
        var values = [Self.runtimeIDPrefix, Int32(truncatingIfNeeded: element)]
        if element >> 32 != 0 { values.append(Int32(truncatingIfNeeded: element >> 32)) }
        return values
    }

    private func boundingRectangleForUIA(_ element: UInt64) -> Rect {
        UIAQuerySnapshot(source.uiaElementSnapshots()).boundingRectangle(element)
    }

    private func stringPropertyForUIA(_ element: UInt64, property: Int32) -> String? {
        UIAQuerySnapshot(source.uiaElementSnapshots()).stringProperty(element, property: property)
    }

    private func controlTypeForUIA(_ element: UInt64) -> Int32 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).controlType(element)
    }

    private func boolPropertyForUIA(_ element: UInt64, property: Int32) -> Int32 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).boolProperty(element, property: property)
    }

    private func hasInvokeActionForUIA(_ element: UInt64) -> Int32 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).hasInvokeAction(element)
    }

    private func invokeDefaultActionForUIA(_ element: UInt64) -> Int32 {
        source.uiaInvokeDefaultAction(elementID: element) ? 1 : 0
    }

    private func supportsPatternForUIA(_ element: UInt64, pattern: Int32) -> Int32 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).supportsPattern(element, pattern: pattern)
    }

    private func setValueForUIA(_ element: UInt64, value: String) -> Int32 {
        guard let snapshot = source.uiaElementSnapshots().first(where: { $0.id == element }),
            isAvailable, snapshot.isEnabled, snapshot.supportsValue, !snapshot.isPassword, !snapshot.isReadOnly
        else { return 0 }
        return source.uiaSetValue(elementID: element, value: value) ? 1 : 0
    }

    private func toggleStateForUIA(_ element: UInt64) -> Int32 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).toggleState(element)
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
        UIAQuerySnapshot(source.uiaElementSnapshots()).selectionContainer(element)
    }

    private func selectionForUIA(_ element: UInt64) -> [UInt64]? {
        UIAQuerySnapshot(source.uiaElementSnapshots()).selection(element)
    }

    private func realizeVirtualizedItemForUIA(_ element: UInt64) -> Int32 {
        source.uiaRealizeVirtualizedItem(elementID: element) ? 1 : 0
    }

    private func setFocusForUIA(_ element: UInt64) {
        source.uiaSetFocus(elementID: element)
    }

    private func elementFromPointForUIA(x: Double, y: Double) -> UInt64 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).elementFromPoint(x: x, y: y)
    }

    private func focusedElementForUIA() -> UInt64 {
        UIAQuerySnapshot(source.uiaElementSnapshots()).focusedElement()
    }
}
