import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct MountedPreferenceValueSumKey: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

private struct MountedPreferenceValueOtherSumKey: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

private struct MountedPreferenceValueOptionalKey: PreferenceKey {
    static let defaultValue: Int? = nil

    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        value = nextValue()
    }
}

@MainActor
private final class MountedPreferenceValueModel {
    let id: Int
    var value: Int
    var isPresent = true
    var callbackVersion = 0

    init(_ value: Int, id: Int = 0) {
        self.value = value
        self.id = id
    }
}

@MainActor
private final class MountedPreferenceValueEvents {
    var values: [String] = []

    func record(_ name: String, value: Int, version: Int = 0) {
        values.append("\(name):\(value)@\(version)")
    }

    func values(for name: String) -> [String] {
        values.filter { $0.hasPrefix("\(name):") }
    }
}

/// All hosts and siblings observe through this one source location.
@MainActor
private struct MountedPreferenceValueProbe: View {
    let model: MountedPreferenceValueModel
    let name: String
    let events: MountedPreferenceValueEvents

    var body: some View {
        let version = model.callbackVersion
        Color.clear
            .frame(width: 10, height: 10)
            .preference(key: MountedPreferenceValueSumKey.self, value: model.value)
            .onPreferenceChange(
                MountedPreferenceValueSumKey.self,
                perform: { value in events.record(name, value: value, version: version) })
    }
}

@MainActor
private struct MountedPreferenceValuePresenceProbe: View {
    let model: MountedPreferenceValueModel
    let events: MountedPreferenceValueEvents

    var body: some View {
        VStack {
            if model.isPresent {
                Color.clear
                    .frame(width: 10, height: 10)
                    .preference(key: MountedPreferenceValueSumKey.self, value: model.value)
            }
        }
        .onPreferenceChange(
            MountedPreferenceValueSumKey.self,
            perform: { value in events.record("presence", value: value) })
    }
}

/// Key specialization and nesting reuse this single observer declaration.
@MainActor
private func mountedPreferenceValueObserving<Key: PreferenceKey, Content: View>(
    _ key: Key.Type, content: Content, name: String, events: MountedPreferenceValueEvents
) -> some View where Key.Value == Int {
    content.onPreferenceChange(key, perform: { value in events.record(name, value: value) })
}

@MainActor
private struct MountedPreferenceValueStateView: View {
    let events: MountedPreferenceValueEvents
    @State private var value = 0

    var body: some View {
        VStack {
            Button("Increment", action: { value += 1 })
                .accessibilityIdentifier("preference.value.increment")
            Text("value=\(value)")
                .accessibilityIdentifier("preference.value.status")
                .preference(key: MountedPreferenceValueSumKey.self, value: value)
        }
        .onPreferenceChange(
            MountedPreferenceValueSumKey.self,
            perform: { newValue in events.record("state", value: newValue) })
    }
}

@MainActor
private func mountedPreferenceValueNode(_ identifier: String, in root: ViewNode) -> ViewNode? {
    var pending = [root]
    while let node = pending.popLast() {
        if node.accessibilityIdentifier == identifier { return node }
        pending.append(contentsOf: node.children)
    }
    return nil
}

