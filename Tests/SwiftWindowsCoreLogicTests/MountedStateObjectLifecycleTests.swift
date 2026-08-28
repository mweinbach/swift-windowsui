import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Object construction and ownership follow the installed declaration, not each authored view value.
@MainActor
final class MountedStateObjectLifecycleTests: XCTestCase {
    func testFactoryWaitsForMountAndFreshChildRebuildsKeepTheFirstObjectAndSeed() async throws {
        let recorder = ObjectLifetimeRecorder()
        let source = ObjectLifetimeCounter(name: "lazy", seed: 10, recorder: recorder)
        let configuration = objectLifetimeConfiguration(source)
        XCTAssertEqual(recorder.factoryCount, 0, "Neither authoring nor erasing the view invokes its factory")
        var initial: ObjectLifetimeWindow? = ObjectLifetimeWindow(configuration: configuration)
        defer { initial?.close() }
        XCTAssertEqual(recorder.seeds, [10])
        try initial?.assertText("10", "lazy.value")
        initial?.close()
        initial = nil

        let driver = ObjectLifetimeDriver()
        let capture = ObjectLifetimeCapture()
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeParent(model: driver) {
                ObjectLifetimeCounter(name: "fresh", seed: driver.revision + 20, recorder: recorder, capture: capture)
            })
        defer { fixture.close() }
        let original = try XCTUnwrap(capture.model)
        let originalNode = try fixture.node("fresh.value")
        XCTAssertEqual(recorder.seeds, [10, 20])

        try fixture.activate("fresh.increment")
        fixture.flush()
        driver.revision = 100
        fixture.flush()

