import CUIAInterop
import Synchronization
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform

private func nativeRequestSurface(
    key: NativeWindowKey = NativeWindowKey(), revision: UInt64 = 7, sequence: UInt64 = 19,
    generation: UInt64 = 3
) -> NativeWindowSurface {
    let geometry = NativeWindowGeometry(
        revision: revision, nativeSequence: sequence, clientSize: IntSize(width: 300, height: 150),
        clientScreenOrigin: Point(x: 100, y: -40), scaleFactor: 1.5, effectiveScaleFactor: 1.5,
        monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
    return NativeWindowSurface(
        key: key, generation: generation, descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize),
        geometry: geometry)
}

private func nativeRequestRoot(name: String = "Root") -> UIAElementSnapshot {
    UIAElementSnapshot(
        id: 0, parentID: nil, name: name, controlType: Int32(SWU_UIA_CONTROL_TYPE_GROUP),
        bounds: Rect(x: 0, y: 0, width: 100, height: 100), isEnabled: true,
        hasKeyboardFocus: true, isKeyboardFocusable: true, hasDefaultAction: true,
        supportsValue: true, isReadOnly: false, toggleState: .off, supportsSelection: true)
}

private func nativeSelectionElements(_ selected: Set<UInt64>) -> [UIAElementSnapshot] {
    var first = nativeRequestRoot(name: "First")
    first.id = 12
    first.parentID = 0
    first.supportsSelection = false
    first.isSelected = selected.contains(12)
    var second = first
    second.id = 13
    second.name = "Second"
    second.isSelected = selected.contains(13)
    return [nativeRequestRoot(), first, second]
}

@MainActor
private final class NativeRequestSource: UIAElementTreeSource {
    var elements = [nativeRequestRoot()]
    var nextSnapshots: [[UIAElementSnapshot]] = []
    var reads = 0
    var legacyReads = 0
    var geometries: [NativeWindowGeometry] = []
    var actions: [String] = []
    var actionResult = false
    var snapshotFailure: UIAProviderRequestFailure?
    var onSnapshot: (() -> Void)?
    var onAction: (() -> Void)?

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        legacyReads += 1
        return elements
    }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        reads += 1
        geometries.append(geometry)
        onSnapshot?()
        if let snapshotFailure { throw snapshotFailure }
        return nextSnapshots.isEmpty ? elements : nextSnapshots.removeFirst()
    }

    private func action(_ name: String) -> Bool {
        actions.append(name)
        onAction?()
        return actionResult
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { action("invoke") }
    func uiaSetFocus(elementID: UInt64) { _ = action("focus") }
    func uiaSetValue(elementID: UInt64, value: String) -> Bool { action("value:\(value)") }
    func uiaToggle(elementID: UInt64) -> Bool { action("toggle") }
    func uiaSelect(elementID: UInt64) -> Bool { action("select") }
    func uiaAddToSelection(elementID: UInt64) -> Bool { action("add") }
    func uiaRemoveFromSelection(elementID: UInt64) -> Bool { action("remove") }
    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool { action("realize") }
}

private final class NativeRequestSnapshots: NativeWindowSnapshotSource {
    private let value: Mutex<Result<NativeWindowSurface, NativeWindowOwnerFailure>>

    init(_ surface: NativeWindowSurface) { value = Mutex(.success(surface)) }
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { value.withLock { $0 } }
    func publish(_ surface: NativeWindowSurface) { value.withLock { $0 = .success(surface) } }
}

private final class NativeRequestCommands: NativeWindowCommandSink {
    private let pending = Mutex<[any NativeWindowOwnerCommand]>([])

    var count: Int { pending.withLock { $0.count } }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        pending.withLock { $0.append(command) }
        return .accepted
    }

    func drain(in context: any NativeWindowOwnerContext) {
        let commands = pending.withLock { stored in
            let commands = stored
            stored = []
            return commands
        }
        for command in commands {
            do { try command.execute(in: context) } catch let failure as NativeWindowOwnerFailure {
                command.reject(failure)
            } catch { command.reject(.execution(String(describing: error))) }
        }
    }
}

private final class NativeRequestEffects: Sendable {
    private struct State {
        var clientQueries = 0
        var events = 0
        var disconnects = 0
        var wakes = 0
        var wakeFailure: NativeWindowOwnerFailure?
    }

