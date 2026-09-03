import CUIAInterop
import Foundation
import Synchronization
import WinSDK
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Frozen internal range-operation oracles. The copied headless fixture uses
/// actual C handles and actor dispatch, but no HWND, UIA client or TextPattern.
@MainActor
final class UIANativeTextRangeTests: XCTestCase {
    func testIndependentAcquisitionsShareOriginalDocumentAndExactAssignmentSurvives() async throws {
        let fixture = try NativeRangeFixture("Ae\u{301}Z")
        defer { fixture.close() }
        let first = try fixture.acquire()
        let second = try fixture.acquire()
        defer {
            first.release()
            second.release()
        }
        XCTAssertEqual(fixture.callbacks.tickets.count, 2)
        XCTAssertNotEqual(fixture.callbacks.tickets[0], fixture.callbacks.tickets[1])
        let compared = fixture.compare(first, second)
        XCTAssertEqual(compared.status, 0)
        XCTAssertEqual(compared.value, 1)
        let endpointCases: [(Int32, Int32, Int32)] = [(0, 0, 0), (0, 1, -1), (1, 0, 1), (1, 1, 0)]
        for (left, right, expected) in endpointCases {
            let result = fixture.endpoints(first, left, second, right)
            XCTAssertEqual(result.status, 0)
            XCTAssertEqual(result.value, expected)
        }
        fixture.text.text = String(decoding: Array("Ae\u{301}Z".utf16), as: UTF16.self)
        XCTAssertEqual(fixture.compare(first, second).value, 1)
        XCTAssertEqual(fixture.compare(first, second).status, 0)
        XCTAssertEqual(fixture.read(first).units, Array("Ae\u{301}Z".utf16))
        fixture.assertNoRetainedCallbacks()
    }

