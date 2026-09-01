import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Real managed Lists retire physical and executable ownership immediately.
/// Only the last normally painted values may survive for a removal transition.
/// These fixtures use the retained scene and CPU rasterizer, with no window,
/// native input, font rendering, or changes to ordinary transition semantics.
@MainActor
final class ManagedLazyListRemovalTransitionTests: XCTestCase {
    func testPublicListDeletionFadesPixelsAfterStateBindingAndInputAuthorityEnd() async throws {
        for builder in [false, true] {
            let probe = ManagedRemovalPaintProbe(count: 1)
            let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: builder) }
            defer {
                harness.host.close()
                probe.finish()
            }
            let initial = harness.render(at: 10)
            let node = try XCTUnwrap(harness.host.find(managedRemovalIdentifier(0)))
            let original = try XCTUnwrap(probe.captures[0])
            let point = managedRemovalCenter(try XCTUnwrap(harness.host.runtime.resolvedLayoutFrame(of: node)))
            let before = managedRemovalPixel(initial, at: point)
            XCTAssertGreaterThan(before.blueContrast, 230)
            original.value.wrappedValue = 41
            XCTAssertNotNil(harness.host.layout())
            _ = harness.render(at: 10)
            let attachment = node.captureLazyListAttachmentProof()
            let dialog = node.beginFileDialogPresentation(kind: .importer)
            let source = RuntimeUIAElementTreeSource(runtime: harness.host.runtime)
            let elementID = try XCTUnwrap(
                source.uiaElementSnapshots().first { $0.automationID == managedRemovalIdentifier(0) }?.id)
            XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: elementID))
            XCTAssertEqual(probe.activations[0], 1)
            harness.host.runtime.requestFocus(node)
            XCTAssertTrue(harness.host.runtime.focusedNode === node)
            harness.host.runtime.pointerDown(at: point)

            probe.rows = []
            harness.refresh {
                XCTAssertFalse(original.owner.isLive, "Accepted deletion retires State before viewport work")
            }

            assertRetired(original, lastValue: 41, in: harness.host)
            XCTAssertNil(harness.host.find(managedRemovalIdentifier(0)))
            XCTAssertFalse(attachment.isCurrent)
            XCTAssertFalse(dialog.isValid)
            XCTAssertFalse(node.hasAppeared)
            XCTAssertFalse(node.isRemovalOverlay)
            XCTAssertFalse(harness.host.runtime.focusedNode === node)
            XCTAssertEqual(probe.disappearances[0], 1)
            XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
            XCTAssertTrue(harness.host.runtime.transitionOverlays.isEmpty)
            // Query the saved ID first: a stale projection must not need an
            // explicit fresh snapshot before losing its old action authority.
            XCTAssertFalse(source.uiaInvokeDefaultAction(elementID: elementID))
            XCTAssertFalse(source.uiaSetValue(elementID: elementID, value: "retired"))
            source.uiaSetFocus(elementID: elementID)
            harness.host.runtime.pointerUp(at: point)
            XCTAssertEqual(probe.activations[0], 1)
            XCTAssertFalse(harness.host.runtime.focusedNode === node)
            XCTAssertNil(source.projectedElementID(forNodeOrAncestor: node))
            XCTAssertFalse(source.uiaElementSnapshots().contains { $0.id == elementID })

            let first = managedRemovalPixel(harness.render(at: 10), at: point)
            XCTAssertEqual(first.blueContrast, before.blueContrast, accuracy: 2)
            let samples = [10.25, 10.5, 10.75].map {
                managedRemovalPixel(harness.render(at: $0), at: point).blueContrast
            }
            XCTAssertEqual(Set(samples).count, 3, "The retired row must paint distinct intermediate frames")
            XCTAssertTrue(samples.allSatisfy { $0 > 5 && $0 < before.blueContrast - 5 })
            XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0 > $1 })
            let finished = managedRemovalPixel(harness.render(at: 11.01), at: point)
            XCTAssertEqual(finished, managedRemovalPlainListBackground)
            XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
            XCTAssertEqual(probe.disappearances[0], 1)
            assertRetired(original, lastValue: 41, in: harness.host)
        }
    }

    func testFrameOnlyRemovalPreservesFrozenOpacityThroughCachedFrameAndCompletion() async throws {
        let probe = ManagedRemovalPaintProbe(count: 1)
        let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: false) }
        defer {
            harness.host.close()
            probe.finish()
        }
        // No renderScene call may seed the capture for this fixture.
        let initial = harness.renderFrame(at: 10)
        let point = try managedRemovalPoint(0, in: harness.host)
        let original = try XCTUnwrap(probe.captures[0])
        let lifetime = try managedRemovalPhysicalLifetime(0, in: harness.host)
        let before = managedRemovalPixel(initial, at: point).blueContrast
        XCTAssertGreaterThan(before, 230)

        probe.rows = []
        harness.refresh()
        let first = harness.renderFrame(at: 10)

        assertRetired(original, lastValue: 100, in: harness.host)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        XCTAssertTrue(harness.host.runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(harness.host.runtime.hasActiveAnimations)
        XCTAssertFalse(lifetime.attachment.isCurrent)
        XCTAssertTrue(lifetime.descendants.allSatisfy { $0.value == nil })
        XCTAssertEqual(managedRemovalPixel(first, at: point).blueContrast, before, accuracy: 2)
        let middle = harness.renderFrame(at: 10.5)
        let halfway = managedRemovalPixel(middle, at: point).blueContrast
        XCTAssertGreaterThan(halfway, 20)
        XCTAssertLessThan(halfway, before - 20)
        XCTAssertFalse(harness.host.runtime.isDirty)
        let revision = harness.host.runtime.contentRevision

        // Do not tick again: that would dirty the runtime and accidentally
        // test fresh painting instead of the cached-frame early return.
        let cached = GPUIRawSceneRasterizer.rasterize(
            harness.host.runtime.renderFrame(at: 10.5), size: harness.size)

        XCTAssertEqual(harness.host.runtime.contentRevision, revision)
        XCTAssertEqual(harness.host.runtime.lastFrameReplayCount, 0)
        XCTAssertEqual(cached, middle)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        let completed = harness.renderFrame(at: 11.01)
        XCTAssertEqual(managedRemovalPixel(completed, at: point), managedRemovalPlainListBackground)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
        XCTAssertEqual(probe.disappearances[0], 1)
        XCTAssertFalse(harness.host.runtime.isDirty)
        let completedRevision = harness.host.runtime.contentRevision
        let cachedCompleted = GPUIRawSceneRasterizer.rasterize(
            harness.host.runtime.renderFrame(at: 11.01), size: harness.size)
        XCTAssertEqual(cachedCompleted, completed)
        XCTAssertEqual(harness.host.runtime.contentRevision, completedRevision)
        XCTAssertEqual(probe.disappearances[0], 1)
    }

    func testManagedTabCrossfadeKeepsDeclaredStateAndDoesNotRestartOnRebuild() async throws {
        let probe = ManagedRemovalPaintProbe(count: 1)
        let harness = ManagedRemovalPaintHarness(size: IntSize(width: 320, height: 160)) {
            managedRemovalTabs(probe)
        }
        defer {
            harness.host.close()
            probe.finish()
        }
        _ = harness.render(at: 10)
        let originalNode = try XCTUnwrap(harness.host.find(managedRemovalIdentifier(0)))
        let original = try XCTUnwrap(probe.captures[0])
        original.value.wrappedValue = 41
        XCTAssertNotNil(harness.host.layout())
        let initial = harness.render(at: 10)
        let point = managedRemovalCenter(try XCTUnwrap(harness.host.runtime.resolvedLayoutFrame(of: originalNode)))
        XCTAssertGreaterThan(managedRemovalPixel(initial, at: point).blue, 230)
        let attachment = originalNode.captureLazyListAttachmentProof()

        probe.selection = 1
        harness.refresh()

        XCTAssertNil(harness.host.find(managedRemovalIdentifier(0)))
        XCTAssertFalse(attachment.isCurrent)
        XCTAssertTrue(original.owner.isLive, "Selection changes retain the still-declared inactive owner")
        XCTAssertTrue(harness.host.coordinator.registry.owner(at: original.owner.identity) === original.owner)
        XCTAssertEqual(original.value.wrappedValue, 41)
        XCTAssertFalse(originalNode.isRemovalOverlay)
        XCTAssertEqual(probe.disappearances[0], 1)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        XCTAssertTrue(harness.host.runtime.transitionOverlays.isEmpty)
        let incoming = try XCTUnwrap(harness.host.nodes.first { $0.nodeTag == "tabview-page:1" })
        let fade = try XCTUnwrap(incoming.animationStates[.opacity])
        XCTAssertEqual(incoming.opacity, 0, accuracy: 0.001)
        let midpoint = fade.startTime + fade.duration / 2
        let middle = harness.render(at: midpoint)
        let pixel = managedRemovalPixel(middle, at: point)
        XCTAssertGreaterThan(pixel.blue, 20, "The outgoing page remains visible")
        XCTAssertGreaterThan(pixel.red, 20, "The incoming page is already visible")
        XCTAssertGreaterThan(incoming.opacity, 0.05)
        XCTAssertLessThan(incoming.opacity, 0.95)
        let progress = incoming.opacity

        harness.host.reload()
        XCTAssertNotNil(harness.host.layout())
        let rebuilt = harness.render(at: midpoint)

        XCTAssertTrue(harness.host.nodes.first { $0.nodeTag == "tabview-page:1" } === incoming)
        XCTAssertEqual(incoming.opacity, progress, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(incoming.animationStates[.opacity]).startTime, fade.startTime)
        XCTAssertEqual(managedRemovalPixel(rebuilt, at: point), pixel)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        let finished = harness.render(at: fade.startTime + fade.duration + 0.01)
        XCTAssertGreaterThan(managedRemovalPixel(finished, at: point).red, 230)
        XCTAssertLessThan(managedRemovalPixel(finished, at: point).blue, 5)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
        XCTAssertEqual(probe.disappearances[0], 1)

        probe.selection = 0
        harness.refresh()
        let returned = try XCTUnwrap(probe.captures[0])
        let returnedNode = try XCTUnwrap(harness.host.find(managedRemovalIdentifier(0)))
        XCTAssertFalse(returnedNode === originalNode)
        XCTAssertTrue(returned.owner === original.owner)
        XCTAssertEqual(returned.owner.generation, original.owner.generation)
        XCTAssertTrue(returned.model === original.model)
        XCTAssertEqual(returned.value.wrappedValue, 41)
        XCTAssertFalse(attachment.isCurrent)
        try harness.host.assertCommittedDescriptor()
    }

    func testRemovalDuringInsertionUsesPresentedOpacityAndCannotCancelReinsertedRow() async throws {
        let probe = ManagedRemovalPaintProbe(count: 0)
        probe.transition = .opacity
        probe.runsTasks = true
        let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: true) }
        defer {
            harness.host.close()
            probe.finish()
        }
        _ = harness.render(at: 10)
        probe.rows = [ManagedRemovalPaintData(id: 0, seed: 100)]
        harness.refresh()
        let originalNode = try XCTUnwrap(harness.host.find(managedRemovalIdentifier(0)))
        let original = try XCTUnwrap(probe.captures[0])
        let insertion = try XCTUnwrap(originalNode.animationStates[.opacity])
        let firstStarted = expectation(description: "Inserted row installed its task cancellation handler")
        probe.tasks.onStart = { if $0 == 0 { firstStarted.fulfill() } }
        _ = harness.render(at: insertion.startTime)
        await fulfillment(of: [firstStarted], timeout: 5)
        probe.tasks.onStart = nil
        let removalTime = insertion.startTime + insertion.duration / 2
        let before = harness.render(at: removalTime)
        let point = managedRemovalCenter(try XCTUnwrap(harness.host.runtime.resolvedLayoutFrame(of: originalNode)))
        let presented = managedRemovalPixel(before, at: point).blueContrast
        XCTAssertGreaterThan(presented, 20)
        XCTAssertLessThan(presented, 235)
        let attachment = originalNode.captureLazyListAttachmentProof()
        let cancelled = expectation(description: "Removal cancels its physical task before the fade finishes")
        probe.tasks.onCancel = { if $0 == 0 { cancelled.fulfill() } }

        probe.rows = []
        harness.refresh()
        let removed = harness.render(at: removalTime)

        XCTAssertEqual(managedRemovalPixel(removed, at: point).blueContrast, presented, accuracy: 2)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        XCTAssertFalse(attachment.isCurrent)
        assertRetired(original, lastValue: 100, in: harness.host)
        await fulfillment(of: [cancelled], timeout: 5)
        probe.tasks.onCancel = nil
        XCTAssertEqual(probe.tasks.cancellations, [0])
        XCTAssertEqual(harness.clock.now, removalTime, "Task cleanup cannot require advancing the fade clock")

        probe.rows = [ManagedRemovalPaintData(id: 0, seed: 900)]
        harness.refresh()
        let replacementNode = try XCTUnwrap(harness.host.find(managedRemovalIdentifier(0)))
        let replacement = try XCTUnwrap(probe.captures[0])
        let replacementFade = try XCTUnwrap(replacementNode.animationStates[.opacity])
        XCTAssertFalse(replacementNode === originalNode)
        XCTAssertFalse(replacement.owner === original.owner)
        XCTAssertNotEqual(replacement.owner.generation, original.owner.generation)
        XCTAssertFalse(replacement.model === original.model)
        XCTAssertEqual(replacement.value.wrappedValue, 900)
        let replacementStarted = expectation(description: "Replacement row starts its own physical task")
        probe.tasks.onStart = { if $0 == 0 { replacementStarted.fulfill() } }
        _ = harness.render(at: removalTime)
        await fulfillment(of: [replacementStarted], timeout: 5)
        probe.tasks.onStart = nil

        let completion = max(removalTime + 1, replacementFade.startTime + replacementFade.duration) + 0.01
        _ = harness.render(at: completion)

        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
        XCTAssertTrue(harness.host.find(managedRemovalIdentifier(0)) === replacementNode)
        XCTAssertTrue(replacementNode.hasAppeared)
        XCTAssertTrue(replacement.owner.isLive)
        XCTAssertEqual(replacement.value.wrappedValue, 900)
        XCTAssertEqual(probe.disappearances[0], 1)
        XCTAssertEqual(probe.tasks.starts, [0, 0])
        XCTAssertEqual(probe.tasks.cancellations, [0])
        assertRetired(original, lastValue: 100, in: harness.host)
    }

    func testCloseDuringCleanupOrActiveFadeDrainsExactlyOnceWithoutKeepingPaint() async throws {
        for closeDuringCleanup in [false, true] {
            let probe = ManagedRemovalPaintProbe(count: 2)
            let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: true) }
            defer {
                probe.onDisappear = nil
                harness.host.close()
                probe.finish()
            }
            _ = harness.render(at: 10)
            let originals = try [0, 1].map { try XCTUnwrap(probe.captures[$0]) }
            let nodes = try [0, 1].map { try XCTUnwrap(harness.host.find(managedRemovalIdentifier($0))) }
            let attachments = nodes.map { $0.captureLazyListAttachmentProof() }
            var callbackSnapshots: [[Bool]] = []
            probe.onDisappear = { row in
                guard row == 0 else { return }
                callbackSnapshots.append([
                    originals.allSatisfy { !$0.owner.isLive },
                    attachments.allSatisfy { !$0.isCurrent },
                    nodes.allSatisfy { !$0.hasAppeared },
                ])
                if closeDuringCleanup { harness.host.close() }
            }
            probe.rows = [ManagedRemovalPaintData(id: 2, seed: 200)]

            withAnimation(.linear(duration: 1)) {
                harness.host.reload()
                _ = harness.host.layout()
            }
            XCTAssertEqual(callbackSnapshots, [[true, true, true]])
            if !closeDuringCleanup {
                XCTAssertGreaterThan(harness.host.runtime.retiredLazyListPaintCount, 0)
                _ = harness.render(at: 10.5)
                harness.host.close()
            }

            XCTAssertTrue(harness.host.isClosed)
            XCTAssertFalse(harness.host.runtime.permitsRetainedActionInvocation)
            XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
            XCTAssertTrue(harness.host.runtime.transitionOverlays.isEmpty)
            XCTAssertEqual(probe.disappearances[0], 1)
            XCTAssertEqual(probe.disappearances[1], 1)
            if closeDuringCleanup { XCTAssertEqual(probe.appearances[2, default: 0], 0) }
            XCTAssertTrue(originals.allSatisfy { !$0.owner.isLive })
            XCTAssertTrue(attachments.allSatisfy { !$0.isCurrent })
            let disappearances = probe.disappearances
            let completions = harness.host.events.rootCompletions

            harness.host.close()
            _ = harness.render(at: 20)
            _ = harness.render(at: 21)

            XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
            XCTAssertEqual(probe.disappearances, disappearances)
            XCTAssertEqual(harness.host.events.rootCompletions, completions)
        }
    }

    func testFixedClockReplacementChurnKeepsPaintBoundedAndReleasesOriginalNodes() async throws {
        let probe = ManagedRemovalPaintProbe(count: 1)
        let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: false) }
        defer {
            harness.host.close()
            probe.finish()
        }
        _ = harness.render(at: 10)
        let limit = RetainedViewRuntime.maximumRetiredLazyListPaintCount
        XCTAssertGreaterThan(limit, 0)
        var retired: [ManagedRemovalPhysicalLifetime] = []
        // These are distinct accepted replacements, not retries to converge a
        // failed layout. Keeping time fixed defeats deadline-only cleanup.
        for replacementID in 1...(limit + 5) {
            retired.append(try managedRemovalPhysicalLifetime(replacementID - 1, in: harness.host))
            probe.rows = [ManagedRemovalPaintData(id: replacementID, seed: replacementID)]
            harness.refresh()
            _ = harness.render(at: 10)

            XCTAssertNotNil(harness.host.find(managedRemovalIdentifier(replacementID)))
            XCTAssertGreaterThan(harness.host.runtime.retiredLazyListPaintCount, 0)
            XCTAssertLessThanOrEqual(harness.host.runtime.retiredLazyListPaintCount, limit)
            XCTAssertTrue(harness.host.runtime.transitionOverlays.isEmpty)
            XCTAssertTrue(retired.allSatisfy { !$0.attachment.isCurrent })
            XCTAssertTrue(retired.allSatisfy { $0.node.value == nil }, "Paint must not retain retired ViewNodes")
            XCTAssertTrue(retired.allSatisfy { $0.descendants.allSatisfy { $0.value == nil } })
            XCTAssertEqual(probe.disappearances[replacementID - 1], 1)
            try harness.host.assertCommittedDescriptor()
        }

        _ = harness.render(at: 11.01)

        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
        XCTAssertTrue(retired.allSatisfy { $0.node.value == nil })
        XCTAssertEqual(probe.disappearances.values.reduce(0, +), limit + 5)
    }

    func testViewportEvictionCancelsTaskWithoutCreatingPaintOrRetiringDeclaredState() async throws {
        let probe = ManagedRemovalPaintProbe(count: 1_000)
        probe.runsTasks = true
        let harness = ManagedRemovalPaintHarness { managedRemovalBoundedList(probe) }
        defer {
            harness.host.close()
            probe.finish()
        }
        let started = expectation(description: "Visible row task starts")
        probe.tasks.onStart = { if $0 == 0 { started.fulfill() } }
        _ = harness.render(at: 10)
        await fulfillment(of: [started], timeout: 5)
        probe.tasks.onStart = nil
        let original = try XCTUnwrap(probe.captures[0])
        let lifetime = try managedRemovalPhysicalLifetime(0, in: harness.host)
        let cancelled = expectation(description: "Viewport eviction cancels the physical task")
        probe.tasks.onCancel = { if $0 == 0 { cancelled.fulfill() } }

        try harness.host.scroll(to: 4_000)
        await fulfillment(of: [cancelled], timeout: 5)
        probe.tasks.onCancel = nil

        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
        XCTAssertTrue(harness.host.runtime.transitionOverlays.isEmpty)
        XCTAssertFalse(lifetime.attachment.isCurrent)
        XCTAssertNil(lifetime.node.value)
        XCTAssertTrue(lifetime.descendants.allSatisfy { $0.value == nil })
        XCTAssertTrue(original.owner.isLive)
        XCTAssertTrue(harness.host.coordinator.registry.owner(at: original.owner.identity) === original.owner)
        XCTAssertEqual(probe.tasks.starts.filter { $0 == 0 }.count, 1)
        XCTAssertEqual(probe.tasks.cancellations.filter { $0 == 0 }.count, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(try harness.host.list().retainedLazyListAdapter).mountedRecordCount, 8)
        original.value.wrappedValue = 41
        XCTAssertNotNil(harness.host.layout())
        XCTAssertNil(harness.host.find(managedRemovalIdentifier(0)))

        let returned = expectation(description: "Returning row starts a fresh physical task")
        probe.tasks.onStart = { if $0 == 0 { returned.fulfill() } }
        try harness.host.scroll(to: 0)
        _ = harness.render(at: 10)
        await fulfillment(of: [returned], timeout: 5)
        probe.tasks.onStart = nil

        let current = try XCTUnwrap(probe.captures[0])
        XCTAssertTrue(current.owner === original.owner)
        XCTAssertTrue(current.model === original.model)
        XCTAssertEqual(current.value.wrappedValue, 41)
        XCTAssertFalse(lifetime.attachment.isCurrent)
        XCTAssertEqual(probe.tasks.starts.filter { $0 == 0 }.count, 2)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
    }

    func testCanvasRemovalReplaysLastNormalPaintWithoutCallingRendererOrKeepingNodes() async throws {
        let probe = ManagedRemovalPaintProbe(count: 1)
        probe.usesCanvas = true
        let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: false) }
        defer {
            harness.host.close()
            probe.finish()
        }
        let initial = harness.render(at: 10)
        let lifetime = try managedRemovalPhysicalLifetime(0, in: harness.host)
        let point = try managedRemovalPoint(0, in: harness.host)
        let initialPixel = managedRemovalPixel(initial, at: point)
        XCTAssertGreaterThan(initialPixel.blueContrast, 230)
        let canvasCalls = probe.canvasCalls
        XCTAssertGreaterThan(canvasCalls, 0)
        let bodyCalls = probe.bodyCalls
        // The escaped Canvas closure would now draw red if removal or any
        // subsequent tick tried to repaint application content.
        probe.canvasColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        probe.rows = []

        harness.refresh()

        XCTAssertEqual(probe.canvasCalls, canvasCalls, "Removal may not enter the Canvas renderer")
        XCTAssertFalse(lifetime.attachment.isCurrent)
        XCTAssertNil(lifetime.node.value, "A captured paint record must not own the original row")
        XCTAssertTrue(lifetime.descendants.allSatisfy { $0.value == nil }, "Canvas descendants must release too")
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        let first = managedRemovalPixel(harness.render(at: 10), at: point)
        let middle = managedRemovalPixel(harness.render(at: 10.5), at: point)
        XCTAssertEqual(first.blueContrast, initialPixel.blueContrast, accuracy: 2)
        XCTAssertGreaterThan(middle.blueContrast, 20)
        XCTAssertLessThan(middle.blueContrast, first.blueContrast - 20)
        XCTAssertEqual(probe.canvasCalls, canvasCalls)
        XCTAssertEqual(probe.bodyCalls, bodyCalls)
        _ = harness.render(at: 11.01)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
        XCTAssertEqual(probe.canvasCalls, canvasCalls)
        XCTAssertNil(lifetime.node.value)
        XCTAssertEqual(probe.disappearances[0], 1)
    }

    func testOffsetRemovalMovesCapturedIndependentGeometryBeforeReleasingIt() async throws {
        let probe = ManagedRemovalPaintProbe(count: 1)
        probe.transition = .asymmetric(insertion: .identity, removal: .offset(x: 40, y: 0))
        let harness = ManagedRemovalPaintHarness { managedRemovalPublicList(probe, builder: false) }
        defer {
            harness.host.close()
            probe.finish()
        }
        let initial = harness.render(at: 10)
        let node = try XCTUnwrap(harness.host.find(managedRemovalIdentifier(0)))
        let frame = try XCTUnwrap(harness.host.runtime.resolvedLayoutFrame(of: node))
        let left = Point(x: frame.minX + 10, y: frame.minY + frame.height / 2)
        let right = Point(x: frame.maxX + 10, y: left.y)
        XCTAssertLessThan(right.x, Double(harness.size.width))
        XCTAssertGreaterThan(managedRemovalPixel(initial, at: left).blueContrast, 230)
        let background = managedRemovalPixel(initial, at: right)
        XCTAssertEqual(background, managedRemovalPlainListBackground)

        probe.rows = []
        harness.refresh()
        let first = harness.render(at: 10)
        let middle = harness.render(at: 10.5)

        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 1)
        XCTAssertGreaterThan(managedRemovalPixel(first, at: left).blueContrast, 230)
        XCTAssertEqual(managedRemovalPixel(middle, at: left), background)
        XCTAssertGreaterThan(managedRemovalPixel(middle, at: right).blueContrast, 230)
        XCTAssertFalse(node.hasAppeared)
        XCTAssertFalse(node.isRemovalOverlay)
        XCTAssertEqual(probe.disappearances[0], 1)
        let finished = harness.render(at: 11.01)
        XCTAssertEqual(managedRemovalPixel(finished, at: right), background)
        XCTAssertEqual(harness.host.runtime.retiredLazyListPaintCount, 0)
    }

    private func assertRetired(
        _ capture: ManagedRemovalPaintCapture, lastValue: Int, in host: MountedLazyListTestHost,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(capture.owner.isLive, file: file, line: line)
        XCTAssertFalse(
            host.coordinator.registry.owner(at: capture.owner.identity) === capture.owner, file: file, line: line)
        let invalidations = host.events.stateInvalidations
        let completions = host.events.rootCompletions
        capture.value.wrappedValue = lastValue + 1_000
        XCTAssertEqual(capture.value.wrappedValue, lastValue, file: file, line: line)
        XCTAssertEqual(host.events.stateInvalidations, invalidations, file: file, line: line)
        XCTAssertEqual(host.events.rootCompletions, completions, file: file, line: line)
    }
}

