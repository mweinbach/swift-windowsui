import CUIAInterop
import Synchronization
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform

private enum InvokeResultHRESULT {
    static let ok: Int32 = 0
    static let failed = Int32(bitPattern: 0x8000_4005)
    static let unavailable = Int32(bitPattern: 0x8004_0201)
    static let notEnabled = Int32(bitPattern: 0x8004_0200)
    static let invalidOperation = Int32(bitPattern: 0x8013_1509)
    static let timeout = Int32(bitPattern: 0x8013_1505)
}

private enum InvokeResultTestFailure: Error {
    case creation
    case projection
}

private enum InvokeResultBridgeMode: Equatable {
    case legacy
    case owned
    case ownedOldVoid
    case ownedNilResult
}

@MainActor
private final class InvokeResultSource: UIAItemContainerSource {
    static let rowID: UInt64 = 1
    var isEnabled = true
    var logicalState = UIALogicalItemState.ordinary
    var actionResult = false
    var performsEffect = false
    var failsProjection = false
    var attempts = 0
    var effects = 0
    var actionElements: [UInt64] = []
    var onAction: (@MainActor () -> Void)?

    private func snapshots() -> [UIAElementSnapshot] {
        let root = UIAElementSnapshot(
            id: 0, parentID: nil, name: "Root", controlType: Int32(SWU_UIA_CONTROL_TYPE_GROUP),
            bounds: Rect(x: 0, y: 0, width: 320, height: 120), isEnabled: true,
            hasKeyboardFocus: false, isKeyboardFocusable: false, hasDefaultAction: false)
        if case .unavailable = logicalState { return [root] }
        let row = UIAElementSnapshot(
            id: Self.rowID, parentID: 0, name: "Ordinary row", controlType: Int32(SWU_UIA_CONTROL_TYPE_BUTTON),
            bounds: Rect(x: 0, y: 0, width: 120, height: 30), isEnabled: isEnabled,
            hasKeyboardFocus: false, isKeyboardFocusable: true, hasDefaultAction: true,
            isVirtualizedPlaceholder: logicalState.rawValue == UIALogicalItemState.placeholder.rawValue)
        return [root, row]
    }

    func uiaElementSnapshots() -> [UIAElementSnapshot] { snapshots() }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        if failsProjection { throw InvokeResultTestFailure.projection }
        return snapshots()
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        attempts += 1
        actionElements.append(elementID)
        guard elementID == Self.rowID else { return false }
        if performsEffect { effects += 1 }
        let action = onAction
        onAction = nil
        action?()
        return actionResult
    }

    func uiaSetFocus(elementID: UInt64) {}

    func uiaFindItem(containerID: UInt64, afterElementID: UInt64?) -> UIAItemContainerResult {
        guard containerID == 0 else { return .unavailable }
        return afterElementID == nil ? .item(Self.rowID) : .end
    }

    func uiaFindItem(
        containerID: UInt64, afterElementID: UInt64?, geometry: NativeWindowGeometry
    ) throws -> UIAItemContainerResult {
        uiaFindItem(containerID: containerID, afterElementID: afterElementID)
    }

    func uiaLogicalItemState(elementID: UInt64) -> UIALogicalItemState {
        if elementID == 0 { return .ordinary }
        return elementID == Self.rowID ? logicalState : .unavailable
    }
}

private func invokeResultSurface() -> NativeWindowSurface {
    let size = IntSize(width: 320, height: 120)
    let geometry = NativeWindowGeometry(
        revision: 7, nativeSequence: 19, clientSize: size, clientScreenOrigin: Point(x: 0, y: 0),
        scaleFactor: 1, effectiveScaleFactor: 1, monitorRefreshRate: 60,
        isMinimized: false, isVisible: true, isActive: true)
    return NativeWindowSurface(
        key: NativeWindowKey(), generation: 3, descriptor: SurfaceDescriptor(offscreenPixelSize: size),
        geometry: geometry)
}

private final class InvokeResultSnapshots: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    init(_ surface: NativeWindowSurface) { self.surface = surface }
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class InvokeResultCommands: NativeWindowCommandSink {
    private let pending = Mutex<[any NativeWindowOwnerCommand]>([])
    var count: Int { pending.withLock { $0.count } }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        pending.withLock { $0.append(command) }
        return .accepted
    }
}