    func testCloneOwnsIndependentIdentityAndTicketUntilItsFinalRelease() async throws {
        let fixture = try NativeRangeFixture("Copy\0Exact")
        defer { fixture.close() }
        let original = try fixture.acquire()
        defer { original.release() }
        let clone = try fixture.clone(original)
        defer { clone.release() }
        let originalTicket = try XCTUnwrap(fixture.callbacks.tickets.first)
        let cloneTicket = try XCTUnwrap(fixture.callbacks.cloneTickets.first)
        XCTAssertNotEqual(originalTicket, cloneTicket)
        original.withPointer { originalPointer in
            clone.withPointer { clonePointer in
                var originalUnknown: UnsafeMutableRawPointer?
                var cloneUnknown: UnsafeMutableRawPointer?
                XCTAssertEqual(
                    SWU_UIATextReadQueryInterfaceResult(
                        originalPointer, Int32(SWU_UIA_INTERFACE_UNKNOWN), &originalUnknown), 0)
                XCTAssertEqual(
                    SWU_UIATextReadQueryInterfaceResult(clonePointer, Int32(SWU_UIA_INTERFACE_UNKNOWN), &cloneUnknown),
                    0)
                XCTAssertEqual(originalUnknown, originalPointer)
                XCTAssertEqual(cloneUnknown, clonePointer)
                XCTAssertNotEqual(originalUnknown, cloneUnknown)
                SWU_UIATextReadRelease(originalUnknown)
                SWU_UIATextReadRelease(cloneUnknown)
            }
        }
        XCTAssertEqual(fixture.compare(original, clone).value, 1)
        XCTAssertEqual(fixture.endpoints(original, 1, clone, 1).value, 0)
        XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 2)
        original.release()
        XCTAssertEqual(fixture.callbacks.retiredTickets, [originalTicket])
        fixture.bridge?.drainNativeTextReadRetirements()
        XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 1)
        XCTAssertEqual(fixture.read(clone).units, Array("Copy\0Exact".utf16))
        let released = await nativeRangeOnWorker {
            clone.release()
            return NativeRangeReleaseResult(threadID: GetCurrentThreadId(), scope: UIANativeActorEntry.isActive)
        }
        XCTAssertFalse(released.scope)
        XCTAssertEqual(fixture.callbacks.retiredTickets, [originalTicket, cloneTicket])
        XCTAssertEqual(fixture.callbacks.retirementThreads.last, released.threadID)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while fixture.bridge?.nativeTextReadCount != 0 && clock.now < deadline { await Task.yield() }
        XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 0)
        // A bounded observation policy, not a wall-time guarantee under starvation.
    }

    func testEqualContentAndAutomationIDCannotBorrowAnotherNodeOrSource() async throws {
        let fixture = try NativeRangeFixture("Same")
        defer { fixture.close() }
        let first = try fixture.acquire()
        defer { first.release() }
        let otherNode = ViewNode(frame: fixture.text.frame, text: "Same")
        otherNode.resolvedFrame = otherNode.frame
        otherNode.accessibilityIdentifier = fixture.text.accessibilityIdentifier
        fixture.container.addChild(otherNode)
        let snapshots = fixture.source.uiaElementSnapshots()
        let otherID = try XCTUnwrap(
            snapshots.first { $0.automationID == "native-held-text" && $0.id != fixture.elementID }?.id)
        let provider = try XCTUnwrap(SWU_UIACreateElementProviderWithContext(fixture.nativeContext, nil, otherID))
        defer { SWU_UIAReleaseProvider(provider) }
        let other = try XCTUnwrap(UIANativeActorEntry.withScope { nativeRangeAcquire(provider) }.handle)
        defer { other.release() }
        XCTAssertEqual(fixture.read(first).units, fixture.read(other).units)
        XCTAssertEqual(fixture.compare(first, other).status, NativeRangeHRESULT.invalidArgument)
        XCTAssertEqual(fixture.compare(first, other).value, 0)
        XCTAssertEqual(fixture.endpoints(first, 0, other, 0).status, NativeRangeHRESULT.invalidArgument)
        XCTAssertEqual(fixture.read(first).status, 0)
        XCTAssertEqual(fixture.read(other).status, 0)

        let routing = NativeRangeRoutingSource()
        let routed = try NativeRangeFixture("Same", sourceOverride: routing)
        defer { routed.close() }
        routing.documentSource = routed.source
        let fromFirstSource = try routed.acquire()
        defer { fromFirstSource.release() }
        let secondSource = RuntimeUIAElementTreeSource(runtime: routed.runtime)
        let sameID = try XCTUnwrap(
            secondSource.uiaElementSnapshots().first { $0.automationID == "native-held-text" }?.id)
        XCTAssertEqual(sameID, routed.elementID)
        routing.documentSource = secondSource
        let fromSecondSource = try routed.acquire()
        defer { fromSecondSource.release() }
        XCTAssertEqual(routed.read(fromFirstSource).status, 0)
        XCTAssertEqual(routed.read(fromSecondSource).status, 0)
        XCTAssertEqual(routed.compare(fromFirstSource, fromSecondSource).status, NativeRangeHRESULT.invalidArgument)
        XCTAssertEqual(
            routed.endpoints(fromFirstSource, 1, fromSecondSource, 1).status, NativeRangeHRESULT.invalidArgument)
        withExtendedLifetime(secondSource) {}
    }

    func testForeignContextAndNonRangeIUnknownRejectBeforeActorEntry() async throws {
        let first = try NativeRangeFixture("Same")
        defer { first.close() }
        let second = try NativeRangeFixture("Same")
        defer { second.close() }
        let left = try first.acquire()
        let right = try second.acquire()
        defer {
            left.release()
            right.release()
        }
        XCTAssertEqual(first.elementID, second.elementID)
        XCTAssertEqual(first.callbacks.tickets, second.callbacks.tickets)
        let firstEntries = first.actor.entries
        let secondEntries = second.actor.entries
        XCTAssertEqual(first.compare(left, right).status, NativeRangeHRESULT.invalidArgument)
        XCTAssertEqual(first.endpoints(left, 0, right, 1).status, NativeRangeHRESULT.invalidArgument)
        UIANativeActorEntry.withScope {
            left.withPointer { pointer in
                var output: Int32 = 99
                XCTAssertEqual(
                    SWU_UIATextReadCompare(pointer, first.provider, &output), NativeRangeHRESULT.invalidArgument)
                XCTAssertEqual(output, 0)
                output = 99
                XCTAssertEqual(
                    SWU_UIATextReadCompareEndpoints(pointer, 0, first.provider, 1, &output),
                    NativeRangeHRESULT.invalidArgument)
                XCTAssertEqual(output, 0)
            }
        }
        XCTAssertEqual(first.actor.entries, firstEntries)
        XCTAssertEqual(second.actor.entries, secondEntries)
        XCTAssertEqual(first.read(left).status, 0)
        XCTAssertEqual(second.read(right).status, 0)
    }

    func testContentABAAndCanonicalEquivalentReplacementInvalidateOldPairsAndClones() async throws {
        for replacement in ["different", "\u{e9}"] {
            let fixture = try NativeRangeFixture("e\u{301}")
            defer { fixture.close() }
            let first = try fixture.acquire()
            let second = try fixture.acquire()
            let clone = try fixture.clone(first)
            defer {
                first.release()
                second.release()
                clone.release()
            }
            fixture.text.text = replacement
            fixture.text.text = "e\u{301}"  // No read between either content transition.
            fixture.assertPeerUnavailable(first, second)
            fixture.assertPeerUnavailable(clone, second)
            fixture.assertCloneUnavailable(first)
            fixture.assertCloneUnavailable(clone)
            let current = try fixture.acquire()
            defer { current.release() }
            XCTAssertEqual(fixture.read(current).units, Array("e\u{301}".utf16))
            fixture.assertPeerUnavailable(first, current)
            fixture.assertPeerUnavailable(current, clone)
        }
    }

    func testAttachmentReplacementAndSelectedPathABACannotRefreshOriginalRanges() async throws {
        let fixture = try NativeRangeFixture("Same")
        defer { fixture.close() }
        let first = try fixture.acquire()
        let second = try fixture.acquire()
        defer {
            first.release()
            second.release()
        }
        fixture.container.removeChild(fixture.text)
        fixture.container.addChild(fixture.text)
        fixture.assertPeerUnavailable(first, second)
        fixture.assertCloneUnavailable(first)
        let reattached = try fixture.acquire()
        defer { reattached.release() }
        let replacement = ViewNode(frame: fixture.text.frame, text: "Same")
        replacement.resolvedFrame = replacement.frame
        replacement.accessibilityIdentifier = fixture.text.accessibilityIdentifier
        fixture.container.setChildren([replacement])
        fixture.assertPeerUnavailable(reattached, first)
        fixture.assertCloneUnavailable(reattached)
        let replacementID = try XCTUnwrap(
            fixture.source.uiaElementSnapshots().first { $0.automationID == "native-held-text" }?.id)
        XCTAssertNotEqual(replacementID, fixture.elementID)
        let replacementProvider = try XCTUnwrap(
            SWU_UIACreateElementProviderWithContext(fixture.nativeContext, nil, replacementID))
        defer { SWU_UIAReleaseProvider(replacementProvider) }
        let replacementHandle = try XCTUnwrap(
            UIANativeActorEntry.withScope { nativeRangeAcquire(replacementProvider) }.handle)
        defer { replacementHandle.release() }
        XCTAssertEqual(fixture.read(replacementHandle).units, Array("Same".utf16))
        fixture.assertPeerUnavailable(reattached, replacementHandle)

        let selected = try NativeRangeFixture("Same", selected: true)
        defer { selected.close() }
        let target = try XCTUnwrap(selected.runtime.accessibilityTarget(for: selected.text))
        let selectedFirst = try selected.acquire()
        let selectedSecond = try selected.acquire()
        defer {
            selectedFirst.release()
            selectedSecond.release()
        }
        let extra = ViewNode(text: "Rejected sibling")
        selected.container.addChild(extra)
        selected.container.removeChild(extra)
        XCTAssertTrue(selected.runtime.isAccessibilityTextReadTargetCurrent(target))
        selected.assertPeerUnavailable(selectedFirst, selectedSecond)
        selected.assertCloneUnavailable(selectedFirst)
        let current = try selected.acquire()
        defer { current.release() }
        XCTAssertEqual(selected.read(current).units, Array("Same".utf16))
        selected.assertPeerUnavailable(current, selectedFirst)
        selected.assertNoRetainedCallbacks()
    }

    func testPrivacyEditorSecureLazyAndDisabledOffscreenPoliciesRemainReadOnly() async throws {
        let policies: [(ViewNode) -> Void] = [
            { $0.isPrivacySensitive = true }, { $0.redactionReasons = .placeholder },
            { $0.accessibilityTraits.insert(.isSecureTextInput) },
            { $0.accessibilityTraits.insert(.isTextInput) }, { $0.accessibilityTraits.insert(.isSearchField) },
        ]
        for deny in policies {
            let fixture = try NativeRangeFixture()
            defer { fixture.close() }
            let left = try fixture.acquire()
            let right = try fixture.acquire()
            defer {
                left.release()
                right.release()
            }
            deny(fixture.container)
            fixture.assertPeerUnavailable(left, right)
            fixture.assertCloneUnavailable(left)
            fixture.assertAcquisitionUnavailable()
            fixture.assertNoRetainedCallbacks()
        }
        for kind in 0..<3 {
            let fixture = try NativeRangeFixture()
            defer { fixture.close() }
            let left = try fixture.acquire()
            let right = try fixture.acquire()
            defer {
                left.release()
                right.release()
            }
            let counters = NativeRangeBindingCounters()
            let binding = Binding<String>(
                get: {
                    counters.gets += 1
                    return "Secret"
                }, set: { _ in counters.sets += 1 })
            let selection = Binding<TextSelection?>(
                get: {
                    counters.selectionGets += 1
                    return nil
                }, set: { _ in counters.selectionSets += 1 })
            let view: AnyView
            switch kind {
            case 0: view = AnyView(TextField("Field", text: binding, selection: selection))
            case 1: view = AnyView(TextEditor(text: binding, selection: selection))
            default: view = AnyView(SecureField("Secure", text: binding))
            }
            let context = ViewBuildContext(canvasSizeProvider: { Size(width: 400, height: 200) }, invalidateHandler: {})
            let owner = view.makeComponent(context: context).makeNode(runtime: fixture.runtime)
            fixture.container.textInputController = try XCTUnwrap(owner.textInputController)
            fixture.container.accessibilityTraits = []
            counters.reset()
            fixture.assertPeerUnavailable(left, right)
            fixture.assertCloneUnavailable(left)
            XCTAssertEqual(counters.gets, 0)
            XCTAssertEqual(counters.sets, 0)
            XCTAssertEqual(counters.selectionGets, 0)
            XCTAssertEqual(counters.selectionSets, 0)
            fixture.assertNoRetainedCallbacks()
        }
        let lazy = try NativeRangeFixture()
        defer { lazy.close() }
        let lazyFirst = try lazy.acquire()
        let lazySecond = try lazy.acquire()
        defer {
            lazyFirst.release()
            lazySecond.release()
        }
        var realizations = 0
        let data = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            data.replaceData([0], id: \.self) { _ in
                realizations += 1
                return [ViewNode(text: "Unrealized")]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: data, estimatedExtent: 20, prefetchExtent: 0, maximumMountedRecords: 2,
                maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        lazy.container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(lazy.container))
        lazy.assertPeerUnavailable(lazyFirst, lazySecond)
        lazy.assertCloneUnavailable(lazyFirst)
        XCTAssertEqual(realizations, 0)
        lazy.assertNoRetainedCallbacks()
        let eligible = try NativeRangeFixture("Offscreen")
        defer { eligible.close() }
        eligible.container.accessibilityRespondsToUserInteraction = false  // Explicit AX metadata only.
        eligible.text.frame = Rect(x: 10, y: 1000, width: 180, height: 20)
        eligible.text.resolvedFrame = eligible.text.frame
        let left = try eligible.acquire()
        let right = try eligible.acquire()
        let clone = try eligible.clone(left)
        defer {
            left.release()
            right.release()
            clone.release()
        }
        XCTAssertEqual(eligible.compare(left, right).status, 0)
        XCTAssertEqual(eligible.compare(left, right).value, 1)
        XCTAssertEqual(eligible.read(clone).units, Array("Offscreen".utf16))
        eligible.assertNoRetainedCallbacks()
    }

    func testWorkerOperationsUseActorScopeAndRejectNestedGeneralAndTextRequests() async throws {
        let first = try NativeRangeFixture("Worker")
        defer { first.close() }
        let second = try NativeRangeFixture("Other")
        defer { second.close() }
        let left = try first.acquire()
        let right = try first.acquire()
        let other = try second.acquire()
        defer {
            left.release()
            right.release()
            other.release()
        }
        var nested: [NativeRangeResult] = []
        var generalStatuses: [Int32] = []
        var generalValues: [Int32] = []
        var generalScopes: [Bool] = []
        first.actor.beforeReceive = {
            nested.append(other.read())
            generalScopes.append(UIANativeActorEntry.isActive)
            var value: Int32 = 99
            generalStatuses.append(SWU_UIAProviderGetControlTypeResult(second.provider, &value))
            generalValues.append(value)
            generalScopes.append(UIANativeActorEntry.isActive)
        }
        let entries = first.actor.entries
        let otherEntries = second.actor.entries
        let cloned = await nativeRangeOnWorker { left.clone() }
        XCTAssertEqual(cloned.status, 0)
        let clone = try XCTUnwrap(cloned.handle)
        defer { clone.release() }
        XCTAssertFalse(cloned.scopeBefore)
        XCTAssertFalse(cloned.scopeAfter)
        XCTAssertNotEqual(first.actor.threadIDs.last, cloned.threadID)
        let compared = await nativeRangeOnWorker { left.compare(to: right) }
        XCTAssertEqual(compared.status, 0)
        XCTAssertEqual(compared.value, 1)
        XCTAssertFalse(compared.scopeBefore)
        XCTAssertFalse(compared.scopeAfter)
        let endpoints = await nativeRangeOnWorker { left.compareEndpoints(0, to: right, endpoint: 1) }
        XCTAssertEqual(endpoints.status, 0)
        XCTAssertEqual(endpoints.value, -1)
        XCTAssertFalse(endpoints.scopeBefore)
        XCTAssertFalse(endpoints.scopeAfter)
        XCTAssertEqual(first.actor.entries, entries + 3)
        XCTAssertTrue(first.actor.scopes.suffix(3).allSatisfy { $0 })
        XCTAssertEqual(nested.count, 3)
        XCTAssertTrue(
            nested.allSatisfy {
                $0.status == UIANativeHRESULT.failed && $0.units == nil && $0.scopeBefore && $0.scopeAfter
            })
        XCTAssertEqual(generalStatuses, Array(repeating: UIANativeHRESULT.failed, count: 3))
        XCTAssertEqual(generalValues, [0, 0, 0])
        XCTAssertEqual(generalScopes, Array(repeating: true, count: 6))
        XCTAssertEqual(second.actor.entries, otherEntries)
        first.actor.beforeReceive = nil
        let next = await nativeRangeOnWorker { other.compare(to: other) }
        XCTAssertEqual(next.status, 0)
        XCTAssertEqual(next.value, 1)
        XCTAssertEqual(second.actor.entries, otherEntries + 1)
        XCTAssertFalse(UIANativeActorEntry.isActive)
        XCTAssertEqual(first.effects.commands, 0)
        XCTAssertEqual(second.effects.commands, 0)
    }

    func testQuiescenceDisconnectRevocationAndEscapedHandlesDoNotRetainAuthority() async throws {
        for mode in 0..<3 {
            let fixture = try NativeRangeFixture()
            defer { fixture.close() }
            let original = try fixture.acquire()
            let clone = try fixture.clone(original)
            defer {
                original.release()
                clone.release()
            }
            let entries = fixture.actor.entries
            switch mode {
            case 0:
                fixture.attachment?.beginQuiescence()
                XCTAssertEqual(fixture.attachment?.isQuiescent, true)
                XCTAssertEqual(fixture.effects.disconnects, 0)
            case 1:
                let detached = try XCTUnwrap(fixture.attachment?.detach())
                XCTAssertTrue(detached.isDetached)
                XCTAssertEqual(
                    detached.failures,
                    [.native(operation: "UiaDisconnectProvider", code: Int64(NativeRangeHRESULT.disconnectFailure))])
                XCTAssertEqual(fixture.attachment?.detach().failures, detached.failures)
                XCTAssertEqual(fixture.effects.disconnects, 1)
            default:
                fixture.bridge?.revokeNativeRequests()
                XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 0)
            }
            fixture.assertPeerUnavailable(original, clone)
            fixture.assertCloneUnavailable(original)
            fixture.assertCloneUnavailable(clone)
            XCTAssertEqual(fixture.actor.entries, entries)
            let alias = try XCTUnwrap(clone.alias())
            alias.release()
            var unknown: UnsafeMutableRawPointer?
            XCTAssertEqual(
                clone.withPointer {
                    SWU_UIATextReadQueryInterfaceResult($0, Int32(SWU_UIA_INTERFACE_UNKNOWN), &unknown)
                }, 0)
            XCTAssertNotNil(unknown)
            SWU_UIATextReadRelease(unknown)
        }
        var fixture: NativeRangeFixture? = try NativeRangeFixture()
        defer { fixture?.close() }
        let original = try fixture!.acquire()
        let clone = try fixture!.clone(original)
        defer {
            original.release()
            clone.release()
        }
        weak var bridge = fixture?.bridge
        weak var source = fixture?.source
        weak var runtime = fixture?.runtime
        weak var root = fixture?.runtime.root
        weak var text = fixture?.text
        fixture?.close()
        fixture = nil
        XCTAssertNil(bridge)
        XCTAssertNil(source)
        XCTAssertNil(runtime)
        XCTAssertNil(root)
        XCTAssertNil(text)
        let denied = await nativeRangeOnWorker { original.compare(to: clone) }
        XCTAssertEqual(denied.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertEqual(denied.value, 0)
        let deniedClone = await nativeRangeOnWorker { clone.clone() }
        XCTAssertEqual(deniedClone.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(deniedClone.handle)
        await nativeRangeOnWorker {
            original.release()
            clone.release()
        }
    }

    func testCloneFailureAfterRegistrationRetiresOnlyUnpublishedTicket() async throws {
        for mode in 0..<4 {
            let fixture = try NativeRangeFixture()
            defer { fixture.close() }
            let original = try fixture.acquire()
            defer { original.release() }
            let originalTicket = try XCTUnwrap(fixture.callbacks.tickets.first)
            switch mode {
            case 0: fixture.callbacks.cloneResultOverride = UIANativeHRESULT.failed
            case 1: fixture.callbacks.revokeAfterClone = true
            case 2: fixture.callbacks.cloneResultOverride = 1
            default:
                fixture.callbacks.cloneResultOverride = 1
                fixture.callbacks.cloneCallFailure = UIANativeHRESULT.failed
            }
            let failed = UIANativeActorEntry.withScope { original.clone() }
            let expected =
                mode == 1
                ? UIANativeHRESULT.elementNotAvailable
                : (mode == 2 ? UIANativeHRESULT.unexpected : UIANativeHRESULT.failed)
            XCTAssertEqual(failed.status, expected)
            XCTAssertNil(failed.handle)
            XCTAssertEqual(fixture.callbacks.cloneCalls, 1)
            XCTAssertEqual(fixture.callbacks.cloneTickets.count, 1)
            let newTicket = try XCTUnwrap(fixture.callbacks.cloneTickets.first)
            XCTAssertNotEqual(newTicket, originalTicket)
            XCTAssertEqual(fixture.callbacks.retiredTickets, [newTicket])
            XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 2)
            fixture.bridge?.drainNativeTextReadRetirements()
            XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 1)
            if mode != 1 { XCTAssertEqual(fixture.read(original).status, 0) }
        }
    }

    func testInvalidArgumentsAndOptionalTablesPreserveLegacyCallsWithoutAdvertisement() async throws {
        let fixture = try NativeRangeFixture()
        defer { fixture.close() }
        let handle = try fixture.acquire()
        defer { handle.release() }
        let entries = fixture.actor.entries
        UIANativeActorEntry.withScope {
            var clone = UnsafeMutableRawPointer(bitPattern: 1)
            XCTAssertEqual(SWU_UIATextReadClone(nil, &clone), NativeRangeHRESULT.pointer)
            XCTAssertNil(clone)
            handle.withPointer { pointer in
                XCTAssertEqual(SWU_UIATextReadClone(pointer, nil), NativeRangeHRESULT.pointer)
                var value: Int32 = 99
                XCTAssertEqual(SWU_UIATextReadCompare(nil, pointer, &value), NativeRangeHRESULT.pointer)
                XCTAssertEqual(value, 0)
                value = 99
                XCTAssertEqual(SWU_UIATextReadCompare(pointer, nil, &value), NativeRangeHRESULT.pointer)
                XCTAssertEqual(value, 0)
                XCTAssertEqual(SWU_UIATextReadCompare(pointer, pointer, nil), NativeRangeHRESULT.pointer)
                XCTAssertEqual(SWU_UIATextReadCompareEndpoints(pointer, 0, pointer, 1, nil), NativeRangeHRESULT.pointer)
                for invalid in [Int32.min, -1, 2, Int32.max] {
                    value = 99
                    XCTAssertEqual(
                        SWU_UIATextReadCompareEndpoints(pointer, invalid, pointer, 1, &value),
                        NativeRangeHRESULT.invalidArgument)
                    XCTAssertEqual(value, 0)
                    value = 99
                    XCTAssertEqual(
                        SWU_UIATextReadCompareEndpoints(pointer, 0, pointer, invalid, &value),
                        NativeRangeHRESULT.invalidArgument)
                    XCTAssertEqual(value, 0)
                }
            }
        }
        XCTAssertEqual(fixture.actor.entries, entries)
        // Callback overrides test only the primitive publication guards. Each
        // wrapper first runs the real actor operation, then changes its reply.
        for endpointOperation in [false, true] {
            let payloads: [(Int32?, Int32?, Bool, Int32)] = [
                (1, nil, false, UIANativeHRESULT.unexpected),
                (1, nil, true, UIANativeHRESULT.failed),
                (nil, 2, false, UIANativeHRESULT.unexpected),
                (nil, 0, false, 0),
            ]
            for (statusOverride, valueOverride, failCall, expected) in payloads {
                let candidate = try NativeRangeFixture()
                defer { candidate.close() }
                let range = try candidate.acquire()
                defer { range.release() }
                candidate.callbacks.peerStatusOverride = statusOverride
                candidate.callbacks.peerValueOverride = valueOverride
                candidate.callbacks.peerCallFailure = failCall ? UIANativeHRESULT.failed : nil
                let result =
                    endpointOperation
                    ? candidate.endpoints(range, 0, range, 1)
                    : candidate.compare(range, range)
                XCTAssertEqual(result.status, expected)
                XCTAssertEqual(result.value, 0)
            }
        }
        for mode in [
            NativeRangeFactoryMode.oldText, .missingRange, .incompleteClone, .incompleteCompare, .incompleteEndpoints,
            .ranges,
        ] {
            let routing = NativeRangeRoutingSource(legacy: NativeRangeLegacySource())
            let candidate = try NativeRangeFixture(mode: mode, sourceOverride: routing)
            defer { candidate.close() }
            routing.documentSource = candidate.source
            let range = try candidate.acquire()
            defer { range.release() }
            XCTAssertEqual(candidate.read(range).units, Array("Original".utf16))
            let result = UIANativeActorEntry.withScope { range.clone() }
            XCTAssertEqual(result.status, mode == .ranges ? 0 : NativeRangeHRESULT.noInterface)
            if mode == .ranges { XCTAssertNotNil(result.handle) } else { XCTAssertNil(result.handle) }
            result.handle?.release()
            XCTAssertEqual(candidate.compare(range, range).status, mode == .ranges ? 0 : NativeRangeHRESULT.noInterface)
            XCTAssertEqual(
                candidate.endpoints(range, 0, range, 1).status, mode == .ranges ? 0 : NativeRangeHRESULT.noInterface)
            let invoke = try XCTUnwrap(
                UIANativeActorEntry.withScope { SWU_UIAProviderGetInvokePattern(candidate.rootProvider) })
            defer { SWU_UIAReleaseProvider(invoke) }
            XCTAssertEqual(UIANativeActorEntry.withScope { SWU_UIAProviderInvokeResult(invoke) }, 0)
            routing.legacy?.actionSucceeds = false
            XCTAssertEqual(
                UIANativeActorEntry.withScope { SWU_UIAProviderInvokeResult(invoke) }, Int32(bitPattern: 0x8013_1509))
            XCTAssertEqual(routing.legacy?.invocations, 2)
            for kind in [Int32(SWU_UIA_INTERFACE_TEXT), Int32(SWU_UIA_INTERFACE_TEXT_RANGE)] {
                var queried = UnsafeMutableRawPointer(bitPattern: 1)
                XCTAssertEqual(
                    SWU_UIAProviderQueryInterfaceResult(candidate.provider, kind, &queried),
                    NativeRangeHRESULT.noInterface)
                XCTAssertNil(queried)
                queried = UnsafeMutableRawPointer(bitPattern: 1)
                XCTAssertEqual(
                    range.withPointer { SWU_UIATextReadQueryInterfaceResult($0, kind, &queried) },
                    NativeRangeHRESULT.noInterface)
                XCTAssertNil(queried)
            }
            for pattern in [Int32(10014), 10024, 10029, 10032] {
                var unsupported = UnsafeMutableRawPointer(bitPattern: 1)
                XCTAssertEqual(
                    UIANativeActorEntry.withScope {
                        SWU_UIAProviderGetPatternResult(candidate.provider, pattern, &unsupported)
                    }, 0)
                XCTAssertNil(unsupported)
            }
        }
    }

    func testBoundarySignsAndReentrantRefusalNeverBecomeDistanceOrRevival() async throws {
        for content in ["", "e\u{301}", "👩‍👩‍👧‍👦", "אבA", "\r\n", "\0", "Ae\u{301}👩‍👩‍👧‍👦אב\r\n\0Z"] {
            let fixture = try NativeRangeFixture(content)
            defer { fixture.close() }
            let first = try fixture.acquire()
            let second = try fixture.acquire()
            defer {
                first.release()
                second.release()
            }
            let endpointCases: [(Int32, Int32)] = [(0, 0), (0, 1), (1, 0), (1, 1)]
            for (left, right) in endpointCases {
                let expected: Int32 = content.isEmpty || left == right ? 0 : (left == 0 ? -1 : 1)
                let result = fixture.endpoints(first, left, second, right)
                XCTAssertEqual(result.status, 0)
                XCTAssertEqual(result.value, expected)  // Signs only, not UTF16/Character distances.
            }
            XCTAssertEqual(fixture.compare(first, second).value, 1)
            XCTAssertEqual(fixture.read(first).units, Array(content.utf16))
            // Native acquisition exposes complete spans only. Exercise unequal
            // spans using existing actor APIs, never test-only registration.
            let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.elementID))
            let peerDocument = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.elementID))
            let whole = try XCTUnwrap(document.documentRange())
            let peerWhole = try XCTUnwrap(peerDocument.documentRange())
            let empty = try XCTUnwrap(peerDocument.range(utf16Start: 0, utf16End: 0))
            XCTAssertNotEqual(document, peerDocument)
            XCTAssertNotEqual(whole, peerWhole)
            XCTAssertNil(whole.compareEndpoints(.start, to: peerWhole, endpoint: .start))
            XCTAssertEqual(whole.compareOriginalRange(to: peerWhole), .value(1))
            XCTAssertEqual(whole.compareOriginalRange(to: empty), .value(content.isEmpty ? 1 : 0))
            XCTAssertEqual(
                whole.compareOriginalEndpoint(.end, to: empty, endpoint: .start), .value(content.isEmpty ? 0 : 1))
            XCTAssertEqual(
                empty.compareOriginalEndpoint(.start, to: whole, endpoint: .end), .value(content.isEmpty ? 0 : -1))
        }
        let source = NativeRangeReentrantSource()
        let fixture = try NativeRangeFixture(sourceOverride: source)
        defer { fixture.close() }
        let first = try fixture.acquire()
        let second = try fixture.acquire()
        defer {
            first.release()
            second.release()
        }
        XCTAssertEqual(source.documents.count, 2)
        source.authority.document = source.documents.first
        source.authority.armed = true
        let refused = fixture.compare(first, second)
        XCTAssertEqual(refused.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertEqual(refused.value, 0)
        XCTAssertTrue(source.authority.nestedWasRejected)
        fixture.assertPeerUnavailable(first, second)
        fixture.assertPeerUnavailable(second, first)
        fixture.assertCloneUnavailable(first)
        fixture.assertCloneUnavailable(second)
        XCTAssertTrue(source.documents.allSatisfy { !$0.isCurrent })
        // Package authority reentrancy, not a retained-source callback hook or
        // a claim about native COM reentry during physical capture/release.
        for endpointOperation in [false, true] {
            // Shared authority means matchesOriginalDocument uses its default
            // identity predicate and introduces no extra isCurrent callbacks.
            for trigger in [3, 6] {
                let late = NativeRangeLateRefusalSource()
                let leftDocument = try XCTUnwrap(late.uiaTextDocument(elementID: 1))
                let rightDocument = try XCTUnwrap(late.uiaTextDocument(elementID: 1))
                let leftRange = try XCTUnwrap(leftDocument.documentRange())
                let rightRange = try XCTUnwrap(rightDocument.documentRange())
                late.authority.arm(right: rightDocument, at: trigger)
                let result =
                    endpointOperation
                    ? leftRange.compareOriginalEndpoint(.start, to: rightRange, endpoint: .end)
                    : leftRange.compareOriginalRange(to: rightRange)
                XCTAssertEqual(result, .unavailable)
                XCTAssertEqual(late.authority.triggeredAt, trigger)
                XCTAssertTrue(late.authority.nestedWasRejected)
                XCTAssertFalse(rightDocument.isCurrent)
                XCTAssertTrue(leftDocument.isCurrent)  // Only the right side observed refusal.
                XCTAssertEqual(leftRange.compareOriginalRange(to: rightRange), .unavailable)
                XCTAssertNil(rightRange.clone())
            }
            let late = NativeRangeLateRefusalSource()
            let native = try NativeRangeFixture(sourceOverride: late)
            defer { native.close() }
            let left = try native.acquire()
            let right = try native.acquire()
            defer {
                left.release()
                right.release()
            }
            let rightDocument = try XCTUnwrap(late.documents.last)
            XCTAssertEqual(late.documents.count, 2)
            // Six document checks, then left/right/left in the bridge. Refuse
            // right reentrantly only during that final bridge left callback.
            late.authority.arm(right: rightDocument, at: 9)
            let result =
                endpointOperation
                ? native.endpoints(left, 0, right, 1)
                : native.compare(left, right)
            XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable)
            XCTAssertEqual(result.value, 0)
            XCTAssertEqual(late.authority.triggeredAt, 9)
            XCTAssertTrue(late.authority.nestedWasRejected)
            XCTAssertFalse(rightDocument.isCurrent)
            native.assertPeerUnavailable(left, right)
            native.assertCloneUnavailable(right)
        }
    }
}

