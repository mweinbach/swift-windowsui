import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Exercises editor sessions and mounted State together through the real host.
/// Payloads deliberately reenter during retirement; presentation stays fake.
@MainActor
final class EditorStateOwnershipTeardownTests: XCTestCase {
    func testStatePayloadReleaseCannotUndoAClosingPlainBindingEditor() async throws {
        try withTextLayout {
            let document = OwnershipPlainDocument(text: "a")
            let capture = OwnershipBindingCapture<OwnershipReleaseProbe?>()
            let events = OwnershipEvents()
            let fixture = OwnershipHost(
                VStack {
                    OwnershipPlainField(document: document, identifier: "closing.editor")
                    OwnershipPayloadOwner(capture: capture)
                })
            defer { fixture.close() }
            try fixture.focus("closing.editor")
            fixture.type("b")
            let manager = try XCTUnwrap(document.manager)
            XCTAssertTrue(manager.canUndo)

            try installStateReleaseProbe(in: capture, events: events, manager: manager)
            fixture.flush()
            // A read handle would retain the retired payload's snapshot. The
            // mounted registry must be the last owner when close begins.
            capture.binding = nil
            XCTAssertNotNil(events.payload)
            XCTAssertEqual(events.releaseCount, 0)

            fixture.close()

            XCTAssertEqual(events.releaseCount, 1)
            XCTAssertNil(events.payload)
            XCTAssertEqual(document.text, "ab")
            XCTAssertEqual(document.writes, ["ab"])
            XCTAssertEqual(document.editingEvents, [true, false])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testPruningAnExpiredUndoTargetCannotWriteStateDuringWindowClose() async throws {
        try withTextLayout {
            let manager = WinSwiftUI.UndoManager()
            let survivorDocument = OwnershipPlainDocument(text: "s")
            let survivor = OwnershipHost(
                OwnershipPlainField(document: survivorDocument, identifier: "survivor.editor")
                    .environment(\.undoManager, manager))
            defer { survivor.close() }
            try survivor.focus("survivor.editor")
            survivor.type("+")

            let closingDocument = OwnershipPlainDocument(text: "a")
            let capture = OwnershipBindingCapture<Int>()
            let closing = OwnershipHost(
                VStack {
                    OwnershipPlainField(document: closingDocument, identifier: "closing.editor")
                    OwnershipIntOwner(capture: capture, identifier: "closing.state")
                }
                .environment(\.undoManager, manager))
            defer { closing.close() }
            try closing.focus("closing.editor")
            closing.type("b")
            let escaped = try XCTUnwrap(capture.binding)
            let events = OwnershipEvents()
            weak var expiredTarget: OwnershipManualTarget?
            do {
                let target = OwnershipManualTarget()
                expiredTarget = target
                let payload = OwnershipReleaseProbe { [weak events] in
                    events?.releaseCount += 1
                    escaped.wrappedValue = 99
                }
                events.payload = payload
                manager.registerUndo(withTarget: target) { _ in
                    withExtendedLifetime(payload) {}
                }
            }
            XCTAssertNil(expiredTarget)
            XCTAssertNotNil(events.payload)
            XCTAssertEqual(events.releaseCount, 0)
            // Availability queries would prune the expired target before
            // close and would no longer exercise the teardown ordering.

            closing.close()

            XCTAssertEqual(events.releaseCount, 1)
            XCTAssertNil(events.payload)
            XCTAssertEqual(escaped.wrappedValue, 7)
            XCTAssertEqual(closingDocument.text, "ab")
            XCTAssertEqual(closingDocument.writes, ["ab"])
            XCTAssertEqual(survivorDocument.text, "s+")
            manager.undo()
            survivor.flush()
            XCTAssertEqual(survivorDocument.text, "s")
            XCTAssertEqual(closingDocument.text, "ab")
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
        }
    }

    func testEarlierBranchDisappearanceCannotUndoALaterDepartingEditor() async throws {
        try withTextLayout {
            let manager = WinSwiftUI.UndoManager()
            let capture = OwnershipDepartureCapture()
            let events = OwnershipEvents()
            let survivorDocument = OwnershipPlainDocument(text: "s")
            let firstDocument = OwnershipPlainDocument(text: "a")
            let secondDocument = OwnershipPlainDocument(text: "c")
            let fixture = OwnershipHost(
                OwnershipDepartingRoot(
                    capture: capture, events: events, survivor: survivorDocument,
                    first: firstDocument, second: secondDocument
                )
                .environment(\.undoManager, manager))
            defer { fixture.close() }
            try fixture.focus("survivor.editor")
            fixture.type("+")
            try fixture.focus("first.editor")
            fixture.type("b")
            try fixture.focus("second.editor")
            fixture.type("d")
            let firstState = try XCTUnwrap(capture.first.binding)
            let secondState = try XCTUnwrap(capture.second.binding)
            let survivorState = try XCTUnwrap(capture.survivor.binding)
            events.onFirstDisappearance = { [weak manager] in manager?.undo() }
            defer { events.onFirstDisappearance = nil }

            try XCTUnwrap(capture.showsOutgoing.binding).wrappedValue = false
            fixture.flush()

            XCTAssertEqual(events.disappearances, ["first", "second"])
            XCTAssertEqual(firstDocument.text, "ab")
            XCTAssertEqual(firstDocument.writes, ["ab"])
            XCTAssertEqual(secondDocument.text, "cd")
            XCTAssertEqual(secondDocument.writes, ["cd"])
            XCTAssertEqual(survivorDocument.text, "s+", "The blocked outgoing action must not skip to its survivor")
            XCTAssertFalse(fixture.contains("first.editor"))
            XCTAssertFalse(fixture.contains("second.editor"))
            firstState.wrappedValue = 91
            secondState.wrappedValue = 92
            XCTAssertEqual(firstState.wrappedValue, 7)
            XCTAssertEqual(secondState.wrappedValue, 7)
            survivorState.wrappedValue = 8
            fixture.flush()
            XCTAssertEqual(survivorState.wrappedValue, 8)
            XCTAssertEqual(try fixture.node("survivor.state").text, "8")

            manager.undo()
            fixture.flush()

            XCTAssertEqual(survivorDocument.text, "s")
            XCTAssertEqual(firstDocument.text, "ab")
            XCTAssertEqual(secondDocument.text, "cd")
            XCTAssertFalse(manager.canUndo)
            manager.redo()
            fixture.flush()
            XCTAssertEqual(survivorDocument.text, "s+")
            XCTAssertEqual(survivorState.wrappedValue, 8)
        }
    }

    func testDroppingHostRevokesOwnersWithoutDeliveringWindowLifecycleCallbacks() async throws {
        try withTextLayout {
            let manager = WinSwiftUI.UndoManager()
            let survivorDocument = OwnershipPlainDocument(text: "s")
            let survivor = OwnershipHost(
                OwnershipPlainField(document: survivorDocument, identifier: "survivor.editor")
                    .environment(\.undoManager, manager))
            defer { survivor.close() }
            try survivor.focus("survivor.editor")
            survivor.type("+")

            let document = OwnershipPlainDocument(text: "a")
            let capture = OwnershipBindingCapture<Int>()
            let events = OwnershipEvents()
            let content = VStack {
                OwnershipPlainField(document: document, identifier: "released.editor")
                    .onDisappear { events.disappearances.append("released") }
                OwnershipIntOwner(capture: capture, identifier: "released.state")
            }
            .environment(\.undoManager, manager)
            let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 400, height: 240), scaleFactor: 1)
            // Retain the uncreated platform window as well as the runtime;
            // this test drops only the host and never sends windowWillClose.
            let window = Win32Window(title: "Released editor owner", clientSize: surface.pixelSize)
            var host: WinSwiftUIWindowHost? = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Released editor owner", size: surface.pixelSize, clearColor: .black,
                    content: [AnyView(content)]),
                platformWindow: window,
                renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
                surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
            host?.windowDidCreate(window)
            let runtime = try XCTUnwrap(host?.hostedRuntime)
            let editor = try ownershipEditor("released.editor", in: runtime)
            runtime.requestFocus(editor)
            host?.window(window, didInputText: "b")
            host?.windowNeedsDisplay(window)
            let escaped = try XCTUnwrap(capture.binding)
            let focusEvents = document.editingEvents
            host?.onWindowClosed = { [weak events] _ in events?.windowClosedCount += 1 }
            host?.onInputEventRouted = { [weak events] _ in events?.inputEventCount += 1 }
            weak var releasedHost = host
            XCTAssertEqual(document.text, "ab")
            XCTAssertTrue(manager.canUndo)
            XCTAssertNil(window.nativeHandle)

            host = nil

            XCTAssertNil(releasedHost, "A retained runtime and escaped State binding must not keep their host alive")
            escaped.wrappedValue = 99
            XCTAssertEqual(escaped.wrappedValue, 7)
            XCTAssertTrue(events.disappearances.isEmpty)
            XCTAssertEqual(events.windowClosedCount, 0)
            XCTAssertEqual(events.inputEventCount, 0)
            XCTAssertEqual(document.editingEvents, focusEvents)
            XCTAssertNil(window.nativeHandle)
            // The retained tree cannot accept orphaned input or replay its
            // former owner's plain Binding after the host has gone away.
            runtime.imeComposition(IMECompositionEvent(phase: .committed("orphaned")))
            manager.undo()
            survivor.flush()
            XCTAssertEqual(document.text, "ab")
            XCTAssertEqual(document.writes, ["ab"])
            XCTAssertEqual(survivorDocument.text, "s")
            XCTAssertEqual(document.editingEvents, focusEvents)
            XCTAssertFalse(manager.canUndo)
            manager.redo()
            survivor.flush()
            XCTAssertEqual(survivorDocument.text, "s+")
            XCTAssertEqual(document.text, "ab")
            withExtendedLifetime((runtime, window, escaped, manager)) {}
        }
    }

    func testMountedUnicodeTextAndSelectionSurviveRebuildUndoRedoAndActiveIME() async throws {
        try withTextLayout {
            let original = "A👩🏽‍💻e\u{301}Z"
            for control in [OwnershipControl.field, .editor] {
                let record = OwnershipEditorRecord(identifier: "mounted.editor")
                let revision = OwnershipBindingCapture<Int>()
                let fixture = OwnershipHost(
                    OwnershipMountedRoot(
                        record: record, control: control, revisionCapture: revision,
                        seed: original, selection: selection(1..<3, in: original)))
                defer { fixture.close() }
                try fixture.focus(record.identifier)
                let editor = try fixture.editor(record.identifier)
                let text = try XCTUnwrap(record.text)
                let selected = try XCTUnwrap(record.selection)
                let manager = try XCTUnwrap(record.manager)
                fixture.type("🧑‍🚀")
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                try XCTUnwrap(revision.binding).wrappedValue = 1
                fixture.flush()

                fixture.undoKey()

                XCTAssertEqual(text.wrappedValue, original)
                XCTAssertTrue(try fixture.editor(record.identifier) === editor)
                XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
                XCTAssertEqual(editor.textInputCaretOffset, 3)
                XCTAssertEqual(selectionOffsets(selected.wrappedValue, in: text.wrappedValue), 1..<3)
                fixture.redoKey()
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
                XCTAssertEqual(selectionOffsets(selected.wrappedValue, in: text.wrappedValue), 2..<2)

                fixture.compose(.started)
                fixture.compose(.updated("ni"))
                try XCTUnwrap(revision.binding).wrappedValue = 2
                fixture.flush()
                XCTAssertTrue(try fixture.editor(record.identifier) === editor)
                XCTAssertEqual(editor.textInputMarkedText, "ni")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                manager.undo()
                fixture.flush()
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
                XCTAssertTrue(manager.canUndo)
                fixture.compose(.committed("你"))
                manager.undo()
                fixture.flush()
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀你Z")
                XCTAssertEqual(editor.textInputCaretOffset, 3)
                XCTAssertTrue(manager.canUndo, "A mounted commit must stay protected until composition ends")
                fixture.compose(.ended)
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀你Z")
                XCTAssertEqual(editor.textInputCaretOffset, 3)
                XCTAssertNil(editor.textInputMarkedText)

                fixture.undoKey()
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀Z")
                XCTAssertEqual(editor.textInputCaretOffset, 2)
                fixture.undoKey()
                XCTAssertEqual(text.wrappedValue, original)
                XCTAssertEqual(selectionOffsets(selected.wrappedValue, in: text.wrappedValue), 1..<3)
                XCTAssertFalse(manager.canUndo, "Marked-text updates must not add their own history")
                fixture.redoKey()
                fixture.redoKey()
                XCTAssertEqual(text.wrappedValue, "A🧑‍🚀你Z")
                XCTAssertEqual(selectionOffsets(selected.wrappedValue, in: text.wrappedValue), 3..<3)
                XCTAssertFalse(manager.canRedo)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
            }
        }
    }

    func testKeyedMountedEditorsKeepSurvivorHistoryAndRetireRemovedBindingGenerations() async throws {
        try withTextLayout {
            let first = OwnershipEditorRecord(identifier: "first.editor")
            let second = OwnershipEditorRecord(identifier: "second.editor")
            let rows = OwnershipBindingCapture<[String]>()
            let fixture = OwnershipHost(OwnershipKeyedRoot(first: first, second: second, rowsCapture: rows))
            defer { fixture.close() }
            try fixture.focus(second.identifier)
            fixture.type("B")
            try fixture.focus(first.identifier)
            fixture.type("A")
            let firstNode = try fixture.editor(first.identifier)
            let secondNode = try fixture.editor(second.identifier)
            let removedText = try XCTUnwrap(first.text)
            let survivingText = try XCTUnwrap(second.text)
            let rowBinding = try XCTUnwrap(rows.binding)
            let manager = try XCTUnwrap(first.manager)

            rowBinding.wrappedValue = ["second", "first"]
            fixture.flush()

            XCTAssertTrue(try fixture.editor(first.identifier) === firstNode)
            XCTAssertTrue(try fixture.editor(second.identifier) === secondNode)
            XCTAssertTrue(fixture.runtime.focusedNode === firstNode)
            XCTAssertEqual(removedText.wrappedValue, "firstA")
            XCTAssertEqual(survivingText.wrappedValue, "secondB")
            manager.undo()
            fixture.flush()
            XCTAssertEqual(removedText.wrappedValue, "first")
            manager.redo()
            fixture.flush()
            XCTAssertEqual(removedText.wrappedValue, "firstA")

            rowBinding.wrappedValue = ["second"]
            fixture.flush()
            removedText.wrappedValue = "stale write"
            XCTAssertEqual(removedText.wrappedValue, "firstA")
            manager.undo()
            fixture.flush()
            XCTAssertEqual(survivingText.wrappedValue, "second")
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)

            rowBinding.wrappedValue = ["first", "second"]
            fixture.flush()

            XCTAssertFalse(try fixture.editor(first.identifier) === firstNode)
            XCTAssertTrue(try fixture.editor(second.identifier) === secondNode)
            XCTAssertEqual(try XCTUnwrap(first.text).wrappedValue, "first")
            XCTAssertEqual(removedText.wrappedValue, "firstA")
            manager.redo()
            fixture.flush()
            XCTAssertEqual(survivingText.wrappedValue, "secondB")
            XCTAssertEqual(try XCTUnwrap(first.text).wrappedValue, "first")
            manager.undo()
            fixture.flush()
            XCTAssertEqual(survivingText.wrappedValue, "second")
            XCTAssertFalse(manager.canUndo)
        }
    }

    func testUndoAfterQueuedMountedRebuildsUsesTheLatestBindingClosures() async throws {
        try withTextLayout {
            let record = OwnershipEditorRecord(identifier: "queued.editor")
            let revision = OwnershipBindingCapture<Int>()
            let fixture = OwnershipHost(
                OwnershipMountedRoot(
                    record: record, control: .editor, revisionCapture: revision,
                    seed: "abcd", selection: selection(1..<2, in: "abcd")))
            defer { fixture.close() }
            try fixture.focus(record.identifier)
            let editor = try fixture.editor(record.identifier)
            let originalBinding = try XCTUnwrap(record.text)
            let revisionBinding = try XCTUnwrap(revision.binding)
            fixture.type("X")
            XCTAssertEqual(originalBinding.wrappedValue, "aXcd")
            XCTAssertEqual(record.textWriteVersions, [0])
            var completionVersions: [Int] = []
            var guardedCompletions: [Bool] = []
            fixture.host.onReloadContentCompleted = { [weak host = fixture.host] in
                completionVersions.append(record.bodyVersion)
                guardedCompletions.append(host?.hostedRuntime.hasActiveRetainedBuild == true)
                if record.bodyVersion == 1 { revisionBinding.wrappedValue = 2 }
            }
            defer { fixture.host.onReloadContentCompleted = nil }

            revisionBinding.wrappedValue = 1
            fixture.flush()

            XCTAssertEqual(completionVersions, [1, 2])
            XCTAssertEqual(guardedCompletions, [true, true])
            XCTAssertEqual(record.bodyVersion, 2)
            XCTAssertEqual(originalBinding.wrappedValue, "aXcd")
            XCTAssertTrue(try fixture.editor(record.identifier) === editor)
            fixture.host.onReloadContentCompleted = nil
            let selectionWritesBeforeReplay = record.selectionWriteVersions.count

            fixture.undoKey()
            XCTAssertEqual(originalBinding.wrappedValue, "abcd")
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<2))
            fixture.redoKey()

            XCTAssertEqual(originalBinding.wrappedValue, "aXcd")
            XCTAssertEqual(try XCTUnwrap(record.text).wrappedValue, "aXcd")
            XCTAssertEqual(record.textWriteVersions, [0, 2, 2])
            let replaySelectionVersions = record.selectionWriteVersions.dropFirst(selectionWritesBeforeReplay)
            XCTAssertGreaterThanOrEqual(replaySelectionVersions.count, 2)
            XCTAssertTrue(replaySelectionVersions.allSatisfy { $0 == 2 })
            XCTAssertEqual(editor.textInputCaretOffset, 2)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
        }
    }

    func testEarlierDisappearanceCannotReplayALaterEditorsReplacedUndoManager() async throws {
        try withTextLayout {
            for installsReplacement in [false, true] {
                let oldManager = WinSwiftUI.UndoManager()
                let replacement: WinSwiftUI.UndoManager? = installsReplacement ? WinSwiftUI.UndoManager() : nil
                let document = OwnershipPlainDocument(text: "a")
                let switched = OwnershipBindingCapture<Bool>()
                let events = OwnershipEvents()
                let fixture = OwnershipHost(
                    OwnershipManagerSwitchRoot(
                        document: document, switched: switched, oldManager: oldManager,
                        replacementManager: replacement, events: events))
                defer { fixture.close() }
                try fixture.focus("switched.editor")
                fixture.type("b")
                let editor = try fixture.editor("switched.editor")
                XCTAssertTrue(oldManager.canUndo)

                try XCTUnwrap(switched.binding).wrappedValue = true
                fixture.flush()

                XCTAssertEqual(events.disappearances, ["manager-switch"])
                XCTAssertTrue(try fixture.editor("switched.editor") === editor)
                XCTAssertEqual(document.text, "ab")
                XCTAssertEqual(document.writes, ["ab"])
                XCTAssertFalse(oldManager.canUndo)
                XCTAssertFalse(oldManager.canRedo)
                XCTAssertTrue(fixture.runtime.focusedNode === editor)
                fixture.type("c")
                XCTAssertEqual(document.text, "abc")
                if let replacement {
                    XCTAssertTrue(document.manager === replacement)
                    XCTAssertTrue(replacement.canUndo)
                    replacement.undo()
                    fixture.flush()
                    XCTAssertEqual(document.text, "ab")
                    replacement.redo()
                    fixture.flush()
                    XCTAssertEqual(document.text, "abc")
                } else {
                    XCTAssertNil(document.manager)
                    fixture.undoKey()
                    XCTAssertEqual(document.text, "abc")
                }
                XCTAssertFalse(oldManager.canUndo)
                XCTAssertFalse(oldManager.canRedo)
            }
        }
    }

    private func withTextLayout(_ body: () throws -> Void) throws {
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
        try body()
    }

    private func selection(_ range: Range<Int>, in text: String) -> TextSelection {
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return TextSelection(range: lower..<upper)
    }

    private func selectionOffsets(_ selection: TextSelection?, in text: String) -> Range<Int>? {
        guard case .selection(let range) = selection?.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        else { return nil }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        return lower..<upper
    }

    private func installStateReleaseProbe(
        in capture: OwnershipBindingCapture<OwnershipReleaseProbe?>,
        events: OwnershipEvents, manager: WinSwiftUI.UndoManager
    ) throws {
        let binding = try XCTUnwrap(capture.binding)
        let payload = OwnershipReleaseProbe { [weak manager, weak events] in
            events?.releaseCount += 1
            // The session may still have an action while mark-only teardown
            // runs. Its target must reject replay before payloads are purged.
            manager?.undo()
        }
        events.payload = payload
        binding.wrappedValue = payload
    }
}

