import CUIAInterop
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public List data is discovered through the actual COM ItemContainer route.
/// These tests use no HWND, desktop capture, input injection, or UIA client.
@MainActor
final class PublicLazyListAccessibilityTests: XCTestCase {
    func testLogicalEnumerationDoesNotConstructRowsOrInventProperties() async throws {
        let fixture = try PublicLazyListAccessibilityFixture()
        defer { fixture.close() }
        let factoryCalls = fixture.probe.factoryCalls
        XCTAssertLessThan(factoryCalls.count, 128)
        XCTAssertFalse(factoryCalls.contains(300))
        let row = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(row) }

        XCTAssertEqual(fixture.probe.factoryCalls, factoryCalls)
        XCTAssertEqual(
            fixture.source.logicalItemReceiptCount, RuntimeUIAElementTreeSource.logicalItemReceiptLimit)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, 301)
        XCTAssertLessThan(fixture.source.uiaElementSnapshots().count, 512)
        XCTAssertEqual(try fixture.runtimeID(row).count, 3)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: try fixture.elementID(row)), .placeholder)

        var name: UnsafeMutablePointer<UInt16>?
        XCTAssertEqual(SWU_UIAProviderGetNameResult(row, &name), publicLazyListElementUnavailable)
        XCTAssertNil(name, "An unknown row name must not be reported as an empty actual name")
        var left = 99.0
        var top = 99.0
        var width = 99.0
        var height = 99.0
        XCTAssertEqual(
            SWU_UIAProviderGetBoundingRectangleResult(row, &left, &top, &width, &height),
            publicLazyListElementUnavailable)
        XCTAssertEqual([left, top, width, height], [0, 0, 0, 0])
        var hasValue: Int32 = 0
        XCTAssertEqual(SWU_UIAProviderGetBoolProperty(row, Int32(SWU_UIA_BOOL_IS_OFFSCREEN), &hasValue), 1)
        XCTAssertEqual(hasValue, 1)
        XCTAssertNil(SWU_UIAProviderGetInvokePattern(row))
        XCTAssertNil(SWU_UIAProviderGetValuePattern(row))
        XCTAssertNil(SWU_UIAProviderGetSelectionItemPattern(row))
        let virtual = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
        defer { SWU_UIAReleaseProvider(virtual) }
        XCTAssertEqual(fixture.probe.factoryCalls, factoryCalls)
    }

    func testRealizeAdoptsAndLaysOutTheActualActionTarget() async throws {
        let fixture = try PublicLazyListAccessibilityFixture()
        defer { fixture.close() }
        let row = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(row) }
        let identity = try fixture.runtimeID(row)
        let elementID = try fixture.elementID(row)
        let virtual = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
        defer { SWU_UIAReleaseProvider(virtual) }
        let before = fixture.probe.factoryCalls.count

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtual), 0)

        XCTAssertTrue(fixture.probe.factoryCalls.contains(300))
        XCTAssertLessThan(fixture.probe.factoryCalls.count - before, 128)
        XCTAssertEqual(try fixture.runtimeID(row), identity)
        XCTAssertEqual(try fixture.name(row), "Row 300")
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .ordinary)
        XCTAssertEqual(fixture.source.uiaElementSnapshots().first(where: { $0.id == elementID })?.name, "Row 300")
        XCTAssertFalse(fixture.host.runtime.hasPendingLayout)
        var left = 0.0
        var top = 0.0
        var width = 0.0
        var height = 0.0
        XCTAssertEqual(SWU_UIAProviderGetBoundingRectangleResult(row, &left, &top, &width, &height), 0)
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        XCTAssertLessThan(top, fixture.host.runtime.root.frame.height)
        XCTAssertGreaterThan(top + height, 0)
        var hasValue: Int32 = 0
        XCTAssertEqual(SWU_UIAProviderGetBoolProperty(row, Int32(SWU_UIA_BOOL_IS_OFFSCREEN), &hasValue), 0)
        XCTAssertEqual(hasValue, 1)
        XCTAssertNil(SWU_UIAProviderGetVirtualizedItemPattern(row))

        let action = try XCTUnwrap(SWU_UIAProviderGetInvokePattern(row))
        defer { SWU_UIAReleaseProvider(action) }
        XCTAssertEqual(SWU_UIAProviderInvokeResult(action), 0)
        XCTAssertEqual(fixture.probe.activations, [300])
        XCTAssertEqual(SWU_UIAProviderSetFocusResult(row), 0)
        XCTAssertNotNil(fixture.host.runtime.focusedNode)
    }

    func testUnsupportedSearchesAndForeignStartsDoNotEvaluateDataViews() async throws {
        let fixture = try PublicLazyListAccessibilityFixture()
        defer { fixture.close() }
        let other = try PublicLazyListAccessibilityFixture(rowCount: 1_000)
        defer { other.close() }
        let before = fixture.probe.factoryCalls
        let query = Array("Row 49999".utf16)
        for property in [SWU_UIA_ITEM_PROPERTY_NAME, SWU_UIA_ITEM_PROPERTY_AUTOMATION_ID] {
            var found: UnsafeMutableRawPointer?
            let result = query.withUnsafeBufferPointer { buffer in
                SWU_UIAItemContainerProviderFindItemResult(
                    fixture.itemContainer, nil, Int32(property), buffer.baseAddress, Int32(buffer.count), &found)
            }
            XCTAssertEqual(result, publicLazyListNotImplemented)
            XCTAssertNil(found)
        }
        var foreign: UnsafeMutableRawPointer?
        XCTAssertEqual(
            SWU_UIAItemContainerProviderFindItemResult(
                fixture.itemContainer, other.rootProvider, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &foreign),
            publicLazyListInvalidArgument)
        XCTAssertNil(foreign)
        XCTAssertEqual(fixture.probe.factoryCalls, before)
        XCTAssertEqual(fixture.source.logicalItemReceiptCount, 0)
    }

    func testLogicalIDsSurviveReceiptEvictionWithoutRetainingRows() async throws {
        let fixture = try PublicLazyListAccessibilityFixture()
        defer { fixture.close() }
        let row = try fixture.item(at: 100)
        defer { SWU_UIAReleaseProvider(row) }
        let virtual = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
        defer { SWU_UIAReleaseProvider(virtual) }
        let identity = try fixture.runtimeID(row)
        let before = fixture.probe.factoryCalls
        let recent = try fixture.item(at: 400)
        defer { SWU_UIAReleaseProvider(recent) }

        XCTAssertEqual(fixture.probe.factoryCalls, before)
        XCTAssertLessThanOrEqual(
            fixture.source.logicalItemReceiptCount, RuntimeUIAElementTreeSource.logicalItemReceiptLimit)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, 401)
        XCTAssertEqual(try fixture.runtimeID(row), identity)
        let next = try fixture.next(after: row)
        defer { SWU_UIAReleaseProvider(next) }
        XCTAssertEqual(fixture.probe.factoryCalls, before)
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtual), 0)
        XCTAssertEqual(try fixture.name(row), "Row 100")
        XCTAssertEqual(try fixture.runtimeID(row), identity)
        XCTAssertLessThan(fixture.probe.factoryCalls.count - before.count, 128)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testDeletedAndReinsertedKeysCannotReviveEscapedLogicalProviders() async throws {
        let fixture = try PublicLazyListAccessibilityFixture()
        defer { fixture.close() }
        let old = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(old) }
        let oldIdentity = try fixture.runtimeID(old)
        let virtual = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(old))
        defer { SWU_UIAReleaseProvider(virtual) }

        fixture.probe.rows.removeAll { $0 == 300 }
        fixture.host.reload()
        XCTAssertNotNil(fixture.host.layout())
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtual), publicLazyListElementUnavailable)

        fixture.probe.rows.insert(300, at: 300)
        fixture.host.reload()
        XCTAssertNotNil(fixture.host.layout())
        try fixture.refreshItemContainer()
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtual), publicLazyListElementUnavailable)
        let replacement = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(replacement) }
        XCTAssertNotEqual(try fixture.runtimeID(replacement), oldIdentity)
        XCTAssertFalse(fixture.probe.factoryCalls.contains(300))
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testAcceptedReorderPreservesLogicalIDWithoutRevivingTheOldPhysicalReceipt() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let originalIdentity = try fixture.runtimeID(original)
        let virtual = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(virtual) }
        let container = try fixture.host.list()
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: container))
        let metadata = try XCTUnwrap(source.row(at: 300))
        let oldAttachment = try XCTUnwrap(
            fixture.host.runtime.lazyListTarget(in: container, key: metadata.providerKey))

        let identityCount = fixture.source.logicalItemIdentityCount
        fixture.probe.rows.swapAt(300, 310)
        fixture.host.reload()
        XCTAssertTrue(fixture.host.runtime.isLazyListAccessibilityContainerCurrent(oldAttachment))
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: oldAttachment))
        // UIA synchronizes before its projection settles the newly accepted
        // adapter. Missing prepared metadata must not revoke live membership.
        _ = fixture.source.uiaElementSnapshots()
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, identityCount)
        XCTAssertNotNil(fixture.host.layout())

        XCTAssertFalse(fixture.host.runtime.isLazyListAccessibilityItemCurrent(oldAttachment))
        XCTAssertNil(fixture.host.runtime.realizedLazyListAccessibilityNodes(for: oldAttachment))
        XCTAssertFalse(fixture.probe.factoryCalls.contains(300))
        let afterRebuild = fixture.probe.factoryCalls
        try fixture.refreshItemContainer()
        let current = try fixture.item(at: 310)
        defer { SWU_UIAReleaseProvider(current) }
        XCTAssertEqual(try fixture.runtimeID(current), originalIdentity)
        XCTAssertEqual(try fixture.runtimeID(original), originalIdentity)
        XCTAssertEqual(fixture.probe.factoryCalls, afterRebuild)

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(virtual), 0)
        XCTAssertEqual(try fixture.name(original), "Row 300")
        XCTAssertEqual(try fixture.runtimeID(original), originalIdentity)
        XCTAssertFalse(fixture.host.runtime.isLazyListAccessibilityItemCurrent(oldAttachment))
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testRuntimeIDAndRealizeCanBeTheFirstQueriesAfterAcceptedReplacement() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let identity = try fixture.runtimeID(original)
        let elementID = try fixture.elementID(original)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(pattern) }
        let witness = try XCTUnwrap(
            fixture.host.runtime.lazyListAccessibilityItem(in: try fixture.host.list()))

        fixture.host.reload()
        XCTAssertTrue(fixture.host.runtime.isLazyListAccessibilityContainerCurrent(witness))
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness))
        let factories = fixture.probe.factoryCalls
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .placeholder)
        XCTAssertEqual(try fixture.runtimeID(original), identity)
        XCTAssertEqual(fixture.probe.factoryCalls, factories, "Scalar membership must never prepare row factories")
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness))

        // There has been no projection or external layout since reload.
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), 0)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .ordinary)
        XCTAssertEqual(try fixture.name(original), "Row 300")
        XCTAssertEqual(try fixture.runtimeID(original), identity)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .ordinary)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testDeletedTokenDoesNotBorrowPendingSuccessorMembershipForRuntimeIDOrRealize() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let elementID = try fixture.elementID(original)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(pattern) }
        let witness = try XCTUnwrap(
            fixture.host.runtime.lazyListAccessibilityItem(in: try fixture.host.list()))

        fixture.probe.rows.removeAll { $0 == 300 }
        fixture.host.reload()
        XCTAssertTrue(fixture.host.runtime.isLazyListAccessibilityContainerCurrent(witness))
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: witness))
        let factories = fixture.probe.factoryCalls
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .unavailable)
        var values = [Int32](repeating: 0, count: 8)
        var count: Int32 = 0
        let result = values.withUnsafeMutableBufferPointer { buffer in
            SWU_UIAProviderGetRuntimeIdResult(original, buffer.baseAddress, Int32(buffer.count), &count)
        }
        XCTAssertEqual(result, publicLazyListElementUnavailable)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), publicLazyListElementUnavailable)
        XCTAssertEqual(fixture.probe.factoryCalls, factories)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testFirstRealizeAfterReplacementCannotRechargeItsPreparationBudget() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let elementID = try fixture.elementID(original)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(pattern) }
        XCTAssertTrue(fixture.host.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        fixture.host.reload()
        let factories = fixture.probe.factoryCalls.count
        let identities = fixture.source.logicalItemIdentityCount

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), publicLazyListInvalidOperation)
        XCTAssertEqual(fixture.probe.factoryCalls.count - factories, 1)
        XCTAssertEqual(fixture.host.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, identities)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .placeholder)
        XCTAssertFalse(fixture.probe.factoryCalls.contains(300))
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testFailedRepeatRealizeKeepsAnAlreadyProjectedRowsOrdinaryProperties() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let elementID = try fixture.elementID(original)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(pattern) }
        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), 0)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .ordinary)
        let row = try XCTUnwrap(fixture.host.find("public.row.300.first"))
        let container = try fixture.host.list()
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: container))
        let metadata = try XCTUnwrap(source.row(at: 301))
        let competing = try XCTUnwrap(fixture.host.runtime.lazyListTarget(in: container, key: metadata.providerKey))
        defer { fixture.host.runtime.releaseLazyListTarget(competing) }
        guard case .ready(let roots) = fixture.host.runtime.resolveLazyListTarget(competing) else {
            return XCTFail("The adjacent current row must hold the competing realization demand")
        }
        XCTAssertFalse(roots.isEmpty)

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), publicLazyListInvalidOperation)
        XCTAssertTrue(fixture.host.contains(row))
        // This scalar query must succeed before Name is allowed to reproject.
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .ordinary)
        XCTAssertEqual(try fixture.name(original), "Row 300")
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testAuthoredSameValueScrollDuringPreparationCancelsTheOriginalRealize() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let elementID = try fixture.elementID(original)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(pattern) }
        let scroll = try fixture.host.scrollContainer()
        let originalOffset = scroll.scrollOffset
        fixture.host.reload()
        var intervened = false
        fixture.probe.onFactory = { _ in
            guard !intervened else { return }
            intervened = true
            // Even an equal offset is a newer authored intent, not one of the
            // framework's permitted prefix/viewport anchor corrections.
            let offset = scroll.scrollOffset
            scroll.scrollOffset = offset
        }

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), publicLazyListInvalidOperation)
        fixture.probe.onFactory = nil
        XCTAssertTrue(intervened, "The regression must reach an authored row boundary during preparation")
        XCTAssertEqual(scroll.scrollOffset, originalOffset)
        XCTAssertFalse(fixture.probe.factoryCalls.contains(300))
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .placeholder)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testAcceptedPrefixAnchorCorrectionCanPrepareAFirstLogicalRealize() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let initialThird = try fixture.host.rowRoot("public.row.3.first")
        try fixture.host.scroll(to: initialThird.resolvedFrame.minY + 2)
        let predecessor = try fixture.host.rowRoot("public.row.2.first")
        let replacementHeight = predecessor.resolvedFrame.height + 40
        XCTAssertGreaterThan(replacementHeight, 40, "The changed predecessor must be measured in upper prefetch")
        let third = try fixture.host.rowRoot("public.row.3.first")
        let scroll = try fixture.host.scrollContainer()
        let beforeOffset = scroll.scrollOffset
        let beforeTop = third.resolvedFrame.minY - scroll.resolvedScrollOffset
        let container = try fixture.host.list()
        let source = try XCTUnwrap(DeferredListScrollSource.attached(to: container))
        let metadata = try XCTUnwrap(source.row(at: 300))
        let original = try XCTUnwrap(fixture.host.runtime.lazyListTarget(in: container, key: metadata.providerKey))
        fixture.probe.heights[2] = replacementHeight
        fixture.host.reload()
        XCTAssertNil(fixture.host.runtime.lazyListAccessibilityGeneration(for: original))
        let mutation = try XCTUnwrap(fixture.host.runtime.beginAccessibilityMutation())
        defer { fixture.host.runtime.endAccessibilityMutation(mutation) }

        let prepared = fixture.host.runtime.withLazyListResolutionBudget {
            fixture.host.runtime.prepareLazyListAccessibilityTarget(
                token: original.token, in: original, during: mutation)
        }
        let current = try XCTUnwrap(prepared)
        XCTAssertEqual(current.token, original.token)
        XCTAssertTrue(fixture.host.runtime.isLazyListAccessibilityItemCurrent(current))
        XCTAssertFalse(fixture.host.runtime.isLazyListAccessibilityItemCurrent(original))
        XCTAssertEqual(scroll.scrollOffset, beforeOffset + 40, accuracy: 0.001)
        XCTAssertEqual(
            try fixture.host.rowRoot("public.row.2.first").resolvedFrame.height, replacementHeight, accuracy: 0.001)
        let currentThird = try fixture.host.rowRoot("public.row.3.first")
        XCTAssertEqual(
            currentThird.resolvedFrame.minY - scroll.resolvedScrollOffset, beforeTop, accuracy: 0.001)
        XCTAssertFalse(fixture.probe.factoryCalls.contains(300), "Preparation only settles the original viewport")
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testSuccessorDuringPreparationCannotCorrectTheSameScrollOwnersAnchor() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(rowCount: 1000)
        defer { fixture.close() }
        let initialThird = try fixture.host.rowRoot("public.row.3.first")
        try fixture.host.scroll(to: initialThird.resolvedFrame.minY + 2)
        let predecessor = try fixture.host.rowRoot("public.row.2.first")
        let replacementHeight = predecessor.resolvedFrame.height + 40
        let original = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(original) }
        let elementID = try fixture.elementID(original)
        let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(original))
        defer { SWU_UIAReleaseProvider(pattern) }
        let scroll = try fixture.host.scrollContainer()
        let originalOffset = scroll.scrollOffset
        fixture.probe.heights[2] = replacementHeight
        fixture.host.reload()
        let preparingAdapter = try XCTUnwrap(try fixture.host.list().retainedLazyListAdapter)
        var requestedReplacement = false
        var successor: RetainedLazyListRuntimeAdapter?
        var successorOffset: Double?
        var successorFactories: [Int] = []
        fixture.probe.onFactory = { [weak host = fixture.host] id in
            if successor != nil { successorFactories.append(id) }
            guard !requestedReplacement, let host else { return }
            requestedReplacement = true
            host.componentHost.reload(onCompleted: { [weak host] in
                guard let host, let list = try? host.list() else {
                    return XCTFail("The queued root replacement must complete inside the original preparation")
                }
                successor = list.retainedLazyListAdapter
                XCTAssertTrue((try? host.scrollContainer()) === scroll)
                let offset = scroll.scrollOffset
                scroll.scrollOffset = offset
                successorOffset = offset
            })
        }

        XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), publicLazyListInvalidOperation)
        fixture.probe.onFactory = nil
        XCTAssertTrue(requestedReplacement)
        let acceptedSuccessor = try XCTUnwrap(successor)
        XCTAssertFalse(acceptedSuccessor === preparingAdapter)
        XCTAssertTrue(try fixture.host.list().retainedLazyListAdapter === acceptedSuccessor)
        XCTAssertEqual(try XCTUnwrap(successorOffset), originalOffset, accuracy: 0.001)
        // Prove the successor had a changed, measured predecessor in this
        // query; no later layout is allowed to manufacture that opportunity.
        XCTAssertTrue(successorFactories.contains(2))
        XCTAssertEqual(
            try fixture.host.rowRoot("public.row.2.first").resolvedFrame.height, replacementHeight, accuracy: 0.001)
        XCTAssertEqual(scroll.scrollOffset, originalOffset, accuracy: 0.001)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: elementID), .placeholder)
        XCTAssertFalse(fixture.probe.factoryCalls.contains(300))
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testZeroAndMultipleLeavesKeepLogicalEnumerationHonest() async throws {
        let fixture = try PublicLazyListAccessibilityFixture(emptyRows: [300], multipleRows: [301])
        defer { fixture.close() }
        let empty = try fixture.item(at: 300)
        defer { SWU_UIAReleaseProvider(empty) }
        let emptyPattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(empty))
        defer { SWU_UIAReleaseProvider(emptyPattern) }

        XCTAssertLessThan(SWU_UIAVirtualizedItemProviderRealizeResult(emptyPattern), 0)
        XCTAssertTrue(fixture.probe.factoryCalls.contains(300))
        let measuredEmptyCalls = fixture.probe.factoryCalls
        XCTAssertLessThan(SWU_UIAVirtualizedItemProviderRealizeResult(emptyPattern), 0)
        XCTAssertEqual(fixture.probe.factoryCalls, measuredEmptyCalls, "Known empty output must not be rebuilt")
        var name: UnsafeMutablePointer<UInt16>?
        XCTAssertEqual(SWU_UIAProviderGetNameResult(empty, &name), publicLazyListElementUnavailable)
        XCTAssertNil(name)
        let multiple = try fixture.next(after: empty)
        defer { SWU_UIAReleaseProvider(multiple) }
        if let pattern = SWU_UIAProviderGetVirtualizedItemPattern(multiple) {
            defer { SWU_UIAReleaseProvider(pattern) }
            XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), 0)
        }
        XCTAssertEqual(try fixture.name(multiple), "Row 301")
        let snapshots = fixture.source.uiaElementSnapshots()
        let tail = try XCTUnwrap(snapshots.first { $0.automationID == "public.row.301.tail" })
        XCTAssertEqual(tail.name, "Tail 301")
        XCTAssertNotEqual(tail.id, try fixture.elementID(multiple))
        XCTAssertFalse(snapshots.contains { $0.automationID == "public.row.300.first" })
        XCTAssertLessThan(fixture.probe.factoryCalls.count, 128)
    }

    func testClosedHostAndCloseDuringConstructionRejectLogicalRealization() async throws {
        for closeInsideFactory in [false, true] {
            let fixture = try PublicLazyListAccessibilityFixture()
            defer { fixture.close() }
            let row = try fixture.item(at: 300)
            defer { SWU_UIAReleaseProvider(row) }
            let pattern = try XCTUnwrap(SWU_UIAProviderGetVirtualizedItemPattern(row))
            defer { SWU_UIAReleaseProvider(pattern) }
            if closeInsideFactory {
                fixture.probe.onFactory = { [weak host = fixture.host] id in
                    if id == 300 { host?.close() }
                }
            } else {
                fixture.host.close()
            }

            XCTAssertEqual(SWU_UIAVirtualizedItemProviderRealizeResult(pattern), publicLazyListElementUnavailable)
            XCTAssertTrue(fixture.host.isClosed)
            XCTAssertNil(SWU_UIAProviderGetInvokePattern(row))
            XCTAssertTrue(fixture.probe.activations.isEmpty)
            XCTAssertTrue(fixture.host.runtime.root.children.isEmpty)
        }
    }
}