        XCTAssertTrue(capture.model === original)
        XCTAssertTrue(try fixture.node("fresh.value") === originalNode)
        XCTAssertEqual(recorder.seeds, [10, 20], "A new initializer input does not replace an existing owner")
        try fixture.assertText("21", "fresh.value")
        try fixture.activate("fresh.increment")
        fixture.flush()
        try fixture.assertText("22", "fresh.value")
    }

    func testPrivateDeclarationSlotsKeepSeparateObjectsWhenReadOrderAndSeedsChange() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeParent(model: driver) {
                ObjectLifetimeSlots(
                    recorder: recorder, seedOffset: driver.revision, reversesReads: driver.reversesReads)
            })
        defer { fixture.close() }
        XCTAssertEqual(recorder.seeds.sorted(), [3, 30])
        try fixture.activate("slots.first.increment")
        try fixture.activate("slots.second.increment")
        try fixture.activate("slots.second.increment")
        fixture.flush()

        driver.revision = 100
        driver.reversesReads = true
        fixture.flush()

        XCTAssertEqual(recorder.factoryCount, 2)
        try fixture.assertText("4", "slots.first")
        try fixture.assertText("32", "slots.second")
        try fixture.activate("slots.first.increment")
        fixture.flush()
        try fixture.assertText("5", "slots.first")
        try fixture.assertText("32", "slots.second")
    }

    func testReusingOneSourceForTwoSiblingsCreatesIndependentObjects() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let source = ObjectLifetimeCounter(name: "shared", recorder: recorder)
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeParent(model: driver) {
                source.accessibilityIdentifier("left")
                source.accessibilityIdentifier("right")
            })
        defer { fixture.close() }
        XCTAssertEqual(recorder.factoryCount, 2)
        let firstObject = try XCTUnwrap(recorder.instances.first?.value)
        let secondObject = try XCTUnwrap(recorder.instances.dropFirst().first?.value)
        XCTAssertFalse(firstObject === secondObject)

        try fixture.activate("shared.increment", within: "left")
        try fixture.activate("shared.increment", within: "right")
        try fixture.activate("shared.increment", within: "right")
        driver.revision += 1
        fixture.flush()

        try fixture.assertText("1", "shared.value", within: "left")
        try fixture.assertText("2", "shared.value", within: "right")
        XCTAssertEqual(recorder.factoryCount, 2)
    }

    func testReusingOneConfigurationAcrossHostsCreatesIndependentObjectsAndSubscriptions() async throws {
        let recorder = ObjectLifetimeRecorder()
        let configuration = objectLifetimeConfiguration(ObjectLifetimeCounter(name: "shared", recorder: recorder))
        let first = ObjectLifetimeWindow(configuration: configuration)
        defer { first.close() }
        try first.activate("shared.increment")
        first.flush()
        let second = ObjectLifetimeWindow(configuration: configuration)
        defer { second.close() }
        XCTAssertEqual(recorder.factoryCount, 2)
        let firstObject = try XCTUnwrap(recorder.instances.first?.value)
        let secondObject = try XCTUnwrap(recorder.instances.dropFirst().first?.value)
        XCTAssertFalse(firstObject === secondObject)
        try second.assertText("0", "shared.value")
        let secondReloads = second.host.executedReloadCount

        try first.activate("shared.increment")
        first.flush()
        second.flush()

        try first.assertText("2", "shared.value")
        try second.assertText("0", "shared.value")
        XCTAssertEqual(second.host.executedReloadCount, secondReloads)
        first.close()
        try second.activate("shared.increment")
        second.flush()
        try second.assertText("1", "shared.value")
        XCTAssertEqual(recorder.factoryCount, 2)
    }

    func testKeyedReorderKeepsSurvivorsAndReinsertionConstructsANewObject() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeParent(model: driver) {
                ForEach(driver.rows, id: \.self) { row in
                    ObjectLifetimeCounter(name: "row.\(row.value)", recorder: recorder)
                }
            })
        defer { fixture.close() }
        try fixture.activate("row.1.increment")
        try fixture.activate("row.1.increment")
        try fixture.activate("row.2.increment")
        fixture.flush()
        let firstNode = try fixture.node("row.1.value")
        let secondNode = try fixture.node("row.2.value")
        XCTAssertEqual(recorder.factoryCount, 2)

        driver.rows = [2, 3, 1].map(ObjectLifetimeRowKey.init)
        fixture.flush()

        XCTAssertEqual(recorder.factoryCount, 3)
        try fixture.assertText("2", "row.1.value")
        try fixture.assertText("1", "row.2.value")
        try fixture.assertText("0", "row.3.value")
        XCTAssertTrue(try fixture.node("row.1.value") === firstNode)
        XCTAssertTrue(try fixture.node("row.2.value") === secondNode)
        driver.rows = [2, 3].map(ObjectLifetimeRowKey.init)
        fixture.flush()
        driver.rows = [1, 2, 3].map(ObjectLifetimeRowKey.init)
        fixture.flush()

        XCTAssertEqual(recorder.factoryCount, 4)
        try fixture.assertText("0", "row.1.value")
        try fixture.assertText("1", "row.2.value")
        XCTAssertFalse(try fixture.node("row.1.value") === firstNode)
        XCTAssertTrue(try fixture.node("row.2.value") === secondNode)
    }

    func testExplicitIDValueAndTypeChangesConstructNewObjectsWithoutChangingTheSource() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let source = ObjectLifetimeCounter(name: "identified", recorder: recorder)
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeParent(model: driver) {
                objectLifetimeIdentified(source, driver: driver)
            })
        defer { fixture.close() }
        try fixture.activate("identified.increment")
        fixture.flush()
        driver.revision += 1
        fixture.flush()
        try fixture.assertText("1", "identified.value")
        XCTAssertEqual(recorder.factoryCount, 1)

        driver.explicitID = 2
        fixture.flush()
        try fixture.assertText("0", "identified.value")
        XCTAssertEqual(recorder.factoryCount, 2)
        try fixture.activate("identified.increment")
        fixture.flush()
        driver.usesStringID = true
        fixture.flush()

        try fixture.assertText("0", "identified.value")
        XCTAssertEqual(recorder.factoryCount, 3, "An Int ID and a String with the same description are different IDs")
    }

    func testConditionalBranchesRetireTheirObjectsWithoutResettingTheFollowingSibling() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeParent(model: driver) {
                if driver.firstBranch {
                    ObjectLifetimeCounter(name: "branch", seed: 10, recorder: recorder)
                } else {
                    ObjectLifetimeCounter(name: "branch", seed: 20, recorder: recorder)
                }
                ObjectLifetimeCounter(name: "following", recorder: recorder)
            })
        defer { fixture.close() }
        try fixture.activate("branch.increment")
        try fixture.activate("following.increment")
        fixture.flush()
        driver.firstBranch = false
        fixture.flush()

        try fixture.assertText("20", "branch.value")
        try fixture.assertText("1", "following.value")
        XCTAssertEqual(recorder.factoryCount, 3)
        try fixture.activate("branch.increment")
        fixture.flush()
        driver.firstBranch = true
        fixture.flush()

        try fixture.assertText("10", "branch.value")
        try fixture.assertText("1", "following.value")
        XCTAssertEqual(recorder.factoryCount, 4)
    }

    func testUnmountedCacheAndCopyLocalSetterDoNotBecomeTheMountedObject() async throws {
        let recorder = ObjectLifetimeRecorder()
        let source = StateObject(wrappedValue: recorder.make(seed: 3))
        XCTAssertEqual(recorder.factoryCount, 0)
        let fallback = source.wrappedValue
        XCTAssertTrue(source.wrappedValue === fallback)
        XCTAssertEqual(recorder.factoryCount, 1)
        var copy = source
        let replacement = ObjectLifetimeModel(value: 99)

        copy.wrappedValue = replacement

        XCTAssertTrue(source.wrappedValue === fallback, "The public setter must not retarget another source copy")
        XCTAssertTrue(copy.wrappedValue === replacement)
        let capture = ObjectLifetimeCapture()
        let fixture = ObjectLifetimeWindow(ObjectLifetimeCounter(name: "cached", storage: source, capture: capture))
        defer { fixture.close() }
        XCTAssertEqual(recorder.seeds, [3, 3])
        XCTAssertFalse(try XCTUnwrap(capture.model) === fallback)
        try fixture.activate("cached.increment")
        fixture.flush()

        try fixture.assertText("4", "cached.value")
        XCTAssertEqual(fallback.value, 3)
        XCTAssertEqual(copy.wrappedValue.value, 99)
        XCTAssertEqual(recorder.factoryCount, 2)
    }

    func testFactoriesReturningOneExternalInstanceIntentionallyShareItsOrdinaryReference() async throws {
        let object = ObjectLifetimeModel(value: 4)
        let configuration = objectLifetimeConfiguration(
            ObjectLifetimeCounter(name: "aliased", storage: StateObject(wrappedValue: object)))
        let first = ObjectLifetimeWindow(configuration: configuration)
        defer { first.close() }
        let second = ObjectLifetimeWindow(configuration: configuration)
        defer { second.close() }

        try first.activate("aliased.increment")
        first.flush()
        second.flush()

        XCTAssertEqual(object.value, 5)
        try first.assertText("5", "aliased.value")
        try second.assertText("5", "aliased.value")
        first.close()
        try second.activate("aliased.increment")
        second.flush()
        XCTAssertEqual(object.value, 6)
        try second.assertText("6", "aliased.value")
    }

    func testRemovalReleasesRegistryOnlyOwnershipWhileTheHostRemainsLive() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let capture = ObjectLifetimeCapture()
        let fixture = objectLifetimeConditionalWindow(recorder: recorder, driver: driver, capture: capture)
        defer { fixture.close() }
        try fixture.activate("owned.increment")
        fixture.flush()
        let first = try XCTUnwrap(recorder.instances.first)
        XCTAssertNotNil(first.value)
        capture.clearBindings()

        driver.showsChild = false
        fixture.flush()
        capture.clearBindings()

        XCTAssertFalse(fixture.contains("owned.value"))
        XCTAssertNil(first.value, "Neither the registry nor the factory retains a retired object")
        driver.showsChild = true
        fixture.flush()
        XCTAssertEqual(recorder.factoryCount, 2)
        try fixture.assertText("0", "owned.value")
        XCTAssertNotNil(capture.model)
    }

    func testEscapedMemberBindingRetainsARemovedObjectOnlyUntilThatBindingIsReleased() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let capture = ObjectLifetimeCapture()
        let fixture = objectLifetimeConditionalWindow(recorder: recorder, driver: driver, capture: capture)
        defer { fixture.close() }
        try fixture.activate("owned.increment")
        fixture.flush()
        let object = try XCTUnwrap(recorder.instances.first)
        var escaped = capture.member
        XCTAssertNotNil(escaped)
        capture.clearBindings()

        driver.showsChild = false
        fixture.flush()
        capture.clearBindings()

        XCTAssertFalse(fixture.contains("owned.value"))
        XCTAssertNotNil(object.value)
        XCTAssertEqual(escaped?.wrappedValue, 1)
        escaped?.wrappedValue = 99
        XCTAssertEqual(escaped?.wrappedValue, 1)
        escaped = nil
        XCTAssertNil(object.value, "The still-live host no longer owns the removed cell")

        driver.showsChild = true
        fixture.flush()
        try fixture.assertText("0", "owned.value")
        XCTAssertEqual(recorder.factoryCount, 2)
        XCTAssertNil(object.value)
    }

    func testCloseAndHostDeinitializationReleaseObjectsAfterRenderedCallbacksAreDropped() async throws {
        for closesExplicitly in [true, false] {
            let recorder = ObjectLifetimeRecorder()
            var fixture: ObjectLifetimeWindow? = ObjectLifetimeWindow(
                ObjectLifetimeCounter(name: "owned", recorder: recorder))
            weak var releasedHost = fixture?.host
            let object = try XCTUnwrap(recorder.instances.first)
            XCTAssertNotNil(object.value)
            try fixture?.activate("owned.increment")
            fixture?.flush()
            if closesExplicitly { fixture?.close() }

            // A closed runtime can still contain rendered callbacks. Release
            // that whole fixture before isolating registry ownership.
            fixture = nil

            XCTAssertNil(releasedHost)
            XCTAssertNil(object.value, "No application read handle escaped this host")
        }
    }

    func testEscapedMemberBindingsKeepLastObjectsAfterCloseButDoNotKeepTheirHostsAlive() async throws {
        for closesExplicitly in [true, false] {
            let recorder = ObjectLifetimeRecorder()
            let capture = ObjectLifetimeCapture()
            var fixture: ObjectLifetimeWindow? = ObjectLifetimeWindow(
                ObjectLifetimeCounter(name: "owned", seed: 8, recorder: recorder, capture: capture))
            weak var releasedHost = fixture?.host
            try fixture?.activate("owned.increment")
            fixture?.flush()
            let object = try XCTUnwrap(recorder.instances.first)
            var escaped = capture.member
            XCTAssertNotNil(escaped)
            capture.clearBindings()
            if closesExplicitly { fixture?.close() }
            fixture = nil
            capture.clearBindings()

            XCTAssertNil(releasedHost)
            XCTAssertNotNil(object.value, "The escaped binding owns a last-object read handle")
            XCTAssertEqual(escaped?.wrappedValue, 9)
            let setterCalls = object.value?.valueSetterCalls
            escaped?.wrappedValue = 99
            XCTAssertEqual(object.value?.valueSetterCalls, setterCalls)
            XCTAssertEqual(escaped?.wrappedValue, 9)

            escaped = nil

            XCTAssertNil(object.value, "Releasing the last read handle releases the object")
        }
    }

    func testRetiredRawMemberAndCollectionProjectionsRejectWritesBeforeApplicationAccessors() async throws {
        let recorder = ObjectLifetimeRecorder()
        let driver = ObjectLifetimeDriver()
        let capture = ObjectLifetimeCapture()
        let fixture = objectLifetimeConditionalWindow(recorder: recorder, driver: driver, capture: capture)
        defer { fixture.close() }
        try fixture.activate("owned.increment")
        try fixture.activate("owned.increment")
        try fixture.activate("owned.increment-first")
        fixture.flush()
        var raw = try XCTUnwrap(capture.raw)
        let member = try XCTUnwrap(capture.member).animation(.linear(duration: 1))
        let record = try XCTUnwrap(capture.record)
        let nested = try XCTUnwrap(capture.nestedMember).transaction(Transaction(animation: nil))
        let element = try XCTUnwrap(capture.element).animation(nil)
        let oldObject = raw.wrappedValue
        capture.clearBindings()
        driver.showsChild = false
        fixture.flush()
        driver.revision = 100
        driver.showsChild = true
        fixture.flush()
        let replacement = try XCTUnwrap(capture.model)
        XCTAssertFalse(replacement === oldObject)
        try fixture.assertText("100", "owned.value")
        XCTAssertTrue(raw.wrappedValue === oldObject)
        XCTAssertEqual(member.wrappedValue, 2)
        XCTAssertEqual(record.wrappedValue.items, [11])
        XCTAssertEqual(nested.wrappedValue, 0)
        XCTAssertEqual(element.wrappedValue, 11)
        let valueGets = oldObject.valueGetterCalls
        let valueSets = oldObject.valueSetterCalls
        let recordGets = oldObject.recordGetterCalls
        let recordSets = oldObject.recordSetterCalls
        let reloads = fixture.host.executedReloadCount

        objectLifetimeAttemptRawReplacement(&raw, recorder: recorder)
        member.wrappedValue = 99
        nested.wrappedValue = 88
        element.wrappedValue = 77
        objectLifetimeAttemptRecordReplacement(record, recorder: recorder)

        XCTAssertNil(recorder.rejectedObject, "A retired raw projection does not store a new object")
        XCTAssertNil(recorder.rejectedPayload, "A retired member projection does not store a new payload")
        XCTAssertEqual(oldObject.valueGetterCalls, valueGets)
        XCTAssertEqual(oldObject.valueSetterCalls, valueSets)
        XCTAssertEqual(oldObject.recordGetterCalls, recordGets)
        XCTAssertEqual(oldObject.recordSetterCalls, recordSets)
        XCTAssertTrue(raw.wrappedValue === oldObject)
        XCTAssertEqual(oldObject.value, 2)
        XCTAssertEqual(oldObject.record.items, [11])
        XCTAssertEqual(replacement.value, 100)
        await fixture.drain()
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        try fixture.assertText("100", "owned.value")

        // A raw reference remains an ordinary alias. Retirement revokes the
        // projected setter; it does not deep-freeze the referenced object.
        oldObject.value = 6
        oldObject.record.items[0] = 12
        XCTAssertEqual(member.wrappedValue, 6)
        XCTAssertEqual(element.wrappedValue, 12)
        await fixture.drain()
        XCTAssertEqual(fixture.host.executedReloadCount, reloads)
        XCTAssertEqual(replacement.value, 100)
    }

    func testEscapedMemberBindingDoesNotRetainTheAuthoredFactoryCaptureOrUnmountedCache() async throws {
        let recorder = ObjectLifetimeRecorder()
        let capture = ObjectLifetimeCapture()
        var fixture: ObjectLifetimeWindow? = objectLifetimeFactoryCaptureWindow(recorder: recorder, capture: capture)
        weak var releasedHost = fixture?.host
        XCTAssertEqual(recorder.seeds, [41, 41], "The source fallback and mounted object are separate evaluations")
        XCTAssertNotNil(recorder.factoryPayload)
        XCTAssertNotNil(recorder.unmountedFallback)
        XCTAssertFalse(recorder.unmountedFallback === capture.model)
        let mounted = try XCTUnwrap(recorder.instances.last)
        var escaped = capture.member
        XCTAssertNotNil(escaped)
        capture.clearBindings()

        fixture?.close()
        fixture = nil
        capture.clearBindings()

        XCTAssertNil(releasedHost)
        XCTAssertNil(recorder.factoryPayload, "The member binding captures only the installed cell")
        XCTAssertNil(recorder.unmountedFallback, "The source cache is not part of mounted ownership")
        XCTAssertNotNil(mounted.value)
        XCTAssertEqual(escaped?.wrappedValue, 41)
        escaped = nil
        XCTAssertNil(mounted.value)
    }

    func testLegacyMountedObjectReplacementKeepsExistingProjectionsOnTheSameGeneration() async throws {
        let recorder = ObjectLifetimeRecorder()
        let capture = ObjectLifetimeCapture()
        let fixture = ObjectLifetimeWindow(
            ObjectLifetimeCounter(name: "replace", seed: 5, recorder: recorder, capture: capture))
        defer { fixture.close() }
        let originalObject = try XCTUnwrap(capture.model)
        let projection = try XCTUnwrap(capture.raw)
        let existingMember = try XCTUnwrap(capture.member)
        let existingElement = try XCTUnwrap(capture.element)
        let originalNode = try fixture.node("replace.value")

        try fixture.activate("replace.replace-object")
        fixture.flush()

        let replacement = try XCTUnwrap(capture.model)
        XCTAssertFalse(replacement === originalObject)
        XCTAssertTrue(projection.wrappedValue === replacement)
        XCTAssertEqual(existingMember.wrappedValue, 200)
        XCTAssertTrue(try fixture.node("replace.value") === originalNode)
        try fixture.assertText("200", "replace.value")
        existingMember.wrappedValue = 201
        existingElement.wrappedValue = 12
        fixture.flush()
        XCTAssertEqual(replacement.value, 201)
        XCTAssertEqual(replacement.record.items, [12])
        XCTAssertEqual(originalObject.value, 5)
        XCTAssertEqual(originalObject.record.items, [10])
        try fixture.assertText("201", "replace.value")
        let reloads = fixture.host.executedReloadCount

        originalObject.value = 99
        await fixture.drain()

        XCTAssertEqual(fixture.host.executedReloadCount, reloads, "The replaced object is no longer a dependency")
        try fixture.assertText("201", "replace.value")
        XCTAssertEqual(recorder.seeds, [5, 200], "Later builds do not call the original factory again")
    }
}

