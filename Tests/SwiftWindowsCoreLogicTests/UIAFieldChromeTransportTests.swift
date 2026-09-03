import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class FieldChromeTransportState {
    var text = "abcd"
    var selection: TextSelection?
    var version = 0
    var reads: [Int] = []
    var writes: [String] = []
    var writeVersions: [Int] = []
    var selectionWrites = 0
    var layoutCalls = 0
    var invalidations = 0
    var completionReads: [Int] = []
    var recordsCompletionReads = false
    var afterWrite: (@MainActor () -> Void)?
    var incomingRow: ViewNode?
    var buttonCalls: [Int] = []
}

private enum FieldChromeTransportPath: CaseIterable {
    case direct
    case nested
}

@MainActor
private func fieldChromeTransportNodes(_ root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private func fieldChromeTransportIsVisible(_ node: ViewNode, within root: ViewNode) -> Bool {
    var cursor: ViewNode? = node
    while let current = cursor {
        if current.isHidden { return false }
        if current === root { return true }
        cursor = current.parent
    }
    return false
}

@MainActor
private final class FieldChromeTransportLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { FieldChromeTransportEpoch() }
}

@MainActor
private final class FieldChromeTransportEpoch: RetainedBuildEpoch {
    private var prepared = false
    var canAdopt: Bool { !prepared }
    func supersede() {}
    func willAdopt() -> Bool {
        guard !prepared else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

private enum FieldChromeTransportFixtureError: Error { case setup }

/// The provider identity is established before mounting. A checked build starts
/// only inside the original UIA binding setter and finishes before it returns.
/// No fake controller or test-only production seam creates the staged owner.
@MainActor
private final class FieldChromeTransportFixture {
    let state: FieldChromeTransportState
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    let container: ViewNode
    let retainedRow: ViewNode
    let retainedField: ViewNode
    let path: FieldChromeTransportPath
    let hasButton: Bool
    let checked: Bool
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>?
    let adapter: RetainedLazyListRuntimeAdapter?
    let rowIdentity: RetainedViewIdentity?
    let lease = FieldChromeTransportLease()
    lazy var source = RuntimeUIAElementTreeSource(runtime: runtime)
    var incomingField: ViewNode?
    var result: RetainedLazyListAdoptionResult?
    var admission: RetainedLazyListAdoptionAdmission?
    var candidate: RetainedLazyListRuntimeAdapter.Candidate?
    var admissionWasCurrentAfterAdoption: Bool?
    var constructionReads: [Int] = []
    var adoptionReads: [Int] = []
    var adoptionLayoutCalls = 0
    var passAtWrite: UInt64?
    var passAfterAdoption: UInt64?
    private var closed = false

    init(path: FieldChromeTransportPath, button: Bool = false, checked: Bool = false) throws {
        let state = FieldChromeTransportState()
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 360, height: 240), isHitTestVisible: false))
        runtime.clock = { 0 }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 360, height: 240) },
            invalidateHandler: { state.invalidations += 1 })
        // EnvironmentValues defaults to a nil undo manager. No undo-session
        // reconciliation read is included in the zero-read adoption oracle.
        XCTAssertNil(context.environmentValues.undoManager)
        let field = Self.makeField(state: state, context: context, runtime: runtime)
        let row =
            path == .direct && !button && !checked
            ? field : Self.makeRow(field: field, state: state, context: context, runtime: runtime, button: button)
        let provider: RetainedLazyListDataSource<Int, [ViewNode]>?
        let adapter: RetainedLazyListRuntimeAdapter?
        let rowIdentity: RetainedViewIdentity?
        if checked {
            let actualProvider = RetainedLazyListDataSource<Int, [ViewNode]>()
            guard
                actualProvider.replaceData(
                    [0], id: \.self, identityRoot: .init(segments: [.role(.content)]),
                    rowContent: { _, _ in
                        guard let incoming = state.incomingRow else {
                            XCTFail("The original binding setter must construct the incoming row before prepare")
                            return []
                        }
                        return [incoming]
                    })
            else { throw FieldChromeTransportFixtureError.setup }
            let metadata = try XCTUnwrap(actualProvider.metadata?.rows.first)
            let request = try XCTUnwrap(actualProvider.request(for: metadata.token))
            let prefix = try XCTUnwrap(actualProvider.identityPrefix(for: request))
            let identity = prefix.appending(contentsOf: [.role(.content), .slot(0)])
            row.retainedViewIdentity = identity
            provider = actualProvider
            adapter = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter(
                    provider: actualProvider, estimatedExtent: 180, prefetchExtent: 0,
                    maximumMountedRecords: 4, maximumMountedLeaves: 64, maximumProtectedRecords: 1))
            rowIdentity = identity
        } else {
            provider = nil
            adapter = nil
            rowIdentity = nil
        }
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 360, height: 240))
        container.addChild(row)
        runtime.root.addChild(container)
        self.state = state
        self.runtime = runtime
        self.context = context
        self.container = container
        self.retainedRow = row
        self.retainedField = field
        self.path = path
        self.hasButton = button
        self.checked = checked
        self.provider = provider
        self.adapter = adapter
        self.rowIdentity = rowIdentity
        runtime.requestFocus(field)
        _ = runtime.renderScene()
    }

    private static func makeField(
        state: FieldChromeTransportState, context: ViewBuildContext, runtime: RetainedViewRuntime
    ) -> ViewNode {
        let version = state.version
        let binding = Binding<String>(
            get: {
                state.reads.append(version)
                if state.recordsCompletionReads { state.completionReads.append(version) }
                return state.text
            },
            set: {
                state.writes.append($0)
                state.writeVersions.append(version)
                state.text = $0
                state.afterWrite?()
            })
        let selection = Binding<TextSelection?>(
            get: { state.selection },
            set: {
                state.selectionWrites += 1
                state.selection = $0
            })
        let field = TextField("Transport field", text: binding, selection: selection)
            .makeComponent(context: context).makeNode(runtime: runtime)
        field.nodeTag = "transport-field"
        field.accessibilityIdentifier = "uia-field-chrome-transport"
        field.frame = Rect(x: 10, y: 30, width: 300, height: 40)
        let originalLayout = field.onLayout
        field.onLayout = { bounds in
            state.layoutCalls += 1
            originalLayout?(bounds)
        }
        return field
    }

    private static func makeRow(
        field: ViewNode, state: FieldChromeTransportState, context: ViewBuildContext,
        runtime: RetainedViewRuntime, button: Bool
    ) -> ViewNode {
        let row = ViewNode(frame: Rect(x: 0, y: 0, width: 360, height: 180))
        row.nodeTag = "transport-row"
        let earlier = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10), text: "earlier \(state.version)")
        earlier.nodeTag = "transport-earlier"
        let later = ViewNode(frame: Rect(x: 0, y: 100, width: 10, height: 10), text: "later \(state.version)")
        later.nodeTag = "transport-later"
        let last = ViewNode(frame: Rect(x: 0, y: 120, width: 10, height: 10), text: "last \(state.version)")
        last.nodeTag = "transport-last"
        row.addChild(earlier)
        row.addChild(field)
        row.addChild(later)
        row.addChild(last)
        if button {
            let version = state.version
            let buttonNode = Button("Run") { state.buttonCalls.append(version) }
                .makeComponent(context: context).makeNode(runtime: runtime)
            buttonNode.nodeTag = "transport-button"
            row.addChild(buttonNode)
        }
        return row
    }

    func node(tag: String, in root: ViewNode) throws -> ViewNode {
        try XCTUnwrap(fieldChromeTransportNodes(root).first { $0.nodeTag == tag })
    }

    func snapshotID() throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "uia-field-chrome-transport" }).id
    }

    /// Called synchronously by the *original* TextField binding setter.
    func constructIncoming(selectionRange: Range<Int>?) throws -> ViewNode {
        passAtWrite = runtime.layoutPassID
        if let range = selectionRange {
            let lower = state.text.index(state.text.startIndex, offsetBy: range.lowerBound)
            let upper = state.text.index(state.text.startIndex, offsetBy: range.upperBound)
            state.selection = TextSelection(range: lower..<upper)
        }
        state.version += 1
        let readsBefore = state.reads.count
        let field = Self.makeField(state: state, context: context, runtime: runtime)
        let row =
            path == .direct && !hasButton && !checked
            ? field : Self.makeRow(field: field, state: state, context: context, runtime: runtime, button: hasButton)
        if let rowIdentity { row.retainedViewIdentity = rowIdentity }
        constructionReads = Array(state.reads.dropFirst(readsBefore))
        incomingField = field
        state.incomingRow = row
        XCTAssertNil(row.parent)
        XCTAssertNil(field.retainedLazyListRuntime)
        XCTAssertEqual(field.children.count, 1, "The native preparation starts with exactly the constructor label")
        XCTAssertFalse(try XCTUnwrap(field.children.first).isHidden)
        return row
    }

    func adoptIncoming(_ incoming: ViewNode) throws {
        let epoch: FieldChromeTransportEpoch?
        if checked {
            let adapter = try XCTUnwrap(adapter)
            container.retainedSubtreeBuildLease = lease
            container.retainedLazyListAdapter = adapter
            let measurement = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 360, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter.Viewport(context: measurement, offset: 0, extent: 240))
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
            let coordinator = runtime.retainedBuildCoordinator
            let sequence = try XCTUnwrap(coordinator.beginBuild())
            let actualEpoch = FieldChromeTransportEpoch()
            coordinator.install(actualEpoch, startedAt: sequence)
            epoch = actualEpoch
            let actualAdmission = RetainedLazyListAdoptionAdmission(
                adapter: adapter, container: container, runtime: runtime,
                coordinator: coordinator, sequence: sequence)
            admission = actualAdmission
            defer {
                if result == nil {
                    actualEpoch.abandon()
                    actualEpoch.finishAfterCallbacks()
                    coordinator.finishBuild()
                }
            }
            guard
                case .ready(let candidate) = adapter.prepare(
                    viewport: viewport, protectedRoots: [], budget: budget, admission: actualAdmission),
                actualAdmission.installCandidate(candidate), actualEpoch.willAdopt(), actualAdmission.isCurrent
            else { throw FieldChromeTransportFixtureError.setup }
            self.candidate = candidate
            let readsBefore = state.reads.count
            let layoutsBefore = state.layoutCalls
            result = ComponentHost.reconcileChildren(
                of: container, oldChildren: container.children,
                newNodes: candidate.children, admission: actualAdmission)
            adoptionReads = Array(state.reads.dropFirst(readsBefore))
            adoptionLayoutCalls = state.layoutCalls - layoutsBefore
        } else {
            epoch = nil
            let readsBefore = state.reads.count
            let layoutsBefore = state.layoutCalls
            if path == .direct {
                result = ComponentHost.adopt(source: incoming, into: retainedRow)
            } else {
                result = ComponentHost.reconcileChildren(
                    of: container, oldChildren: container.children, newNodes: [incoming])
            }
            adoptionReads = Array(state.reads.dropFirst(readsBefore))
            adoptionLayoutCalls = state.layoutCalls - layoutsBefore
        }
        passAfterAdoption = runtime.layoutPassID
        admissionWasCurrentAfterAdoption = admission?.isCurrent
        if let epoch {
            if admission?.didMutate == true { epoch.commit() } else { epoch.abandon() }
            epoch.finishAfterCallbacks()
            runtime.retainedBuildCoordinator.finishBuild()
        }
        state.recordsCompletionReads = true
    }

    func close() {
        guard !closed else { return }
        closed = true
        state.afterWrite = nil
        state.recordsCompletionReads = false
        for root in [retainedRow, state.incomingRow].compactMap({ $0 }) {
            for node in fieldChromeTransportNodes(root) { node.onUpdatePlatformView = nil }
        }
        provider?.close()
        runtime.root.removeChild(container)
        state.incomingRow = nil
        candidate = nil
    }
}

