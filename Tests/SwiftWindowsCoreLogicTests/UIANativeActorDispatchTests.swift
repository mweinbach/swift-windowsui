import CUIAInterop
import Dispatch
import Foundation
import SwiftWindowsCore
import Synchronization
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform

/// Uses owned production callback tables and real COM vtables, with no HWND,
/// native UIA client, message pump, or native disconnection. Foreign queries
/// originate on actual new threads; no main.sync context is manufactured.
@MainActor
final class UIANativeActorDispatchTests: XCTestCase {
    func testForeignQueryRunsOnActorAndReturnsToItsOriginalUnmarkedThread() async throws {
        let fixture = try ActorDispatchFixture()
        defer { fixture.close() }
        let provider = try fixture.provider()
        let result = await actorDispatchForeignQuery(provider)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.value, Int32(SWU_UIA_CONTROL_TYPE_CUSTOM))
        XCTAssertFalse(result.scopeBefore)
        XCTAssertFalse(result.scopeAfter)
        XCTAssertEqual(fixture.source.threadIDs.count, 1)
        XCTAssertNotEqual(fixture.source.threadIDs.first, result.threadID)
        XCTAssertEqual(fixture.source.scopes, [true])
        XCTAssertEqual(fixture.source.geometries, [fixture.surface.geometry])
        XCTAssertEqual(fixture.effects.commandCount, 0)
        XCTAssertFalse(UIANativeActorEntry.isActive)
    }

    func testExplicitOuterActorQueryReturnsSynchronouslyAndRestoresEntry() async throws {
        let fixture = try ActorDispatchFixture()
        defer { fixture.close() }
        let provider = try fixture.provider()
        XCTAssertFalse(UIANativeActorEntry.isActive)
        let thread = GetCurrentThreadId()
        let result = UIANativeActorEntry.withScope { provider.query() }

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.value, Int32(SWU_UIA_CONTROL_TYPE_CUSTOM))
        XCTAssertEqual(result.threadID, thread)
        XCTAssertTrue(result.scopeBefore)
        XCTAssertTrue(result.scopeAfter)
        XCTAssertEqual(fixture.source.threadIDs, [thread])
        XCTAssertFalse(UIANativeActorEntry.isActive)
        XCTAssertEqual(UIANativeActorEntry.withScope { provider.query() }.status, 0)
        XCTAssertEqual(fixture.source.threadIDs.count, 2)
    }

    func testQueuedReceiveKeepsSameFamilyNestedFailureSynchronous() async throws {
        let fixture = try ActorDispatchFixture()
        defer { fixture.close() }
        let provider = try fixture.provider()
        var nested: ActorDispatchQueryResult?
        fixture.source.beforeRead = { nested = provider.query() }
        let outer = await actorDispatchForeignQuery(provider)

        XCTAssertEqual(outer.status, 0)
        XCTAssertEqual(nested?.status, UIANativeHRESULT.failed)
        XCTAssertEqual(nested?.value, 0)
        XCTAssertEqual(nested?.scopeBefore, true)
        XCTAssertEqual(nested?.scopeAfter, true)
        XCTAssertEqual(fixture.source.threadIDs.count, 1)
        fixture.source.beforeRead = nil
        let next = await actorDispatchForeignQuery(provider)
        XCTAssertEqual(next.status, 0)
        XCTAssertEqual(fixture.source.threadIDs.count, 2)
    }

    func testDifferentFamilyNestedRequestUsesExistingGlobalFailureGuard() async throws {
        let first = try ActorDispatchFixture()
        let second = try ActorDispatchFixture()
        defer {
            first.close()
            second.close()
        }
        let firstProvider = try first.provider()
        let secondProvider = try second.provider()
        var nested: ActorDispatchQueryResult?
        first.source.beforeRead = { nested = secondProvider.query() }
        let outer = await actorDispatchForeignQuery(firstProvider)

        XCTAssertEqual(outer.status, 0)
        XCTAssertEqual(nested?.status, UIANativeHRESULT.failed)
        XCTAssertEqual(nested?.value, 0)
        XCTAssertEqual(nested?.scopeBefore, true)
        XCTAssertTrue(second.source.threadIDs.isEmpty)
        let next = await actorDispatchForeignQuery(secondProvider)
        XCTAssertEqual(next.status, 0)
        XCTAssertEqual(second.source.threadIDs.count, 1)
        XCTAssertFalse(UIANativeActorEntry.isActive)
    }

    func testRevocationDuringQueuedReceiveCompletesNilReplyAndDrainsFullCall() async throws {
        let fixture = try ActorDispatchFixture()
        defer { fixture.close() }
        let provider = try fixture.provider()
        var quiescentDuringRead: Bool?
        fixture.source.beforeRead = { [weak fixture] in
            fixture?.bridge?.revokeNativeRequests()
            quiescentDuringRead = fixture?.attachment?.isQuiescent
        }
        let result = await actorDispatchForeignQuery(provider)

        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(quiescentDuringRead, false)
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        XCTAssertEqual(fixture.effects.wakeCount, 1)
        XCTAssertEqual(fixture.source.scopes, [true])
        XCTAssertFalse(result.scopeAfter)
        XCTAssertFalse(UIANativeActorEntry.isActive)
    }

    func testFullCLeaseSurvivesQueuedActorReplyUntilNativeOutputPublicationFinishes() async throws {
        let fixture = try ActorDispatchFixture()
        defer { fixture.close() }
        let provider = try fixture.provider()
        let gate = try provider.armPublicationGate()
        defer { gate.open() }
        let query = Task { await actorDispatchForeignQuery(provider) }
        let entered = await Task.detached { gate.waitUntilEntered() }.value
        XCTAssertEqual(entered, 0)
        XCTAssertEqual(fixture.source.threadIDs.count, 1)
        XCTAssertEqual(fixture.source.scopes, [true])
        fixture.bridge?.revokeNativeRequests()
        XCTAssertEqual(fixture.attachment?.isQuiescent, false)
        XCTAssertEqual(fixture.attachment?.detach().isDetached, false)
        XCTAssertEqual(fixture.effects.disconnectCount, 0)
        gate.open()
        let result = await query.value

        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        XCTAssertEqual(fixture.effects.wakeCount, 1)
        XCTAssertFalse(result.scopeAfter)
    }

    func testNestedLexicalScopesRestoreThePreviousEntryAndLeaveNoMarker() async {
        XCTAssertFalse(UIANativeActorEntry.isActive)
        let result = UIANativeActorEntry.withScope {
            XCTAssertTrue(UIANativeActorEntry.isActive)
            let nested = UIANativeActorEntry.withScope { UIANativeActorEntry.isActive }
            XCTAssertTrue(nested)
            XCTAssertTrue(UIANativeActorEntry.isActive)
            return 37
        }
        XCTAssertEqual(result, 37)
        XCTAssertFalse(UIANativeActorEntry.isActive)
    }

    func testLiveActorEntryDoesNotPropagateToAnotherThread() async throws {
        let reply = ActorDispatchScopeReply()
        let actorThread = GetCurrentThreadId()
        let foreign = UIANativeActorEntry.withScope {
            Thread.detachNewThread {
                reply.complete(thread: GetCurrentThreadId(), scope: UIANativeActorEntry.isActive)
            }
            // This worker only reads its own TLS; it never asks the actor for
            // work. The scope remains live while this independent read occurs.
            return reply.wait()
        }
        let observation = try XCTUnwrap(foreign)
        XCTAssertNotEqual(observation.thread, actorThread)
        XCTAssertFalse(observation.scope)
        XCTAssertFalse(UIANativeActorEntry.isActive)
    }

    func testOptionalNilScopeResultAndNilReplyAreCompletedValues() async {
        let value: String? = UIANativeActorEntry.withScope { nil }
        XCTAssertNil(value)
        XCTAssertFalse(UIANativeActorEntry.isActive)
        let reply = UIANativeActorReplyCell()
        reply.complete(nil)
        reply.complete(.integer(99))
        XCTAssertNil(reply.wait())
    }

    func testReplyCellRetainsItsFirstCompletedValue() async {
        let reply = UIANativeActorReplyCell()
        reply.complete(.integer(17))
        reply.complete(nil)
        XCTAssertEqual(reply.wait(), .integer(17))
    }
}