private enum NativeRangeHRESULT {
    static let pointer = Int32(bitPattern: 0x8000_4003)
    static let noInterface = Int32(bitPattern: 0x8000_4002)
    static let invalidArgument = Int32(bitPattern: 0x8007_0057)
    static let outOfMemory = Int32(bitPattern: 0x8007_000E)
    static let disconnectFailure = Int32(bitPattern: 0x8000_4005)
}

private struct NativeRangeResult: Sendable {
    let status: Int32
    let units: [UInt16]?
    let threadID: UInt32
    let scopeBefore: Bool
    let scopeAfter: Bool
}

private struct NativeRangeAcquireResult: Sendable {
    let status: Int32
    let handle: NativeRangeHandle?
}

private struct NativeRangeCloneResult: Sendable {
    let status: Int32
    let handle: NativeRangeHandle?
    let threadID: UInt32
    let scopeBefore: Bool
    let scopeAfter: Bool
}

private struct NativeRangePeerResult: Sendable {
    let status: Int32
    let value: Int32
    let threadID: UInt32
    let scopeBefore: Bool
    let scopeAfter: Bool
}

private struct NativeRangeReleaseResult: Sendable {
    let threadID: UInt32
    let scope: Bool
}

private func nativeRangeConsume(_ string: UnsafeMutablePointer<UInt16>?) -> [UInt16]? {
    guard let string else { return nil }
    defer { SWU_UIAFreeString(string) }
    return Array(UnsafeBufferPointer(start: string, count: Int(SysStringLen(string))))
}