    private let state = Mutex(State())
    var clientQueries: Int { state.withLock { $0.clientQueries } }
    var events: Int { state.withLock { $0.events } }
    var disconnects: Int { state.withLock { $0.disconnects } }
    var wakes: Int { state.withLock { $0.wakes } }
    var wakeFailure: NativeWindowOwnerFailure? {
        get { state.withLock { $0.wakeFailure } }
        set { state.withLock { $0.wakeFailure = newValue } }
    }

    func wake() -> Result<Void, NativeWindowOwnerFailure> {
        state.withLock {
            $0.wakes += 1
            return $0.wakeFailure.map { .failure($0) } ?? .success(())
        }
    }

    func makeCalls() -> UIANativeCalls {
        UIANativeCalls(
            clientsAreListening: { [self] in
                state.withLock { $0.clientQueries += 1 }
                return true
            },
            returnProvider: { _, _, _, _ in 42 },
            disconnectProvider: { [self] _ in
                state.withLock { $0.disconnects += 1 }
                return UIANativeHRESULT.failed
            },
            raiseFocusChanged: { [self] _ in state.withLock { $0.events += 1 } },
            raiseStructureChanged: { [self] _ in state.withLock { $0.events += 1 } },
            raiseLiveRegionChanged: { [self] _ in state.withLock { $0.events += 1 } })
    }
}

/// A headless owner used synchronously by each test. No HWND, message pump, OS
/// UIA call, or native presentation is created; real C provider vtables are used.
private final class NativeRequestContext: NativeWindowOwnerContext {
    let surface: NativeWindowSurface
    let snapshotSource: any NativeWindowSnapshotSource
    let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure>
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]

    init(surface: NativeWindowSurface, snapshots: NativeRequestSnapshots, effects: NativeRequestEffects) {
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

@MainActor
private final class NativeRequestFixture {
    let source = NativeRequestSource()
    let effects = NativeRequestEffects()
    let commands = NativeRequestCommands()
    let surface: NativeWindowSurface
    let snapshots: NativeRequestSnapshots
    let context: NativeRequestContext
    var bridge: UIAProviderBridge?
    var attachment: UIANativeProviderAttachment?
    var root: UnsafeMutableRawPointer?
    var beforeRequest: ((UInt64) -> Result<Void, NativeWindowOwnerFailure>)?
    var sequences: [UInt64] = []
    var actorSurface: NativeWindowSurface?
    private var attachmentID: NativeWindowAttachmentID?

    init() throws {
        surface = nativeRequestSurface()
        snapshots = NativeRequestSnapshots(surface)
        context = NativeRequestContext(surface: surface, snapshots: snapshots, effects: effects)
        let bridge = UIAProviderBridge(
            source: source, nativeWindowKey: surface.key, nativeSnapshotSource: snapshots,
            nativeCommandSink: commands,
            beforeRequest: { [weak self] key, generation, geometry in
                guard let self else { return .failure(.closed) }
                let sequence = geometry.nativeSequence
                sequences.append(sequence)
                if let beforeRequest, case .failure(let failure) = beforeRequest(sequence) {
                    return .failure(failure)
                }
                let current = actorSurface ?? surface
                guard current.key == key else { return .failure(.staleWindow) }
                guard current.generation == generation else {
                    return .failure(.staleSurface(expected: generation, actual: current.generation))
                }
                return .success(())
            })
        self.bridge = bridge
        let factory = try XCTUnwrap(bridge.makeNativeAttachmentFactory(nativeCalls: effects.makeCalls()))
        let attachment = try XCTUnwrap(try factory.makeAttachment(in: context) as? UIANativeProviderAttachment)
        self.attachment = attachment
        attachmentID = factory.attachmentID
        try context.install(attachment, for: factory.attachmentID)
        root = try XCTUnwrap(attachment.retainedRootProviderForTesting())
    }

    func close() {
        bridge?.revokeNativeRequests()
        _ = attachment?.detach()
        if let root {
            self.root = nil
            SWU_UIAReleaseProvider(root)
        }
        if let attachmentID { _ = context.removeAttachment(for: attachmentID) }
        attachment = nil
        bridge = nil
    }
}

private func nativeRequestName(_ provider: UnsafeMutableRawPointer?) -> (Int32, String?) {
    var string: UnsafeMutablePointer<UInt16>?
    let result = SWU_UIAProviderGetNameResult(provider, &string)
    guard let string else { return (result, nil) }
    defer { SWU_UIAFreeString(string) }
    var count = 0
    while string[count] != 0 { count += 1 }
    return (result, String(decoding: UnsafeBufferPointer(start: string, count: count), as: UTF16.self))
}

/// A non-owning capability for this fixture's atomically retained C provider.
/// Copying it does not AddRef; NativeRequestProviderHandle explicitly owns and
/// balances the permanent reference and each temporary query reference.
private struct NativeRequestProviderCapability: Sendable {
    private let address: UInt

    init(_ provider: UnsafeMutableRawPointer) { address = UInt(bitPattern: provider) }

    private var pointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: address)! }

    func retain() { SWU_UIAAddRefProvider(pointer) }
    static func release(_ provider: Self?) { SWU_UIAReleaseProvider(provider?.pointer) }
    static func name(_ provider: Self?) -> (Int32, String?) { nativeRequestName(provider?.pointer) }
}