private struct ActorDispatchQueryResult: Sendable {
    let status: Int32
    let value: Int32
    let threadID: UInt32
    let scopeBefore: Bool
    let scopeAfter: Bool
}

/// Immutable retained C capability only; no source, actor object, or output
/// buffer crosses the worker boundary. ProviderCall owns each actual C method.
private final class ActorDispatchProvider: Sendable {
    private let address: UInt

    init(_ provider: UnsafeMutableRawPointer) {
        address = UInt(bitPattern: provider)
        SWU_UIAAddRefProvider(provider)
    }

    deinit { SWU_UIAReleaseProvider(pointer) }

    private var pointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(bitPattern: address)! }

    func query() -> ActorDispatchQueryResult {
        let thread = GetCurrentThreadId()
        let before = UIANativeActorEntry.isActive
        var value: Int32 = 99
        let status = SWU_UIAProviderGetControlTypeResult(pointer, &value)
        return ActorDispatchQueryResult(
            status: status, value: value, threadID: thread,
            scopeBefore: before, scopeAfter: UIANativeActorEntry.isActive)
    }

    func armPublicationGate() throws -> ActorDispatchPublicationGate {
        var gate: OpaquePointer?
        let status = SWU_UIAProviderArmControlTypePublicationGate(pointer, 30_000, &gate)
        guard status == 0, let gate else { throw ActorDispatchFailure.gate(status) }
        return ActorDispatchPublicationGate(adopting: gate)
    }
}

