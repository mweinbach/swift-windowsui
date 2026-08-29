import CUIAInterop
import Foundation
@preconcurrency import XCTest

/// Drives real COM vtables with pure C callback boxes. No HWND, actor dispatch,
/// UIA client, native event, or native disconnect operation is involved.
@MainActor
final class UIAProviderCallLeaseTests: XCTestCase {
    func testRetainedActorTokenKeepsAdmissionAliveAfterCOMMethodReturns() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.retainNextQuery = true
        var controlType: Int32 = 0

        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &controlType), CallLeaseHRESULT.ok)
        XCTAssertEqual(controlType, Int32(SWU_UIA_CONTROL_TYPE_CUSTOM))
        let token = try XCTUnwrap(fixture.box.retainedCall)
        XCTAssertEqual(SWU_UIACallOwnerContext(token), Unmanaged.passUnretained(fixture.box).toOpaque())
        XCTAssertEqual(SWU_UIACallStatus(token), CallLeaseHRESULT.ok)

        SWU_UIARevokeProviderContext(fixture.context)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 0)
        XCTAssertEqual(fixture.box.wakeCount, 0)
        XCTAssertEqual(SWU_UIACallStatus(token), CallLeaseHRESULT.unavailable)

        fixture.releaseRetainedCall()
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
        XCTAssertEqual(fixture.box.wakeCount, 1)
    }

    func testOwnerRevocationInsideCallbackDrainsOnlyAfterNativeReturn() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.revokeInQuery = true
        var value: Int32 = 99

        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &value), CallLeaseHRESULT.unavailable)
        XCTAssertEqual(value, 0)
        XCTAssertEqual(fixture.box.quiescentInsideQuery, 0)
        XCTAssertEqual(fixture.box.wakesInsideQuery, 0)
        XCTAssertEqual(fixture.box.reentrantStatus, CallLeaseHRESULT.unavailable)
        XCTAssertEqual(fixture.box.queryCount, 1)
        XCTAssertEqual(fixture.box.events, ["query", "revoked", "query-return", "wake"])
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
    }

    func testWakeRunsOutsideAdmissionLockAndIsDeliveredExactlyOnce() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.reenterWake = true

        SWU_UIARevokeProviderContext(fixture.context)
        SWU_UIARevokeProviderContext(fixture.context)

        XCTAssertEqual(fixture.box.wakeCount, 1)
        XCTAssertEqual(fixture.box.quiescentInsideWake, 1)
        XCTAssertEqual(fixture.box.reentrantStatus, CallLeaseHRESULT.unavailable)
        XCTAssertEqual(SWU_UIAProviderContextDrainWakeResult(fixture.context), CallLeaseHRESULT.ok)
    }

    func testFailedDrainWakeRetainsActualHRESULTWithoutReopeningAdmission() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.wakeResult = Int32(bitPattern: 0x8007_0005)
        SWU_UIARevokeProviderContext(fixture.context)

        XCTAssertEqual(SWU_UIAProviderContextDrainWakeResult(fixture.context), fixture.box.wakeResult)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 0)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
        XCTAssertEqual(fixture.box.wakeCount, 1)
    }

    func testTransportFailureDoesNotBecomeSuccessfulBooleanPayload() async throws {
        let fixture = try UIACallLeaseFixture()
        let toggle = try fixture.pattern(Int32(SWU_UIA_PATTERN_TOGGLE))
        defer { SWU_UIAReleaseProvider(toggle) }
        fixture.box.actionValue = 1
        fixture.box.actionFailure = CallLeaseHRESULT.failed

        XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), CallLeaseHRESULT.failed)
        XCTAssertEqual(fixture.box.actionCount, 1)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
    }

    func testFalseAndVoidActionsRetainTheirDifferentLegacyMeanings() async throws {
        let fixture = try UIACallLeaseFixture()
        let toggle = try fixture.pattern(Int32(SWU_UIA_PATTERN_TOGGLE))
        let invoke = try fixture.pattern(Int32(SWU_UIA_PATTERN_INVOKE))
        defer {
            SWU_UIAReleaseProvider(toggle)
            SWU_UIAReleaseProvider(invoke)
        }
        fixture.box.actionValue = 0

        XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), CallLeaseHRESULT.invalidOperation)
        XCTAssertEqual(SWU_UIAProviderInvokeResult(invoke), CallLeaseHRESULT.ok)
        XCTAssertEqual(SWU_UIAProviderSetFocusResult(fixture.root), CallLeaseHRESULT.ok)
        XCTAssertEqual(fixture.box.actionCount, 3)
    }

    func testNonzeroBooleanPayloadIsNotReinterpretedAsHRESULT() async throws {
        let fixture = try UIACallLeaseFixture()
        let toggle = try fixture.pattern(Int32(SWU_UIA_PATTERN_TOGGLE))
        defer { SWU_UIAReleaseProvider(toggle) }
        // This deliberately demonstrates why transport uses CallFail. Legacy
        // integer action callbacks treat every nonzero payload as true.
        fixture.box.actionValue = CallLeaseHRESULT.failed

        XCTAssertEqual(SWU_UIAToggleProviderToggleResult(toggle), CallLeaseHRESULT.ok)
    }

    func testFirstCallFailureWinsAndOwnerRevocationOverridesIt() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.retainNextQuery = true
        var value: Int32 = 0
        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &value), CallLeaseHRESULT.ok)
        let token = try XCTUnwrap(fixture.box.retainedCall)

        SWU_UIACallFail(token, CallLeaseHRESULT.failed)
        SWU_UIACallFail(token, CallLeaseHRESULT.invalidOperation)
        SWU_UIACallFail(token, CallLeaseHRESULT.ok)
        XCTAssertEqual(SWU_UIACallStatus(token), CallLeaseHRESULT.failed)
        SWU_UIACallRevokeOwner(token)
        XCTAssertEqual(SWU_UIACallStatus(token), CallLeaseHRESULT.unavailable)
        fixture.releaseRetainedCall()
    }

    func testNestedCOMCallsUseDistinctTokensAndDoNotAliasOuterStatus() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.reenterQuery = true
        var value: Int32 = 0

        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &value), CallLeaseHRESULT.ok)
        XCTAssertEqual(fixture.box.queryCount, 2)
        XCTAssertEqual(fixture.box.queryTokens.count, 2)
        XCTAssertNotEqual(fixture.box.queryTokens[0], fixture.box.queryTokens[1])
        XCTAssertEqual(fixture.box.reentrantStatus, CallLeaseHRESULT.ok)
    }

    func testSelectionCountAndFillShareOneFullMethodToken() async throws {
        let fixture = try UIACallLeaseFixture()
        let selection = try fixture.pattern(Int32(SWU_UIA_PATTERN_SELECTION))
        defer { SWU_UIAReleaseProvider(selection) }
        var count: Int32 = 0

        XCTAssertEqual(SWU_UIASelectionProviderGetSelectedCountResult(selection, &count), CallLeaseHRESULT.ok)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(fixture.box.selectionTokens.count, 2)
        XCTAssertEqual(fixture.box.selectionTokens[0], fixture.box.selectionTokens[1])
    }

    func testCallOwnsContextAfterExternalProviderAndContextOwnersRelease() async throws {
        let fixture = try UIACallLeaseFixture()
        fixture.box.retainNextQuery = true
        var value: Int32 = 0
        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &value), CallLeaseHRESULT.ok)
        let token = try XCTUnwrap(fixture.box.retainedCall)
        SWU_UIACallRevokeOwner(token)
        fixture.releaseNativeOwners()

        XCTAssertEqual(fixture.box.callbackReleases, 0)
        XCTAssertEqual(fixture.box.wakeReleases, 0)
        XCTAssertEqual(SWU_UIACallStatus(token), CallLeaseHRESULT.unavailable)
        fixture.releaseRetainedCall()
        XCTAssertEqual(fixture.box.wakeCount, 1)
        XCTAssertEqual(fixture.box.callbackReleases, 1)
        XCTAssertEqual(fixture.box.wakeReleases, 1)
    }

    func testFixedCOMIdentitySurvivesRevocationWhileConstantPropertiesFail() async throws {
        let fixture = try UIACallLeaseFixture()
        SWU_UIARevokeProviderContext(fixture.context)
        var unknown: UnsafeMutableRawPointer?
        XCTAssertEqual(
            SWU_UIAProviderQueryInterfaceResult(fixture.root, Int32(SWU_UIA_INTERFACE_UNKNOWN), &unknown),
            CallLeaseHRESULT.ok)
        if let unknown { SWU_UIAReleaseProvider(unknown) }
        var options: Int32 = 99
        XCTAssertEqual(
            SWU_UIAProviderGetProviderOptionsResult(fixture.root, &options), CallLeaseHRESULT.unavailable)
        XCTAssertEqual(options, 0)
    }

    func testFactoryFailureDoesNotAdoptEitherContextReference() async {
        let box = UIACallLeaseBox()
        let callback = Unmanaged.passRetained(box).toOpaque()
        var wake = makeCallLeaseWake(box)

        XCTAssertNil(SWU_UIACreateProviderContextWithCalls(nil, releaseCallLeaseCallbackBox, &wake))
        XCTAssertEqual(box.callbackReleases, 0)
        XCTAssertEqual(box.wakeReleases, 0)
        releaseCallLeaseCallbackBox(callback)
        releaseCallLeaseWakeBox(wake.context)
        XCTAssertEqual(box.callbackReleases, 1)
        XCTAssertEqual(box.wakeReleases, 1)
    }

    func testLegacyCallbackTableStillReceivesOriginalOwnerContext() async throws {
        let box = UIACallLeaseBox()
        var callbacks = SWUUIACallbacks()
        callbacks.context = Unmanaged.passRetained(box).toOpaque()
        callbacks.getControlType = { context, _ in
            guard let context else { return 0 }
            let box = Unmanaged<UIACallLeaseBox>.fromOpaque(context).takeUnretainedValue()
            box.queryCount += 1
            return Int32(SWU_UIA_CONTROL_TYPE_CUSTOM)
        }
        guard let context = SWU_UIACreateProviderContext(&callbacks, releaseCallLeaseCallbackBox) else {
            releaseCallLeaseCallbackBox(callbacks.context)
            throw CallLeaseTestFailure.creation
        }
        defer { SWU_UIAReleaseProviderContext(context) }
        let root = try XCTUnwrap(SWU_UIACreateRootProviderWithContext(context, nil))
        defer { SWU_UIAReleaseProvider(root) }
        var value: Int32 = 0

        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(root, &value), CallLeaseHRESULT.ok)
        XCTAssertEqual(value, Int32(SWU_UIA_CONTROL_TYPE_CUSTOM))
        XCTAssertEqual(box.queryCount, 1)
    }
}

