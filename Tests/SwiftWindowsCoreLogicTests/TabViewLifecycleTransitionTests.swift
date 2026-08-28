import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class TabViewLifecycleTransitionTests: XCTestCase {
    func testSceneTabSwitchesPreserveIncomingLifecycleAndOutgoingFade() async throws {
        try withTextLayout { try exerciseSwitchAndRemount(rendering: .scene) }
    }

    func testFrameTabSwitchesPreserveIncomingLifecycleAndOutgoingFade() async throws {
        try withTextLayout { try exerciseSwitchAndRemount(rendering: .frame) }
    }

    private func exerciseSwitchAndRemount(rendering path: TabLifecycleRenderPath) throws {
        let harness = TabLifecycleHarness(rendering: path)
        defer {
            harness.runtime.stopRenderLifecycleCallbacks()
            harness.runtime.cancelRenderLifecycleTasks()
        }
        harness.render(at: harness.clock.now)
        let original = try harness.page(0)
        let originalDescendant = try harness.descendant(0)
        XCTAssertFalse(original === originalDescendant, "Lifecycle belongs to a descendant, not just the page wrapper")
        XCTAssertFalse(original.isRemovalOverlay)
        XCTAssertFalse(originalDescendant.isRemovalOverlay)
        XCTAssertEqual(original.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(harness.events.values, [.appear(0)])
        XCTAssertTrue(harness.runtime.transitionOverlays.isEmpty)

        harness.rebuild()
        harness.render(at: harness.clock.now)
        XCTAssertTrue(try harness.page(0) === original)
        XCTAssertTrue(try harness.descendant(0) === originalDescendant)
        XCTAssertEqual(harness.events.values, [.appear(0)])
        XCTAssertTrue(harness.runtime.transitionOverlays.isEmpty)

        let switchedAt = harness.clock.now
        harness.select(1)
        let incoming = try harness.page(1)
        let incomingDescendant = try harness.descendant(1)
        let incomingFade = try XCTUnwrap(incoming.animationStates[.opacity])
        let outgoingFade = try XCTUnwrap(original.animationStates[.opacity])
        XCTAssertFalse(harness.containsPage(0))
        XCTAssertFalse(incoming.isRemovalOverlay, "Adopting a constructed page must not mark it as a removed overlay")
        XCTAssertFalse(incomingDescendant.isRemovalOverlay)
        XCTAssertEqual(harness.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(harness.runtime.transitionOverlays.first === original)
        XCTAssertTrue(original.isRemovalOverlay)
        XCTAssertEqual(incoming.opacity, 0, accuracy: 0.001)
        XCTAssertEqual(original.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(incomingFade.startTime, switchedAt, accuracy: 0.001)
        XCTAssertEqual(outgoingFade.startTime, switchedAt, accuracy: 0.001)
        XCTAssertEqual(incomingFade.endValue, 1, accuracy: 0.001)
        XCTAssertEqual(outgoingFade.endValue, 0, accuracy: 0.001)
        XCTAssertGreaterThan(incomingFade.duration, 0)
        XCTAssertEqual(incomingFade.duration, outgoingFade.duration, accuracy: 0.001)
        XCTAssertEqual(harness.events.values, [.appear(0)], "Outgoing disappearance must wait for the fade")

        let midpoint = switchedAt + incomingFade.duration / 2
        harness.render(at: midpoint)

        XCTAssertGreaterThan(incoming.opacity, 0.05)
        XCTAssertLessThan(incoming.opacity, 0.95)
        XCTAssertGreaterThan(original.opacity, 0.05)
        XCTAssertLessThan(original.opacity, 0.95)
        XCTAssertFalse(incoming.isRemovalOverlay)
        XCTAssertTrue(harness.runtime.transitionOverlays.first === original)
        XCTAssertEqual(harness.events.values, [.appear(0), .appear(1)])
        let progressBeforeRebuild = incoming.opacity
        harness.rebuild()
        harness.render(at: midpoint)
        XCTAssertTrue(try harness.page(1) === incoming)
        XCTAssertTrue(try harness.descendant(1) === incomingDescendant)
        XCTAssertFalse(incoming.isRemovalOverlay)
        XCTAssertEqual(incoming.opacity, progressBeforeRebuild, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(incoming.animationStates[.opacity]).startTime, switchedAt, accuracy: 0.001)
        XCTAssertEqual(harness.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(harness.runtime.transitionOverlays.first === original)
        XCTAssertEqual(harness.events.values, [.appear(0), .appear(1)])

        harness.render(at: switchedAt + incomingFade.duration + 0.001)

        XCTAssertEqual(incoming.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(original.opacity, 0, accuracy: 0.001)
        XCTAssertNil(incoming.animationStates[.opacity])
        XCTAssertTrue(harness.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(harness.events.values, [.appear(0), .appear(1), .disappear(0)])

        let returnedAt = harness.clock.now
        harness.select(0)
        let returned = try harness.page(0)
        let returnedDescendant = try harness.descendant(0)
        let returnedFade = try XCTUnwrap(returned.animationStates[.opacity])
        XCTAssertFalse(returned === original, "Switching back must mount a fresh page node")
        XCTAssertFalse(returnedDescendant === originalDescendant)
        XCTAssertFalse(returned.isRemovalOverlay)
        XCTAssertFalse(returnedDescendant.isRemovalOverlay)
        XCTAssertFalse(harness.containsPage(1))
        XCTAssertEqual(returned.opacity, 0, accuracy: 0.001)
        XCTAssertEqual(returnedFade.startTime, returnedAt, accuracy: 0.001)
        XCTAssertEqual(returnedFade.endValue, 1, accuracy: 0.001)
        XCTAssertEqual(harness.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(harness.runtime.transitionOverlays.first === incoming)
        XCTAssertTrue(incoming.isRemovalOverlay)
        XCTAssertEqual(harness.events.values, [.appear(0), .appear(1), .disappear(0)])

        harness.render(at: returnedAt + returnedFade.duration / 2)

        XCTAssertGreaterThan(returned.opacity, 0.05)
        XCTAssertLessThan(returned.opacity, 0.95)
        XCTAssertGreaterThan(incoming.opacity, 0.05)
        XCTAssertLessThan(incoming.opacity, 0.95)
        XCTAssertEqual(harness.events.values, [.appear(0), .appear(1), .disappear(0), .appear(0)])
        XCTAssertEqual(harness.runtime.transitionOverlays.count, 1)
        XCTAssertTrue(harness.runtime.transitionOverlays.first === incoming)
        harness.render(at: returnedAt + returnedFade.duration + 0.001)

        XCTAssertEqual(returned.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(incoming.opacity, 0, accuracy: 0.001)
        XCTAssertTrue(harness.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(
            harness.events.values,
            [.appear(0), .appear(1), .disappear(0), .appear(0), .disappear(1)])
        harness.rebuild()
        harness.render(at: harness.clock.now)
        XCTAssertTrue(try harness.page(0) === returned)
        XCTAssertTrue(try harness.descendant(0) === returnedDescendant)
        XCTAssertFalse(returned.isRemovalOverlay)
        XCTAssertEqual(returned.opacity, 1, accuracy: 0.001)
        XCTAssertNil(returned.animationStates[.opacity])
        XCTAssertTrue(harness.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(
            harness.events.values,
            [.appear(0), .appear(1), .disappear(0), .appear(0), .disappear(1)])
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
}

private enum TabLifecycleRenderPath {
    case scene
    case frame
}

private enum TabLifecycleEvent: Equatable {
    case appear(Int)
    case disappear(Int)
}

@MainActor
private final class TabLifecycleEvents {
    var values: [TabLifecycleEvent] = []
}

@MainActor
private final class TabLifecycleSelection {
    var value = 0
}

@MainActor
private struct TabLifecyclePage: View {
    let index: Int
    let events: TabLifecycleEvents

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(index == 0 ? Color.red : Color.blue)
                .frame(width: 120, height: 80)
                .accessibilityIdentifier("tab-lifecycle-descendant:\(index)")
                .onAppear { events.values.append(.appear(index)) }
                .onDisappear { events.values.append(.disappear(index)) }
        }
    }
}

@MainActor
private final class TabLifecycleHarness {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let clock: RuntimeTestClock
    let events: TabLifecycleEvents
    private let selection: TabLifecycleSelection
    private let rendering: TabLifecycleRenderPath

    init(rendering: TabLifecycleRenderPath) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        runtime.clock = { clock.now }
        let host = ComponentHost(runtime: runtime)
        let events = TabLifecycleEvents()
        let selection = TabLifecycleSelection()
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() })
        host.setComponents {
            [
                TabView(selection: Binding(get: { selection.value }, set: { selection.value = $0 })) {
                    TabLifecyclePage(index: 0, events: events)
                        .tabItem { Text("One") }
                        .tag(0)
                    TabLifecyclePage(index: 1, events: events)
                        .tabItem { Text("Two") }
                        .tag(1)
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        self.clock = clock
        self.runtime = runtime
        self.host = host
        self.events = events
        self.selection = selection
        self.rendering = rendering
    }

    func select(_ index: Int) {
        selection.value = index
        host.reload()
    }

    func rebuild() { host.reload() }

    func render(at timestamp: Double) {
        clock.now = timestamp
        _ = runtime.tickAnimations(at: timestamp)
        switch rendering {
        case .scene: _ = runtime.renderScene(at: timestamp)
        case .frame: _ = runtime.renderFrame(at: timestamp)
        }
    }

    func page(_ index: Int) throws -> ViewNode {
        try XCTUnwrap(nodes.first { $0.nodeTag == "tabview-page:\(index)" })
    }

    func containsPage(_ index: Int) -> Bool {
        nodes.contains { $0.nodeTag == "tabview-page:\(index)" }
    }

    func descendant(_ index: Int) throws -> ViewNode {
        try XCTUnwrap(nodes.first { $0.accessibilityIdentifier == "tab-lifecycle-descendant:\(index)" })
    }

    private var nodes: [ViewNode] {
        var result: [ViewNode] = []
        var pending = [runtime.root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}
