import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class MountedOnChangeTransactionClock {
    var now = 100.0
}

private struct MountedOnChangeTransactionSnapshot {
    let transaction: Transaction?
    let animationDuration: Double?
    let animationEasing: AnimationEasing?
    let isBuilding: Bool
    let opacityAnimation: AnimationState?
}

@MainActor
private final class MountedOnChangeTransactionProbe {
    var observed = 0
    var writeTransaction: Transaction?
    var installedOpacity: Binding<Double>?
    var changes: [String] = []
    var beforeWrite: [MountedOnChangeTransactionSnapshot] = []
    var afterWrite: [MountedOnChangeTransactionSnapshot] = []
    var completions: [MountedOnChangeTransactionSnapshot] = []
    var afterStateWrite: (@MainActor () -> Void)?
    var afterCompletion: (@MainActor (Int) -> Void)?
    weak var host: MountedOnChangeTestHost?
    weak var target: ViewNode?

    func snapshot() -> MountedOnChangeTransactionSnapshot {
        MountedOnChangeTransactionSnapshot(
            transaction: currentTransaction,
            animationDuration: currentAnimationTransaction?.duration,
            animationEasing: currentAnimationTransaction?.easing,
            isBuilding: host?.runtime.hasActiveRetainedBuild == true,
            opacityAnimation: target?.animationStates[.opacity])
    }
}

@MainActor
private struct MountedOnChangeTransactionView: View {
    let probe: MountedOnChangeTransactionProbe
    @State private var opacity = 1.0

    var body: some View {
        // This projection comes from the installed body, never a source seed.
        let binding = $opacity
        probe.installedOpacity = binding
        return Color.blue
            .frame(width: 80, height: 24)
            .opacity(opacity)
            .accessibilityIdentifier("onchange.transaction.opacity")
            .onChange(of: probe.observed) { old, new in
                probe.changes.append("\(old)->\(new)")
                probe.beforeWrite.append(probe.snapshot())
                if let transaction = probe.writeTransaction {
                    binding.transaction(transaction).wrappedValue = 0.2
                } else {
                    binding.wrappedValue = 0.2
                }
                probe.afterWrite.append(probe.snapshot())
                probe.afterStateWrite?()
            }
    }
}

@MainActor
final class MountedOnChangeTransactionTests: XCTestCase {
    func testQueuedObserverPreservesFullTransactionAndRestoresNestedScopes() async throws {
        try withoutAmbientTransaction {
            for disablesAnimations in [false, true] {
                let probe = MountedOnChangeTransactionProbe()
                let clock = MountedOnChangeTransactionClock()
                let host = makeHost(probe: probe, clock: clock)
                defer { host.close() }
                let node = try opacityNode(in: host, probe: probe)
                XCTAssertEqual(
                    try XCTUnwrap(host.runtime.resolvedLayoutFrame(of: node)).size, Size(width: 80, height: 24))
                let outer = outerTransaction()
                var captured = detailedTransaction(animation: .linear(duration: 1))
                captured.disablesAnimations = disablesAnimations

                // Queue the observed change while an adopted outer build still
                // owns the guard. Its nested scope ends before delivery starts.
                probe.afterCompletion = { [weak host, weak probe] count in
                    guard count == 1, let host, let probe else { return }
                    self.assertContext(probe.snapshot(), transaction: outer)
                    withTransaction(captured) {
                        probe.observed = 1
                        host.reload()
                        XCTAssertTrue(probe.changes.isEmpty)
                        self.assertContext(probe.snapshot(), transaction: captured)
                    }
                    self.assertContext(probe.snapshot(), transaction: outer)
                }
                withTransaction(outer) {
                    host.reload()
                    assertContext(probe.snapshot(), transaction: outer)
                }

                XCTAssertEqual(probe.changes, ["0->1"])
                XCTAssertEqual(probe.beforeWrite.count, 1)
                XCTAssertEqual(probe.afterWrite.count, 1)
                for snapshot in probe.beforeWrite + probe.afterWrite {
                    assertContext(snapshot, transaction: captured)
                    XCTAssertTrue(snapshot.isBuilding)
                }
                XCTAssertEqual(probe.completions.count, 3)
                for (snapshot, transaction) in zip(probe.completions, [outer, captured, captured]) {
                    assertContext(snapshot, transaction: transaction)
                    XCTAssertTrue(snapshot.isBuilding)
                }
                XCTAssertEqual(probe.installedOpacity?.wrappedValue, 0.2)
                XCTAssertTrue(try opacityNode(in: host, probe: probe) === node)
                XCTAssertNil(currentTransaction)
                XCTAssertNil(currentAnimationTransaction)
                if disablesAnimations {
                    XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
                    XCTAssertNil(node.animationStates[.opacity])
                } else {
                    assertTween(on: node, start: 100, duration: 1)
                    tick(host, clock: clock, at: 100.5)
                    XCTAssertEqual(node.opacity, 0.6, accuracy: 0.0001)
                    tick(host, clock: clock, at: 101)
                    XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
                    XCTAssertNil(node.animationStates[.opacity])
                }
            }
        }
    }

