import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class SheetDismissActivityTests: XCTestCase {
    func testAcceptedItemReplacementNeverRevivesAnEarlierDismissAction() async throws {
        try withTextLayout {
            let model = SheetActivityModel(kind: .item)
            let fixture = SheetActivityHost(SheetActivityOwner(model: model))
            defer { fixture.close() }
            let first = try model.action()
            let firstID = try XCTUnwrap(model.item).id
            model.item = SheetActivityItem(id: SheetActivityID(value: 2), title: "Second")
            fixture.rebuild()
            let second = try model.action()
            assertInert(first, model: model, fixture: fixture)

            model.item = SheetActivityItem(id: firstID, title: "First again")
            fixture.rebuild()

            assertInert(first, model: model, fixture: fixture)
            assertInert(second, model: model, fixture: fixture)
            XCTAssertEqual(model.item?.id, firstID)
            model.resetAccesses()
            try model.action()()
            fixture.flush()
            XCTAssertNil(model.item)
            XCTAssertEqual(model.setters, [0])
            XCTAssertEqual(model.callbacks, [0])
            assertInert(first, model: model, fixture: fixture)
        }
    }

    func testAcceptedBooleanAbsenceAndReopenRetireTheOldAction() async throws {
        try withTextLayout {
            let model = SheetActivityModel(kind: .boolean)
            let fixture = SheetActivityHost(SheetActivityOwner(model: model))
            defer { fixture.close() }
            let first = try model.action()
            model.presented = false
            fixture.rebuild()
            assertInert(first, model: model, fixture: fixture)

            model.presented = true
            fixture.rebuild()

            assertInert(first, model: model, fixture: fixture)
            XCTAssertTrue(model.presented)
            model.resetAccesses()
            try model.action()()
            fixture.flush()
            XCTAssertFalse(model.presented)
            XCTAssertEqual(model.setters, [0])
            XCTAssertEqual(model.callbacks, [0])
            model.presented = true
            fixture.rebuild()
            assertInert(first, model: model, fixture: fixture)
        }
    }

    func testContinuouslyAcceptedActionsUseTheLatestBindingAndCallback() async throws {
        try withTextLayout {
            for kind in [SheetActivityKind.boolean, .item] {
                let model = SheetActivityModel(kind: kind)
                let fixture = SheetActivityHost(SheetActivityOwner(model: model))
                defer { fixture.close() }
                let original = try model.action()
                for version in [1, 2] {
                    model.version = version
                    model.item = SheetActivityItem(id: SheetActivityID(value: 1), title: "Version \(version)")
                    fixture.rebuild()
                }
                model.resetAccesses()

                original()
                fixture.flush()

                XCTAssertFalse(model.hasPresentation)
                XCTAssertFalse(model.getters.isEmpty)
                XCTAssertTrue(model.getters.allSatisfy { $0 == 2 })
                XCTAssertEqual(model.setters, [2])
                XCTAssertEqual(model.callbacks, [2])
                assertInert(original, model: model, fixture: fixture)
            }
        }
    }

    func testInactiveTabPreservesStateAndStateObjectButNotDismissalAuthority() async throws {
        try withTextLayout {
            let model = SheetActivityModel(kind: .boolean)
            model.content = .stateful
            let tabs = SheetActivityTabsModel()
            let fixture = SheetActivityHost(SheetActivityTabbedRoot(model: model, tabs: tabs))
            defer { fixture.close() }
            let original = try model.action()
            let state = try XCTUnwrap(model.counter)
            let object = try XCTUnwrap(model.object)
            state.wrappedValue = 11
            object.value = 21
            fixture.flush()
            tabs.selection = 1
            fixture.rebuild()
            fixture.finishTransitions()
            let ownerBodies = model.ownerBodies
            let contentBodies = model.contentBodies
            let statefulBodies = model.statefulBodies
            assertInert(original, model: model, fixture: fixture)

            state.wrappedValue = 12
            object.value = 22
            fixture.flush()
            fixture.rebuild()

            XCTAssertEqual(state.wrappedValue, 12)
            XCTAssertEqual(object.value, 22)
            XCTAssertEqual(model.ownerBodies, ownerBodies)
            XCTAssertEqual(model.contentBodies, contentBodies)
            XCTAssertEqual(model.statefulBodies, statefulBodies)
            assertInert(original, model: model, fixture: fixture)
            tabs.selection = 0
            fixture.rebuild()
            fixture.finishTransitions()
            XCTAssertTrue(model.object === object)
            XCTAssertEqual(try XCTUnwrap(model.counter).wrappedValue, 12)
            XCTAssertEqual(try fixture.node("subject.state").text, "12 / 22")
            assertInert(original, model: model, fixture: fixture)
            XCTAssertTrue(model.presented)
            try model.action()()
            fixture.flush()
            XCTAssertFalse(model.presented)
        }
    }

    func testRawBooleanAndItemSheetDismissalStillWorksWithoutACoordinator() async throws {
        try withTextLayout {
            for kind in [SheetActivityKind.boolean, .item] {
                let model = SheetActivityModel(kind: kind)
                let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 400)))
                let host = ComponentHost(runtime: runtime)
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 400, height: 400) },
                    invalidateHandler: { [weak host] in host?.reload() })
                host.setComponents { [SheetActivityOwner(model: model).makeComponent(context: context)] }
                defer {
                    runtime.stopRenderLifecycleCallbacks()
                    runtime.cancelRenderLifecycleTasks()
                    model.actions.removeAll()
                }
                _ = runtime.renderFrame()
                let dismiss = try model.action()
                model.resetAccesses()

                dismiss()
                _ = runtime.renderFrame()

                XCTAssertFalse(model.hasPresentation)
                XCTAssertEqual(model.setters, [0])
                XCTAssertEqual(model.callbacks, [0])
                XCTAssertFalse(sheetActivityNodes(in: runtime.root).contains { $0.nodeTag == "sheet-overlay" })
                withExtendedLifetime(host) {}
            }
        }
    }

    func testDeferredGeometryActivityChangesDoNotSweepAnOutsideSheet() async throws {
        try withTextLayout {
            let inside = SheetActivityModel(kind: .boolean, name: "inside")
            let outside = SheetActivityModel(kind: .boolean, name: "outside")
            let geometry = SheetActivityGeometryProbe()
            let fixture = SheetActivityHost(
                SheetActivityGeometryRoot(inside: inside, outside: outside, geometry: geometry))
            defer { fixture.close() }
            let original = try inside.action()
            let outsideAction = try outside.action()
            let reader = try fixture.reader()
            let resolves = fixture.runtime.geometryReaderResolveCount
            let reloads = fixture.host.executedReloadCount

            fixture.resizeRuntime(to: IntSize(width: 480, height: 420))

            XCTAssertTrue(try fixture.reader() === reader)
            XCTAssertGreaterThan(fixture.runtime.geometryReaderResolveCount, resolves)
            XCTAssertEqual(fixture.host.executedReloadCount, reloads)
            inside.resetAccesses()
            original()
            fixture.flush()
            XCTAssertFalse(inside.presented)
            XCTAssertEqual(inside.setters, [480], "A continuous resize publishes the latest accepted configuration")
            XCTAssertEqual(inside.callbacks, [480])
            XCTAssertTrue(outside.presented)

            inside.presented = true
            fixture.rebuild()
            let beforeOmission = try inside.action()
            let outsideBodies = outside.ownerBodies
            let outsideActions = outside.actions.count
            let rootReloads = fixture.host.executedReloadCount
            fixture.resizeRuntime(to: IntSize(width: 260, height: 360))
            XCTAssertFalse(fixture.contains("inside.sheet"))
            assertInert(beforeOmission, model: inside, fixture: fixture)
            fixture.resizeRuntime(to: IntSize(width: 520, height: 460))
            XCTAssertTrue(fixture.contains("inside.sheet"))
            XCTAssertEqual(fixture.host.executedReloadCount, rootReloads)
            XCTAssertEqual(outside.ownerBodies, outsideBodies)
            XCTAssertEqual(outside.actions.count, outsideActions)
            assertInert(beforeOmission, model: inside, fixture: fixture)
            let returned = try inside.action()

            outside.resetAccesses()
            outsideAction()
            fixture.flush()
            XCTAssertFalse(outside.presented)
            XCTAssertEqual(outside.setters, [0])
            XCTAssertEqual(outside.callbacks, [0])
            XCTAssertTrue(inside.presented)
            returned()
            fixture.flush()
            XCTAssertFalse(inside.presented)
        }
    }

    func testOldReaderBuildersStayInertAfterReplacementAndTabInactivity() async throws {
        try withTextLayout {
            let model = SheetActivityModel(kind: .boolean)
            let tabs = SheetActivityTabsModel()
            let geometry = SheetActivityGeometryProbe()
            let fixture = SheetActivityHost(
                SheetActivityTabbedReaderRoot(model: model, tabs: tabs, geometry: geometry))
            defer { fixture.close() }
            let firstReader = try fixture.reader()
            let firstLease = try XCTUnwrap(firstReader.retainedSubtreeBuildLease)
            let firstBuilder = try XCTUnwrap(firstReader.geometryReaderBuild)
            XCTAssertTrue(firstLease.canBuild)

            fixture.rebuild()

            XCTAssertTrue(try fixture.reader() === firstReader)
            assertRetiredLease(firstLease)
            let afterReplacement = geometry.bodies
            XCTAssertTrue(firstBuilder(fixture.runtime, Size(width: 490, height: 320)).isEmpty)
            XCTAssertEqual(geometry.bodies, afterReplacement)
            let activeLease = try XCTUnwrap(firstReader.retainedSubtreeBuildLease)
            let activeBuilder = try XCTUnwrap(firstReader.geometryReaderBuild)
            XCTAssertTrue(activeLease.canBuild)
            tabs.selection = 1
            fixture.rebuild()
            fixture.finishTransitions()
            let inactiveBodies = geometry.bodies
            assertRetiredLease(activeLease)
            XCTAssertTrue(activeBuilder(fixture.runtime, Size(width: 510, height: 340)).isEmpty)
            XCTAssertEqual(geometry.bodies, inactiveBodies)

            tabs.selection = 0
            fixture.rebuild()
            fixture.finishTransitions()

            let returnedReader = try fixture.reader()
            XCTAssertFalse(returnedReader === firstReader)
            XCTAssertTrue(try XCTUnwrap(returnedReader.retainedSubtreeBuildLease).canBuild)
            assertRetiredLease(firstLease)
            assertRetiredLease(activeLease)
            let returnedBodies = geometry.bodies
            XCTAssertTrue(firstBuilder(fixture.runtime, Size(width: 530, height: 350)).isEmpty)
            XCTAssertTrue(activeBuilder(fixture.runtime, Size(width: 550, height: 360)).isEmpty)
            XCTAssertEqual(geometry.bodies, returnedBodies)
            fixture.resizeRuntime(to: IntSize(width: 560, height: 440))
            XCTAssertGreaterThan(geometry.bodies, returnedBodies)
            try model.action()()
            fixture.flush()
            XCTAssertFalse(model.presented)
        }
    }

    func testCloseAndHostReleaseRevokeEscapedActionsBeforeConfigurationPayloadCleanup() async throws {
        try withTextLayout {
            for dropsWithoutClose in [false, true] {
                let model = SheetActivityModel(kind: .item)
                model.capturesPayload = true
                let fixture = SheetActivityHost(SheetActivityOwner(model: model))
                defer {
                    model.onPayloadRelease = nil
                    fixture.close()
                }
                let runtime = fixture.runtime
                let dismiss = try model.action()
                weak var releasedHost = fixture.retainedHost
                weak var payload = model.payload
                XCTAssertNotNil(payload)
                let before = model.accesses
                let releasesBefore = model.payloadReleases
                var closeCalls = 0
                fixture.host.onWindowClosed = { _ in closeCalls += 1 }
                model.onPayloadRelease = { [weak model] in
                    dismiss()
                    if let model { model.releaseAccesses.append(model.accesses) }
                }

                if dropsWithoutClose { fixture.dropHost() } else { fixture.close() }

                XCTAssertNil(payload, "An escaped action must not own the accepted binding/callback payload")
                XCTAssertGreaterThan(model.payloadReleases, releasesBefore)
                XCTAssertFalse(model.releaseAccesses.isEmpty)
                XCTAssertTrue(model.releaseAccesses.allSatisfy { $0 == before })
                XCTAssertEqual(closeCalls, dropsWithoutClose ? 0 : 1)
                assertInert(dismiss, model: model, fixture: fixture)
                XCTAssertNotNil(model.item)
                if !dropsWithoutClose { fixture.dropHost() }
                XCTAssertNil(releasedHost)
                assertInert(dismiss, model: model, fixture: fixture)
                withExtendedLifetime(runtime) {}
            }
        }
    }

    func testCopiedActionGetterRecursionSharesOneDismissalGuard() async throws {
        try withTextLayout {
            for kind in [SheetActivityKind.boolean, .item] {
                let model = SheetActivityModel(kind: kind)
                let fixture = SheetActivityHost(SheetActivityOwner(model: model))
                defer {
                    model.onGet = nil
                    fixture.close()
                }
                let original = try model.action()
                let copy = original
                var entries = 0
                model.onGet = { [weak model] in
                    entries += 1
                    if entries == 1 { copy() }
                    model?.onGet = nil
                }
                model.resetAccesses()

                original()
                fixture.flush()

                XCTAssertEqual(entries, 1, "The recursive copy must refuse before another application getter")
                XCTAssertFalse(model.hasPresentation)
                XCTAssertEqual(model.setters, [0])
                XCTAssertEqual(model.callbacks, [0])
                assertInert(copy, model: model, fixture: fixture)
            }
        }
    }

    func testGetterAcceptedRebuildAbortsTheInterruptedConfigurationWithoutRetiringItsReceipt() async throws {
        try withTextLayout {
            for kind in [SheetActivityKind.boolean, .item] {
                let model = SheetActivityModel(kind: kind)
                let fixture = SheetActivityHost(SheetActivityOwner(model: model))
                defer {
                    model.onGet = nil
                    fixture.close()
                }
                let original = try model.action()
                var rebuilt = 0
                model.onGet = { [weak model, weak fixture] in
                    guard let model, let fixture else { return }
                    model.onGet = nil
                    rebuilt += 1
                    model.version = 1
                    fixture.rebuild()
                }
                model.resetAccesses()

                original()

                XCTAssertEqual(rebuilt, 1)
                XCTAssertTrue(model.hasPresentation)
                XCTAssertTrue(model.setters.isEmpty)
                XCTAssertTrue(model.callbacks.isEmpty)
                model.resetAccesses()
                original()
                fixture.flush()
                XCTAssertFalse(model.hasPresentation)
                XCTAssertFalse(model.getters.isEmpty)
                XCTAssertTrue(model.getters.allSatisfy { $0 == 1 })
                XCTAssertEqual(model.setters, [1])
                XCTAssertEqual(model.callbacks, [1])
            }
        }
    }

    func testInteractiveFocusReplacementRefusesOldWriteAndEnvironmentDismissDoesNotPrepareFocus() async throws {
        try withTextLayout {
            let model = SheetActivityModel(kind: .item)
            model.item = nil
            model.content = .editor
            let fixture = SheetActivityHost(SheetActivityOwner(model: model))
            defer {
                model.onEditingChanged = nil
                model.onWrite = nil
                fixture.close()
            }
            let background = try fixture.focus("subject.background")
            model.item = SheetActivityItem(id: SheetActivityID(value: 1), title: "First")
            fixture.rebuild()
            let oldEnvironment = try model.action()
            let oldInteractive = try XCTUnwrap(
                fixture.nodes.first { $0.nodeTag == "sheet-scrim-dismiss-enabled" }?.onActivate)
            _ = try fixture.focus("subject.editor")
            model.version = 1
            fixture.rebuild()
            model.onEditingChanged = { [weak model] isEditing in
                guard !isEditing else { return }
                // This ordinary reference-backed write deliberately does not
                // rebuild the sheet while the focus callback is executing.
                model?.item = SheetActivityItem(id: SheetActivityID(value: 2), title: "Second")
            }
            model.resetAccesses()

            oldInteractive()

            XCTAssertTrue(fixture.runtime.focusedNode === background)
            XCTAssertEqual(model.item?.id, SheetActivityID(value: 2))
            XCTAssertTrue(model.setters.isEmpty)
            XCTAssertTrue(model.callbacks.isEmpty)
            let overlay = try XCTUnwrap(fixture.nodes.first { $0.nodeTag == "sheet-overlay" })
            XCTAssertTrue(
                overlay.accessibilityTraits.contains(.isModal),
                "Refusing dismissal after a focus callback must restore the current overlay's modal scope")
            model.onEditingChanged = nil
            fixture.rebuild()
            assertInert(oldEnvironment, model: model, fixture: fixture)
            let editor = try fixture.focus("subject.editor")
            var focusedAtSetter: [Bool] = []
            model.onWrite = { [weak fixture, weak editor] in
                focusedAtSetter.append(fixture?.runtime.focusedNode === editor)
            }

            try model.action()()
            fixture.flush()

            XCTAssertEqual(focusedAtSetter, [true], "Environment dismissal must not run interactive focus preparation")
            XCTAssertNil(model.item)
            XCTAssertEqual(model.setters, [1])
            XCTAssertEqual(model.callbacks, [1])
        }
    }

    func testCoalescedIdentityWritesKeepTheContinuouslyAcceptedDismissAction() async throws {
        try withTextLayout {
            for kind in [SheetActivityKind.boolean, .item] {
                let model = SheetActivityModel(kind: kind)
                let fixture = SheetActivityHost(SheetActivityOwner(model: model))
                defer {
                    model.onGet = nil
                    fixture.host.onReloadContentCompleted = nil
                    fixture.close()
                }
                let original = try model.action()
                let originalSheet = try fixture.node("subject.sheet")
                let originalID = try XCTUnwrap(model.item).id
                let ownerVersionCount = model.ownerVersions.count
                let actionVersionCount = model.actionVersions.count
                var completedVersions: [Int?] = []
                var completedPresentations: [Bool] = []
                var getterEntries = 0
                fixture.host.onReloadContentCompleted = { [weak model, weak fixture] in
                    guard let model, let fixture else { return }
                    completedVersions.append(model.actionVersions.last)
                    completedPresentations.append(fixture.contains("subject.sheet"))
                }
                model.onGet = { [weak model, weak fixture] in
                    guard let model, let fixture else { return }
                    model.onGet = nil
                    getterEntries += 1
                    // Both mounted revision writes occur inside the version 1
                    // candidate. Its active build queues the requests, and the
                    // intermediate request is obsolete before either can run.
                    model.version = 2
                    if kind == .boolean {
                        model.presented = false
                    } else {
                        model.item = SheetActivityItem(id: SheetActivityID(value: 2), title: "Intermediate")
                    }
                    fixture.rebuild()
                    model.version = 3
                    if kind == .boolean {
                        model.presented = true
                    } else {
                        model.item = SheetActivityItem(id: originalID, title: "Final")
                    }
                    fixture.rebuild()
                }
                model.version = 1
                model.resetAccesses()

                fixture.rebuild()
                fixture.flush()

                XCTAssertEqual(getterEntries, 1)
                XCTAssertEqual(Array(model.ownerVersions.dropFirst(ownerVersionCount)), [1, 3])
                XCTAssertFalse(model.getters.contains(2), "The intermediate binding was never evaluated")
                XCTAssertFalse(model.actionVersions.dropFirst(actionVersionCount).contains(2))
                XCTAssertEqual(completedVersions, [3], "Only the final candidate may finish adoption")
                XCTAssertEqual(completedPresentations, [true], "No accepted absence interrupted the presentation")
                XCTAssertTrue(try fixture.node("subject.sheet") === originalSheet)
                XCTAssertTrue(model.hasPresentation)
                XCTAssertEqual(model.item?.id, originalID)
                fixture.host.onReloadContentCompleted = nil
                model.resetAccesses()

                original()
                fixture.flush()

                XCTAssertFalse(model.hasPresentation)
                XCTAssertFalse(model.getters.isEmpty)
                XCTAssertTrue(model.getters.allSatisfy { $0 == 3 })
                XCTAssertEqual(model.setters, [3])
                XCTAssertEqual(model.callbacks, [3])
            }
        }
    }

    private func assertRetiredLease(
        _ lease: any RetainedSubtreeBuildLease, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(lease.canBuild, file: file, line: line)
        let candidate = lease.beginBuild()
        XCTAssertNil(candidate, "A retired lease must not begin a deferred epoch", file: file, line: line)
        candidate?.abandon()
        candidate?.finishAfterCallbacks()
    }

    private func assertInert(
        _ action: DismissAction, model: SheetActivityModel, fixture: SheetActivityHost,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let before = model.accesses
        let host = fixture.retainedHost
        let reloads = host?.executedReloadCount
        let focus = host?.hostedRuntime.focusedNode
        action()
        fixture.flush()
        XCTAssertEqual(
            model.accesses, before, "A retired action must not read or write application configuration", file: file,
            line: line)
        XCTAssertEqual(host?.executedReloadCount, reloads, file: file, line: line)
        XCTAssertTrue(host?.hostedRuntime.focusedNode === focus, file: file, line: line)
    }

    private func withTextLayout(_ body: () throws -> Void) throws {
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
}