@MainActor
final class MountedPreferenceValueTests: XCTestCase {
    func testTwoHostsObserveTheSamePreferenceIndependentlyAtOneCallSite() async {
        let model = MountedPreferenceValueModel(2)
        let events = MountedPreferenceValueEvents()
        let first = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValueProbe(model: model, name: "first", events: events))
        }
        defer { first.close() }
        let second = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValueProbe(model: model, name: "second", events: events))
        }
        defer { second.close() }
        XCTAssertEqual(events.values, ["first:2@0", "second:2@0"])

        model.value = 3
        first.reload()
        first.reload()
        XCTAssertEqual(events.values, ["first:2@0", "second:2@0", "first:3@0"])
        second.reload()
        model.value = 4
        second.reload()
        first.reload()
        XCTAssertEqual(events.values(for: "first"), ["first:2@0", "first:3@0", "first:4@0"])
        XCTAssertEqual(events.values(for: "second"), ["second:2@0", "second:3@0", "second:4@0"])
    }

    func testTwoHostsDoNotCompareDifferentPreferencesAtOneCallSite() async {
        let firstModel = MountedPreferenceValueModel(3)
        let secondModel = MountedPreferenceValueModel(20)
        let events = MountedPreferenceValueEvents()
        let first = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValueProbe(model: firstModel, name: "first", events: events))
        }
        defer { first.close() }
        let second = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValueProbe(model: secondModel, name: "second", events: events))
        }
        defer { second.close() }
        XCTAssertEqual(events.values, ["first:3@0", "second:20@0"])

        firstModel.value = 4
        second.reload()
        XCTAssertEqual(events.values, ["first:3@0", "second:20@0"])
        first.reload()
        secondModel.value = 21
        first.reload()
        second.reload()
        XCTAssertEqual(events.values, ["first:3@0", "second:20@0", "first:4@0", "second:21@0"])
    }

    func testOnePrebuiltPreferenceObserverNotifiesEachHostOnce() async {
        var received: [Int] = []
        let source = AnyView(
            Color.clear
                .preference(key: MountedPreferenceValueSumKey.self, value: 17)
                .onPreferenceChange(MountedPreferenceValueSumKey.self, perform: { received.append($0) }))
        let first = MountedOnChangeTestHost { source }
        defer { first.close() }
        let second = MountedOnChangeTestHost { source }
        defer { second.close() }
        XCTAssertEqual(received, [17, 17])

        first.reload()
        second.reload()
        first.close()
        second.reload()
        XCTAssertEqual(received, [17, 17])
    }

    func testOnePrebuiltPreferenceObserverHasIndependentSiblingOccurrences() async {
        var received: [Int] = []
        let source = AnyView(
            Color.clear
                .preference(key: MountedPreferenceValueSumKey.self, value: 9)
                .onPreferenceChange(MountedPreferenceValueSumKey.self, perform: { received.append($0) }))
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    source
                    source
                })
        }
        defer { host.close() }
        XCTAssertEqual(received, [9, 9])

        host.reload()
        host.reload()
        XCTAssertEqual(received, [9, 9])
    }

    func testSiblingPreferencesAtOneCallSiteKeepSeparateBaselines() async {
        let first = MountedPreferenceValueModel(10)
        let second = MountedPreferenceValueModel(20)
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    MountedPreferenceValueProbe(model: first, name: "first", events: events)
                    MountedPreferenceValueProbe(model: second, name: "second", events: events)
                })
        }
        defer { host.close() }
        host.reload()
        first.value = 11
        host.reload()
        XCTAssertEqual(events.values(for: "first"), ["first:10@0", "first:11@0"])
        XCTAssertEqual(events.values(for: "second"), ["second:20@0"])
        second.value = 21
        host.reload()
        host.reload()
        XCTAssertEqual(events.values(for: "first"), ["first:10@0", "first:11@0"])
        XCTAssertEqual(events.values(for: "second"), ["second:20@0", "second:21@0"])
    }

    func testNestedObserversAtOneHelperAndKeyKeepSeparateReducedValues() async {
        let inner = MountedPreferenceValueModel(2)
        let outside = MountedPreferenceValueModel(5)
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedPreferenceValueObserving(
                    MountedPreferenceValueSumKey.self,
                    content: HStack {
                        mountedPreferenceValueObserving(
                            MountedPreferenceValueSumKey.self,
                            content: Color.clear.preference(key: MountedPreferenceValueSumKey.self, value: inner.value),
                            name: "inner", events: events)
                        Color.clear.preference(key: MountedPreferenceValueSumKey.self, value: outside.value)
                    },
                    name: "outer", events: events))
        }
        defer { host.close() }
        XCTAssertEqual(events.values.sorted(), ["inner:2@0", "outer:7@0"])

        inner.value = 3
        host.reload()
        outside.value = 9
        host.reload()
        host.reload()
        XCTAssertEqual(events.values(for: "inner"), ["inner:2@0", "inner:3@0"])
        XCTAssertEqual(events.values(for: "outer"), ["outer:7@0", "outer:8@0", "outer:12@0"])
    }

    func testDistinctPreferenceKeysSharingIntHaveIndependentObservations() async {
        let first = MountedPreferenceValueModel(3)
        let second = MountedPreferenceValueModel(30)
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedPreferenceValueObserving(
                    MountedPreferenceValueOtherSumKey.self,
                    content: mountedPreferenceValueObserving(
                        MountedPreferenceValueSumKey.self,
                        content: Color.clear
                            .preference(key: MountedPreferenceValueSumKey.self, value: first.value)
                            .preference(key: MountedPreferenceValueOtherSumKey.self, value: second.value),
                        name: "first", events: events),
                    name: "second", events: events))
        }
        defer { host.close() }
        XCTAssertEqual(events.values.sorted(), ["first:3@0", "second:30@0"])

        first.value = 4
        host.reload()
        second.value = 40
        host.reload()
        host.reload()
        XCTAssertEqual(events.values(for: "first"), ["first:3@0", "first:4@0"])
        XCTAssertEqual(events.values(for: "second"), ["second:30@0", "second:40@0"])
    }

    func testChangingPreferenceKeyAtTheSameModifiedViewShapeStartsFresh() async {
        let events = MountedPreferenceValueEvents()
        let content = Color.clear
            .preference(key: MountedPreferenceValueSumKey.self, value: 7)
            .preference(key: MountedPreferenceValueOtherSumKey.self, value: 7)
        let first = mountedPreferenceValueObserving(
            MountedPreferenceValueSumKey.self, content: content, name: "first", events: events)
        let second = mountedPreferenceValueObserving(
            MountedPreferenceValueOtherSumKey.self, content: content, name: "second", events: events)
        XCTAssertEqual(ObjectIdentifier(type(of: first)), ObjectIdentifier(type(of: second)))

        var observesFirst = true
        let host = MountedOnChangeTestHost { observesFirst ? AnyView(first) : AnyView(second) }
        defer { host.close() }
        XCTAssertEqual(events.values, ["first:7@0"])
        observesFirst = false
        host.reload()
        host.reload()
        observesFirst = true
        host.reload()
        host.reload()
        XCTAssertEqual(events.values, ["first:7@0", "second:7@0", "first:7@0"])
    }

    func testSwitchingOnChangeAndPreferenceAtTheSameModifiedViewShapeStartsFresh() async {
        let events = MountedPreferenceValueEvents()
        let content = Color.clear.preference(key: MountedPreferenceValueSumKey.self, value: 7)
        let change = content.onChange(
            of: 7, initial: true, perform: { value in events.record("change", value: value) })
        let preference = content.onPreferenceChange(
            MountedPreferenceValueSumKey.self, perform: { value in events.record("preference", value: value) })
        XCTAssertEqual(ObjectIdentifier(type(of: change)), ObjectIdentifier(type(of: preference)))

        var observesPreference = false
        let host = MountedOnChangeTestHost { observesPreference ? AnyView(preference) : AnyView(change) }
        defer { host.close() }
        XCTAssertEqual(events.values, ["change:7@0"])
        observesPreference = true
        host.reload()
        host.reload()
        observesPreference = false
        host.reload()
        observesPreference = true
        host.reload()
        XCTAssertEqual(events.values, ["change:7@0", "preference:7@0", "change:7@0", "preference:7@0"])
    }

    func testKeyedReorderingAndInsertionPreserveExistingPreferenceHistory() async {
        let first = MountedPreferenceValueModel(10, id: 1)
        let second = MountedPreferenceValueModel(20, id: 2)
        let inserted = MountedPreferenceValueModel(30, id: 3)
        let events = MountedPreferenceValueEvents()
        var rows = [first, second]
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    ForEach(rows, id: \.id) { row in
                        MountedPreferenceValueProbe(model: row, name: "row.\(row.id)", events: events)
                    }
                })
        }
        defer { host.close() }
        first.value = 11
        second.value = 21
        rows = [second, first]
        host.reload()
        host.reload()
        rows = [second, inserted, first]
        host.reload()
        rows = [first, second, inserted]
        host.reload()
        XCTAssertEqual(events.values(for: "row.1"), ["row.1:10@0", "row.1:11@0"])
        XCTAssertEqual(events.values(for: "row.2"), ["row.2:20@0", "row.2:21@0"])
        XCTAssertEqual(events.values(for: "row.3"), ["row.3:30@0"])
    }

    func testKeyedRemovalAndReinsertionStartANewPreferenceGeneration() async {
        let first = MountedPreferenceValueModel(10, id: 1)
        let second = MountedPreferenceValueModel(20, id: 2)
        let events = MountedPreferenceValueEvents()
        var rows = [first, second]
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    ForEach(rows, id: \.id) { row in
                        MountedPreferenceValueProbe(model: row, name: "row.\(row.id)", events: events)
                    }
                })
        }
        defer { host.close() }
        first.value = 11
        host.reload()
        rows = [second]
        host.reload()
        first.value = 12
        second.value = 21
        host.reload()
        XCTAssertEqual(events.values(for: "row.1"), ["row.1:10@0", "row.1:11@0"])
        rows = [first, second]
        host.reload()
        rows = [second]
        host.reload()
        rows = [first, second]
        host.reload()
        host.reload()
        XCTAssertEqual(events.values(for: "row.1"), ["row.1:10@0", "row.1:11@0", "row.1:12@0", "row.1:12@0"])
        XCTAssertEqual(events.values(for: "row.2"), ["row.2:20@0", "row.2:21@0"])
    }

    func testRootRemovalAndRemountStartANewPreferenceGeneration() async {
        let model = MountedPreferenceValueModel(2)
        let events = MountedPreferenceValueEvents()
        var isMounted = true
        let host = MountedOnChangeTestHost {
            if isMounted {
                return AnyView(MountedPreferenceValueProbe(model: model, name: "root", events: events))
            }
            return AnyView(EmptyView())
        }
        defer { host.close() }
        model.value = 3
        host.reload()
        isMounted = false
        host.reload()
        model.value = 5
        host.reload()
        XCTAssertEqual(events.values, ["root:2@0", "root:3@0"])
        isMounted = true
        host.reload()
        host.reload()
        XCTAssertEqual(events.values, ["root:2@0", "root:3@0", "root:5@0"])
    }

    func testExplicitIDReplacementDoesNotRestorePreferenceHistory() async {
        let model = MountedPreferenceValueModel(2)
        let events = MountedPreferenceValueEvents()
        var identifier = 1
        let host = MountedOnChangeTestHost {
            AnyView(
                MountedPreferenceValueProbe(model: model, name: "identified", events: events)
                    .id(identifier))
        }
        defer { host.close() }
        model.value = 3
        host.reload()
        identifier = 2
        host.reload()
        host.reload()
        identifier = 1
        host.reload()
        XCTAssertEqual(events.values, ["identified:2@0", "identified:3@0", "identified:3@0", "identified:3@0"])
    }

    func testFirstExplicitDefaultPreferenceNotifiesOnce() async {
        let model = MountedPreferenceValueModel(MountedPreferenceValueSumKey.defaultValue)
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValuePresenceProbe(model: model, events: events))
        }
        defer { host.close() }
        XCTAssertEqual(events.values, ["presence:0@0"])
        host.reload()
        host.reload()
        XCTAssertEqual(events.values, ["presence:0@0"])
        model.value = 1
        host.reload()
        XCTAssertEqual(events.values, ["presence:0@0", "presence:1@0"])
    }

    func testFirstMissingPreferenceSilentlyEstablishesItsDefault() async {
        let model = MountedPreferenceValueModel(5)
        model.isPresent = false
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValuePresenceProbe(model: model, events: events))
        }
        defer { host.close() }
        host.reload()
        XCTAssertTrue(events.values.isEmpty)
        model.isPresent = true
        host.reload()
        host.reload()
        XCTAssertEqual(events.values, ["presence:5@0"])
    }

    func testRemovingAPresentPreferenceDeliversTheDefaultOnce() async {
        let model = MountedPreferenceValueModel(8)
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValuePresenceProbe(model: model, events: events))
        }
        defer { host.close() }
        model.isPresent = false
        host.reload()
        host.reload()
        XCTAssertEqual(events.values, ["presence:8@0", "presence:0@0"])
        model.isPresent = true
        host.reload()
        XCTAssertEqual(events.values, ["presence:8@0", "presence:0@0", "presence:8@0"])
    }

    func testMissingThenExplicitSameDefaultDoesNotNotify() async {
        let model = MountedPreferenceValueModel(MountedPreferenceValueSumKey.defaultValue)
        model.isPresent = false
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValuePresenceProbe(model: model, events: events))
        }
        defer { host.close() }
        model.isPresent = true
        host.reload()
        model.isPresent = false
        host.reload()
        model.isPresent = true
        host.reload()
        XCTAssertTrue(events.values.isEmpty)
        model.value = 1
        host.reload()
        XCTAssertEqual(events.values, ["presence:1@0"])
    }

    func testExplicitOptionalNoneIsPresentAndRemainsARealBaseline() async {
        var value: Int?
        var isPresent = true
        var received: [Int?] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    if isPresent {
                        Color.clear.preference(key: MountedPreferenceValueOptionalKey.self, value: value)
                    }
                }
                .onPreferenceChange(MountedPreferenceValueOptionalKey.self, perform: { received.append($0) }))
        }
        defer { host.close() }
        XCTAssertEqual(received, [nil])
        host.reload()
        isPresent = false
        host.reload()
        isPresent = true
        host.reload()
        XCTAssertEqual(received, [nil])
        value = 4
        host.reload()
        value = nil
        host.reload()
        host.reload()
        XCTAssertEqual(received, [nil, 4, nil])
    }

    func testEqualPreferenceRebuildsUseTheLatestCallbackCapture() async {
        let model = MountedPreferenceValueModel(1)
        model.callbackVersion = 1
        let events = MountedPreferenceValueEvents()
        let host = MountedOnChangeTestHost {
            AnyView(MountedPreferenceValueProbe(model: model, name: "value", events: events))
        }
        defer { host.close() }
        XCTAssertEqual(events.values, ["value:1@1"])
        model.callbackVersion = 2
        host.reload()
        model.callbackVersion = 3
        host.reload()
        XCTAssertEqual(events.values, ["value:1@1"])
        model.value = 2
        host.reload()
        model.callbackVersion = 4
        host.reload()
        model.value = 3
        host.reload()
        XCTAssertEqual(events.values, ["value:1@1", "value:2@3", "value:3@4"])
    }

    func testRetainedButtonStateWritesDeliverUpdatedPreferences() async throws {
        let events = MountedPreferenceValueEvents()
        let source = MountedPreferenceValueStateView(events: events)
        let host = MountedOnChangeTestHost { AnyView(source) }
        defer { host.close() }
        XCTAssertNil(host.coordinator.latestInstallationError)
        XCTAssertEqual(events.values, ["state:0@0"])

        for value in 1...2 {
            let button = try XCTUnwrap(
                mountedPreferenceValueNode("preference.value.increment", in: host.runtime.root))
            let activate = try XCTUnwrap(button.onActivate)
            activate()
            XCTAssertEqual(
                mountedPreferenceValueNode("preference.value.status", in: host.runtime.root)?.text,
                "value=\(value)")
            XCTAssertEqual(events.values.last, "state:\(value)@0")
            XCTAssertNil(host.coordinator.latestInstallationError)
        }
        host.reload()
        XCTAssertEqual(events.values, ["state:0@0", "state:1@0", "state:2@0"])
    }
}