@MainActor
private final class ObjectLifetimeModel: ObservableObject {
    @Published var value: Int
    @Published var record: ObjectLifetimeRecord
    var valueGetterCalls = 0
    var valueSetterCalls = 0
    var recordGetterCalls = 0
    var recordSetterCalls = 0

    init(value: Int) {
        self.value = value
        self.record = ObjectLifetimeRecord(value: value, items: [10])
    }

    var computedValue: Int {
        get {
            valueGetterCalls += 1
            return value
        }
        set {
            valueSetterCalls += 1
            value = newValue
        }
    }

    var computedRecord: ObjectLifetimeRecord {
        get {
            recordGetterCalls += 1
            return record
        }
        set {
            recordSetterCalls += 1
            record = newValue
        }
    }
}

private final class ObjectLifetimePayload {}

private struct ObjectLifetimeRecord {
    var value: Int
    var items: [Int]
    var payload: ObjectLifetimePayload?
}

private final class ObjectLifetimeFactoryPayload {
    let seed: Int

    init(seed: Int) { self.seed = seed }
}

@MainActor
private final class ObjectLifetimeWeakModel {
    weak var value: ObjectLifetimeModel?

    init(_ value: ObjectLifetimeModel) { self.value = value }
}

@MainActor
private final class ObjectLifetimeRecorder {
    private(set) var seeds: [Int] = []
    private(set) var instances: [ObjectLifetimeWeakModel] = []
    weak var factoryPayload: ObjectLifetimeFactoryPayload?
    weak var unmountedFallback: ObjectLifetimeModel?
    weak var rejectedObject: ObjectLifetimeModel?
    weak var rejectedPayload: ObjectLifetimePayload?

