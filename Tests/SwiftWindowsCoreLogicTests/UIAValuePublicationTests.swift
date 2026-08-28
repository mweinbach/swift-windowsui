import CUIAInterop
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private enum UIAPublicationControl: Equatable {
    case field, editor, secure
}

private enum UIAPublicationHosting: Equatable {
    case raw, window
}

@MainActor
private final class UIAPublicationState {
    let control: UIAPublicationControl
    let bindsSelection: Bool
    var text: String
    var selection: TextSelection?
    var authoredMetadata: String?
    var manager: WinSwiftUI.UndoManager?
    var showsInput = true
    var version = 0
    var builds = 0
    var invalidations = 0
    var values: [String] = []
    var writeVersions: [Int] = []
    var readVersions: [Int] = []
    var selectionWrites = 0
    var beforeRead: (@MainActor (Int) -> Void)?
    var setter: (@MainActor (String) -> Void)?
    var afterWrite: (@MainActor () -> Void)?
    var beforeBuild: (@MainActor () -> Void)?
    var onInvalidate: (@MainActor () -> Void)?

    init(
        control: UIAPublicationControl, bindsSelection: Bool, hosting: UIAPublicationHosting,
        authoredMetadata: String?
    ) {
        self.control = control
        self.bindsSelection = bindsSelection
        self.authoredMetadata = authoredMetadata
        text = control == .secure ? String(repeating: "s", count: 17) : "Ada"
        manager = hosting == .window ? WinSwiftUI.UndoManager() : nil
    }
}

@MainActor
private struct UIAPublicationRoot: View {
    let state: UIAPublicationState

    var body: some View {
        state.beforeBuild?()
        state.builds += 1
        let version = state.version
        let text = Binding<String>(
            get: {
                state.readVersions.append(version)
                state.beforeRead?(version)
                return state.text
            },
            set: {
                state.values.append($0)
                state.writeVersions.append(version)
                if let setter = state.setter { setter($0) } else { state.text = $0 }
                state.afterWrite?()
            })
        let selection = Binding<TextSelection?>(
            get: { state.selection },
            set: {
                state.selectionWrites += 1
                state.selection = $0
            })
        let input: AnyView
        switch state.control {
        case .field:
            input =
                state.bindsSelection
                ? AnyView(TextField("Publication input", text: text, selection: selection))
                : AnyView(TextField("Publication input", text: text))
        case .editor:
            input = AnyView(TextEditor(text: text, selection: state.bindsSelection ? selection : nil))
        case .secure:
            input = AnyView(SecureField("Publication input", text: text))
        }
        let decorated = state.authoredMetadata.map { AnyView(input.accessibilityValue($0)) } ?? input
        return VStack(alignment: .leading, spacing: 4) {
            if state.showsInput {
                decorated
                    .accessibilityLabel("Publication input")
                    .accessibilityIdentifier("uia-value-publication-input")
                    .frame(width: 300, height: 120)
                    .id(0)
            }
            Text("Publication fixture")
        }
        .environment(\.undoManager, state.manager)
    }
}

@MainActor
private func uiaPublicationNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children)
    }
    return result
}

@MainActor
private final class UIAPublicationFixture {
    let state: UIAPublicationState
    let runtime: RetainedViewRuntime
    let componentHost: ComponentHost?
    let windowHost: WinSwiftUIWindowHost?
    let window: Win32Window?
    private var isActive = true
    private(set) var isClosed = false
    lazy var source = RuntimeUIAElementTreeSource(runtime: runtime)