private enum SheetActivityKind: Equatable {
    case boolean
    case item
}

private enum SheetActivityContentKind {
    case stateless
    case stateful
    case editor
}

private struct SheetActivityID: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "shared item description" }
}

private struct SheetActivityItem: Identifiable {
    let id: SheetActivityID
    let title: String
}

private struct SheetActivityAccesses: Equatable {
    let getters: [Int]
    let setters: [Int]
    let callbacks: [Int]
}

@MainActor
private final class SheetActivityModel {
    let kind: SheetActivityKind
    let name: String
    var presented = true
    var item: SheetActivityItem? = SheetActivityItem(id: SheetActivityID(value: 1), title: "First")
    var version = 0
    var content = SheetActivityContentKind.stateless
    var getters: [Int] = []
    var setters: [Int] = []
    var callbacks: [Int] = []
    var actions: [DismissAction] = []
    var ownerVersions: [Int] = []
    var actionVersions: [Int] = []
    var ownerBodies = 0
    var contentBodies = 0
    var statefulBodies = 0
    var counter: Binding<Int>?
    var object: SheetActivityObject?
    var editorText = "Sheet editor"
    var onGet: (@MainActor () -> Void)?
    var onWrite: (@MainActor () -> Void)?
    var onEditingChanged: (@MainActor (Bool) -> Void)?
    var capturesPayload = false
    weak var payload: SheetActivityPayload?
    var payloadReleases = 0
    var onPayloadRelease: (@MainActor () -> Void)?
    var releaseAccesses: [SheetActivityAccesses] = []

