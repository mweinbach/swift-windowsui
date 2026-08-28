import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class RetainedAlertActivityTests: XCTestCase {
    func testInactiveTabPreservesStateButRetiresEscapedAlertActions() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            let tabs = RetainedAlertActivityTabs()
            let fixture = RetainedAlertActivityHost(RetainedAlertActivityTabbedRoot(model: model, tabs: tabs))
            defer { fixture.close() }
            let original = try fixture.action(model.name)
            let state = try XCTUnwrap(model.counter)
            state.wrappedValue = 11
            fixture.flush()
            let beforeInactivity = try fixture.action(model.name)

            tabs.selection = 1
            fixture.rebuild()
            fixture.finishTransitions()
            let backgroundBodies = model.backgroundBodies
            let actionConstructions = model.captured.count
            assertInert(original, model: model, fixture: fixture)
            assertInert(beforeInactivity, model: model, fixture: fixture)
            XCTAssertFalse(fixture.contains("\(model.name).choose"))
            XCTAssertTrue(model.presented)

            state.wrappedValue = 12
            fixture.flush()
            fixture.rebuild()
            XCTAssertEqual(model.backgroundBodies, backgroundBodies)
            XCTAssertEqual(model.captured.count, actionConstructions)
            XCTAssertEqual(state.wrappedValue, 12)
            tabs.selection = 0
            fixture.rebuild()
            fixture.finishTransitions()

            XCTAssertEqual(try XCTUnwrap(model.counter).wrappedValue, 12)
            XCTAssertEqual(try fixture.node("\(model.name).state").text, "Count 12")
            assertInert(original, model: model, fixture: fixture)
            assertInert(beforeInactivity, model: model, fixture: fixture)
            model.resetAccesses()
            try fixture.action(model.name).activate()
            fixture.flush()
            XCTAssertEqual(model.choices, [0])
            XCTAssertEqual(model.setters, [0])
            XCTAssertFalse(model.presented)
        }
    }

    func testActualGeometrySlotControlsAlertActivityWithoutRebuildingTheOutsideOwner() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            let outside = RetainedAlertActivityModel(name: "outside")
            let geometry = RetainedAlertActivityGeometry()
            let fixture = RetainedAlertActivityHost(
                RetainedAlertActivityGeometryRoot(model: model, outside: outside, geometry: geometry))
            defer { fixture.close() }
            let reader = try fixture.reader()
            XCTAssertLessThan(reader.resolvedFrame.size.width, 350)
            XCTAssertFalse(fixture.contains("\(model.name).choose"))
            for seedAction in model.captured {
                assertInert(seedAction, model: model, fixture: fixture, renderOnly: true)
            }
            let outsideNode = try fixture.node("outside.state")
            let outsideBodies = outside.backgroundBodies
            let reloads = fixture.host.executedReloadCount
            let resolves = fixture.runtime.geometryReaderResolveCount

            fixture.resizeRuntime(to: IntSize(width: 560, height: 420))

            XCTAssertTrue(try fixture.reader() === reader)
            XCTAssertGreaterThan(fixture.runtime.geometryReaderResolveCount, resolves)
            XCTAssertTrue(fixture.contains("\(model.name).choose"))
            let first = try fixture.action(model.name)
            let firstWidth = Int(reader.resolvedFrame.size.width.rounded())
            XCTAssertEqual(first.version, firstWidth)
            fixture.resizeRuntime(to: IntSize(width: 620, height: 460))
            let resized = try fixture.action(model.name)
            XCTAssertNotEqual(resized.version, first.version)
            assertInert(first, model: model, fixture: fixture, renderOnly: true)
            fixture.resizeRuntime(to: IntSize(width: 300, height: 360))
            XCTAssertFalse(fixture.contains("\(model.name).choose"))
            assertInert(resized, model: model, fixture: fixture, renderOnly: true)
            fixture.resizeRuntime(to: IntSize(width: 580, height: 440))

            XCTAssertTrue(fixture.contains("\(model.name).choose"))
            XCTAssertTrue(try fixture.node("outside.state") === outsideNode)
            XCTAssertEqual(outside.backgroundBodies, outsideBodies)
            XCTAssertEqual(fixture.host.executedReloadCount, reloads)
            assertInert(first, model: model, fixture: fixture, renderOnly: true)
            assertInert(resized, model: model, fixture: fixture, renderOnly: true)
            let current = try fixture.action(model.name)
            model.resetAccesses()
            current.activate()
            fixture.renderRuntime()
            XCTAssertEqual(model.choices, [current.version])
            XCTAssertEqual(model.setters, [current.version])
            XCTAssertFalse(model.presented)
        }
    }

    func testAbandonedConstructedReaderCandidateKeepsTheAcceptedAlertAndLease() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            let outside = RetainedAlertActivityModel(name: "outside")
            let geometry = RetainedAlertActivityGeometry()
            let fixture = RetainedAlertActivityHost(
                RetainedAlertActivityGeometryRoot(model: model, outside: outside, geometry: geometry),
                size: IntSize(width: 560, height: 400))
            defer { fixture.close() }
            let reader = try fixture.reader()
            let acceptedAction = try fixture.action(model.name)
            let acceptedNode = try fixture.node("\(model.name).choose")
            let lease = try XCTUnwrap(reader.retainedSubtreeBuildLease)
            let builder = try XCTUnwrap(reader.geometryReaderBuild)
            let acceptedSize = reader.geometryReaderBuiltSize
            let constructions = model.captured.count
            let bodies = geometry.bodies
            let build = try XCTUnwrap(lease.beginBuild())
            defer {
                build.abandon()
                build.finishAfterCallbacks()
            }
            let candidateNodes = builder(fixture.runtime, Size(width: 610, height: 310))
            XCTAssertFalse(candidateNodes.isEmpty)
            XCTAssertGreaterThan(geometry.bodies, bodies)
            XCTAssertGreaterThan(model.captured.count, constructions)
            let candidateAction = try XCTUnwrap(model.captured.last)
            XCTAssertEqual(candidateAction.version, 610)
            let before = model.accesses
            candidateAction.activate()
            candidateAction.repeatActivate()
            XCTAssertEqual(model.accesses, before)
            XCTAssertTrue(build.willAdopt())
            XCTAssertFalse(lease.canBuild)
            acceptedAction.activate()
            XCTAssertEqual(model.accesses, before, "Preparation must suspend the still-attached accepted alert")

            build.abandon()
            build.finishAfterCallbacks()

            XCTAssertTrue(lease.canBuild)
            XCTAssertTrue(try fixture.reader() === reader)
            XCTAssertTrue(try fixture.node("\(model.name).choose") === acceptedNode)
            XCTAssertEqual(reader.geometryReaderBuiltSize, acceptedSize)
            assertInert(candidateAction, model: model, fixture: fixture, renderOnly: true)
            model.resetAccesses()
            acceptedAction.activate()
            fixture.flush()
            XCTAssertEqual(model.choices, [acceptedAction.version])
            XCTAssertEqual(model.setters, [acceptedAction.version])
            XCTAssertFalse(model.presented)
            withExtendedLifetime(candidateNodes) {}
        }
    }

    func testBodyConstructionAndAppearCallbacksCannotActivateCandidateActions() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            let fixture = RetainedAlertActivityHost(RetainedAlertActivityOwner(model: model))
            defer {
                model.onOwnerBody = nil
                model.onConstruction = nil
                model.onAppear = nil
                fixture.close()
            }
            let original = try fixture.action(model.name)
            var attempts: [String] = []
            model.onOwnerBody = { [weak model] in
                guard let model else { return }
                model.onOwnerBody = nil
                let before = model.accesses
                attempts.append("body")
                original.activate()
                original.repeatActivate()
                XCTAssertEqual(model.accesses, before)
            }
            model.onConstruction = { [weak model] action in
                guard let model else { return }
                model.onConstruction = nil
                let before = model.accesses
                attempts.append("construction")
                action.activate()
                action.repeatActivate()
                XCTAssertEqual(model.accesses, before)
            }
            model.onAppear = { [weak model] action in
                guard let model else { return }
                model.onAppear = nil
                let before = model.accesses
                attempts.append("appear")
                action.activate()
                action.repeatActivate()
                XCTAssertEqual(model.accesses, before)
            }
            model.version = 1
            model.resetAccesses()

            fixture.rebuild()

            XCTAssertEqual(attempts, ["body", "construction", "appear"])
            XCTAssertTrue(model.choices.isEmpty)
            XCTAssertTrue(model.setters.isEmpty)
            XCTAssertTrue(model.presented)
            assertInert(original, model: model, fixture: fixture)
            model.resetAccesses()
            try fixture.action(model.name).activate()
            fixture.flush()
            XCTAssertEqual(model.choices, [1])
            XCTAssertEqual(model.setters, [1])
            XCTAssertFalse(model.presented)
        }
    }

    func testDisappearOpeningAReplacementAlertNeverRestoresFocusIntoTheBackground() async throws {
        try withAlertActivityTextLayout {
            let primary = RetainedAlertActivityModel(name: "primary")
            let replacement = RetainedAlertActivityModel(name: "replacement")
            primary.presented = false
            replacement.presented = false
            let fixture = RetainedAlertActivityHost(
                RetainedAlertActivityReplacementRoot(primary: primary, replacement: replacement))
            defer {
                primary.onDisappear = nil
                fixture.close()
            }
            let background = try fixture.focus("primary.background")
            primary.presented = true
            fixture.rebuild()
            _ = try fixture.focus("primary.choose")
            let original = try fixture.action(primary.name)
            let backgroundEntries = primary.backgroundFocusEntries
            var disappearances = 0
            primary.onDisappear = { [weak primary, weak replacement, weak fixture] _ in
                guard let primary, let replacement, let fixture else { return }
                primary.onDisappear = nil
                disappearances += 1
                replacement.presented = true
                replacement.version = 1
                fixture.rebuild()
            }

            original.activate()
            fixture.flush()
            fixture.finishTransitions()

            XCTAssertEqual(disappearances, 1)
            XCTAssertFalse(primary.presented)
            XCTAssertTrue(replacement.presented)
            XCTAssertTrue(fixture.contains("replacement.choose"))
            XCTAssertFalse(fixture.runtime.focusedNode === background)
            XCTAssertEqual(
                primary.backgroundFocusEntries, backgroundEntries, "A stale ticket must not steal focus transiently")
            let modal = try XCTUnwrap(fixture.runtime.activeModalPresentationNode)
            XCTAssertTrue(alertActivityNodes(in: modal).contains { $0.accessibilityIdentifier == "replacement.choose" })
            if let focused = fixture.runtime.focusedNode {
                XCTAssertTrue(alertActivityNodes(in: modal).contains { $0 === focused })
            }
            assertInert(original, model: primary, fixture: fixture)
            XCTAssertTrue(replacement.choices.isEmpty)
            XCTAssertTrue(replacement.setters.isEmpty)
        }
    }

    func testDisappearClosingTheHostCannotRestoreOldFocusOrReactivateAnAction() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            model.presented = false
            let fixture = RetainedAlertActivityHost(RetainedAlertActivityOwner(model: model))
            defer {
                model.onDisappear = nil
                fixture.close()
            }
            _ = try fixture.focus("\(model.name).background")
            model.presented = true
            fixture.rebuild()
            _ = try fixture.focus("\(model.name).choose")
            let original = try fixture.action(model.name)
            let backgroundEntries = model.backgroundFocusEntries
            var closes = 0
            fixture.host.onWindowClosed = { _ in closes += 1 }
            model.onDisappear = { [weak model, weak fixture] _ in
                model?.onDisappear = nil
                fixture?.close()
            }
            model.resetAccesses()

            original.activate()
            fixture.flush()
            fixture.renderRuntime()

            XCTAssertEqual(closes, 1)
            XCTAssertEqual(model.choices, [0])
            XCTAssertEqual(model.setters, [0])
            XCTAssertEqual(model.backgroundFocusEntries, backgroundEntries)
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertFalse(fixture.host.currentTimerState.isEnabled)
            assertInert(original, model: model, fixture: fixture)
        }
    }

    func testCloseAndHostDeinitRevokeActionsBeforeCapturedPayloadDeinitializersRun() async throws {
        try withAlertActivityTextLayout {
            for dropsWithoutClose in [false, true] {
                let model = RetainedAlertActivityModel()
                model.capturesPayload = true
                let fixture = RetainedAlertActivityHost(RetainedAlertActivityOwner(model: model))
                defer {
                    model.onPayloadRelease = nil
                    fixture.close()
                }
                let original = try fixture.action(model.name)
                let runtime = fixture.runtime
                weak var releasedHost = fixture.retainedHost
                weak var payload = model.payload
                XCTAssertNotNil(payload)
                let before = model.accesses
                let releases = model.payloadReleases
                var releaseAccesses: [RetainedAlertActivityAccesses] = []
                model.onPayloadRelease = { [weak model] in
                    original.activate()
                    original.repeatActivate()
                    if let model { releaseAccesses.append(model.accesses) }
                }

                if dropsWithoutClose { fixture.dropHost() } else { fixture.close() }

                XCTAssertNil(payload, "Escaped handlers retain receipts, not authored action captures")
                XCTAssertGreaterThan(model.payloadReleases, releases)
                XCTAssertFalse(releaseAccesses.isEmpty)
                XCTAssertTrue(releaseAccesses.allSatisfy { $0 == before })
                assertInert(original, model: model, fixture: fixture)
                XCTAssertTrue(model.presented)
                if !dropsWithoutClose { fixture.dropHost() }
                XCTAssertNil(releasedHost)
                assertInert(original, model: model, fixture: fixture)
                withExtendedLifetime(runtime) {}
            }
        }
    }

    func testRetiredAlertNodesPayloadAndRuntimeReleaseWhileOnlyEscapedReceiptsRemain() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            model.capturesPayload = true
            let fixture = RetainedAlertActivityHost(RetainedAlertActivityOwner(model: model))
            defer { fixture.close() }
            let original = try fixture.action(model.name)
            weak var overlay = fixture.nodes.first { $0.nodeTag == "alert-overlay" }
            weak var button = try fixture.node("\(model.name).choose")
            weak var payload = model.payload
            weak var runtime = fixture.retainedHost?.hostedRuntime
            weak var host = fixture.retainedHost
            XCTAssertNotNil(overlay)
            XCTAssertNotNil(button)
            XCTAssertNotNil(payload)

            model.presented = false
            fixture.rebuild()
            fixture.finishTransitions()

            XCTAssertNil(payload)
            XCTAssertNil(overlay, "Alert layout and dismissal callbacks must not retain the removed overlay")
            XCTAssertNil(button, "An escaped action must not retain its removed construction or retained button")
            assertInert(original, model: model, fixture: fixture)
            fixture.dropHost()
            withExtendedLifetime((model, fixture, original)) {
                XCTAssertNil(host)
                XCTAssertNil(runtime)
                XCTAssertNil(payload)
                XCTAssertNil(overlay)
                XCTAssertNil(button)
            }
            assertInert(original, model: model, fixture: fixture)
        }
    }

    func testQueuedAcceptedItemReplacementRejectsTheAdmittedOldReset() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel(kind: .item)
            let fixture = RetainedAlertActivityHost(RetainedAlertActivityOwner(model: model))
            defer {
                model.onGet = nil
                model.onChoice = nil
                fixture.host.onReloadContentCompleted = nil
                fixture.close()
            }
            let original = try fixture.action(model.name)
            var completedVersions: [Int] = []
            var completedItems: [Int?] = []
            fixture.host.onReloadContentCompleted = { [weak model] in
                guard let model else { return }
                completedVersions.append(model.version)
                completedItems.append(model.item?.id.value)
            }
            model.onChoice = { [weak model, weak fixture] in
                guard let model, let fixture else { return }
                model.onChoice = nil
                model.version = 1
                model.item = RetainedAlertActivityItem(id: .init(value: 2), title: "Replacement")
                model.onGet = { [weak model, weak fixture] in
                    guard let model, let fixture else { return }
                    model.onGet = nil
                    model.version = 2
                    model.item = RetainedAlertActivityItem(id: .init(value: 3), title: "Intermediate")
                    fixture.rebuild()
                    model.version = 3
                    model.item = RetainedAlertActivityItem(id: .init(value: 2), title: "Final replacement")
                    fixture.rebuild()
                }
                fixture.rebuild()
            }
            model.resetAccesses()

            original.activate()
            fixture.flush()

            XCTAssertEqual(model.choices, [0])
            XCTAssertTrue(model.setters.isEmpty, "An old flight cannot reset an accepted replacement item")
            XCTAssertEqual(model.item?.id.value, 2)
            XCTAssertFalse(model.getters.contains(2), "The superseded intermediate candidate was never evaluated")
            XCTAssertFalse(completedVersions.isEmpty)
            XCTAssertTrue(completedVersions.allSatisfy { $0 == 3 })
            XCTAssertTrue(completedItems.allSatisfy { $0 == 2 })
            assertInert(original, model: model, fixture: fixture)
            fixture.host.onReloadContentCompleted = nil
            model.resetAccesses()
            try fixture.action(model.name).activate()
            fixture.flush()
            XCTAssertEqual(model.choices, [3])
            XCTAssertEqual(model.setters, [3])
            XCTAssertNil(model.item)
        }
    }

    func testCoalescedUnobservedBooleanAbsenceDoesNotCancelTheAdmittedGeneration() async throws {
        try withAlertActivityTextLayout {
            let model = RetainedAlertActivityModel()
            let fixture = RetainedAlertActivityHost(RetainedAlertActivityOwner(model: model))
            defer {
                model.onGet = nil
                model.onChoice = nil
                fixture.host.onReloadContentCompleted = nil
                fixture.close()
            }
            let original = try fixture.action(model.name)
            var completedDuringChoice: [Bool] = []
            var choosing = false
            fixture.host.onReloadContentCompleted = { [weak model, weak fixture] in
                guard choosing, let model, let fixture else { return }
                completedDuringChoice.append(model.presented && fixture.contains("\(model.name).choose"))
            }
            model.onChoice = { [weak model, weak fixture] in
                guard let model, let fixture else { return }
                model.onChoice = nil
                choosing = true
                defer { choosing = false }
                model.version = 1
                model.onGet = { [weak model, weak fixture] in
                    guard let model, let fixture else { return }
                    model.onGet = nil
                    // Neither intermediate Boolean write is an accepted
                    // absence. The original admitted flight keeps its reset.
                    model.version = 2
                    model.presented = false
                    fixture.rebuild()
                    model.version = 3
                    model.presented = true
                    fixture.rebuild()
                }
                fixture.rebuild()
            }
            model.resetAccesses()

            original.activate()
            fixture.flush()

            XCTAssertEqual(model.choices, [0])
            XCTAssertEqual(model.setters, [0], "The flight pins its admitted reset, not the newest equal-true binding")
            XCTAssertFalse(model.getters.contains(2))
            XCTAssertFalse(completedDuringChoice.isEmpty)
            XCTAssertTrue(completedDuringChoice.allSatisfy { $0 })
            XCTAssertFalse(model.presented)
            XCTAssertFalse(fixture.contains("\(model.name).choose"))
            assertInert(original, model: model, fixture: fixture)
        }
    }

    private func assertInert(
        _ action: RetainedAlertActivityAction, model: RetainedAlertActivityModel, fixture: RetainedAlertActivityHost,
        renderOnly: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) {
        let before = model.accesses
        let host = fixture.retainedHost
        let reloads = host?.executedReloadCount
        let focus = host?.hostedRuntime.focusedNode
        action.activate()
        action.repeatActivate()
        if renderOnly { fixture.renderRuntime() } else { fixture.flush() }
        XCTAssertEqual(
            model.accesses, before, "A retired action must not read, choose, reset, or invalidate", file: file,
            line: line)
        XCTAssertEqual(host?.executedReloadCount, reloads, file: file, line: line)
        XCTAssertTrue(host?.hostedRuntime.focusedNode === focus, file: file, line: line)
    }
}

