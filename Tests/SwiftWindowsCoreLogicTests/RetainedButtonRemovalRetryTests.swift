import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A rejected removal attempt must stop, while a later paid provider round may
/// start a new attempt from the actual retained tree. These are separate rules.
@MainActor
final class RetainedButtonRemovalRetryTests: XCTestCase {
    func testDefaultBudgetRetriesManagedRemovalAfterButtonOwnerClears() async throws {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = nil
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        let rows = ButtonRemovalRetryRows()
        let host = MountedLazyListTestHost(size: Size(width: 140, height: 80)) {
            WinSwiftUI.List(rows.values, id: \.self) { _ in
                WinSwiftUI.Button("Run") {}
                    .frame(width: 80, height: 32)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    .accessibilityIdentifier("button.removal.retry.row")
            }
            .listStyle(.plain)
        }
        defer {
            host.runtime.recordsLazyListUIAPhasesForTesting = false
            host.close()
        }
        host.runtime.clock = { 10 }
        XCTAssertNotNil(host.layout())
        XCTAssertTrue(host.runtime.renderScene(at: 10).validate().isEmpty)
        let list = try host.list()
        let row = try host.rowRoot("button.removal.retry.row")
        let button = try XCTUnwrap(
            MountedLazyListTestHost.descendants(in: row).first { $0.buttonActionOwner != nil })
        let originalOwner = try XCTUnwrap(button.buttonActionOwner)
        let rowAttachment = row.captureLazyListAttachmentProof()
        let buttonAttachment = button.captureLazyListAttachmentProof()
        let buttonIdentity = button.captureLazyListIdentityProof()
        XCTAssertNotNil(list.retainedLazyListAdapter?.managedLogicalDescriptorBinding)
        XCTAssertTrue(row.retainedLazyListPresentedPaint?.isCurrent == true)
        XCTAssertTrue(row.hasAppeared)
        XCTAssertTrue(row.parent === list)
        XCTAssertNotEqual(row.transition.removal.kind, .identity)

        // These existing records contain native scalar observations only. They
        // cannot authorize, schedule, or refund a build. Do not change the budget.
        host.runtime.recordsLazyListUIAPhasesForTesting = true
        var firstModifierPhases: [RetainedViewRuntime.LazyListUIAPhaseTrace] = []
        var laterModifierPhases: [RetainedViewRuntime.LazyListUIAPhaseTrace] = []
        var disappearances = 0
        @MainActor
        func currentProviderPhase() throws -> RetainedViewRuntime.LazyListUIAPhaseTrace {
            let phase = try XCTUnwrap(
                host.runtime.lazyListUIAPhasesForTesting.last { $0.kind == .providerPhase })
            XCTAssertEqual(phase.consumedRounds + phase.remainingRounds, 4)
            XCTAssertEqual(phase.remainingElements, 128)
            XCTAssertGreaterThan(phase.consumedRounds, 0)
            return phase
        }
        row.onDisappear = {
            disappearances += 1
            do {
                let original = try XCTUnwrap(firstModifierPhases.first)
                let later = try XCTUnwrap(laterModifierPhases.last)
                let phase = try currentProviderPhase()
                XCTAssertGreaterThan(phase.consumedRounds, original.consumedRounds)
                XCTAssertEqual(phase.consumedRounds, later.consumedRounds)
                XCTAssertEqual(phase.layoutPassID, later.layoutPassID)
            } catch {
                XCTFail("Retirement must belong to an admitted successor round: \(error)")
            }
        }
        row.reconcileAnimationModifiers = [
            RetainedAnimationModifier(transaction: { transaction in
                do {
                    let original = try XCTUnwrap(firstModifierPhases.first)
                    let latestFirst = try XCTUnwrap(firstModifierPhases.last)
                    let phase = try currentProviderPhase()
                    // Continuing the original invalidated modifier loop fails
                    // here even if its later retirement looks otherwise valid.
                    XCTAssertGreaterThan(phase.consumedRounds, original.consumedRounds)
                    XCTAssertNotEqual(phase.layoutPassID, original.layoutPassID)
                    XCTAssertEqual(phase.consumedRounds, latestFirst.consumedRounds)
                    XCTAssertEqual(phase.layoutPassID, latestFirst.layoutPassID)
                    laterModifierPhases.append(phase)
                } catch {
                    XCTFail("The later modifier must run only in a fresh provider round: \(error)")
                }
                transaction.animation = Animation(duration: 1, easing: .linear)
            }),
            RetainedAnimationModifier(transaction: { transaction in
                do {
                    let phase = try currentProviderPhase()
                    XCTAssertTrue(host.runtime.hasActiveRetainedBuild)
                    if let previous = firstModifierPhases.last {
                        XCTAssertGreaterThan(phase.consumedRounds, previous.consumedRounds)
                        XCTAssertNotEqual(phase.layoutPassID, previous.layoutPassID)
                        XCTAssertTrue(laterModifierPhases.isEmpty)
                    } else {
                        XCTAssertTrue(button.buttonActionOwner === originalOwner)
                        button.onActivate = nil
                    }
                    firstModifierPhases.append(phase)
                    // Before a successor's own first modifier can advance, the
                    // original refusal must have left all physical work untouched.
                    XCTAssertTrue(originalOwner.isRetired)
                    XCTAssertNil(button.buttonActionOwner)
                    XCTAssertTrue(rowAttachment.isCurrent)
                    XCTAssertTrue(buttonAttachment.isCurrent)
                    XCTAssertTrue(buttonIdentity.isCurrent)
                    XCTAssertTrue(row.parent === list)
                    XCTAssertTrue(list.children.contains { $0 === row })
                    XCTAssertEqual(disappearances, 0)
                    XCTAssertEqual(host.runtime.retiredLazyListPaintCount, 0)
                    XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
                    XCTAssertTrue(row.animationStates.isEmpty)
                } catch {
                    XCTFail("Removal must run in a paid provider round with original physical ownership: \(error)")
                }
                transaction.animation = Animation(duration: 1, easing: .linear)
            }),
        ]
        defer {
            row.transition = .identity
            row.reconcileAnimationModifiers = []
            row.onDisappear = nil
        }

        rows.values = []
        withAnimation(.linear(duration: 1)) {
            host.reload()
            XCTAssertTrue(firstModifierPhases.isEmpty, "Descriptor acceptance must preserve the physical row")
            _ = host.layout()
        }

        // Observe this one query before any later layout or render could supply
        // the missing retry or finish the original removal on its behalf.
        XCTAssertGreaterThanOrEqual(firstModifierPhases.count, 2)
        XCTAssertEqual(laterModifierPhases.count, 1)
        let original = try XCTUnwrap(firstModifierPhases.first)
        let successor = try XCTUnwrap(laterModifierPhases.first)
        XCTAssertGreaterThan(successor.consumedRounds, original.consumedRounds)
        XCTAssertNotEqual(successor.layoutPassID, original.layoutPassID)
        XCTAssertFalse(rowAttachment.isCurrent)
        XCTAssertFalse(buttonAttachment.isCurrent)
        XCTAssertTrue(buttonIdentity.isCurrent)
        XCTAssertFalse(host.contains(row))
        XCTAssertTrue(list.children.isEmpty)
        XCTAssertTrue(originalOwner.isRetired)
        XCTAssertNil(button.buttonActionOwner)
        XCTAssertEqual(disappearances, 1)
        XCTAssertEqual(host.runtime.retiredLazyListPaintCount, 1)
        XCTAssertTrue(host.runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(row.animationStates.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
    }
}

@MainActor
private final class ButtonRemovalRetryRows {
    var values = [0]
}
