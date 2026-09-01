import CUIAInterop
import XCTest

/// Real COM metadata and the production disconnect driver with per-call fake
/// native functions. These tests create no HWND, UIA client, or native pump.
@MainActor
final class UIAOwnedRootShutdownTests: XCTestCase {
    func testOwnedFactoryFixesHWNDIdentityWithoutReadingAuthoredRuntimeID() async throws {
        let fixture = try OwnedRootShutdownFixture()
        var count: Int32 = 99
        XCTAssertEqual(SWU_UIAProviderGetRuntimeIdResult(fixture.root, nil, 0, &count), ShutdownHRESULT.ok)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(fixture.box.runtimeQueries, 0)

        let generic = try XCTUnwrap(SWU_UIACreateRootProviderWithContext(fixture.context, fixture.hwnd))
        defer { SWU_UIAReleaseProvider(generic) }
        var runtimeID: Int32 = 0
        XCTAssertEqual(SWU_UIAProviderGetRuntimeIdResult(generic, &runtimeID, 1, &count), ShutdownHRESULT.ok)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(runtimeID, 0x1234)
        XCTAssertEqual(fixture.box.runtimeQueries, 1)
    }

    func testRevokedRootUsesPrivateIdentityWithOriginalHWNDAndBalancedReferences() async throws {
        let fixture = try OwnedRootShutdownFixture()
        SWU_UIARevokeProviderContext(fixture.context)
        var probe = SWUUIADisconnectProbe()

        XCTAssertEqual(SWU_UIAProbeDisconnectProvider(fixture.root, 0, 0, 0, &probe), ShutdownHRESULT.ok)
        XCTAssertEqual(probe.nativeCallCount, 1)
        XCTAssertEqual(probe.usedPrivateIdentity, 1)
        XCTAssertEqual(probe.hostWindowHandle, UInt(bitPattern: fixture.hwnd))
        XCTAssertEqual(probe.contextAvailable, 0)
        XCTAssertEqual(probe.contextQuiescent, 1)
        XCTAssertEqual(probe.originalOptionsResult, ShutdownHRESULT.unavailable)
        XCTAssertEqual(probe.optionsResult, ShutdownHRESULT.ok)
        XCTAssertEqual(probe.options, 0x22)  // ServerSideProvider | UseComThreading.
        XCTAssertEqual(probe.patternResult, ShutdownHRESULT.ok)
        XCTAssertEqual(probe.patternIsNull, 1)
        XCTAssertEqual(probe.propertyResult, ShutdownHRESULT.ok)
        XCTAssertEqual(probe.propertyVariantType, 0)  // VT_EMPTY: no authored payload.
        XCTAssertEqual(probe.unknownResult, ShutdownHRESULT.ok)
        XCTAssertEqual(probe.simpleResult, ShutdownHRESULT.ok)
        XCTAssertEqual(probe.fragmentResult, ShutdownHRESULT.noInterface)
        XCTAssertEqual(probe.sameUnknownIdentity, 1)
        XCTAssertEqual(probe.hostResult, ShutdownHRESULT.ok)
        XCTAssertEqual(probe.identityAfterAddRef, 2)
        XCTAssertEqual(probe.identityAfterRelease, 1)
        XCTAssertEqual(probe.identityAfterOwnerRelease, 0)
        XCTAssertEqual(probe.hostAfterAddRef, 2)
        XCTAssertEqual(probe.hostAfterRelease, 1)
        XCTAssertEqual(probe.hostAfterOwnerRelease, 0)
        XCTAssertEqual(fixture.box.runtimeQueries, 0)
        XCTAssertEqual(fixture.box.controlQueries, 0)

        var count: Int32 = 99
        XCTAssertEqual(
            SWU_UIAProviderGetRuntimeIdResult(fixture.root, nil, 0, &count), ShutdownHRESULT.unavailable)
        XCTAssertEqual(count, 0)
        var value: Int32 = 99
        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &value), ShutdownHRESULT.unavailable)
        XCTAssertEqual(value, 0)
        XCTAssertEqual(fixture.box.callbackReleases, 0)
        fixture.releaseOwners()
        XCTAssertEqual(fixture.box.callbackReleases, 1, "The private identity must not retain the Swift context")
    }

    func testNativeSuccessAndFailuresReturnVerbatimAfterOneCall() async throws {
        for status in [ShutdownHRESULT.ok, 1, ShutdownHRESULT.failed, ShutdownHRESULT.unavailable] {
            let fixture = try OwnedRootShutdownFixture()
            var probe = SWUUIADisconnectProbe()
            XCTAssertEqual(SWU_UIAProbeDisconnectProvider(fixture.root, status, 0, 0, &probe), status)
            XCTAssertEqual(probe.nativeCallCount, 1)
            XCTAssertEqual(probe.usedPrivateIdentity, 1)
            XCTAssertEqual(probe.identityAfterOwnerRelease, 0)
            XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 0)
            XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
            fixture.releaseOwners()
            XCTAssertEqual(fixture.box.callbackReleases, 1)
        }
    }

    func testHostLookupFailureDoesNotFallBackOrRetry() async throws {
        let fixture = try OwnedRootShutdownFixture()
        var probe = SWUUIADisconnectProbe()
        XCTAssertEqual(
            SWU_UIAProbeDisconnectProvider(fixture.root, 0, 1, 0, &probe), ShutdownHRESULT.accessDenied)
        XCTAssertEqual(probe.nativeCallCount, 1)
        XCTAssertEqual(probe.usedPrivateIdentity, 1)
        XCTAssertEqual(probe.hostResult, ShutdownHRESULT.accessDenied)
        XCTAssertEqual(probe.hostWindowHandle, 0)
        XCTAssertEqual(probe.identityAfterOwnerRelease, 0)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 0)
        XCTAssertEqual(fixture.box.controlQueries, 0)
    }

    func testIdentityAllocationFailureDoesNotCallNativeOrReopenOriginal() async throws {
        let fixture = try OwnedRootShutdownFixture()
        var probe = SWUUIADisconnectProbe()
        XCTAssertEqual(
            SWU_UIAProbeDisconnectProvider(fixture.root, 0, 0, 1, &probe), ShutdownHRESULT.outOfMemory)
        XCTAssertEqual(probe.nativeCallCount, 0)
        XCTAssertEqual(probe.usedPrivateIdentity, 0)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 0)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
        fixture.releaseOwners()
        XCTAssertEqual(fixture.box.callbackReleases, 1)
    }

    func testHeldFullCallPreventsNativeDisconnectUntilOwnerCanDrain() async throws {
        let fixture = try OwnedRootShutdownFixture()
        fixture.box.retainNextCall = true
        var controlType: Int32 = 0
        XCTAssertEqual(SWU_UIAProviderGetControlTypeResult(fixture.root, &controlType), ShutdownHRESULT.ok)
        let call = try XCTUnwrap(fixture.box.retainedCall)
        var probe = SWUUIADisconnectProbe()
        XCTAssertEqual(
            SWU_UIAProbeDisconnectProvider(fixture.root, 0, 0, 0, &probe), ShutdownHRESULT.invalidOperation)
        XCTAssertEqual(probe.nativeCallCount, 0)
        XCTAssertEqual(probe.usedPrivateIdentity, 0)
        XCTAssertEqual(SWU_UIACallStatus(call), ShutdownHRESULT.unavailable)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 0)
        fixture.releaseOwners()
        XCTAssertEqual(fixture.box.callbackReleases, 0, "The full call still owns the callback context")
        fixture.releaseRetainedCall()
        XCTAssertEqual(fixture.box.callbackReleases, 1)
    }

    func testChildDoesNotUseRootIdentityFallback() async throws {
        let fixture = try OwnedRootShutdownFixture()
        let child = try XCTUnwrap(SWU_UIACreateElementProviderWithContext(fixture.context, fixture.hwnd, 7))
        defer { SWU_UIAReleaseProvider(child) }
        var probe = SWUUIADisconnectProbe()
        XCTAssertEqual(SWU_UIAProbeDisconnectProvider(child, 0, 0, 0, &probe), ShutdownHRESULT.unavailable)
        XCTAssertEqual(probe.nativeCallCount, 1)
        XCTAssertEqual(probe.usedPrivateIdentity, 0)
        XCTAssertEqual(probe.optionsResult, ShutdownHRESULT.unavailable)
        XCTAssertEqual(probe.hostResult, ShutdownHRESULT.unavailable)
        XCTAssertEqual(probe.hostWindowHandle, 0)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 0)
    }

    func testUnmarkedRootWithHWNDDoesNotGuessRuntimeIdentity() async throws {
        let fixture = try OwnedRootShutdownFixture()
        let generic = try XCTUnwrap(SWU_UIACreateRootProviderWithContext(fixture.context, fixture.hwnd))
        defer { SWU_UIAReleaseProvider(generic) }
        var probe = SWUUIADisconnectProbe()
        XCTAssertEqual(SWU_UIAProbeDisconnectProvider(generic, 0, 0, 0, &probe), ShutdownHRESULT.unavailable)
        XCTAssertEqual(probe.nativeCallCount, 1)
        XCTAssertEqual(probe.usedPrivateIdentity, 0)
        XCTAssertEqual(probe.hostWindowHandle, 0)
    }

    func testOwnedFactoryRejectsMissingHWNDLegacyContextAndRevokedContext() async throws {
        let fixture = try OwnedRootShutdownFixture()
        XCTAssertNil(SWU_UIACreateOwnedHWNDRootProviderWithContext(nil, fixture.hwnd))
        XCTAssertNil(SWU_UIACreateOwnedHWNDRootProviderWithContext(fixture.context, nil))
        var callbacks = SWUUIACallbacks()
        let legacy = try XCTUnwrap(SWU_UIACreateProviderContext(&callbacks, nil))
        defer { SWU_UIAReleaseProviderContext(legacy) }
        XCTAssertNil(SWU_UIACreateOwnedHWNDRootProviderWithContext(legacy, fixture.hwnd))
        SWU_UIARevokeProviderContext(fixture.context)
        XCTAssertNil(SWU_UIACreateOwnedHWNDRootProviderWithContext(fixture.context, fixture.hwnd))
        fixture.releaseOwners()
        XCTAssertEqual(fixture.box.callbackReleases, 1)
    }

    func testMissingProbeOutputFailsBeforeRevokingOwner() async throws {
        let fixture = try OwnedRootShutdownFixture()
        XCTAssertEqual(SWU_UIAProbeDisconnectProvider(fixture.root, 0, 0, 0, nil), ShutdownHRESULT.pointer)
        XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
        var probe = SWUUIADisconnectProbe()
        XCTAssertEqual(SWU_UIAProbeDisconnectProvider(nil, 0, 0, 0, &probe), ShutdownHRESULT.pointer)
        XCTAssertEqual(probe.nativeCallCount, 0)
    }
}