    init(
        control: UIAPublicationControl, hosting: UIAPublicationHosting, bindsSelection: Bool,
        authoredMetadata: String?
    ) throws {
        let state = UIAPublicationState(
            control: control, bindsSelection: bindsSelection,
            hosting: hosting, authoredMetadata: authoredMetadata)
        self.state = state
        let size = IntSize(width: 360, height: 240)
        if hosting == .raw {
            let runtime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 360, height: 240)))
            let host = ComponentHost(runtime: runtime)
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 360, height: 240) },
                invalidateHandler: {
                    state.invalidations += 1
                    state.onInvalidate?()
                })
            host.setComponents { [UIAPublicationRoot(state: state).makeComponent(context: context)] }
            self.runtime = runtime
            componentHost = host
            windowHost = nil
            window = nil
        } else {
            let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
            let window = Win32Window(title: "Value publication fixture", clientSize: size)
            let host = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Value publication fixture", size: size,
                    clearColor: .black, content: [AnyView(UIAPublicationRoot(state: state))]),
                platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
                surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
            host.windowDidCreate(window)
            self.runtime = host.hostedRuntime
            componentHost = nil
            windowHost = host
            self.window = window
            XCTAssertNil(window.nativeHandle)
        }
        runtime.clock = { 0 }
        render()
        runtime.requestFocus(try input())
        render()
    }

    func input() throws -> ViewNode {
        try XCTUnwrap(
            uiaPublicationNodes(in: runtime.root).first {
                $0.accessibilityIdentifier == "uia-value-publication-input"
                    && $0.accessibilityTraits.contains(.isTextInput)
            })
    }

    func snapshot() throws -> UIAElementSnapshot {
        try XCTUnwrap(
            source.uiaElementSnapshots().first {
                $0.automationID == "uia-value-publication-input"
            })
    }

    func rebuildWithoutRender() {
        state.version += 1
        if let windowHost, let window {
            isActive.toggle()
            windowHost.windowDidChangeActiveState(window, isActive: isActive)
        } else {
            componentHost?.reload()
        }
    }

    func render() {
        if let windowHost, let window { windowHost.windowNeedsDisplay(window) }
        _ = runtime.renderScene()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        if let windowHost, let window {
            windowHost.windowWillClose(window)
        } else {
            runtime.root.removeAllChildren()
        }
    }

    func contains(_ node: ViewNode) -> Bool {
        !isClosed && uiaPublicationNodes(in: runtime.root).contains { $0 === node }
    }

    func replace(_ value: String) throws -> TextInputAccessibilityValueResult {
        let node = try input()
        let original = try XCTUnwrap(node.textInputController as? any TextInputAccessibilityValueReplacing)
        return original.replaceValueForAccessibility(
            value,
            validation: TextInputAccessibilityValueValidation(
                mayDispatch: {
                    self.contains(node) && node.textInputController === original
                        && self.runtime.focusedNode === node
                },
                isRetainedTargetCurrent: {
                    self.contains(node) && self.runtime.focusedNode === node
                }))
    }
}