private func nativeRangeAcquire(_ provider: UnsafeMutableRawPointer?) -> NativeRangeAcquireResult {
    var raw: UnsafeMutableRawPointer?
    let status = SWU_UIAProviderAcquireTextRead(provider, &raw)
    return NativeRangeAcquireResult(status: status, handle: raw.map { NativeRangeHandle(adopting: $0) })
}

/// Only an explicitly retained C capability crosses threads. Pins are taken
/// under a short mutex; no callback or final native Release runs under it.
private final class NativeRangeHandle: Sendable {
    private let address: Mutex<UInt?>

    init(adopting pointer: UnsafeMutableRawPointer) { address = Mutex(UInt(bitPattern: pointer)) }
    deinit { release() }

    func withPointer<Result>(_ body: (UnsafeMutableRawPointer?) -> Result) -> Result {
        let pinned = address.withLock { value -> UInt? in
            if let value { SWU_UIATextReadRetain(UnsafeMutableRawPointer(bitPattern: value)) }
            return value
        }
        let pointer = pinned.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        defer { SWU_UIATextReadRelease(pointer) }
        return body(pointer)
    }

    func alias() -> NativeRangeHandle? {
        withPointer { pointer in
            guard let pointer else { return nil }
            SWU_UIATextReadRetain(pointer)
            return NativeRangeHandle(adopting: pointer)
        }
    }

