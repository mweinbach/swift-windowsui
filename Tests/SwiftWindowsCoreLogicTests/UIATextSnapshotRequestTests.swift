import CUIAInterop
import Synchronization
import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

private struct TextRequestSurfaceSource: NativeWindowSnapshotSource {
    let surface: NativeWindowSurface

    func snapshot() -> Result<NativeWindowSurface, NativeWindowOwnerFailure> { .success(surface) }
}

private final class TextRequestCommands: NativeWindowCommandSink {
    private let submissions = Mutex<Int>(0)

    var count: Int { submissions.withLock { $0 } }

    func submit(_ command: any NativeWindowOwnerCommand) -> NativeWindowSubmission {
        submissions.withLock { $0 += 1 }
        return .accepted
    }
}

/// Uses the actor resolver with copied geometry. No attachment factory, HWND,
/// COM provider, native request transport, or render/layout pass is created.
@MainActor
private struct TextRequestHarness {
    let bridge: UIAProviderBridge
    let geometry: NativeWindowGeometry
    let commands: TextRequestCommands

    init(source: any UIAElementTreeSource) {
        geometry = NativeWindowGeometry(
            revision: 1, nativeSequence: 1, clientSize: IntSize(width: 400, height: 200),
            clientScreenOrigin: .zero, scaleFactor: 1, effectiveScaleFactor: 1,
            monitorRefreshRate: 60, isMinimized: false, isVisible: true, isActive: true)
        let surface = NativeWindowSurface(
            key: NativeWindowKey(), generation: 1,
            descriptor: SurfaceDescriptor(offscreenPixelSize: geometry.clientSize), geometry: geometry)
        let commands = TextRequestCommands()
        self.commands = commands
        bridge = UIAProviderBridge(
            source: source, nativeWindowKey: surface.key,
            nativeSnapshotSource: TextRequestSurfaceSource(surface: surface),
            nativeCommandSink: commands, beforeRequest: { _, _, _ in .success(()) })
    }

    func reply(
        _ request: UIAProviderRequest, isAvailable: @MainActor () -> Bool = { true }
    ) throws -> UIAProviderReply {
        try bridge.replyForNativeRequest(request, geometry: geometry, isAvailable: isAvailable)
    }

    func text(
        _ id: UInt64, isAvailable: @MainActor () -> Bool = { true }
    ) throws -> String? {
        let reply = try reply(.textContent(element: id), isAvailable: isAvailable)
        guard case .string(let value) = reply else {
            XCTFail("A text-content request must use the existing string reply")
            return nil
        }
        return value
    }
}

@MainActor
private final class TextReadEffects {
    var maps = 0
    var layouts = 0
    var actions = 0
    var focus = 0
    var refreshes = 0
    var textGets = 0
    var textSets = 0
    var selectionGets = 0
    var selectionSets = 0
}

@MainActor
private final class PlainTextReadFixture {
    let runtime: RetainedViewRuntime
    let container: ViewNode
    let text: ViewNode
    let source: RuntimeUIAElementTreeSource
    let effects: TextReadEffects
    let id: UInt64

    init(_ content: String = "Stored document") throws {
        let effects = TextReadEffects()
        self.effects = effects
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
        root.resolvedFrame = root.frame
        runtime = RetainedViewRuntime(root: root)
        container = ViewNode(frame: root.frame)
        container.resolvedFrame = container.frame
        root.addChild(container)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 200) },
            invalidateHandler: { effects.refreshes += 1 })
        text = Text(verbatim: content).makeComponent(context: context).makeNode(runtime: runtime)
        text.frame = Rect(x: 10, y: 10, width: 200, height: 20)
        text.resolvedFrame = text.frame
        text.accessibilityIdentifier = "plain-document"
        container.addChild(text)
        source = RuntimeUIAElementTreeSource(
            runtime: runtime,
            screenBoundsMapper: {
                effects.maps += 1
                return $0
            })
        id = try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "plain-document" }?.id)
        effects.maps = 0
        effects.refreshes = 0
    }
}