private enum CallLeaseHRESULT {
    static let ok: Int32 = 0
    static let unavailable = Int32(bitPattern: 0x8004_0201)
    static let invalidOperation = Int32(bitPattern: 0x8013_1509)
    static let failed = Int32(bitPattern: 0x8000_4005)
}

private enum CallLeaseTestFailure: Error { case creation }

/// This box contains test values only. All tests call their C peers directly
/// and synchronously on one thread; no actor-owned UI state enters C callbacks.
private final class UIACallLeaseBox {
    var context: OpaquePointer?
    var root: UnsafeMutableRawPointer?
    var retainedCall: OpaquePointer?
    var retainNextQuery = false
    var revokeInQuery = false
    var reenterQuery = false
    var reenterWake = false
    var queryCount = 0
    var actionCount = 0
    var wakeCount = 0
    var callbackReleases = 0
    var wakeReleases = 0
    var quiescentInsideQuery: Int32?
    var quiescentInsideWake: Int32?
    var wakesInsideQuery: Int?
    var reentrantStatus: Int32?
    var actionValue: Int32 = 1
    var actionFailure: Int32?
    var wakeResult: Int32 = 0
    var events: [String] = []
    var queryTokens: [UInt] = []
    var selectionTokens: [UInt] = []

    func query(_ call: OpaquePointer) -> Int32 {
        queryCount += 1
        queryTokens.append(UInt(bitPattern: call))
        events.append("query")
        if retainNextQuery {
            retainNextQuery = false
            SWU_UIARetainCall(call)
            retainedCall = call
        }
        if revokeInQuery {
            revokeInQuery = false
            SWU_UIACallRevokeOwner(call)
            events.append("revoked")
            quiescentInsideQuery = SWU_UIAProviderContextIsQuiescent(context)
            wakesInsideQuery = wakeCount
            var value: Int32 = 99
            reentrantStatus = SWU_UIAProviderGetControlTypeResult(root, &value)
        } else if reenterQuery {
            reenterQuery = false
            var value: Int32 = 0
            reentrantStatus = SWU_UIAProviderGetControlTypeResult(root, &value)
        }
        events.append("query-return")
        return Int32(SWU_UIA_CONTROL_TYPE_CUSTOM)
    }