    func testExplicitNilStateTransactionSnapsUnderAnAnimatedObserver() async throws {
        try withoutAmbientTransaction {
            let probe = MountedOnChangeTransactionProbe()
            let clock = MountedOnChangeTransactionClock()
            let host = makeHost(probe: probe, clock: clock)
            defer { host.close() }
            let node = try opacityNode(in: host, probe: probe)
            let outer = outerTransaction()
            // Keep disablesAnimations false: explicit nil itself must suppress
            // the observer's ambient animation for the queued State rebuild.
            let explicit = detailedTransaction(animation: nil)
            XCTAssertFalse(explicit.disablesAnimations)
            probe.writeTransaction = explicit

            withTransaction(outer) {
                probe.observed = 1
                host.reload()
                assertContext(probe.snapshot(), transaction: outer)
            }

            XCTAssertEqual(probe.changes, ["0->1"])
            XCTAssertEqual(probe.beforeWrite.count, 1)
            XCTAssertEqual(probe.afterWrite.count, 1)
            for snapshot in probe.beforeWrite + probe.afterWrite {
                assertContext(snapshot, transaction: outer)
                XCTAssertTrue(snapshot.isBuilding)
            }
            XCTAssertEqual(probe.completions.count, 2)
            for (snapshot, transaction) in zip(probe.completions, [outer, explicit]) {
                assertContext(snapshot, transaction: transaction)
                XCTAssertTrue(snapshot.isBuilding)
            }
            XCTAssertEqual(probe.installedOpacity?.wrappedValue, 0.2)
            XCTAssertTrue(try opacityNode(in: host, probe: probe) === node)
            XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
            XCTAssertNil(node.animationStates[.opacity])
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
            tick(host, clock: clock, at: 102)
            XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
            XCTAssertNil(node.animationStates[.opacity])
            XCTAssertEqual(probe.changes, ["0->1"])
        }
    }