    var factoryCount: Int { seeds.count }

    func make(seed: Int) -> ObjectLifetimeModel {
        let object = ObjectLifetimeModel(value: seed)
        seeds.append(seed)
        instances.append(ObjectLifetimeWeakModel(object))
        return object
    }
}

@MainActor
private final class ObjectLifetimeCapture {
    weak var model: ObjectLifetimeModel?
    var raw: StateObject<ObjectLifetimeModel>?
    var member: Binding<Int>?
    var record: Binding<ObjectLifetimeRecord>?
    var nestedMember: Binding<Int>?
    var element: Binding<Int>?

    func store(_ projection: StateObject<ObjectLifetimeModel>) {
        model = projection.wrappedValue
        raw = projection
        member = projection.computedValue
        let record = projection.computedRecord
        self.record = record
        nestedMember = record.value
        element = record.items[0]
    }

    func clearBindings() {
        raw = nil
        member = nil
        record = nil
        nestedMember = nil
        element = nil
    }
}

@MainActor
private final class ObjectLifetimeDriver: ObservableObject {
    @Published var revision = 0
    @Published var rows = [1, 2].map(ObjectLifetimeRowKey.init)
    @Published var showsChild = true
    @Published var firstBranch = true
    @Published var explicitID = 1
    @Published var usesStringID = false
    @Published var reversesReads = false
}