private final class InvokeResultNativeEffects: Sendable {
    private struct State {
        var wakes = 0
        var disconnects = 0
    }

    private let state = Mutex(State())
    var wakes: Int { state.withLock { $0.wakes } }
    var disconnects: Int { state.withLock { $0.disconnects } }

    func wake() -> Result<Void, NativeWindowOwnerFailure> {
        state.withLock { $0.wakes += 1 }
        return .success(())
    }

    func makeCalls() -> UIANativeCalls {
        UIANativeCalls(
            clientsAreListening: { false }, returnProvider: { _, _, _, _ in 0 },
            disconnectProvider: { [self] _ in
                state.withLock { $0.disconnects += 1 }
                return InvokeResultHRESULT.ok
            },
            raiseFocusChanged: { _ in }, raiseStructureChanged: { _ in }, raiseLiveRegionChanged: { _ in })
    }

    @MainActor
    func makeLegacyCalls() -> UIAProviderNativeCalls {
        UIAProviderNativeCalls(
            clientsAreListening: { false }, returnProvider: { _, _, _, _ in 0 },
            disconnectProvider: { _ in InvokeResultHRESULT.ok },
            raiseFocusChanged: { _ in }, raiseStructureChanged: { _ in }, raiseLiveRegionChanged: { _ in })
    }
}

private final class InvokeResultOwnerContext: NativeWindowOwnerContext {
    let surface: NativeWindowSurface
    let snapshotSource: any NativeWindowSnapshotSource
    let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure>
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]

    init(surface: NativeWindowSurface, snapshots: InvokeResultSnapshots, effects: InvokeResultNativeEffects) {
        self.surface = surface
        snapshotSource = snapshots
        wake = { effects.wake() }
    }

    func attachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? { attachments[id] }
    func install(_ attachment: any NativeWindowOwnerAttachment, for id: NativeWindowAttachmentID) throws {
        guard attachments[id] == nil else { throw NativeWindowOwnerFailure.duplicateAttachment(id) }
        attachments[id] = attachment
    }
    func removeAttachment(for id: NativeWindowAttachmentID) -> (any NativeWindowOwnerAttachment)? {
        attachments.removeValue(forKey: id)
    }
    func withNativeModal<Result>(_ body: () throws -> Result) rethrows -> Result { try body() }
}

/// Real provider vtables, without HWNDs, native UIA discovery, or a message pump.
/// The two compatibility modes change only context construction: their callback
/// table and integer actor reply are the actual production implementations.
@MainActor
private final class InvokeResultBridgeFixture {
    let mode: InvokeResultBridgeMode
    let source = InvokeResultSource()
    let effects = InvokeResultNativeEffects()
    let commands = InvokeResultCommands()
    var bridge: UIAProviderBridge?
    var attachment: UIANativeProviderAttachment?
    weak var callbackBox: UIANativeCallbackContext?
    var insideDetached: Bool?
    var insideQuiescent: Bool?
    var insideWakes: Int?
    var insideCallbackBoxAlive: Bool?
    private var context: InvokeResultOwnerContext?
    private var attachmentID: NativeWindowAttachmentID?
    private var references: [UnsafeMutableRawPointer] = []
    private var row: UnsafeMutableRawPointer?
    private var invokePattern: UnsafeMutableRawPointer?