private final class ActorDispatchPublicationGate: Sendable {
    private let address: UInt

    init(adopting gate: OpaquePointer) { address = UInt(bitPattern: gate) }
    private var pointer: OpaquePointer { OpaquePointer(bitPattern: address)! }

    deinit {
        _ = SWU_UIAPublicationGateOpen(pointer)
        SWU_UIAReleasePublicationGate(pointer)
    }

    func waitUntilEntered() -> Int32 { SWU_UIAPublicationGateWaitUntilEntered(pointer, 5_000) }
    func open() { _ = SWU_UIAPublicationGateOpen(pointer) }
}

private func actorDispatchForeignQuery(_ provider: ActorDispatchProvider) async -> ActorDispatchQueryResult {
    await withCheckedContinuation { continuation in
        Thread.detachNewThread { continuation.resume(returning: provider.query()) }
    }
}

private final class ActorDispatchScopeReply: Sendable {
    private let result = Mutex<(thread: UInt32, scope: Bool)?>(nil)
    private let completed = DispatchSemaphore(value: 0)

    func complete(thread: UInt32, scope: Bool) {
        result.withLock { $0 = (thread, scope) }
        completed.signal()
    }

    func wait() -> (thread: UInt32, scope: Bool)? {
        guard completed.wait(timeout: .now() + 5) == .success else { return nil }
        return result.withLock { $0 }
    }
}

@MainActor
private final class ActorDispatchSource: UIAElementTreeSource {
    var beforeRead: (() -> Void)?
    var threadIDs: [UInt32] = []
    var scopes: [Bool] = []
    var geometries: [NativeWindowGeometry] = []

    func uiaElementSnapshots() -> [UIAElementSnapshot] { [] }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) throws -> [UIAElementSnapshot] {
        threadIDs.append(GetCurrentThreadId())
        scopes.append(UIANativeActorEntry.isActive)
        geometries.append(geometry)
        beforeRead?()
        return [
            UIAElementSnapshot(
                id: 0, parentID: nil, name: "Actor query", controlType: Int32(SWU_UIA_CONTROL_TYPE_CUSTOM),
                bounds: Rect(x: 0, y: 0, width: 100, height: 50), isEnabled: true,
                hasKeyboardFocus: false, isKeyboardFocusable: false, hasDefaultAction: false)
        ]
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { false }
    func uiaSetFocus(elementID: UInt64) {}
}

