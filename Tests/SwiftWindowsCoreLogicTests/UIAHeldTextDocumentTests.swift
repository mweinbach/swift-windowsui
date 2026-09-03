import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class UIAHeldTextDocumentTests: XCTestCase {
    func testDocumentRangeAndClonePreserveExactTextWithoutCallbacks() async throws {
        let original = "Ae\u{301}👩‍👩‍👧‍👦אב\r\n\0Z"
        let fixture = try HeldTextFixture(original)
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        let clone = try XCTUnwrap(range.clone())
        XCTAssertEqual(Array(try XCTUnwrap(range.getText()).utf16), Array(original.utf16))
        XCTAssertEqual(try clone.getText(), original)
        XCTAssertEqual(range.compareEndpoints(.end, to: clone, endpoint: .end), 0)
        XCTAssertEqual(try range.getText(maximumUTF16Length: 2), "A")
        XCTAssertEqual(try range.getText(maximumUTF16Length: 0), "")
        XCTAssertEqual(try document.range(utf16Start: 1, utf16End: 3)?.getText(), "e\u{301}")
        XCTAssertNil(document.range(utf16Start: 1, utf16End: 2))
        XCTAssertNil(document.range(utf16Start: Int.min, utf16End: Int.max))
        XCTAssertThrowsError(try range.getText(maximumUTF16Length: Int.min)) {
            XCTAssertEqual($0 as? TextRangeValueError, .invalidMaximumLength)
        }
        XCTAssertEqual(try range.getText(), original)
        fixture.assertQuiet()
    }

    func testEqualUTF16AssignmentSurvivesButCanonicalEquivalentChangeInvalidates() async throws {
        let fixture = try HeldTextFixture("e\u{301}")
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        fixture.text.text = String(decoding: Array("e\u{301}".utf16), as: UTF16.self)
        XCTAssertEqual(try range.getText(), "e\u{301}")
        fixture.text.text = "\u{e9}"
        XCTAssertNil(try range.getText())
        XCTAssertNil(document.documentRange())
        fixture.text.text = "e\u{301}"
        XCTAssertNil(try range.getText())
        XCTAssertNotNil(fixture.source.uiaTextDocument(elementID: fixture.id))
    }

    func testContentABAInvalidatesWithoutAnIntermediateRead() async throws {
        let fixture = try HeldTextFixture("first")
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        fixture.text.text = "other"
        fixture.text.text = "first"
        XCTAssertNil(try range.getText())
        XCTAssertNil(range.clone())
        let current = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        XCTAssertEqual(try current.documentRange()?.getText(), "first")
    }

    func testNilAndEmptyTransitionsDoNotResurrectOriginalDocument() async throws {
        let fixture = try HeldTextFixture("")
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        XCTAssertEqual(try range.getText(), "")
        fixture.text.text = nil
        fixture.text.text = ""
        XCTAssertNil(try range.getText())
        let current = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        XCTAssertEqual(try current.documentRange()?.getText(), "")
    }

    func testDetachAndReinsertCannotRefreshOriginalAttachment() async throws {
        let fixture = try HeldTextFixture()
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        fixture.container.removeChild(fixture.text)
        fixture.container.addChild(fixture.text)
        XCTAssertNil(try range.getText())
        let current = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        XCTAssertEqual(try current.documentRange()?.getText(), "Original")
    }

    func testReplacementWithSameAutomationIDAndTextDoesNotLendAuthority() async throws {
        let fixture = try HeldTextFixture()
        let original = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(original.documentRange())
        let replacement = ViewNode(text: "Original")
        replacement.accessibilityIdentifier = fixture.text.accessibilityIdentifier
        fixture.container.setChildren([replacement])
        let replacementID = try XCTUnwrap(
            fixture.source.uiaElementSnapshots().first { $0.automationID == "held-text" }?.id)
        XCTAssertNotEqual(replacementID, fixture.id)
        XCTAssertNil(try range.getText())
        XCTAssertNil(fixture.source.uiaTextDocument(elementID: fixture.id))
        let current = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: replacementID))
        XCTAssertEqual(try current.documentRange()?.getText(), "Original")
    }

    func testPrivacyAndRepresentationExclusionsInvalidateHeldReads() async throws {
        let denials: [(ViewNode) -> Void] = [
            { $0.isPrivacySensitive = true },
            { $0.redactionReasons = .placeholder },
            { $0.isHidden = true },
            { $0.isAccessibilityHidden = true },
            { $0.isLayoutDeferredByVirtualization = true },
            { $0.accessibilityTraits.insert(.isSecureTextInput) },
            { $0.accessibilityTraits.insert(.isTextInput) },
            { $0.accessibilityTraits.insert(.isSearchField) },
            { $0.accessibilityChildBehavior = .combine },
            { $0.accessibilityRepresentationChildren = [ViewNode(text: "Synthetic")] },
        ]
        for deny in denials {
            let fixture = try HeldTextFixture()
            let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
            let range = try XCTUnwrap(document.documentRange())
            deny(fixture.container)
            XCTAssertNil(try range.getText())
            XCTAssertNil(document.documentRange())
            XCTAssertNil(fixture.source.uiaTextDocument(elementID: fixture.id))
            fixture.assertQuiet()
        }
        let fixture = try HeldTextFixture()
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        fixture.text.isPrivacySensitive = true
        XCTAssertNil(try range.getText())
        fixture.text.isPrivacySensitive = false
        XCTAssertNil(try range.getText())
        XCTAssertNotNil(fixture.source.uiaTextDocument(elementID: fixture.id))
    }

    func testFieldEditorAndSecureControllerAncestryNeverReadsBindings() async throws {
        for kind in 0..<3 {
            let fixture = try HeldTextFixture()
            let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
            let range = try XCTUnwrap(document.documentRange())
            let effects = HeldTextEffects()
            let binding = Binding<String>(
                get: {
                    effects.bindingGets += 1
                    return "Secret"
                },
                set: { _ in effects.bindingSets += 1 })
            let selection = Binding<TextSelection?>(
                get: {
                    effects.selectionGets += 1
                    return nil
                },
                set: { _ in effects.selectionSets += 1 })
            let view: AnyView
            switch kind {
            case 0: view = AnyView(TextField("Field", text: binding, selection: selection))
            case 1: view = AnyView(TextEditor(text: binding, selection: selection))
            default: view = AnyView(SecureField("Secure", text: binding))
            }
            let context = ViewBuildContext(
                canvasSizeProvider: { Size(width: 400, height: 200) }, invalidateHandler: {})
            let owner = view.makeComponent(context: context).makeNode(runtime: fixture.runtime)
            fixture.container.textInputController = try XCTUnwrap(owner.textInputController)
            fixture.container.accessibilityTraits = []
            effects.resetBindings()
            XCTAssertNil(try range.getText())
            XCTAssertNil(fixture.source.uiaTextDocument(elementID: fixture.id))
            XCTAssertEqual(effects.bindingGets, 0)
            XCTAssertEqual(effects.bindingSets, 0)
            XCTAssertEqual(effects.selectionGets, 0)
            XCTAssertEqual(effects.selectionSets, 0)
            fixture.assertQuiet()
        }
    }

    func testLazyAdapterAncestryRejectsWithoutRealization() async throws {
        let fixture = try HeldTextFixture()
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        var factories = 0
        let data = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            data.replaceData([0], id: \.self) { _ in
                factories += 1
                return [ViewNode(text: "Unconstructed")]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: data, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        fixture.container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(fixture.container))
        XCTAssertNil(try range.getText())
        XCTAssertNil(fixture.source.uiaTextDocument(elementID: fixture.id))
        XCTAssertNil(fixture.source.uiaTextDocument(elementID: UInt64(1) << 63))
        XCTAssertEqual(factories, 0)
        fixture.assertQuiet()
    }

    func testOriginalSelectedPathRejectsChildrenABAWithAttachmentStillCurrent() async throws {
        let fixture = try HeldTextFixture(selected: true)
        let target = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.text))
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        let extra = ViewNode(text: "Rejected sibling")
        fixture.container.addChild(extra)
        fixture.container.removeChild(extra)
        XCTAssertTrue(fixture.runtime.isAccessibilityTextReadTargetCurrent(target))
        XCTAssertNil(try range.getText())
        let current = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        XCTAssertEqual(try current.documentRange()?.getText(), "Original")
        fixture.assertQuiet()
    }

    func testDocumentsAndRangesDoNotRetainSourceRuntimeOrNodes() async throws {
        var fixture: HeldTextFixture? = try HeldTextFixture()
        weak var source = fixture?.source
        weak var runtime = fixture?.runtime
        weak var root = fixture?.runtime.root
        weak var text = fixture?.text
        let document = try XCTUnwrap(fixture?.source.uiaTextDocument(elementID: try XCTUnwrap(fixture?.id)))
        let range = try XCTUnwrap(document.documentRange())
        fixture = nil
        XCTAssertNil(source)
        XCTAssertNil(runtime)
        XCTAssertNil(root)
        XCTAssertNil(text)
        XCTAssertNil(document.documentRange())
        XCTAssertNil(try range.getText())
    }

    func testDisabledOffscreenPlainTextRemainsReadable() async throws {
        let fixture = try HeldTextFixture()
        let document = try XCTUnwrap(fixture.source.uiaTextDocument(elementID: fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        fixture.container.accessibilityRespondsToUserInteraction = false
        fixture.text.frame = Rect(x: 10, y: 1000, width: 180, height: 20)
        fixture.text.resolvedFrame = fixture.text.frame
        XCTAssertEqual(try range.getText(), "Original")
        XCTAssertNotNil(document.documentRange())
        fixture.assertQuiet()
    }

    func testRequestAdmissionAndProviderRevocationRejectHeldPublication() async throws {
        let fixture = try HeldTextFixture()
        let harness = HeldTextRequestHarness(source: fixture.source)
        XCTAssertEqual(
            try harness.reply(.textDocument(element: fixture.id), isAvailable: { false }), .textDocument(nil))
        let document = try XCTUnwrap(harness.document(fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        var checks = 0
        let request = UIAProviderRequest.textRangeContent(range: range, maximumUTF16Length: -1)
        XCTAssertEqual(
            try harness.reply(
                request,
                isAvailable: {
                    checks += 1
                    return checks == 1
                }), .string(nil))
        XCTAssertEqual(try harness.reply(request), .string("Original"))
        harness.bridge.revokeNativeRequests()
        XCTAssertEqual(try harness.reply(request), .string(nil))
        XCTAssertNil(try range.getText())
        fixture.assertQuiet()
    }

    func testSameRootElementIDInAnotherProviderCannotBorrowHeldRange() async throws {
        let firstRuntime = RetainedViewRuntime(root: ViewNode(text: "Same"))
        let secondRuntime = RetainedViewRuntime(root: ViewNode(text: "Same"))
        let firstSource = RuntimeUIAElementTreeSource(runtime: firstRuntime)
        let secondSource = RuntimeUIAElementTreeSource(runtime: secondRuntime)
        let first = HeldTextRequestHarness(source: firstSource)
        let second = HeldTextRequestHarness(source: secondSource)
        let firstDocument = try XCTUnwrap(first.document(0))
        let secondDocument = try XCTUnwrap(second.document(0))
        let firstRange = try XCTUnwrap(firstDocument.documentRange())
        let secondRange = try XCTUnwrap(secondDocument.documentRange())
        XCTAssertNil(firstRange.compareEndpoints(.start, to: secondRange, endpoint: .start))
        let request = UIAProviderRequest.textRangeContent(range: firstRange, maximumUTF16Length: -1)
        XCTAssertEqual(try second.reply(request), .string(nil))
        XCTAssertEqual(try first.reply(request), .string("Same"))
    }

    func testProviderOwnerIsWeakAndCannotBeRebound() async throws {
        let fixture = try HeldTextFixture()
        var harness: HeldTextRequestHarness? = HeldTextRequestHarness(source: fixture.source)
        weak var owner = harness?.bridge
        let document = try XCTUnwrap(harness?.document(fixture.id))
        let range = try XCTUnwrap(document.documentRange())
        harness = nil
        XCTAssertNil(owner)
        let replacement = HeldTextRequestHarness(source: fixture.source)
        XCTAssertFalse(document.bind(to: replacement.bridge))
        XCTAssertNil(try range.getText())
        XCTAssertNotNil(fixture.source.uiaTextDocument(elementID: fixture.id))
    }

    func testReentrantAuthorityCannotUndoAnObservedRefusal() async throws {
        // This checks the package authority contract, not authored callbacks
        // in the retained source or native COM reentrancy.
        let authority = ReentrantHeldTextAuthority()
        let document = UIATextDocument(snapshot: try XCTUnwrap(TextRangeSnapshot("Copy")), authority: authority)
        authority.document = document
        let range = try XCTUnwrap(document.documentRange())
        authority.armed = true
        XCTAssertNil(range.clone())
        XCTAssertTrue(authority.nestedWasRejected)
        XCTAssertFalse(document.isCurrent)
        XCTAssertNil(document.documentRange())
        XCTAssertNil(range.compareEndpoints(.start, to: range, endpoint: .start))
        XCTAssertNil(try range.getText())
    }
}

@MainActor
private final class ReentrantHeldTextAuthority: UIATextDocumentAuthority {
    weak var document: UIATextDocument?
    var armed = false
    var didReenter = false
    var nestedWasRejected = false

    func isCurrent() -> Bool {
        guard armed else { return true }
        guard !didReenter else { return false }
        didReenter = true
        nestedWasRejected = document?.isCurrent == false
        return true
    }
}

@MainActor
private final class HeldTextEffects {
    var maps = 0
    var layouts = 0
    var actions = 0
    var bindingGets = 0
    var bindingSets = 0
    var selectionGets = 0
    var selectionSets = 0

    func resetBindings() {
        bindingGets = 0
        bindingSets = 0
        selectionGets = 0
        selectionSets = 0
    }
}

@MainActor
private final class HeldTextFixture {
    let runtime: RetainedViewRuntime
    let container: ViewNode
    let text: ViewNode
    let source: RuntimeUIAElementTreeSource
    let id: UInt64
    let effects: HeldTextEffects

    init(_ content: String = "Original", selected: Bool = false) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
        root.resolvedFrame = root.frame
        let text = ViewNode(frame: Rect(x: 10, y: 10, width: 180, height: 20), text: content)
        text.resolvedFrame = text.frame
        text.accessibilityIdentifier = "held-text"
        let container =
            selected
            ? ViewNode.selectedContentBoundary(role: .viewThatFits, child: text)
            : ViewNode(frame: root.frame)
        if !selected { container.addChild(text) }
        root.addChild(container)
        let runtime = RetainedViewRuntime(root: root)
        let effects = HeldTextEffects()
        let source = RuntimeUIAElementTreeSource(
            runtime: runtime,
            screenBoundsMapper: {
                effects.maps += 1
                return $0
            })
        id = try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "held-text" }?.id)
        self.runtime = runtime
        self.container = container
        self.text = text
        self.source = source
        self.effects = effects
        effects.maps = 0
        for node in [root, container, text] {
            node.onLayout = { _ in effects.layouts += 1 }
        }
        text.onActivate = { effects.actions += 1 }
    }

    func assertQuiet(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(effects.maps, 0, file: file, line: line)
        XCTAssertEqual(effects.layouts, 0, file: file, line: line)
        XCTAssertEqual(effects.actions, 0, file: file, line: line)
        XCTAssertNil(runtime.focusedNode, file: file, line: line)
    }
}