    init(kind: SheetActivityKind, name: String = "subject") {
        self.kind = kind
        self.name = name
    }

    var hasPresentation: Bool { kind == .boolean ? presented : item != nil }
    var accesses: SheetActivityAccesses { .init(getters: getters, setters: setters, callbacks: callbacks) }

    func resetAccesses() {
        getters.removeAll()
        setters.removeAll()
        callbacks.removeAll()
    }

    func action() throws -> DismissAction { try XCTUnwrap(actions.last) }

    func readBoolean(version: Int) -> Bool {
        getters.append(version)
        onGet?()
        return presented
    }

    func readItem(version: Int) -> SheetActivityItem? {
        getters.append(version)
        onGet?()
        return item
    }

    func writeBoolean(_ value: Bool, version: Int) {
        setters.append(version)
        onWrite?()
        presented = value
    }

    func writeItem(_ value: SheetActivityItem?, version: Int) {
        setters.append(version)
        onWrite?()
        item = value
    }
}

@MainActor
private final class SheetActivityPayload {
    private weak var model: SheetActivityModel?

    init(model: SheetActivityModel) { self.model = model }

    isolated deinit {
        model?.payloadReleases += 1
        model?.onPayloadRelease?()
    }
}

@MainActor
private struct SheetActivityOwner: View {
    let model: SheetActivityModel
    var versionOverride: Int? = nil

