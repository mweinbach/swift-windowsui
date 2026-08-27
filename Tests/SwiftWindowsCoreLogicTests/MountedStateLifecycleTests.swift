import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// State belongs to a mounted occurrence, including when the authored value is rebuilt or reused.
@MainActor
final class MountedStateLifecycleTests: XCTestCase {
    func testFreshPrivateStateChildKeepsItsOwnActionAcrossParentRebuildsAndNewSeeds() async throws {
        let model = MountedStateTestModel()
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                MountedStateCounter(name: "counter", seed: model.revision + 10)
            })
        defer { fixture.close() }
        let originalValueNode = try fixture.node("counter.value")

        try fixture.activate("counter.increment")
        fixture.flush()
        try fixture.assertText("11", "counter.value")

        model.revision = 100
        fixture.flush()

        try fixture.assertText("11", "counter.value")
        XCTAssertTrue(try fixture.node("counter.value") === originalValueNode)
        try fixture.activate("counter.increment")
        fixture.flush()
        try fixture.assertText("12", "counter.value")
    }

    func testProjectedBindingCanInvalidateWithoutAnOwnerBodyReadingWrappedValue() async throws {
        let capture = MountedStateProjectionCapture()
        let model = MountedStateTestModel()
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                MountedStateProjectionOnly(capture: capture)
            })
        defer { fixture.close() }
        let binding = try XCTUnwrap(capture.binding)
        let buildsBeforeWrite = capture.bodyBuilds

        binding.wrappedValue = 7
        fixture.flush()

        XCTAssertGreaterThan(capture.bodyBuilds, buildsBeforeWrite)
        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 7)
        try fixture.activate("projection.increment")
        fixture.flush()
        XCTAssertEqual(try XCTUnwrap(capture.binding).wrappedValue, 8)
    }

    func testSameSourceValueMountedTwiceHasIndependentState() async throws {
        let model = MountedStateTestModel()
        let source = MountedStateCounter(name: "shared")
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                source.accessibilityIdentifier("left")
                source.accessibilityIdentifier("right")
            })
        defer { fixture.close() }

        try fixture.activate("shared.increment", within: "left")
        fixture.flush()
        try fixture.assertText("1", "shared.value", within: "left")
        try fixture.assertText("0", "shared.value", within: "right")

        try fixture.activate("shared.increment", within: "right")
        try fixture.activate("shared.increment", within: "right")
        model.revision += 1
        fixture.flush()

        try fixture.assertText("1", "shared.value", within: "left")
        try fixture.assertText("2", "shared.value", within: "right")
    }

    func testSameSourceInTwoHostsStartsFromTheAuthoredSeedAndInvalidatesOnlyItsOwner() async throws {
        let source = MountedStateCounter(name: "shared")
        let configuration = mountedStateConfiguration(source)
        let first = MountedStateWindow(configuration: configuration)
        defer { first.close() }
        try first.activate("shared.increment")
        first.flush()
        try first.assertText("1", "shared.value")

        let second = MountedStateWindow(configuration: configuration)
        defer { second.close() }
        try second.assertText("0", "shared.value")
        let secondReloads = second.host.executedReloadCount

        try first.activate("shared.increment")
        first.flush()
        second.flush()

        try first.assertText("2", "shared.value")
        try second.assertText("0", "shared.value")
        XCTAssertEqual(second.host.executedReloadCount, secondReloads)
        try second.activate("shared.increment")
        second.flush()
        try first.assertText("2", "shared.value")
        try second.assertText("1", "shared.value")
        first.close()
        try second.activate("shared.increment")
        second.flush()
        try second.assertText("2", "shared.value")
    }

    func testKeyedReorderInsertionRemovalAndReinsertionKeepOnlySurvivingOwners() async throws {
        let model = MountedStateTestModel()
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                ForEach(model.rows, id: \.self) { row in
                    MountedStateCounter(name: "row.\(row.value)")
                }
            })
        defer { fixture.close() }
        try fixture.activate("row.1.increment")
        try fixture.activate("row.1.increment")
        try fixture.activate("row.2.increment")
        fixture.flush()
        let first = try fixture.node("row.1.value")
        let second = try fixture.node("row.2.value")

        model.rows = [2, 3, 1].map(MountedStateRowKey.init)
        fixture.flush()

        try fixture.assertText("2", "row.1.value")
        try fixture.assertText("1", "row.2.value")
        try fixture.assertText("0", "row.3.value")
        XCTAssertTrue(try fixture.node("row.1.value") === first)
        XCTAssertTrue(try fixture.node("row.2.value") === second)

        model.rows = [2, 3].map(MountedStateRowKey.init)
        fixture.flush()
        model.rows = [1, 2, 3].map(MountedStateRowKey.init)
        fixture.flush()

        try fixture.assertText("0", "row.1.value")
        try fixture.assertText("1", "row.2.value")
        XCTAssertFalse(try fixture.node("row.1.value") === first)
        XCTAssertTrue(try fixture.node("row.2.value") === second)
    }

    func testSameTypeConditionalBranchesResetTheirStateWithoutResettingTheFollowingSibling() async throws {
        let model = MountedStateTestModel()
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                if model.firstBranch {
                    MountedStateCounter(name: "branch", seed: 10)
                } else {
                    MountedStateCounter(name: "branch", seed: 20)
                }
                MountedStateCounter(name: "following")
            })
        defer { fixture.close() }
        try fixture.activate("branch.increment")
        try fixture.activate("following.increment")
        fixture.flush()
        try fixture.assertText("11", "branch.value")

        model.firstBranch = false
        fixture.flush()
        try fixture.assertText("20", "branch.value")
        try fixture.assertText("1", "following.value")
        try fixture.activate("branch.increment")
        fixture.flush()
        try fixture.assertText("21", "branch.value")

        model.firstBranch = true
        fixture.flush()
        try fixture.assertText("10", "branch.value")
        try fixture.assertText("1", "following.value")
    }

    func testOptionalRemovalRetiresAReusedValueAndKeepsTheFollowingSibling() async throws {
        let model = MountedStateTestModel()
        let source = MountedStateCounter(name: "optional")
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                if model.showsChild { source }
                MountedStateCounter(name: "following")
            })
        defer { fixture.close() }
        try fixture.activate("optional.increment")
        try fixture.activate("following.increment")
        fixture.flush()
        try fixture.assertText("1", "optional.value")

        model.showsChild = false
        fixture.flush()
        XCTAssertFalse(fixture.contains("optional.value"))
        try fixture.assertText("1", "following.value")

        model.showsChild = true
        fixture.flush()
        try fixture.assertText("0", "optional.value")
        try fixture.assertText("1", "following.value")
    }

    func testExplicitIDValueAndTypeChangesResetAReusedSource() async throws {
        let model = MountedStateTestModel()
        let source = MountedStateCounter(name: "identified")
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                mountedStateIdentified(source, model: model)
            })
        defer { fixture.close() }
        try fixture.activate("identified.increment")
        fixture.flush()
        try fixture.assertText("1", "identified.value")

        model.revision += 1
        fixture.flush()
        try fixture.assertText("1", "identified.value")
        model.explicitID = 2
        fixture.flush()
        try fixture.assertText("0", "identified.value")

        try fixture.activate("identified.increment")
        fixture.flush()
        model.usesStringID = true
        fixture.flush()
        try fixture.assertText("0", "identified.value")
        try fixture.activate("identified.increment")
        fixture.flush()
        try fixture.assertText("1", "identified.value")
    }

    func testPrivatePropertySlotsDoNotDependOnWrappedValueReadOrder() async throws {
        let model = MountedStateTestModel()
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                MountedStateDeclarationSlots(reversesReads: model.reversesReads)
            })
        defer { fixture.close() }
        try fixture.activate("slots.first.increment")
        try fixture.activate("slots.second.increment")
        try fixture.activate("slots.second.increment")
        fixture.flush()
        try fixture.assertText("4", "slots.first")
        try fixture.assertText("32", "slots.second")

        model.reversesReads = true
        fixture.flush()

        try fixture.assertText("4", "slots.first")
        try fixture.assertText("32", "slots.second")
        try fixture.activate("slots.first.increment")
        fixture.flush()
        try fixture.assertText("5", "slots.first")
        try fixture.assertText("32", "slots.second")
    }

    func testRetiredRawBindingReadsTheLastMountedValueAndRejectsReplacementWrites() async throws {
        let (model, capture, fixture) = makeMountedStateRecordWindow()
        defer { fixture.close() }
        let stale = try XCTUnwrap(capture.raw)
        try fixture.activate("record.increment")
        try fixture.activate("record.increment")
        fixture.flush()
        replaceMountedStateRecordOwner(model: model, fixture: fixture)
        try fixture.activate("record.increment")
        fixture.flush()
        let reloads = fixture.host.executedReloadCount
        XCTAssertEqual(stale.wrappedValue.value, 2, "Read the last mounted value, not the seed or replacement")

        stale.wrappedValue = MountedStateRecord(value: 99)

        XCTAssertEqual(stale.wrappedValue.value, 2)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        await Task.yield()
        await Task.yield()
        fixture.flush()
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        try fixture.assertText("1", "record.value")
    }

    func testRetiredDynamicMemberBindingReadsItsOldGenerationAndRejectsWrites() async throws {
        let (model, capture, fixture) = makeMountedStateRecordWindow()
        defer { fixture.close() }
        let stale = try XCTUnwrap(capture.member).animation(.linear(duration: 1))
        try fixture.activate("record.increment")
        try fixture.activate("record.increment")
        fixture.flush()
        replaceMountedStateRecordOwner(model: model, fixture: fixture)
        try fixture.activate("record.increment")
        fixture.flush()
        let reloads = fixture.host.executedReloadCount
        XCTAssertEqual(stale.wrappedValue, 2)

        stale.wrappedValue = 99

        XCTAssertEqual(stale.wrappedValue, 2)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        await Task.yield()
        await Task.yield()
        fixture.flush()
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        try fixture.assertText("1", "record.value")
    }

    func testRetiredComputedBindingRejectsWritesBeforeItsSetterMutatesAReference() async throws {
        let model = MountedStateTestModel()
        let capture = MountedStateComputedCapture()
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                if model.showsChild {
                    MountedStateComputedOwner(capture: capture)
                }
            })
        defer { fixture.close() }
        let stale = try XCTUnwrap(capture.binding)
        let oldReference = try XCTUnwrap(capture.reference)
        try fixture.activate("computed.increment")
        fixture.flush()
        try fixture.assertText("5", "computed.value")
        XCTAssertEqual(oldReference.setterCalls, 1)

        model.showsChild = false
        fixture.flush()
        model.showsChild = true
        fixture.flush()
        let replacement = try XCTUnwrap(capture.reference)
        XCTAssertFalse(replacement === oldReference)
        XCTAssertEqual(stale.wrappedValue, 5)
        let reloads = fixture.host.executedReloadCount

        stale.wrappedValue = 99

        XCTAssertEqual(oldReference.setterCalls, 1, "Reject the write before invoking the computed setter")
        XCTAssertEqual(oldReference.value, 5)
        XCTAssertEqual(replacement.setterCalls, 0)
        XCTAssertEqual(replacement.value, 4)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        await Task.yield()
        await Task.yield()
        fixture.flush()
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        try fixture.assertText("4", "computed.value")

        // Retiring a binding rejects its setter; it does not freeze an
        // ordinary reference that an external owner can still mutate.
        oldReference.value = 6
        XCTAssertEqual(stale.wrappedValue, 6)
        XCTAssertEqual(oldReference.setterCalls, 1)
        XCTAssertEqual(replacement.value, 4)
    }

    func testRetiredCollectionBindingReadsTheLastMountedSnapshotAndRejectsWrites() async throws {
        let (model, capture, fixture) = makeMountedStateRecordWindow()
        defer { fixture.close() }
        try fixture.activate("record.install")
        fixture.flush()
        let stale = try XCTUnwrap(capture.element).animation(nil)
        try fixture.activate("record.increment-first")
        fixture.flush()
        replaceMountedStateRecordOwner(model: model, fixture: fixture)
        try fixture.assertText("none", "record.first")
        try fixture.activate("record.install")
        fixture.flush()
        let reloads = fixture.host.executedReloadCount
        XCTAssertEqual(stale.wrappedValue, 11, "The seed is empty and the replacement contains 10")

        stale.wrappedValue = 99

        XCTAssertEqual(stale.wrappedValue, 11)
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        await Task.yield()
        await Task.yield()
        fixture.flush()
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        try fixture.assertText("10", "record.first")
    }

    func testUnmountReleasesRegistryOwnershipWhenNoExternalReadHandlesRemain() async throws {
        let (model, capture, fixture) = makeMountedStateRecordWindow()
        defer { fixture.close() }
        try fixture.activate("record.install")
        fixture.flush()
        XCTAssertNotNil(capture.payload)
        capture.clearBindings()

        model.showsChild = false
        fixture.flush()
        capture.clearBindings()

        XCTAssertFalse(fixture.contains("record.value"))
        XCTAssertNil(capture.payload, "The live host's registry must relinquish its retired value")
    }

    func testExternalReadHandlesKeepRetiredPayloadsUntilEveryHandleIsDropped() async throws {
        let (model, capture, fixture) = makeMountedStateRecordWindow()
        defer { fixture.close() }
        try fixture.activate("record.install")
        fixture.flush()
        var raw = capture.raw
        var member = capture.member
        var element = capture.element
        capture.clearBindings()

        model.showsChild = false
        fixture.flush()
        capture.clearBindings()

        XCTAssertNotNil(capture.payload, "An external read handle legitimately retains its last mounted value")
        XCTAssertTrue(raw?.wrappedValue.payload === capture.payload)
        XCTAssertEqual(member?.wrappedValue, 0)
        XCTAssertEqual(element?.wrappedValue, 10)
        member = nil
        element = nil
        XCTAssertNotNil(raw?.wrappedValue.payload)
        XCTAssertNotNil(capture.payload)

        raw = nil

        XCTAssertNil(capture.payload, "No registry or external read handle owns the payload now")
    }

    func testClosedHostBindingsKeepTheirSnapshotAndRejectNewPayloadsWithoutInvalidation() async throws {
        let model = MountedStateTestModel()
        let capture = MountedStateBindingCapture()
        var fixture: MountedStateWindow? = MountedStateWindow(
            MountedStateParent(model: model) {
                MountedStateRecordOwner(capture: capture)
            })
        defer { fixture?.close() }
        try fixture?.activate("record.install")
        fixture?.flush()
        XCTAssertNotNil(capture.payload)
        var escaped = capture.raw
        capture.clearBindings()

        fixture?.close()
        let reloads = try XCTUnwrap(fixture?.host.executedReloadCount)

        XCTAssertEqual(escaped?.wrappedValue.items, [10])
        XCTAssertTrue(escaped?.wrappedValue.payload === capture.payload)
        attemptRetiredMountedStatePayloadWrite(try XCTUnwrap(escaped), capture: capture)
        XCTAssertNil(capture.rejectedPayload, "A retired binding must not store a newly supplied payload")
        XCTAssertEqual(escaped?.wrappedValue.items, [10])
        XCTAssertEqual(fixture?.host.executedReloadCount, reloads)
        await Task.yield()
        await Task.yield()
        fixture?.flush()
        XCTAssertEqual(fixture?.host.executedReloadCount, reloads)

        // The closed fixture may still own rendered callbacks. Drop those
        // before isolating the lifetime of the remaining external read handle.
        fixture = nil
        capture.clearBindings()
        XCTAssertNotNil(escaped?.wrappedValue.payload)
        XCTAssertNotNil(capture.payload)

        escaped = nil

        XCTAssertNil(capture.payload)
    }

    func testMountedStateBindingCarriesItsFullTransactionIntoARealOpacityTween() async throws {
        let model = MountedStateTestModel()
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.isContinuous = true
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                MountedStateAnimatedOwner(transaction: transaction)
            })
        defer { fixture.close() }
        let target = try fixture.node("animated.opacity")
        let startedAt = fixture.clock.now
        var transactions: [Transaction?] = []
        fixture.host.onReloadContentCompleted = { transactions.append(currentTransaction) }

        try fixture.activate("animated.toggle")

        try fixture.assertText("on", "animated.value")
        XCTAssertTrue(try fixture.node("animated.opacity") === target)
        let tween = try XCTUnwrap(target.animationStates[.opacity])
        XCTAssertEqual(tween.startValue, 1, accuracy: 0.0001)
        XCTAssertEqual(tween.endValue, 0.2, accuracy: 0.0001)
        XCTAssertEqual(tween.duration, 1, accuracy: 0.0001)
        XCTAssertEqual(tween.startTime, startedAt, accuracy: 0.0001)
        XCTAssertEqual(tween.easing, .linear)
        XCTAssertTrue(transactions.contains { $0?.animation?.duration == 1 && $0?.isContinuous == true })
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)

        fixture.present(at: startedAt + 0.5)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        fixture.present(at: startedAt + 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        model.revision += 1
        fixture.flush()
        try fixture.assertText("on", "animated.value")
    }

    func testMountedStateBindingExplicitNilTransactionSuppressesAnOuterAnimation() async throws {
        let model = MountedStateTestModel()
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        let fixture = MountedStateWindow(
            MountedStateParent(model: model) {
                MountedStateAnimatedOwner(transaction: transaction)
            })
        defer { fixture.close() }
        let target = try fixture.node("animated.opacity")
        var transactions: [Transaction?] = []
        fixture.host.onReloadContentCompleted = { transactions.append(currentTransaction) }

        try withAnimation(.linear(duration: 3)) {
            try fixture.activate("animated.toggle")
            XCTAssertEqual(currentTransaction?.animation?.duration, 3)
        }

        try fixture.assertText("on", "animated.value")
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertTrue(
            transactions.contains {
                $0 != nil && $0?.animation == nil && $0?.disablesAnimations == true && $0?.isContinuous == true
            })
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
        fixture.present(at: fixture.clock.now + 0.5)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }
}