/// Only a retained native capability is shared with a worker. No actor fixture
/// or mutable C output buffer crosses that boundary, and no lock spans a callback.
private final class NativeRequestProviderHandle: Sendable {
    private let provider: Mutex<NativeRequestProviderCapability?>

    init(_ provider: UnsafeMutableRawPointer) {
        let retained = NativeRequestProviderCapability(provider)
        retained.retain()
        self.provider = Mutex(retained)
    }

    deinit {
        let released = provider.withLock { stored in
            let released = stored
            stored = nil
            return released
        }
        if let released { NativeRequestProviderCapability.release(released) }
    }

    func name() -> (Int32, String?) {
        let retained = provider.withLock { stored in
            if let stored { stored.retain() }
            return stored
        }
        defer { NativeRequestProviderCapability.release(retained) }
        return NativeRequestProviderCapability.name(retained)
    }
}

@MainActor
final class UIANativeRequestTests: XCTestCase {
    func testEachQueryProjectsOnceAndRuntimeIDDoesNotProject() async throws {
        let source = NativeRequestSource()
        let bridge = UIAProviderBridge(source: source)
        let geometry = nativeRequestSurface().geometry
        let queries: [UIAProviderRequest] = [
            .navigate(element: 0, direction: Int32(SWU_UIA_NAV_FIRST_CHILD)),
            .boundingRectangle(element: 0), .stringProperty(element: 0, property: Int32(SWU_UIA_STRING_NAME)),
            .controlType(element: 0), .boolProperty(element: 0, property: Int32(SWU_UIA_BOOL_IS_ENABLED)),
            .hasInvokeAction(element: 0), .supportsPattern(element: 0, pattern: Int32(SWU_UIA_PATTERN_VALUE)),
            .toggleState(element: 0), .selectionContainer(element: 0), .selection(element: 0),
            .elementFromPoint(x: 1, y: 1), .focusedElement,
        ]
        for request in queries {
            let before = source.reads
            _ = try bridge.replyForNativeRequest(request, geometry: geometry, isAvailable: { true })
            XCTAssertEqual(source.reads, before + 1)
        }
        XCTAssertEqual(source.reads, 12)
        XCTAssertEqual(
            try bridge.replyForNativeRequest(.runtimeID(element: 9), geometry: geometry, isAvailable: { true }),
            .runtimeID([0x5357, 9]))
        XCTAssertEqual(source.reads, 12)
        XCTAssertEqual(
            try bridge.replyForNativeRequest(
                .setValue(element: 0, value: "copied"), geometry: geometry, isAvailable: { true }),
            .integer(0))
        XCTAssertEqual(source.reads, 13)
        XCTAssertEqual(source.legacyReads, 0)
        XCTAssertEqual(source.actions, ["value:copied"])
    }

