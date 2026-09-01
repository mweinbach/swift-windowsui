import CUIAInterop
import Dispatch
import Foundation
import Synchronization
import WinSDK
@preconcurrency import XCTest

/// Real local provider methods and owned gate events, without an HWND, actor
/// dispatch, UIA client, disconnect, or native window. Every wait is bounded.
@MainActor
final class UIAPublicationGateTests: XCTestCase {
    func testEarlyOpenPreservesValueAndTheProviderCanOnlyBeArmedOnce() async throws {
        let fixture = try PublicationGateFixture()
        let gate = try fixture.arm()
        XCTAssertEqual(gate.enteredThreadID, 0)
        XCTAssertEqual(gate.waitUntilEntered(milliseconds: 1), PublicationGateHRESULT.timeout)
        XCTAssertEqual(gate.open(), PublicationGateHRESULT.ok)
        XCTAssertEqual(gate.open(), PublicationGateHRESULT.ok)

        let result = try fixture.provider().query()
        XCTAssertEqual(result.status, PublicationGateHRESULT.ok)
        XCTAssertEqual(result.value, Int32(SWU_UIA_CONTROL_TYPE_CUSTOM))
        XCTAssertEqual(gate.enteredThreadID, result.threadID)
        XCTAssertEqual(gate.waitUntilEntered(milliseconds: 1), PublicationGateHRESULT.ok)

        var second: OpaquePointer? = OpaquePointer(bitPattern: 1)
        XCTAssertEqual(
            SWU_UIAProviderArmControlTypePublicationGate(fixture.root, 5_000, &second),
            PublicationGateHRESULT.invalidOperation)
        XCTAssertNil(second)
        XCTAssertEqual(try fixture.provider().query().status, PublicationGateHRESULT.ok)
        XCTAssertEqual(fixture.box.snapshot.queryCount, 2)
    }

    func testRevocationWhileHeldClearsOutputAndDrainsOnlyAfterMethodReturn() async throws {
        let fixture = try PublicationGateFixture()
        let gate = try fixture.arm()
        let worker = PublicationGateWorker(provider: try fixture.provider())
        defer {
            _ = gate.open()
            _ = worker.wait()
        }
        XCTAssertEqual(gate.waitUntilEntered(), PublicationGateHRESULT.ok)
        let callbacks = fixture.box.snapshot
        XCTAssertEqual(callbacks.callbacksReturned, 1)
        XCTAssertEqual(callbacks.logicalTokens.count, 2)
        XCTAssertEqual(Set(callbacks.tokens + callbacks.logicalTokens).count, 1)
        XCTAssertNil(worker.completed)

        // This fixture does not retain the callback token. Admission here is
        // held by the real native method, after its callback has returned.
        SWU_UIARevokeProviderContext(fixture.context)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 0)
        XCTAssertEqual(fixture.box.snapshot.wakeCount, 0)
        XCTAssertEqual(gate.open(), PublicationGateHRESULT.ok)