@MainActor
private final class MountedStateTestModel: ObservableObject {
    @Published var revision = 0
    @Published var rows = [1, 2].map(MountedStateRowKey.init)
    @Published var showsChild = true
    @Published var firstBranch = true
    @Published var explicitID = 1
    @Published var usesStringID = false
    @Published var reversesReads = false
}

private struct MountedStateRowKey: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "shared" }
}

private struct MountedStateParent: View {
    @ObservedObject private var model: MountedStateTestModel
    private let content: @MainActor () -> [AnyView]

    init(model: MountedStateTestModel, @ViewBuilder content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: some View {
        let revision = model.revision
        return VStack(alignment: .leading, spacing: 8) {
            Text("Parent \(revision)")
                .accessibilityIdentifier("parent.revision")
            content()
        }
    }
}

private struct MountedStateCounter: View {
    @State private var count: Int
    let name: String

    init(name: String, seed: Int = 0) {
        self.name = name
        _count = State(initialValue: seed)
    }

    var body: some View {
        let value = count
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(value)).accessibilityIdentifier("\(name).value")
            Button("Increment \(name)") { count += 1 }
                .accessibilityIdentifier("\(name).increment")
        }
    }
}

@MainActor
private func mountedStateIdentified(_ source: MountedStateCounter, model: MountedStateTestModel) -> AnyView {
    if model.usesStringID {
        return AnyView(source.id(String(model.explicitID)))
    }
    return AnyView(source.id(model.explicitID))
}