private let publicLazyListElementUnavailable = Int32(bitPattern: 0x8004_0201)
private let publicLazyListInvalidOperation = Int32(bitPattern: 0x8013_1509)
private let publicLazyListInvalidArgument = Int32(bitPattern: 0x8007_0057)
private let publicLazyListNotImplemented = Int32(bitPattern: 0x8000_4001)

@MainActor
private final class PublicLazyListAccessibilityProbe {
    var rows: [Int]
    let emptyRows: Set<Int>
    let multipleRows: Set<Int>
    var factoryCalls: [Int] = []
    var heights: [Int: Double] = [:]
    var activations: [Int] = []
    var onFactory: ((Int) -> Void)?

    init(count: Int, emptyRows: Set<Int>, multipleRows: Set<Int>) {
        rows = Array(0..<count)
        self.emptyRows = emptyRows
        self.multipleRows = multipleRows
    }

    func makeRows(_ id: Int) -> [AnyView] {
        factoryCalls.append(id)
        onFactory?(id)
        guard !emptyRows.contains(id) else { return [] }
        var views = [
            AnyView(
                Button("Row \(id)") { [weak self] in self?.activations.append(id) }
                    .accessibilityIdentifier("public.row.\(id).first")
                    .frame(height: heights[id] ?? 24))
        ]
        if multipleRows.contains(id) {
            views.append(
                AnyView(
                    Text("Tail \(id)")
                        .accessibilityIdentifier("public.row.\(id).tail")
                        .frame(height: 32)))
        }
        return views
    }
}

