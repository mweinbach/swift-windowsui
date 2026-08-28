import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ItemSheetStateIdentityTests: XCTestCase {
    func testChangedItemIDsRetireStateWhileSameIDPayloadUpdatesPreserveIt() async throws {
        try withTextLayout {
            let model = ItemSheetStateModel()
            let firstID = ItemSheetStateID(value: 1)
            let secondID = ItemSheetStateID(value: 2)
            XCTAssertNotEqual(firstID, secondID)
            XCTAssertEqual(firstID.description, secondID.description, "Identity must not use a string description")
            model.item = ItemSheetStateItem(id: firstID, title: "First", seed: 10)
            let fixture = ItemSheetStateHost(model: model)
            defer { fixture.close() }
            let firstNode = try fixture.node("item-sheet-value")
            let firstBinding = try XCTUnwrap(model.counters[firstID])

            try fixture.activate("item-sheet-increment")
            try fixture.assertText("First: 11", "item-sheet-value")
            model.item = ItemSheetStateItem(id: firstID, title: "Updated first", seed: 50)
            fixture.flush()

            try fixture.assertText("Updated first: 11", "item-sheet-value")
            XCTAssertTrue(try fixture.node("item-sheet-value") === firstNode)
            firstBinding.wrappedValue = 12
            fixture.flush()
            try fixture.assertText("Updated first: 12", "item-sheet-value")

            model.item = ItemSheetStateItem(id: secondID, title: "Second", seed: 100)
            fixture.flush()
            let secondNode = try fixture.node("item-sheet-value")
            XCTAssertFalse(secondNode === firstNode)
            try fixture.assertText("Second: 100", "item-sheet-value")
            try fixture.assertRetired(firstBinding, value: 12, displayed: "Second: 100")
            let secondBinding = try XCTUnwrap(model.counters[secondID])
            try fixture.activate("item-sheet-increment")
            try fixture.assertText("Second: 101", "item-sheet-value")

            model.item = ItemSheetStateItem(id: firstID, title: "First again", seed: 200)
            fixture.flush()
            let returnedNode = try fixture.node("item-sheet-value")
            XCTAssertFalse(returnedNode === firstNode)
            XCTAssertFalse(returnedNode === secondNode)
            try fixture.assertText("First again: 200", "item-sheet-value")
            try fixture.assertRetired(firstBinding, value: 12, displayed: "First again: 200")
            try fixture.assertRetired(secondBinding, value: 101, displayed: "First again: 200")

            try XCTUnwrap(model.counters[firstID]).wrappedValue = 201
            fixture.flush()
            try fixture.assertText("First again: 201", "item-sheet-value")
        }
    }

    func testBackgroundSelectionAndUndoSurviveItemReplacementAndExplicitDismissal() async throws {
        try withTextLayout {
            let model = ItemSheetStateModel()
            let fixture = ItemSheetStateHost(model: model)
            defer { fixture.close() }
            let shell = try XCTUnwrap(fixture.runtime.root.children.first)
            let background = try XCTUnwrap(shell.children.first)
            let editor = try fixture.node("item-sheet-background")
            let text = try XCTUnwrap(model.backgroundText)
            let selected = try XCTUnwrap(model.backgroundSelection)
            let manager = try XCTUnwrap(model.manager)
            fixture.runtime.requestFocus(editor)
            XCTAssertTrue(fixture.runtime.focusedNode === editor)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
            fixture.type("X")
            XCTAssertEqual(text.wrappedValue, "aXd")
            XCTAssertTrue(manager.canUndo)
            selected.wrappedValue = itemSheetSelection(0..<1, in: text.wrappedValue)
            fixture.flush()

            let firstID = ItemSheetStateID(value: 1)
            let items = [
                ItemSheetStateItem(id: firstID, title: "First", seed: 10),
                ItemSheetStateItem(id: firstID, title: "Updated first", seed: 50),
                ItemSheetStateItem(id: ItemSheetStateID(value: 2), title: "Second", seed: 100),
                ItemSheetStateItem(id: firstID, title: "First again", seed: 200),
            ]
            for item in items {
                model.item = item
                fixture.flush()
                XCTAssertTrue(fixture.runtime.root.children.first === shell)
                XCTAssertTrue(shell.children.first === background)
                XCTAssertTrue(try fixture.node("item-sheet-background") === editor)
                XCTAssertEqual(text.wrappedValue, "aXd")
                XCTAssertEqual(editor.textInputSelection?.indices, .range(0..<1))
                XCTAssertEqual(editor.textInputCaretOffset, 1)
                XCTAssertEqual(itemSheetSelectionOffsets(selected.wrappedValue, in: text.wrappedValue), 0..<1)
                XCTAssertTrue(manager.canUndo)

                try fixture.focusControl("item-sheet-dismiss")
                manager.undo()
                fixture.flush()
                XCTAssertEqual(text.wrappedValue, "aXd", "A sheet must still block background undo")
                XCTAssertTrue(manager.canUndo)
                XCTAssertFalse(manager.canRedo)
            }

            let dismissesBefore = model.dismissCount
            try fixture.activate("item-sheet-dismiss")
            XCTAssertNil(model.item)
            XCTAssertEqual(model.dismissCount, dismissesBefore + 1)
            XCTAssertFalse(fixture.containsSheetOverlay)
            XCTAssertTrue(fixture.runtime.root.children.first === shell)
            XCTAssertTrue(shell.children.first === background)
            XCTAssertTrue(try fixture.node("item-sheet-background") === editor)
            XCTAssertEqual(editor.textInputSelection?.indices, .range(0..<1))
            XCTAssertTrue(manager.canUndo)

            fixture.runtime.requestFocus(editor)
            fixture.key(0x5A, modifiers: [.control])
            XCTAssertEqual(text.wrappedValue, "abcd")
            XCTAssertEqual(editor.textInputSelection?.indices, .range(1..<3))
            XCTAssertEqual(itemSheetSelectionOffsets(selected.wrappedValue, in: text.wrappedValue), 1..<3)
            XCTAssertFalse(manager.canUndo)
            XCTAssertTrue(manager.canRedo)
            fixture.key(0x59, modifiers: [.control])
            XCTAssertEqual(text.wrappedValue, "aXd")
            XCTAssertEqual(editor.textInputCaretOffset, 2)
            XCTAssertTrue(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }

    func testExplicitDismissalRetiresItemStateBeforeSameIDReopens() async throws {
        try withTextLayout {
            let model = ItemSheetStateModel()
            let itemID = ItemSheetStateID(value: 1)
            model.item = ItemSheetStateItem(id: itemID, title: "First", seed: 10)
            let fixture = ItemSheetStateHost(model: model)
            defer { fixture.close() }
            let original = try fixture.node("item-sheet-value")
            let oldBinding = try XCTUnwrap(model.counters[itemID])
            try fixture.activate("item-sheet-increment")
            try fixture.assertText("First: 11", "item-sheet-value")

            try fixture.activate("item-sheet-dismiss")
            XCTAssertNil(model.item)
            XCTAssertEqual(model.dismissCount, 1)
            XCTAssertFalse(fixture.containsSheetOverlay)
            let reloads = fixture.host.executedReloadCount
            oldBinding.wrappedValue = 99
            fixture.flush()
            XCTAssertEqual(oldBinding.wrappedValue, 11)
            XCTAssertEqual(fixture.host.executedReloadCount, reloads)

            model.item = ItemSheetStateItem(id: itemID, title: "Reopened", seed: 70)
            fixture.flush()
            XCTAssertFalse(try fixture.node("item-sheet-value") === original)
            try fixture.assertText("Reopened: 70", "item-sheet-value")
            try fixture.assertRetired(oldBinding, value: 11, displayed: "Reopened: 70")
            try fixture.activate("item-sheet-increment")
            try fixture.assertText("Reopened: 71", "item-sheet-value")
            try fixture.activate("item-sheet-dismiss")
            XCTAssertNil(model.item)
            XCTAssertEqual(model.dismissCount, 2)
            XCTAssertFalse(fixture.containsSheetOverlay)
        }
    }

    private func withTextLayout(_ body: () throws -> Void) rethrows {
        let previous = NativeTextRenderer.testingOverrides
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let characters = Array(text)
            let glyphs = characters.enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 10, y: 0),
                    advance: 10, glyphID: UInt32(index + 1), fontFamily: style.fontFamily,
                    weight: style.weight, fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let width = Double(max(characters.count, 1)) * 10
            let height = max(style.nativeFontPixelSize, 1)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: width, height: height, glyphs: glyphs)],
                contentSize: Size(width: width, height: height), measuredSize: Size(width: width, height: height))
        }
        defer { NativeTextRenderer.testingOverrides = previous }
        try body()
    }
}