    func testQueuedObserverRetainsLegacyAnimationWithoutInventingAFullTransaction() async throws {
        try withoutAmbientTransaction {
            let probe = MountedOnChangeTransactionProbe()
            let clock = MountedOnChangeTransactionClock()
            let host = makeHost(probe: probe, clock: clock)
            defer { host.close() }
            let node = try opacityNode(in: host, probe: probe)
            let outer = outerTransaction()

            probe.afterCompletion = { [weak host, weak probe] count in
                guard count == 1, let host, let probe else { return }
                let previous = currentTransaction
                let previousAnimation = currentAnimationTransaction
                currentTransaction = nil
                currentAnimationTransaction = (duration: 2, easing: .linear)
                defer {
                    currentTransaction = previous
                    currentAnimationTransaction = previousAnimation
                }
                probe.observed = 1
                host.reload()
                XCTAssertTrue(probe.changes.isEmpty)
                self.assertLegacyContext(probe.snapshot(), duration: 2)
            }
            withTransaction(outer) {
                host.reload()
                assertContext(probe.snapshot(), transaction: outer)
            }

            XCTAssertEqual(probe.changes, ["0->1"])
            XCTAssertEqual(probe.beforeWrite.count, 1)
            XCTAssertEqual(probe.afterWrite.count, 1)
            for snapshot in probe.beforeWrite + probe.afterWrite {
                assertLegacyContext(snapshot, duration: 2)
                XCTAssertTrue(snapshot.isBuilding)
            }
            XCTAssertEqual(probe.completions.count, 3)
            assertContext(try XCTUnwrap(probe.completions.first), transaction: outer)
            for snapshot in probe.completions.dropFirst() {
                assertLegacyContext(snapshot, duration: 2)
                XCTAssertTrue(snapshot.isBuilding)
            }
            XCTAssertEqual(probe.installedOpacity?.wrappedValue, 0.2)
            XCTAssertTrue(try opacityNode(in: host, probe: probe) === node)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
            assertTween(on: node, start: 100, duration: 2)
            tick(host, clock: clock, at: 101)
            XCTAssertEqual(node.opacity, 0.6, accuracy: 0.0001)
            tick(host, clock: clock, at: 102)
            XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
            XCTAssertNil(node.animationStates[.opacity])
        }
    }

    func testObserverSecondReloadDoesNotRestartTheUnchangedOpacityTween() async throws {
        try withoutAmbientTransaction {
            let probe = MountedOnChangeTransactionProbe()
            let clock = MountedOnChangeTransactionClock()
            let host = makeHost(probe: probe, clock: clock)
            defer { host.close() }
            let node = try opacityNode(in: host, probe: probe)
            let outer = outerTransaction()
            let stateTransaction = detailedTransaction(animation: .linear(duration: 1))
            probe.writeTransaction = stateTransaction
            var secondReloads = 0
            probe.afterStateWrite = { [weak host] in
                secondReloads += 1
                host?.reload()
            }
            probe.afterCompletion = { count in
                // State's one-second tween is already adopted. The next queued
                // request has the same endpoint and the outer four-second scope.
                if count == 2 { clock.now = 100.25 }
            }

            withTransaction(outer) {
                probe.observed = 1
                host.reload()
                assertContext(probe.snapshot(), transaction: outer)
            }

            XCTAssertEqual(probe.changes, ["0->1"])
            XCTAssertEqual(secondReloads, 1)
            XCTAssertEqual(probe.beforeWrite.count, 1)
            XCTAssertEqual(probe.afterWrite.count, 1)
            for snapshot in probe.beforeWrite + probe.afterWrite {
                assertContext(snapshot, transaction: outer)
                XCTAssertTrue(snapshot.isBuilding)
            }
            XCTAssertEqual(probe.completions.count, 3)
            for (snapshot, transaction) in zip(probe.completions, [outer, stateTransaction, outer]) {
                assertContext(snapshot, transaction: transaction)
                XCTAssertTrue(snapshot.isBuilding)
            }
            XCTAssertEqual(probe.completions.map { $0.opacityAnimation?.duration }, [nil, 1, 1])
            XCTAssertEqual(probe.completions.map { $0.opacityAnimation?.startTime }, [nil, 100, 100])
            XCTAssertEqual(probe.installedOpacity?.wrappedValue, 0.2)
            XCTAssertTrue(try opacityNode(in: host, probe: probe) === node)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
            assertTween(on: node, start: 100, duration: 1)
            tick(host, clock: clock, at: 100.25)
            XCTAssertEqual(node.opacity, 0.8, accuracy: 0.0001)
            tick(host, clock: clock, at: 100.5)
            XCTAssertEqual(node.opacity, 0.6, accuracy: 0.0001)
            tick(host, clock: clock, at: 101)
            XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
            XCTAssertNil(node.animationStates[.opacity])
            XCTAssertEqual(probe.changes, ["0->1"])
            XCTAssertEqual(secondReloads, 1)
        }
    }