    var body: some View {
        model.ownerBodies += 1
        let version = versionOverride ?? model.version
        model.ownerVersions.append(version)
        let payload = model.capturesPayload ? SheetActivityPayload(model: model) : nil
        if model.capturesPayload { model.payload = payload }
        let base = Button("Background") {}
            .accessibilityIdentifier("\(model.name).background")
            .frame(width: 240, height: 40)
        let onDismiss: () -> Void = {
            withExtendedLifetime(payload) { model.callbacks.append(version) }
        }
        switch model.kind {
        case .boolean:
            return AnyView(
                base.sheet(
                    isPresented: Binding(
                        get: { model.readBoolean(version: version) },
                        set: { model.writeBoolean($0, version: version) }),
                    onDismiss: onDismiss
                ) {
                    SheetActivityContent(model: model, label: "Version \(version)", version: version)
                })
        case .item:
            return AnyView(
                base.sheet(
                    item: Binding(
                        get: { model.readItem(version: version) },
                        set: { model.writeItem($0, version: version) }),
                    onDismiss: onDismiss
                ) { item in
                    SheetActivityContent(model: model, label: item.title, version: version)
                })
        }
    }
}

@MainActor
private struct SheetActivityContent: View {
    @Environment(\.dismiss) private var dismiss
    let model: SheetActivityModel
    let label: String
    let version: Int