@MainActor
private final class PublicLazyListAccessibilityFixture {
    let probe: PublicLazyListAccessibilityProbe
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let bridge: UIAProviderBridge
    private(set) var rootProvider: UnsafeMutableRawPointer?
    private(set) var itemContainer: UnsafeMutableRawPointer?

    init(rowCount: Int = 50_000, emptyRows: Set<Int> = [], multipleRows: Set<Int> = []) throws {
        let probe = PublicLazyListAccessibilityProbe(
            count: rowCount, emptyRows: emptyRows, multipleRows: multipleRows)
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { id in probe.makeRows(id) }.listStyle(.plain)
        }
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        bridge = UIAProviderBridge(source: source)
        XCTAssertNotNil(host.layout())
        rootProvider = try XCTUnwrap(bridge.retainedRootProviderForTesting())
        do {
            try refreshItemContainer()
        } catch {
            close()
            throw error
        }
    }

    func refreshItemContainer() throws {
        SWU_UIAReleaseProvider(itemContainer)
        itemContainer = nil
        itemContainer = try XCTUnwrap(findItemContainer(in: rootProvider))
    }

    func close() {
        probe.onFactory = nil
        host.close()
        SWU_UIAReleaseProvider(itemContainer)
        SWU_UIAReleaseProvider(rootProvider)
        itemContainer = nil
        rootProvider = nil
    }

    func next(after: UnsafeMutableRawPointer?) throws -> UnsafeMutableRawPointer {
        var result: UnsafeMutableRawPointer?
        XCTAssertEqual(
            SWU_UIAItemContainerProviderFindItemResult(
                itemContainer, after, Int32(SWU_UIA_ITEM_PROPERTY_ANY), nil, 0, &result), 0)
        return try XCTUnwrap(result)
    }

    func item(at index: Int) throws -> UnsafeMutableRawPointer {
        var current: UnsafeMutableRawPointer?
        for _ in 0...index {
            let previous = current
            current = nil
            defer { SWU_UIAReleaseProvider(previous) }
            current = try next(after: previous)
        }
        return try XCTUnwrap(current)
    }

    func runtimeID(_ provider: UnsafeMutableRawPointer) throws -> [Int32] {
        var values = [Int32](repeating: 0, count: 8)
        var count: Int32 = 0
        let result = values.withUnsafeMutableBufferPointer { buffer in
            SWU_UIAProviderGetRuntimeIdResult(provider, buffer.baseAddress, Int32(buffer.count), &count)
        }
        XCTAssertEqual(result, 0)
        XCTAssertGreaterThanOrEqual(count, 2)
        return Array(values.prefix(Int(max(0, count))))
    }

    func elementID(_ provider: UnsafeMutableRawPointer) throws -> UInt64 {
        let values = try runtimeID(provider)
        let low = UInt64(UInt32(bitPattern: try XCTUnwrap(values.dropFirst().first)))
        let high = values.count > 2 ? UInt64(UInt32(bitPattern: values[2])) << 32 : 0
        return high | low
    }

    func name(_ provider: UnsafeMutableRawPointer) throws -> String {
        var text: UnsafeMutablePointer<UInt16>?
        XCTAssertEqual(SWU_UIAProviderGetNameResult(provider, &text), 0)
        let value = try XCTUnwrap(text)
        defer { SWU_UIAFreeString(value) }
        return String(decodingCString: value, as: UTF16.self)
    }

    private func findItemContainer(in provider: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let provider else { return nil }
        if let pattern = SWU_UIAProviderGetItemContainerPattern(provider) { return pattern }
        var next = SWU_UIAProviderNavigate(provider, Int32(SWU_UIA_NAV_FIRST_CHILD))
        while let child = next {
            let pattern = findItemContainer(in: child)
            next = pattern == nil ? SWU_UIAProviderNavigate(child, Int32(SWU_UIA_NAV_NEXT_SIBLING)) : nil
            SWU_UIAReleaseProvider(child)
            if let pattern { return pattern }
        }
        return nil
    }
}