@MainActor
private final class ManagedRemovalPaintHarness {
    let host: MountedLazyListTestHost
    let clock = RuntimeTestClock()
    let size: IntSize

    init<Content: View>(
        size: IntSize = IntSize(width: 160, height: 96),
        content: @escaping @MainActor () -> Content
    ) {
        self.size = size
        host = MountedLazyListTestHost(
            size: Size(width: Double(size.width), height: Double(size.height)), content: content)
        clock.now = 10
        let clock = clock
        host.runtime.clock = { clock.now }
    }

    func refresh(afterReload: () -> Void = {}) {
        withAnimation(.linear(duration: 1)) {
            host.reload()
            afterReload()
            XCTAssertNotNil(host.layout())
        }
    }

    @discardableResult
    func render(at timestamp: Double) -> BitmapSurface {
        clock.now = timestamp
        _ = host.runtime.tickAnimations(at: timestamp)
        let scene = host.runtime.renderScene(at: timestamp)
        XCTAssertTrue(scene.validate().isEmpty)
        return GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    @discardableResult
    func renderFrame(at timestamp: Double) -> BitmapSurface {
        clock.now = timestamp
        _ = host.runtime.tickAnimations(at: timestamp)
        return GPUIRawSceneRasterizer.rasterize(host.runtime.renderFrame(at: timestamp), size: size)
    }
}

private struct ManagedRemovalPaintData: Identifiable {
    let id: Int
    let seed: Int
}

@MainActor
private struct ManagedRemovalPaintCapture {
    let owner: StateMountOwner
    let value: Binding<Int>
    let model: MountedLazyListModel
}

@MainActor
private final class ManagedRemovalPaintProbe {
    var rows: [ManagedRemovalPaintData]
    var selection = 0
    var transition: AnyTransition = .asymmetric(insertion: .identity, removal: .opacity)
    var runsTasks = false
    var usesCanvas = false
    var canvasColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
    var canvasCalls = 0
    var bodyCalls: [Int: Int] = [:]
    var captures: [Int: ManagedRemovalPaintCapture] = [:]
    var appearances: [Int: Int] = [:]
    var disappearances: [Int: Int] = [:]
    var activations: [Int: Int] = [:]
    var onDisappear: ((Int) -> Void)?
    let tasks = ManagedRemovalTaskProbe()