    var body: some View {
        model.actions.append(dismiss)
        model.actionVersions.append(version)
        model.contentBodies += 1
        switch model.content {
        case .stateless:
            return AnyView(Text(label).accessibilityIdentifier("\(model.name).sheet"))
        case .stateful:
            return AnyView(SheetActivityStatefulContent(model: model))
        case .editor:
            return AnyView(
                TextField(
                    "Sheet", text: Binding(get: { model.editorText }, set: { model.editorText = $0 }),
                    onEditingChanged: { model.onEditingChanged?($0) }
                )
                .accessibilityIdentifier("\(model.name).editor")
                .frame(width: 240, height: 40))
        }
    }
}

@MainActor
private final class SheetActivityObject: ObservableObject {
    @Published var value = 20
}

@MainActor
private struct SheetActivityStatefulContent: View {
    @State private var count = 10
    @StateObject private var object: SheetActivityObject
    let model: SheetActivityModel

    init(model: SheetActivityModel) {
        self.model = model
        _object = StateObject(wrappedValue: SheetActivityObject())
    }

    var body: some View {
        model.statefulBodies += 1
        model.counter = $count
        model.object = object
        return Text("\(count) / \(object.value)").accessibilityIdentifier("\(model.name).state")
    }
}

@MainActor
private final class SheetActivityTabsModel {
    var selection = 0
}