private final class ActorDispatchEffects: NativeWindowCommandSink {
    private struct State {
        var commands = 0
        var wakes = 0
        var disconnects = 0
    }
    private let state = Mutex(State())
    var commandCount: Int { state.withLock { $0.commands } }
    var wakeCount: Int { state.withLock { $0.wakes } }
    var disconnectCount: Int { state.withLock { $0.disconnects } }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        state.withLock { $0.commands += 1 }
        command.reject(.unavailable)
        return .rejected(.unavailable)
    }

    func wake() -> Result<Void, NativeWindowOwnerFailure> {
        state.withLock { $0.wakes += 1 }
        return .success(())
    }

    func calls() -> UIANativeCalls {
        UIANativeCalls(
            clientsAreListening: { false }, returnProvider: { _, _, _, _ in 0 },
            disconnectProvider: { [self] _ in
                state.withLock { $0.disconnects += 1 }
                return 0
            },
            raiseFocusChanged: { _ in }, raiseStructureChanged: { _ in }, raiseLiveRegionChanged: { _ in })
    }
}

private struct ActorDispatchSnapshots: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class ActorDispatchOwnerContext: NativeWindowOwnerContext {
    let surface: NativeWindowSurface
    let snapshotSource: any NativeWindowSnapshotSource
    let wake: @Sendable () -> Result<Void, NativeWindowOwnerFailure>
    private var attachments: [NativeWindowAttachmentID: any NativeWindowOwnerAttachment] = [:]

    init(surface: NativeWindowSurface, effects: ActorDispatchEffects) {
        self.surface = surface
        snapshotSource = ActorDispatchSnapshots(surface: surface)
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
private final class ActorDispatchFixture {
    let source = ActorDispatchSource()
    let effects = ActorDispatchEffects()
    let surface: NativeWindowSurface
    let context: ActorDispatchOwnerContext
    var bridge: UIAProviderBridge?
    var attachment: UIANativeProviderAttachment?
    private var root: UnsafeMutableRawPointer?
    private var attachmentID: NativeWindowAttachmentID?

    init() throws {
        let geometry = NativeWindowGeometry(
            revision: 5, nativeSequence: 19, clientSize: IntSize(width: 300, height: 150),
            clientScreenOrigin: Point(x: 100, y: -40), scaleFactor: 1.5, effectiveScaleFactor: 1.5,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
        surface = NativeWindowSurface(
            key: NativeWindowKey(), generation: 3,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize), geometry: geometry)
        context = ActorDispatchOwnerContext(surface: surface, effects: effects)
        let bridge = UIAProviderBridge(
            source: source, nativeWindowKey: surface.key, nativeSnapshotSource: context.snapshotSource,
            nativeCommandSink: effects,
            beforeRequest: { [surface] key, generation, geometry in
                guard key == surface.key else { return .failure(.staleWindow) }
                guard generation == surface.generation else {
                    return .failure(.staleSurface(expected: generation, actual: surface.generation))
                }
                guard geometry == surface.geometry else { return .failure(.execution("Changed query geometry")) }
                return .success(())
            })
        self.bridge = bridge
        let factory = try XCTUnwrap(bridge.makeNativeAttachmentFactory(nativeCalls: effects.calls()))
        attachmentID = factory.attachmentID
        let attachment = try XCTUnwrap(try factory.makeAttachment(in: context) as? UIANativeProviderAttachment)
        self.attachment = attachment
        try context.install(attachment, for: factory.attachmentID)
        root = try XCTUnwrap(attachment.retainedRootProviderForTesting())
    }

    func provider() throws -> ActorDispatchProvider { ActorDispatchProvider(try XCTUnwrap(root)) }

    func close() {
        bridge?.revokeNativeRequests()
        _ = attachment?.detach()
        if let root { SWU_UIAReleaseProvider(root) }
        root = nil
        if let attachmentID { _ = context.removeAttachment(for: attachmentID) }
        attachmentID = nil
        attachment = nil
        bridge = nil
    }
}

private enum ActorDispatchFailure: Error { case gate(Int32) }