@MainActor
private final class FieldChromeForgedController: RetainedTextInputController {
    var onReconcile: (() -> Void)?
    private(set) var reconciles = 0
    func attach(to node: ViewNode) {}
    func detach(from node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        reconciles += 1
        onReconcile?()
    }
}

/// Additive, headless source tests. These assertions are requirements, not
/// pre-fix observations. In particular checked native growth is not skipped.
@MainActor
final class UIAFieldChromeTransportTests: XCTestCase {
    private func withFixture(
        path: FieldChromeTransportPath = .direct, button: Bool = false, checked: Bool = false,
        _ body: (FieldChromeTransportFixture) throws -> Void
    ) throws {
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
        defer { NativeTextRenderer.resetTestingOverrides() }
        let fixture = try FieldChromeTransportFixture(path: path, button: button, checked: checked)
        defer { fixture.close() }
        try body(fixture)
    }

    private func assertNoAdoptionEffects(
        _ fixture: FieldChromeTransportFixture, value: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(fixture.state.writes, [value], file: file, line: line)
        XCTAssertEqual(fixture.state.writeVersions, [0], file: file, line: line)
        XCTAssertEqual(fixture.state.selectionWrites, 0, file: file, line: line)
        XCTAssertEqual(fixture.constructionReads, [1], file: file, line: line)
        XCTAssertEqual(fixture.adoptionReads, [], file: file, line: line)
        XCTAssertEqual(fixture.adoptionLayoutCalls, 0, file: file, line: line)
        XCTAssertEqual(fixture.passAtWrite, fixture.passAfterAdoption, file: file, line: line)
        XCTAssertEqual(fixture.runtime.layoutPassID, try XCTUnwrap(fixture.passAtWrite), file: file, line: line)
        XCTAssertEqual(Array(fixture.state.text.utf8), Array(value.utf8), file: file, line: line)
    }