private struct ItemSheetStateID: Hashable, CustomStringConvertible {
    let value: Int
    var description: String { "shared item description" }
}

private struct ItemSheetStateItem: Identifiable {
    let id: ItemSheetStateID
    let title: String
    let seed: Int
}

@MainActor
private final class ItemSheetStateModel: ObservableObject {
    @Published var item: ItemSheetStateItem?
    var counters: [ItemSheetStateID: Binding<Int>] = [:]
    var backgroundText: Binding<String>?
    var backgroundSelection: Binding<TextSelection?>?
    var manager: WinSwiftUI.UndoManager?
    var dismissCount = 0
}

@MainActor
private struct ItemSheetStateRoot: View {
    @ObservedObject private var model: ItemSheetStateModel
    @Environment(\.undoManager) private var manager
    @State private var backgroundText = "abcd"
    @State private var backgroundSelection: TextSelection? = itemSheetSelection(1..<3, in: "abcd")

    init(model: ItemSheetStateModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    var body: some View {
        model.backgroundText = $backgroundText
        model.backgroundSelection = $backgroundSelection
        model.manager = manager
        return TextField("Background", text: $backgroundText, selection: $backgroundSelection)
            .accessibilityIdentifier("item-sheet-background")
            .frame(width: 240, height: 40)
            .sheet(
                item: Binding(get: { model.item }, set: { model.item = $0 }),
                onDismiss: { model.dismissCount += 1 },
                content: { item in
                    ItemSheetStateCounter(item: item, model: model)
                }
            )
    }
}

@MainActor
private struct ItemSheetStateCounter: View {
    @State private var count: Int
    let item: ItemSheetStateItem
    let model: ItemSheetStateModel
    @Environment(\.dismiss) private var dismiss