private enum OwnershipControl {
    case field
    case editor
}

@MainActor
private final class OwnershipReleaseProbe {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class OwnershipManualTarget {}

@MainActor
private final class OwnershipEvents {
    weak var payload: OwnershipReleaseProbe?
    var releaseCount = 0
    var disappearances: [String] = []
    var windowClosedCount = 0
    var inputEventCount = 0
    var onFirstDisappearance: (@MainActor () -> Void)?

    func disappear(_ identifier: String) {
        disappearances.append(identifier)
        if identifier == "first" { onFirstDisappearance?() }
    }
}

@MainActor
private final class OwnershipBindingCapture<Value> {
    var binding: Binding<Value>?
}

@MainActor
private final class OwnershipPlainDocument {
    var text: String
    var writes: [String] = []
    var editingEvents: [Bool] = []
    weak var manager: WinSwiftUI.UndoManager?

    init(text: String) { self.text = text }
}

@MainActor
private struct OwnershipPlainField: View {
    @Environment(\.undoManager) private var manager
    let document: OwnershipPlainDocument
    let identifier: String

    var body: some View {
        document.manager = manager
        // This model deliberately has no mounted-State write guard. Editor
        // lifetime alone must prevent replay during removal and window close.
        let binding = Binding<String>(
            get: { document.text },
            set: {
                document.writes.append($0)
                document.text = $0
            })
        return TextField("Text", text: binding, onEditingChanged: { document.editingEvents.append($0) })
            .accessibilityIdentifier(identifier)
            .frame(width: 320, height: 44)
    }
}

@MainActor
private struct OwnershipPayloadOwner: View {
    @State private var payload: OwnershipReleaseProbe? = nil
    let capture: OwnershipBindingCapture<OwnershipReleaseProbe?>