@MainActor
private final class MountedStateProjectionCapture {
    var binding: Binding<Int>?
    var bodyBuilds = 0
}

private struct MountedStateProjectionOnly: View {
    @State private var value = 0
    let capture: MountedStateProjectionCapture

    var body: some View {
        let binding = $value
        capture.binding = binding
        capture.bodyBuilds += 1
        return Button("Increment projected binding") { binding.wrappedValue += 1 }
            .accessibilityIdentifier("projection.increment")
    }
}

private struct MountedStateDeclarationSlots: View {
    @State private var first = 3
    @State private var second = 30
    let reversesReads: Bool

    var body: some View {
        let values = reversesReads ? [second, first] : [first, second]
        let firstValue = values[reversesReads ? 1 : 0]
        let secondValue = values[reversesReads ? 0 : 1]
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(firstValue)).accessibilityIdentifier("slots.first")
            Text(String(secondValue)).accessibilityIdentifier("slots.second")
            Button("Increment first") { first += 1 }.accessibilityIdentifier("slots.first.increment")
            Button("Increment second") { second += 1 }.accessibilityIdentifier("slots.second.increment")
        }
    }
}

private final class MountedStateComputedReference {
    var value = 4
    var setterCalls = 0
}

private struct MountedStateComputedValue {
    let reference: MountedStateComputedReference