@MainActor
private class MetadataOnlyTextSource: UIAElementTreeSource {
    var legacyReads = 0
    var geometryReads = 0
    var actions: [String] = []
    var element = UIAElementSnapshot(
        id: 0, parentID: nil, name: "Accessible name", value: "Accessible value",
        controlType: Int32(SWU_UIA_CONTROL_TYPE_EDIT), bounds: Rect(x: 0, y: 0, width: 100, height: 40),
        isEnabled: true, hasKeyboardFocus: false, isKeyboardFocusable: true, hasDefaultAction: true,
        supportsValue: true, isReadOnly: false, toggleState: .off, isSelected: true,
        supportsSelection: true, isVirtualizedPlaceholder: true, supportsItemContainer: true)

    func uiaElementSnapshots() -> [UIAElementSnapshot] {
        legacyReads += 1
        return [element]
    }

    func uiaElementSnapshots(geometry: NativeWindowGeometry) -> [UIAElementSnapshot] {
        geometryReads += 1
        return [element]
    }

    func uiaInvokeDefaultAction(elementID: UInt64) -> Bool {
        actions.append("invoke")
        return true
    }
    func uiaSetFocus(elementID: UInt64) { actions.append("focus") }
    func uiaSetValue(elementID: UInt64, value: String) -> Bool {
        actions.append("value")
        return true
    }
    func uiaToggle(elementID: UInt64) -> Bool {
        actions.append("toggle")
        return true
    }
    func uiaSelect(elementID: UInt64) -> Bool {
        actions.append("select")
        return true
    }
    func uiaAddToSelection(elementID: UInt64) -> Bool {
        actions.append("add")
        return true
    }
    func uiaRemoveFromSelection(elementID: UInt64) -> Bool {
        actions.append("remove")
        return true
    }
    func uiaRealizeVirtualizedItem(elementID: UInt64) -> Bool {
        actions.append("realize")
        return true
    }
}

@MainActor
private final class OptionalTextSource: MetadataOnlyTextSource, UIATextSnapshotSource {
    var document: String? = "Snapshot content"
    var textReads = 0
    var onCapture: (() -> Void)?

    func uiaTextSnapshot(elementID: UInt64) -> TextRangeSnapshot? {
        textReads += 1
        let result = document.flatMap { TextRangeSnapshot($0) }
        onCapture?()
        return result
    }
}

@MainActor
final class UIATextSnapshotRequestTests: XCTestCase {
    private enum InputKind { case field, editor, secure }