private enum RetainedAlertActivityKind {
    case boolean
    case item
}

private struct RetainedAlertActivityID: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "same item description" }
}

private struct RetainedAlertActivityItem: Identifiable {
    let id: RetainedAlertActivityID
    let title: String
}

private struct RetainedAlertActivityAccesses: Equatable {
    let getters: [Int]
    let setters: [Int]
    let choices: [Int]
}

@MainActor
private struct RetainedAlertActivityAction {
    let version: Int
    let activate: () -> Void
    let repeatActivate: () -> Void
}

@MainActor
private final class RetainedAlertActivityModel {
    let kind: RetainedAlertActivityKind
    let name: String
    var presented = true
    var item: RetainedAlertActivityItem? = .init(id: .init(value: 1), title: "Original")
    var version = 0
    var getters: [Int] = []
    var setters: [Int] = []
    var choices: [Int] = []
    var captured: [RetainedAlertActivityAction] = []
    var ownerVersions: [Int] = []
    var backgroundBodies = 0
    var backgroundFocusEntries = 0
    var counter: Binding<Int>?
    var capturesPayload = false
    weak var payload: RetainedAlertActivityPayload?
    var payloadReleases = 0
    var onPayloadRelease: (@MainActor () -> Void)?
    var onOwnerBody: (@MainActor () -> Void)?
    var onConstruction: (@MainActor (RetainedAlertActivityAction) -> Void)?
    var onAppear: (@MainActor (RetainedAlertActivityAction) -> Void)?
    var onDisappear: (@MainActor (Int) -> Void)?
    var onGet: (@MainActor () -> Void)?
    var onChoice: (@MainActor () -> Void)?