    var computed: Int {
        get { reference.value }
        set {
            reference.setterCalls += 1
            reference.value = newValue
        }
    }
}

@MainActor
private final class MountedStateComputedCapture {
    var binding: Binding<Int>?
    weak var reference: MountedStateComputedReference?
}

private struct MountedStateComputedOwner: View {
    @State private var value: MountedStateComputedValue
    let capture: MountedStateComputedCapture

    init(capture: MountedStateComputedCapture) {
        self.capture = capture
        _value = State(initialValue: MountedStateComputedValue(reference: MountedStateComputedReference()))
    }

    var body: some View {
        let binding = $value.computed
        let current = value.computed
        capture.binding = binding
        capture.reference = value.reference
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(current)).accessibilityIdentifier("computed.value")
            Button("Increment computed property") { binding.wrappedValue += 1 }
                .accessibilityIdentifier("computed.increment")
        }
    }
}

private final class MountedStatePayload {}

private struct MountedStateRecord {
    var value = 0
    var items: [Int] = []
    var payload: MountedStatePayload?
}

@MainActor
private final class MountedStateBindingCapture {
    var raw: Binding<MountedStateRecord>?
    var member: Binding<Int>?
    var element: Binding<Int>?
    weak var payload: MountedStatePayload?
    weak var rejectedPayload: MountedStatePayload?

