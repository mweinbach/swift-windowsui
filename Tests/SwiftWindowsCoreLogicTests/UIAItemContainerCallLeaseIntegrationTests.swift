import CUIAInterop
import Foundation
@preconcurrency import XCTest

/// Exercises the real local C provider tables with copied test values. No HWND,
/// UIA client, actor dispatch, window owner, or native event is involved.
@MainActor
final class UIAItemContainerCallLeaseIntegrationTests: XCTestCase {
    func testLogicalLookupAndSameContextStartAfterShareOneFullMethodToken() async throws {
        let fixture = try ItemContainerLeaseFixture()
        let pattern = try fixture.itemContainer()
        defer { SWU_UIAReleaseProvider(pattern) }
        let after = try fixture.element(17)
        defer { SWU_UIAReleaseProvider(after) }
        // Keeping the first token alive also prevents allocator address reuse
        // from making several separately admitted calls look like one token.
        fixture.box.retainFirstCall = true
        var found: UnsafeMutableRawPointer?
        let status = SWU_UIAItemContainerProviderFindItemResult(
            pattern, after, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &found)
        defer { if let found { SWU_UIAReleaseProvider(found) } }

        XCTAssertEqual(status, ItemContainerLeaseHRESULT.ok)
        XCTAssertNotNil(found)
        XCTAssertEqual(fixture.box.events, ["logical.root", "pattern", "find", "logical.target"])
        XCTAssertEqual(fixture.box.lookupCount, 1)
        XCTAssertEqual(fixture.box.lookupAfter, 17)
        let token = try XCTUnwrap(fixture.box.retainedCall)
        XCTAssertEqual(fixture.box.tokens.count, 4)
        XCTAssertTrue(fixture.box.tokens.allSatisfy { $0 == UInt(bitPattern: token) })
        XCTAssertEqual(SWU_UIACallOwnerContext(token), Unmanaged.passUnretained(fixture.box).toOpaque())

        SWU_UIARevokeProviderContext(fixture.context)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 0)
        XCTAssertEqual(fixture.box.wakeCount, 0)
        fixture.releaseRetainedCall()
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
        XCTAssertEqual(fixture.box.wakeCount, 1)
    }

    func testTransportFailureWinsOverLogicalPatternAndFoundPayloads() async throws {
        for point in ItemContainerLeaseFailurePoint.allCases {
            let fixture = try ItemContainerLeaseFixture()
            let pattern = try fixture.itemContainer()
            defer { SWU_UIAReleaseProvider(pattern) }
            let expected =
                point == .pattern || point == .lookup
                ? ItemContainerLeaseHRESULT.failed : ItemContainerLeaseHRESULT.unexpected
            fixture.box.failurePoint = point
            fixture.box.failureCode = expected
            var found: UnsafeMutableRawPointer?

            XCTAssertEqual(
                SWU_UIAItemContainerProviderFindItemResult(
                    pattern, nil, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &found), expected)
            XCTAssertNil(found, "A plausible FOUND payload cannot publish an object after transport failure")
            if let found { SWU_UIAReleaseProvider(found) }
            XCTAssertEqual(fixture.box.lookupCount, point == .lookup || point == .target ? 1 : 0)
            XCTAssertEqual(fixture.box.events, point.expectedEvents)
            XCTAssertEqual(SWU_UIAProviderContextIsAvailable(fixture.context), 1)
        }
    }

    func testTargetRevocationSuppressesOutputAndDelaysDrainUntilCallRelease() async throws {
        let fixture = try ItemContainerLeaseFixture()
        let pattern = try fixture.itemContainer()
        defer { SWU_UIAReleaseProvider(pattern) }
        fixture.box.revokeInTarget = true
        var found: UnsafeMutableRawPointer?

        XCTAssertEqual(
            SWU_UIAItemContainerProviderFindItemResult(
                pattern, nil, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &found),
            ItemContainerLeaseHRESULT.unavailable)
        XCTAssertNil(found)
        if let found { SWU_UIAReleaseProvider(found) }
        XCTAssertEqual(fixture.box.quiescentInsideTarget, 0)
        XCTAssertEqual(fixture.box.wakesInsideTarget, 0)
        XCTAssertEqual(fixture.box.statusInsideTarget, ItemContainerLeaseHRESULT.unavailable)
        XCTAssertEqual(
            fixture.box.events,
            ["logical.root", "pattern", "find", "logical.target", "revoked", "target.return", "wake"])
        XCTAssertEqual(fixture.box.wakeCount, 1)
        XCTAssertEqual(fixture.box.quiescentInsideWake, 1)
        XCTAssertEqual(SWU_UIAProviderContextIsQuiescent(fixture.context), 1)
        XCTAssertEqual(SWU_UIAProviderContextDrainWakeResult(fixture.context), ItemContainerLeaseHRESULT.ok)
    }

    func testForeignContextStartAfterIsRejectedBeforeLookupOrPublication() async throws {
        let fixture = try ItemContainerLeaseFixture()
        let foreign = try ItemContainerLeaseFixture()
        let pattern = try fixture.itemContainer()
        defer { SWU_UIAReleaseProvider(pattern) }
        let after = try foreign.element(17)
        defer { SWU_UIAReleaseProvider(after) }
        fixture.box.retainFirstCall = true
        var found: UnsafeMutableRawPointer?

        XCTAssertEqual(
            SWU_UIAItemContainerProviderFindItemResult(
                pattern, after, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &found),
            ItemContainerLeaseHRESULT.invalidArgument)
        XCTAssertNil(found)
        if let found { SWU_UIAReleaseProvider(found) }
        XCTAssertEqual(fixture.box.events, ["logical.root", "pattern"])
        XCTAssertEqual(fixture.box.lookupCount, 0)
        XCTAssertTrue(foreign.box.events.isEmpty, "Native identity validation must not query the foreign actor")
        let token = try XCTUnwrap(fixture.box.retainedCall)
        XCTAssertEqual(fixture.box.tokens.count, 2)
        XCTAssertTrue(fixture.box.tokens.allSatisfy { $0 == UInt(bitPattern: token) })
        XCTAssertEqual(SWU_UIACallStatus(token), ItemContainerLeaseHRESULT.ok)
        fixture.releaseRetainedCall()
    }
}

