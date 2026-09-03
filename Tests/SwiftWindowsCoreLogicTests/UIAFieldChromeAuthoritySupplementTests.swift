import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class FieldChromeAuthorityState {
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

private enum FieldChromeAuthorityPath: CaseIterable {
    case direct
    case nested
}

@MainActor
private func fieldChromeAuthorityNodes(_ root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private func fieldChromeAuthorityIsVisible(_ node: ViewNode, within root: ViewNode) -> Bool {
    var cursor: ViewNode? = node
    while let current = cursor {
        if current.isHidden { return false }
        if current === root { return true }
        cursor = current.parent
    }
    return false
}

@MainActor
private final class FieldChromeAuthorityLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { FieldChromeAuthorityEpoch() }
}

@MainActor
private final class FieldChromeAuthorityEpoch: RetainedBuildEpoch {
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

private enum FieldChromeAuthorityFixtureError: Error { case setup }

/// The provider identity is established before mounting. A checked build starts
/// only inside the original UIA binding setter and finishes before it returns.
/// No fake controller or test-only production seam creates the staged owner.
@MainActor
private final class FieldChromeAuthorityFixture {
    let state: FieldChromeAuthorityState
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    let container: ViewNode
    let retainedRow: ViewNode
    let retainedField: ViewNode
    let path: FieldChromeAuthorityPath
    let hasButton: Bool
    let checked: Bool
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>?
    let adapter: RetainedLazyListRuntimeAdapter?
    let rowIdentity: RetainedViewIdentity?
    let lease = FieldChromeAuthorityLease()
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

    init(path: FieldChromeAuthorityPath, button: Bool = false, checked: Bool = false) throws {
        let state = FieldChromeAuthorityState()
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
            else { throw FieldChromeAuthorityFixtureError.setup }
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
        state: FieldChromeAuthorityState, context: ViewBuildContext, runtime: RetainedViewRuntime
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
        field: ViewNode, state: FieldChromeAuthorityState, context: ViewBuildContext,
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
        try XCTUnwrap(fieldChromeAuthorityNodes(root).first { $0.nodeTag == tag })
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
        let epoch: FieldChromeAuthorityEpoch?
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
            let actualEpoch = FieldChromeAuthorityEpoch()
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
            else { throw FieldChromeAuthorityFixtureError.setup }
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
            for node in fieldChromeAuthorityNodes(root) { node.onUpdatePlatformView = nil }
        }
        provider?.close()
        runtime.root.removeChild(container)
        state.incomingRow = nil
        candidate = nil
    }
}

/// Separate additive authority tests. The historical seven-test packet is
/// immutable; copied private helpers here avoid changing its fixtures or bodies.
@MainActor
final class UIAFieldChromeAuthoritySupplementTests: XCTestCase {
    private func withFixture(
        path: FieldChromeAuthorityPath = .direct, button: Bool = false, checked: Bool = false,
        _ body: (FieldChromeAuthorityFixture) throws -> Void
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
        let fixture = try FieldChromeAuthorityFixture(path: path, button: button, checked: checked)
        defer { fixture.close() }
        try body(fixture)
    }

    private func assertNoAdoptionEffects(
        _ fixture: FieldChromeAuthorityFixture, value: String, file: StaticString = #filePath, line: UInt = #line
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
        _ fixture: FieldChromeAuthorityFixture, value: String, selectionRange: Range<Int>?,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let field = fixture.retainedField
        let nodes = fieldChromeAuthorityNodes(field)
        let visibleNodes = nodes.filter { fieldChromeAuthorityIsVisible($0, within: field) }
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
        _ fixture: FieldChromeAuthorityFixture, value: String, selectionRange: Range<Int>? = nil,
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

    private enum OrdinaryEntry: CaseIterable {
        case adoptRow
        case reconcileContainer
    }

    private enum GeometryMutation: CaseIterable {
        case sameFieldFrame
        case fieldFrameABA
        case baseFrameABA
    }

    private func adoptOrdinary(
        _ fixture: FieldChromeAuthorityFixture, incoming: ViewNode, entry: OrdinaryEntry
    ) {
        let reads = fixture.state.reads.count
        let layouts = fixture.state.layoutCalls
        switch entry {
        case .adoptRow:
            fixture.result = ComponentHost.adopt(source: incoming, into: fixture.retainedRow)
        case .reconcileContainer:
            fixture.result = ComponentHost.reconcileChildren(
                of: fixture.container, oldChildren: fixture.container.children, newNodes: [incoming])
        }
        fixture.adoptionReads = Array(fixture.state.reads.dropFirst(reads))
        fixture.adoptionLayoutCalls = fixture.state.layoutCalls - layouts
        fixture.passAfterAdoption = fixture.runtime.layoutPassID
        fixture.state.recordsCompletionReads = true
    }

    /// Receipt-only expiry must not publish native chrome, even where ordinary
    /// base-label adoption can complete. This does not invent a failure result.
    private func assertInactiveChrome(
        _ fixture: FieldChromeAuthorityFixture, base: ViewNode, value: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let field = fixture.retainedField
        XCTAssertTrue(
            try fixture.node(tag: "transport-field", in: fixture.runtime.root) === field, file: file, line: line)
        XCTAssertTrue(field.children.first === base, file: file, line: line)
        XCTAssertTrue(base.parent === field, file: file, line: line)
        XCTAssertFalse(base.isHidden, file: file, line: line)
        XCTAssertEqual(Array(try XCTUnwrap(base.text).utf8), Array(value.utf8), file: file, line: line)
        let visibleNative = fieldChromeAuthorityNodes(field).filter {
            $0 !== field && $0 !== base && fieldChromeAuthorityIsVisible($0, within: field)
                && ($0.isTextInputCaret || $0.text != nil)
        }
        XCTAssertTrue(
            visibleNative.isEmpty, "An expired preparation must not activate native rows", file: file, line: line)
    }

    /// Run the saved real layout handler only AFTER all refusal assertions.
    /// This separate phase observes cache recovery without another value write,
    /// render, query, or layout pass. It is not used to satisfy refusal checks.
    private func assertSameValueCanRecoverThroughNormalChromeRefresh(
        _ fixture: FieldChromeAuthorityFixture, value: String,
        restoring handler: ((Rect) -> Void)? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        if let handler { fixture.retainedField.onLayout = handler }
        let layout = try XCTUnwrap(fixture.retainedField.onLayout)
        let reads = fixture.state.reads.count
        let callbacks = fixture.state.layoutCalls
        let pass = fixture.runtime.layoutPassID
        let writes = fixture.state.writes
        let selectionWrites = fixture.state.selectionWrites
        layout(fixture.retainedField.frame)
        XCTAssertEqual(Array(fixture.state.reads.dropFirst(reads)), [1], file: file, line: line)
        XCTAssertEqual(fixture.state.layoutCalls, callbacks + 1, file: file, line: line)
        XCTAssertEqual(fixture.runtime.layoutPassID, pass, file: file, line: line)
        XCTAssertEqual(fixture.state.writes, writes, file: file, line: line)
        XCTAssertEqual(fixture.state.selectionWrites, selectionWrites, file: file, line: line)
        try assertChrome(fixture, value: value, selectionRange: nil, file: file, line: line)
    }

    func testOrdinaryEarlierSiblingCannotRearmChromeAfterSourceOrLabelAttachmentABA() async throws {
        for entry in OrdinaryEntry.allCases {
            for movesLabel in [false, true] {
                try withFixture(path: .nested) { fixture in
                    let value = "A👩‍👩‍👧‍👧e\u{301}Z"
                    let base = try XCTUnwrap(fixture.retainedField.children.first)
                    let id = try fixture.snapshotID()
                    var callbacks = 0
                    var staleProof: RetainedLazyListAttachmentProof?
                    fixture.state.afterWrite = { [weak fixture] in
                        guard let fixture else { return }
                        do {
                            let incoming = try fixture.constructIncoming(selectionRange: nil)
                            let field = try XCTUnwrap(fixture.incomingField)
                            let label = try XCTUnwrap(field.children.first)
                            let controller = try XCTUnwrap(field.textInputController)
                            let parent = movesLabel ? field : incoming
                            let moved = movesLabel ? label : field
                            let order = parent.children
                            let identities = order.map(ObjectIdentifier.init)
                            let attachment = moved.captureLazyListAttachmentProof()
                            staleProof = attachment
                            let earlier = try fixture.node(tag: "transport-earlier", in: incoming)
                            earlier.onUpdatePlatformView = { _ in
                                callbacks += 1
                                XCTAssertTrue(attachment.isCurrent)
                                parent.removeChild(moved)
                                parent.setChildren(order)
                                XCTAssertFalse(attachment.isCurrent)
                                XCTAssertTrue(moved.parent === parent)
                                XCTAssertEqual(parent.children.map(ObjectIdentifier.init), identities)
                                XCTAssertTrue(field.textInputController === controller)
                                XCTAssertEqual(field.children.count, 1)
                                XCTAssertTrue(field.children.first === label)
                                XCTAssertTrue(label.children.isEmpty)
                                XCTAssertFalse(label.isHidden)
                            }
                            self.adoptOrdinary(fixture, incoming: incoming, entry: entry)
                        } catch { XCTFail("Unable to prepare the ordinary attachment ABA: \(error)") }
                    }
                    let pass = fixture.runtime.layoutPassID
                    _ = fixture.source.uiaSetValue(elementID: id, value: value)
                    fixture.state.recordsCompletionReads = false
                    fixture.state.afterWrite = nil
                    XCTAssertNotNil(fixture.result)
                    XCTAssertEqual(callbacks, 1)
                    XCTAssertFalse(try XCTUnwrap(staleProof).isCurrent)
                    XCTAssertEqual(fixture.runtime.layoutPassID, pass + 1)
                    try assertNoAdoptionEffects(fixture, value: value)
                    try assertInactiveChrome(fixture, base: base, value: value)
                    try assertSameValueCanRecoverThroughNormalChromeRefresh(fixture, value: value)
                }
            }
        }
    }

    func testLocalFrameABACannotActivatePreparedChrome() async throws {
        for mutation in GeometryMutation.allCases {
            try withFixture(path: .nested) { fixture in
                let value = "A👩‍👩‍👧‍👧e\u{301}Z"
                let base = try XCTUnwrap(fixture.retainedField.children.first)
                let id = try fixture.snapshotID()
                var callbacks = 0
                var preparedRoot: ViewNode?
                var preservedCompletion: RetainedLazyListAdoptionCompletion?
                fixture.state.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    do {
                        let incoming = try fixture.constructIncoming(selectionRange: nil)
                        let last = try fixture.node(tag: "transport-last", in: incoming)
                        last.onUpdatePlatformView = { [weak fixture] _ in
                            guard let fixture else { return }
                            callbacks += 1
                            let field = fixture.retainedField
                            guard let root = field.children.first(where: { $0 !== base }),
                                let controller = field.textInputController,
                                let completion = RetainedLazyListAdoptionCompletion(of: field)
                            else {
                                XCTFail("The field must already own its provisional native row")
                                return
                            }
                            preparedRoot = root
                            preservedCompletion = completion
                            XCTAssertTrue(root.isHidden)
                            XCTAssertFalse(base.isHidden)
                            let fieldAttachment = field.captureLazyListAttachmentProof()
                            let baseAttachment = base.captureLazyListAttachmentProof()
                            let rootAttachment = root.captureLazyListAttachmentProof()
                            let order = field.children.map(ObjectIdentifier.init)
                            let target = mutation == .baseFrameABA ? base : field
                            let frame = target.frame
                            let reads = fixture.state.reads.count
                            let layouts = fixture.state.layoutCalls
                            let pass = fixture.runtime.layoutPassID
                            if mutation != .sameFieldFrame {
                                target.frame = Rect(
                                    x: frame.origin.x, y: frame.origin.y,
                                    width: frame.size.width + 1, height: frame.size.height)
                            }
                            target.frame = frame
                            XCTAssertEqual(target.frame, frame)
                            XCTAssertTrue(fieldAttachment.isCurrent)
                            XCTAssertTrue(baseAttachment.isCurrent)
                            XCTAssertTrue(rootAttachment.isCurrent)
                            XCTAssertTrue(completion.isCurrent)
                            XCTAssertTrue(field.textInputController === controller)
                            XCTAssertEqual(field.children.map(ObjectIdentifier.init), order)
                            XCTAssertEqual(fixture.state.reads.count, reads)
                            XCTAssertEqual(fixture.state.layoutCalls, layouts)
                            XCTAssertEqual(fixture.runtime.layoutPassID, pass)
                        }
                        self.adoptOrdinary(fixture, incoming: incoming, entry: .reconcileContainer)
                    } catch { XCTFail("Unable to prepare the ordinary local geometry case: \(error)") }
                }
                let pass = fixture.runtime.layoutPassID
                let accepted = fixture.source.uiaSetValue(elementID: id, value: value)
                fixture.state.recordsCompletionReads = false
                fixture.state.afterWrite = nil
                XCTAssertEqual(callbacks, 1)
                XCTAssertEqual(fixture.runtime.layoutPassID, pass + 1)
                let result = try XCTUnwrap(fixture.result)
                let root = try XCTUnwrap(preparedRoot)
                try assertNoAdoptionEffects(fixture, value: value)
                if mutation == .sameFieldFrame {
                    XCTAssertTrue(accepted)
                    XCTAssertTrue(result.completed)
                    XCTAssertNil(result.completion)
                    XCTAssertTrue(try XCTUnwrap(preservedCompletion).isCurrent)
                    XCTAssertTrue(fieldChromeAuthorityIsVisible(root, within: fixture.retainedField))
                    XCTAssertEqual(fixture.state.completionReads, [0])
                    try assertChrome(fixture, value: value, selectionRange: nil)
                } else {
                    XCTAssertFalse(fieldChromeAuthorityIsVisible(root, within: fixture.retainedField))
                    try assertInactiveChrome(fixture, base: base, value: value)
                    try assertSameValueCanRecoverThroughNormalChromeRefresh(fixture, value: value)
                }
            }
        }
    }

    func testLayoutOnlyQueryCannotActivatePreparedChromeUsingPendingDirtyFlags() async throws {
        try withFixture(path: .nested) { fixture in
            let value = "A👩‍👩‍👧‍👧e\u{301}Z"
            let base = try XCTUnwrap(fixture.retainedField.children.first)
            let id = try fixture.snapshotID()
            var callbacks = 0
            var queries = 0
            var queryLayouts = 0
            var passBeforeQuery: UInt64?
            var passAfterQuery: UInt64?
            var preparedRoot: ViewNode?
            var savedNativeLayout: ((Rect) -> Void)?
            fixture.state.afterWrite = { [weak fixture] in
                guard let fixture else { return }
                do {
                    let incoming = try fixture.constructIncoming(selectionRange: nil)
                    let field = try XCTUnwrap(fixture.incomingField)
                    savedNativeLayout = try XCTUnwrap(field.onLayout)
                    // Isolate resolution expiry from the real field's normal
                    // getter-bearing refresh. The controller/factory stay real.
                    // This override exists before the outer adoption captures it.
                    field.onLayout = { [weak state = fixture.state] _ in
                        queryLayouts += 1
                        state?.layoutCalls += 1
                    }
                    let last = try fixture.node(tag: "transport-last", in: incoming)
                    last.onUpdatePlatformView = { [weak fixture] _ in
                        guard let fixture else { return }
                        callbacks += 1
                        let field = fixture.retainedField
                        guard let root = field.children.first(where: { $0 !== base }),
                            let controller = field.textInputController,
                            let completion = RetainedLazyListAdoptionCompletion(of: field)
                        else {
                            XCTFail("The field must already own its provisional native row")
                            return
                        }
                        preparedRoot = root
                        XCTAssertTrue(root.isHidden)
                        XCTAssertFalse(base.isHidden)
                        let attachment = field.captureLazyListAttachmentProof()
                        let baseAttachment = base.captureLazyListAttachmentProof()
                        let rootAttachment = root.captureLazyListAttachmentProof()
                        let order = field.children.map(ObjectIdentifier.init)
                        let frame = field.frame
                        let dirty = fixture.runtime.dirtyFlags
                        let fieldDirty = field.subtreeDirtyFlags
                        let reads = fixture.state.reads.count
                        let layouts = queryLayouts
                        let pass = fixture.runtime.layoutPassID
                        passBeforeQuery = pass
                        XCTAssertTrue(fixture.runtime.hasPendingLayout)
                        queries += 1
                        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.runtime.root))
                        passAfterQuery = fixture.runtime.layoutPassID
                        XCTAssertEqual(fixture.runtime.layoutPassID, pass + 1)
                        XCTAssertEqual(queryLayouts, layouts + 1)
                        XCTAssertEqual(fixture.state.reads.count, reads)
                        XCTAssertEqual(fixture.runtime.dirtyFlags, dirty)
                        XCTAssertEqual(field.subtreeDirtyFlags, fieldDirty)
                        XCTAssertTrue(fixture.runtime.hasPendingLayout)
                        XCTAssertEqual(field.frame, frame)
                        XCTAssertTrue(attachment.isCurrent)
                        XCTAssertTrue(baseAttachment.isCurrent)
                        XCTAssertTrue(rootAttachment.isCurrent)
                        XCTAssertTrue(completion.isCurrent)
                        XCTAssertTrue(field.textInputController === controller)
                        XCTAssertEqual(field.children.map(ObjectIdentifier.init), order)
                    }
                    self.adoptOrdinary(fixture, incoming: incoming, entry: .reconcileContainer)
                } catch { XCTFail("Unable to prepare the ordinary layout-only query case: \(error)") }
            }
            let pass = fixture.runtime.layoutPassID
            _ = fixture.source.uiaSetValue(elementID: id, value: value)
            fixture.state.recordsCompletionReads = false
            fixture.state.afterWrite = nil
            XCTAssertNotNil(fixture.result)
            XCTAssertEqual(callbacks, 1)
            XCTAssertEqual(queries, 1)
            XCTAssertEqual(queryLayouts, 1)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass + 2)
            XCTAssertEqual(try XCTUnwrap(passAfterQuery), try XCTUnwrap(passBeforeQuery) + 1)
            XCTAssertEqual(fixture.runtime.layoutPassID, try XCTUnwrap(passAfterQuery))
            XCTAssertEqual(fixture.passAtWrite, passBeforeQuery)
            XCTAssertEqual(fixture.passAfterAdoption, passAfterQuery)
            XCTAssertEqual(fixture.adoptionLayoutCalls, 1)
            XCTAssertEqual(fixture.constructionReads, [1])
            XCTAssertEqual(fixture.adoptionReads, [])
            XCTAssertEqual(fixture.state.writes, [value])
            XCTAssertEqual(fixture.state.writeVersions, [0])
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            XCTAssertEqual(Array(fixture.state.text.utf8), Array(value.utf8))
            let root = try XCTUnwrap(preparedRoot)
            XCTAssertFalse(fieldChromeAuthorityIsVisible(root, within: fixture.retainedField))
            try assertInactiveChrome(fixture, base: base, value: value)
            try assertSameValueCanRecoverThroughNormalChromeRefresh(
                fixture, value: value, restoring: try XCTUnwrap(savedNativeLayout))
        }
    }
}
