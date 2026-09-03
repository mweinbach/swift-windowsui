import CUIAInterop
import Foundation
import Synchronization
import WinSDK
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Authored against the frozen native read protocol. These headless fixtures
/// use real C handles, ProviderCall and actor dispatch, but install no HWND,
/// message pump, UIA client, or TextPattern/ITextRangeProvider implementation.
@MainActor
final class UIANativeTextReadTests: XCTestCase {
    func testNativeTextPreservesUTF16EmptyAndMaximumPolicy() async throws {
        let original = "Ae\u{301}👩‍👩‍👧‍👦אב\r\n\0Z"
        let fixture = try NativeTextFixture(original)
        defer { fixture.close() }
        let handle = try fixture.acquire()
        defer { handle.release() }
        let all = fixture.read(handle)
        XCTAssertEqual(all.status, 0)
        XCTAssertEqual(all.units, Array(original.utf16))
        XCTAssertEqual(fixture.read(handle, maximum: 0).units, [])
        XCTAssertEqual(fixture.read(handle, maximum: 2).units, Array("A".utf16))
        XCTAssertEqual(fixture.read(handle, maximum: 3).units, Array("Ae\u{301}".utf16))
        let beforeInvalid = fixture.actor.entries
        let invalid = fixture.read(handle, maximum: -2)
        XCTAssertEqual(invalid.status, NativeTextHRESULT.invalidArgument)
        XCTAssertNil(invalid.units)
        XCTAssertEqual(fixture.actor.entries, beforeInvalid)
        XCTAssertEqual(fixture.read(handle, maximum: Int32.min).status, NativeTextHRESULT.invalidArgument)

        var missingHandle = UnsafeMutableRawPointer(bitPattern: 1)
        XCTAssertEqual(SWU_UIAProviderAcquireTextRead(nil, &missingHandle), NativeTextHRESULT.pointer)
        XCTAssertNil(missingHandle)
        XCTAssertEqual(
            UIANativeActorEntry.withScope { SWU_UIAProviderAcquireTextRead(fixture.provider, nil) },
            NativeTextHRESULT.pointer)
        var missingText = UnsafeMutablePointer<UInt16>(bitPattern: 1)
        XCTAssertEqual(SWU_UIATextReadGetText(nil, -1, &missingText), NativeTextHRESULT.pointer)
        XCTAssertNil(missingText)
        XCTAssertEqual(
            UIANativeActorEntry.withScope { handle.withPointer { SWU_UIATextReadGetText($0, -1, nil) } },
            NativeTextHRESULT.pointer)

        let empty = try NativeTextFixture("")
        defer { empty.close() }
        let emptyHandle = try empty.acquire()
        defer { emptyHandle.release() }
        let copiedEmpty = empty.read(emptyHandle)
        XCTAssertEqual(copiedEmpty.status, 0)
        XCTAssertEqual(copiedEmpty.units, [])  // Non-nil, explicitly length-zero BSTR.
        empty.text.isPrivacySensitive = true
        let denied = empty.read(emptyHandle)
        XCTAssertEqual(denied.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(denied.units)
        fixture.assertNoRetainedCallbacks()
        empty.assertNoRetainedCallbacks()
    }

    func testExactContentIdentityRejectsChangesAndABA() async throws {
        let fixture = try NativeTextFixture("e\u{301}")
        defer { fixture.close() }
        let first = try fixture.acquire()
        defer { first.release() }
        fixture.text.text = String(decoding: Array("e\u{301}".utf16), as: UTF16.self)
        XCTAssertEqual(fixture.read(first).units, Array("e\u{301}".utf16))
        fixture.text.text = "\u{e9}"
        fixture.assertUnavailable(first)
        fixture.text.text = "e\u{301}"
        fixture.assertUnavailable(first)
        let second = try fixture.acquire()
        defer { second.release() }
        fixture.text.text = "different"
        fixture.text.text = "e\u{301}"
        fixture.assertUnavailable(second)  // No intervening read during A-B-A.
        let current = try fixture.acquire()
        defer { current.release() }
        XCTAssertEqual(fixture.read(current).units, Array("e\u{301}".utf16))
    }

    func testOriginalAttachmentAndContextCannotBeBorrowed() async throws {
        let first = try NativeTextFixture("Same")
        defer { first.close() }
        let other = try NativeTextFixture("Same")
        defer { other.close() }
        XCTAssertEqual(first.elementID, other.elementID)
        let old = try first.acquire()
        let independent = try other.acquire()
        defer {
            old.release()
            independent.release()
        }
        first.container.removeChild(first.text)
        first.container.addChild(first.text)
        first.assertUnavailable(old)
        let reattached = try first.acquire()
        defer { reattached.release() }
        let replacement = ViewNode(frame: first.text.frame, text: "Same")
        replacement.resolvedFrame = replacement.frame
        replacement.accessibilityIdentifier = first.text.accessibilityIdentifier
        first.container.setChildren([replacement])
        let replacementID = try XCTUnwrap(
            first.source.uiaElementSnapshots().first { $0.automationID == "native-held-text" }?.id)
        XCTAssertNotEqual(replacementID, first.elementID)
        first.assertUnavailable(old)
        first.assertUnavailable(reattached)
        let obsolete = first.acquireResult()
        XCTAssertEqual(obsolete.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(obsolete.handle)
        let replacementProvider = try XCTUnwrap(
            SWU_UIACreateElementProviderWithContext(first.nativeContext, nil, replacementID))
        defer { SWU_UIAReleaseProvider(replacementProvider) }
        let acquiredReplacement = UIANativeActorEntry.withScope { nativeTextAcquire(replacementProvider) }
        XCTAssertEqual(acquiredReplacement.status, 0)
        let replacementHandle = try XCTUnwrap(acquiredReplacement.handle)
        defer { replacementHandle.release() }
        XCTAssertEqual(first.read(replacementHandle).units, Array("Same".utf16))
        // Equal numeric IDs in another original context neither refresh nor
        // adopt either failed handle. Its independent handle remains usable.
        first.assertUnavailable(old)
        XCTAssertEqual(other.read(independent).units, Array("Same".utf16))
    }

    func testPrivacyEditorsLazyAndDisabledOffscreenControls() async throws {
        let policies: [(ViewNode) -> Void] = [
            { $0.isPrivacySensitive = true },
            { $0.redactionReasons = .placeholder },
            { $0.accessibilityTraits.insert(.isSecureTextInput) },
            { $0.accessibilityTraits.insert(.isTextInput) },
            { $0.accessibilityTraits.insert(.isSearchField) },
        ]
        for deny in policies {
            let fixture = try NativeTextFixture()
            defer { fixture.close() }
            let handle = try fixture.acquire()
            defer { handle.release() }
            deny(fixture.container)
            fixture.assertUnavailable(handle)
            fixture.assertAcquisitionUnavailable()
            fixture.assertNoRetainedCallbacks()
        }
        for kind in 0..<3 {
            let fixture = try NativeTextFixture()
            defer { fixture.close() }
            let handle = try fixture.acquire()
            defer { handle.release() }
            let counters = NativeTextBindingCounters()
            let binding = Binding<String>(
                get: {
                    counters.gets += 1
                    return "Secret"
                }, set: { _ in counters.sets += 1 })
            let selection = Binding<TextSelection?>(
                get: {
                    counters.selectionGets += 1
                    return nil
                },
                set: { _ in counters.selectionSets += 1 })
            let view: AnyView
            switch kind {
            case 0: view = AnyView(TextField("Field", text: binding, selection: selection))
            case 1: view = AnyView(TextEditor(text: binding, selection: selection))
            default: view = AnyView(SecureField("Secure", text: binding))
            }
            let build = ViewBuildContext(
                canvasSizeProvider: { Size(width: 400, height: 200) }, invalidateHandler: {})
            let owner = view.makeComponent(context: build).makeNode(runtime: fixture.runtime)
            fixture.container.textInputController = try XCTUnwrap(owner.textInputController)
            fixture.container.accessibilityTraits = []  // Controller, not trait-only refusal.
            counters.reset()
            fixture.assertUnavailable(handle)
            fixture.assertAcquisitionUnavailable()
            XCTAssertEqual(counters.gets, 0)
            XCTAssertEqual(counters.sets, 0)
            XCTAssertEqual(counters.selectionGets, 0)
            XCTAssertEqual(counters.selectionSets, 0)
            fixture.assertNoRetainedCallbacks()
        }
        let lazy = try NativeTextFixture()
        defer { lazy.close() }
        let lazyHandle = try lazy.acquire()
        defer { lazyHandle.release() }
        var realizations = 0
        let data = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            data.replaceData([0], id: \.self) { _ in
                realizations += 1
                return [ViewNode(text: "Unrealized")]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: data, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        lazy.container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(lazy.container))
        lazy.assertUnavailable(lazyHandle)
        lazy.assertAcquisitionUnavailable()
        XCTAssertEqual(realizations, 0)
        lazy.assertNoRetainedCallbacks()

        let eligible = try NativeTextFixture("Offscreen")
        defer { eligible.close() }
        // Explicit AX disabled/read-only metadata, not a claim about the
        // public context.withEnabled environment mapping.
        eligible.container.accessibilityRespondsToUserInteraction = false
        eligible.text.frame = Rect(x: 10, y: 1000, width: 180, height: 20)
        eligible.text.resolvedFrame = eligible.text.frame
        let eligibleHandle = try eligible.acquire()
        defer { eligibleHandle.release() }
        XCTAssertEqual(eligible.read(eligibleHandle).units, Array("Offscreen".utf16))
        eligible.assertNoRetainedCallbacks()
    }

    func testQuiescenceRefusesNativeReadsBeforeActorEntry() async throws {
        let fixture = try NativeTextFixture()
        defer { fixture.close() }
        let localDocument = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.elementID))
        let localRange = try XCTUnwrap(localDocument.documentRange())
        let handle = try fixture.acquire()
        defer { handle.release() }
        let entries = fixture.actor.entries
        fixture.attachment?.beginQuiescence()  // No bridge revoke or detach here.
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        let acquisition = fixture.acquireResult()
        XCTAssertEqual(acquisition.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(acquisition.handle)
        fixture.assertUnavailable(handle)
        XCTAssertEqual(fixture.actor.entries, entries)
        XCTAssertEqual(try localRange.getText(), "Original")
        XCTAssertEqual(fixture.effects.disconnects, 0)
        XCTAssertEqual(fixture.effects.commands, 0)
    }

    func testDisconnectFailureIsTerminalAndNotRetried() async throws {
        let fixture = try NativeTextFixture()
        defer { fixture.close() }
        let handle = try fixture.acquire()
        defer { handle.release() }
        let entries = fixture.actor.entries
        let detached = try XCTUnwrap(fixture.attachment?.detach())
        XCTAssertTrue(detached.isDetached)
        XCTAssertEqual(
            detached.failures,
            [
                .native(operation: "UiaDisconnectProvider", code: Int64(NativeTextHRESULT.disconnectFailure))
            ])
        XCTAssertEqual(fixture.effects.disconnects, 1)
        XCTAssertEqual(fixture.session.disconnectResult, NativeTextHRESULT.disconnectFailure)
        fixture.assertUnavailable(handle)
        XCTAssertEqual(fixture.actor.entries, entries)
        let repeated = try XCTUnwrap(fixture.attachment?.detach())
        XCTAssertTrue(repeated.isDetached)
        XCTAssertEqual(repeated.failures, detached.failures)
        XCTAssertEqual(fixture.effects.disconnects, 1)
    }

    func testRevocationAfterActorReplySuppressesPublicationAndPreservesLease() async throws {
        let fixture = try NativeTextFixture()
        defer { fixture.close() }
        let handle = try fixture.acquire()
        defer { handle.release() }
        fixture.callbacks.revokeAfterCopy = true
        fixture.callbacks.holdCopyCall = true
        let entries = fixture.actor.entries
        let result = fixture.read(handle)
        XCTAssertEqual(fixture.actor.entries, entries + 1)
        XCTAssertEqual(fixture.callbacks.copiedReplies, 1)
        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(result.units)
        XCTAssertEqual(fixture.attachment?.isQuiescent, false)
        XCTAssertEqual(fixture.attachment?.detach().isDetached, false)
        XCTAssertEqual(fixture.effects.disconnects, 0)
        fixture.callbacks.releaseHeldCall()
        XCTAssertEqual(fixture.attachment?.isQuiescent, true)
        XCTAssertEqual(fixture.effects.wakes, 1)
        // The wrapper revokes after the production callback has dispatched and
        // allocated its reply. This does not assert suppression of a later
        // race between the final availability load and pointer publication.
    }

    func testWorkerDispatchAndNestedGuardUseExistingAdmission() async throws {
        let first = try NativeTextFixture("Worker")
        defer { first.close() }
        let second = try NativeTextFixture("Other")
        defer { second.close() }
        let provider = NativeTextProvider(try XCTUnwrap(first.provider))
        let foreignAcquire = await nativeTextOnWorker { provider.acquire() }
        XCTAssertEqual(foreignAcquire.status, 0)
        let handle = try XCTUnwrap(foreignAcquire.handle)
        defer { handle.release() }
        let otherHandle = try second.acquire()
        defer { otherHandle.release() }
        var nested: NativeTextResult?
        var generalStatus: Int32?
        var generalValue: Int32 = 99
        var generalScopeBefore: Bool?
        var generalScopeAfter: Bool?
        first.actor.beforeReceive = {
            nested = otherHandle.read()
            generalScopeBefore = UIANativeActorEntry.isActive
            generalStatus = SWU_UIAProviderGetControlTypeResult(second.provider, &generalValue)
            generalScopeAfter = UIANativeActorEntry.isActive
        }
        let secondEntries = second.actor.entries
        let outer = await nativeTextOnWorker { handle.read() }
        XCTAssertEqual(outer.status, 0)
        XCTAssertEqual(outer.units, Array("Worker".utf16))
        XCTAssertFalse(outer.scopeBefore)
        XCTAssertFalse(outer.scopeAfter)
        XCTAssertNotEqual(first.actor.threadIDs.last, outer.threadID)
        XCTAssertEqual(first.actor.scopes.last, true)
        XCTAssertEqual(nested?.status, UIANativeHRESULT.failed)
        XCTAssertNil(nested?.units)
        XCTAssertEqual(nested?.scopeBefore, true)
        XCTAssertEqual(nested?.scopeAfter, true)
        XCTAssertEqual(generalStatus, UIANativeHRESULT.failed)
        XCTAssertEqual(generalValue, 0)
        XCTAssertEqual(generalScopeBefore, true)
        XCTAssertEqual(generalScopeAfter, true)
        XCTAssertEqual(second.actor.entries, secondEntries)
        first.actor.beforeReceive = nil
        let next = await nativeTextOnWorker { otherHandle.read() }
        XCTAssertEqual(next.status, 0)
        XCTAssertEqual(next.units, Array("Other".utf16))
        XCTAssertEqual(second.actor.entries, secondEntries + 1)
        XCTAssertFalse(UIANativeActorEntry.isActive)
        XCTAssertEqual(first.effects.commands, 0)
        XCTAssertEqual(second.effects.commands, 0)
    }

    func testAliasesAndWorkerReleaseRetireOnActorWithoutRetainingTree() async throws {
        var fixture: NativeTextFixture? = try NativeTextFixture()
        defer { fixture?.close() }
        let handle = try fixture!.acquire()
        let alias = try XCTUnwrap(handle.alias())
        let ticket = try XCTUnwrap(fixture?.callbacks.tickets.first)
        XCTAssertEqual(fixture?.bridge?.nativeTextReadCount, 1)
        handle.release()
        XCTAssertEqual(fixture?.bridge?.nativeTextReadCount, 1)
        XCTAssertEqual(fixture?.callbacks.retiredTickets, [])
        XCTAssertEqual(fixture?.read(alias).units, Array("Original".utf16))
        let released = await nativeTextOnWorker {
            alias.release()
            return NativeTextReleaseResult(threadID: GetCurrentThreadId(), scope: UIANativeActorEntry.isActive)
        }
        XCTAssertFalse(released.scope)
        XCTAssertEqual(fixture?.callbacks.retiredTickets, [ticket])
        XCTAssertEqual(fixture?.callbacks.retirementThreads, [released.threadID])
        XCTAssertEqual(fixture?.callbacks.retirementScopes, [false])
        let retirementClock = ContinuousClock()
        let retirementDeadline = retirementClock.now.advanced(by: .seconds(5))
        while fixture?.bridge?.nativeTextReadCount != 0 && retirementClock.now < retirementDeadline {
            await Task.yield()
        }
        XCTAssertEqual(fixture?.bridge?.nativeTextReadCount, 0)
        let escaped = try fixture!.acquire()
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
        let denied = await nativeTextOnWorker { escaped.read() }
        XCTAssertEqual(denied.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(denied.units)
        await nativeTextOnWorker { escaped.release() }
    }

    func testFailedAcquireRollsBackAfterRegistration() async throws {
        let fixture = try NativeTextFixture()
        defer { fixture.close() }
        fixture.callbacks.revokeAfterAcquire = true
        let failed = fixture.acquireResult()
        XCTAssertEqual(failed.status, UIANativeHRESULT.elementNotAvailable)
        XCTAssertNil(failed.handle)
        XCTAssertEqual(fixture.callbacks.acquireCalls, 1)
        XCTAssertEqual(fixture.callbacks.tickets.count, 1)
        XCTAssertEqual(fixture.callbacks.retiredTickets, fixture.callbacks.tickets)
        XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 1)
        // The synchronous callback has finished registering before the native
        // unpublished handle is destroyed and enqueues the original ticket.
        fixture.bridge?.drainNativeTextReadRetirements()
        XCTAssertEqual(fixture.bridge?.nativeTextReadCount, 0)

        for failCall in [false, true] {
            let positive = try NativeTextFixture()
            defer { positive.close() }
            positive.callbacks.acquireResultOverride = 1  // S_FALSE is not registration success.
            if failCall { positive.callbacks.acquireCallFailure = UIANativeHRESULT.failed }
            let rejected = positive.acquireResult()
            XCTAssertEqual(rejected.status, failCall ? UIANativeHRESULT.failed : UIANativeHRESULT.unexpected)
            XCTAssertNil(rejected.handle)
            XCTAssertEqual(positive.callbacks.tickets.count, 1)
            XCTAssertEqual(positive.callbacks.retiredTickets, positive.callbacks.tickets)
            XCTAssertEqual(positive.bridge?.nativeTextReadCount, 1)
            positive.bridge?.drainNativeTextReadRetirements()
            XCTAssertEqual(positive.bridge?.nativeTextReadCount, 0)
        }

        let allocation = try NativeTextFixture()
        defer { allocation.close() }
        var refused = UnsafeMutableRawPointer(bitPattern: 1)
        let status = UIANativeActorEntry.withScope {
            SWU_UIAProviderAcquireTextReadWithAllocationFailureForTesting(allocation.provider, &refused)
        }
        XCTAssertEqual(status, NativeTextHRESULT.outOfMemory)
        XCTAssertNil(refused)
        XCTAssertEqual(allocation.callbacks.acquireCalls, 0)
        XCTAssertEqual(allocation.callbacks.retiredTickets, [])
        XCTAssertEqual(allocation.actor.entries, 0)
        XCTAssertEqual(allocation.bridge?.nativeTextReadCount, 0)
        let successful = try allocation.acquire()
        defer { successful.release() }
        XCTAssertEqual(allocation.callbacks.tickets, [2])  // Failed allocation burns ticket 1.
        XCTAssertEqual(allocation.bridge?.nativeTextReadCount, 1)
    }

    func testTicketExhaustionAndDuplicateRetirementAreSafe() async throws {
        var next = UInt64.max
        var ticket: UInt64 = 17
        XCTAssertEqual(SWU_UIATextReadNextTicket(&next, &ticket), 0)
        XCTAssertEqual(ticket, UInt64.max)
        XCTAssertEqual(next, 0)
        XCTAssertEqual(SWU_UIATextReadNextTicket(&next, &ticket), NativeTextHRESULT.outOfMemory)
        XCTAssertEqual(ticket, 0)
        XCTAssertEqual(next, 0)
        XCTAssertEqual(SWU_UIATextReadNextTicket(&next, &ticket), NativeTextHRESULT.outOfMemory)
        XCTAssertEqual(next, 0)
        XCTAssertEqual(UIANativeTextReadBuffer.checkedLength(Int(Int32.max)), Int32.max)
        XCTAssertNil(UIANativeTextReadBuffer.checkedLength(Int(Int32.max) + 1))
        XCTAssertNil(UIANativeTextReadBuffer.checkedLength(-1))
        XCTAssertEqual(UIANativeTextReadBuffer.checkedLength(0), 0)

        let first = try NativeTextFixture("One")
        defer { first.close() }
        let second = try NativeTextFixture("Two")
        defer { second.close() }
        let firstHandle = try first.acquire()
        let secondHandle = try second.acquire()
        defer {
            firstHandle.release()
            secondHandle.release()
        }
        let firstTicket = try XCTUnwrap(first.callbacks.tickets.first)
        XCTAssertEqual(first.callbacks.tickets, second.callbacks.tickets)
        XCTAssertTrue(first.callbackBox.textReadRetirements.enqueue(firstTicket))
        XCTAssertFalse(first.callbackBox.textReadRetirements.enqueue(firstTicket))
        XCTAssertFalse(first.callbackBox.textReadRetirements.enqueue(0))
        XCTAssertFalse(first.callbackBox.textReadRetirements.enqueue(UInt64.max))
        first.bridge?.drainNativeTextReadRetirements()
        XCTAssertEqual(first.bridge?.nativeTextReadCount, 0)
        XCTAssertEqual(second.bridge?.nativeTextReadCount, 1)
        first.assertUnavailable(firstHandle)
        XCTAssertEqual(second.read(secondHandle).units, Array("Two".utf16))
        // The clear happened under the mailbox mutex; a later enqueue gets a
        // new scheduling claim. Duplicate/stale retirement never crosses boxes.
        XCTAssertTrue(first.callbackBox.textReadRetirements.enqueue(firstTicket))
        first.bridge?.drainNativeTextReadRetirements()
        first.callbackBox.retireTextRead(0)
        first.callbackBox.retireTextRead(UInt64.max)
        first.bridge?.drainNativeTextReadRetirements()
        XCTAssertEqual(second.bridge?.nativeTextReadCount, 1)
    }

    func testLegacyTablesValueAndTextInterfacesStayUnchanged() async throws {
        for mode in [NativeTextFactoryMode.oldCalls, .oldInvokeResult, .missingText, .incompleteText, .text] {
            let source = NativeTextLegacySource()
            let fixture = try NativeTextFixture(mode: mode, sourceOverride: source)
            defer { fixture.close() }
            let acquired = UIANativeActorEntry.withScope { nativeTextAcquire(fixture.rootProvider) }
            XCTAssertEqual(
                acquired.status,
                mode == .text ? UIANativeHRESULT.elementNotAvailable : NativeTextHRESULT.noInterface)
            XCTAssertNil(acquired.handle)
            var controlType: Int32 = 0
            XCTAssertEqual(
                UIANativeActorEntry.withScope {
                    SWU_UIAProviderGetControlTypeResult(fixture.rootProvider, &controlType)
                }, 0)
            XCTAssertEqual(controlType, Int32(SWU_UIA_CONTROL_TYPE_EDIT))
            let value = try XCTUnwrap(
                UIANativeActorEntry.withScope {
                    SWU_UIAProviderGetValuePattern(fixture.rootProvider)
                })
            defer { SWU_UIAReleaseProvider(value) }
            var copied: UnsafeMutablePointer<UInt16>?
            let valueStatus = UIANativeActorEntry.withScope { SWU_UIAValueProviderGetValueResult(value, &copied) }
            XCTAssertEqual(valueStatus, 0)
            XCTAssertEqual(nativeTextConsume(copied), Array("Legacy value".utf16))
            let invoke = try XCTUnwrap(
                UIANativeActorEntry.withScope {
                    SWU_UIAProviderGetInvokePattern(fixture.rootProvider)
                })
            defer { SWU_UIAReleaseProvider(invoke) }
            XCTAssertEqual(UIANativeActorEntry.withScope { SWU_UIAProviderInvokeResult(invoke) }, 0)
            XCTAssertEqual(source.invocations, 1)
            source.actionSucceeds = false
            let rejected = UIANativeActorEntry.withScope { SWU_UIAProviderInvokeResult(invoke) }
            XCTAssertEqual(rejected, mode == .oldCalls ? 0 : Int32(bitPattern: 0x8013_1509))
            XCTAssertEqual(source.invocations, 2)
        }
        let fixture = try NativeTextFixture()
        defer { fixture.close() }
        let handle = try fixture.acquire()
        defer { handle.release() }
        XCTAssertEqual(fixture.read(handle).units, Array("Original".utf16))
        for kind in [Int32(SWU_UIA_INTERFACE_TEXT), Int32(SWU_UIA_INTERFACE_TEXT_RANGE)] {
            var queried = UnsafeMutableRawPointer(bitPattern: 1)
            XCTAssertEqual(
                SWU_UIAProviderQueryInterfaceResult(fixture.provider, kind, &queried), NativeTextHRESULT.noInterface)
            XCTAssertNil(queried)
            queried = UnsafeMutableRawPointer(bitPattern: 1)
            XCTAssertEqual(
                handle.withPointer { SWU_UIATextReadQueryInterfaceResult($0, kind, &queried) },
                NativeTextHRESULT.noInterface)
            XCTAssertNil(queried)
        }
        var unknown: UnsafeMutableRawPointer?
        XCTAssertEqual(
            handle.withPointer {
                SWU_UIATextReadQueryInterfaceResult($0, Int32(SWU_UIA_INTERFACE_UNKNOWN), &unknown)
            }, 0)
        XCTAssertNotNil(unknown)
        handle.withPointer { XCTAssertEqual(unknown, $0) }
        SWU_UIATextReadRelease(unknown)
        for pattern in [Int32(10014), 10024, 10029, 10032] {
            var unsupported = UnsafeMutableRawPointer(bitPattern: 1)
            XCTAssertEqual(
                UIANativeActorEntry.withScope {
                    SWU_UIAProviderGetPatternResult(fixture.provider, pattern, &unsupported)
                }, 0)
            XCTAssertNil(unsupported)
        }
    }
}

private enum NativeTextHRESULT {
    static let pointer = Int32(bitPattern: 0x8000_4003)
    static let noInterface = Int32(bitPattern: 0x8000_4002)
    static let invalidArgument = Int32(bitPattern: 0x8007_0057)
    static let outOfMemory = Int32(bitPattern: 0x8007_000E)
    static let disconnectFailure = Int32(bitPattern: 0x8000_4005)
}

private struct NativeTextResult: Sendable {
    let status: Int32
    let units: [UInt16]?
    let threadID: UInt32
    let scopeBefore: Bool
    let scopeAfter: Bool
}

private struct NativeTextAcquireResult: Sendable {
    let status: Int32
    let handle: NativeTextHandle?
}

private struct NativeTextReleaseResult: Sendable {
    let threadID: UInt32
    let scope: Bool
}

private func nativeTextConsume(_ string: UnsafeMutablePointer<UInt16>?) -> [UInt16]? {
    guard let string else { return nil }
    defer { SWU_UIAFreeString(string) }
    return Array(UnsafeBufferPointer(start: string, count: Int(SysStringLen(string))))
}

private func nativeTextAcquire(_ provider: UnsafeMutableRawPointer?) -> NativeTextAcquireResult {
    var raw: UnsafeMutableRawPointer?
    let status = SWU_UIAProviderAcquireTextRead(provider, &raw)
    return NativeTextAcquireResult(status: status, handle: raw.map { NativeTextHandle(adopting: $0) })
}

/// Only an explicitly retained C capability crosses threads. Pins are taken
/// under a short mutex; no callback or final native Release runs under it.
private final class NativeTextHandle: Sendable {
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

