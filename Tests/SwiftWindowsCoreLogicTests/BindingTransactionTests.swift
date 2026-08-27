import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class BindingTransactionTests: XCTestCase {
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

    func testUnconfiguredGetSetBindingPreservesAbsenceOfTransaction() async {
        withoutAmbientTransaction {
            var value = 1
            var setterCalls = 0
            let binding = Binding(
                get: { value },
                set: { newValue in
                    value = newValue
                    setterCalls += 1
                    XCTAssertNil(currentTransaction)
                    XCTAssertNil(currentAnimationTransaction)
                })

            XCTAssertNil(binding.transaction.animation)
            binding.wrappedValue = 4
            binding.projectedValue.wrappedValue = 7

            XCTAssertEqual(binding.wrappedValue, 7)
            XCTAssertEqual(setterCalls, 2)
            XCTAssertNil(currentTransaction)
        }
    }

    func testTransactionSetterReceivesDefaultOrAmbientTransaction() async {
        withoutAmbientTransaction {
            var received: [Transaction] = []
            var value = 0
            let binding = Binding(
                get: { value },
                set: { newValue, transaction in
                    value = newValue
                    received.append(transaction)
                })
            binding.wrappedValue = 1
            var ambient = Transaction(animation: .linear(duration: 2))
            ambient.isContinuous = true
            withTransaction(ambient) {
                binding.wrappedValue = 2
                XCTAssertEqual(currentTransaction?.animation?.duration, 2)
            }

            XCTAssertEqual(value, 2)
            XCTAssertEqual(received.count, 2)
            XCTAssertNil(received[0].animation)
            XCTAssertFalse(received[0].isContinuous)
            XCTAssertEqual(received[1].animation?.duration, 2)
            XCTAssertTrue(received[1].isContinuous)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    func testTransactionReturnsIndependentBindingAndScopesBothSetterForms() async {
        withoutAmbientTransaction {
            var value = 0
            var received: Transaction?
            let binding = Binding(
                get: { value },
                set: { newValue, transaction in
                    value = newValue
                    received = transaction
                    XCTAssertEqual(currentTransaction?.animation?.duration, 0.8)
                    XCTAssertEqual(currentAnimationTransaction?.duration, 0.8)
                })
            var transaction = Transaction(animation: .easeOut(duration: 0.8))
            transaction.isContinuous = true
            transaction.scrollTargetAnchor = .bottom
            transaction.tracksVelocity = true
            let configured = binding.transaction(transaction)
            configured.wrappedValue = 9

            XCTAssertEqual(value, 9)
            XCTAssertEqual(received?.animation?.easing, .easeOut)
            XCTAssertEqual(received?.isContinuous, true)
            XCTAssertEqual(received?.scrollTargetAnchor, .bottom)
            XCTAssertEqual(received?.tracksVelocity, true)
            XCTAssertNil(binding.transaction.animation)
            XCTAssertEqual(configured.transaction.animation?.duration, 0.8)
            XCTAssertNil(currentTransaction)

            let simple = Binding(
                get: { value },
                set: { newValue in
                    value = newValue
                    XCTAssertEqual(currentTransaction?.animation?.duration, 0.8)
                    XCTAssertEqual(currentAnimationTransaction?.duration, 0.8)
                })
            simple.transaction(transaction).wrappedValue = 12
            XCTAssertEqual(value, 12)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    func testTransactionPropertyMutationAndAnimationPreserveOtherFlags() async {
        withoutAmbientTransaction {
            var received: Transaction?
            var binding = Binding(
                get: { 0 },
                set: { _, transaction in
                    received = transaction
                    XCTAssertNil(currentAnimationTransaction)
                })
            binding.transaction.disablesAnimations = true
            binding.transaction.isContinuous = true
            binding.transaction.scrollTargetAnchor = .top
            binding.transaction.tracksVelocity = true
            let animated = binding.animation(.linear(duration: 0.4))
            animated.wrappedValue = 1

            XCTAssertEqual(received?.animation?.duration, 0.4)
            XCTAssertEqual(received?.disablesAnimations, true)
            XCTAssertEqual(received?.isContinuous, true)
            XCTAssertEqual(received?.scrollTargetAnchor, .top)
            XCTAssertEqual(received?.tracksVelocity, true)
            XCTAssertNil(binding.transaction.animation)
            XCTAssertNil(currentTransaction)
        }
    }

    func testAnimationOnlyConfigurationInheritsAmbientFlagsAndRestoresScope() async {
        withoutAmbientTransaction {
            var received: Transaction?
            let binding = Binding(get: { 0 }, set: { _, transaction in received = transaction })
                .animation(.linear(duration: 0.25))
            var ambient = Transaction(animation: .easeIn(duration: 2))
            ambient.isContinuous = true
            ambient.scrollTargetAnchor = .trailing
            ambient.tracksVelocity = true
            withTransaction(ambient) {
                binding.wrappedValue = 1
                XCTAssertEqual(currentTransaction?.animation?.duration, 2)
                XCTAssertEqual(currentAnimationTransaction?.duration, 2)
            }

            XCTAssertEqual(received?.animation?.duration, 0.25)
            XCTAssertEqual(received?.animation?.easing, .linear)
            XCTAssertEqual(received?.isContinuous, true)
            XCTAssertEqual(received?.scrollTargetAnchor, .trailing)
            XCTAssertEqual(received?.tracksVelocity, true)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    func testExplicitNilAnimationOverridesAmbientOnlyDuringBindingWrite() async {
        withoutAmbientTransaction {
            var received: Transaction?
            let binding = Binding(
                get: { 0 },
                set: { _, transaction in
                    received = transaction
                    XCTAssertNotNil(currentTransaction)
                    XCTAssertNil(currentTransaction?.animation)
                    XCTAssertNil(currentAnimationTransaction)
                })
            withAnimation(.linear(duration: 3)) {
                binding.animation(nil).wrappedValue = 1
                XCTAssertEqual(currentTransaction?.animation?.duration, 3)
                XCTAssertEqual(currentAnimationTransaction?.duration, 3)
            }

            XCTAssertNotNil(received)
            XCTAssertNil(received?.animation)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    func testAnimationDefaultAndRepeatedConfigurationUseLatestValue() async {
        withoutAmbientTransaction {
            var received: Transaction?
            let binding = Binding(get: { 0 }, set: { _, transaction in received = transaction })
            binding.animation().wrappedValue = 1
            XCTAssertEqual(received?.animation?.duration, Animation.default.duration)
            XCTAssertEqual(received?.animation?.easing, Animation.default.easing)

            binding.animation(.linear(duration: 5)).animation(.easeOut(duration: 0.6)).wrappedValue = 2
            XCTAssertEqual(received?.animation?.duration, 0.6)
            XCTAssertEqual(received?.animation?.easing, .easeOut)

            binding.animation(.linear).transaction(Transaction(animation: nil)).wrappedValue = 3
            XCTAssertNil(received?.animation)
            XCTAssertNil(currentTransaction)
        }
    }

    func testDynamicMemberAndCollectionProjectionsPreserveAndReplaceTransaction() async {
        withoutAmbientTransaction {
            struct Item {
                var title: String
                var count: Int
            }
            struct Model {
                var items: [Item]
                var name: String
            }
            var model = Model(items: [Item(title: "first", count: 1), Item(title: "second", count: 2)], name: "model")
            var received: [Transaction] = []
            let binding = Binding(
                get: { model },
                set: { newValue, transaction in
                    model = newValue
                    received.append(transaction)
                    XCTAssertEqual(currentTransaction?.animation?.duration, transaction.animation?.duration)
                })
            var transaction = Transaction(animation: .easeIn(duration: 1.5))
            transaction.isContinuous = true
            let configured = binding.transaction(transaction)
            let title = configured.items[1].title
            XCTAssertEqual(title.transaction.animation?.duration, 1.5)
            title.projectedValue.wrappedValue = "edited"
            configured.items[0].count.animation(.linear(duration: 0.5)).wrappedValue = 4
            binding.items[1].title.animation(.easeOut(duration: 0.2)).wrappedValue = "latest"

            XCTAssertEqual(model.items[0].title, "first")
            XCTAssertEqual(model.items[0].count, 4)
            XCTAssertEqual(model.items[1].title, "latest")
            XCTAssertEqual(model.items[1].count, 2)
            XCTAssertEqual(model.name, "model")
            XCTAssertEqual(received.map { $0.animation?.duration }, [1.5, 0.5, 0.2])
            XCTAssertTrue(received[0].isContinuous)
            XCTAssertTrue(received[1].isContinuous)
            XCTAssertFalse(received[2].isContinuous)
            XCTAssertNil(currentTransaction)
        }
    }

    func testOptionalProjectionForwardsTransactionAndIgnoresNilWrites() async {
        withoutAmbientTransaction {
            var value = 1
            var received: [Transaction] = []
            let binding = Binding(
                get: { value },
                set: { newValue, transaction in
                    value = newValue
                    received.append(transaction)
                }
            ).animation(.linear(duration: 1))
            let optional = Binding<Int?>(binding)
            XCTAssertEqual(optional.transaction.animation?.duration, 1)
            optional.wrappedValue = 2
            optional.animation(.easeIn(duration: 0.3)).wrappedValue = 3
            optional.wrappedValue = nil

            XCTAssertEqual(value, 3)
            XCTAssertEqual(received.map { $0.animation?.duration }, [1, 0.3])
            XCTAssertNil(currentTransaction)
        }
    }

    func testUnwrappedOptionalProjectionKeepsFallbackAndTransaction() async {
        withoutAmbientTransaction {
            var value: Int? = nil
            var received: [Transaction] = []
            let binding = Binding(
                get: { value },
                set: { newValue, transaction in
                    value = newValue
                    received.append(transaction)
                }
            ).animation(.easeOut(duration: 0.7))
            XCTAssertNil(Binding<Int>(binding))
            value = 5
            guard let unwrapped = Binding<Int>(binding) else { return XCTFail("missing optional projection") }
            XCTAssertEqual(unwrapped.transaction.animation?.duration, 0.7)
            unwrapped.wrappedValue = 6
            value = nil
            XCTAssertEqual(unwrapped.wrappedValue, 5)
            unwrapped.animation(.linear(duration: 0.2)).wrappedValue = 9

            XCTAssertEqual(value, 9)
            XCTAssertEqual(received.map { $0.animation?.duration }, [0.7, 0.2])
            XCTAssertNil(currentTransaction)
        }
    }

    func testNestedBindingWritesRestoreOuterAndAmbientTransactions() async {
        withoutAmbientTransaction {
            var seen: [Double?] = []
            let nested = Binding(
                get: { 0 },
                set: { _ in
                    seen.append(currentTransaction?.animation?.duration)
                }
            ).animation(.linear(duration: 0.2))
            let outer = Binding(
                get: { 0 },
                set: { _ in
                    seen.append(currentTransaction?.animation?.duration)
                    nested.wrappedValue = 1
                    seen.append(currentTransaction?.animation?.duration)
                }
            ).animation(.linear(duration: 0.8))
            withAnimation(.linear(duration: 2)) {
                outer.wrappedValue = 1
                seen.append(currentTransaction?.animation?.duration)
            }

            XCTAssertEqual(seen, [0.8, 0.2, 0.8, 2])
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    func testCoreTransactionScopeRestoresBothContextsAfterThrow() async throws {
        try withoutAmbientTransaction {
            enum ExpectedFailure: Error { case failure }
            currentAnimationTransaction = (duration: 4, easing: .easeIn)
            defer { currentAnimationTransaction = nil }
            XCTAssertThrowsError(
                try TransactionContext.withValue(Transaction(animation: .linear(duration: 1))) {
                    XCTAssertEqual(currentTransaction?.animation?.duration, 1)
                    XCTAssertEqual(currentAnimationTransaction?.duration, 1)
                    try TransactionContext.withValue(Transaction(animation: nil)) {
                        XCTAssertNotNil(currentTransaction)
                        XCTAssertNil(currentAnimationTransaction)
                        throw ExpectedFailure.failure
                    }
                })

            XCTAssertNil(currentTransaction)
            XCTAssertEqual(currentAnimationTransaction?.duration, 4)
            XCTAssertEqual(currentAnimationTransaction?.easing, .easeIn)
        }
    }

    private struct AnimatedStateView: View {
        @State var opacity = 1.0

        var body: some View {
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 40)
                .opacity(opacity)
        }
    }

    func testAnimatedStateBindingReconcilesAndPresentsIntermediateOpacity() async {
        withoutAmbientTransaction {
            let clock = RuntimeTestClock()
            clock.now = 10
            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60)))
            runtime.clock = { clock.now }
            let host = ComponentHost(runtime: runtime)
            let view = AnimatedStateView()
            var invalidations = 0
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 100, height: 60) },
                invalidateHandler: { [weak host] in
                    invalidations += 1
                    host?.reload()
                })
            host.setComponents { [view.makeComponent(context: context)] }
            let node = runtime.root.children[0]

            view.$opacity.animation(.linear(duration: 1)).wrappedValue = 0.2
            XCTAssertEqual(invalidations, 1)
            XCTAssertTrue(runtime.root.children[0] === node)
            XCTAssertEqual(view.opacity, 0.2)
            XCTAssertEqual(node.opacity, 1)
            XCTAssertEqual(node.animationStates[.opacity]?.startTime, 10)

            clock.now = 10.5
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(node.opacity, 0.6, accuracy: 0.0001)
            XCTAssertTrue(runtime.hasActiveAnimations)
            clock.now = 11
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(node.opacity, 0.2, accuracy: 0.0001)
            XCTAssertFalse(runtime.hasActiveAnimations)

            withAnimation(.linear(duration: 3)) {
                view.$opacity.animation(nil).wrappedValue = 0.9
                XCTAssertEqual(node.opacity, 0.9)
                XCTAssertFalse(runtime.hasActiveAnimations)
                XCTAssertEqual(currentAnimationTransaction?.duration, 3)
            }
            XCTAssertEqual(invalidations, 2)
            XCTAssertNil(currentTransaction)
            XCTAssertNil(currentAnimationTransaction)
        }
    }

    func testOrdinaryBindingPreservesControlMotionAndExplicitNilCancelsIt() async {
        withoutAmbientTransaction {
            let clock = RuntimeTestClock()
            clock.now = 20
            let runtime = RetainedViewRuntime(root: ViewNode())
            runtime.clock = { clock.now }
            let host = ComponentHost(runtime: runtime)
            var opacity = 1.0
            host.setContent {
                Component { _ in
                    let node = ViewNode()
                    node.opacity = opacity
                    node.implicitReconcileAnimation = AnimationTransaction(duration: 1, easing: .linear)
                    return node
                }
            }
            let binding = Binding(
                get: { opacity },
                set: { newValue in
                    opacity = newValue
                    host.reload()
                })
            let node = runtime.root.children[0]
            binding.wrappedValue = 0.2
            clock.now = 20.5
            _ = runtime.tickAnimations(at: clock.now)
            XCTAssertEqual(node.opacity, 0.6, accuracy: 0.0001)

            binding.animation(nil).wrappedValue = 0.8
            XCTAssertEqual(node.opacity, 0.8)
            XCTAssertFalse(runtime.hasActiveAnimations)
            XCTAssertNil(currentTransaction)
        }
    }
}