    func release() {
        let removed = address.withLock { value in
            let removed = value
            value = nil
            return removed
        }
        if let removed { SWU_UIATextReadRelease(UnsafeMutableRawPointer(bitPattern: removed)) }
    }

    func read(maximum: Int32 = -1) -> NativeRangeResult {
        withPointer { pointer in
            let before = UIANativeActorEntry.isActive
            var copied: UnsafeMutablePointer<UInt16>?
            let status = SWU_UIATextReadGetText(pointer, maximum, &copied)
            return NativeRangeResult(
                status: status, units: nativeRangeConsume(copied), threadID: GetCurrentThreadId(),
                scopeBefore: before, scopeAfter: UIANativeActorEntry.isActive)
        }
    }

    func clone() -> NativeRangeCloneResult {
        withPointer { pointer in
            let before = UIANativeActorEntry.isActive
            var result: UnsafeMutableRawPointer?
            let status = SWU_UIATextReadClone(pointer, &result)
            return NativeRangeCloneResult(
                status: status, handle: result.map { NativeRangeHandle(adopting: $0) },
                threadID: GetCurrentThreadId(), scopeBefore: before, scopeAfter: UIANativeActorEntry.isActive)
        }
    }

    func compare(to other: NativeRangeHandle) -> NativeRangePeerResult {
        withPointer { left in
            other.withPointer { right in
                let before = UIANativeActorEntry.isActive
                var value: Int32 = 99
                let status = SWU_UIATextReadCompare(left, right, &value)
                return NativeRangePeerResult(
                    status: status, value: value, threadID: GetCurrentThreadId(),
                    scopeBefore: before, scopeAfter: UIANativeActorEntry.isActive)
            }
        }
    }