    func action(_ call: OpaquePointer) -> Int32 {
        actionCount += 1
        if let actionFailure { SWU_UIACallFail(call, actionFailure) }
        return actionValue
    }
}

private func callLeaseBox(_ call: OpaquePointer?) -> UIACallLeaseBox? {
    guard let call, let context = SWU_UIACallOwnerContext(call) else { return nil }
    return Unmanaged<UIACallLeaseBox>.fromOpaque(context).takeUnretainedValue()
}

private func releaseCallLeaseCallbackBox(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let owned = Unmanaged<UIACallLeaseBox>.fromOpaque(context)
    owned.takeUnretainedValue().callbackReleases += 1
    owned.release()
}

private func releaseCallLeaseWakeBox(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let owned = Unmanaged<UIACallLeaseBox>.fromOpaque(context)
    owned.takeUnretainedValue().wakeReleases += 1
    owned.release()
}

private func makeCallLeaseWake(_ box: UIACallLeaseBox) -> SWUUIADrainWake {
    var wake = SWUUIADrainWake()
    wake.context = Unmanaged.passRetained(box).toOpaque()
    wake.signal = { context in
        guard let context else { return CallLeaseHRESULT.failed }
        let box = Unmanaged<UIACallLeaseBox>.fromOpaque(context).takeUnretainedValue()
        box.wakeCount += 1
        box.events.append("wake")
        box.quiescentInsideWake = SWU_UIAProviderContextIsQuiescent(box.context)
        if box.reenterWake {
            SWU_UIARevokeProviderContext(box.context)
            var value: Int32 = 99
            box.reentrantStatus = SWU_UIAProviderGetControlTypeResult(box.root, &value)
        }
        return box.wakeResult
    }
    wake.releaseContext = releaseCallLeaseWakeBox
    return wake
}