    var body: some View {
        capture.binding = $payload
        // No escaping body callback captures this owner or its State value.
        return Text(payload == nil ? "Empty payload" : "Owned payload")
    }
}

@MainActor
private struct OwnershipIntOwner: View {
    @State private var value = 7
    let capture: OwnershipBindingCapture<Int>
    let identifier: String

    var body: some View {
        capture.binding = $value
        return Text(String(value)).accessibilityIdentifier(identifier)
    }
}

@MainActor
private final class OwnershipDepartureCapture {
    let showsOutgoing = OwnershipBindingCapture<Bool>()
    let survivor = OwnershipBindingCapture<Int>()
    let first = OwnershipBindingCapture<Int>()
    let second = OwnershipBindingCapture<Int>()
}

@MainActor
private struct OwnershipDepartingRoot: View {
    @State private var showsOutgoing = true
    let capture: OwnershipDepartureCapture
    let events: OwnershipEvents
    let survivor: OwnershipPlainDocument
    let first: OwnershipPlainDocument
    let second: OwnershipPlainDocument

    var body: some View {
        capture.showsOutgoing.binding = $showsOutgoing
        return VStack(alignment: .leading, spacing: 4) {
            OwnershipPlainField(document: survivor, identifier: "survivor.editor")
            OwnershipIntOwner(capture: capture.survivor, identifier: "survivor.state")
            VStack {
                if showsOutgoing {
                    OwnershipDepartingBranch(
                        document: first, capture: capture.first, events: events, identifier: "first")
                }
                Text("Earlier surviving branch")
            }
            VStack {
                if showsOutgoing {
                    OwnershipDepartingBranch(
                        document: second, capture: capture.second, events: events, identifier: "second")
                }
                Text("Later surviving branch")
            }
        }
    }
}

@MainActor
private struct OwnershipDepartingBranch: View {
    let document: OwnershipPlainDocument
    let capture: OwnershipBindingCapture<Int>
    let events: OwnershipEvents
    let identifier: String