private struct ObjectLifetimeRowKey: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "same description" }
}

private struct ObjectLifetimeParent: View {
    @ObservedObject private var model: ObjectLifetimeDriver
    private let content: @MainActor () -> [AnyView]

    init(model: ObjectLifetimeDriver, @ViewBuilder content: @escaping @MainActor () -> [AnyView]) {
        self.model = model
        self.content = content
    }

    var body: some View {
        let revision = model.revision
        return VStack(alignment: .leading, spacing: 8) {
            Text("Parent \(revision)").accessibilityIdentifier("parent.revision")
            content()
        }
    }
}

private struct ObjectLifetimeCounter: View {
    @StateObject private var object: ObjectLifetimeModel
    let name: String
    let capture: ObjectLifetimeCapture?
    let replacementRecorder: ObjectLifetimeRecorder?

    init(name: String, seed: Int = 0, recorder: ObjectLifetimeRecorder, capture: ObjectLifetimeCapture? = nil) {
        self.name = name
        self.capture = capture
        self.replacementRecorder = recorder
        _object = StateObject(wrappedValue: recorder.make(seed: seed))
    }

    init(name: String, storage: StateObject<ObjectLifetimeModel>, capture: ObjectLifetimeCapture? = nil) {
        self.name = name
        self.capture = capture
        self.replacementRecorder = nil
        _object = storage
    }

