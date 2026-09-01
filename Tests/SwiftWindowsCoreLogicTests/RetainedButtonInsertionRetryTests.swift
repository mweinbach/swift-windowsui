import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class RetainedButtonInsertionRetryTests: XCTestCase {
    func testDefaultBudgetUsesFreshAttemptsAfterTheInsertionClockClearsTheButtonOwner() async throws {
        try assertDefaultBudgetRetry(.clear)
    }

    func testDefaultBudgetUsesFreshAttemptsAfterTheInsertionClockReplacesTheButtonOwner() async throws {
        try assertDefaultBudgetRetry(.replace)
    }

    private func assertDefaultBudgetRetry(
        _ change: ButtonInsertionRetryChange, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = nil
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        let probe = ButtonInsertionRetryProbe()
        let host = MountedLazyListTestHost(size: Size(width: 160, height: 120)) {
            WinSwiftUI.List(probe.rows, id: \.self) { _ in ButtonInsertionRetryRow(probe: probe) }
                .listStyle(.plain)
        }
        defer {
            probe.willBuild = nil
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

        // Keep the production default budget. These tests observe fresh attempts,
        // not a fixed number of source builds, resolution rounds, or clock reads.
        probe.rows = [1]
        withAnimation(.linear(duration: 2)) { host.reload() }
        probe.adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter, file: file, line: line)
        XCTAssertTrue(probe.builds.isEmpty, file: file, line: line)

        var original: ButtonInsertionRetryRejection?
        var buildsAtOriginalClock = 0
        var firstSuccessor: ButtonInsertionRetryAttempt?
        probe.willBuild = { attempt, descriptorAttempt in
            guard let original, firstSuccessor == nil else { return }
            do {
                let successor = ButtonInsertionRetryAttempt(
                    attempt: try XCTUnwrap(attempt, file: file, line: line),
                    descriptorAttempt: try XCTUnwrap(descriptorAttempt, file: file, line: line))
                firstSuccessor = successor
                XCTAssertFalse(successor.attempt === original.attempt.attempt, file: file, line: line)
                XCTAssertFalse(
                    successor.descriptorAttempt === original.attempt.descriptorAttempt, file: file, line: line)
                // This runs before inner.makeNode or any successor property copy.
                // A permitted layout pass may already have changed resolved frames.
                XCTAssertTrue(original.owner.isRetired, file: file, line: line)
                XCTAssertFalse(original.event.isPending, file: file, line: line)
                XCTAssertFalse(original.completion.isCurrent, file: file, line: line)
                for pose in original.poses { pose.assertUnanimated(file: file, line: line) }
            } catch {
                XCTFail(
                    "Successor source construction must carry native attempt identities: \(error)", file: file,
                    line: line)
            }
        }
        host.runtime.clock = {
            clockReads += 1
            guard original == nil else { return 12 }
            do {
                let root = try host.rowRoot(buttonInsertionRetryIdentifier, file: file, line: line)
                let target = try XCTUnwrap(host.find(buttonInsertionRetryIdentifier), file: file, line: line)
                let button = try XCTUnwrap(
                    MountedLazyListTestHost.descendants(in: root).first { $0.buttonActionOwner != nil },
                    file: file, line: line)
                let owner = try XCTUnwrap(button.buttonActionOwner, file: file, line: line)
                // Associate delivery with the actual accepted owner, not an
                // assumed first source build or the current array's last entry.
                let build = try XCTUnwrap(probe.builds.last { $0.owner === owner }, file: file, line: line)
                let attempt = ButtonInsertionRetryAttempt(
                    attempt: try XCTUnwrap(build.attempt, file: file, line: line),
                    descriptorAttempt: try XCTUnwrap(build.descriptorAttempt, file: file, line: line))
                let event = try XCTUnwrap(probe.event, file: file, line: line)
                let action = try XCTUnwrap(button.onActivate, file: file, line: line)
                let completion = try XCTUnwrap(
                    RetainedLazyListAdoptionCompletion(of: root), file: file, line: line)
                let poses = MountedLazyListTestHost.descendants(in: root).map(ButtonInsertionRetryPose.init)
                XCTAssertTrue(probe.eventWasPendingAtFirstBuild, file: file, line: line)
                XCTAssertFalse(event.isPending, file: file, line: line)
                XCTAssertTrue(button.isRetainedLazyListAttached(in: host.runtime), file: file, line: line)
                XCTAssertTrue(button.retainedLazyListRuntime === host.runtime, file: file, line: line)
                XCTAssertFalse(owner.isPending, file: file, line: line)
                XCTAssertFalse(owner.isRetired, file: file, line: line)
                XCTAssertTrue(completion.isCurrent, file: file, line: line)
                XCTAssertTrue(target.didPlayInsertionTransition, file: file, line: line)
                XCTAssertNotEqual(target.transition.insertion.kind, .identity, file: file, line: line)
                for pose in poses { pose.assertUnanimated(file: file, line: line) }
                original = ButtonInsertionRetryRejection(
                    attempt: attempt, owner: owner, event: event, completion: completion,
                    poses: poses, action: action)
                buildsAtOriginalClock = probe.builds.count
                switch change {
                case .clear:
                    button.onActivate = nil
                case .replace:
                    button.buttonActionOwner = RetainedButtonActionOwner(
                        action: nil, node: button, runtime: host.runtime)
                }
                XCTAssertTrue(owner.isRetired, file: file, line: line)
                XCTAssertFalse(completion.isCurrent, file: file, line: line)
                XCTAssertFalse(event.isPending, file: file, line: line)
                // Do not invoke the public action here: its ordinary completion
                // would independently invalidate the enclosing build context.
            } catch {
                XCTFail(
                    "Insertion delivery must identify the accepted Button and its original attempt: \(error)",
                    file: file, line: line)
            }
            return 12
        }

        _ = host.layout()

        // Freeze this query's native-token log before any later measurement or
        // explicit query could stand in for its post-refusal successor attempts.
        let firstQueryBuilds = probe.builds
        let rejected = try XCTUnwrap(original, file: file, line: line)
        let successor = try XCTUnwrap(firstSuccessor, file: file, line: line)
        let laterBuilds = Array(firstQueryBuilds.dropFirst(buildsAtOriginalClock))
        XCTAssertFalse(laterBuilds.isEmpty, file: file, line: line)
        let firstLaterBuild = try XCTUnwrap(laterBuilds.first, file: file, line: line)
        XCTAssertTrue(firstLaterBuild.attempt === successor.attempt, file: file, line: line)
        XCTAssertTrue(firstLaterBuild.descriptorAttempt === successor.descriptorAttempt, file: file, line: line)

        var seenAttempts = Set<ObjectIdentifier>()
        var seenDescriptorAttempts = Set<ObjectIdentifier>()
        var previous: ButtonInsertionRetryAttempt?
        for build in laterBuilds {
            let attempt = try XCTUnwrap(build.attempt, file: file, line: line)
            let descriptorAttempt = try XCTUnwrap(build.descriptorAttempt, file: file, line: line)
            XCTAssertFalse(attempt === rejected.attempt.attempt, file: file, line: line)
            XCTAssertFalse(descriptorAttempt === rejected.attempt.descriptorAttempt, file: file, line: line)
            if previous?.attempt === attempt {
                // Several sources in one attempt may share both native tokens.
                XCTAssertTrue(previous?.descriptorAttempt === descriptorAttempt, file: file, line: line)
            } else {
                XCTAssertTrue(seenAttempts.insert(ObjectIdentifier(attempt)).inserted, file: file, line: line)
                XCTAssertTrue(
                    seenDescriptorAttempts.insert(ObjectIdentifier(descriptorAttempt)).inserted, file: file, line: line)
            }
            previous = ButtonInsertionRetryAttempt(attempt: attempt, descriptorAttempt: descriptorAttempt)
        }
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertFalse(rejected.event.isPending, file: file, line: line)
        XCTAssertTrue(rejected.owner.isRetired, file: file, line: line)

        // Fresh attempts may settle within the first query or need a later
        // measurement. Neither is a resumption of the rejected completion.
        _ = host.layout()
        let currentTarget = try XCTUnwrap(host.find(buttonInsertionRetryIdentifier), file: file, line: line)
        XCTAssertTrue(currentTarget.didPlayInsertionTransition, file: file, line: line)
        XCTAssertNil(currentTarget.animationStates[.opacity], file: file, line: line)
        XCTAssertEqual(currentTarget.opacity, 1, file: file, line: line)
        XCTAssertFalse(rejected.event.isPending, file: file, line: line)
        XCTAssertFalse(rejected.completion.isCurrent, file: file, line: line)
        rejected.action()
        XCTAssertEqual(probe.activations, 0, file: file, line: line)
    }
}