    init(count: Int) {
        rows = (0..<count).map { ManagedRemovalPaintData(id: $0, seed: 100 + $0) }
    }

    func record(row: Int, value: Binding<Int>, model: MountedLazyListModel) {
        bodyCalls[row, default: 0] += 1
        guard let owner = ViewBuildContextScope.current?.viewIdentity.installedOwner else {
            XCTFail("A real managed row must install its State owner")
            return
        }
        captures[row] = ManagedRemovalPaintCapture(owner: owner, value: value, model: model)
    }

    func disappear(_ row: Int) {
        disappearances[row, default: 0] += 1
        onDisappear?(row)
    }

    func finish() {
        onDisappear = nil
        tasks.finish()
        captures.removeAll()
    }
}

@MainActor
private struct ManagedRemovalPaintRow: View {
    @State private var value: Int
    @StateObject private var model: MountedLazyListModel
    let row: Int
    let probe: ManagedRemovalPaintProbe

    init(_ data: ManagedRemovalPaintData, probe: ManagedRemovalPaintProbe) {
        row = data.id
        self.probe = probe
        _value = State(initialValue: data.seed)
        _model = StateObject(wrappedValue: MountedLazyListModel(value: data.seed, serial: data.id))
    }

    var body: some View {
        probe.record(row: row, value: $value, model: model)
        let row = row
        let probe = probe
        let fill: AnyView
        if probe.usesCanvas {
            fill = AnyView(
                Canvas { context, size in
                    probe.canvasCalls += 1
                    var path = Path()
                    path.moveTo(Point(x: 0, y: 0))
                    path.lineTo(Point(x: size.width, y: 0))
                    path.lineTo(Point(x: size.width, y: size.height))
                    path.lineTo(Point(x: 0, y: size.height))
                    path.close()
                    context.fill(path, with: .color(probe.canvasColor))
                })
        } else {
            fill = AnyView(
                row == 1
                    ? Color(red: 1, green: 0, blue: 0, alpha: 1)
                    : Color(red: 0, green: 0, blue: 1, alpha: 1))
        }
        let content =
            fill
            .frame(width: 80, height: 32)
            .transition(probe.transition)
            .accessibilityIdentifier(managedRemovalIdentifier(row))
            .accessibilityLabel("Paint row \(row)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { probe.activations[row, default: 0] += 1 }
            .focusable()
            .onTapGesture { probe.activations[row, default: 0] += 1 }
            .onAppear { probe.appearances[row, default: 0] += 1 }
            .onDisappear { probe.disappear(row) }
        if probe.runsTasks {
            return AnyView(content.task(id: row) { await probe.tasks.run(row) })
        }
        return AnyView(content)
    }
}

@MainActor
@ViewBuilder
private func managedRemovalPublicList(_ probe: ManagedRemovalPaintProbe, builder: Bool) -> some View {
    if builder {
        List { ForEach(probe.rows) { ManagedRemovalPaintRow($0, probe: probe) } }
            .listStyle(.plain)
    } else {
        List(probe.rows) { ManagedRemovalPaintRow($0, probe: probe) }
            .listStyle(.plain)
    }
}

@MainActor
private func managedRemovalBoundedList(_ probe: ManagedRemovalPaintProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.id, estimatedExtent: 32, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { ManagedRemovalPaintRow($0, probe: probe) }
}

@MainActor
private func managedRemovalTabs(_ probe: ManagedRemovalPaintProbe) -> some View {
    ManagedLazyListContent(
        [0], id: \.self, estimatedExtent: 160, prefetchExtent: 0,
        maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1
    ) { _ in
        TabView(selection: Binding(get: { probe.selection }, set: { probe.selection = $0 })) {
            ManagedRemovalPaintRow(ManagedRemovalPaintData(id: 0, seed: 100), probe: probe)
                .tag(0)
                .tabItem { Color.clear.frame(width: 16, height: 8) }
            ManagedRemovalPaintRow(ManagedRemovalPaintData(id: 1, seed: 200), probe: probe)
                .tag(1)
                .tabItem { Color.clear.frame(width: 16, height: 8) }
        }
        .frame(height: 160)
    }
}

@MainActor
private final class ManagedRemovalTaskProbe {
    var onStart: ((Int) -> Void)?
    var onCancel: ((Int) -> Void)?
    private(set) var starts: [Int] = []
    private(set) var cancellations: [Int] = []
    private var nextRun = 0
    private var running: [Int: (row: Int, continuation: CheckedContinuation<Void, Never>)] = [:]