    init(name: String, capture: ObjectLifetimeCapture, factory: @escaping @MainActor () -> ObjectLifetimeModel) {
        self.name = name
        self.capture = capture
        self.replacementRecorder = nil
        _object = StateObject(wrappedValue: factory())
    }

    var unmountedObject: ObjectLifetimeModel { object }

    var body: some View {
        let projection = $object
        let value = projection.value
        let firstItem = projection.computedRecord.items[0]
        var replacementProjection = projection
        capture?.store(projection)
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(object.value)).accessibilityIdentifier("\(name).value")
            Button("Increment \(name)") { value.wrappedValue += 1 }
                .accessibilityIdentifier("\(name).increment")
            Button("Increment first item") { firstItem.wrappedValue += 1 }
                .accessibilityIdentifier("\(name).increment-first")
            if let replacementRecorder {
                Button("Replace object") {
                    replacementProjection.wrappedValue = replacementRecorder.make(seed: 200)
                }
                .accessibilityIdentifier("\(name).replace-object")
            }
        }
    }
}

private struct ObjectLifetimeSlots: View {
    @StateObject private var first: ObjectLifetimeModel
    @StateObject private var second: ObjectLifetimeModel
    let reversesReads: Bool

    init(recorder: ObjectLifetimeRecorder, seedOffset: Int, reversesReads: Bool) {
        _first = StateObject(wrappedValue: recorder.make(seed: seedOffset + 3))
        _second = StateObject(wrappedValue: recorder.make(seed: seedOffset + 30))
        self.reversesReads = reversesReads
    }