    func testValueCopiesAndActualActionResultsRemainDistinctFromVoid() async throws {
        let source = NativeRequestSource()
        let bridge = UIAProviderBridge(source: source)
        let geometry = nativeRequestSurface().geometry
        var input = "original"
        let request = UIAProviderRequest.setValue(element: 0, value: input)
        input = "later"
        let copied = await Task.detached { request }.value
        XCTAssertEqual(
            try bridge.replyForNativeRequest(copied, geometry: geometry, isAvailable: { true }), .integer(0))
        XCTAssertEqual(source.actions, ["value:original"])
        XCTAssertEqual(input, "later")
        for request in [
            UIAProviderRequest.toggle(element: 0), .select(element: 0), .addToSelection(element: 0),
            .removeFromSelection(element: 0), .realizeVirtualizedItem(element: 0),
        ] {
            XCTAssertEqual(
                try bridge.replyForNativeRequest(request, geometry: geometry, isAvailable: { true }), .integer(0))
        }
        XCTAssertEqual(
            try bridge.replyForNativeRequest(
                .invokeDefaultAction(element: 0), geometry: geometry, isAvailable: { true }), .completed)
        XCTAssertEqual(
            try bridge.replyForNativeRequest(.setFocus(element: 0), geometry: geometry, isAvailable: { true }),
            .completed)
    }

    func testValueRechecksAdmissionAfterItsSeparateProjection() async throws {
        let source = NativeRequestSource()
        let bridge = UIAProviderBridge(source: source)
        var available = true
        source.onSnapshot = { available = false }
        XCTAssertEqual(
            try bridge.replyForNativeRequest(
                .setValue(element: 0, value: "blocked"), geometry: nativeRequestSurface().geometry,
                isAvailable: { available }), .integer(0))
        XCTAssertEqual(source.reads, 1)
        XCTAssertTrue(source.actions.isEmpty)
    }

