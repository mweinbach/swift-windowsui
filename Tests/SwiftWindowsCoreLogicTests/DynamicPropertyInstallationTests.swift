import SwiftWindowsCore
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class DynamicPropertyInstallationTests: XCTestCase {
    func testPrivateNestedDeclarationsInstallIntoACopyAndUpdateChildrenFirst() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let source = InstallationRoot(events: events)

        let installed = try harness.install(source)

        XCTAssertEqual(source.values, [1, 2, 3])
        XCTAssertEqual(source.updateCounts, [0, 0, 0, 0, 0])
        XCTAssertEqual(installed.updateCounts, [1, 1, 1, 1, 1])
        XCTAssertEqual(
            events.entries,
            [
                "install:first", "seed:first", "update:first", "install:second", "seed:second", "update:second",
                "install:nested", "seed:nested", "update:nested", "update:inner", "update:outer",
            ])
        XCTAssertEqual(Set(events.slots).count, 3)
        XCTAssertEqual(events.slots.map { $0.declaration.count }, [1, 1, 3])
        XCTAssertEqual(events.slots.map { $0.concreteTypes.count }, [2, 2, 4])

        let setter = installed.firstSetter
        XCTAssertTrue(setter(40), "A captured setter must work before any installed getter is read")
        XCTAssertEqual(installed.values, [40, 2, 3])
        XCTAssertEqual(source.values, [1, 2, 3])
    }

    func testRepeatedSourceValuesUseIndependentOwnersAndHosts() async throws {
        let first = try InstallationHarness()
        let second = try InstallationHarness()
        defer {
            first.close()
            second.close()
        }
        let source = InstallationRoot(events: InstallationEvents())
        let firstCopy = try first.install(source)
        let siblingOwner = try XCTUnwrap(first.epoch.owner(at: .init(segments: [.slot(1)])))
        let sibling = try DynamicPropertyInstaller.install(source, in: siblingOwner)
        let secondCopy = try second.install(source)
        first.commit()
        second.commit()

        XCTAssertTrue(firstCopy.firstSetter(10))
        XCTAssertTrue(sibling.firstSetter(20))
        XCTAssertTrue(secondCopy.firstSetter(30))

        XCTAssertEqual(firstCopy.values, [10, 2, 3])
        XCTAssertEqual(sibling.values, [20, 2, 3])
        XCTAssertEqual(secondCopy.values, [30, 2, 3])
        XCTAssertEqual(source.values, [1, 2, 3])
        XCTAssertEqual(first.invalidations, 2)
        XCTAssertEqual(second.invalidations, 1)
    }

    func testReconstructedSourceKeepsLocationsByDeclarationWithoutRepeatingSeeds() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let first = try harness.install(InstallationRoot(events: events))
        let originalSlots = events.slots
        harness.commit()
        XCTAssertTrue(first.firstSetter(90))
        try harness.beginNextBuild()

        let rebuilt = try harness.install(InstallationRoot(events: events, first: 999))

        XCTAssertEqual(rebuilt.values, [90, 2, 3])
        XCTAssertEqual(Array(events.slots.suffix(3)), originalSlots)
        XCTAssertEqual(events.entries.filter { $0.hasPrefix("seed:") }.count, 3)
        XCTAssertEqual(rebuilt.updateCounts, [1, 1, 1, 1, 1])
        XCTAssertTrue(rebuilt.firstSetter(91))
        XCTAssertEqual(first.values.first, 91)
    }

    func testPrivateExistentialCompositionAndAnyDeclarationsHaveTypedWriteback() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let source = InstallationErasedRoot(events: events)

        let installed = try harness.install(source)

        XCTAssertEqual(installed.updateCounts, [1, 1, 1])
        XCTAssertEqual(source.updateCounts, [0, 0, 0])
        XCTAssertEqual(Set(events.slots).count, 3)
        XCTAssertTrue(installed.setFirst(70))
        XCTAssertEqual(installed.values, [70, 5, 6])
        XCTAssertEqual(source.values, [4, 5, 6])
    }

    func testChangingAnExistentialConcreteTypeCreatesADistinctPropertySlot() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let first = try harness.install(
            InstallationPayloadRoot(property: InstallationLeaf<InstallationFirst>(1, "a", events)))
        let firstLeaf = try XCTUnwrap(first.property as? InstallationLeaf<InstallationFirst>)
        let firstSlot = try XCTUnwrap(events.slots.last)
        harness.commit()
        XCTAssertTrue(firstLeaf.setter(8))
        try harness.beginNextBuild()

        let replacement = try harness.install(
            InstallationPayloadRoot(property: InstallationLeaf<InstallationSecond>(2, "b", events)))
        let replacementLeaf = try XCTUnwrap(replacement.property as? InstallationLeaf<InstallationSecond>)
        let secondSlot = try XCTUnwrap(events.slots.last)
        harness.commit()

        XCTAssertEqual(firstSlot.declaration, secondSlot.declaration)
        XCTAssertNotEqual(firstSlot.concreteTypes, secondSlot.concreteTypes)
        XCTAssertEqual(replacementLeaf.value, 2)
        XCTAssertFalse(firstLeaf.setter(100))
        XCTAssertEqual(firstLeaf.value, 8, "Retired handles retain their last value")
        XCTAssertTrue(replacementLeaf.setter(9))
    }

    func testImmutableNestedDeclarationFailsBeforeAnyLeafOrUpdateEffect() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let source = InstallationInvalidRoot(
            first: InstallationLeaf<InstallationFirst>(1, "first", events),
            invalid: InstallationImmutableProperty(events: events))

        assertFailure(source, in: harness, reason: .immutableProperty)

        XCTAssertTrue(events.entries.isEmpty)
        XCTAssertTrue(events.slots.isEmpty)
    }

    func testClassAndEnumDynamicPropertiesFailBeforeEarlierValidSiblings() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        assertFailure(
            InstallationInvalidRoot(
                first: InstallationLeaf<InstallationFirst>(1, "first", events), invalid: InstallationReferenceProperty()
            ),
            in: harness, reason: .unsupportedValueKind)
        assertFailure(
            InstallationInvalidRoot(
                first: InstallationLeaf<InstallationFirst>(1, "first", events), invalid: InstallationEnumProperty.value),
            in: harness, reason: .unsupportedValueKind)
        assertFailure(InstallationReferenceRoot(), in: harness, reason: .unsupportedValueKind)

        XCTAssertTrue(events.entries.isEmpty)
    }

    func testOrdinaryOptionalAndAnyHashableContainersDoNotBecomeDynamicComposition() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        InstallationHashableProperty.updates = 0
        let events = InstallationEvents()
        let source = InstallationContainerRoot(events: events)

        let installed = try harness.install(source)
        _ = try harness.install(AnyHashable(InstallationHashableProperty(value: 10)))

        XCTAssertEqual(installed.leaf.updates, 1)
        XCTAssertEqual(installed.optional?.updates, 0)
        XCTAssertEqual((installed.erasedOptional as? InstallationLeaf<InstallationFirst>)?.updates, 0)
        XCTAssertEqual(InstallationHashableProperty.updates, 0)
        XCTAssertEqual(events.slots.count, 1)
        XCTAssertEqual(events.entries, ["install:direct", "seed:direct", "update:direct"])
    }

    func testOrdinaryStoredModelsClosuresAndWeakFieldsAreNotTraversed() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let reference = InstallationReferenceRoot()
        let source = InstallationOrdinaryRoot(events: events, reference: reference)

        let installed = try harness.install(source)

        XCTAssertEqual(installed.leaf.updates, 1)
        XCTAssertEqual(installed.child.leaf.updates, 0)
        XCTAssertTrue(installed.reference === reference)
        XCTAssertTrue(installed.weakReference === reference)
        XCTAssertEqual(events.slots.count, 1)
        XCTAssertEqual(installed.callback(), 12)
    }

    func testExplicitNonOwningLeafSkipsImplementationDetailsButUpdatesOnce() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let source = InstallationNonOwningProperty(events: events)

        let installed = try harness.install(source)

        XCTAssertEqual(installed.updates, 1)
        XCTAssertEqual(source.updates, 0)
        XCTAssertTrue(events.entries.isEmpty)
    }

    func testImmutableTrustedNoOpLeavesNeedNoWritebackOrOwningEffects() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let source = InstallationImmutableTrustedRoot(events: events)

        let installed = try harness.install(source)

        XCTAssertEqual(installed.values, [11, 11, 11])
        XCTAssertEqual(source.values, [11, 11, 11])
        XCTAssertTrue(events.entries.isEmpty)
        XCTAssertTrue(events.slots.isEmpty)
    }

    func testImmutableCustomUpdateOnlyPropertyStillFailsBeforeAnyEffects() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()
        let source = InstallationInvalidRoot(
            first: InstallationLeaf<InstallationFirst>(1, "first", events),
            invalid: InstallationImmutableUpdateOnlyRoot(events: events))

        assertFailure(source, in: harness, reason: .immutableProperty)

        XCTAssertTrue(events.entries.isEmpty)
        XCTAssertTrue(events.slots.isEmpty)
    }

    func testEmptyCustomPropertiesUpdateEachOccurrenceDespiteEqualKeyPaths() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        InstallationEmptyProperty.updates = 0

        _ = try harness.install(InstallationEmptyRoot())

        XCTAssertEqual(MemoryLayout<InstallationEmptyRoot>.size, 0)
        XCTAssertEqual(InstallationEmptyProperty.updates, 2)
    }

    func testEqualOwningDeclarationKeyPathsAreRejectedBeforeEffects() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        InstallationEmptyOwningProperty.installs = 0

        assertFailure(InstallationAmbiguousRoot(), in: harness, reason: .ambiguousPropertySlot)

        XCTAssertEqual(MemoryLayout<InstallationAmbiguousRoot>.size, 0)
        XCTAssertEqual(InstallationEmptyOwningProperty.installs, 0)
    }

    func testStoredVoidIsDiagnosedAsAmbiguousMetadataBeforeEffects() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()

        assertFailure(
            InstallationVoidRoot(leaf: InstallationLeaf<InstallationFirst>(1, "first", events)),
            in: harness, reason: .ambiguousFieldMetadata)

        XCTAssertTrue(events.entries.isEmpty)
    }

    func testOwnerCloseDuringASeedStopsBeforeUpdatesAndLaterLeaves() async throws {
        let harness = try InstallationHarness()
        let events = InstallationEvents()
        events.onSeed = { _ in harness.registry.close() }

        assertFailure(InstallationRoot(events: events), in: harness, reason: .ownerUnavailable)

        XCTAssertEqual(events.entries, ["install:first", "seed:first"])
        events.onSeed = nil
        harness.close()
        assertFailure(InstallationRoot(events: events), in: harness, reason: .ownerUnavailable)
    }

    func testOwnerCloseDuringUpdateStopsBeforeLaterLeaves() async throws {
        let harness = try InstallationHarness()
        let events = InstallationEvents()
        events.onUpdate = { _ in harness.registry.close() }

        assertFailure(InstallationRoot(events: events), in: harness, reason: .ownerUnavailable)

        XCTAssertEqual(events.entries, ["install:first", "seed:first", "update:first"])
        events.onUpdate = nil
        harness.close()
    }

    func testRestartingTheEpochCannotResumeAnOlderInstallationForTheSameLiveOwner() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        _ = try harness.install(InstallationRoot(events: InstallationEvents()))
        harness.commit()
        try harness.beginNextBuild()
        let events = InstallationEvents()
        let originalEpoch = harness.epoch
        var restarted: StateMountEpoch?
        events.onUpdate = { _ in
            originalEpoch.abort()
            restarted = harness.registry.beginRootBuild()
            XCTAssertTrue(restarted?.owner(at: harness.owner.identity) === harness.owner)
        }

        assertFailure(InstallationRoot(events: events), in: harness, reason: .ownerUnavailable)

        XCTAssertEqual(events.entries, ["install:first", "update:first"])
        XCTAssertTrue(
            harness.owner.isInstallationActive, "The new epoch is valid but must not continue the old adapter")
        events.onUpdate = nil
        restarted?.abort()
    }

    func testCustomUpdateCanWriteItsInstalledValueWithoutReplacingTheDeclaration() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()

        let installed = try harness.install(InstallationMutatingProperty(events: events, mutation: .writeValue))

        XCTAssertEqual(installed.value, 99)
        XCTAssertEqual(installed.updates, 1)
        XCTAssertEqual(events.slots.count, 1)
    }

    func testCustomUpdateCannotReplaceASameTypeOrDifferentTypeOwningDeclaration() async throws {
        for mutation in [InstallationMutation.replaceSameType, .replaceDifferentType, .remove] {
            let harness = try InstallationHarness()
            defer { harness.close() }
            let events = InstallationEvents()
            assertFailure(
                InstallationMutatingProperty(events: events, mutation: mutation),
                in: harness, reason: .mutatedDynamicProperty)
            XCTAssertEqual(events.slots.count, 1)
            XCTAssertEqual(events.entries.filter { $0.hasPrefix("seed:") }.count, 1)
        }
    }

    func testCustomUpdateCannotIntroduceAnOwningPropertyIntoAnOrdinaryAnyField() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()

        assertFailure(InstallationIntroducedProperty(events: events), in: harness, reason: .mutatedDynamicProperty)

        XCTAssertTrue(events.entries.isEmpty)
    }

    func testCustomUpdateCannotBorrowAnInstalledLeafFromAnotherOwnerOrDeclaration() async throws {
        let donor = try InstallationHarness()
        let target = try InstallationHarness()
        let swapped = try InstallationHarness()
        defer {
            donor.close()
            target.close()
            swapped.close()
        }
        let installed = try donor.install(InstallationLeaf<InstallationFirst>(7, "donor", InstallationEvents()))
        donor.commit()

        assertFailure(
            InstallationBorrowedProperty(events: InstallationEvents(), borrowed: installed),
            in: target, reason: .mutatedDynamicProperty)
        assertFailure(
            InstallationSwappedProperty(events: InstallationEvents()),
            in: swapped, reason: .mutatedDynamicProperty)

        XCTAssertTrue(installed.setter(8), "Rejected borrowing must not revoke the unrelated live owner")
        XCTAssertEqual(installed.value, 8)
    }

    func testAnAncestorUpdateCannotReplaceANestedCustomWrapperWithUninstalledChildren() async throws {
        let harness = try InstallationHarness()
        defer { harness.close() }
        let events = InstallationEvents()

        assertFailure(InstallationReplacedNestedProperty(events: events), in: harness, reason: .mutatedDynamicProperty)

        XCTAssertEqual(events.slots.count, 1)
        XCTAssertEqual(events.entries, ["install:nested", "seed:nested", "update:nested", "update:inner"])
    }

    func testCachedMetadataDoesNotRetainSourceValuesOrMountOwners() async throws {
        weak var recordedEvents: InstallationEvents?
        weak var recordedOwner: StateMountOwner?
        weak var recordedRegistry: StateMountRegistry?
        do {
            let harness = try InstallationHarness()
            let events = InstallationEvents()
            recordedEvents = events
            recordedOwner = harness.owner
            recordedRegistry = harness.registry
            _ = try harness.install(InstallationRoot(events: events))
            harness.commit()
            harness.close()
        }

        XCTAssertNil(recordedEvents)
        XCTAssertNil(recordedOwner)
        XCTAssertNil(recordedRegistry)
    }

    private func assertFailure<Root>(
        _ source: Root, in harness: InstallationHarness, reason: DynamicPropertyInstallationError.Reason,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            _ = try harness.install(source)
            XCTFail("Expected installation to fail with \(reason)", file: file, line: line)
        } catch let error as DynamicPropertyInstallationError {
            XCTAssertEqual(error.reason, reason, error.description, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

@MainActor
private final class InstallationHarness {
    let registry: StateMountRegistry
    var epoch: StateMountEpoch
    var owner: StateMountOwner
    private let counter: InstallationInvalidations
    var invalidations: Int { counter.count }

    init() throws {
        let counter = InstallationInvalidations()
        self.counter = counter
        registry = StateMountRegistry(invalidate: { counter.count += 1 })
        epoch = try XCTUnwrap(registry.beginRootBuild())
        owner = try XCTUnwrap(epoch.owner(at: .init()))
    }

    func install<Root>(_ source: Root) throws -> Root {
        try DynamicPropertyInstaller.install(source, in: owner)
    }

    func commit() {
        XCTAssertTrue(epoch.prepareForAdoption())
        epoch.commitAdoption()
        registry.finishPendingRetirements()
    }

    func beginNextBuild() throws {
        epoch = try XCTUnwrap(registry.beginRootBuild())
        let nextOwner = try XCTUnwrap(epoch.owner(at: owner.identity))
        XCTAssertTrue(nextOwner === owner)
        owner = nextOwner
    }

    func close() {
        registry.close()
        epoch.abort()
    }
}

@MainActor
private final class InstallationInvalidations {
    var count = 0
}

@MainActor
private final class InstallationEvents {
    var entries: [String] = []
    var slots: [StatePropertySlot] = []
    var onSeed: ((String) -> Void)?
    var onUpdate: ((String) -> Void)?
}

private enum InstallationFirst {}
private enum InstallationSecond {}
private protocol InstallationExtra {}

@MainActor
private struct InstallationLeaf<Tag>: MountedDynamicProperty, InstallationExtra {
    private let seed: Int
    private let name: String
    private let events: InstallationEvents
    private var cell: MountedStateCell<Int>?
    private(set) var updates = 0

    init(_ seed: Int, _ name: String, _ events: InstallationEvents) {
        self.seed = seed
        self.name = name
        self.events = events
    }

    var value: Int {
        if let cell { return cell.readValue() }
        return seed
    }

    var setter: (Int) -> Bool { { value in cell?.write(value) ?? false } }

    mutating func install(in owner: StateMountOwner, at slot: StatePropertySlot) {
        events.entries.append("install:\(name)")
        events.slots.append(slot)
        cell = owner.resolve(at: slot) {
            events.entries.append("seed:\(name)")
            events.onSeed?(name)
            return seed
        }
    }

    func isInstalled(in owner: StateMountOwner, at slot: StatePropertySlot) -> Bool {
        guard let cell else { return false }
        return owner.isInstalled(cell: cell, at: slot)
    }

    nonisolated mutating func update() {
        updates += 1
        MainActor.assumeIsolated {
            events.entries.append("update:\(name)")
            events.onUpdate?(name)
        }
    }
}

@MainActor
private struct InstallationInner: DynamicProperty {
    private var leaf: InstallationLeaf<InstallationFirst>
    private let events: InstallationEvents
    private(set) var updates = 0
    var value: Int { leaf.value }
    var leafUpdates: Int { leaf.updates }

    init(events: InstallationEvents) {
        leaf = InstallationLeaf(3, "nested", events)
        self.events = events
    }

    nonisolated mutating func update() {
        updates += 1
        MainActor.assumeIsolated { events.entries.append("update:inner") }
    }
}

@MainActor
private struct InstallationOuter: DynamicProperty {
    private var inner: InstallationInner
    private let events: InstallationEvents
    private(set) var updates = 0
    var value: Int { inner.value }
    var updateCounts: [Int] { [inner.leafUpdates, inner.updates, updates] }

    init(events: InstallationEvents) {
        inner = InstallationInner(events: events)
        self.events = events
    }

    nonisolated mutating func update() {
        updates += 1
        MainActor.assumeIsolated { events.entries.append("update:outer") }
    }
}

@MainActor
private struct InstallationRoot {
    private var first: InstallationLeaf<InstallationFirst>
    private var second: InstallationLeaf<InstallationFirst>
    private var outer: InstallationOuter

    init(events: InstallationEvents, first: Int = 1) {
        self.first = InstallationLeaf(first, "first", events)
        second = InstallationLeaf(2, "second", events)
        outer = InstallationOuter(events: events)
    }

    var values: [Int] { [first.value, second.value, outer.value] }
    var updateCounts: [Int] { [first.updates, second.updates] + outer.updateCounts }
    var firstSetter: (Int) -> Bool { first.setter }
}

@MainActor
private struct InstallationErasedRoot {
    private var erased: any DynamicProperty
    private var composition: any DynamicProperty & InstallationExtra
    private var anything: Any

    init(events: InstallationEvents) {
        erased = InstallationLeaf<InstallationFirst>(4, "erased", events)
        composition = InstallationLeaf<InstallationFirst>(5, "composition", events)
        anything = InstallationLeaf<InstallationFirst>(6, "anything", events)
    }

    private var leaves: [InstallationLeaf<InstallationFirst>] {
        [erased, composition, anything].compactMap { $0 as? InstallationLeaf<InstallationFirst> }
    }
    var values: [Int] { leaves.map(\.value) }
    var updateCounts: [Int] { leaves.map(\.updates) }
    func setFirst(_ value: Int) -> Bool { leaves.first?.setter(value) ?? false }
}

private struct InstallationPayloadRoot {
    var property: any DynamicProperty
}

@MainActor
private struct InstallationInvalidRoot<Invalid> {
    var first: InstallationLeaf<InstallationFirst>
    var invalid: Invalid
}

@MainActor
private struct InstallationImmutableProperty: DynamicProperty {
    private let leaf: InstallationLeaf<InstallationFirst>
    init(events: InstallationEvents) { leaf = InstallationLeaf(2, "immutable", events) }
}

private final class InstallationReferenceProperty: DynamicProperty {}
private final class InstallationReferenceRoot {}
private enum InstallationEnumProperty: DynamicProperty { case value }

private struct InstallationHashableProperty: DynamicProperty, Hashable {
    var value: Int
    @MainActor static var updates = 0

    mutating func update() {
        MainActor.assumeIsolated { Self.updates += 1 }
    }
}

@MainActor
private struct InstallationContainerRoot {
    var leaf: InstallationLeaf<InstallationFirst>
    var optional: InstallationLeaf<InstallationFirst>?
    var absent: InstallationLeaf<InstallationFirst>?
    var erasedOptional: Any
    var hashable: AnyHashable
    var erasedHashable: Any

    init(events: InstallationEvents) {
        leaf = InstallationLeaf(1, "direct", events)
        optional = InstallationLeaf(2, "optional", events)
        erasedOptional = Optional(InstallationLeaf<InstallationFirst>(3, "erasedOptional", events)) as Any
        hashable = AnyHashable(InstallationHashableProperty(value: 4))
        erasedHashable = AnyHashable(InstallationHashableProperty(value: 5))
    }
}

@MainActor
private struct InstallationOrdinaryRoot {
    struct Child {
        var leaf: InstallationLeaf<InstallationFirst>
    }

    var leaf: InstallationLeaf<InstallationFirst>
    var child: Child
    let reference: InstallationReferenceRoot
    weak var weakReference: InstallationReferenceRoot?
    let callback: () -> Int = { 12 }

    init(events: InstallationEvents, reference: InstallationReferenceRoot) {
        leaf = InstallationLeaf(1, "direct", events)
        child = Child(leaf: InstallationLeaf(2, "child", events))
        self.reference = reference
        weakReference = reference
    }
}

@MainActor
private struct InstallationNonOwningProperty: NonOwningDynamicProperty {
    private let implementation: InstallationImmutableProperty
    private(set) var updates = 0
    init(events: InstallationEvents) { implementation = InstallationImmutableProperty(events: events) }
    nonisolated mutating func update() { updates += 1 }
}

@MainActor
private struct InstallationTrustedNoOpProperty: NonOwningDynamicProperty, InstallationExtra {
    private let implementation: InstallationLeaf<InstallationFirst>
    var value: Int { implementation.value }

    init(events: InstallationEvents) {
        implementation = InstallationLeaf(11, "implementation", events)
    }
}

@MainActor
private struct InstallationImmutableTrustedRoot {
    private let plain: InstallationTrustedNoOpProperty
    private let erased: any DynamicProperty & InstallationExtra
    private let anything: Any

    init(events: InstallationEvents) {
        plain = InstallationTrustedNoOpProperty(events: events)
        erased = InstallationTrustedNoOpProperty(events: events)
        anything = InstallationTrustedNoOpProperty(events: events)
    }

    var values: [Int] {
        [plain, erased, anything].compactMap { ($0 as? InstallationTrustedNoOpProperty)?.value }
    }
}

@MainActor
private struct InstallationUpdateOnlyProperty: DynamicProperty {
    private let events: InstallationEvents
    init(events: InstallationEvents) { self.events = events }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { events.entries.append("update:immutableCustom") }
    }
}

@MainActor
private struct InstallationImmutableUpdateOnlyRoot: DynamicProperty {
    private let property: InstallationUpdateOnlyProperty
    init(events: InstallationEvents) { property = InstallationUpdateOnlyProperty(events: events) }
}

private struct InstallationEmptyProperty: DynamicProperty {
    @MainActor static var updates = 0
    mutating func update() { MainActor.assumeIsolated { Self.updates += 1 } }
}

private struct InstallationEmptyRoot {
    var first = InstallationEmptyProperty()
    var second = InstallationEmptyProperty()
}

@MainActor
private struct InstallationEmptyOwningProperty: MountedDynamicProperty {
    static var installs = 0
    mutating func install(in owner: StateMountOwner, at slot: StatePropertySlot) { Self.installs += 1 }
    func isInstalled(in owner: StateMountOwner, at slot: StatePropertySlot) -> Bool { false }
}

@MainActor
private struct InstallationAmbiguousRoot {
    var first = InstallationEmptyOwningProperty()
    var second = InstallationEmptyOwningProperty()
}

@MainActor
private struct InstallationVoidRoot {
    var leaf: InstallationLeaf<InstallationFirst>
    var ambiguous: Void = ()
}

private enum InstallationMutation {
    case writeValue
    case replaceSameType
    case replaceDifferentType
    case remove
}

@MainActor
private struct InstallationMutatingProperty: DynamicProperty {
    private var property: Any
    private let events: InstallationEvents
    private let mutation: InstallationMutation
    private(set) var updates = 0
    var value: Int? { (property as? InstallationLeaf<InstallationFirst>)?.value }

    init(events: InstallationEvents, mutation: InstallationMutation) {
        property = InstallationLeaf<InstallationFirst>(1, "original", events)
        self.events = events
        self.mutation = mutation
    }

    nonisolated mutating func update() {
        updates += 1
        MainActor.assumeIsolated {
            switch mutation {
            case .writeValue:
                _ = (property as? InstallationLeaf<InstallationFirst>)?.setter(99)
            case .replaceSameType:
                property = InstallationLeaf<InstallationFirst>(2, "replacement", events)
            case .replaceDifferentType:
                property = InstallationLeaf<InstallationSecond>(2, "replacement", events)
            case .remove:
                property = 0
            }
        }
    }
}

@MainActor
private struct InstallationIntroducedProperty: DynamicProperty {
    private var property: Any = 0
    private let events: InstallationEvents
    init(events: InstallationEvents) { self.events = events }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { property = InstallationLeaf<InstallationFirst>(1, "introduced", events) }
    }
}

@MainActor
private struct InstallationBorrowedProperty: DynamicProperty {
    private struct Donor {
        let leaf: InstallationLeaf<InstallationFirst>
    }

    private var property: InstallationLeaf<InstallationFirst>
    private let donor: Donor

    init(events: InstallationEvents, borrowed: InstallationLeaf<InstallationFirst>) {
        property = InstallationLeaf(1, "target", events)
        donor = Donor(leaf: borrowed)
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { property = donor.leaf }
    }
}

@MainActor
private struct InstallationSwappedProperty: DynamicProperty {
    private var first: InstallationLeaf<InstallationFirst>
    private var second: InstallationLeaf<InstallationFirst>

    init(events: InstallationEvents) {
        first = InstallationLeaf(1, "first", events)
        second = InstallationLeaf(2, "second", events)
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { swap(&first, &second) }
    }
}

@MainActor
private struct InstallationReplacedNestedProperty: DynamicProperty {
    private var inner: InstallationInner
    private let events: InstallationEvents

    init(events: InstallationEvents) {
        inner = InstallationInner(events: events)
        self.events = events
    }

    nonisolated mutating func update() {
        MainActor.assumeIsolated { inner = InstallationInner(events: events) }
    }
}