    private func input(
        _ kind: InputKind, value: String, enabled: Bool = true,
        runtime: RetainedViewRuntime, effects: TextReadEffects
    ) -> ViewNode {
        let binding = Binding<String>(
            get: {
                effects.textGets += 1
                return value
            },
            set: { _ in effects.textSets += 1 })
        let selection = Binding<TextSelection?>(
            get: {
                effects.selectionGets += 1
                return nil
            },
            set: { _ in effects.selectionSets += 1 })
        let view: AnyView
        switch kind {
        case .field:
            view = AnyView(TextField("Placeholder", text: binding, selection: selection))
        case .editor:
            view = AnyView(TextEditor(text: binding, selection: selection))
        case .secure:
            view = AnyView(SecureField("Password", text: binding))
        }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 200) },
            invalidateHandler: { effects.refreshes += 1 })
        return view.makeComponent(context: context.withEnabled(enabled)).makeNode(runtime: runtime)
    }

    private func id(
        of node: ViewNode, named name: String, in source: RuntimeUIAElementTreeSource
    ) throws -> UInt64 {
        node.accessibilityIdentifier = name
        return try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == name }?.id)
    }

    private func resetInputEffects(_ effects: TextReadEffects) {
        effects.textGets = 0
        effects.textSets = 0
        effects.selectionGets = 0
        effects.selectionSets = 0
        effects.refreshes = 0
    }

    private func assertNoInputEffects(_ effects: TextReadEffects) {
        XCTAssertEqual(effects.textGets, 0)
        XCTAssertEqual(effects.textSets, 0)
        XCTAssertEqual(effects.selectionGets, 0)
        XCTAssertEqual(effects.selectionSets, 0)
        XCTAssertEqual(effects.refreshes, 0)
    }

    func testStoredTextSnapshotAndRequestPreserveExactUnicode() async throws {
        let original = "e\u{301}|👩🏽‍💻|אבג\r\n\0tail"
        let fixture = try PlainTextReadFixture(original)
        let snapshot = try XCTUnwrap(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        XCTAssertEqual(Array(snapshot.text.utf16), Array(original.utf16))
        XCTAssertEqual(snapshot.utf16Count, original.utf16.count)
        XCTAssertEqual(snapshot.characterCount, original.count)
        XCTAssertEqual(
            Array(try snapshot.getText(in: snapshot.documentRange).utf16), Array(original.utf16))
        let harness = TextRequestHarness(source: fixture.source)
        let reply = try XCTUnwrap(harness.text(fixture.id))
        XCTAssertEqual(Array(reply.utf16), Array(original.utf16))
        XCTAssertEqual(harness.commands.count, 0)
    }

    func testEmptyTextIsDistinctFromAbsentAndMissingCapability() async throws {
        let fixture = try PlainTextReadFixture("")
        let snapshot = try XCTUnwrap(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        XCTAssertEqual(snapshot.text, "")
        XCTAssertEqual(snapshot.documentRange.characterRange, 0..<0)
        let harness = TextRequestHarness(source: fixture.source)
        XCTAssertEqual(try harness.reply(.textContent(element: fixture.id)), .string(""))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: UInt64.max))
        XCTAssertEqual(try harness.reply(.textContent(element: UInt64.max)), .string(nil))
        let metadata = MetadataOnlyTextSource()
        let unsupported = TextRequestHarness(source: metadata)
        XCTAssertEqual(try unsupported.reply(.textContent(element: 0)), .string(nil))
        XCTAssertEqual(metadata.legacyReads, 0)
        XCTAssertEqual(metadata.geometryReads, 0)
        XCTAssertTrue(metadata.actions.isEmpty)
    }

    func testDocumentNeverFallsBackToAccessibleMetadata() async throws {
        let fixture = try PlainTextReadFixture("Stored text")
        fixture.text.accessibilityLabel = "Different spoken label"
        fixture.text.accessibilityValue = "Different accessible value"
        let metadata = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.id == fixture.id })
        XCTAssertEqual(metadata.name, "Different spoken label")
        XCTAssertEqual(metadata.value, "Different accessible value")
        let harness = TextRequestHarness(source: fixture.source)
        XCTAssertEqual(try harness.text(fixture.id), "Stored text")
        fixture.text.text = nil
        fixture.text.accessibilityTraits = .isStaticText
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        XCTAssertNil(try harness.text(fixture.id))
        fixture.text.text = "Stored again"
        fixture.text.accessibilityTraits = .isButton
        XCTAssertNil(try harness.text(fixture.id))
    }

    func testDisabledAndOrdinaryOffscreenTextRemainReadable() async throws {
        let fixture = try PlainTextReadFixture()
        fixture.container.accessibilityRespondsToUserInteraction = false
        fixture.text.accessibilityRespondsToUserInteraction = false
        fixture.text.frame = Rect(x: 10, y: 1000, width: 200, height: 20)
        fixture.text.resolvedFrame = fixture.text.frame
        let metadata = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.id == fixture.id })
        XCTAssertFalse(metadata.isEnabled)
        XCTAssertEqual(metadata.isOffscreen, true)
        XCTAssertFalse(metadata.isVirtualizedPlaceholder)
        let effects = fixture.effects
        fixture.text.onFocusEnter = { effects.focus += 1 }
        let scroll = fixture.container.scrollOffset
        XCTAssertEqual(fixture.source.uiaTextSnapshot(elementID: fixture.id)?.text, "Stored document")
        XCTAssertEqual(try TextRequestHarness(source: fixture.source).text(fixture.id), "Stored document")
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.container.scrollOffset, scroll)
        XCTAssertEqual(fixture.effects.focus, 0)
    }

    func testCopiesStayImmutableAcrossStoredTextChanges() async throws {
        let first = "e\u{301}\0first"
        let second = "\u{e9}\0second"
        let fixture = try PlainTextReadFixture(first)
        let harness = TextRequestHarness(source: fixture.source)
        let oldSnapshot = try XCTUnwrap(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        let oldReply = try XCTUnwrap(harness.text(fixture.id))
        fixture.text.text = second
        let newSnapshot = try XCTUnwrap(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        let newReply = try XCTUnwrap(harness.text(fixture.id))
        XCTAssertEqual(Array(oldSnapshot.text.utf16), Array(first.utf16))
        XCTAssertEqual(Array(oldReply.utf16), Array(first.utf16))
        XCTAssertEqual(Array(newSnapshot.text.utf16), Array(second.utf16))
        XCTAssertEqual(Array(newReply.utf16), Array(second.utf16))
        fixture.text.text = "e\u{301}"
        let decomposed = try XCTUnwrap(harness.text(fixture.id))
        fixture.text.text = "\u{e9}"
        let composed = try XCTUnwrap(harness.text(fixture.id))
        XCTAssertNotEqual(Array(decomposed.utf16), Array(composed.utf16))
    }

    func testSnapshotsAndRepliesDoNotKeepRuntimeOrNodesAlive() async throws {
        @MainActor func makeRuntime() -> RetainedViewRuntime {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 200))
            root.resolvedFrame = root.frame
            root.addChild(ViewNode(text: "Owned only by runtime"))
            return RetainedViewRuntime(root: root)
        }
        var owner: RetainedViewRuntime? = makeRuntime()
        weak var releasedRuntime = owner
        weak var releasedRoot = owner?.root
        weak var releasedText = owner?.root.children.first
        let source = RuntimeUIAElementTreeSource(runtime: try XCTUnwrap(owner))
        let harness = TextRequestHarness(source: source)
        let knownID = try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Owned only by runtime" }?.id)
        let copy = try XCTUnwrap(source.uiaTextSnapshot(elementID: knownID))
        let reply = try harness.reply(.textContent(element: knownID))
        owner = nil
        withExtendedLifetime((source, harness, copy, reply)) {
            XCTAssertNil(releasedRuntime)
            XCTAssertNil(releasedRoot)
            XCTAssertNil(releasedText)
            XCTAssertEqual(copy.text, "Owned only by runtime")
            XCTAssertEqual(reply, .string("Owned only by runtime"))
            XCTAssertNil(source.uiaTextSnapshot(elementID: knownID))
        }
        XCTAssertNil(try harness.text(knownID))

        let fixture = try PlainTextReadFixture()
        var removed: ViewNode? = ViewNode(text: "Temporary")
        weak var dead = removed
        fixture.runtime.root.addChild(try XCTUnwrap(removed))
        let removedID = try id(of: XCTUnwrap(removed), named: "removed", in: fixture.source)
        fixture.runtime.root.removeChild(try XCTUnwrap(removed))
        removed = nil
        XCTAssertNil(dead)
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: removedID))
    }

    func testTextFieldsAndEditorsDoNotReadBindingsOrSelections() async throws {
        for kind in [InputKind.field, .editor] {
            for enabled in [true, false] {
                let fixture = try PlainTextReadFixture()
                let effects = TextReadEffects()
                let node = input(
                    kind, value: "Bound secret", enabled: enabled, runtime: fixture.runtime, effects: effects)
                // AX read-only is authored separately; context.withEnabled does not set it.
                node.accessibilityRespondsToUserInteraction = enabled
                fixture.runtime.root.addChild(node)
                XCTAssertNotNil(node.textInputController)
                let knownID = try id(of: node, named: "editor", in: fixture.source)
                let metadata = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.id == knownID })
                XCTAssertEqual(metadata.isReadOnly, !enabled)
                resetInputEffects(effects)
                XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: knownID))
                XCTAssertNil(try TextRequestHarness(source: fixture.source).text(knownID))
                assertNoInputEffects(effects)
            }
        }
    }

    func testSecureControllerAncestryIsDeniedAfterExposedTraitsChange() async throws {
        let fixture = try PlainTextReadFixture()
        let effects = TextReadEffects()
        let secure = input(.secure, value: "secret", runtime: fixture.runtime, effects: effects)
        fixture.runtime.root.addChild(secure)
        let ownerID = try id(of: secure, named: "secure-owner", in: fixture.source)
        let fragment = try XCTUnwrap(secure.children.first { $0.text != nil })
        let fragmentID = try id(of: fragment, named: "secure-fragment", in: fixture.source)
        let metadata = try XCTUnwrap(fixture.source.uiaElementSnapshots().first { $0.id == ownerID })
        XCTAssertTrue(metadata.isPassword)
        XCTAssertFalse(metadata.supportsValue)
        resetInputEffects(effects)
        let harness = TextRequestHarness(source: fixture.source)
        XCTAssertNil(try harness.text(ownerID))
        XCTAssertNil(try harness.text(fragmentID))
        secure.accessibilityTraits = []
        secure.text = "Do not expose owner text"
        fragment.accessibilityTraits = .isStaticText
        fragment.text = "Do not expose a controller-owned fragment"
        XCTAssertNotNil(secure.textInputController)
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: ownerID))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: fragmentID))
        XCTAssertNil(try harness.text(fragmentID))
        assertNoInputEffects(effects)
    }

    func testPlaceholderAndMarkedDisplayFragmentsAreNotDocuments() async throws {
        let fixture = try PlainTextReadFixture()
        let effects = TextReadEffects()
        let field = input(.field, value: "", runtime: fixture.runtime, effects: effects)
        fixture.runtime.root.addChild(field)
        let placeholder = try XCTUnwrap(field.children.first { $0.text == "Placeholder" })
        let placeholderID = try id(of: placeholder, named: "placeholder", in: fixture.source)
        let editor = input(.editor, value: "authored", runtime: fixture.runtime, effects: effects)
        fixture.runtime.root.addChild(editor)
        let marked = ViewNode(text: "marked display only")
        let viewport = try XCTUnwrap(editor.children.first)
        viewport.addChild(marked)
        editor.textInputMarkedText = "marked display only"
        let markedID = try id(of: marked, named: "marked", in: fixture.source)
        resetInputEffects(effects)
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: placeholderID))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: markedID))
        let harness = TextRequestHarness(source: fixture.source)
        XCTAssertNil(try harness.text(placeholderID))
        XCTAssertNil(try harness.text(markedID))
        assertNoInputEffects(effects)
        // This is retained display-state refusal, not native IME qualification.
    }

    func testHiddenRemovedDeferredPrivateAndRedactedAncestryIsDenied() async throws {
        let policies: [(String, (ViewNode) -> Void)] = [
            ("hidden", { $0.isHidden = true }),
            ("accessibility hidden", { $0.isAccessibilityHidden = true }),
            ("removal", { $0.isRemovalOverlay = true }),
            ("deferred", { $0.isLayoutDeferredByVirtualization = true }),
            ("private", { $0.isPrivacySensitive = true }),
            ("placeholder redaction", { $0.redactionReasons = .placeholder }),
            ("unknown redaction", { $0.redactionReasons = RetainedRedactionReasons(rawValue: 1 << 17) }),
            ("secure trait", { $0.accessibilityTraits.insert(.isSecureTextInput) }),
            ("editor trait", { $0.accessibilityTraits.insert(.isTextInput) }),
            ("search trait", { $0.accessibilityTraits.insert(.isSearchField) }),
        ]
        for (name, deny) in policies {
            for onAncestor in [false, true] {
                let fixture = try PlainTextReadFixture()
                XCTAssertNotNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
                deny(onAncestor ? fixture.container : fixture.text)
                XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: fixture.id), name)
                XCTAssertNil(try TextRequestHarness(source: fixture.source).text(fixture.id), name)
            }
        }
        let stopped = try PlainTextReadFixture()
        stopped.runtime.stopRenderLifecycleCallbacks()
        XCTAssertNil(stopped.source.uiaTextSnapshot(elementID: stopped.id))
    }

    func testCombinedIgnoredSyntheticAndLogicalNodesHaveNoDocument() async throws {
        for behavior in [RetainedAccessibilityChildBehavior.combine, .ignore] {
            let fixture = try PlainTextReadFixture()
            XCTAssertNotNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
            fixture.container.accessibilityChildBehavior = behavior
            XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        }
        let synthetic = try PlainTextReadFixture()
        let representation = ViewNode(text: "Representation only")
        representation.accessibilityIdentifier = "synthetic"
        synthetic.container.accessibilityRepresentationChildren = [representation]
        let syntheticID = try XCTUnwrap(
            synthetic.source.uiaElementSnapshots().first { $0.automationID == "synthetic" }?.id)
        XCTAssertNil(synthetic.runtime.accessibilityTarget(for: representation))
        XCTAssertNil(synthetic.source.uiaTextSnapshot(elementID: syntheticID))
        XCTAssertNil(synthetic.source.uiaTextSnapshot(elementID: synthetic.id))

        let lazy = try PlainTextReadFixture()
        XCTAssertNotNil(lazy.source.uiaTextSnapshot(elementID: lazy.id))
        var factories = 0
        let data = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            data.replaceData([0], id: \.self) { _ in
                factories += 1
                return [ViewNode(text: "Unconstructed logical row")]
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: data, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        lazy.container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(lazy.container))
        XCTAssertEqual(factories, 0)
        XCTAssertNil(lazy.source.uiaTextSnapshot(elementID: lazy.id))
        XCTAssertNil(lazy.source.uiaTextSnapshot(elementID: UInt64(1) << 63))
        XCTAssertNil(try TextRequestHarness(source: lazy.source).text(lazy.id))
        XCTAssertEqual(factories, 0)
        // Physical adapter ancestry and an unknown logical ID are separate
        // negatives; this does not claim a realized logical-row receipt.
    }

    func testOriginalReadWitnessFailsAcrossReattachmentAndRuntimeMoves() async throws {
        let fixture = try PlainTextReadFixture()
        let original = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.text))
        XCTAssertTrue(fixture.runtime.isAccessibilityTextReadTargetCurrent(original))
        fixture.container.removeChild(fixture.text)
        fixture.container.addChild(fixture.text)
        XCTAssertFalse(fixture.runtime.isAccessibilityTextReadTargetCurrent(original))
        let fresh = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.text))
        XCTAssertTrue(fixture.runtime.isAccessibilityTextReadTargetCurrent(fresh))
        XCTAssertEqual(fixture.source.uiaTextSnapshot(elementID: fixture.id)?.text, "Stored document")
        let other = RetainedViewRuntime(root: ViewNode())
        fixture.container.removeChild(fixture.text)
        other.root.addChild(fixture.text)
        XCTAssertFalse(fixture.runtime.isAccessibilityTextReadTargetCurrent(original))
        XCTAssertFalse(fixture.runtime.isAccessibilityTextReadTargetCurrent(fresh))
        XCTAssertFalse(other.isAccessibilityTextReadTargetCurrent(original))
        XCTAssertFalse(other.isAccessibilityTextReadTargetCurrent(fresh))
        let moved = try XCTUnwrap(other.accessibilityTarget(for: fixture.text))
        XCTAssertTrue(other.isAccessibilityTextReadTargetCurrent(moved))
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        // The production helper's release-before-recheck ordering is reviewed
        // in source. This primitive test establishes no held-range lifetime.
    }

    func testPhysicalModalBlocksBackgroundBeforePrepaintWithoutLayout() async throws {
        let fixture = try PlainTextReadFixture()
        let modal = ViewNode()
        let enclosed = ViewNode(text: "Inside modal")
        modal.addChild(enclosed)
        fixture.runtime.root.addChild(modal)
        let enclosedID = try id(of: enclosed, named: "enclosed", in: fixture.source)
        XCTAssertNotNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        XCTAssertNotNil(fixture.source.uiaTextSnapshot(elementID: enclosedID))
        let effects = fixture.effects
        fixture.runtime.root.onLayout = { _ in effects.layouts += 1 }
        modal.onLayout = { _ in effects.layouts += 1 }
        let maps = effects.maps
        XCTAssertNil(fixture.runtime.activeModalPresentationNode)
        modal.accessibilityTraits.insert(.isModal)
        XCTAssertNil(fixture.runtime.activeModalPresentationNode)
        XCTAssertNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        XCTAssertEqual(fixture.source.uiaTextSnapshot(elementID: enclosedID)?.text, "Inside modal")
        let harness = TextRequestHarness(source: fixture.source)
        XCTAssertNil(try harness.text(fixture.id))
        XCTAssertEqual(try harness.text(enclosedID), "Inside modal")
        XCTAssertEqual(effects.layouts, 0)
        XCTAssertEqual(effects.maps, maps)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(harness.commands.count, 0)
    }

    func testAvailabilityChecksBracketOneOptionalSourceCapture() async throws {
        let source = OptionalTextSource()
        let harness = TextRequestHarness(source: source)
        var available = false
        XCTAssertNil(try harness.text(0, isAvailable: { available }))
        XCTAssertEqual(source.textReads, 0)
        available = true
        source.onCapture = { available = false }
        XCTAssertNil(try harness.text(0, isAvailable: { available }))
        XCTAssertEqual(source.textReads, 1)
        source.onCapture = nil
        available = true
        XCTAssertEqual(try harness.text(0, isAvailable: { available }), "Snapshot content")
        XCTAssertEqual(source.textReads, 2)
        XCTAssertEqual(source.geometryReads, 0)
        XCTAssertEqual(source.legacyReads, 0)
        XCTAssertTrue(source.actions.isEmpty)
        // Fake-source revocation is resolver admission evidence only.
    }

    func testTextCaptureDoesNotRunQueriesActionsFocusLayoutOrRealization() async throws {
        let source = OptionalTextSource()
        let harness = TextRequestHarness(source: source)
        XCTAssertEqual(try harness.text(0), "Snapshot content")
        XCTAssertEqual(try harness.text(0), "Snapshot content")
        XCTAssertEqual(source.textReads, 2)
        XCTAssertEqual(source.geometryReads, 0)
        XCTAssertEqual(source.legacyReads, 0)
        XCTAssertEqual(
            try harness.reply(.stringProperty(element: 0, property: Int32(SWU_UIA_STRING_NAME))),
            .string("Accessible name"))
        XCTAssertEqual(
            try harness.reply(.supportsPattern(element: 0, pattern: Int32(SWU_UIA_PATTERN_VALUE))), .integer(1))
        XCTAssertEqual(source.geometryReads, 2)
        XCTAssertEqual(source.legacyReads, 0)
        XCTAssertEqual(source.textReads, 2)
        XCTAssertTrue(source.actions.isEmpty)

        let fixture = try PlainTextReadFixture()
        let effects = fixture.effects
        fixture.text.isFocusable = true
        fixture.text.onActivate = { effects.actions += 1 }
        fixture.text.onFocusEnter = { effects.focus += 1 }
        fixture.text.onLayout = { _ in effects.layouts += 1 }
        fixture.text.textInputSelection = RetainedTextSelection(indices: .range(0..<1))
        let retainedSelection = fixture.text.textInputSelection
        let scroll = fixture.container.scrollOffset
        let maps = effects.maps
        let runtimeHarness = TextRequestHarness(source: fixture.source)
        XCTAssertNotNil(fixture.source.uiaTextSnapshot(elementID: fixture.id))
        XCTAssertEqual(try runtimeHarness.text(fixture.id), "Stored document")
        XCTAssertEqual(effects.maps, maps)
        XCTAssertEqual(effects.layouts, 0)
        XCTAssertEqual(effects.actions, 0)
        XCTAssertEqual(effects.focus, 0)
        XCTAssertEqual(effects.refreshes, 0)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.text.textInputSelection, retainedSelection)
        XCTAssertEqual(fixture.container.scrollOffset, scroll)
        XCTAssertEqual(harness.commands.count, 0)
        XCTAssertEqual(runtimeHarness.commands.count, 0)
    }

    func testAddingTextRequestDoesNotAdvertiseTextPatternOrChangeExistingPatterns() async throws {
        let source = OptionalTextSource()
        let harness = TextRequestHarness(source: source)
        let existing: [Int32] = [
            Int32(SWU_UIA_PATTERN_VALUE), Int32(SWU_UIA_PATTERN_TOGGLE),
            Int32(SWU_UIA_PATTERN_SELECTION), Int32(SWU_UIA_PATTERN_SELECTION_ITEM),
            Int32(SWU_UIA_PATTERN_VIRTUALIZED_ITEM), Int32(SWU_UIA_PATTERN_ITEM_CONTAINER),
        ]
        let before = try existing.map { try harness.reply(.supportsPattern(element: 0, pattern: $0)) }
        XCTAssertEqual(before, Array(repeating: .integer(1), count: existing.count))
        XCTAssertEqual(try harness.text(0), "Snapshot content")
        let after = try existing.map { try harness.reply(.supportsPattern(element: 0, pattern: $0)) }
        XCTAssertEqual(after, before)
        // Microsoft Control Pattern Identifiers: Text, Text2, TextChild, TextEdit.
        // These test query discovery only. C/COM advertisement is separately
        // protected by byte preservation, not exercised by this value test.
        let unsupported: [Int32] = [10014, 10024, 10029, 10032, Int32.max]
        for pattern in unsupported {
            XCTAssertEqual(try harness.reply(.supportsPattern(element: 0, pattern: pattern)), .integer(0))
        }
        let fixture = try PlainTextReadFixture()
        let plain = TextRequestHarness(source: fixture.source)
        XCTAssertEqual(
            try plain.reply(.supportsPattern(element: fixture.id, pattern: Int32(SWU_UIA_PATTERN_VALUE))),
            .integer(0))
        XCTAssertEqual(try plain.reply(.supportsPattern(element: fixture.id, pattern: 10014)), .integer(0))
        XCTAssertEqual(source.textReads, 1)
        XCTAssertEqual(harness.commands.count, 0)
    }
}
