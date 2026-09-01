import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The insertion clock runs after Button adoption has finished. Its completion
/// must still describe the original optional action owner before any tween writes.
@MainActor
final class RetainedButtonInsertionCompositionTests: XCTestCase {
    func testClearingTheAcceptedButtonInTheInsertionClockRejectsTheWholePresentation() async throws {
        try assertInsertionClock(.clear)
    }

    func testReplacingOnlyTheButtonOwnerInTheInsertionClockRejectsTheWholePresentation() async throws {
        try assertInsertionClock(.replace)
    }

    func testUnchangedButtonOwnerAllowsInsertionAndTheAcceptedAction() async throws {
        try assertInsertionClock(.unchanged)
    }

    func testCompletionDistinguishesAnAbsentOwnerFromANewlyInstalledOwner() async throws {
        let runtime = makeRuntime()
        let node = makeButton(in: runtime)
        runtime.root.addChild(node)
        node.onActivate = nil
        let native = ButtonInsertionNativeWitness(node)
        let absent = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        let absentTwin = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        XCTAssertTrue(absent.isCurrent)
        XCTAssertTrue(absent.containsEquivalentWitnesses(of: absentTwin))

        let installed = RetainedButtonActionOwner(action: nil, node: node, runtime: runtime)
        node.buttonActionOwner = installed
        let present = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))

        native.assertCurrent(includingPose: true)
        XCTAssertFalse(absent.isCurrent)
        XCTAssertTrue(present.isCurrent)
        XCTAssertFalse(present.containsEquivalentWitnesses(of: absent))
        XCTAssertFalse(absent.containsEquivalentWitnesses(of: present))
        // Equivalence compares the original captures, not today's currentness.
        XCTAssertTrue(absent.containsEquivalentWitnesses(of: absentTwin))
        withExtendedLifetime(runtime) {}
    }

    func testCompletionComparesTheOriginalOwnerIdentityWhenBothSnapshotsHadAnOwner() async throws {
        let runtime = makeRuntime()
        let node = makeButton(in: runtime)
        runtime.root.addChild(node)
        let originalOwner = try XCTUnwrap(node.buttonActionOwner)
        let native = ButtonInsertionNativeWitness(node)
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        let replacementOwner = RetainedButtonActionOwner(action: nil, node: node, runtime: runtime)

        node.buttonActionOwner = replacementOwner
        let replacement = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))

        native.assertCurrent(includingPose: true)
        XCTAssertTrue(originalOwner.isRetired)
        XCTAssertFalse(replacementOwner.isRetired)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(replacement.isCurrent)
        XCTAssertFalse(replacement.containsEquivalentWitnesses(of: original))
        XCTAssertFalse(original.containsEquivalentWitnesses(of: replacement))
        withExtendedLifetime((runtime, originalOwner, replacementOwner)) {}
    }

    func testCompletionDoesNotKeepAClearedButtonOwnerAlive() async throws {
        let runtime = makeRuntime()
        let node = makeButton(in: runtime)
        runtime.root.addChild(node)
        weak var originalOwner = node.buttonActionOwner
        let native = ButtonInsertionNativeWitness(node)
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        let originalTwin = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        XCTAssertNotNil(originalOwner)
        XCTAssertTrue(original.isCurrent)

        node.onActivate = nil
        let cleared = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))

        native.assertCurrent(includingPose: true)
        XCTAssertNil(originalOwner, "Weak completion witnesses cannot keep the retired action owner alive")
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(cleared.isCurrent)
        XCTAssertFalse(original.containsEquivalentWitnesses(of: originalTwin), "Expired weak owners are not equivalent")
        XCTAssertFalse(cleared.containsEquivalentWitnesses(of: original))
        withExtendedLifetime(runtime) {}
    }

    func testCompletionRemembersTheRetiredBitOfTheSameInstalledOwner() async throws {
        let runtime = makeRuntime()
        let node = makeButton(in: runtime)
        runtime.root.addChild(node)
        let owner = try XCTUnwrap(node.buttonActionOwner)
        let native = ButtonInsertionNativeWitness(node)
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        let originalTwin = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))

        owner.retire()
        let retired = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        let retiredTwin = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))

        native.assertCurrent(includingPose: true)
        XCTAssertTrue(node.buttonActionOwner === owner)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(retired.isCurrent, "A new native snapshot may describe an already retired owner")
        XCTAssertFalse(retired.containsEquivalentWitnesses(of: original))
        XCTAssertFalse(original.containsEquivalentWitnesses(of: retired))
        XCTAssertTrue(original.containsEquivalentWitnesses(of: originalTwin))
        XCTAssertTrue(retired.containsEquivalentWitnesses(of: retiredTwin))
        withExtendedLifetime(runtime) {}
    }

    func testRestoringTheSameOwnerAfterNilActivationCannotRefreshItsOldCompletion() async throws {
        let runtime = makeRuntime()
        var calls = 0
        let node = makeButton(in: runtime) { calls += 1 }
        runtime.root.addChild(node)
        let owner = try XCTUnwrap(node.buttonActionOwner)
        let action = try XCTUnwrap(node.onActivate)
        let native = ButtonInsertionNativeWitness(node)
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
        XCTAssertFalse(owner.isRetired)

        node.onActivate = nil
        node.buttonActionOwner = owner
        node.onActivate = action
        let restored = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))

        native.assertCurrent(includingPose: true)
        XCTAssertTrue(node.buttonActionOwner === owner)
        XCTAssertTrue(owner.isRetired)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(restored.isCurrent)
        XCTAssertFalse(restored.containsEquivalentWitnesses(of: original))
        action()
        XCTAssertEqual(calls, 0)
        withExtendedLifetime(runtime) {}
    }

    private func assertInsertionClock(
        _ change: ButtonInsertionOwnerChange, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = nil
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        let probe = ButtonInsertionCompositionProbe()
        let host = MountedLazyListTestHost(size: Size(width: 160, height: 120)) {
            WinSwiftUI.List(probe.rows, id: \.self) { probe.makeRow($0) }
                .listStyle(.plain)
        }
        defer {
            host.runtime.clock = { 0 }
            host.close()
        }
        var clockReads = 0
        host.runtime.clock = {
            clockReads += 1
            return 12
        }
        XCTAssertNotNil(host.layout(), file: file, line: line)
        XCTAssertTrue(try host.list().children.isEmpty, file: file, line: line)
        try host.assertCommittedDescriptor(file: file, line: line)
        XCTAssertEqual(clockReads, 0, file: file, line: line)

        probe.rows = [1, 2]
        withAnimation(.linear(duration: 2)) { host.reload() }
        XCTAssertTrue(probe.factoryCalls.isEmpty, "Descriptor acceptance must not build rows", file: file, line: line)
        XCTAssertNil(host.find(buttonInsertionIdentifier(1)), file: file, line: line)
        XCTAssertNil(host.find(buttonInsertionIdentifier(2)), file: file, line: line)
        XCTAssertEqual(clockReads, 0, file: file, line: line)

        var targets: [ViewNode] = []
        var witnesses: [ButtonInsertionNativeWitness] = []
        var button: ViewNode?
        var originalOwner: RetainedButtonActionOwner?
        var replacementOwner: RetainedButtonActionOwner?
        var escapedAction: (() -> Void)?
        host.runtime.clock = {
            clockReads += 1
            guard clockReads == 1 else {
                XCTFail("Only the admitted insertion delivery may sample the clock", file: file, line: line)
                return 12
            }
            do {
                let roots = try [1, 2].map { try host.rowRoot(buttonInsertionIdentifier($0), file: file, line: line) }
                targets = try [1, 2].map {
                    try XCTUnwrap(host.find(buttonInsertionIdentifier($0)), file: file, line: line)
                }
                let forest = roots.flatMap { MountedLazyListTestHost.descendants(in: $0) }
                witnesses = forest.map { ButtonInsertionNativeWitness($0) }
                let actualButton = try XCTUnwrap(
                    MountedLazyListTestHost.descendants(in: roots[0]).first { $0.buttonActionOwner != nil },
                    file: file, line: line)
                let acceptedOwner = try XCTUnwrap(actualButton.buttonActionOwner, file: file, line: line)
                button = actualButton
                originalOwner = acceptedOwner
                escapedAction = try XCTUnwrap(actualButton.onActivate, file: file, line: line)
                XCTAssertTrue(actualButton.retainedLazyListRuntime === host.runtime, file: file, line: line)
                XCTAssertTrue(actualButton.isRetainedLazyListAttached(in: host.runtime), file: file, line: line)
                XCTAssertFalse(acceptedOwner.isPending, file: file, line: line)
                XCTAssertFalse(acceptedOwner.isRetired, file: file, line: line)
                for target in targets {
                    XCTAssertNotEqual(target.transition.insertion.kind, .identity, file: file, line: line)
                    XCTAssertTrue(target.didPlayInsertionTransition, file: file, line: line)
                    XCTAssertNil(target.animationStates[.opacity], file: file, line: line)
                    XCTAssertEqual(target.opacity, 1, file: file, line: line)
                }
                XCTAssertTrue(forest.allSatisfy { $0.animationStates.isEmpty }, file: file, line: line)
                switch change {
                case .unchanged: break
                case .clear: actualButton.onActivate = nil
                case .replace:
                    // A full component adoption would change identity/configuration
                    // too. Change only this native owner slot; do not grant the
                    // replacement any acceptance or claim that its action is live.
                    let replacement = RetainedButtonActionOwner(action: nil, node: actualButton, runtime: host.runtime)
                    replacementOwner = replacement
                    actualButton.buttonActionOwner = replacement
                }
                for witness in witnesses { witness.assertCurrent(includingPose: true, file: file, line: line) }
            } catch {
                XCTFail("Insertion must reach both actual rows before its clock: \(error)", file: file, line: line)
            }
            // Public Button completion invalidates its build context. Invoking
            // it here would independently reject even an unchanged insertion.
            return 12
        }

        let layout = host.layout()

        // No render or second layout may replace this callback-bearing attempt.
        XCTAssertEqual(clockReads, 1, file: file, line: line)
        XCTAssertEqual(targets.count, 2, file: file, line: line)
        let actualButton = try XCTUnwrap(button, file: file, line: line)
        let acceptedOwner = try XCTUnwrap(originalOwner, file: file, line: line)
        let savedAction = try XCTUnwrap(escapedAction, file: file, line: line)
        for witness in witnesses { witness.assertCurrent(includingPose: false, file: file, line: line) }
        for target in targets {
            XCTAssertTrue(host.contains(target), file: file, line: line)
            XCTAssertTrue(target.didPlayInsertionTransition, file: file, line: line)
        }
        switch change {
        case .unchanged:
            XCTAssertNotNil(layout, file: file, line: line)
            XCTAssertTrue(actualButton.buttonActionOwner === acceptedOwner, file: file, line: line)
            XCTAssertFalse(acceptedOwner.isRetired, file: file, line: line)
            for target in targets {
                let state = try XCTUnwrap(target.animationStates[.opacity], file: file, line: line)
                XCTAssertEqual(state.startTime, 12, file: file, line: line)
                XCTAssertEqual(state.duration, 2, file: file, line: line)
                XCTAssertEqual(state.startValue, 0, file: file, line: line)
                XCTAssertEqual(state.endValue, 1, file: file, line: line)
                XCTAssertEqual(state.easing, .linear, file: file, line: line)
                XCTAssertEqual(target.opacity, 0, file: file, line: line)
            }
            // Action availability is tested after the presentation assertions,
            // so its ordinary invalidation cannot stand in for owner rejection.
            host.runtime.clock = { 12 }
            savedAction()
            XCTAssertEqual(probe.activations, 1, file: file, line: line)
        case .clear, .replace:
            XCTAssertTrue(acceptedOwner.isRetired, file: file, line: line)
            if change == .clear {
                XCTAssertNil(actualButton.buttonActionOwner, file: file, line: line)
                XCTAssertNil(actualButton.onActivate, file: file, line: line)
            } else {
                let replacement = try XCTUnwrap(replacementOwner, file: file, line: line)
                XCTAssertTrue(actualButton.buttonActionOwner === replacement, file: file, line: line)
                XCTAssertFalse(replacement.isRetired, file: file, line: line)
            }
            for witness in witnesses {
                XCTAssertTrue(witness.node.animationStates.isEmpty, file: file, line: line)
                XCTAssertEqual(witness.node.opacity, witness.opacity, file: file, line: line)
                XCTAssertEqual(witness.node.transform, witness.transform, file: file, line: line)
            }
            savedAction()
            XCTAssertEqual(probe.activations, 0, file: file, line: line)
        }
    }

    private func makeRuntime() -> RetainedViewRuntime {
        RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 120)))
    }

    private func makeButton(in runtime: RetainedViewRuntime, action: (() -> Void)? = nil) -> ViewNode {
        Controls.button(
            runtime: runtime, frame: Rect(x: 0, y: 0, width: 80, height: 32), cornerRadius: 4,
            palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
    }
}