    init(kind: RetainedAlertActivityKind = .boolean, name: String = "subject") {
        self.kind = kind
        self.name = name
    }

    var accesses: RetainedAlertActivityAccesses {
        .init(getters: getters, setters: setters, choices: choices)
    }

    func resetAccesses() {
        getters.removeAll()
        setters.removeAll()
        choices.removeAll()
    }

    func booleanBinding(version: Int) -> Binding<Bool> {
        Binding(
            get: {
                self.getters.append(version)
                self.onGet?()
                return self.presented
            },
            set: {
                self.setters.append(version)
                self.presented = $0
            })
    }

    func itemBinding(version: Int) -> Binding<RetainedAlertActivityItem?> {
        Binding(
            get: {
                self.getters.append(version)
                self.onGet?()
                return self.item
            },
            set: {
                self.setters.append(version)
                self.item = $0
            })
    }

    func choose(version: Int) {
        choices.append(version)
        onChoice?()
    }
}

@MainActor
private final class RetainedAlertActivityPayload {
    private weak var model: RetainedAlertActivityModel?

    init(model: RetainedAlertActivityModel) { self.model = model }

    isolated deinit {
        model?.payloadReleases += 1
        model?.onPayloadRelease?()
    }
}

@MainActor
private struct RetainedAlertActivityOwner: View {
    let model: RetainedAlertActivityModel
    var versionOverride: Int? = nil