    func compareEndpoints(_ endpoint: Int32, to other: NativeRangeHandle, endpoint otherEndpoint: Int32)
        -> NativeRangePeerResult
    {
        withPointer { left in
            other.withPointer { right in
                let before = UIANativeActorEntry.isActive
                var value: Int32 = 99
                let status = SWU_UIATextReadCompareEndpoints(left, endpoint, right, otherEndpoint, &value)
                return NativeRangePeerResult(
                    status: status, value: value, threadID: GetCurrentThreadId(),
                    scopeBefore: before, scopeAfter: UIANativeActorEntry.isActive)
            }
        }
    }
}

private func nativeRangeOnWorker<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        Thread.detachNewThread { continuation.resume(returning: body()) }
    }
}

/// The registry belongs only to this test file. Its values hold counters,
/// flags only, never a bridge, range, runtime or node.
private enum NativeRangeCallbackRegistry {
    private static let probes = Mutex<[UInt: NativeRangeCallbackProbe]>([:])
    static func register(_ raw: UnsafeMutableRawPointer, _ probe: NativeRangeCallbackProbe) {
        probes.withLock { $0[UInt(bitPattern: raw)] = probe }
    }
    static func remove(_ raw: UnsafeMutableRawPointer) {
        let removed = probes.withLock { $0.removeValue(forKey: UInt(bitPattern: raw)) }
        withExtendedLifetime(removed) {}
    }
    static func probe(_ call: OpaquePointer?) -> NativeRangeCallbackProbe? {
        guard let call, let raw = SWU_UIACallOwnerContext(call) else { return nil }
        return probe(raw: raw)
    }
    static func probe(raw: UnsafeMutableRawPointer?) -> NativeRangeCallbackProbe? {
        guard let raw else { return nil }
        return probes.withLock { $0[UInt(bitPattern: raw)] }
    }
}

@MainActor
private final class NativeRangeActorProbe {
    var threadIDs: [UInt32] = []
    var scopes: [Bool] = []
    var beforeReceive: (() -> Void)?
    var maps = 0
    var layouts = 0
    var actions = 0
    var entries: Int { threadIDs.count }
    func receive() {
        threadIDs.append(GetCurrentThreadId())
        scopes.append(UIANativeActorEntry.isActive)
        beforeReceive?()
    }
}

@MainActor
private final class NativeRangeBindingCounters {
    var gets = 0
    var sets = 0
    var selectionGets = 0
    var selectionSets = 0
    func reset() {
        gets = 0
        sets = 0
        selectionGets = 0
        selectionSets = 0
    }
}

private final class NativeRangeEffects: NativeWindowCommandSink {
    private struct State {
        var commands = 0
        var wakes = 0
        var disconnects = 0
    }
    private let state = Mutex(State())
    var commands: Int { state.withLock { $0.commands } }
    var wakes: Int { state.withLock { $0.wakes } }
    var disconnects: Int { state.withLock { $0.disconnects } }
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
                return NativeRangeHRESULT.disconnectFailure
            },
            raiseFocusChanged: { _ in }, raiseStructureChanged: { _ in }, raiseLiveRegionChanged: { _ in })
    }
}

private struct NativeRangeSnapshots: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private enum NativeRangeFactoryMode {
    case ranges, oldText, missingRange, incompleteClone, incompleteCompare, incompleteEndpoints
}

@MainActor
private final class NativeRangeFixture {
    let runtime: RetainedViewRuntime
    let container: ViewNode
    let text: ViewNode
    let source: RuntimeUIAElementTreeSource
    let elementID: UInt64
    let actor: NativeRangeActorProbe
    let effects: NativeRangeEffects
    let callbacks: NativeRangeCallbackProbe
    let session: UIANativeProviderSession
    let callbackBox: UIANativeCallbackContext
    let nativeContext: OpaquePointer  // Borrowed from attachment/session/handles.
    var bridge: UIAProviderBridge?
    var attachment: UIANativeProviderAttachment?
    var provider: UnsafeMutableRawPointer?
    var rootProvider: UnsafeMutableRawPointer?
    private var registryContext: UnsafeMutableRawPointer?

