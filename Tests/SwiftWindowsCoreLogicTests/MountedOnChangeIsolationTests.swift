import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class MountedOnChangeIsolationModel {
    let id: Int
    var value: Int
    var callbackVersion = 0

    init(_ value: Int, id: Int = 0) {
        self.value = value
        self.id = id
    }
}

@MainActor
private final class MountedOnChangeIsolationEvents {
    var values: [String] = []

    func record(_ name: String, old: Int, new: Int, version: Int = 0) {
        values.append("\(name):\(old)->\(new)@\(version)")
    }

    func values(for name: String) -> [String] {
        values.filter { $0.hasPrefix("\(name):") }
    }
}

/// Every occurrence uses this same source location, including across hosts.
@MainActor
private struct MountedOnChangeIsolationProbe: View {
    let model: MountedOnChangeIsolationModel
    let name: String
    let events: MountedOnChangeIsolationEvents
    var initial = false

    var body: some View {
        let value = model.value
        let version = model.callbackVersion
        Color.clear
            .frame(width: 10, height: 10)
            .onChange(of: value, initial: initial) { old, new in
                events.record(name, old: old, new: new, version: version)
            }
    }
}

/// Nesting calls this one onChange declaration with different content types.
@MainActor
private func mountedOnChangeNested<Content: View>(
    _ content: Content, value: Int, name: String, events: MountedOnChangeIsolationEvents
) -> some View {
    content.onChange(of: value) { old, new in
        events.record(name, old: old, new: new)
    }
}

@MainActor
final class MountedOnChangeIsolationTests: XCTestCase {
    func testTwoHostsObserveTheSharedModelIndependentlyAtOneCallSite() async {
        let model = MountedOnChangeIsolationModel(0)
        let events = MountedOnChangeIsolationEvents()
        let first = MountedOnChangeTestHost {
            AnyView(MountedOnChangeIsolationProbe(model: model, name: "first", events: events))
        }
        defer { first.close() }
        let second = MountedOnChangeTestHost {
            AnyView(MountedOnChangeIsolationProbe(model: model, name: "second", events: events))
        }
        defer { second.close() }
        XCTAssertTrue(events.values.isEmpty)

        model.value = 1
        first.reload()
        first.reload()
        XCTAssertEqual(events.values, ["first:0->1@0"])
        second.reload()
        XCTAssertEqual(events.values, ["first:0->1@0", "second:0->1@0"])
        model.value = 2
        second.reload()
        first.reload()
        XCTAssertEqual(events.values(for: "first"), ["first:0->1@0", "first:1->2@0"])
        XCTAssertEqual(events.values(for: "second"), ["second:0->1@0", "second:1->2@0"])
    }

    func testTwoHostsDoNotCompareDifferentModelsAtOneCallSite() async {
        let firstModel = MountedOnChangeIsolationModel(3)
        let secondModel = MountedOnChangeIsolationModel(20)
        let events = MountedOnChangeIsolationEvents()
        let first = MountedOnChangeTestHost {
            AnyView(MountedOnChangeIsolationProbe(model: firstModel, name: "first", events: events))
        }
        defer { first.close() }
        let second = MountedOnChangeTestHost {
            AnyView(MountedOnChangeIsolationProbe(model: secondModel, name: "second", events: events))
        }
        defer { second.close() }
        XCTAssertTrue(events.values.isEmpty)

        firstModel.value = 4
        second.reload()
        XCTAssertTrue(events.values.isEmpty)
        first.reload()
        secondModel.value = 21
        first.reload()
        second.reload()
        XCTAssertEqual(events.values, ["first:3->4@0", "second:20->21@0"])
    }

    func testOnePrebuiltModifiedValueHasAnInitialCallbackInEachHost() async {
        var calls = 0
        let source = AnyView(
            Color.clear.onChange(of: 17, initial: true) { _, _ in calls += 1 })
        let first = MountedOnChangeTestHost { source }
        defer { first.close() }
        XCTAssertEqual(calls, 1)
        let second = MountedOnChangeTestHost { source }
        defer { second.close() }
        XCTAssertEqual(calls, 2)

        first.reload()
        second.reload()
        XCTAssertEqual(calls, 2)
        first.close()
        second.reload()
        XCTAssertEqual(calls, 2)
    }

    func testOnePrebuiltModifiedValueHasIndependentSiblingOccurrences() async {
        var calls = 0
        let source = AnyView(
            Color.clear.onChange(of: 9, initial: true) { _, _ in calls += 1 })
        let host = MountedOnChangeTestHost {
            AnyView(
                HStack {
                    source
                    source
                })
        }
        defer { host.close() }
        XCTAssertEqual(calls, 2)

        host.reload()
        host.reload()
        XCTAssertEqual(calls, 2)
    }