    func testProductionCOMQueryFlushesPublishedSequenceWithoutNativeProgress() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        fixture.beforeRequest = { [weak fixture] _ in
            fixture?.source.elements[0].name = "Flushed"
            return .success(())
        }
        let first = nativeRequestName(fixture.root)
        XCTAssertEqual(first.0, 0)
        XCTAssertEqual(first.1, "Flushed")
        XCTAssertEqual(fixture.sequences, [19])
        XCTAssertEqual(fixture.source.geometries.map(\.revision), [7])
        XCTAssertEqual(fixture.effects.clientQueries, 0)
        XCTAssertEqual(fixture.commands.count, 0)
        fixture.beforeRequest = nil
        fixture.source.elements[0].name = "Fresh"
        fixture.snapshots.publish(nativeRequestSurface(key: fixture.surface.key, revision: 8, sequence: 21))
        XCTAssertEqual(nativeRequestName(fixture.root).1, "Fresh")
        XCTAssertEqual(fixture.source.geometries.map(\.revision), [7, 8])
    }

    func testWorkerCOMQueryReturnsCopiedReplyThroughMainQueue() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        let provider = NativeRequestProviderHandle(try XCTUnwrap(fixture.root))
        let result = await Task.detached { provider.name() }.value
        XCTAssertEqual(result.0, 0)
        XCTAssertEqual(result.1, "Root")
        XCTAssertEqual(fixture.source.reads, 1)
        XCTAssertEqual(fixture.effects.clientQueries, 0)
    }

    func testCOMActionFailureIsNotTransportSuccessAndVoidInvokeStaysVoid() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        let toggle = try XCTUnwrap(SWU_UIAProviderGetTogglePattern(fixture.root))
        defer { SWU_UIAReleaseProvider(toggle) }
        XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), Int32(bitPattern: 0x8013_1509))
        let invoke = try XCTUnwrap(SWU_UIAProviderGetInvokePattern(fixture.root))
        defer { SWU_UIAReleaseProvider(invoke) }
        XCTAssertEqual(SWU_UIAProviderInvokeResult(invoke), 0)
        XCTAssertEqual(SWU_UIAProviderSetFocusResult(fixture.root), 0)
        XCTAssertEqual(fixture.source.actions, ["toggle", "invoke", "focus"])
    }

    func testRevocationDuringProjectionRejectsOutputAndDrainsAfterFullCall() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        var quiescentInsideCallback: Bool?
        fixture.source.onSnapshot = { [weak fixture] in
            fixture?.bridge?.revokeNativeRequests()
            quiescentInsideCallback = fixture?.attachment?.isQuiescent
        }
        let result = nativeRequestName(fixture.root)
        XCTAssertEqual(result.0, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(result.1)
        XCTAssertEqual(quiescentInsideCallback, false)
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        XCTAssertEqual(fixture.effects.wakes, 1)
        XCTAssertEqual(fixture.effects.disconnects, 0)
    }

    func testNestedRequestFailsBeforeFlushingOrProjectingAndDoesNotRevokeFamily() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        var nested: (Int32, String?)?
        fixture.source.onSnapshot = { [weak fixture] in nested = nativeRequestName(fixture?.root) }
        XCTAssertEqual(nativeRequestName(fixture.root).0, 0)
        XCTAssertEqual(nested?.0, UIANativeHRESULT.failed)
        XCTAssertNil(nested?.1)
        XCTAssertEqual(fixture.source.reads, 1)
        XCTAssertEqual(fixture.sequences, [19])
        fixture.source.onSnapshot = nil
        XCTAssertEqual(nativeRequestName(fixture.root).0, 0)
    }

    func testBeforeRequestFailureDoesNotReadSourceOrRevokeFamily() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        fixture.beforeRequest = { _ in .failure(.execution("Uncommitted actor input")) }
        XCTAssertEqual(nativeRequestName(fixture.root).0, UIANativeHRESULT.failed)
        XCTAssertEqual(fixture.source.reads, 0)
        fixture.beforeRequest = nil
        XCTAssertEqual(nativeRequestName(fixture.root).0, 0)
    }

    func testIngressOverflowRejectsOlderCommittedQueriesAndActionsWithTheActualFailure() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        let toggle = try XCTUnwrap(SWU_UIAProviderGetTogglePattern(fixture.root))
        defer { SWU_UIAReleaseProvider(toggle) }
        let ingress = Win32NativeEventIngress(limits: Win32NativeIngressLimits(maximumRecords: 1)) { _ in }
        func record(_ sequence: UInt64) -> Win32NativeWindowEventRecord {
            Win32NativeWindowEventRecord(
                observation: Win32NativeWindowObservation(
                    surface: nativeRequestSurface(key: fixture.surface.key, sequence: sequence),
                    systemAppearance: .unavailable, displayIdentity: "fixture", isInLiveResize: false,
                    isFullscreen: false),
                event: .textInput("input"))
        }
        try ingress.enqueue(record(19)).get()
        try ingress.flush(through: 19).get()
        try ingress.enqueue(record(20)).get()
        let failure = NativeWindowOwnerFailure.capacityExceeded(resource: "nativeInputRecords", limit: 1)
        if case .failure(let actual) = ingress.enqueue(record(21)) {
            XCTAssertEqual(actual, failure)
        } else {
            XCTFail("The essential input beyond capacity must be rejected")
        }
        fixture.beforeRequest = { ingress.flush(through: $0) }
        let readsBefore = fixture.source.reads
        // The published fixture still carries the older, already committed
        // sequence 19. A terminal ingress cannot use that fast success path.
        let name = nativeRequestName(fixture.root)
        XCTAssertEqual(name.0, UIANativeHRESULT.failed)
        XCTAssertNil(name.1)
        XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), UIANativeHRESULT.failed)
        XCTAssertEqual(fixture.source.reads, readsBefore)
        XCTAssertTrue(fixture.source.actions.isEmpty)
        XCTAssertEqual(fixture.bridge?.lastNativeFailure, failure)
        XCTAssertEqual(ingress.snapshot.lastAcceptedSequence, 20)
        ingress.fail(failure, windowKey: fixture.surface.key)
    }

    func testStaleSurfaceGenerationFailsBeforeProjectionOrAction() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        fixture.actorSurface = nativeRequestSurface(key: fixture.surface.key, generation: 4)
        XCTAssertEqual(nativeRequestName(fixture.root).0, UIANativeHRESULT.failed)
        XCTAssertEqual(fixture.source.reads, 0)
        XCTAssertTrue(fixture.source.actions.isEmpty)
        XCTAssertEqual(fixture.bridge?.lastNativeFailure, .staleSurface(expected: 3, actual: 4))
        fixture.snapshots.publish(nativeRequestSurface(key: fixture.surface.key, generation: 4))
        XCTAssertEqual(nativeRequestName(fixture.root).0, 0)
        XCTAssertEqual(fixture.source.reads, 1)
    }

    func testNativeEventsAreNotAwaitedOrDiscardedWhenActionReturnsFalse() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        let toggle = try XCTUnwrap(SWU_UIAProviderGetTogglePattern(fixture.root))
        defer { SWU_UIAReleaseProvider(toggle) }
        fixture.source.onAction = { [weak fixture] in fixture?.bridge?.raiseFocusChanged(elementID: 0) }
        XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), Int32(bitPattern: 0x8013_1509))
        XCTAssertEqual(fixture.effects.events, 0)
        XCTAssertEqual(fixture.commands.count, 1)
        fixture.commands.drain(in: fixture.context)
        XCTAssertEqual(fixture.effects.events, 1)
        XCTAssertEqual(fixture.effects.clientQueries, 1)
    }

    func testProductionSelectionCountAndFillRemainSeparateAcrossShrinkAndGrowth() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        fixture.source.elements = nativeSelectionElements([12, 13])
        let selection = try XCTUnwrap(SWU_UIAProviderGetSelectionPattern(fixture.root))
        defer { SWU_UIAReleaseProvider(selection) }
        fixture.source.reads = 0
        fixture.source.nextSnapshots = [nativeSelectionElements([12, 13]), nativeSelectionElements([13])]
        var selected: UnsafeMutableRawPointer?
        XCTAssertEqual(SWU_UIASelectionProviderGetSelectedAtResult(selection, 0, &selected), 0)
        defer { SWU_UIAReleaseProvider(selected) }
        XCTAssertEqual(fixture.source.reads, 2)
        XCTAssertEqual(nativeRequestName(selected).1, "Second")
        fixture.source.reads = 0
        fixture.source.nextSnapshots = [nativeSelectionElements([12]), nativeSelectionElements([12, 13])]
        var count: Int32 = -1
        XCTAssertEqual(
            SWU_UIASelectionProviderGetSelectedCountResult(selection, &count), Int32(bitPattern: 0x8013_1509))
        XCTAssertEqual(count, 0)
        XCTAssertEqual(fixture.source.reads, 2)
    }

    func testDisconnectRetainsActualNativeFailureAndNeverRetries() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        fixture.bridge?.disconnect()
        fixture.bridge?.disconnect()
        XCTAssertNil(fixture.bridge?.lastDisconnectResult)
        XCTAssertEqual(fixture.effects.disconnects, 0)
        XCTAssertEqual(nativeRequestName(fixture.root).0, UIANativeHRESULT.elementNotAvailable)
        fixture.commands.drain(in: fixture.context)
        XCTAssertEqual(fixture.bridge?.lastDisconnectResult, UIANativeHRESULT.failed)
        XCTAssertEqual(fixture.effects.disconnects, 1)
        _ = fixture.attachment?.detach()
        XCTAssertEqual(fixture.effects.disconnects, 1)
    }

    func testInvalidGeometryReportsFailureWithoutCachingOrRevokingFamily() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        fixture.source.snapshotFailure = .invalidGeometry
        let failed = nativeRequestName(fixture.root)
        XCTAssertEqual(failed.0, UIANativeHRESULT.failed)
        XCTAssertNil(failed.1)
        fixture.source.snapshotFailure = nil
        fixture.source.elements[0].name = "Recovered"
        XCTAssertEqual(nativeRequestName(fixture.root).1, "Recovered")
        XCTAssertEqual(fixture.source.reads, 2)
    }

    func testDetachRetainsFailedDrainWakeAlongsideActualDisconnectFailure() async throws {
        let fixture = try NativeRequestFixture()
        defer { fixture.close() }
        let wakeFailure = NativeWindowOwnerFailure.postFailed(code: 1234)
        fixture.effects.wakeFailure = wakeFailure
        fixture.bridge?.revokeNativeRequests()
        let detached = try XCTUnwrap(fixture.attachment?.detach())
        XCTAssertTrue(detached.isDetached)
        XCTAssertTrue(detached.failures.contains(wakeFailure))
        XCTAssertTrue(
            detached.failures.contains(
                .native(operation: "UiaDisconnectProvider", code: Int64(UIANativeHRESULT.failed))))
        XCTAssertEqual(fixture.effects.wakes, 1)
        XCTAssertEqual(fixture.effects.disconnects, 1)
    }
}