    private func makeHost(
        probe: MountedOnChangeTransactionProbe, clock: MountedOnChangeTransactionClock
    ) -> MountedOnChangeTestHost {
        let host = MountedOnChangeTestHost {
            AnyView(MountedOnChangeTransactionView(probe: probe))
        }
        probe.host = host
        host.runtime.clock = { clock.now }
        host.componentHost.onReloadCompleted = { [weak probe] in
            guard let probe else { return }
            probe.completions.append(probe.snapshot())
            probe.afterCompletion?(probe.completions.count)
        }
        XCTAssertNil(host.coordinator.latestInstallationError)
        XCTAssertEqual(probe.installedOpacity?.wrappedValue, 1)
        XCTAssertTrue(probe.changes.isEmpty)
        return host
    }

    private func opacityNode(
        in host: MountedOnChangeTestHost, probe: MountedOnChangeTransactionProbe,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        var pending = host.runtime.root.children
        var matches: [ViewNode] = []
        while let node = pending.popLast() {
            if node.accessibilityIdentifier == "onchange.transaction.opacity" { matches.append(node) }
            pending.append(contentsOf: node.children)
        }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        let node = try XCTUnwrap(matches.first, file: file, line: line)
        probe.target = node
        return node
    }

    private func outerTransaction() -> Transaction {
        var transaction = Transaction(animation: .linear(duration: 4))
        transaction.scrollTargetAnchor = .top
        return transaction
    }

    private func detailedTransaction(animation: Animation?) -> Transaction {
        var transaction = Transaction(animation: animation)
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        return transaction
    }

    private func assertContext(
        _ snapshot: MountedOnChangeTransactionSnapshot, transaction: Transaction,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNotNil(snapshot.transaction, file: file, line: line)
        XCTAssertEqual(
            snapshot.transaction?.animation?.duration, transaction.animation?.duration, file: file, line: line)
        XCTAssertEqual(snapshot.transaction?.animation?.easing, transaction.animation?.easing, file: file, line: line)
        XCTAssertEqual(snapshot.transaction?.disablesAnimations, transaction.disablesAnimations, file: file, line: line)
        XCTAssertEqual(snapshot.transaction?.isContinuous, transaction.isContinuous, file: file, line: line)
        XCTAssertEqual(snapshot.transaction?.scrollTargetAnchor, transaction.scrollTargetAnchor, file: file, line: line)
        XCTAssertEqual(snapshot.transaction?.tracksVelocity, transaction.tracksVelocity, file: file, line: line)
        let animation = transaction.disablesAnimations ? nil : transaction.animation
        XCTAssertEqual(snapshot.animationDuration, animation?.duration, file: file, line: line)
        XCTAssertEqual(snapshot.animationEasing, animation?.easing, file: file, line: line)
    }

    private func assertLegacyContext(
        _ snapshot: MountedOnChangeTransactionSnapshot, duration: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNil(snapshot.transaction, file: file, line: line)
        XCTAssertEqual(snapshot.animationDuration, duration, file: file, line: line)
        XCTAssertEqual(snapshot.animationEasing, .linear, file: file, line: line)
    }

    private func assertTween(
        on node: ViewNode, start: Double, duration: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(node.opacity, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(node.animationStates[.opacity]?.startValue, 1, file: file, line: line)
        XCTAssertEqual(node.animationStates[.opacity]?.endValue, 0.2, file: file, line: line)
        XCTAssertEqual(node.animationStates[.opacity]?.startTime, start, file: file, line: line)
        XCTAssertEqual(node.animationStates[.opacity]?.duration, duration, file: file, line: line)
        XCTAssertEqual(node.animationStates[.opacity]?.easing, .linear, file: file, line: line)
    }

    private func tick(_ host: MountedOnChangeTestHost, clock: MountedOnChangeTransactionClock, at time: Double) {
        clock.now = time
        _ = host.runtime.tickAnimations(at: time)
    }

    private func withoutAmbientTransaction(_ body: () throws -> Void) rethrows {
        let previous = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = nil
        defer {
            currentTransaction = previous
            currentAnimationTransaction = previousAnimation
        }
        try body()
    }
}