    var body: some View {
        model.onOwnerBody?()
        let version = versionOverride ?? model.version
        model.ownerVersions.append(version)
        let base = RetainedAlertActivityBackground(model: model)
        switch model.kind {
        case .boolean:
            return AnyView(
                base.alert("Alert \(model.name)", isPresented: model.booleanBinding(version: version)) {
                    RetainedAlertActivityCapturedButton(model: model, version: version)
                })
        case .item:
            return AnyView(
                base.alert(item: model.itemBinding(version: version)) { item in
                    Alert(
                        title: Text(item.title),
                        dismissButton: .default(Text("Choose \(model.name)")) { model.choose(version: version) })
                })
        }
    }
}

@MainActor
private struct RetainedAlertActivityCapturedButton: View {
    typealias Body = Never
    let model: RetainedAlertActivityModel
    let version: Int

    var body: Never { fatalError("RetainedAlertActivityCapturedButton uses makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let payload = model.capturesPayload ? RetainedAlertActivityPayload(model: model) : nil
        if model.capturesPayload { model.payload = payload }
        let component = Button("Choose \(model.name)") {
            withExtendedLifetime(payload) { model.choose(version: version) }
        }
        .accessibilityIdentifier("\(model.name).choose")
        .accessibilityValue(String(version))
        .id(version)
        .makeComponent(context: context)
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            guard let button = alertActivityNodes(in: node).first(where: { $0.onActivate != nil }),
                let activate = button.onActivate, let repeatActivate = button.onRepeatActivate
            else {
                XCTFail("Expected a constructed alert button with both activation handlers")
                return node
            }
            let action = RetainedAlertActivityAction(
                version: version, activate: activate, repeatActivate: repeatActivate)
            model.captured.append(action)
            model.onConstruction?(action)
            let previousAppear = node.onAppear
            node.onAppear = { [weak model] in
                previousAppear?()
                model?.onAppear?(action)
            }
            let previousDisappear = node.onDisappear
            node.onDisappear = { [weak model] in
                previousDisappear?()
                model?.onDisappear?(version)
            }
            return node
        }
    }
}