private final class UIACallLeaseFixture {
    let box = UIACallLeaseBox()
    private(set) var context: OpaquePointer?
    private(set) var root: UnsafeMutableRawPointer?

    init() throws {
        var callbacks = SWUUIACallCallbacks()
        callbacks.context = Unmanaged.passRetained(box).toOpaque()
        callbacks.getControlType = { call, _ in
            guard let call, let box = callLeaseBox(call) else { return 0 }
            return box.query(call)
        }
        callbacks.getBoolProperty = { _, _, property in
            property == Int32(SWU_UIA_BOOL_IS_ENABLED) ? 1 : 0
        }
        callbacks.hasInvokeAction = { _, _ in 1 }
        callbacks.supportsPattern = { _, _, _ in 1 }
        callbacks.toggle = { call, _ in
            guard let call, let box = callLeaseBox(call) else { return 0 }
            return box.action(call)
        }
        callbacks.invokeDefaultAction = { call, _ in
            guard let call, let box = callLeaseBox(call) else { return }
            _ = box.action(call)
        }
        callbacks.setFocus = { call, _ in
            guard let call, let box = callLeaseBox(call) else { return }
            _ = box.action(call)
        }
        callbacks.getSelection = { call, _, buffer, capacity in
            guard let call, let box = callLeaseBox(call) else { return -1 }
            box.selectionTokens.append(UInt(bitPattern: call))
            if let buffer {
                if capacity > 0 { buffer[0] = 7 }
                if capacity > 1 { buffer[1] = 8 }
            }
            return 2
        }
        var wake = makeCallLeaseWake(box)
        guard
            let context = SWU_UIACreateProviderContextWithCalls(
                &callbacks, releaseCallLeaseCallbackBox, &wake)
        else {
            releaseCallLeaseCallbackBox(callbacks.context)
            releaseCallLeaseWakeBox(wake.context)
            throw CallLeaseTestFailure.creation
        }
        self.context = context
        box.context = context
        guard let root = SWU_UIACreateRootProviderWithContext(context, nil) else {
            throw CallLeaseTestFailure.creation
        }
        self.root = root
        box.root = root
    }

    deinit {
        if let context { SWU_UIARevokeProviderContext(context) }
        releaseRetainedCall()
        releaseNativeOwners()
        box.context = nil
    }

    func releaseRetainedCall() {
        let call = box.retainedCall
        box.retainedCall = nil
        if let call { SWU_UIAReleaseCall(call) }
    }

    func releaseNativeOwners() {
        box.root = nil
        if let root {
            self.root = nil
            SWU_UIAReleaseProvider(root)
        }
        if let context {
            self.context = nil
            SWU_UIAReleaseProviderContext(context)
        }
    }

    func pattern(_ kind: Int32) throws -> UnsafeMutableRawPointer {
        var value: UnsafeMutableRawPointer?
        let result = SWU_UIAProviderGetPatternResult(root, kind, &value)
        guard result == CallLeaseHRESULT.ok, let value else { throw CallLeaseTestFailure.creation }
        return value
    }
}