    var body: some View {
        let values: (Int, Int)
        if reversesReads {
            let secondValue = second.value
            values = (first.value, secondValue)
        } else {
            let firstValue = first.value
            values = (firstValue, second.value)
        }
        let firstBinding = $first.value
        let secondBinding = $second.value
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(values.0)).accessibilityIdentifier("slots.first")
            Text(String(values.1)).accessibilityIdentifier("slots.second")
            Button("Increment first") { firstBinding.wrappedValue += 1 }
                .accessibilityIdentifier("slots.first.increment")
            Button("Increment second") { secondBinding.wrappedValue += 1 }
                .accessibilityIdentifier("slots.second.increment")
        }
    }
}

@MainActor
private func objectLifetimeIdentified(_ source: ObjectLifetimeCounter, driver: ObjectLifetimeDriver) -> AnyView {
    if driver.usesStringID { return AnyView(source.id(String(driver.explicitID))) }
    return AnyView(source.id(driver.explicitID))
}

@MainActor
private func objectLifetimeConditionalWindow(
    recorder: ObjectLifetimeRecorder, driver: ObjectLifetimeDriver, capture: ObjectLifetimeCapture
) -> ObjectLifetimeWindow {
    ObjectLifetimeWindow(
        ObjectLifetimeParent(model: driver) {
            if driver.showsChild {
                ObjectLifetimeCounter(name: "owned", seed: driver.revision, recorder: recorder, capture: capture)
            }
        })
}