    init(
        _ content: String = "Original", mode: NativeRangeFactoryMode = .ranges, selected: Bool = false,
        sourceOverride: (any UIAElementTreeSource)? = nil
    ) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
        root.resolvedFrame = root.frame
        let text = ViewNode(frame: Rect(x: 10, y: 10, width: 180, height: 20), text: content)
        text.resolvedFrame = text.frame
        text.accessibilityIdentifier = "native-held-text"
        let container =
            selected
            ? ViewNode.selectedContentBoundary(role: .viewThatFits, child: text)
            : ViewNode(frame: root.frame)
        if !selected { container.addChild(text) }
        root.addChild(container)
        let runtime = RetainedViewRuntime(root: root)
        let actor = NativeRangeActorProbe()
        let source = RuntimeUIAElementTreeSource(
            runtime: runtime,
            screenBoundsMapper: {
                actor.maps += 1
                return $0
            })
        let elementID = try XCTUnwrap(
            source.uiaElementSnapshots().first { $0.automationID == "native-held-text" }?.id)
        actor.maps = 0
        for node in [root, container, text] { node.onLayout = { _ in actor.layouts += 1 } }
        text.onActivate = { actor.actions += 1 }
        let effects = NativeRangeEffects()
        let callbacks = NativeRangeCallbackProbe()
        let geometry = NativeWindowGeometry(
            revision: 5, nativeSequence: 19, clientSize: IntSize(width: 400, height: 200),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
        let surface = NativeWindowSurface(
            key: NativeWindowKey(), generation: 3,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize), geometry: geometry)
        let bridge = UIAProviderBridge(
            source: sourceOverride ?? source, nativeWindowKey: surface.key,
            nativeSnapshotSource: NativeRangeSnapshots(surface: surface), nativeCommandSink: effects,
            beforeRequest: { key, generation, currentGeometry in
                guard key == surface.key else { return .failure(.staleWindow) }
                guard generation == surface.generation else {
                    return .failure(.staleSurface(expected: generation, actual: surface.generation))
                }
                guard currentGeometry == geometry else { return .failure(.execution("Unexpected geometry")) }
                actor.receive()
                return .success(())
            })
        let factory = try XCTUnwrap(
            bridge.makeNativeAttachmentFactory(nativeCalls: effects.calls()) as? UIANativeProviderFactory)
        let raw = Unmanaged.passRetained(factory.callbackContext).toOpaque()
        let wakeBox = UIANativeDrainWake(wake: { effects.wake() }, diagnostics: factory.session.diagnostics)
        let rawWake = Unmanaged.passRetained(wakeBox).toOpaque()
        var calls = UIANativeProviderCallbacks.make(context: raw, supportsLogicalItems: false)
        var wake = SWUUIADrainWake()
        wake.context = rawWake
        wake.signal = signalUIANativeDrainWake
        wake.releaseContext = releaseUIANativeDrainWake
        var textCalls = UIANativeTextReadCallbacks.make()
        textCalls.acquire = nativeRangeWrappedAcquire
        textCalls.retire = nativeRangeWrappedRetire
        var rangeCalls = UIANativeTextRangeCallbacks.make()
        rangeCalls.clone = nativeRangeWrappedClone
        rangeCalls.compare = nativeRangeWrappedCompare
        rangeCalls.compareEndpoints = nativeRangeWrappedEndpoints
        if mode == .incompleteClone { rangeCalls.clone = nil }
        if mode == .incompleteCompare { rangeCalls.compare = nil }
        if mode == .incompleteEndpoints { rangeCalls.compareEndpoints = nil }
        let created: OpaquePointer?
        switch mode {
        case .oldText:
            created = SWU_UIACreateProviderContextWithCallsAndTextRead(
                &calls, releaseUIANativeCallbackContext, &wake,
                { UIANativeProviderCallbacks.invokeDefaultActionResult($0, $1) }, &textCalls)
        case .missingRange:
            created = SWU_UIACreateProviderContextWithCallsAndTextRanges(
                &calls, releaseUIANativeCallbackContext, &wake,
                { UIANativeProviderCallbacks.invokeDefaultActionResult($0, $1) }, &textCalls, nil)
        case .ranges, .incompleteClone, .incompleteCompare, .incompleteEndpoints:
            created = SWU_UIACreateProviderContextWithCallsAndTextRanges(
                &calls, releaseUIANativeCallbackContext, &wake,
                { UIANativeProviderCallbacks.invokeDefaultActionResult($0, $1) }, &textCalls, &rangeCalls)
        }
        guard let created else {
            releaseUIANativeCallbackContext(raw)
            releaseUIANativeDrainWake(rawWake)
            throw NativeWindowOwnerFailure.execution("Unable to construct headless text context")
        }
        do { try factory.session.bind(created) } catch {
            SWU_UIARevokeProviderContext(created)
            SWU_UIAReleaseProviderContext(created)
            throw error
        }
        let attachment = UIANativeProviderAttachment(
            session: factory.session, context: created, hwnd: nil, nativeCalls: factory.nativeCalls)
        self.runtime = runtime
        self.container = container
        self.text = text
        self.source = source
        self.elementID = elementID
        self.actor = actor
        self.effects = effects
        self.callbacks = callbacks
        self.session = factory.session
        self.callbackBox = factory.callbackContext
        self.nativeContext = created
        self.bridge = bridge
        self.attachment = attachment
        NativeRangeCallbackRegistry.register(raw, callbacks)
        registryContext = raw
        do {
            rootProvider = try XCTUnwrap(attachment.retainedRootProviderForTesting())
            provider = try XCTUnwrap(SWU_UIACreateElementProviderWithContext(created, nil, elementID))
        } catch {
            close()
            throw error
        }
    }

    func acquireResult() -> NativeRangeAcquireResult {
        UIANativeActorEntry.withScope { nativeRangeAcquire(provider) }
    }
    func acquire() throws -> NativeRangeHandle {
        let result = acquireResult()
        XCTAssertEqual(result.status, 0)
        return try XCTUnwrap(result.handle)
    }
    func assertAcquisitionUnavailable(file: StaticString = #filePath, line: UInt = #line) {
        let result = acquireResult()
        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable, file: file, line: line)
        XCTAssertNil(result.handle, file: file, line: line)
    }
    func read(_ handle: NativeRangeHandle, maximum: Int32 = -1) -> NativeRangeResult {
        UIANativeActorEntry.withScope { handle.read(maximum: maximum) }
    }
    func clone(_ handle: NativeRangeHandle) throws -> NativeRangeHandle {
        let result = UIANativeActorEntry.withScope { handle.clone() }
        XCTAssertEqual(result.status, 0)
        return try XCTUnwrap(result.handle)
    }
    func compare(_ left: NativeRangeHandle, _ right: NativeRangeHandle) -> NativeRangePeerResult {
        UIANativeActorEntry.withScope { left.compare(to: right) }
    }
    func endpoints(_ left: NativeRangeHandle, _ endpoint: Int32, _ right: NativeRangeHandle, _ otherEndpoint: Int32)
        -> NativeRangePeerResult
    {
        UIANativeActorEntry.withScope { left.compareEndpoints(endpoint, to: right, endpoint: otherEndpoint) }
    }
    func assertPeerUnavailable(
        _ left: NativeRangeHandle, _ right: NativeRangeHandle, file: StaticString = #filePath, line: UInt = #line
    ) {
        let compared = compare(left, right)
        XCTAssertEqual(compared.status, UIANativeHRESULT.elementNotAvailable, file: file, line: line)
        XCTAssertEqual(compared.value, 0, file: file, line: line)
        let ordered = endpoints(left, 0, right, 1)
        XCTAssertEqual(ordered.status, UIANativeHRESULT.elementNotAvailable, file: file, line: line)
        XCTAssertEqual(ordered.value, 0, file: file, line: line)
    }
    func assertCloneUnavailable(_ range: NativeRangeHandle, file: StaticString = #filePath, line: UInt = #line) {
        let cloned = UIANativeActorEntry.withScope { range.clone() }
        XCTAssertEqual(cloned.status, UIANativeHRESULT.elementNotAvailable, file: file, line: line)
        XCTAssertNil(cloned.handle, file: file, line: line)
    }
    func assertUnavailable(_ handle: NativeRangeHandle, file: StaticString = #filePath, line: UInt = #line) {
        let result = read(handle)
        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable, file: file, line: line)
        XCTAssertNil(result.units, file: file, line: line)
    }
    func assertNoRetainedCallbacks(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actor.maps, 0, file: file, line: line)
        XCTAssertEqual(actor.layouts, 0, file: file, line: line)
        XCTAssertEqual(actor.actions, 0, file: file, line: line)
        XCTAssertNil(runtime.focusedNode, file: file, line: line)
    }
    func close() {
        actor.beforeReceive = nil
        bridge?.revokeNativeRequests()
        _ = attachment?.detach()
        if let provider { SWU_UIAReleaseProvider(provider) }
        provider = nil
        if let rootProvider { SWU_UIAReleaseProvider(rootProvider) }
        rootProvider = nil
        attachment = nil
        bridge = nil
        if let registryContext { NativeRangeCallbackRegistry.remove(registryContext) }
        registryContext = nil
    }
}

@MainActor
private final class NativeRangeLegacySource: UIAElementTreeSource {
    var invocations = 0
    var actionSucceeds = true
    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        [
            UIAElementSnapshot(
                id: 0, parentID: nil, name: "Legacy", value: "Legacy value",
                controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT), bounds: Rect(x: 0, y: 0, width: 100, height: 30),
                isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true,
                hasDefaultAction: true, supportsValue: true, isReadOnly: true)
        ]
    }
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        invocations += 1
        return actionSucceeds
    }
    func uiaSetFocus(elementID: UInt64) {}
}