@MainActor
private struct RetainedAlertActivityBackground: View {
    let model: RetainedAlertActivityModel
    @State private var count = 10

    var body: some View {
        model.backgroundBodies += 1
        model.counter = $count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Count \(count)").accessibilityIdentifier("\(model.name).state")
            RetainedAlertActivityBackgroundButton(model: model)
        }
    }
}

@MainActor
private struct RetainedAlertActivityBackgroundButton: View {
    typealias Body = Never
    let model: RetainedAlertActivityModel

    var body: Never { fatalError("RetainedAlertActivityBackgroundButton uses makeComponent") }

    func makeComponent(context: ViewBuildContext) -> Component {
        let component = Button("Background \(model.name)") {}
            .accessibilityIdentifier("\(model.name).background")
            .frame(width: 240, height: 40)
            .makeComponent(context: context)
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            guard let focusable = alertActivityNodes(in: node).first(where: { $0.isFocusable }) else {
                XCTFail("Expected a focusable background button")
                return node
            }
            let existing = focusable.onFocusEnter
            focusable.onFocusEnter = { [weak model] in
                existing?()
                model?.backgroundFocusEntries += 1
            }
            return node
        }
    }
}

@MainActor
private final class RetainedAlertActivityTabs {
    var selection = 0
}

@MainActor
private struct RetainedAlertActivityTabbedRoot: View {
    let model: RetainedAlertActivityModel
    let tabs: RetainedAlertActivityTabs