    var body: some View {
        VStack {
            OwnershipPlainField(document: document, identifier: "\(identifier).editor")
            OwnershipIntOwner(capture: capture, identifier: "\(identifier).state")
        }
        .onDisappear { events.disappear(identifier) }
    }
}

@MainActor
private struct OwnershipManagerSwitchRoot: View {
    @State private var hasSwitched = false
    let document: OwnershipPlainDocument
    let switched: OwnershipBindingCapture<Bool>
    let oldManager: WinSwiftUI.UndoManager
    let replacementManager: WinSwiftUI.UndoManager?
    let events: OwnershipEvents

    var body: some View {
        switched.binding = $hasSwitched
        return VStack {
            VStack {
                if !hasSwitched {
                    Text("Departing before the editor changes managers")
                        .onDisappear { [oldManager, events] in
                            events.disappearances.append("manager-switch")
                            oldManager.undo()
                        }
                }
                Text("Earlier surviving branch")
            }
            OwnershipPlainField(document: document, identifier: "switched.editor")
                .environment(\.undoManager, hasSwitched ? replacementManager : oldManager)
                .id("same-editor")
        }
    }
}

@MainActor
private final class OwnershipEditorRecord {
    let identifier: String
    var text: Binding<String>?
    var selection: Binding<TextSelection?>?
    weak var manager: WinSwiftUI.UndoManager?
    var bodyVersion = 0
    var textWriteVersions: [Int] = []
    var selectionWriteVersions: [Int] = []