/// Probe state is primitive-only; it never retains an actor document or tree.
private final class NativeRangeCallbackProbe: Sendable {
    private struct State: Sendable {
        var tickets: [UInt64] = []
        var cloneTickets: [UInt64] = []
        var retiredTickets: [UInt64] = []
        var retirementThreads: [UInt32] = []
        var retirementScopes: [Bool] = []
        var cloneCalls = 0
        var cloneResultOverride: Int32?
        var cloneCallFailure: Int32?
        var revokeAfterClone = false
        var peerStatusOverride: Int32?
        var peerValueOverride: Int32?
        var peerCallFailure: Int32?
    }
    private let state = Mutex(State())
    var tickets: [UInt64] { state.withLock { $0.tickets } }
    var cloneTickets: [UInt64] { state.withLock { $0.cloneTickets } }
    var retiredTickets: [UInt64] { state.withLock { $0.retiredTickets } }
    var retirementThreads: [UInt32] { state.withLock { $0.retirementThreads } }
    var retirementScopes: [Bool] { state.withLock { $0.retirementScopes } }
    var cloneCalls: Int { state.withLock { $0.cloneCalls } }
    var cloneResultOverride: Int32? {
        get { state.withLock { $0.cloneResultOverride } }
        set { state.withLock { $0.cloneResultOverride = newValue } }
    }
    var cloneCallFailure: Int32? {
        get { state.withLock { $0.cloneCallFailure } }
        set { state.withLock { $0.cloneCallFailure = newValue } }
    }
    var revokeAfterClone: Bool {
        get { state.withLock { $0.revokeAfterClone } }
        set { state.withLock { $0.revokeAfterClone = newValue } }
    }
    var peerStatusOverride: Int32? {
        get { state.withLock { $0.peerStatusOverride } }
        set { state.withLock { $0.peerStatusOverride = newValue } }
    }
    var peerValueOverride: Int32? {
        get { state.withLock { $0.peerValueOverride } }
        set { state.withLock { $0.peerValueOverride = newValue } }
    }
    var peerCallFailure: Int32? {
        get { state.withLock { $0.peerCallFailure } }
        set { state.withLock { $0.peerCallFailure = newValue } }
    }
    func acquired(_ ticket: UInt64, status: Int32) {
        if status == 0 { state.withLock { $0.tickets.append(ticket) } }
    }
    func cloned(_ call: OpaquePointer?, ticket: UInt64, status: Int32) -> Int32 {
        let options = state.withLock { state in
            state.cloneCalls += 1
            if status == 0 { state.cloneTickets.append(ticket) }
            return (state.cloneResultOverride, state.cloneCallFailure, state.revokeAfterClone)
        }
        if options.2 { SWU_UIACallRevokeOwner(call) }
        if let failure = options.1 { SWU_UIACallFail(call, failure) }
        return options.0 ?? status
    }
    func compared(_ call: OpaquePointer?, result: UnsafeMutablePointer<Int32>?, status: Int32) -> Int32 {
        let options = state.withLock { ($0.peerStatusOverride, $0.peerValueOverride, $0.peerCallFailure) }
        if let value = options.1 { result?.pointee = value }
        if let failure = options.2 { SWU_UIACallFail(call, failure) }
        return options.0 ?? status
    }
    func retiring(_ ticket: UInt64) {
        let thread = GetCurrentThreadId()
        let scope = UIANativeActorEntry.isActive
        state.withLock { state in
            state.retiredTickets.append(ticket)
            state.retirementThreads.append(thread)
            state.retirementScopes.append(scope)
        }
    }
}

private func nativeRangeWrappedAcquire(_ call: OpaquePointer?, _ element: UInt64, _ ticket: UInt64) -> Int32 {
    let result = UIANativeTextReadCallbacks.acquire(call, element, ticket)
    NativeRangeCallbackRegistry.probe(call)?.acquired(ticket, status: result)
    return result
}

private func nativeRangeWrappedClone(_ call: OpaquePointer?, _ source: UInt64, _ ticket: UInt64) -> Int32 {
    let result = UIANativeTextRangeCallbacks.clone(call, source, ticket)
    return NativeRangeCallbackRegistry.probe(call)?.cloned(call, ticket: ticket, status: result) ?? result
}

private func nativeRangeWrappedCompare(
    _ call: OpaquePointer?, _ left: UInt64, _ right: UInt64, _ output: UnsafeMutablePointer<Int32>?
) -> Int32 {
    let result = UIANativeTextRangeCallbacks.compare(call, left, right, output)
    return NativeRangeCallbackRegistry.probe(call)?.compared(call, result: output, status: result) ?? result
}

private func nativeRangeWrappedEndpoints(
    _ call: OpaquePointer?, _ left: UInt64, _ endpoint: Int32, _ right: UInt64, _ otherEndpoint: Int32,
    _ output: UnsafeMutablePointer<Int32>?
) -> Int32 {
    let result = UIANativeTextRangeCallbacks.compareEndpoints(call, left, endpoint, right, otherEndpoint, output)
    return NativeRangeCallbackRegistry.probe(call)?.compared(call, result: output, status: result) ?? result
}

private func nativeRangeWrappedRetire(_ raw: UnsafeMutableRawPointer?, _ ticket: UInt64) {
    NativeRangeCallbackRegistry.probe(raw: raw)?.retiring(ticket)
    UIANativeTextReadCallbacks.make().retire?(raw, ticket)
}

@MainActor
private final class NativeRangeRoutingSource: UIATextDocumentSource {
    var documentSource: (any UIATextDocumentSource)?
    let legacy: NativeRangeLegacySource?
    init(legacy: NativeRangeLegacySource? = nil) { self.legacy = legacy }
    func uiaTextDocument(elementID: UInt64) -> UIATextDocument? {
        documentSource?.uiaTextDocument(elementID: elementID)
    }
    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        legacy?.uiaElementSnapshots() ?? documentSource?.uiaElementSnapshots() ?? []
    }
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        legacy?.uiaInvokeDefaultAction(elementID: elementID) ?? false
    }
    func uiaSetFocus(elementID: UInt64) {}
}

@MainActor
private final class NativeRangeReentrantAuthority: UIATextDocumentAuthority {
    weak var document: UIATextDocument?
    var armed = false
    var didReenter = false
    var nestedWasRejected = false
    func isCurrent() -> Bool {
        guard armed else { return true }
        guard !didReenter else { return false }
        didReenter = true
        nestedWasRejected = document?.isCurrent == false
        return true
    }
}

@MainActor
private final class NativeRangeReentrantSource: UIATextDocumentSource {
    let authority = NativeRangeReentrantAuthority()
    var documents: [UIATextDocument] = []
    func uiaTextDocument(elementID: UInt64) -> UIATextDocument? {
        guard let snapshot = TextRangeSnapshot("Original") else { return nil }
        let document = UIATextDocument(snapshot: snapshot, authority: authority)
        documents.append(document)
        return document
    }
    func uiaElementSnapshots() -> [UIAElementSnapshot] { [] }
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { false }
    func uiaSetFocus(elementID: UInt64) {}
}

@MainActor
private final class NativeRangeLateRefusalAuthority: UIATextDocumentAuthority {
    private weak var right: UIATextDocument?
    private var callCount = 0
    private var trigger: Int?
    private var rejectingNested = false
    private(set) var triggeredAt: Int?
    private(set) var nestedWasRejected = false
    func arm(right: UIATextDocument, at trigger: Int) {
        self.right = right
        self.trigger = trigger
        callCount = 0
    }
    func isCurrent() -> Bool {
        guard !rejectingNested else { return false }
        callCount += 1
        if let trigger, callCount == trigger {
            triggeredAt = callCount
            rejectingNested = true
            nestedWasRejected = right?.isCurrent == false
            rejectingNested = false
        }
        return true
    }
}

@MainActor
private final class NativeRangeLateRefusalSource: UIATextDocumentSource {
    let authority = NativeRangeLateRefusalAuthority()
    var documents: [UIATextDocument] = []
    func uiaTextDocument(elementID: UInt64) -> UIATextDocument? {
        guard let snapshot = TextRangeSnapshot("Original") else { return nil }
        let document = UIATextDocument(snapshot: snapshot, authority: authority)
        documents.append(document)
        return document
    }
    func uiaElementSnapshots() -> [UIAElementSnapshot] { [] }
    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool { false }
    func uiaSetFocus(elementID: UInt64) {}
}