    var body: some View {
        TabView(selection: Binding(get: { tabs.selection }, set: { tabs.selection = $0 })) {
            RetainedAlertActivityOwner(model: model).tag(0).tabItem { Text("Alert") }
            Text("Other page").tag(1).tabItem { Text("Other") }
        }
    }
}

@MainActor
private final class RetainedAlertActivityGeometry {
    var bodies = 0
}

@MainActor
private struct RetainedAlertActivityGeometryRoot: View {
    let model: RetainedAlertActivityModel
    let outside: RetainedAlertActivityModel
    let geometry: RetainedAlertActivityGeometry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                WinSwiftUI.Color.clear.frame(width: 80)
                GeometryReader { proxy in
                    RetainedAlertActivityGeometryContent(model: model, geometry: geometry, size: proxy.size)
                }
            }
            RetainedAlertActivityBackground(model: outside).frame(height: 60)
        }
    }
}

@MainActor
private struct RetainedAlertActivityGeometryContent: View {
    let model: RetainedAlertActivityModel
    let geometry: RetainedAlertActivityGeometry
    let size: Size

    var body: some View {
        geometry.bodies += 1
        return VStack(alignment: .leading, spacing: 0) {
            if size.width >= 350 {
                RetainedAlertActivityOwner(model: model, versionOverride: Int(size.width.rounded()))
            } else {
                Text("Alert omitted in this slot")
            }
        }
    }
}