    func clearBindings() {
        raw = nil
        member = nil
        element = nil
    }
}

private struct MountedStateRecordOwner: View {
    @State private var record = MountedStateRecord()
    let capture: MountedStateBindingCapture

    var body: some View {
        let binding = $record
        let current = record
        capture.raw = binding
        capture.member = binding.value
        capture.element = current.items.isEmpty ? nil : binding.items[0]
        let firstItem = current.items.first.map(String.init) ?? "none"
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(current.value)).accessibilityIdentifier("record.value")
            Text(firstItem).accessibilityIdentifier("record.first")
            Button("Increment record") { record.value += 1 }
                .accessibilityIdentifier("record.increment")
            Button("Increment first item") {
                guard !record.items.isEmpty else { return }
                record.items[0] += 1
            }
            .accessibilityIdentifier("record.increment-first")
            Button("Install payload and collection") {
                let payload = MountedStatePayload()
                capture.payload = payload
                var next = record
                next.payload = payload
                next.items = [10]
                record = next
            }
            .accessibilityIdentifier("record.install")
        }
    }
}

private struct MountedStateAnimatedOwner: View {
    @State private var isOn = false
    let transaction: Transaction

    var body: some View {
        let value = isOn
        return VStack(alignment: .leading, spacing: 4) {
            Toggle("Animated state", isOn: $isOn.transaction(transaction))
                .labelsHidden()
                .accessibilityIdentifier("animated.toggle")
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 24)
                .opacity(value ? 0.2 : 1)
                .accessibilityIdentifier("animated.opacity")
            Text(value ? "on" : "off").accessibilityIdentifier("animated.value")
        }
    }
}