    func run(_ row: Int) async {
        nextRun += 1
        let run = nextRun
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                running[run] = (row, continuation)
                starts.append(row)
                onStart?(row)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(run) }
        }
    }

    private func cancel(_ run: Int) {
        guard let task = running.removeValue(forKey: run) else { return }
        cancellations.append(task.row)
        task.continuation.resume()
        onCancel?(task.row)
    }

    func finish() {
        onStart = nil
        onCancel = nil
        let continuations = running.values.map(\.continuation)
        running.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

private func managedRemovalIdentifier(_ row: Int) -> String { "managed.removal.\(row)" }

private func managedRemovalCenter(_ frame: Rect) -> Point {
    Point(x: frame.minX + frame.width / 2, y: frame.minY + frame.height / 2)
}

@MainActor
private func managedRemovalPoint(_ row: Int, in host: MountedLazyListTestHost) throws -> Point {
    let node = try XCTUnwrap(host.find(managedRemovalIdentifier(row)))
    return managedRemovalCenter(try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: node)))
}

private struct ManagedRemovalPixel: Equatable {
    let blue: Int
    let green: Int
    let red: Int
    let alpha: Int
    var blueContrast: Double { Double(blue - red) }
}

/// A plain List keeps its opaque control well after its final row leaves.
/// Its slight blue cast is background, not a remnant of the blue test row.
private var managedRemovalPlainListBackground: ManagedRemovalPixel {
    let color = ControlPalette.darkStandard.controlBackground
    return ManagedRemovalPixel(
        blue: Int((color.blue * 255).rounded()), green: Int((color.green * 255).rounded()),
        red: Int((color.red * 255).rounded()), alpha: Int((color.alpha * 255).rounded()))
}