@MainActor
private func uiaPublicationProviderName(_ provider: UnsafeMutableRawPointer?) -> String? {
    guard let value = SWU_UIAProviderGetName(provider) else { return nil }
    defer { SWU_UIAFreeString(value) }
    var length = 0
    while value[length] != 0 { length += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
}

@MainActor
private func retainedUIAPublicationProvider(in parent: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let parent else { return nil }
    if uiaPublicationProviderName(parent) == "Publication input" {
        SWU_UIAAddRefProvider(parent)
        return parent
    }
    var child = SWU_UIAProviderNavigate(parent, Int32(SWU_UIA_NAV_FIRST_CHILD))
    while let current = child {
        let next = SWU_UIAProviderNavigate(current, Int32(SWU_UIA_NAV_NEXT_SIBLING))
        let found = retainedUIAPublicationProvider(in: current)
        SWU_UIAReleaseProvider(current)
        if let found {
            SWU_UIAReleaseProvider(next)
            return found
        }
        child = next
    }
    return nil
}

@MainActor
private func readUIAPublicationValue(_ pattern: UnsafeMutableRawPointer?) -> String? {
    guard let value = SWU_UIAValueProviderGetValue(pattern) else { return nil }
    defer { SWU_UIAFreeString(value) }
    var length = 0
    while value[length] != 0 { length += 1 }
    return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
}

@MainActor
private func setUIAPublicationValue(_ pattern: UnsafeMutableRawPointer?, to value: String) -> Int32 {
    var units = Array(value.utf16)
    units.append(0)
    return units.withUnsafeBufferPointer {
        SWU_UIAValueProviderSetValue(pattern, $0.baseAddress, Int32($0.count - 1))
    }
}

/// Local COM vtables read the real retained adapter. These headless fixtures
/// do not qualify external-client scheduling or a native HWND accessibility host.
@MainActor
final class UIAValuePublicationTests: XCTestCase {
    private func withFixture(
        control: UIAPublicationControl = .field, hosting: UIAPublicationHosting = .raw,
        bindsSelection: Bool = false, authoredMetadata: String? = nil,
        _ body: @MainActor (UIAPublicationFixture) throws -> Void
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
        let fixture = try UIAPublicationFixture(
            control: control, hosting: hosting,
            bindsSelection: bindsSelection, authoredMetadata: authoredMetadata)
        defer { fixture.close() }
        try body(fixture)
    }

    private func withProvider(
        _ source: RuntimeUIAElementTreeSource,
        _ body: @MainActor (UnsafeMutableRawPointer) throws -> Void
    ) throws {
        let bridge = UIAProviderBridge(source: source)
        defer { withExtendedLifetime(bridge) {} }
        let root = try XCTUnwrap(bridge.retainedRootProviderForTesting())
        defer { SWU_UIAReleaseProvider(root) }
        let provider = try XCTUnwrap(retainedUIAPublicationProvider(in: root))
        defer { SWU_UIAReleaseProvider(provider) }
        try body(provider)
    }

    private func withValuePattern(
        _ source: RuntimeUIAElementTreeSource,
        _ body: @MainActor (UnsafeMutableRawPointer) throws -> Void
    ) throws {
        try withProvider(source) { provider in
            let pattern = try XCTUnwrap(SWU_UIAProviderGetValuePattern(provider))
            defer { SWU_UIAReleaseProvider(pattern) }
            try body(pattern)
        }
    }

    func testRawControlsPublishUnicodeEqualAndEmptyValuesForImmediateCOMReadback() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let node = try fixture.input()
                let builds = fixture.state.builds
                let unicode = "Åda 👩🏽‍💻 東京 e\u{301}"
                let values = [unicode, unicode, "", ""]
                try withValuePattern(fixture.source) { pattern in
                    XCTAssertEqual(readUIAPublicationValue(pattern), "Ada")
                    for (index, value) in values.enumerated() {
                        XCTAssertEqual(
                            setUIAPublicationValue(pattern, to: value), 1,
                            "control=\(control), index=\(index)")
                        // Check stored publication before a COM read can query layout.
                        XCTAssertEqual(node.accessibilityValue, value.isEmpty ? nil : value)
                        XCTAssertEqual(fixture.state.text, value)
                        XCTAssertEqual(
                            fixture.state.values, Array(values.prefix(index + 1)),
                            "control=\(control), index=\(index)")
                        XCTAssertEqual(
                            fixture.state.writeVersions, Array(repeating: 0, count: index + 1),
                            "control=\(control), index=\(index)")
                        XCTAssertEqual(
                            fixture.state.invalidations, index + 1,
                            "control=\(control), index=\(index)")
                        XCTAssertEqual(fixture.state.builds, builds)
                        XCTAssertEqual(fixture.state.selectionWrites, 0)
                        XCTAssertEqual(readUIAPublicationValue(pattern), value)
                    }
                }
            }
        }
    }

    func testRawRejectedAndNormalizedSettersPublishObservedValuesWithoutReportingAcceptance() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            for actual in ["normalized", "Ada", ""] {
                try withFixture(control: control) { fixture in
                    let node = try fixture.input()
                    fixture.state.setter = { [weak state = fixture.state] _ in state?.text = actual }
                    try withValuePattern(fixture.source) { pattern in
                        XCTAssertEqual(setUIAPublicationValue(pattern, to: " proposed "), 0)
                        XCTAssertEqual(fixture.state.values, [" proposed "])
                        XCTAssertEqual(fixture.state.writeVersions, [0])
                        XCTAssertEqual(fixture.state.text, actual)
                        XCTAssertEqual(node.accessibilityValue, actual.isEmpty ? nil : actual)
                        XCTAssertEqual(fixture.state.invalidations, 1)
                        XCTAssertEqual(fixture.state.selectionWrites, 0)
                        XCTAssertEqual(readUIAPublicationValue(pattern), actual)
                    }
                }
            }
        }
    }

    func testDirectPublicationAddsNoGetterSelectionWriteOrLayoutQuery() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            for bindsSelection in [false, true] {
                try withFixture(control: control, bindsSelection: bindsSelection) { fixture in
                    let node = try fixture.input()
                    let original = try XCTUnwrap(node.textInputController)
                    let pass = fixture.runtime.layoutPassID
                    fixture.state.readVersions.removeAll()
                    let result = try fixture.replace("atomic value")
                    XCTAssertTrue(result.didDispatch)
                    XCTAssertTrue(result.accepted)
                    // The bound-selection path retains its existing verification read.
                    XCTAssertEqual(fixture.state.readVersions, Array(repeating: 0, count: bindsSelection ? 4 : 3))
                    XCTAssertEqual(fixture.state.values, ["atomic value"])
                    XCTAssertEqual(fixture.state.writeVersions, [0])
                    XCTAssertEqual(fixture.state.selectionWrites, 0)
                    XCTAssertEqual(fixture.state.invalidations, 1)
                    XCTAssertEqual(fixture.runtime.layoutPassID, pass)
                    XCTAssertTrue(node.textInputController === original)
                    XCTAssertEqual(node.accessibilityValue, "atomic value")
                }
            }
        }
    }

    func testSynchronousReplacementKeepsItsAuthoredMetadataWithoutNewControllerReads() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            try withFixture(control: control, hosting: .window, authoredMetadata: "Original declaration") { fixture in
                let node = try fixture.input()
                let original = try XCTUnwrap(node.textInputController)
                let builds = fixture.state.builds
                var readsAfterSetter: [Int] = []
                fixture.state.afterWrite = { [weak fixture] in
                    guard let fixture else { return }
                    fixture.state.authoredMetadata = "Replacement declaration"
                    fixture.rebuildWithoutRender()
                    fixture.state.beforeRead = { readsAfterSetter.append($0) }
                }
                try withValuePattern(fixture.source) { pattern in
                    let result = try fixture.replace("accepted")
                    fixture.state.beforeRead = nil
                    fixture.state.afterWrite = nil
                    XCTAssertTrue(result.didDispatch)
                    XCTAssertTrue(result.accepted)
                    XCTAssertEqual(readsAfterSetter, [0])
                    XCTAssertEqual(fixture.state.values, ["accepted"])
                    XCTAssertEqual(fixture.state.writeVersions, [0])
                    XCTAssertEqual(fixture.state.selectionWrites, 0)
                    XCTAssertEqual(fixture.state.builds, builds + 1)
                    XCTAssertTrue(try fixture.input() === node)
                    XCTAssertFalse(node.textInputController === original)
                    XCTAssertEqual(node.accessibilityValue, "Replacement declaration")
                    XCTAssertEqual(readUIAPublicationValue(pattern), "Replacement declaration")
                }
            }
        }
    }

    func testFinalInvalidationSeesPublicationAndKeepsItsNewerAuthoredMetadata() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let node = try fixture.input()
                var metadataAtInvalidation: String?
                var readsAfterInvalidation: [Int] = []
                fixture.state.onInvalidate = { [weak fixture, weak node] in
                    guard let fixture, let node else { return }
                    metadataAtInvalidation = node.accessibilityValue
                    node.accessibilityValue = "Final authored declaration"
                    fixture.state.beforeRead = { readsAfterInvalidation.append($0) }
                }
                try withValuePattern(fixture.source) { pattern in
                    let result = try fixture.replace("accepted")
                    fixture.state.beforeRead = nil
                    fixture.state.onInvalidate = nil
                    XCTAssertTrue(result.didDispatch)
                    XCTAssertTrue(result.accepted)
                    XCTAssertEqual(metadataAtInvalidation, "accepted")
                    XCTAssertTrue(readsAfterInvalidation.isEmpty)
                    XCTAssertEqual(fixture.state.values, ["accepted"])
                    XCTAssertEqual(fixture.state.writeVersions, [0])
                    XCTAssertEqual(fixture.state.text, "accepted")
                    XCTAssertEqual(fixture.state.invalidations, 1)
                    XCTAssertEqual(fixture.state.selectionWrites, 0)
                    XCTAssertEqual(node.accessibilityValue, "Final authored declaration")
                    XCTAssertEqual(readUIAPublicationValue(pattern), "Final authored declaration")
                }
            }
        }
    }

    func testFinalHostedRefreshKeepsNewerTextAndMetadataAfterOneValueEffect() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            try withFixture(control: control, hosting: .window, authoredMetadata: "Original declaration") { fixture in
                let node = try fixture.input()
                let original = try XCTUnwrap(node.textInputController)
                let builds = fixture.state.builds
                var metadataAtRefresh: String?
                fixture.state.beforeBuild = { [weak fixture, weak node] in
                    guard let fixture, let node else { return }
                    fixture.state.beforeBuild = nil
                    metadataAtRefresh = node.accessibilityValue
                    fixture.state.text = "newer during refresh"
                    fixture.state.authoredMetadata = "Newer declaration"
                    fixture.state.version += 1
                }
                try withValuePattern(fixture.source) { pattern in
                    XCTAssertEqual(setUIAPublicationValue(pattern, to: "accepted"), 0)
                    XCTAssertEqual(metadataAtRefresh, "accepted")
                    XCTAssertEqual(fixture.state.values, ["accepted"])
                    XCTAssertEqual(fixture.state.writeVersions, [0])
                    XCTAssertEqual(fixture.state.text, "newer during refresh")
                    XCTAssertEqual(fixture.state.builds, builds + 1)
                    XCTAssertEqual(fixture.state.selectionWrites, 0)
                    XCTAssertTrue(try fixture.input() === node)
                    XCTAssertFalse(node.textInputController === original)
                    XCTAssertEqual(node.accessibilityValue, "Newer declaration")
                    XCTAssertEqual(readUIAPublicationValue(pattern), "Newer declaration")
                    XCTAssertFalse(try XCTUnwrap(fixture.state.manager).canUndo)
                }
            }
        }
    }

    func testFinalHostedCloseDoesNotOverwriteMetadataAuthoredByTheClosingCallback() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            try withFixture(control: control, hosting: .window) { fixture in
                let node = try fixture.input()
                var metadataAtRefresh: String?
                fixture.state.beforeBuild = { [weak fixture, weak node] in
                    guard let fixture, let node else { return }
                    fixture.state.beforeBuild = nil
                    metadataAtRefresh = node.accessibilityValue
                    fixture.close()
                    node.accessibilityValue = "Closing declaration"
                }
                let result = try fixture.replace("accepted")
                XCTAssertTrue(result.didDispatch)
                XCTAssertFalse(result.accepted)
                XCTAssertTrue(fixture.isClosed)
                XCTAssertEqual(metadataAtRefresh, "accepted")
                XCTAssertEqual(fixture.state.values, ["accepted"])
                XCTAssertEqual(fixture.state.writeVersions, [0])
                XCTAssertEqual(fixture.state.text, "accepted")
                XCTAssertEqual(fixture.state.selectionWrites, 0)
                XCTAssertEqual(node.accessibilityValue, "Closing declaration")
            }
        }
    }

    func testStaleAndSecureRefusalsLeaveMetadataAndBindingsUntouched() async throws {
        for control in [UIAPublicationControl.field, .editor] {
            try withFixture(control: control) { fixture in
                let node = try fixture.input()
                let metadata = node.accessibilityValue
                try withValuePattern(fixture.source) { pattern in
                    fixture.state.showsInput = false
                    fixture.rebuildWithoutRender()
                    let reads = fixture.state.readVersions.count
                    XCTAssertEqual(setUIAPublicationValue(pattern, to: "ignored"), 0)
                    XCTAssertEqual(fixture.state.readVersions.count, reads)
                    XCTAssertTrue(fixture.state.values.isEmpty)
                    XCTAssertEqual(fixture.state.selectionWrites, 0)
                    XCTAssertEqual(fixture.state.text, "Ada")
                    XCTAssertEqual(node.accessibilityValue, metadata)
                    XCTAssertFalse(
                        fixture.source.uiaElementSnapshots().contains {
                            $0.automationID == "uia-value-publication-input"
                        })
                }
            }
        }
        try withFixture(control: .secure) { fixture in
            let node = try fixture.input()
            let secret = fixture.state.text
            try withProvider(fixture.source) { provider in
                let snapshot = try fixture.snapshot()
                let reads = fixture.state.readVersions.count
                XCTAssertFalse(fixture.source.uiaSetValue(elementID: snapshot.id, value: "ignored"))
                XCTAssertEqual(fixture.state.readVersions.count, reads)
                XCTAssertTrue(fixture.state.values.isEmpty)
                XCTAssertEqual(fixture.state.selectionWrites, 0)
                XCTAssertTrue(fixture.state.text == secret, "Secure storage must remain unchanged")
                XCTAssertTrue(node.accessibilityValue == nil, "Secure metadata must remain absent")
                XCTAssertTrue(snapshot.value == nil, "Secure UIA values must remain absent")
                XCTAssertFalse(snapshot.supportsValue)
                let pattern = SWU_UIAProviderGetValuePattern(provider)
                defer { SWU_UIAReleaseProvider(pattern) }
                XCTAssertNil(pattern)
                var hasPasswordProperty: Int32 = 0
                XCTAssertEqual(
                    SWU_UIAProviderGetBoolProperty(
                        provider, Int32(SWU_UIA_BOOL_IS_PASSWORD),
                        &hasPasswordProperty), 1)
                XCTAssertEqual(hasPasswordProperty, 1)
                XCTAssertFalse(
                    fixture.source.uiaElementSnapshots().contains {
                        $0.name == secret || $0.value == secret
                    }, "Secure content must not appear in UIA")
            }
        }
    }

    func testAuthoredFieldSelectionSettlesInOneGeometryQueryWithoutRepeatingFollowup() async throws {
        try withFixture(control: .field, bindsSelection: true) { fixture in
            let node = try fixture.input()
            let original = try XCTUnwrap(node.textInputController)
            let elementID = try fixture.snapshot().id
            let builds = fixture.state.builds
            let value = "A👩‍👩‍👧‍👧e\u{301}Z"
            let lower = value.index(value.startIndex, offsetBy: 1)
            let upper = value.index(value.startIndex, offsetBy: 3)
            let authored = TextSelection(range: lower..<upper)
            let selectedText = String(value[lower..<upper])
            fixture.state.afterWrite = { [weak state = fixture.state] in state?.selection = authored }

            XCTAssertTrue(fixture.source.uiaSetValue(elementID: elementID, value: value))
            fixture.state.afterWrite = nil
            XCTAssertEqual(fixture.state.values, [value])
            XCTAssertEqual(fixture.state.writeVersions, [0])
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            XCTAssertEqual(fixture.state.invalidations, 1)
            XCTAssertEqual(fixture.state.builds, builds)
            XCTAssertEqual(fixture.state.selection, authored)
            XCTAssertEqual(node.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(node.textInputCaretOffset, 3)
            XCTAssertEqual(node.accessibilityValue, value)

            let beforeQuery = fixture.runtime.layoutPassID
            let frame = try XCTUnwrap(fixture.runtime.resolvedLayoutFrame(of: node))
            XCTAssertEqual(fixture.runtime.layoutPassID, beforeQuery + 2)
            guard case .settled(let firstReceipt) = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("One geometry query must settle the field's changed selection chrome")
            }
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(firstReceipt))
            XCTAssertGreaterThan(frame.size.width, 0)
            XCTAssertGreaterThan(frame.size.height, 0)
            XCTAssertTrue(node.textInputController === original)
            XCTAssertTrue(fixture.runtime.focusedNode === node)
            XCTAssertEqual(node.children.first?.text, value)
            XCTAssertEqual(uiaPublicationNodes(in: node).filter(\.isTextInputCaret).count, 0)
            XCTAssertEqual(
                uiaPublicationNodes(in: node).filter {
                    $0.text == selectedText && $0.backgroundColor != nil
                }.count, 1)

            let beforeCachedQuery = fixture.runtime.layoutPassID
            XCTAssertEqual(fixture.runtime.resolvedLayoutFrame(of: node), frame)
            XCTAssertEqual(fixture.runtime.layoutPassID, beforeCachedQuery + 1)
            guard case .settled(let cachedReceipt) = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("Unchanged field chrome must not enqueue another follow-up")
            }
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(cachedReceipt))
            XCTAssertEqual(Array(fixture.state.text.utf8), Array(value.utf8))
            XCTAssertEqual(fixture.state.selection, authored)
            XCTAssertEqual(node.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(node.textInputCaretOffset, 3)
            XCTAssertEqual(node.accessibilityValue, value)
            XCTAssertEqual(fixture.state.values, [value])
            XCTAssertEqual(fixture.state.writeVersions, [0])
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            XCTAssertEqual(fixture.state.invalidations, 1)
            XCTAssertEqual(fixture.state.builds, builds)
        }
    }

    func testRelocatedFieldCannotQueueChromeSettlementOnItsConstructionRuntime() async throws {
        try withFixture(control: .field) { fixture in
            let runtimeA = fixture.runtime
            let node = try fixture.input()
            let original = try XCTUnwrap(node.textInputController)
            let builds = fixture.state.builds
            let runtimeB = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 360, height: 240)))
            runtimeB.clock = { 0 }
            defer {
                runtimeA.root.onLayout = nil
                runtimeB.root.removeAllChildren()
            }

            // Public reparenting reattaches the same controller. Its captured
            // constructor runtime remains A; no controller runtime is fabricated.
            runtimeB.root.addChild(node)
            runtimeB.requestFocus(node)
            _ = runtimeB.renderScene()
            XCTAssertTrue(node.parent === runtimeB.root)
            XCTAssertTrue(runtimeB.root.children.contains { $0 === node })
            XCTAssertFalse(fixture.contains(node))
            XCTAssertTrue(node.textInputController === original)
            XCTAssertNil(runtimeA.focusedNode)
            XCTAssertTrue(runtimeB.focusedNode === node)
            let label = try XCTUnwrap(node.children.first)
            let previousChrome = try XCTUnwrap(node.children.last)
            XCTAssertFalse(label === previousChrome)
            XCTAssertEqual(label.text, "Ada")

            let readsBeforeQuery = fixture.state.readVersions.count
            fixture.state.text = "Moved field content"
            // A plain model mutation does not invalidate the new runtime.
            // This public placement change ensures B visits the real callback.
            node.frame = node.frame.offsetBy(dx: 1, dy: 0)
            let passesA = runtimeA.layoutPassID
            let passesB = runtimeB.layoutPassID
            var performedNestedQuery = false
            var nestedQueries = 0
            var observedAInLayout = false
            var nestedFrame: Rect?
            runtimeA.root.onLayout = { [weak runtimeA, weak runtimeB, weak node] _ in
                guard !performedNestedQuery else { return }
                performedNestedQuery = true
                guard let runtimeA, let runtimeB, let node else {
                    return XCTFail("The two runtime owners must remain alive during the nested query")
                }
                nestedQueries += 1
                observedAInLayout = runtimeA.isLayoutInProgress
                nestedFrame = runtimeB.resolvedLayoutFrame(of: node)
            }

            XCTAssertNotNil(runtimeA.resolvedLayoutFrame(of: runtimeA.root))
            XCTAssertEqual(nestedQueries, 1)
            XCTAssertTrue(observedAInLayout)
            // B's returned frame witnesses traversal, not a settled B receipt.
            XCTAssertNotNil(nestedFrame)
            XCTAssertEqual(runtimeB.layoutPassID, passesB + 1)
            XCTAssertEqual(runtimeA.layoutPassID, passesA + 1)
            XCTAssertEqual(label.text, "Moved field content")
            XCTAssertFalse(node.children.last === previousChrome)
            XCTAssertGreaterThan(fixture.state.readVersions.count, readsBeforeQuery)
            XCTAssertTrue(node.parent === runtimeB.root)
            XCTAssertTrue(node.textInputController === original)
            XCTAssertTrue(fixture.state.values.isEmpty)
            XCTAssertTrue(fixture.state.writeVersions.isEmpty)
            XCTAssertEqual(fixture.state.selectionWrites, 0)
            XCTAssertEqual(fixture.state.invalidations, 0)
            XCTAssertEqual(fixture.state.builds, builds)
        }
    }

}