private enum ShutdownHRESULT {
    static let ok: Int32 = 0
    static let pointer = Int32(bitPattern: 0x8000_4003)
    static let failed = Int32(bitPattern: 0x8000_4005)
    static let noInterface = Int32(bitPattern: 0x8000_4002)
    static let outOfMemory = Int32(bitPattern: 0x8007_000E)
    static let accessDenied = Int32(bitPattern: 0x8007_0005)
    static let unavailable = Int32(bitPattern: 0x8004_0201)
    static let invalidOperation = Int32(bitPattern: 0x8013_1509)
}

/// Test data only; every access is synchronous on the calling test's thread.
private final class OwnedRootShutdownBox {
    var runtimeQueries = 0
    var controlQueries = 0
    var callbackReleases = 0
    var retainNextCall = false
    var retainedCall: OpaquePointer?
}

private final class OwnedRootShutdownFixture {
    let box = OwnedRootShutdownBox()
    let hwnd = UnsafeMutableRawPointer(bitPattern: 0x7654)!
    private(set) var context: OpaquePointer?
    private(set) var root: UnsafeMutableRawPointer?

    init() throws {
        var callbacks = SWUUIACallCallbacks()
        callbacks.context = Unmanaged.passRetained(box).toOpaque()
        callbacks.getRuntimeId = { call, _, buffer, capacity in
            guard let call, let context = SWU_UIACallOwnerContext(call) else { return 0 }
            let box = Unmanaged<OwnedRootShutdownBox>.fromOpaque(context).takeUnretainedValue()
            box.runtimeQueries += 1
            if let buffer, capacity > 0 { buffer[0] = 0x1234 }
            return 1
        }
        callbacks.getControlType = { call, _ in
            guard let call, let context = SWU_UIACallOwnerContext(call) else { return 0 }
            let box = Unmanaged<OwnedRootShutdownBox>.fromOpaque(context).takeUnretainedValue()
            box.controlQueries += 1
            if box.retainNextCall {
                box.retainNextCall = false
                SWU_UIARetainCall(call)
                box.retainedCall = call
            }
            return Int32(SWU_UIA_CONTROL_TYPE_CUSTOM)
        }
        guard
            let context = SWU_UIACreateProviderContextWithCalls(
                &callbacks,
                { raw in
                    guard let raw else { return }
                    let owned = Unmanaged<OwnedRootShutdownBox>.fromOpaque(raw)
                    owned.takeUnretainedValue().callbackReleases += 1
                    owned.release()
                }, nil)
        else {
            Unmanaged<OwnedRootShutdownBox>.fromOpaque(callbacks.context!).release()
            throw OwnedRootShutdownFailure.creation
        }
        self.context = context
        guard let root = SWU_UIACreateOwnedHWNDRootProviderWithContext(context, hwnd) else {
            SWU_UIAReleaseProviderContext(context)
            self.context = nil
            throw OwnedRootShutdownFailure.creation
        }
        self.root = root
    }

    deinit {
        if let context { SWU_UIARevokeProviderContext(context) }
        releaseRetainedCall()
        releaseOwners()
    }

    func releaseRetainedCall() {
        let call = box.retainedCall
        box.retainedCall = nil
        if let call { SWU_UIAReleaseCall(call) }
    }

    func releaseOwners() {
        let root = root
        let context = context
        self.root = nil
        self.context = nil
        if let root { SWU_UIAReleaseProvider(root) }
        if let context { SWU_UIAReleaseProviderContext(context) }
    }
}

private enum OwnedRootShutdownFailure: Error { case creation }