@MainActor
private struct SheetActivityTabbedRoot: View {
    let model: SheetActivityModel
    let tabs: SheetActivityTabsModel

    var body: some View {
        TabView(selection: Binding(get: { tabs.selection }, set: { tabs.selection = $0 })) {
            SheetActivityOwner(model: model).tag(0).tabItem { Text("Sheet") }
            Text("Other page").tag(1).tabItem { Text("Other") }
        }
    }
}

@MainActor
private final class SheetActivityGeometryProbe {
    var bodies = 0
}

@MainActor
private struct SheetActivityGeometryContent: View {
    let size: Size
    let model: SheetActivityModel
    let geometry: SheetActivityGeometryProbe

    var body: some View {
        geometry.bodies += 1
        return VStack(alignment: .leading, spacing: 0) {
            if size.width >= 350 {
                SheetActivityOwner(model: model, versionOverride: Int(size.width.rounded()))
            } else {
                Text("Sheet omitted at this width")
            }
        }
    }
}

@MainActor
private struct SheetActivityGeometryRoot: View {
    let inside: SheetActivityModel
    let outside: SheetActivityModel
    let geometry: SheetActivityGeometryProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                SheetActivityGeometryContent(size: proxy.size, model: inside, geometry: geometry)
            }
            SheetActivityOwner(model: outside).frame(height: 60)
        }
    }
}