    private func assertChrome(
        _ fixture: FieldChromeTransportFixture, value: String, selectionRange: Range<Int>?,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let field = fixture.retainedField
        let nodes = fieldChromeTransportNodes(field)
        let visibleNodes = nodes.filter { fieldChromeTransportIsVisible($0, within: field) }
        XCTAssertTrue(field.isFocused, file: file, line: line)
        XCTAssertTrue(fixture.runtime.focusedNode === field, file: file, line: line)
        XCTAssertTrue(
            try fixture.node(tag: "transport-field", in: fixture.runtime.root) === field, file: file, line: line)
        XCTAssertTrue(try XCTUnwrap(field.children.first).isHidden, file: file, line: line)
        for parent in nodes {
            XCTAssertEqual(
                Set(parent.children.map(ObjectIdentifier.init)).count, parent.children.count, file: file, line: line)
            for child in parent.children { XCTAssertTrue(child.parent === parent, file: file, line: line) }
        }
        let visibleText = visibleNodes.compactMap(\.text).joined()
        XCTAssertEqual(Array(visibleText.utf8), Array(value.utf8), file: file, line: line)
        if let range = selectionRange {
            let lower = value.index(value.startIndex, offsetBy: range.lowerBound)
            let upper = value.index(value.startIndex, offsetBy: range.upperBound)
            let selected = String(value[lower..<upper])
            XCTAssertEqual(field.textInputSelection?.indices, .range(range), file: file, line: line)
            XCTAssertEqual(field.textInputCaretOffset, range.upperBound, file: file, line: line)
            XCTAssertEqual(nodes.filter(\.isTextInputCaret).count, 0, file: file, line: line)
            XCTAssertEqual(
                nodes.filter { $0.text == selected && $0.backgroundColor != nil }.count, 1, file: file, line: line)
            XCTAssertEqual(
                visibleNodes.filter { $0.text == selected && $0.backgroundColor != nil }.count, 1, file: file,
                line: line)
        } else {
            XCTAssertNil(field.textInputSelection, file: file, line: line)
            XCTAssertEqual(field.textInputCaretOffset, value.count, file: file, line: line)
            XCTAssertEqual(nodes.filter(\.isTextInputCaret).count, 1, file: file, line: line)
            XCTAssertEqual(visibleNodes.filter(\.isTextInputCaret).count, 1, file: file, line: line)
        }
    }