    init(item: ItemSheetStateItem, model: ItemSheetStateModel) {
        self.item = item
        self.model = model
        _count = State(initialValue: item.seed)
    }

    var body: some View {
        model.counters[item.id] = $count
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(item.title): \(count)").accessibilityIdentifier("item-sheet-value")
            Button("Increment") { count += 1 }.accessibilityIdentifier("item-sheet-increment")
            Button("Dismiss") { dismiss() }.accessibilityIdentifier("item-sheet-dismiss")
        }
    }
}

@MainActor
private final class ItemSheetStateHost {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock
    var runtime: RetainedViewRuntime { host.hostedRuntime }
    var containsSheetOverlay: Bool { descendants(in: runtime.root).contains { $0.nodeTag == "sheet-overlay" } }

    init(model: ItemSheetStateModel) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let size = IntSize(width: 640, height: 480)
        let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
        let window = Win32Window(title: "Item sheet State", clientSize: size)
        window.testScaleFactorOverride = 1
        window.testMonitorRefreshRateOverride = 60
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Item sheet State", size: size, clearColor: .black,
                content: [AnyView(ItemSheetStateRoot(model: model))]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        self.clock = clock
        self.window = window
        self.host = host
        host.windowDidCreate(window)
        flush()
        host.resetObservabilityCounters()
    }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func close() { host.windowWillClose(window) }

    func node(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let matches = descendants(in: runtime.root).filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node for \(identifier)", file: file, line: line)
        return try XCTUnwrap(matches.first, file: file, line: line)
    }

    func focusControl(_ identifier: String) throws {
        let identified = try node(identifier)
        let control = try XCTUnwrap(descendants(in: identified).first { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(control)
        XCTAssertTrue(runtime.focusedNode === control)
    }

    func activate(_ identifier: String) throws {
        try focusControl(identifier)
        key(KeyboardKey.enter.rawValue)
    }

    func key(_ code: UInt32, modifiers: KeyboardModifiers = []) {
        host.window(
            window, keyDown: KeyboardEvent(keyCode: code, modifiers: modifiers, textInputDelivery: .systemCharacter))
        flush()
    }

    func type(_ value: String) {
        host.window(window, didInputText: value)
        flush()
    }

    func assertText(
        _ expected: String, _ identifier: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try node(identifier, file: file, line: line).text, expected, file: file, line: line)
    }

    func assertRetired(
        _ binding: Binding<Int>, value: Int, displayed: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let reloads = host.executedReloadCount
        XCTAssertEqual(binding.wrappedValue, value, file: file, line: line)
        binding.wrappedValue = 999
        flush()
        XCTAssertEqual(binding.wrappedValue, value, file: file, line: line)
        XCTAssertEqual(host.executedReloadCount, reloads, file: file, line: line)
        try assertText(displayed, "item-sheet-value", file: file, line: line)
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}

@MainActor
private func itemSheetSelection(_ range: Range<Int>, in text: String) -> TextSelection {
    let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
    let upper = text.index(text.startIndex, offsetBy: range.upperBound)
    return TextSelection(range: lower..<upper)
}

@MainActor
private func itemSheetSelectionOffsets(_ selection: TextSelection?, in text: String) -> Range<Int>? {
    guard let selection, case .selection(let range) = selection.indices else { return nil }
    let lower = text.distance(from: text.startIndex, to: range.lowerBound)
    let upper = text.distance(from: text.startIndex, to: range.upperBound)
    return lower..<upper
}