    func alias() -> NativeTextHandle? {
        withPointer { pointer in
            guard let pointer else { return nil }
            SWU_UIATextReadRetain(pointer)
            return NativeTextHandle(adopting: pointer)
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

    func read(maximum: Int32 = -1) -> NativeTextResult {
        withPointer { pointer in
            let before = UIANativeActorEntry.isActive
            var copied: UnsafeMutablePointer<UInt16>?
            let status = SWU_UIATextReadGetText(pointer, maximum, &copied)
            return NativeTextResult(
                status: status, units: nativeTextConsume(copied), threadID: GetCurrentThreadId(),
                scopeBefore: before, scopeAfter: UIANativeActorEntry.isActive)
        }
    }
}

private final class NativeTextProvider: Sendable {
    private let address: UInt
    init(_ pointer: UnsafeMutableRawPointer) {
        address = UInt(bitPattern: pointer)
        SWU_UIAAddRefProvider(pointer)
    }
    deinit { SWU_UIAReleaseProvider(UnsafeMutableRawPointer(bitPattern: address)) }
    func acquire() -> NativeTextAcquireResult { nativeTextAcquire(UnsafeMutableRawPointer(bitPattern: address)) }
}

private func nativeTextOnWorker<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        Thread.detachNewThread { continuation.resume(returning: body()) }
    }
}

/// The registry belongs only to this test file. Its values hold counters,
/// flags and a checked call lease, never a bridge, range, runtime or node.
private enum NativeTextCallbackRegistry {
    private static let probes = Mutex<[UInt: NativeTextCallbackProbe]>([:])
    static func register(_ raw: UnsafeMutableRawPointer, _ probe: NativeTextCallbackProbe) {
        probes.withLock { $0[UInt(bitPattern: raw)] = probe }
    }
    static func remove(_ raw: UnsafeMutableRawPointer) {
        let removed = probes.withLock { $0.removeValue(forKey: UInt(bitPattern: raw)) }
        withExtendedLifetime(removed) {}
    }
    static func probe(_ call: OpaquePointer?) -> NativeTextCallbackProbe? {
        guard let call, let raw = SWU_UIACallOwnerContext(call) else { return nil }
        return probe(raw: raw)
    }
    static func probe(raw: UnsafeMutableRawPointer?) -> NativeTextCallbackProbe? {
        guard let raw else { return nil }
        return probes.withLock { $0[UInt(bitPattern: raw)] }
    }
}

private final class NativeTextCallbackProbe: Sendable {
    private struct State: Sendable {
        var acquireCalls = 0
        var copiedReplies = 0
        var tickets: [UInt64] = []
        var retiredTickets: [UInt64] = []
        var retirementThreads: [UInt32] = []
        var retirementScopes: [Bool] = []
        var revokeAfterAcquire = false
        var acquireResultOverride: Int32?
        var acquireCallFailure: Int32?
        var revokeAfterCopy = false
        var holdCopyCall = false
        var heldCall: UIANativeCallLease?
    }
    private let state = Mutex(State())
    var acquireCalls: Int { state.withLock { $0.acquireCalls } }
    var copiedReplies: Int { state.withLock { $0.copiedReplies } }
    var tickets: [UInt64] { state.withLock { $0.tickets } }
    var retiredTickets: [UInt64] { state.withLock { $0.retiredTickets } }
    var retirementThreads: [UInt32] { state.withLock { $0.retirementThreads } }
    var retirementScopes: [Bool] { state.withLock { $0.retirementScopes } }
    var revokeAfterAcquire: Bool {
        get { state.withLock { $0.revokeAfterAcquire } }
        set { state.withLock { $0.revokeAfterAcquire = newValue } }
    }
    var acquireResultOverride: Int32? {
        get { state.withLock { $0.acquireResultOverride } }
        set { state.withLock { $0.acquireResultOverride = newValue } }
    }
    var acquireCallFailure: Int32? {
        get { state.withLock { $0.acquireCallFailure } }
        set { state.withLock { $0.acquireCallFailure = newValue } }
    }
    var revokeAfterCopy: Bool {
        get { state.withLock { $0.revokeAfterCopy } }
        set { state.withLock { $0.revokeAfterCopy = newValue } }
    }
    var holdCopyCall: Bool {
        get { state.withLock { $0.holdCopyCall } }
        set { state.withLock { $0.holdCopyCall = newValue } }
    }
    func beganAcquire() { state.withLock { $0.acquireCalls += 1 } }
    func retiring(_ ticket: UInt64) {
        let thread = GetCurrentThreadId()
        let scope = UIANativeActorEntry.isActive
        state.withLock { state in
            state.retiredTickets.append(ticket)
            state.retirementThreads.append(thread)
            state.retirementScopes.append(scope)
        }
    }
    func acquired(_ call: OpaquePointer?, ticket: UInt64, status: Int32) -> Int32 {
        let options = state.withLock { state in
            if status == 0 { state.tickets.append(ticket) }
            return (state.revokeAfterAcquire, state.acquireResultOverride, state.acquireCallFailure)
        }
        if options.0 { SWU_UIACallRevokeOwner(call) }
        if let failure = options.2 { SWU_UIACallFail(call, failure) }
        return options.1 ?? status
    }
    func copied(_ call: OpaquePointer?, hasReply: Bool) {
        let options = state.withLock { state in
            if hasReply { state.copiedReplies += 1 }
            return (state.holdCopyCall, state.revokeAfterCopy)
        }
        if options.0, let call {
            let retained = UIANativeCallLease(retaining: call)
            let replaced = state.withLock { state in
                let replaced = state.heldCall
                state.heldCall = retained
                return replaced
            }
            withExtendedLifetime(replaced) {}
        }
        if options.1 { SWU_UIACallRevokeOwner(call) }
    }
    func releaseHeldCall() {
        let released = state.withLock { state in
            let released = state.heldCall
            state.heldCall = nil
            return released
        }
        withExtendedLifetime(released) {}
    }
}

private func nativeTextWrappedAcquire(_ call: OpaquePointer?, _ element: UInt64, _ ticket: UInt64) -> Int32 {
    let probe = NativeTextCallbackRegistry.probe(call)
    probe?.beganAcquire()
    let result = UIANativeTextReadCallbacks.acquire(call, element, ticket)
    return probe?.acquired(call, ticket: ticket, status: result) ?? result
}

private func nativeTextWrappedCopy(
    _ call: OpaquePointer?, _ ticket: UInt64, _ maximum: Int32
) -> UnsafeMutablePointer<UInt16>? {
    let result = UIANativeTextReadCallbacks.copyText(call, ticket, maximum)
    NativeTextCallbackRegistry.probe(call)?.copied(call, hasReply: result != nil)
    return result
}

private func nativeTextWrappedRetire(_ raw: UnsafeMutableRawPointer?, _ ticket: UInt64) {
    NativeTextCallbackRegistry.probe(raw: raw)?.retiring(ticket)
    // Keep the production numeric-mailbox retirement path. The test wrapper
    // records primitive observations only, outside its probe mutex.
    UIANativeTextReadCallbacks.make().retire?(raw, ticket)
}

@MainActor
private final class NativeTextActorProbe {
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
private final class NativeTextBindingCounters {
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

private final class NativeTextEffects: NativeWindowCommandSink {
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
                return NativeTextHRESULT.disconnectFailure
            },
            raiseFocusChanged: { _ in }, raiseStructureChanged: { _ in }, raiseLiveRegionChanged: { _ in })
    }
}