    init(identifier: String) { self.identifier = identifier }
}

@MainActor
private struct OwnershipMountedEditor: View {
    @Environment(\.undoManager) private var manager
    @State private var text: String
    @State private var selection: TextSelection?
    let record: OwnershipEditorRecord
    let control: OwnershipControl
    let version: Int

    init(
        record: OwnershipEditorRecord, control: OwnershipControl,
        seed: String, selection: TextSelection? = nil, version: Int = 0
    ) {
        self.record = record
        self.control = control
        self.version = version
        _text = State(initialValue: seed)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let mountedText = $text
        let mountedSelection = $selection
        record.text = mountedText
        record.selection = mountedSelection
        record.manager = manager
        record.bodyVersion = version
        let textBinding = Binding<String>(
            get: { mountedText.wrappedValue },
            set: {
                record.textWriteVersions.append(version)
                mountedText.wrappedValue = $0
            })
        let selectionBinding = Binding<TextSelection?>(
            get: { mountedSelection.wrappedValue },
            set: {
                record.selectionWriteVersions.append(version)
                mountedSelection.wrappedValue = $0
            })
        let input: AnyView
        switch control {
        case .field:
            input = AnyView(TextField("Text", text: textBinding, selection: selectionBinding))
        case .editor:
            input = AnyView(TextEditor(text: textBinding, selection: selectionBinding))
        }
        return input.accessibilityIdentifier(record.identifier).frame(width: 320, height: 96)
    }
}

@MainActor
private struct OwnershipMountedRoot: View {
    @State private var revision = 0
    let record: OwnershipEditorRecord
    let control: OwnershipControl
    let revisionCapture: OwnershipBindingCapture<Int>
    let seed: String
    let selection: TextSelection?