    func testNestedModifiersAtOneCallSiteKeepSeparateBaselines() async {
        let model = MountedOnChangeIsolationModel(0)
        let events = MountedOnChangeIsolationEvents()
        let host = MountedOnChangeTestHost {
            AnyView(
                mountedOnChangeNested(
                    mountedOnChangeNested(Color.clear, value: model.value, name: "inner", events: events),
                    value: model.value, name: "outer", events: events))
        }
        defer { host.close() }
        XCTAssertTrue(events.values.isEmpty)

        model.value = 1
        host.reload()
        XCTAssertEqual(events.values.sorted(), ["inner:0->1@0", "outer:0->1@0"])
        host.reload()
        XCTAssertEqual(events.values.count, 2)
        model.value = 2
        host.reload()
        XCTAssertEqual(events.values(for: "inner"), ["inner:0->1@0", "inner:1->2@0"])
        XCTAssertEqual(events.values(for: "outer"), ["outer:0->1@0", "outer:1->2@0"])
    }

    func testRootUnmountAndRemountStartANewObservationGeneration() async {
        let model = MountedOnChangeIsolationModel(0)
        let events = MountedOnChangeIsolationEvents()
        var isMounted = true
        let host = MountedOnChangeTestHost {
            if isMounted {
                return AnyView(MountedOnChangeIsolationProbe(model: model, name: "root", events: events, initial: true))
            }
            return AnyView(EmptyView())
        }
        defer { host.close() }
        XCTAssertEqual(events.values, ["root:0->0@0"])
        model.value = 1
        host.reload()
        XCTAssertEqual(events.values.last, "root:0->1@0")

        isMounted = false
        host.reload()
        model.value = 5
        host.reload()
        XCTAssertEqual(events.values.count, 2)
        isMounted = true
        host.reload()
        host.reload()
        XCTAssertEqual(events.values, ["root:0->0@0", "root:0->1@0", "root:5->5@0"])
    }

    func testExplicitIDReplacementDoesNotRestoreTheOldObservationHistory() async {
        let model = MountedOnChangeIsolationModel(2)
        let events = MountedOnChangeIsolationEvents()
        var identifier = 1
        let host = MountedOnChangeTestHost {
            AnyView(
                MountedOnChangeIsolationProbe(model: model, name: "identified", events: events, initial: true)
                    .id(identifier))
        }
        defer { host.close() }
        XCTAssertEqual(events.values, ["identified:2->2@0"])
        model.value = 3
        host.reload()
        identifier = 2
        host.reload()
        host.reload()
        identifier = 1
        host.reload()
        XCTAssertEqual(
            events.values,
            ["identified:2->2@0", "identified:2->3@0", "identified:3->3@0", "identified:3->3@0"])
    }