        let result = try XCTUnwrap(worker.wait())
        XCTAssertEqual(result.threadID, gate.enteredThreadID)
        XCTAssertEqual(result.status, PublicationGateHRESULT.unavailable)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
        XCTAssertEqual(fixture.box.snapshot.wakeCount, 1)
    }

    func testRecordedTransportFailuresWinAfterIndependentRelease() async throws {
        for failure in [PublicationGateHRESULT.failed, PublicationGateHRESULT.unexpected] {
            let fixture = try PublicationGateFixture(retainsCall: true)
            let gate = try fixture.arm()
            let worker = PublicationGateWorker(provider: try fixture.provider())
            defer {
                _ = gate.open()
                _ = worker.wait()
            }
            XCTAssertEqual(gate.waitUntilEntered(), PublicationGateHRESULT.ok)
            let call = try XCTUnwrap(fixture.box.retainedCall)
            call.fail(failure)
            XCTAssertEqual(gate.open(), PublicationGateHRESULT.ok)

            let result = try XCTUnwrap(worker.wait())
            XCTAssertEqual(result.status, failure)
            XCTAssertEqual(result.value, 0)
            XCTAssertEqual(result.threadID, gate.enteredThreadID)
            XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
        }
    }

    func testFailedCallbackDoesNotEnterTheGateOrPublishItsPlausibleValue() async throws {
        for failure in [PublicationGateHRESULT.failed, PublicationGateHRESULT.unexpected] {
            let fixture = try PublicationGateFixture(queryFailure: failure)
            let gate = try fixture.arm()
            defer { _ = gate.open() }

            let result = try fixture.provider().query()
            XCTAssertEqual(result.status, failure)
            XCTAssertEqual(result.value, 0)
            XCTAssertEqual(gate.enteredThreadID, 0)
            XCTAssertEqual(gate.waitUntilEntered(milliseconds: 1), PublicationGateHRESULT.timeout)
            XCTAssertEqual(fixture.box.snapshot.callbacksReturned, 1)
        }
    }

    func testNestedQueryCannotTakeTheOuterGateOrReplaceItsStatus() async throws {
        for nestedFailure in [PublicationGateHRESULT.ok, PublicationGateHRESULT.unexpected] {
            let fixture = try PublicationGateFixture(nestsQuery: true, nestedFailure: nestedFailure)
            let gate = try fixture.arm()
            fixture.box.setGate(gate)
            XCTAssertEqual(gate.open(), PublicationGateHRESULT.ok)

            let result = try fixture.provider().query()
            let observed = fixture.box.snapshot
            XCTAssertEqual(result.status, PublicationGateHRESULT.ok)
            XCTAssertEqual(result.value, Int32(SWU_UIA_CONTROL_TYPE_CUSTOM))
            XCTAssertEqual(observed.queryCount, 2)
            XCTAssertEqual(observed.tokens.count, 2)
            XCTAssertEqual(Set(observed.tokens).count, 2)
            XCTAssertEqual(observed.nestedStatus, nestedFailure)
            XCTAssertEqual(
                observed.nestedValue, nestedFailure == 0 ? Int32(SWU_UIA_CONTROL_TYPE_CUSTOM) : 0)
            // A successful nested query would enter a gate taken only at final
            // publication. Both subcases must leave the outer gate untouched.
            XCTAssertEqual(observed.gateThreadAfterNested, 0)
            XCTAssertEqual(observed.outerStatusAfterNested, PublicationGateHRESULT.ok)
            XCTAssertEqual(gate.enteredThreadID, result.threadID)
        }
    }

    func testHoldTimeoutFailsInsteadOfPublishingAndDoesNotRearm() async throws {
        let fixture = try PublicationGateFixture()
        let gate = try fixture.arm(milliseconds: 1)
        defer { _ = gate.open() }

        let result = try fixture.provider().query()
        XCTAssertEqual(result.status, PublicationGateHRESULT.timeout)
        XCTAssertEqual(result.value, 0)
        XCTAssertEqual(gate.enteredThreadID, result.threadID)
        XCTAssertEqual(gate.waitUntilEntered(milliseconds: 1), PublicationGateHRESULT.ok)
        XCTAssertEqual(try fixture.provider().query().status, PublicationGateHRESULT.ok)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
    }

    func testControllerReferencesSurviveReleaseOfAnUnqueriedProvider() async throws {
        let fixture = try PublicationGateFixture()
        let box = fixture.box
        let gate = try fixture.arm()
        let alias = PublicationGateController(retaining: gate)
        fixture.releaseNativeOwners()

        XCTAssertEqual(box.snapshot.callbackReleases, 1)
        XCTAssertEqual(box.snapshot.wakeReleases, 1)
        XCTAssertEqual(box.snapshot.wakeCount, 1)
        XCTAssertEqual(gate.enteredThreadID, 0)
        XCTAssertEqual(alias.open(), PublicationGateHRESULT.ok)
        XCTAssertEqual(gate.waitUntilEntered(milliseconds: 1), PublicationGateHRESULT.timeout)
    }

    func testInvalidInputsAndLegacyContextsCannotArm() async throws {
        let fixture = try PublicationGateFixture()
        for timeout in [UInt32(0), 30_001, UInt32.max] {
            var gate: OpaquePointer? = OpaquePointer(bitPattern: 1)
            XCTAssertEqual(
                SWU_UIAProviderArmControlTypePublicationGate(fixture.root, timeout, &gate),
                PublicationGateHRESULT.invalidArgument)
            XCTAssertNil(gate)
        }
        var missing: OpaquePointer? = OpaquePointer(bitPattern: 1)
        XCTAssertEqual(
            SWU_UIAProviderArmControlTypePublicationGate(nil, 1, &missing), PublicationGateHRESULT.pointer)
        XCTAssertNil(missing)
        XCTAssertEqual(
            SWU_UIAProviderArmControlTypePublicationGate(fixture.root, 1, nil), PublicationGateHRESULT.pointer)
        XCTAssertEqual(SWU_UIAPublicationGateOpen(nil), PublicationGateHRESULT.pointer)
        XCTAssertEqual(SWU_UIAPublicationGateWaitUntilEntered(nil, 1), PublicationGateHRESULT.pointer)
        XCTAssertEqual(SWU_UIAPublicationGateEnteredThreadID(nil), 0)

        let gate = try fixture.arm()
        XCTAssertEqual(gate.waitUntilEntered(milliseconds: 0), PublicationGateHRESULT.invalidArgument)
        XCTAssertEqual(gate.waitUntilEntered(milliseconds: 30_001), PublicationGateHRESULT.invalidArgument)
        XCTAssertEqual(gate.open(), PublicationGateHRESULT.ok)

        var callbacks = SWUUIACallbacks()
        let legacy = try XCTUnwrap(SWU_UIACreateRootProvider(&callbacks, nil))
        defer { SWU_UIAReleaseProvider(legacy) }
        var legacyGate: OpaquePointer?
        XCTAssertEqual(
            SWU_UIAProviderArmControlTypePublicationGate(legacy, 1, &legacyGate),
            PublicationGateHRESULT.invalidArgument)
        XCTAssertNil(legacyGate)

        SWU_UIARevokeProviderContext(fixture.context)
        var revokedGate: OpaquePointer?
        XCTAssertEqual(
            SWU_UIAProviderArmControlTypePublicationGate(fixture.root, 1, &revokedGate),
            PublicationGateHRESULT.unavailable)
        XCTAssertNil(revokedGate)
    }
}