private enum ButtonInsertionRetryChange { case clear, replace }
private let buttonInsertionRetryIdentifier = "button.insertion.retry.row"

@MainActor
private struct ButtonInsertionRetryAttempt {
    // Strong native identity objects cannot be mistaken for reused addresses.
    let attempt: RetainedLazyListAttemptID
    let descriptorAttempt: RetainedLazyListAttemptID
}

@MainActor
private final class ButtonInsertionRetryBuild {
    let attempt: RetainedLazyListAttemptID?
    let descriptorAttempt: RetainedLazyListAttemptID?
    weak var owner: RetainedButtonActionOwner?

    init(attempt: RetainedLazyListAttemptID?, descriptorAttempt: RetainedLazyListAttemptID?) {
        self.attempt = attempt
        self.descriptorAttempt = descriptorAttempt
    }
}

@MainActor
private final class ButtonInsertionRetryProbe {
    var rows: [Int] = []
    var activations = 0
    weak var adapter: RetainedLazyListRuntimeAdapter?
    var event: RetainedLazyListInsertionEvent?
    var eventWasPendingAtFirstBuild = false
    var builds: [ButtonInsertionRetryBuild] = []
    var willBuild: ((RetainedLazyListAttemptID?, RetainedLazyListAttemptID?) -> Void)?
}