private enum ItemContainerLeaseHRESULT {
    static let ok: Int32 = 0
    static let failed = Int32(bitPattern: 0x8000_4005)
    static let unexpected = Int32(bitPattern: 0x8000_FFFF)
    static let unavailable = Int32(bitPattern: 0x8004_0201)
    static let invalidArgument = Int32(bitPattern: 0x8007_0057)
}

private enum ItemContainerLeaseTestFailure: Error { case creation }

private enum ItemContainerLeaseFailurePoint: CaseIterable, Equatable {
    case logical
    case pattern
    case lookup
    case target

    var expectedEvents: [String] {
        switch self {
        case .logical: return ["logical.root"]
        case .pattern: return ["logical.root", "pattern"]
        case .lookup: return ["logical.root", "pattern", "find"]
        case .target: return ["logical.root", "pattern", "find", "logical.target"]
        }
    }
}

/// All C calls in these fixtures are synchronous on the test's one thread.
/// This box owns only test values; it does not contain actor-isolated UI state.
private final class ItemContainerLeaseBox {
    let target: UInt64 = 42
    var context: OpaquePointer?
    var retainedCall: OpaquePointer?
    var retainFirstCall = false
    var revokeInTarget = false
    var failurePoint: ItemContainerLeaseFailurePoint?
    var failureCode = ItemContainerLeaseHRESULT.failed
    var lookupCount = 0
    var lookupAfter: UInt64?
    var wakeCount = 0
    var quiescentInsideTarget: Int32?
    var wakesInsideTarget: Int?
    var statusInsideTarget: Int32?
    var quiescentInsideWake: Int32?
    var events: [String] = []
    var tokens: [UInt] = []

    func record(_ call: OpaquePointer, event: String) {
        events.append(event)
        tokens.append(UInt(bitPattern: call))
        if retainFirstCall && retainedCall == nil {
            SWU_UIARetainCall(call)
            retainedCall = call
        }
    }

    func logicalState(_ call: OpaquePointer, element: UInt64) -> Int32 {
        let isTarget = element == target
        record(call, event: isTarget ? "logical.target" : "logical.root")
        if failurePoint == (isTarget ? .target : .logical) { SWU_UIACallFail(call, failureCode) }
        if isTarget && revokeInTarget {
            // Revocation outranks an earlier transport error, while the
            // enclosing C method must still own the admitted call token.
            SWU_UIACallFail(call, ItemContainerLeaseHRESULT.failed)
            SWU_UIACallRevokeOwner(call)
            events.append("revoked")
            quiescentInsideTarget = SWU_UIAProviderContextIsQuiescent(context)
            wakesInsideTarget = wakeCount
            statusInsideTarget = SWU_UIACallStatus(call)
            events.append("target.return")
        }
        return Int32(isTarget ? SWU_UIA_LOGICAL_ITEM_PLACEHOLDER : SWU_UIA_LOGICAL_ITEM_ORDINARY)
    }
}