private enum PublicationGateHRESULT {
    static let ok: Int32 = 0
    static let failed = Int32(bitPattern: 0x8000_4005)
    static let unexpected = Int32(bitPattern: 0x8000_FFFF)
    static let pointer = Int32(bitPattern: 0x8000_4003)
    static let invalidArgument = Int32(bitPattern: 0x8007_0057)
    static let unavailable = Int32(bitPattern: 0x8004_0201)
    static let invalidOperation = Int32(bitPattern: 0x8013_1509)
    static let timeout = Int32(bitPattern: 0x8007_05B4)
}

private enum PublicationGateFailure: Error {
    case creation(Int32)
}

private struct PublicationGateObservation: Sendable {
    let status: Int32
    let value: Int32
    let threadID: UInt32
}

// These wrappers own C references, not borrowed Swift pointers. UInt stores
// only native identity; all cross-thread lifetime operations use the C APIs.
private final class PublicationGateProvider: Sendable {
    private let address: UInt
    init(retaining provider: UnsafeMutableRawPointer) {
        SWU_UIAAddRefProvider(provider)
        address = UInt(bitPattern: provider)
    }
    deinit { SWU_UIAReleaseProvider(UnsafeMutableRawPointer(bitPattern: address)) }
    func query() -> PublicationGateObservation {
        let threadID = GetCurrentThreadId()
        var value: Int32 = 99
        let status = SWU_UIAProviderGetControlTypeResult(UnsafeMutableRawPointer(bitPattern: address), &value)
        return PublicationGateObservation(status: status, value: value, threadID: threadID)
    }
}

private final class PublicationGateController: Sendable {
    let address: UInt
    private var handle: OpaquePointer { OpaquePointer(bitPattern: address)! }
    init(adopting gate: OpaquePointer) { address = UInt(bitPattern: gate) }
    init(retaining gate: PublicationGateController) {
        SWU_UIARetainPublicationGate(gate.handle)
        address = gate.address
    }
    deinit { SWU_UIAReleasePublicationGate(handle) }
    var enteredThreadID: UInt32 { SWU_UIAPublicationGateEnteredThreadID(handle) }
    func open() -> Int32 { SWU_UIAPublicationGateOpen(handle) }
    func waitUntilEntered(milliseconds: UInt32 = 2_000) -> Int32 {
        SWU_UIAPublicationGateWaitUntilEntered(handle, milliseconds)
    }
}