private struct HeldTextSurfaceSource: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface
    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class HeldTextCommands: NativeWindowCommandSink {
    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission { .accepted }
}

@MainActor
private struct HeldTextRequestHarness {
    // Local actor ownership/admission only. No context is installed, and these
    // tests do not exercise native dispatch, full-call draining, or COM release.
    let bridge: UIAProviderBridge
    let geometry: NativeWindowGeometry

    init(source: any UIAElementTreeSource) {
        geometry = NativeWindowGeometry(
            revision: 1, nativeSequence: 1, clientSize: IntSize(width: 400, height: 200),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
        let surface = NativeWindowSurface(
            key: NativeWindowKey(), generation: 1,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize), geometry: geometry)
        bridge = UIAProviderBridge(
            source: source, nativeWindowKey: surface.key,
            nativeSnapshotSource: HeldTextSurfaceSource(surface: surface),
            nativeCommandSink: HeldTextCommands(), beforeRequest: { _, _, _ in .success(()) })
    }

    func reply(
        _ request: UIAProviderRequest, isAvailable: @MainActor () -> Bool = { true }
    ) throws -> UIAProviderReply {
        try bridge.replyForNativeRequest(request, geometry: geometry, isAvailable: isAvailable)
    }

    func document(_ id: UInt64) throws -> UIATextDocument? {
        guard case .textDocument(let document) = try reply(.textDocument(element: id)) else {
            XCTFail("Document acquisition must return its distinct internal reply")
            return nil
        }
        return document
    }
}