    init(mode: InvokeResultBridgeMode) throws {
        self.mode = mode
        do {
            let root: UnsafeMutableRawPointer
            if mode == .legacy {
                let bridge = UIAProviderBridge(source: source, nativeCalls: effects.makeLegacyCalls())
                self.bridge = bridge
                root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
            } else {
                let surface = invokeResultSurface()
                let snapshots = InvokeResultSnapshots(surface)
                let context = InvokeResultOwnerContext(surface: surface, snapshots: snapshots, effects: effects)
                self.context = context
                let bridge = UIAProviderBridge(
                    source: source, nativeWindowKey: surface.key, nativeSnapshotSource: snapshots,
                    nativeCommandSink: commands, beforeRequest: { _, _, _ in .success(()) })
                self.bridge = bridge
                let factory = try XCTUnwrap(
                    bridge.makeNativeAttachmentFactory(nativeCalls: effects.makeCalls()) as? UIANativeProviderFactory)
                callbackBox = factory.callbackContext
                let attachment: UIANativeProviderAttachment
                if mode == .owned {
                    attachment = try XCTUnwrap(try factory.makeAttachment(in: context) as? UIANativeProviderAttachment)
                } else {
                    attachment = try makeVoidCompatibilityAttachment(factory: factory, context: context)
                }
                self.attachment = attachment
                attachmentID = factory.attachmentID
                try context.install(attachment, for: factory.attachmentID)
                root = try XCTUnwrap(attachment.retainedRootProviderForTesting())
            }
            references.append(root)
            var child: UnsafeMutableRawPointer?
            let navigation = withC {
                SWU_UIAProviderNavigateResult(root, Int32(SWU_UIA_NAV_FIRST_CHILD), &child)
            }
            guard navigation == InvokeResultHRESULT.ok, let child else { throw InvokeResultTestFailure.creation }
            row = child
            references.append(child)
            let pattern = try XCTUnwrap(withC { SWU_UIAProviderGetInvokePattern(child) })
            invokePattern = pattern
            references.append(pattern)
        } catch {
            close()
            throw error
        }
    }

    private func makeVoidCompatibilityAttachment(
        factory: UIANativeProviderFactory, context: InvokeResultOwnerContext
    ) throws -> UIANativeProviderAttachment {
        let retainedCallback = Unmanaged.passRetained(factory.callbackContext).toOpaque()
        let drainWake = UIANativeDrainWake(wake: context.wake, diagnostics: factory.session.diagnostics)
        let retainedWake = Unmanaged.passRetained(drainWake).toOpaque()
        var callbacks = UIANativeProviderCallbacks.make(context: retainedCallback, supportsLogicalItems: true)
        var wake = SWUUIADrainWake()
        wake.context = retainedWake
        wake.signal = signalUIANativeDrainWake
        wake.releaseContext = releaseUIANativeDrainWake
        let created: OpaquePointer?
        if mode == .ownedOldVoid {
            created = SWU_UIACreateProviderContextWithCalls(&callbacks, releaseUIANativeCallbackContext, &wake)
        } else {
            created = SWU_UIACreateProviderContextWithCallsAndInvokeResult(
                &callbacks, releaseUIANativeCallbackContext, &wake, nil)
        }
        guard let created else {
            releaseUIANativeCallbackContext(retainedCallback)
            releaseUIANativeDrainWake(retainedWake)
            throw InvokeResultTestFailure.creation
        }
        do {
            try factory.session.bind(created)
        } catch {
            SWU_UIARevokeProviderContext(created)
            SWU_UIAReleaseProviderContext(created)
            throw error
        }
        return UIANativeProviderAttachment(
            session: factory.session, context: created, hwnd: nil, nativeCalls: factory.nativeCalls)
    }

    private func withC<Result>(_ body: @MainActor () -> Result) -> Result {
        if mode == .legacy { return body() }
        return UIANativeActorEntry.withScope(body)
    }

    func invoke() -> Int32 { withC { SWU_UIAProviderInvokeResult(invokePattern) } }

    func rowName() -> (Int32, String?) {
        withC {
            var value: UnsafeMutablePointer<UInt16>?
            let result = SWU_UIAProviderGetNameResult(row, &value)
            guard let value else { return (result, nil) }
            defer { SWU_UIAFreeString(value) }
            var count = 0
            while value[count] != 0 { count += 1 }
            return (result, String(decoding: UnsafeBufferPointer(start: value, count: count), as: UTF16.self))
        }
    }

    func closeDuringAction() {
        bridge?.revokeNativeRequests()
        insideDetached = attachment?.detach().isDetached
        insideQuiescent = attachment?.isQuiescent
        insideWakes = effects.wakes
        insideCallbackBoxAlive = callbackBox != nil
    }