@MainActor
private func objectLifetimeAttemptRawReplacement(
    _ projection: inout StateObject<ObjectLifetimeModel>, recorder: ObjectLifetimeRecorder
) {
    let object = ObjectLifetimeModel(value: 999)
    recorder.rejectedObject = object
    projection.wrappedValue = object
}

@MainActor
private func objectLifetimeAttemptRecordReplacement(
    _ binding: Binding<ObjectLifetimeRecord>, recorder: ObjectLifetimeRecorder
) {
    let payload = ObjectLifetimePayload()
    recorder.rejectedPayload = payload
    binding.wrappedValue = ObjectLifetimeRecord(value: 999, items: [999], payload: payload)
}

@MainActor
private func objectLifetimeFactoryCaptureWindow(
    recorder: ObjectLifetimeRecorder, capture: ObjectLifetimeCapture
) -> ObjectLifetimeWindow {
    let payload = ObjectLifetimeFactoryPayload(seed: 41)
    recorder.factoryPayload = payload
    let source = ObjectLifetimeCounter(name: "captured", capture: capture) {
        recorder.make(seed: payload.seed)
    }
    recorder.unmountedFallback = source.unmountedObject
    return ObjectLifetimeWindow(source)
}

@MainActor
private func objectLifetimeConfiguration<Content: View>(_ content: Content) -> WindowGroupConfiguration {
    WindowGroupConfiguration(
        title: "Mounted StateObject", size: IntSize(width: 640, height: 640), clearColor: .black,
        content: [AnyView(content)])
}

@MainActor
private final class ObjectLifetimeWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    convenience init<Content: View>(_ content: Content) {
        self.init(configuration: objectLifetimeConfiguration(content))
    }

    init(configuration: WindowGroupConfiguration) {
        let clock = RuntimeTestClock()
        clock.now = 6_000
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
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func drain() async {
        await Task.yield()
        await Task.yield()
        flush()
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