    var body: some View {
        revisionCapture.binding = $revision
        return VStack {
            Text("Revision \(revision)")
            OwnershipMountedEditor(
                record: record, control: control, seed: seed, selection: selection, version: revision)
        }
    }
}

@MainActor
private struct OwnershipKeyedRoot: View {
    @State private var rows = ["first", "second"]
    let first: OwnershipEditorRecord
    let second: OwnershipEditorRecord
    let rowsCapture: OwnershipBindingCapture<[String]>

    var body: some View {
        rowsCapture.binding = $rows
        return VStack {
            ForEach(rows, id: \.self) { row in
                OwnershipMountedEditor(
                    record: row == "first" ? first : second, control: .editor, seed: row)
            }
        }
    }
}

@MainActor
private func ownershipNodes(in root: ViewNode) -> [ViewNode] {
    var result: [ViewNode] = []
    var pending = [root]
    while let node = pending.popLast() {
        result.append(node)
        pending.append(contentsOf: node.children.reversed())
    }
    return result
}

@MainActor
private func ownershipEditor(_ identifier: String, in runtime: RetainedViewRuntime) throws -> ViewNode {
    try XCTUnwrap(
        ownershipNodes(in: runtime.root).first {
            $0.accessibilityIdentifier == identifier && $0.accessibilityTraits.contains(.isTextInput)
        })
}

@MainActor
private final class OwnershipHost {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 640, height: 640), scaleFactor: 1)
        let window = Win32Window(title: "Editor and State ownership", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Editor and State ownership", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.clock = clock
        self.window = window
        self.host = host
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
            _ = runtime.renderScene(at: clock.now)
        }
    }

    func close() { host.windowWillClose(window) }

    func contains(_ identifier: String) -> Bool {
        ownershipNodes(in: runtime.root).contains { $0.accessibilityIdentifier == identifier }
    }

    func node(_ identifier: String) throws -> ViewNode {
        try XCTUnwrap(ownershipNodes(in: runtime.root).first { $0.accessibilityIdentifier == identifier })
    }

    func editor(_ identifier: String) throws -> ViewNode {
        try ownershipEditor(identifier, in: runtime)
    }

    func focus(_ identifier: String) throws {
        runtime.requestFocus(try editor(identifier))
        flush()
    }

    func type(_ text: String) {
        host.window(window, didInputText: text)
        flush()
    }

    func compose(_ phase: IMECompositionEvent.Phase) {
        host.window(window, imeComposition: IMECompositionEvent(phase: phase))
        flush()
    }

    func undoKey() { shortcut(0x5A) }
    func redoKey() { shortcut(0x59) }

    private func shortcut(_ code: UInt32) {
        host.window(
            window,
            keyDown: KeyboardEvent(keyCode: code, modifiers: [.control], textInputDelivery: .systemCharacter))
        flush()
    }
}