    func close() {
        source.onAction = nil
        bridge?.revokeNativeRequests()
        for reference in references.reversed() { SWU_UIAReleaseProvider(reference) }
        references.removeAll()
        row = nil
        invokePattern = nil
        _ = attachment?.detach()
        if let attachmentID { _ = context?.removeAttachment(for: attachmentID) }
        attachmentID = nil
        attachment = nil
        bridge = nil
        context = nil
    }
}

private enum InvokeResultRawFactory: Equatable {
    case legacyResult
    case callsResult
    case legacyVoid
    case legacyNilResult
}

/// Scalar test state used only by synchronous C calls; it owns no actor state.
private final class InvokeResultRawBox {
    var context: OpaquePointer?
    var value: Int32 = 0
    var failure: Int32?
    var resultCalls = 0
    var voidCalls = 0
    var logicalReads = 0
    var elements: [UInt64] = []
    var callbackReleases = 0
    var wakeReleases = 0
    var wakes = 0

    func invokeResult(element: UInt64, call: OpaquePointer? = nil) -> Int32 {
        resultCalls += 1
        elements.append(element)
        if let failure, let call { SWU_UIACallFail(call, failure) }
        return value
    }
}

private func invokeResultRawBox(_ context: UnsafeMutableRawPointer?) -> InvokeResultRawBox? {
    guard let context else { return nil }
    return Unmanaged<InvokeResultRawBox>.fromOpaque(context).takeUnretainedValue()
}

private func invokeResultCallBox(_ call: OpaquePointer?) -> InvokeResultRawBox? {
    guard let call else { return nil }
    return invokeResultRawBox(SWU_UIACallOwnerContext(call))
}

private func releaseInvokeResultRawBox(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let owned = Unmanaged<InvokeResultRawBox>.fromOpaque(context)
    owned.takeUnretainedValue().callbackReleases += 1
    owned.release()
}

private func releaseInvokeResultRawWake(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let owned = Unmanaged<InvokeResultRawBox>.fromOpaque(context)
    owned.takeUnretainedValue().wakeReleases += 1
    owned.release()
}

private func makeInvokeResultRawWake(_ box: InvokeResultRawBox) -> SWUUIADrainWake {
    var wake = SWUUIADrainWake()
    wake.context = Unmanaged.passRetained(box).toOpaque()
    wake.signal = { context in
        guard let box = invokeResultRawBox(context) else { return InvokeResultHRESULT.failed }
        box.wakes += 1
        return InvokeResultHRESULT.ok
    }
    wake.releaseContext = releaseInvokeResultRawWake
    return wake
}

private func invokeResultRawCallback(_ context: UnsafeMutableRawPointer?, _ element: UInt64) -> Int32 {
    invokeResultRawBox(context)?.invokeResult(element: element) ?? 0
}

private func invokeResultCallCallback(_ call: OpaquePointer?, _ element: UInt64) -> Int32 {
    invokeResultCallBox(call)?.invokeResult(element: element, call: call) ?? 0
}

private final class InvokeResultRawFixture {
    let box = InvokeResultRawBox()
    private(set) var context: OpaquePointer?
    private var provider: UnsafeMutableRawPointer?
    private var pattern: UnsafeMutableRawPointer?