private enum ButtonInsertionOwnerChange { case unchanged, clear, replace }

@MainActor
private final class ButtonInsertionCompositionProbe {
    var rows: [Int] = []
    var factoryCalls: [Int] = []
    var activations = 0

    func makeRow(_ value: Int) -> some View {
        factoryCalls.append(value)
        return WinSwiftUI.Button("Run") { self.activations += 1 }
            .frame(width: 80, height: 32)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .accessibilityIdentifier(buttonInsertionIdentifier(value))
    }
}

private func buttonInsertionIdentifier(_ value: Int) -> String { "button.insertion.composition.\(value)" }

/// These are test observations, never completion proofs passed into adoption.
@MainActor
private struct ButtonInsertionNativeWitness {
    let node: ViewNode
    let attachment: RetainedLazyListAttachmentProof
    let identity: RetainedLazyListViewIdentityProof
    let configuration: RetainedRemovalTransitionConfigurationID
    let children: [ObjectIdentifier]
    let opacity: Double
    let transform: Transform2D
    let frame: Rect

    init(_ node: ViewNode) {
        self.node = node
        attachment = node.captureLazyListAttachmentProof()
        identity = node.captureLazyListIdentityProof()
        configuration = node.removalTransitionConfigurationID
        children = node.children.map(ObjectIdentifier.init)
        opacity = node.opacity
        transform = node.transform
        frame = node.resolvedFrame
    }

    func assertCurrent(includingPose: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(attachment.isCurrent, file: file, line: line)
        XCTAssertTrue(identity.isCurrent, file: file, line: line)
        XCTAssertTrue(node.removalTransitionConfigurationID === configuration, file: file, line: line)
        XCTAssertEqual(node.children.map(ObjectIdentifier.init), children, file: file, line: line)
        if includingPose {
            XCTAssertEqual(node.opacity, opacity, file: file, line: line)
            XCTAssertEqual(node.transform, transform, file: file, line: line)
            XCTAssertEqual(node.resolvedFrame, frame, file: file, line: line)
        }
    }
}