@MainActor
private struct RetainedAlertActivityReplacementRoot: View {
    let primary: RetainedAlertActivityModel
    let replacement: RetainedAlertActivityModel

    var body: some View {
        let version = replacement.version
        return RetainedAlertActivityOwner(model: primary)
            .alert("Replacement alert", isPresented: replacement.booleanBinding(version: version)) {
                RetainedAlertActivityCapturedButton(model: replacement, version: version)
            }
    }
}

@MainActor
private final class RetainedAlertActivityRootControl {
    var revision: Binding<Int>?
}

@MainActor
private struct RetainedAlertActivityHostedRoot<Content: View>: View {
    @State private var revision = 0
    let control: RetainedAlertActivityRootControl
    let content: Content

    var body: some View {
        control.revision = $revision
        let _ = revision
        return content
    }
}

@MainActor
private func alertActivityNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private func withAlertActivityTextLayout(_ body: () throws -> Void) rethrows {
    let previous = NativeTextRenderer.testingOverrides
    NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
        let glyphs = Array(text).enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                fontSize: style.nativeFontPixelSize, sourceIndex: index)
        }
        let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
        return NativeTextLayoutResult(
            lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
            contentSize: size, measuredSize: size)
    }
    defer { NativeTextRenderer.testingOverrides = previous }
    try body()
}