    init(factory: InvokeResultRawFactory, value: Int32) throws {
        box.value = value
        let retained = Unmanaged.passRetained(box).toOpaque()
        let created: OpaquePointer?
        if factory == .callsResult {
            var callbacks = SWUUIACallCallbacks()
            callbacks.context = retained
            callbacks.getBoolProperty = { _, _, property in
                property == Int32(SWU_UIA_BOOL_IS_ENABLED) ? 1 : 0
            }
            callbacks.hasInvokeAction = { _, _ in 1 }
            callbacks.getLogicalItemState = { call, _ in
                invokeResultCallBox(call)?.logicalReads += 1
                return Int32(SWU_UIA_LOGICAL_ITEM_ORDINARY)
            }
            callbacks.invokeDefaultAction = { call, element in
                guard let box = invokeResultCallBox(call) else { return }
                box.voidCalls += 1
                box.elements.append(element)
            }
            var wake = makeInvokeResultRawWake(box)
            created = SWU_UIACreateProviderContextWithCallsAndInvokeResult(
                &callbacks, releaseInvokeResultRawBox, &wake, invokeResultCallCallback)
            if created == nil { releaseInvokeResultRawWake(wake.context) }
        } else {
            var callbacks = SWUUIACallbacks()
            callbacks.context = retained
            callbacks.getBoolProperty = { _, _, property in
                property == Int32(SWU_UIA_BOOL_IS_ENABLED) ? 1 : 0
            }
            callbacks.hasInvokeAction = { _, _ in 1 }
            callbacks.getLogicalItemState = { context, _ in
                invokeResultRawBox(context)?.logicalReads += 1
                return Int32(SWU_UIA_LOGICAL_ITEM_ORDINARY)
            }
            callbacks.invokeDefaultAction = { context, element in
                guard let box = invokeResultRawBox(context) else { return }
                box.voidCalls += 1
                box.elements.append(element)
            }
            if factory == .legacyVoid {
                created = SWU_UIACreateProviderContext(&callbacks, releaseInvokeResultRawBox)
            } else if factory == .legacyNilResult {
                created = SWU_UIACreateProviderContextWithInvokeResult(&callbacks, releaseInvokeResultRawBox, nil)
            } else {
                created = SWU_UIACreateProviderContextWithInvokeResult(
                    &callbacks, releaseInvokeResultRawBox, invokeResultRawCallback)
            }
        }
        guard let created else {
            releaseInvokeResultRawBox(retained)
            throw InvokeResultTestFailure.creation
        }
        context = created
        box.context = created
        do {
            guard let provider = SWU_UIACreateElementProviderWithContext(created, nil, 1) else {
                throw InvokeResultTestFailure.creation
            }
            self.provider = provider
            guard let pattern = SWU_UIAProviderGetInvokePattern(provider) else {
                throw InvokeResultTestFailure.creation
            }
            self.pattern = pattern
            box.logicalReads = 0
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    func invoke() -> Int32 { SWU_UIAProviderInvokeResult(pattern) }

    func close() {
        if let context { SWU_UIARevokeProviderContext(context) }
        if let pattern {
            self.pattern = nil
            SWU_UIAReleaseProvider(pattern)
        }
        if let provider {
            self.provider = nil
            SWU_UIAReleaseProvider(provider)
        }
        if let context {
            self.context = nil
            SWU_UIAReleaseProviderContext(context)
        }
        box.context = nil
    }
}

@MainActor
final class UIAInvokeResultPropagationTests: XCTestCase {
    private func assertOrdinary(
        _ fixture: InvokeResultBridgeFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            fixture.source.uiaLogicalItemState(elementID: InvokeResultSource.rowID).rawValue,
            UIALogicalItemState.ordinary.rawValue, file: file, line: line)
        let name = fixture.rowName()
        XCTAssertEqual(name.0, InvokeResultHRESULT.ok, file: file, line: line)
        XCTAssertEqual(name.1, "Ordinary row", file: file, line: line)
        XCTAssertEqual(fixture.commands.count, 0, file: file, line: line)
    }

    func testFalseWithoutEffectKeepsOrdinaryElementAndReturnsInvalidOperation() async throws {
        for mode in [InvokeResultBridgeMode.legacy, .owned] {
            let fixture = try InvokeResultBridgeFixture(mode: mode)
            defer { fixture.close() }
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.invalidOperation)
            XCTAssertEqual(fixture.source.attempts, 1)
            XCTAssertEqual(fixture.source.effects, 0)
            XCTAssertEqual(fixture.source.actionElements, [InvokeResultSource.rowID])
            assertOrdinary(fixture)
        }
    }