private func managedRemovalPixel(
    _ bitmap: BitmapSurface, at point: Point, file: StaticString = #filePath, line: UInt = #line
) -> ManagedRemovalPixel {
    guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
        point.x < Double(bitmap.width), point.y < Double(bitmap.height)
    else {
        XCTFail("Expected an interior pixel inside the retained surface, got \(point)", file: file, line: line)
        return ManagedRemovalPixel(blue: 0, green: 0, red: 0, alpha: 0)
    }
    let offset = Int(point.y) * Int(bitmap.bytesPerRow) + Int(point.x) * 4
    return ManagedRemovalPixel(
        blue: Int(bitmap.pixels[offset]), green: Int(bitmap.pixels[offset + 1]),
        red: Int(bitmap.pixels[offset + 2]), alpha: Int(bitmap.pixels[offset + 3]))
}

@MainActor
private final class ManagedRemovalWeakNode {
    weak var value: ViewNode?
    init(_ value: ViewNode) { self.value = value }
}

@MainActor
private struct ManagedRemovalPhysicalLifetime {
    let node: ManagedRemovalWeakNode
    let descendants: [ManagedRemovalWeakNode]
    let attachment: RetainedLazyListAttachmentProof
}

@MainActor
private func managedRemovalPhysicalLifetime(
    _ row: Int, in host: MountedLazyListTestHost
) throws -> ManagedRemovalPhysicalLifetime {
    let node = try host.rowRoot(managedRemovalIdentifier(row))
    return ManagedRemovalPhysicalLifetime(
        node: ManagedRemovalWeakNode(node),
        descendants: MountedLazyListTestHost.descendants(in: node).map(ManagedRemovalWeakNode.init),
        attachment: node.captureLazyListAttachmentProof())
}