@MainActor
private final class RetainedAlertActivityHost {
    private(set) var retainedHost: WinSwiftUIWindowHost?
    let window: Win32Window
    let clock: RuntimeTestClock
    private let control: RetainedAlertActivityRootControl

    var host: WinSwiftUIWindowHost { retainedHost! }
    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var nodes: [ViewNode] { alertActivityNodes(in: runtime.root) }

    init<Content: View>(_ content: Content, size: IntSize = IntSize(width: 400, height: 400)) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let control = RetainedAlertActivityRootControl()
        let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
        let window = Win32Window(title: "Retained alert activity", clientSize: size)
        window.testScaleFactorOverride = 1
        window.testMonitorRefreshRateOverride = 60
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Retained alert activity", size: size, clearColor: .black,
                content: [AnyView(RetainedAlertActivityHostedRoot(control: control, content: content))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.clock = clock
        self.control = control
        self.window = window
        retainedHost = host
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func close() { retainedHost?.windowWillClose(window) }
    func dropHost() { retainedHost = nil }

    func flush() {
        guard let retainedHost else { return }
        for _ in 0..<2 {
            clock.now += 0.02
            retainedHost.windowNeedsDisplay(window)
        }
    }

    func rebuild() {
        guard let revision = control.revision else { return XCTFail("Missing mounted root revision") }
        revision.wrappedValue += 1
        flush()
    }

    func renderRuntime() {
        guard let retainedHost else { return }
        clock.now += 0.02
        _ = retainedHost.hostedRuntime.renderFrame(at: clock.now)
    }

    func finishTransitions() {
        clock.now += 1
        _ = runtime.tickAnimations(at: clock.now)
        _ = runtime.renderFrame(at: clock.now)
    }

    func resizeRuntime(to size: IntSize) {
        runtime.setRootSize(size)
        renderRuntime()
    }

    func contains(_ identifier: String) -> Bool { nodes.contains { $0.accessibilityIdentifier == identifier } }

    func node(_ identifier: String) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one \(identifier)")
        return try XCTUnwrap(matches.first)
    }

    func action(_ name: String) throws -> RetainedAlertActivityAction {
        let matches = nodes.filter { $0.onActivate != nil && $0.accessibilityLabel == "Choose \(name)" }
        XCTAssertEqual(matches.count, 1, "Expected one alert action for \(name)")
        let node = try XCTUnwrap(matches.first)
        let activate = try XCTUnwrap(node.onActivate)
        let repeatActivate = try XCTUnwrap(node.onRepeatActivate)
        // Builder fixtures expose their version as an accessibility value;
        // retained identity keys remain opaque. Legacy alerts do not need it.
        let version = node.accessibilityValue.flatMap { Int($0) } ?? 0
        return RetainedAlertActivityAction(version: version, activate: activate, repeatActivate: repeatActivate)
    }

    func reader() throws -> ViewNode {
        let matches = nodes.filter { $0.geometryReaderBuild != nil }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    @discardableResult
    func focus(_ identifier: String) throws -> ViewNode {
        let identified = try node(identifier)
        let focusable = try XCTUnwrap(alertActivityNodes(in: identified).first { $0.isFocusable })
        runtime.requestFocus(focusable)
        XCTAssertTrue(runtime.focusedNode === focusable)
        return focusable
    }
}