    func testTrueAfterEffectKeepsOrdinaryElementAndReturnsSuccess() async throws {
        for mode in [InvokeResultBridgeMode.legacy, .owned] {
            let fixture = try InvokeResultBridgeFixture(mode: mode)
            defer { fixture.close() }
            fixture.source.actionResult = true
            fixture.source.performsEffect = true
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.ok)
            XCTAssertEqual(fixture.source.attempts, 1)
            XCTAssertEqual(fixture.source.effects, 1)
            XCTAssertEqual(fixture.source.actionElements, [InvokeResultSource.rowID])
            assertOrdinary(fixture)
        }
    }

    func testFalseAfterEffectDoesNotRetryOrUndoTheAction() async throws {
        for mode in [InvokeResultBridgeMode.legacy, .owned] {
            let fixture = try InvokeResultBridgeFixture(mode: mode)
            defer { fixture.close() }
            fixture.source.performsEffect = true
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.invalidOperation)
            XCTAssertEqual(fixture.source.attempts, 1)
            XCTAssertEqual(fixture.source.effects, 1)
            XCTAssertEqual(fixture.source.actionElements, [InvokeResultSource.rowID])
            assertOrdinary(fixture)
        }
    }

    func testPostActionLogicalUnavailabilityPrecedesEitherActionResult() async throws {
        for mode in [InvokeResultBridgeMode.legacy, .owned] {
            for value in [false, true] {
                for state in [UIALogicalItemState.unavailable, .placeholder] {
                    let fixture = try InvokeResultBridgeFixture(mode: mode)
                    defer { fixture.close() }
                    fixture.source.actionResult = value
                    fixture.source.performsEffect = true
                    fixture.source.onAction = { [weak fixture] in fixture?.source.logicalState = state }
                    XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.unavailable)
                    XCTAssertEqual(fixture.source.attempts, 1)
                    XCTAssertEqual(fixture.source.effects, 1)
                    XCTAssertEqual(fixture.source.logicalState.rawValue, state.rawValue)
                }
            }
        }
    }

    func testDisabledElementPreservesNotEnabledAndSkipsAction() async throws {
        for mode in [InvokeResultBridgeMode.legacy, .owned] {
            let fixture = try InvokeResultBridgeFixture(mode: mode)
            defer { fixture.close() }
            fixture.source.isEnabled = false
            fixture.source.actionResult = true
            fixture.source.performsEffect = true
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.notEnabled)
            XCTAssertEqual(fixture.source.attempts, 0)
            XCTAssertEqual(fixture.source.effects, 0)
            assertOrdinary(fixture)
        }
    }

    func testOwnedProjectionFailureRemainsTransportFailure() async throws {
        let fixture = try InvokeResultBridgeFixture(mode: .owned)
        defer { fixture.close() }
        fixture.source.failsProjection = true
        XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.failed)
        XCTAssertEqual(fixture.source.attempts, 0)
        XCTAssertEqual(fixture.source.effects, 0)
        fixture.source.failsProjection = false
        assertOrdinary(fixture)
    }

    func testRecordedCallTimeoutPrecedesEitherActionResult() async throws {
        for value in [Int32(0), 1] {
            let fixture = try InvokeResultRawFixture(factory: .callsResult, value: value)
            defer { fixture.close() }
            fixture.box.failure = InvokeResultHRESULT.timeout
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.timeout)
            XCTAssertEqual(fixture.box.resultCalls, 1)
            XCTAssertEqual(fixture.box.voidCalls, 0)
            XCTAssertEqual(fixture.box.elements, [1])
            XCTAssertEqual(fixture.box.logicalReads, 1)
            XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
        }
    }

    func testOwnerCloseDuringActionPreservesUnavailableAndFullCallDrain() async throws {
        let fixture = try InvokeResultBridgeFixture(mode: .owned)
        defer { fixture.close() }
        fixture.source.performsEffect = true
        fixture.source.onAction = { [weak fixture] in fixture?.closeDuringAction() }
        XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.unavailable)
        XCTAssertEqual(fixture.source.attempts, 1)
        XCTAssertEqual(fixture.source.effects, 1)
        XCTAssertEqual(fixture.insideDetached, false)
        XCTAssertEqual(fixture.insideQuiescent, false)
        XCTAssertEqual(fixture.insideWakes, 0)
        XCTAssertEqual(fixture.insideCallbackBoxAlive, true)
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        XCTAssertEqual(fixture.effects.wakes, 1)
        fixture.close()
        XCTAssertNil(fixture.callbackBox)
        XCTAssertEqual(fixture.effects.disconnects, 1)
        XCTAssertEqual(fixture.effects.wakes, 1)
    }

    func testResultCallbackRunsOnceWithoutCallingVoidFallback() async throws {
        for factory in [InvokeResultRawFactory.legacyResult, .callsResult] {
            // A negative, nonzero payload is still Boolean true. No CallFail is
            // made here; an HRESULT-shaped integer must not become transport.
            for value in [Int32(0), 1, InvokeResultHRESULT.failed] {
                let fixture = try InvokeResultRawFixture(factory: factory, value: value)
                defer { fixture.close() }
                XCTAssertNil(fixture.box.failure)
                XCTAssertEqual(
                    fixture.invoke(), value == 0 ? InvokeResultHRESULT.invalidOperation : InvokeResultHRESULT.ok)
                XCTAssertEqual(fixture.box.resultCalls, 1)
                XCTAssertEqual(fixture.box.voidCalls, 0)
                XCTAssertEqual(fixture.box.elements, [1])
                XCTAssertEqual(fixture.box.logicalReads, 2)
                XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
                fixture.close()
                XCTAssertEqual(fixture.box.callbackReleases, 1)
                XCTAssertEqual(fixture.box.wakeReleases, factory == .callsResult ? 1 : 0)
            }
        }
    }

    func testLegacyVoidContextAndNilResultRetainExistingInvokeBehavior() async throws {
        for factory in [InvokeResultRawFactory.legacyVoid, .legacyNilResult] {
            let fixture = try InvokeResultRawFixture(factory: factory, value: 0)
            defer { fixture.close() }
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.ok)
            XCTAssertEqual(fixture.box.voidCalls, 1)
            XCTAssertEqual(fixture.box.resultCalls, 0)
            XCTAssertEqual(fixture.box.elements, [1])
            XCTAssertEqual(fixture.box.logicalReads, 2)
            fixture.close()
            XCTAssertEqual(fixture.box.callbackReleases, 1)
        }
    }

    func testExplicitVoidContextAndNilResultRetainExistingInvokeBehavior() async throws {
        for mode in [InvokeResultBridgeMode.ownedOldVoid, .ownedNilResult] {
            let fixture = try InvokeResultBridgeFixture(mode: mode)
            defer { fixture.close() }
            fixture.source.performsEffect = true
            // The production resolver returns .integer(0), and the production
            // void thunk deliberately discards it for these compatible contexts.
            XCTAssertFalse(fixture.source.actionResult)
            XCTAssertEqual(fixture.invoke(), InvokeResultHRESULT.ok)
            XCTAssertEqual(fixture.source.attempts, 1)
            XCTAssertEqual(fixture.source.effects, 1)
            XCTAssertEqual(fixture.source.actionElements, [InvokeResultSource.rowID])
            assertOrdinary(fixture)
            fixture.close()
            XCTAssertNil(fixture.callbackBox)
            XCTAssertEqual(fixture.effects.wakes, 1)
        }
    }

    func testNewFactoriesRejectNilTablesWithoutAdoptingContexts() async throws {
        let box = InvokeResultRawBox()
        let retained = Unmanaged.passRetained(box).toOpaque()
        defer { releaseInvokeResultRawBox(retained) }
        let legacy = SWU_UIACreateProviderContextWithInvokeResult(
            nil, releaseInvokeResultRawBox, invokeResultRawCallback)
        XCTAssertNil(legacy)
        if let legacy { SWU_UIAReleaseProviderContext(legacy) }
        XCTAssertEqual(box.callbackReleases, 0)
        var wake = makeInvokeResultRawWake(box)
        let owned = SWU_UIACreateProviderContextWithCallsAndInvokeResult(
            nil, releaseInvokeResultRawBox, &wake, invokeResultCallCallback)
        XCTAssertNil(owned)
        XCTAssertEqual(box.callbackReleases, 0)
        XCTAssertEqual(box.wakeReleases, 0)
        XCTAssertEqual(box.wakes, 0)
        if let owned {
            SWU_UIARevokeProviderContext(owned)
            SWU_UIAReleaseProviderContext(owned)
        } else {
            releaseInvokeResultRawWake(wake.context)
        }
        XCTAssertEqual(box.wakeReleases, 1)
    }
}