@MainActor
private struct SheetActivityTabbedReaderRoot: View {
    let model: SheetActivityModel
    let tabs: SheetActivityTabsModel
    let geometry: SheetActivityGeometryProbe

    var body: some View {
        TabView(selection: Binding(get: { tabs.selection }, set: { tabs.selection = $0 })) {
            GeometryReader { proxy in
                SheetActivityGeometryContent(size: proxy.size, model: model, geometry: geometry)
            }
            .tag(0).tabItem { Text("Reader") }
            Text("Other page").tag(1).tabItem { Text("Other") }
        }
    }
}

@MainActor
private final class SheetActivityRootControl {
    var revision: Binding<Int>?
}

@MainActor
private struct SheetActivityHostedRoot<Content: View>: View {
    @State private var revision = 0
    let control: SheetActivityRootControl
    let content: Content

    var body: some View {
        control.revision = $revision
        let _ = revision
        return content
    }
}

@MainActor
private func sheetActivityNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private final class SheetActivityHost {
    private(set) var retainedHost: WinSwiftUIWindowHost?
    let window: Win32Window
    let clock: RuntimeTestClock
    private let control: SheetActivityRootControl

    var host: WinSwiftUIWindowHost { retainedHost! }
    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var nodes: [ViewNode] { sheetActivityNodes(in: runtime.root) }

    init<Content: View>(_ content: Content) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let control = SheetActivityRootControl()
        let size = IntSize(width: 400, height: 400)
        let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
        let window = Win32Window(title: "Sheet dismissal activity", clientSize: size)
        window.testScaleFactorOverride = 1
        window.testMonitorRefreshRateOverride = 60
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Sheet dismissal activity", size: size, clearColor: .black,
                content: [AnyView(SheetActivityHostedRoot(control: control, content: content))]),
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

    func finishTransitions() {
        clock.now += 1
        _ = runtime.tickAnimations(at: clock.now)
        _ = runtime.renderFrame(at: clock.now)
    }

    func resizeRuntime(to size: IntSize) {
        clock.now += 0.02
        runtime.setRootSize(size)
        _ = runtime.renderFrame(at: clock.now)
    }

    func contains(_ identifier: String) -> Bool { nodes.contains { $0.accessibilityIdentifier == identifier } }

    func node(_ identifier: String) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one \(identifier)")
        return try XCTUnwrap(matches.first)
    }

    func reader() throws -> ViewNode {
        let matches = nodes.filter { $0.geometryReaderBuild != nil }
        XCTAssertEqual(matches.count, 1)
        return try XCTUnwrap(matches.first)
    }

    @discardableResult
    func focus(_ identifier: String) throws -> ViewNode {
        let identified = try node(identifier)
        let focusable = try XCTUnwrap(sheetActivityNodes(in: identified).first { $0.isFocusable })
        runtime.requestFocus(focusable)
        XCTAssertTrue(runtime.focusedNode === focusable)
        return focusable
    }
}