private func itemContainerLeaseBox(_ call: OpaquePointer?) -> ItemContainerLeaseBox? {
    guard let call, let context = SWU_UIACallOwnerContext(call) else { return nil }
    return Unmanaged<ItemContainerLeaseBox>.fromOpaque(context).takeUnretainedValue()
}

private func releaseItemContainerLeaseBox(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<ItemContainerLeaseBox>.fromOpaque(context).release()
}

private final class ItemContainerLeaseFixture {
    let box = ItemContainerLeaseBox()
    private(set) var context: OpaquePointer?
    private(set) var root: UnsafeMutableRawPointer?

    init() throws {
        var callbacks = SWUUIACallCallbacks()
        callbacks.context = Unmanaged.passRetained(box).toOpaque()
        callbacks.getLogicalItemState = { call, element in
            guard let call, let box = itemContainerLeaseBox(call) else {
                return Int32(SWU_UIA_LOGICAL_ITEM_UNAVAILABLE)
            }
            return box.logicalState(call, element: element)
        }
        callbacks.supportsPattern = { call, _, pattern in
            guard let call, let box = itemContainerLeaseBox(call) else { return 0 }
            box.record(call, event: "pattern")
            if box.failurePoint == .pattern { SWU_UIACallFail(call, box.failureCode) }
            return pattern == Int32(SWU_UIA_PATTERN_ITEM_CONTAINER) ? 1 : 0
        }
        callbacks.findItem = { call, _, after, target in
            guard let call, let box = itemContainerLeaseBox(call) else {
                return Int32(SWU_UIA_ITEM_LOOKUP_UNAVAILABLE)
            }
            box.record(call, event: "find")
            box.lookupCount += 1
            box.lookupAfter = after
            if box.failurePoint == .lookup { SWU_UIACallFail(call, box.failureCode) }
            target?.pointee = box.target
            return Int32(SWU_UIA_ITEM_LOOKUP_FOUND)
        }
        var wake = SWUUIADrainWake()
        wake.context = Unmanaged.passRetained(box).toOpaque()
        wake.signal = { context in
            guard let context else { return ItemContainerLeaseHRESULT.failed }
            let box = Unmanaged<ItemContainerLeaseBox>.fromOpaque(context).takeUnretainedValue()
            box.wakeCount += 1
            box.events.append("wake")
            box.quiescentInsideWake = SWU_UIAProviderContextIsQuiescent(box.context)
            return ItemContainerLeaseHRESULT.ok
        }
        wake.releaseContext = releaseItemContainerLeaseBox
        guard
            let context = SWU_UIACreateProviderContextWithCalls(
                &callbacks, releaseItemContainerLeaseBox, &wake)
        else {
            releaseItemContainerLeaseBox(callbacks.context)
            releaseItemContainerLeaseBox(wake.context)
            throw ItemContainerLeaseTestFailure.creation
        }
        self.context = context
        box.context = context
        guard let root = SWU_UIACreateRootProviderWithContext(context, nil) else {
            self.context = nil
            box.context = nil
            SWU_UIAReleaseProviderContext(context)
            throw ItemContainerLeaseTestFailure.creation
        }
        self.root = root
    }

    deinit {
        if let context { SWU_UIARevokeProviderContext(context) }
        releaseRetainedCall()
        if let root { SWU_UIAReleaseProvider(root) }
        if let context { SWU_UIAReleaseProviderContext(context) }
        box.context = nil
    }

    func releaseRetainedCall() {
        let call = box.retainedCall
        box.retainedCall = nil
        if let call { SWU_UIAReleaseCall(call) }
    }

    func itemContainer() throws -> UnsafeMutableRawPointer {
        var value: UnsafeMutableRawPointer?
        let status = SWU_UIAProviderQueryInterfaceResult(root, Int32(SWU_UIA_INTERFACE_ITEM_CONTAINER), &value)
        guard status == ItemContainerLeaseHRESULT.ok, let value else { throw ItemContainerLeaseTestFailure.creation }
        return value
    }

    func element(_ token: UInt64) throws -> UnsafeMutableRawPointer {
        guard let value = SWU_UIACreateElementProviderWithContext(context, nil, token) else {
            throw ItemContainerLeaseTestFailure.creation
        }
        return value
    }
}