private final class PublicationGateCall: Sendable {
    private let address: UInt
    init(retaining call: OpaquePointer) {
        SWU_UIARetainCall(call)
        address = UInt(bitPattern: call)
    }
    deinit { SWU_UIAReleaseCall(OpaquePointer(bitPattern: address)) }
    func fail(_ result: Int32) { SWU_UIACallFail(OpaquePointer(bitPattern: address), result) }
}

private final class PublicationGateWorker: Sendable {
    private let result = Mutex<PublicationGateObservation?>(nil)
    private let finished = DispatchSemaphore(value: 0)
    init(provider: PublicationGateProvider) {
        Thread.detachNewThread { [self, provider] in
            let observation = provider.query()
            result.withLock { $0 = observation }
            finished.signal()
        }
    }
    var completed: PublicationGateObservation? { result.withLock { $0 } }
    func wait() -> PublicationGateObservation? {
        if let completed { return completed }
        guard finished.wait(timeout: .now() + .seconds(6)) == .success else { return nil }
        return completed
    }
}

private final class PublicationGateBox: Sendable {
    struct Snapshot: Sendable {
        var queryCount = 0
        var callbacksReturned = 0
        var tokens: [UInt] = []
        var logicalTokens: [UInt] = []
        var nestedStatus: Int32?
        var nestedValue: Int32?
        var gateThreadAfterNested: UInt32?
        var outerStatusAfterNested: Int32?
        var wakeCount = 0
        var callbackReleases = 0
        var wakeReleases = 0
    }
    struct State: Sendable {
        var snapshot = Snapshot()
        var rootAddress: UInt = 0
        var gateAddress: UInt = 0
        var retainedCall: PublicationGateCall?
        var isClosing = false
    }
    let state = Mutex(State())
    let queryFailure: Int32
    let retainsCall: Bool
    let nestsQuery: Bool
    let nestedFailure: Int32
    init(queryFailure: Int32, retainsCall: Bool, nestsQuery: Bool, nestedFailure: Int32) {
        self.queryFailure = queryFailure
        self.retainsCall = retainsCall
        self.nestsQuery = nestsQuery
        self.nestedFailure = nestedFailure
    }
    var snapshot: Snapshot { state.withLock { $0.snapshot } }
    var retainedCall: PublicationGateCall? { state.withLock { $0.retainedCall } }
    func setGate(_ gate: PublicationGateController) { state.withLock { $0.gateAddress = gate.address } }
    func releaseRetainedCall() {
        let released = state.withLock { state in
            state.isClosing = true
            let call = state.retainedCall
            state.retainedCall = nil
            return call
        }
        // A last call release may signal the drain and reenter this box.
        withExtendedLifetime(released) {}
    }
    func query(_ call: OpaquePointer) -> Int32 {
        let entry = state.withLock { state -> (Int, UInt, UInt) in
            state.snapshot.queryCount += 1
            state.snapshot.tokens.append(UInt(bitPattern: call))
            return (state.snapshot.queryCount, state.rootAddress, state.gateAddress)
        }
        if retainsCall && entry.0 == 1 {
            let owned = PublicationGateCall(retaining: call)
            state.withLock {
                if !$0.isClosing { $0.retainedCall = owned }
            }
            // Timeout cleanup may already have closed the fixture. Do not
            // publish a late token or release a rejected token under its lock.
            withExtendedLifetime(owned) {}
        }
        if nestsQuery && entry.0 == 1 {
            var nestedValue: Int32 = 99
            let nestedStatus = SWU_UIAProviderGetControlTypeResult(
                UnsafeMutableRawPointer(bitPattern: entry.1), &nestedValue)
            let gateThread = SWU_UIAPublicationGateEnteredThreadID(OpaquePointer(bitPattern: entry.2))
            let outerStatus = SWU_UIACallStatus(call)
            state.withLock {
                $0.snapshot.nestedStatus = nestedStatus
                $0.snapshot.nestedValue = nestedValue
                $0.snapshot.gateThreadAfterNested = gateThread
                $0.snapshot.outerStatusAfterNested = outerStatus
            }
        }
        let failure = nestsQuery && entry.0 > 1 ? nestedFailure : queryFailure
        SWU_UIACallFail(call, failure)
        state.withLock { $0.snapshot.callbacksReturned += 1 }
        return Int32(SWU_UIA_CONTROL_TYPE_CUSTOM)
    }
}

