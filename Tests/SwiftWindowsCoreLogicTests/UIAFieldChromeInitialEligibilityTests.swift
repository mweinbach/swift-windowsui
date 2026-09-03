import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum InitialChromeExtra: CaseIterable {
    case sibling
    case insideLabel
}

private enum InitialChromeEntry: CaseIterable {
    case adopt
    case reconcile
}

@MainActor
private final class InitialChromeState {
    var text = "abcd"
    var version = 0
    var writes: [String] = []
    var writeVersions: [Int] = []
    var buttonCalls: [Int] = []
    var layoutCalls = 0
    var authoredCreated = 0
    var authoredReleased = 0
    var authoredActions = 0
    var afterWrite: (@MainActor () -> Void)?
    weak var authored: ViewNode?
}

@MainActor
private final class InitialChromePayload {
    let state: InitialChromeState
    init(_ state: InitialChromeState) {
        self.state = state
        state.authoredCreated += 1
    }
    isolated deinit { state.authoredReleased += 1 }
}

@MainActor
private func initialChromeNodes(_ root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private struct InitialChromeBuild {
    let root: ViewNode
    let field: ViewNode
    let earlier: ViewNode
}

/// Public fields and Buttons share the actual retained adoption entry points.
/// Authored extras are installed before that entry, never relabeled as chrome.
@MainActor
private final class InitialChromeFixture {
    let state: InitialChromeState
    let runtime: RetainedViewRuntime
    let context: ViewBuildContext
    let retained: InitialChromeBuild
    let framed: Bool
    let companions: Bool
    lazy var source = RuntimeUIAElementTreeSource(runtime: runtime)
    var result: RetainedLazyListAdoptionResult?
    var adoptionLayoutCalls: Int?
    var passBeforeAdoption: UInt64?
    var passAfterAdoption: UInt64?

    init(framed: Bool, companions: Bool) throws {
        let state = InitialChromeState()
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 360, height: 260), isHitTestVisible: false))
        runtime.clock = { 0 }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 360, height: 260) }, invalidateHandler: {})
        let built = try Self.build(
            state: state, runtime: runtime, context: context, framed: framed, companions: companions)
        self.state = state
        self.runtime = runtime
        self.context = context
        self.retained = built
        self.framed = framed
        self.companions = companions
        runtime.root.addChild(built.root)
        runtime.requestFocus(built.field)
        _ = runtime.renderScene()
    }

    private static func build(
        state: InitialChromeState, runtime: RetainedViewRuntime, context: ViewBuildContext,
        framed: Bool, companions: Bool
    ) throws -> InitialChromeBuild {
        let version = state.version
        let binding = Binding<String>(
            get: { state.text },
            set: {
                state.writes.append($0)
                state.writeVersions.append(version)
                state.text = $0
                state.afterWrite?()
            })
        var view = AnyView(TextField("Eligibility field", text: binding).accessibilityIdentifier("eligibility-field"))
        if framed { view = AnyView(view.frame(width: 300, height: 60)) }
        let content = view.makeComponent(context: context).makeNode(runtime: runtime)
        content.nodeTag = "eligibility-content"
        content.frame = Rect(x: 0, y: 20, width: 300, height: 60)
        let field = try XCTUnwrap(initialChromeNodes(content).first { $0.textInputController != nil })
        let layout = field.onLayout
        field.onLayout = { bounds in
            state.layoutCalls += 1
            layout?(bounds)
        }
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 360, height: 240))
        root.nodeTag = "eligibility-row"
        let earlier = ViewNode(frame: Rect(x: 0, y: 0, width: 8, height: 8), text: "Earlier \(version)")
        earlier.nodeTag = "eligibility-earlier"
        root.addChild(earlier)
        root.addChild(content)
        if companions {
            // This pristine registration keeps the chrome scope nonempty even
            // when the first field is ineligible for optional preparation.
            let other = TextField("Other field", text: .constant("Other"))
                .accessibilityIdentifier("eligibility-other")
                .makeComponent(context: context).makeNode(runtime: runtime)
            other.nodeTag = "eligibility-other"
            other.frame = Rect(x: 0, y: 90, width: 300, height: 40)
            root.addChild(other)
            let button = Button("Run") { state.buttonCalls.append(version) }
                .accessibilityIdentifier("eligibility-button")
                .makeComponent(context: context).makeNode(runtime: runtime)
            button.nodeTag = "eligibility-button"
            button.frame = Rect(x: 0, y: 150, width: 100, height: 32)
            root.addChild(button)
        }
        return InitialChromeBuild(root: root, field: field, earlier: earlier)
    }

    func incoming() throws -> InitialChromeBuild {
        state.version += 1
        return try Self.build(state: state, runtime: runtime, context: context, framed: framed, companions: companions)
    }

    func addAuthored(to field: ViewNode, location: InitialChromeExtra) throws {
        let parent = location == .sibling ? field : try XCTUnwrap(field.children.first)
        let payload = InitialChromePayload(state)
        let authored = ViewNode(
            frame: Rect(x: 0, y: 0, width: 8, height: 8),
            accessibilityLabel: "Authored child", accessibilityIdentifier: "eligibility-authored")
        // An authored identity may not reuse an old native chrome node.
        authored.retainedViewIdentity = .init(segments: [.role(.content), .slot(777)])
        authored.onActivate = { payload.state.authoredActions += 1 }
        state.authored = authored
        parent.addChild(authored)
    }

    func adopt(_ incoming: InitialChromeBuild, entry: InitialChromeEntry) {
        passBeforeAdoption = runtime.layoutPassID
        let layouts = state.layoutCalls
        switch entry {
        case .adopt:
            result = ComponentHost.adopt(source: incoming.root, into: retained.root)
        case .reconcile:
            result = ComponentHost.reconcileChildren(
                of: runtime.root, oldChildren: runtime.root.children, newNodes: [incoming.root])
        }
        adoptionLayoutCalls = state.layoutCalls - layouts
        passAfterAdoption = runtime.layoutPassID
    }

    func id(_ identifier: String = "eligibility-field") throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == identifier }).id
    }

    func assertAuthoredPresent(location: InitialChromeExtra) throws {
        let authored = try XCTUnwrap(state.authored)
        let parent = location == .sibling ? retained.field : try XCTUnwrap(retained.field.children.first)
        XCTAssertTrue(authored.parent === parent)
        XCTAssertTrue(parent.children.contains { $0 === authored })
        XCTAssertEqual(state.authoredCreated, 1)
        XCTAssertEqual(state.authoredReleased, 0)
        XCTAssertEqual(state.authoredActions, 0)
    }

    func close() {
        state.afterWrite = nil
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
final class UIAFieldChromeInitialEligibilityTests: XCTestCase {
    private func withFixture(
        framed: Bool, companions: Bool = false, _ body: (InitialChromeFixture) throws -> Void
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
        let fixture = try InitialChromeFixture(framed: framed, companions: companions)
        defer { fixture.close() }
        try body(fixture)
    }

    private func assertPositiveMatrix(companions: Bool) throws {
        for framed in [false, true] {
            for entry in InitialChromeEntry.allCases {
                for location in InitialChromeExtra.allCases {
                    try withFixture(framed: framed, companions: companions) { fixture in
                        let field = fixture.retained.field
                        let id = try fixture.id()
                        fixture.state.afterWrite = { [weak fixture] in
                            guard let fixture else { return }
                            do {
                                let incoming = try fixture.incoming()
                                try fixture.addAuthored(to: incoming.field, location: location)
                                fixture.adopt(incoming, entry: entry)
                            } catch { XCTFail("Unable to construct authored input: \(error)") }
                        }
                        XCTAssertTrue(fixture.source.uiaSetValue(elementID: id, value: "one effect"))
                        fixture.state.afterWrite = nil
                        XCTAssertTrue(try XCTUnwrap(fixture.result).completed)
                        XCTAssertEqual(fixture.state.writes, ["one effect"])
                        XCTAssertEqual(fixture.state.writeVersions, [0])
                        XCTAssertEqual(fixture.adoptionLayoutCalls, 0)
                        XCTAssertEqual(fixture.passBeforeAdoption, fixture.passAfterAdoption)
                        XCTAssertTrue(initialChromeNodes(fixture.runtime.root).contains { $0 === field })
                        // No projection, render, or layout is inserted between
                        // the value call and this original-child ownership check.
                        try fixture.assertAuthoredPresent(location: location)
                        if companions {
                            XCTAssertTrue(
                                fixture.source.uiaInvokeDefaultAction(elementID: try fixture.id("eligibility-button")))
                            XCTAssertEqual(fixture.state.buttonCalls, [1])
                            XCTAssertEqual(fixture.state.writes, ["one effect"])
                            let other = try XCTUnwrap(
                                initialChromeNodes(fixture.runtime.root).first {
                                    $0.accessibilityIdentifier == "eligibility-other" && $0.textInputController != nil
                                })
                            XCTAssertEqual(other.accessibilityValue, "Other")
                        }
                    }
                }
            }
        }
    }

    func testInitiallyAuthoredChildrenSurvivePlainAndFramedValueAdoption() async throws {
        try assertPositiveMatrix(companions: false)
    }

    func testInitiallyAuthoredChildrenCoexistWithButtonAndPristineField() async throws {
        try assertPositiveMatrix(companions: true)
    }

    func testInitiallyEligibleSourcesStillRejectPostCaptureChildMutationAndAttachmentABA() async throws {
        for entry in InitialChromeEntry.allCases {
            for restoresShape in [false, true] {
                try withFixture(framed: true) { fixture in
                    let id = try fixture.id()
                    let originalController = fixture.retained.field.textInputController
                    var callbacks = 0
                    fixture.state.afterWrite = { [weak fixture] in
                        guard let fixture else { return }
                        do {
                            let incoming = try fixture.incoming()
                            let label = try XCTUnwrap(incoming.field.children.first)
                            let attachment = label.captureLazyListAttachmentProof()
                            incoming.earlier.onUpdatePlatformView = { _ in
                                callbacks += 1
                                if restoresShape {
                                    incoming.field.removeChild(label)
                                    incoming.field.addChild(label)
                                    XCTAssertFalse(attachment.isCurrent)
                                    XCTAssertEqual(incoming.field.children.count, 1)
                                    XCTAssertTrue(incoming.field.children.first === label)
                                } else {
                                    incoming.field.addChild(ViewNode())
                                }
                            }
                            fixture.adopt(incoming, entry: entry)
                            incoming.earlier.onUpdatePlatformView = nil
                        } catch { XCTFail("Unable to construct mutation input: \(error)") }
                    }
                    XCTAssertFalse(fixture.source.uiaSetValue(elementID: id, value: "one effect"))
                    fixture.state.afterWrite = nil
                    XCTAssertEqual(callbacks, 1)
                    XCTAssertFalse(try XCTUnwrap(fixture.result).completed)
                    XCTAssertTrue(fixture.retained.field.textInputController === originalController)
                    XCTAssertEqual(fixture.state.writes, ["one effect"])
                    XCTAssertEqual(fixture.state.writeVersions, [0])
                    XCTAssertEqual(fixture.adoptionLayoutCalls, 0)
                }
            }
        }
    }

    func testCapturedPristineShapeDoesNotHideOriginalTextMismatch() async throws {
        for framed in [false, true] {
            try withFixture(framed: framed, companions: true) { fixture in
                let id = try fixture.id()
                let originalController = fixture.retained.field.textInputController
                fixture.state.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    do {
                        let incoming = try fixture.incoming()
                        let label = try XCTUnwrap(incoming.field.children.first)
                        label.text = "Not the registered constructor text"
                        XCTAssertEqual(incoming.field.children.count, 1)
                        XCTAssertTrue(label.children.isEmpty)
                        fixture.adopt(incoming, entry: .adopt)
                    } catch { XCTFail("Unable to construct text mismatch: \(error)") }
                }
                // A plain field still reports the original setter's accepted
                // value when the rejected rebuild left its owner untouched.
                // A framed target additionally needs a completed publication.
                let accepted = fixture.source.uiaSetValue(elementID: id, value: "one effect")
                XCTAssertEqual(accepted, !framed)
                fixture.state.afterWrite = nil
                XCTAssertFalse(try XCTUnwrap(fixture.result).completed)
                XCTAssertTrue(fixture.retained.field.textInputController === originalController)
                XCTAssertEqual(fixture.state.writes, ["one effect"])
                XCTAssertEqual(fixture.state.buttonCalls, [])
            }
        }
    }

    func testClaimedRegistrationIsNotOmittedWhenNestedCaptureSeesAuthoredChildren() async throws {
        for location in InitialChromeExtra.allCases {
            try withFixture(framed: false) { fixture in
                let incoming = try fixture.incoming()
                let outer = try XCTUnwrap(
                    RetainedTextInputChromeAdoptionScope(
                        retainedRoots: [fixture.retained.root], sourceRoots: [incoming.root]))
                outer.associateOriginalContext(
                    admission: nil, lazyJournal: nil, taskAdoption: nil, buttonActions: nil, uiaAuthority: nil)
                defer { outer.closeAndReleaseConstruction() }
                XCTAssertTrue(outer.bind(source: incoming.field, target: fixture.retained.field, strict: true))
                try fixture.addAuthored(to: incoming.field, location: location)
                // The registration still points at its original outer attempt.
                // A nested scope must keep it enrolled and refuse reuse, rather
                // than silently treating it as an unclaimed optional recipe.
                let nested = try XCTUnwrap(
                    RetainedTextInputChromeAdoptionScope(
                        retainedRoots: [fixture.retained.root], sourceRoots: [incoming.root]))
                nested.associateOriginalContext(
                    admission: nil, lazyJournal: nil, taskAdoption: nil, buttonActions: nil, uiaAuthority: nil)
                defer { nested.closeAndReleaseConstruction() }
                XCTAssertFalse(nested.bind(source: incoming.field, target: fixture.retained.field, strict: true))
                XCTAssertEqual(fixture.state.writes, [])
                XCTAssertEqual(fixture.state.buttonCalls, [])
                XCTAssertFalse(initialChromeNodes(fixture.runtime.root).contains { $0 === fixture.state.authored })
            }
        }
    }
}