    func testConditionalBranchReplacementKeepsTheFollowingSiblingHistory() async {
        let first = MountedOnChangeIsolationModel(10)
        let second = MountedOnChangeIsolationModel(20)
        let following = MountedOnChangeIsolationModel(100)
        let events = MountedOnChangeIsolationEvents()
        var showsFirst = true
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    if showsFirst {
                        MountedOnChangeIsolationProbe(model: first, name: "branch", events: events, initial: true)
                    } else {
                        MountedOnChangeIsolationProbe(model: second, name: "branch", events: events, initial: true)
                    }
                    MountedOnChangeIsolationProbe(model: following, name: "following", events: events, initial: true)
                })
        }
        defer { host.close() }
        first.value = 11
        following.value = 101
        host.reload()
        showsFirst = false
        host.reload()
        second.value = 21
        following.value = 102
        host.reload()
        showsFirst = true
        host.reload()

        XCTAssertEqual(
            events.values(for: "branch"),
            ["branch:10->10@0", "branch:10->11@0", "branch:20->20@0", "branch:20->21@0", "branch:11->11@0"])
        XCTAssertEqual(
            events.values(for: "following"),
            ["following:100->100@0", "following:100->101@0", "following:101->102@0"])
    }

    func testOptionalRemovalRemountsOnlyTheMissingSibling() async {
        let optional = MountedOnChangeIsolationModel(1)
        let following = MountedOnChangeIsolationModel(10)
        let events = MountedOnChangeIsolationEvents()
        let source = MountedOnChangeIsolationProbe(model: optional, name: "optional", events: events, initial: true)
        var showsOptional = true
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    if showsOptional { source }
                    MountedOnChangeIsolationProbe(model: following, name: "following", events: events, initial: true)
                })
        }
        defer { host.close() }
        optional.value = 2
        following.value = 11
        host.reload()
        showsOptional = false
        host.reload()
        optional.value = 3
        following.value = 12
        host.reload()
        showsOptional = true
        host.reload()

        XCTAssertEqual(events.values(for: "optional"), ["optional:1->1@0", "optional:1->2@0", "optional:3->3@0"])
        XCTAssertEqual(
            events.values(for: "following"), ["following:10->10@0", "following:10->11@0", "following:11->12@0"])
    }

    func testKeyedReorderingPreservesSurvivorsAndReinsertionStartsFresh() async {
        let first = MountedOnChangeIsolationModel(10, id: 1)
        let second = MountedOnChangeIsolationModel(20, id: 2)
        let inserted = MountedOnChangeIsolationModel(30, id: 3)
        let events = MountedOnChangeIsolationEvents()
        var rows = [first, second]
        let host = MountedOnChangeTestHost {
            AnyView(
                VStack {
                    ForEach(rows, id: \.id) { row in
                        MountedOnChangeIsolationProbe(
                            model: row, name: "row.\(row.id)", events: events, initial: true)
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
        rows = [second, inserted]
        host.reload()
        first.value = 12
        second.value = 22
        rows = [first, second, inserted]
        host.reload()

        XCTAssertEqual(events.values(for: "row.1"), ["row.1:10->10@0", "row.1:10->11@0", "row.1:12->12@0"])
        XCTAssertEqual(events.values(for: "row.2"), ["row.2:20->20@0", "row.2:20->21@0", "row.2:21->22@0"])
        XCTAssertEqual(events.values(for: "row.3"), ["row.3:30->30@0"])
    }

    func testInitialFalseUsesTheFirstAdoptedValueWithoutCallingTheAction() async {
        var value = 5
        var changes: [[Int]] = []
        let host = MountedOnChangeTestHost {
            AnyView(Color.clear.onChange(of: value, initial: false) { old, new in changes.append([old, new]) })
        }
        defer { host.close() }
        host.reload()
        XCTAssertTrue(changes.isEmpty)
        value = 6
        host.reload()
        host.reload()
        value = 7
        host.reload()
        XCTAssertEqual(changes, [[5, 6], [6, 7]])
    }

    func testInitialTrueTwoValueOverloadReportsOneEqualPairThenChanges() async {
        var value = 2
        var changes: [[Int]] = []
        let host = MountedOnChangeTestHost {
            AnyView(Color.clear.onChange(of: value, initial: true) { old, new in changes.append([old, new]) })
        }
        defer { host.close() }
        XCTAssertEqual(changes, [[2, 2]])
        host.reload()
        host.reload()
        XCTAssertEqual(changes, [[2, 2]])
        value = 4
        host.reload()
        XCTAssertEqual(changes, [[2, 2], [2, 4]])
    }

    func testPerformOverloadTreatsOptionalNilAsAnObservedInitialValue() async {
        var value: Int?
        var received: [Int?] = []
        let host = MountedOnChangeTestHost {
            AnyView(Color.clear.onChange(of: value, initial: true, perform: { received.append($0) }))
        }
        defer { host.close() }
        XCTAssertEqual(received, [nil])
        host.reload()
        XCTAssertEqual(received, [nil])
        value = 1
        host.reload()
        value = nil
        host.reload()
        host.reload()
        XCTAssertEqual(received, [nil, 1, nil])
    }

    func testZeroArgumentOverloadRunsInitiallyAndOnlyWhenTheValueChanges() async {
        var value = 1
        var received: [Int] = []
        let host = MountedOnChangeTestHost {
            let captured = value
            return AnyView(Color.clear.onChange(of: value, initial: true) { received.append(captured) })
        }
        defer { host.close() }
        XCTAssertEqual(received, [1])
        host.reload()
        value = 2
        host.reload()
        host.reload()
        value = 3
        host.reload()
        XCTAssertEqual(received, [1, 2, 3])
    }

    func testUnchangedValueRebuildsUseTheLatestCallbackCapture() async {
        let model = MountedOnChangeIsolationModel(0)
        model.callbackVersion = 1
        let events = MountedOnChangeIsolationEvents()
        let host = MountedOnChangeTestHost {
            AnyView(MountedOnChangeIsolationProbe(model: model, name: "value", events: events))
        }
        defer { host.close() }
        model.callbackVersion = 2
        host.reload()
        model.callbackVersion = 3
        host.reload()
        XCTAssertTrue(events.values.isEmpty)
        model.value = 1
        host.reload()
        XCTAssertEqual(events.values, ["value:0->1@3"])
        model.callbackVersion = 4
        host.reload()
        XCTAssertEqual(events.values.count, 1)
        model.value = 2
        host.reload()
        XCTAssertEqual(events.values, ["value:0->1@3", "value:1->2@4"])
    }

    func testTwoValueOverloadKeepsNilAsThePreviousOptionalValue() async {
        var value: Int?
        var changes: [[Int?]] = []
        let host = MountedOnChangeTestHost {
            AnyView(Color.clear.onChange(of: value) { old, new in changes.append([old, new]) })
        }
        defer { host.close() }
        host.reload()
        XCTAssertTrue(changes.isEmpty)
        value = 2
        host.reload()
        value = nil
        host.reload()
        host.reload()
        XCTAssertEqual(changes, [[nil, 2], [2, nil]])
    }
}