private func publicationGateBox(_ call: OpaquePointer?) -> PublicationGateBox? {
    guard let call, let raw = SWU_UIACallOwnerContext(call) else { return nil }
    return Unmanaged<PublicationGateBox>.fromOpaque(raw).takeUnretainedValue()
}

private final class PublicationGateFixture {
    let box: PublicationGateBox
    private(set) var context: OpaquePointer?
    private(set) var root: UnsafeMutableRawPointer?
    init(
        queryFailure: Int32 = 0, retainsCall: Bool = false, nestsQuery: Bool = false,
        nestedFailure: Int32 = PublicationGateHRESULT.unexpected
    ) throws {
        box = PublicationGateBox(
            queryFailure: queryFailure, retainsCall: retainsCall, nestsQuery: nestsQuery,
            nestedFailure: nestedFailure)
        var callbacks = SWUUIACallCallbacks()
        callbacks.context = Unmanaged.passRetained(box).toOpaque()
        callbacks.getControlType = { call, _ in
            guard let call, let box = publicationGateBox(call) else { return 0 }
            return box.query(call)
        }
        callbacks.getLogicalItemState = { call, _ in
            guard let call, let box = publicationGateBox(call) else {
                return Int32(SWU_UIA_LOGICAL_ITEM_UNAVAILABLE)
            }
            box.state.withLock { $0.snapshot.logicalTokens.append(UInt(bitPattern: call)) }
            return Int32(SWU_UIA_LOGICAL_ITEM_ORDINARY)
        }
        var wake = SWUUIADrainWake()
        wake.context = Unmanaged.passRetained(box).toOpaque()
        wake.signal = { raw in
            guard let raw else { return PublicationGateHRESULT.pointer }
            let box = Unmanaged<PublicationGateBox>.fromOpaque(raw).takeUnretainedValue()
            box.state.withLock { $0.snapshot.wakeCount += 1 }
            return PublicationGateHRESULT.ok
        }
        wake.releaseContext = { raw in
            guard let raw else { return }
            let box = Unmanaged<PublicationGateBox>.fromOpaque(raw).takeRetainedValue()
            box.state.withLock { $0.snapshot.wakeReleases += 1 }
        }
        let releaseContext: @convention(c) (UnsafeMutableRawPointer?) -> Void = { raw in
            guard let raw else { return }
            let box = Unmanaged<PublicationGateBox>.fromOpaque(raw).takeRetainedValue()
            box.state.withLock { $0.snapshot.callbackReleases += 1 }
        }
        guard let context = SWU_UIACreateProviderContextWithCalls(&callbacks, releaseContext, &wake) else {
            releaseContext(callbacks.context)
            wake.releaseContext?(wake.context)
            throw PublicationGateFailure.creation(PublicationGateHRESULT.failed)
        }
        guard let root = SWU_UIACreateRootProviderWithContext(context, nil) else {
            SWU_UIARevokeProviderContext(context)
            SWU_UIAReleaseProviderContext(context)
            throw PublicationGateFailure.creation(PublicationGateHRESULT.failed)
        }
        self.context = context
        self.root = root
        box.state.withLock { $0.rootAddress = UInt(bitPattern: root) }
    }
    deinit { releaseNativeOwners() }
    func releaseNativeOwners() {
        box.releaseRetainedCall()
        if let context { SWU_UIARevokeProviderContext(context) }
        if let root { SWU_UIAReleaseProvider(root) }
        if let context { SWU_UIAReleaseProviderContext(context) }
        root = nil
        context = nil
        box.state.withLock { $0.rootAddress = 0 }
    }
    func provider() throws -> PublicationGateProvider {
        guard let root else { throw PublicationGateFailure.creation(PublicationGateHRESULT.pointer) }
        return PublicationGateProvider(retaining: root)
    }
    func arm(milliseconds: UInt32 = 5_000) throws -> PublicationGateController {
        var gate: OpaquePointer?
        let status = SWU_UIAProviderArmControlTypePublicationGate(root, milliseconds, &gate)
        guard status == PublicationGateHRESULT.ok, let gate else { throw PublicationGateFailure.creation(status) }
        return PublicationGateController(adopting: gate)
    }
}