    private func performPositiveEdit(
        _ fixture: FieldChromeTransportFixture, value: String, selectionRange: Range<Int>? = nil,
        configure: ((ViewNode) throws -> Void)? = nil
    ) throws {
        let original = try XCTUnwrap(fixture.retainedField.textInputController)
        let id = try fixture.snapshotID()
        fixture.state.afterWrite = { [weak fixture] in
            guard let fixture else { return }
            do {
                let incoming = try fixture.constructIncoming(selectionRange: selectionRange)
                try configure?(incoming)
                try fixture.adoptIncoming(incoming)
            } catch { XCTFail("Unable to prepare the real staged adoption: \(error)") }
        }
        let pass = fixture.runtime.layoutPassID
        XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: value))
        fixture.state.recordsCompletionReads = false
        fixture.state.afterWrite = nil
        XCTAssertEqual(fixture.runtime.layoutPassID, pass + 1)
        let result = try XCTUnwrap(fixture.result)
        XCTAssertTrue(result.completed)
        if fixture.checked || fixture.hasButton {
            XCTAssertTrue(result.completion?.isCurrent == true)
        } else {
            XCTAssertNil(result.completion)
        }
        XCTAssertFalse(fixture.retainedField.textInputController === original)
        XCTAssertEqual(fixture.state.completionReads, [0])
        try assertNoAdoptionEffects(fixture, value: value)
        try assertChrome(fixture, value: value, selectionRange: selectionRange)
    }

    func testDirectAdoptionTransportsPreparedFieldChromeWithoutLayout() async throws {
        let value = "A👩‍👩‍👧‍👧e\u{301}Z"
        let ranges: [Range<Int>?] = [nil, 1..<3]
        for range in ranges {
            try withFixture { fixture in
                try performPositiveEdit(fixture, value: value, selectionRange: range)
            }
        }
    }

    func testNestedReconciliationTransportsPreparedFieldChromeWithoutLayout() async throws {
        let value = "A👩‍👩‍👧‍👧e\u{301}Z"
        let ranges: [Range<Int>?] = [nil, 1..<3]
        for range in ranges {
            try withFixture(path: .nested) { fixture in
                let row = fixture.retainedRow
                try performPositiveEdit(fixture, value: value, selectionRange: range)
                XCTAssertTrue(fixture.container.children.first === row)
                XCTAssertTrue(fixture.retainedField.parent === row)
                XCTAssertEqual(try fixture.node(tag: "transport-last", in: row).text, "last 1")
            }
        }
    }

    func testPreparedFieldChromeBesideButtonPreservesActionAdmission() async throws {
        for path in FieldChromeTransportPath.allCases {
            try withFixture(path: path, button: true) { fixture in
                let retainedButton = try fixture.node(tag: "transport-button", in: fixture.retainedRow)
                var buttonUpdates = 0
                try performPositiveEdit(fixture, value: "updated") { incoming in
                    let incomingButton = try fixture.node(tag: "transport-button", in: incoming)
                    incomingButton.onUpdatePlatformView = { node in
                        buttonUpdates += 1
                        node.onActivate?()
                        retainedButton.onActivate?()
                    }
                }
                XCTAssertEqual(buttonUpdates, 1)
                XCTAssertEqual(fixture.state.buttonCalls, [])
                XCTAssertTrue(try fixture.node(tag: "transport-button", in: fixture.retainedRow) === retainedButton)
                retainedButton.onActivate?()
                XCTAssertEqual(fixture.state.buttonCalls, [1])
            }
        }
    }

    func testCustomControllerAppendCannotMasqueradeAsPreparedFieldChrome() async throws {
        for path in FieldChromeTransportPath.allCases {
            let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 80)))
            let retained = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 40))
            let incoming = ViewNode(frame: retained.frame)
            retained.nodeTag = "forged-field"
            incoming.nodeTag = "forged-field"
            let oldLabel = ViewNode(frame: .zero, text: "old")
            let newLabel = ViewNode(frame: .zero, text: "new")
            retained.addChild(oldLabel)
            incoming.addChild(newLabel)
            let previous = FieldChromeForgedController()
            let controller = FieldChromeForgedController()
            retained.textInputController = previous
            incoming.textInputController = controller
            let forged = ViewNode(frame: .zero, text: "not native chrome")
            forged.isTextInputCaret = true
            var layouts = 0
            retained.onLayout = { _ in layouts += 1 }
            incoming.onLayout = { _ in layouts += 1 }
            controller.onReconcile = { incoming.addChild(forged) }
            runtime.root.addChild(retained)
            defer {
                controller.onReconcile = nil
                runtime.root.removeChild(retained)
            }
            let pass = runtime.layoutPassID
            let result: RetainedLazyListAdoptionResult
            if path == .direct {
                result = ComponentHost.adopt(source: incoming, into: retained)
            } else {
                result = ComponentHost.reconcileChildren(
                    of: runtime.root, oldChildren: runtime.root.children, newNodes: [incoming])
            }
            XCTAssertTrue(result.completed)
            XCTAssertEqual(controller.reconciles, 1)
            XCTAssertEqual(layouts, 0)
            XCTAssertEqual(runtime.layoutPassID, pass)
            XCTAssertTrue(retained.children.first === oldLabel)
            XCTAssertEqual(oldLabel.text, "new")
            XCTAssertFalse(fieldChromeTransportNodes(retained).contains { $0 === forged })
            XCTAssertTrue(forged.parent === incoming)
            XCTAssertTrue(incoming.children.contains { $0 === forged })
        }
    }

    func testCheckedReconciliationTransportsPreparedFieldChromeWithCurrentCompletion() async throws {
        let ranges: [Range<Int>?] = [nil, 1..<3]
        for range in ranges {
            try withFixture(path: .nested, checked: true) { fixture in
                try performPositiveEdit(fixture, value: "A👩‍👩‍👧‍👧e\u{301}Z", selectionRange: range)
                XCTAssertEqual(fixture.admissionWasCurrentAfterAdoption, true)
            }
        }
    }

    func testEarlierCallbackCannotChangeTheCapturedFieldChildrenAndContinue() async throws {
        for mutatesLabel in [false, true] {
            try withFixture(path: .nested, checked: true) { fixture in
                let id = try fixture.snapshotID()
                let original = try XCTUnwrap(fixture.retainedField.textInputController)
                let forged = ViewNode(frame: .zero, text: "authored callback child")
                var callbackCalls = 0
                var laterCalls = 0
                var mutatedParent: ViewNode?
                fixture.state.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    do {
                        let incoming = try fixture.constructIncoming(selectionRange: nil)
                        let field = try XCTUnwrap(fixture.incomingField)
                        let parent: ViewNode
                        if mutatesLabel { parent = try XCTUnwrap(field.children.first) } else { parent = field }
                        mutatedParent = parent
                        let earlier = try fixture.node(tag: "transport-earlier", in: incoming)
                        let last = try fixture.node(tag: "transport-last", in: incoming)
                        earlier.onUpdatePlatformView = { _ in
                            callbackCalls += 1
                            parent.addChild(forged)
                        }
                        last.onUpdatePlatformView = { _ in laterCalls += 1 }
                        try fixture.adoptIncoming(incoming)
                    } catch { XCTFail("Unable to prepare the checked callback case: \(error)") }
                }
                _ = fixture.source.uiaSetValue(elementID: id, value: "one effect")
                fixture.state.recordsCompletionReads = false
                fixture.state.afterWrite = nil
                let result = try XCTUnwrap(fixture.result)
                XCTAssertEqual(callbackCalls, 1)
                XCTAssertEqual(laterCalls, 0)
                XCTAssertFalse(result.completed)
                XCTAssertNil(result.completion)
                XCTAssertTrue(fixture.retainedField.textInputController === original)
                XCTAssertTrue(forged.parent === mutatedParent)
                XCTAssertTrue(try XCTUnwrap(mutatedParent).children.contains { $0 === forged })
                XCTAssertFalse(fieldChromeTransportNodes(fixture.retainedRow).contains { $0 === forged })
                XCTAssertEqual(try fixture.node(tag: "transport-last", in: fixture.retainedRow).text, "last 0")
                try assertNoAdoptionEffects(fixture, value: "one effect")
            }
        }
    }

    func testLaterCallbackCannotReattachAcceptedChromeAndContinue() async throws {
        for removesContentRow in [false, true] {
            try withFixture(path: .nested, checked: true) { fixture in
                let id = try fixture.snapshotID()
                var callbackCalls = 0
                var lastCalls = 0
                var acceptedCaret: ViewNode?
                var caretParent: ViewNode?
                var caretProof: RetainedLazyListAttachmentProof?
                var acceptedContentRow: ViewNode?
                var acceptedBase: ViewNode?
                var acceptedController: (any RetainedTextInputController)?
                var expectedOrder: [ObjectIdentifier] = []
                fixture.state.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    do {
                        let incoming = try fixture.constructIncoming(selectionRange: nil)
                        let later = try fixture.node(tag: "transport-later", in: incoming)
                        let last = try fixture.node(tag: "transport-last", in: incoming)
                        later.onUpdatePlatformView = { [weak fixture] _ in
                            guard let fixture else { return }
                            callbackCalls += 1
                            guard
                                let caret = fieldChromeTransportNodes(fixture.retainedField).first(
                                    where: \.isTextInputCaret),
                                let parent = caret.parent
                            else {
                                XCTFail("The earlier accepted field must already own its prepared native caret")
                                return
                            }
                            acceptedCaret = caret
                            caretParent = parent
                            caretProof = caret.captureLazyListAttachmentProof()
                            acceptedBase = fixture.retainedField.children.first
                            acceptedController = fixture.retainedField.textInputController
                            var contentRow = parent
                            while let ancestor = contentRow.parent, ancestor !== fixture.retainedField {
                                contentRow = ancestor
                            }
                            guard contentRow.parent === fixture.retainedField else {
                                XCTFail("Expected native chrome inside this same retained field")
                                return
                            }
                            acceptedContentRow = contentRow
                            let originalChildren = parent.children
                            expectedOrder = originalChildren.map(ObjectIdentifier.init)
                            if removesContentRow {
                                fixture.retainedField.removeChild(contentRow)
                            } else {
                                parent.removeChild(caret)
                                parent.setChildren(originalChildren)
                            }
                        }
                        last.onUpdatePlatformView = { _ in lastCalls += 1 }
                        try fixture.adoptIncoming(incoming)
                    } catch { XCTFail("Unable to prepare the checked ABA case: \(error)") }
                }
                _ = fixture.source.uiaSetValue(elementID: id, value: "one effect")
                fixture.state.recordsCompletionReads = false
                fixture.state.afterWrite = nil
                let result = try XCTUnwrap(fixture.result)
                XCTAssertEqual(callbackCalls, 1)
                XCTAssertEqual(lastCalls, 0)
                XCTAssertFalse(result.completed)
                XCTAssertNil(result.completion)
                XCTAssertEqual(fixture.admissionWasCurrentAfterAdoption, false)
                let caret = try XCTUnwrap(acceptedCaret)
                let parent = try XCTUnwrap(caretParent)
                let base = try XCTUnwrap(acceptedBase)
                let contentRow = try XCTUnwrap(acceptedContentRow)
                XCTAssertFalse(try XCTUnwrap(caretProof).isCurrent)
                XCTAssertTrue(caret.parent === parent)
                XCTAssertEqual(parent.children.map(ObjectIdentifier.init), expectedOrder)
                XCTAssertTrue(fixture.retainedField.children.first === base)
                XCTAssertTrue(fixture.retainedField.textInputController === acceptedController)
                if removesContentRow {
                    XCTAssertNil(contentRow.parent)
                    XCTAssertFalse(fieldChromeTransportNodes(fixture.retainedField).contains { $0 === caret })
                    XCTAssertFalse(base.isHidden, "A current field cannot lose both its visible base and its chrome")
                } else {
                    XCTAssertTrue(contentRow.parent === fixture.retainedField)
                    XCTAssertTrue(fieldChromeTransportNodes(fixture.retainedField).contains { $0 === caret })
                }
                // Pending native rows may be hidden until enclosing acknowledgement.
                // Count visibility through every ancestor, not just the leaf flag.
                let visibleChrome = fieldChromeTransportNodes(fixture.retainedField).contains { node in
                    guard node !== fixture.retainedField, node !== base,
                        node.isTextInputCaret || node.text != nil
                    else { return false }
                    return fieldChromeTransportIsVisible(node, within: fixture.retainedField)
                }
                if !visibleChrome {
                    XCTAssertFalse(base.isHidden, "Rejected preparation cannot conceal the only visible field text")
                }
                XCTAssertEqual(try fixture.node(tag: "transport-last", in: fixture.retainedRow).text, "last 0")
                try assertNoAdoptionEffects(fixture, value: "one effect")
            }
        }
    }
}