@MainActor
private func makeMountedStateRecordWindow() -> (
    MountedStateTestModel, MountedStateBindingCapture, MountedStateWindow
) {
    let model = MountedStateTestModel()
    let capture = MountedStateBindingCapture()
    let fixture = MountedStateWindow(
        MountedStateParent(model: model) {
            if model.showsChild {
                MountedStateRecordOwner(capture: capture)
            }
        })
    return (model, capture, fixture)
}

@MainActor
private func replaceMountedStateRecordOwner(model: MountedStateTestModel, fixture: MountedStateWindow) {
    model.showsChild = false
    fixture.flush()
    model.showsChild = true
    fixture.flush()
}

@MainActor
private func attemptRetiredMountedStatePayloadWrite(
    _ binding: Binding<MountedStateRecord>, capture: MountedStateBindingCapture
) {
    let payload = MountedStatePayload()
    capture.rejectedPayload = payload
    binding.wrappedValue = MountedStateRecord(payload: payload)
}

@MainActor
private func mountedStateConfiguration<Content: View>(_ content: Content) -> WindowGroupConfiguration {
    WindowGroupConfiguration(
        title: "Mounted State", size: IntSize(width: 640, height: 640), clearColor: .black,
        content: [AnyView(content)])
}

@MainActor
private final class MountedStateWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    convenience init<Content: View>(_ content: Content) {
        self.init(configuration: mountedStateConfiguration(content))
    }

    init(configuration: WindowGroupConfiguration) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: configuration.size, scaleFactor: 1)
        let window = Win32Window(title: configuration.title, clientSize: configuration.size)
        let host = WinSwiftUIWindowHost(
            configuration: configuration, platformWindow: window,
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        self.clock = clock
        self.window = window
        self.host = host
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func flush() {
        for _ in 0..<2 { present(at: clock.now + 0.02) }
    }

    func present(at timestamp: Double) {
        clock.now = timestamp
        host.windowNeedsDisplay(window)
    }

    func close() { host.windowWillClose(window) }

    func contains(_ identifier: String) -> Bool {
        descendants(in: runtime.root).contains { $0.accessibilityIdentifier == identifier }
    }

    func node(
        _ identifier: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let root = try scope.map { try node($0, file: file, line: line) } ?? runtime.root
        let matches = descendants(in: root).filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node identified as \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func activate(_ identifier: String, within scope: String? = nil) throws {
        let identified = try node(identifier, within: scope)
        let control = try XCTUnwrap(descendants(in: identified).first { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(control)
        XCTAssertTrue(runtime.focusedNode === control)
        host.window(window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func assertText(
        _ expected: String, _ identifier: String, within scope: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let actual = try node(identifier, within: scope, file: file, line: line).text
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