private struct NativeTextSnapshots: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private enum NativeTextFactoryMode { case text, oldCalls, oldInvokeResult, missingText, incompleteText }

@MainActor
private final class NativeTextFixture {
    let runtime: RetainedViewRuntime
    let container: ViewNode
    let text: ViewNode
    let source: RuntimeUIAElementTreeSource
    let elementID: UInt64
    let actor: NativeTextActorProbe
    let effects: NativeTextEffects
    let callbacks: NativeTextCallbackProbe
    let session: UIANativeProviderSession
    let callbackBox: UIANativeCallbackContext
    let nativeContext: OpaquePointer  // Borrowed from attachment/session/handles.
    var bridge: UIAProviderBridge?
    var attachment: UIANativeProviderAttachment?
    var provider: UnsafeMutableRawPointer?
    var rootProvider: UnsafeMutableRawPointer?
    private var registryContext: UnsafeMutableRawPointer?

    init(
        _ content: String = "Original", mode: NativeTextFactoryMode = .text,
        sourceOverride: (any UIAElementTreeSource)? = nil
    ) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
        root.resolvedFrame = root.frame
        let container = ViewNode(frame: root.frame)
        let text = ViewNode(frame: Rect(x: 10, y: 10, width: 180, height: 20), text: content)
        text.resolvedFrame = text.frame
        text.accessibilityIdentifier = "native-held-text"
        container.addChild(text)
        root.addChild(container)
        let runtime = RetainedViewRuntime(root: root)
        let actor = NativeTextActorProbe()
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
        let effects = NativeTextEffects()
        let callbacks = NativeTextCallbackProbe()
        let geometry = NativeWindowGeometry(
            revision: 5, nativeSequence: 19, clientSize: IntSize(width: 400, height: 200),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
        let surface = NativeWindowSurface(
            key: NativeWindowKey(), generation: 3,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize), geometry: geometry)
        let bridge = UIAProviderBridge(
            source: sourceOverride ?? source, nativeWindowKey: surface.key,
            nativeSnapshotSource: NativeTextSnapshots(surface: surface), nativeCommandSink: effects,
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
        textCalls.acquire = nativeTextWrappedAcquire
        textCalls.copyText = nativeTextWrappedCopy
        textCalls.retire = nativeTextWrappedRetire
        if mode == .incompleteText { textCalls.copyText = nil }
        let created: OpaquePointer?
        switch mode {
        case .oldCalls:
            created = SWU_UIACreateProviderContextWithCalls(&calls, releaseUIANativeCallbackContext, &wake)
        case .oldInvokeResult:
            created = SWU_UIACreateProviderContextWithCallsAndInvokeResult(
                &calls, releaseUIANativeCallbackContext, &wake,
                { UIANativeProviderCallbacks.invokeDefaultActionResult($0, $1) })
        case .missingText:
            created = SWU_UIACreateProviderContextWithCallsAndTextRead(
                &calls, releaseUIANativeCallbackContext, &wake,
                { UIANativeProviderCallbacks.invokeDefaultActionResult($0, $1) }, nil)
        case .text, .incompleteText:
            created = SWU_UIACreateProviderContextWithCallsAndTextRead(
                &calls, releaseUIANativeCallbackContext, &wake,
                { UIANativeProviderCallbacks.invokeDefaultActionResult($0, $1) }, &textCalls)
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
        NativeTextCallbackRegistry.register(raw, callbacks)
        registryContext = raw
        do {
            rootProvider = try XCTUnwrap(attachment.retainedRootProviderForTesting())
            provider = try XCTUnwrap(SWU_UIACreateElementProviderWithContext(created, nil, elementID))
        } catch {
            close()
            throw error
        }
    }

    func acquireResult() -> NativeTextAcquireResult {
        UIANativeActorEntry.withScope { nativeTextAcquire(provider) }
    }
    func acquire() throws -> NativeTextHandle {
        let result = acquireResult()
        XCTAssertEqual(result.status, 0)
        return try XCTUnwrap(result.handle)
    }
    func assertAcquisitionUnavailable(file: StaticString = #filePath, line: UInt = #line) {
        let result = acquireResult()
        XCTAssertEqual(result.status, UIANativeHRESULT.elementNotAvailable, file: file, line: line)
        XCTAssertNil(result.handle, file: file, line: line)
    }
    func read(_ handle: NativeTextHandle, maximum: Int32 = -1) -> NativeTextResult {
        UIANativeActorEntry.withScope { handle.read(maximum: maximum) }
    }
    func assertUnavailable(_ handle: NativeTextHandle, file: StaticString = #filePath, line: UInt = #line) {
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
        callbacks.releaseHeldCall()
        bridge?.revokeNativeRequests()
        _ = attachment?.detach()
        if let provider { SWU_UIAReleaseProvider(provider) }
        provider = nil
        if let rootProvider { SWU_UIAReleaseProvider(rootProvider) }
        rootProvider = nil
        attachment = nil
        bridge = nil
        if let registryContext { NativeTextCallbackRegistry.remove(registryContext) }
        registryContext = nil
    }
}

@MainActor
private final class NativeTextLegacySource: UIAElementTreeSource {
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