@MainActor
private struct ButtonInsertionRetryRow: View {
    typealias Body = Never
    let probe: ButtonInsertionRetryProbe
    var body: Never { fatalError("Primitive") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let inner = WinSwiftUI.Button("Run") { probe.activations += 1 }
            .frame(width: 80, height: 32)
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
            .accessibilityIdentifier(buttonInsertionRetryIdentifier)
            .makeComponent(context: context)
        let attempt = context.viewIdentity.lazyList?.native.attempt
        let descriptorAttempt = context.viewIdentity.lazyList?.native.descriptorBuildAttemptID
        let token = context.viewIdentity.lazyList?.native.rowRequest.token
        return Component { runtime in
            if probe.event == nil, let token, let event = probe.adapter?.pendingInsertionEvent(for: token) {
                // Save the original event once. Looking up a consumed event in
                // a later attempt would itself expire pending insertion state.
                probe.event = event
                probe.eventWasPendingAtFirstBuild = event.isPending
            }
            probe.willBuild?(attempt, descriptorAttempt)
            let observation = ButtonInsertionRetryBuild(attempt: attempt, descriptorAttempt: descriptorAttempt)
            probe.builds.append(observation)
            let node = inner.makeNode(runtime: runtime)
            observation.owner = MountedLazyListTestHost.descendants(in: node).compactMap(\.buttonActionOwner).first
            return node
        }
    }
}

@MainActor
private struct ButtonInsertionRetryRejection {
    let attempt: ButtonInsertionRetryAttempt
    let owner: RetainedButtonActionOwner
    let event: RetainedLazyListInsertionEvent
    // This is a test observation and is never submitted as engine authority.
    let completion: RetainedLazyListAdoptionCompletion
    let poses: [ButtonInsertionRetryPose]
    let action: () -> Void
}

@MainActor
private struct ButtonInsertionRetryPose {
    let node: ViewNode
    let opacity: Double
    let transform: Transform2D

    init(_ node: ViewNode) {
        self.node = node
        opacity = node.opacity
        transform = node.transform
    }

    func assertUnanimated(file: StaticString, line: UInt) {
        XCTAssertNil(node.animationStates[.opacity], file: file, line: line)
        XCTAssertEqual(node.opacity, opacity, file: file, line: line)
        XCTAssertEqual(node.transform, transform, file: file, line: line)
    }
}
