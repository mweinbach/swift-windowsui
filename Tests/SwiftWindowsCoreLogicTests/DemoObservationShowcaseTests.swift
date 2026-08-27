import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DemoObservationShowcaseTests: XCTestCase {
    @MainActor
    private struct Harness {
        let model: DemoDashboardModel
        let host: WinSwiftUIWindowHost
        let window: Win32Window
        let clock: RuntimeTestClock

        var runtime: RetainedViewRuntime { host.hostedRuntime }

        func frames(_ count: Int = 2) {
            for _ in 0..<count {
                clock.now += 0.02
                host.windowNeedsDisplay(window)
            }
        }
    }

    private func makeHarness() -> Harness {
        let model = DemoDashboardModel()
        let clock = RuntimeTestClock()
        clock.now = 10
        let size = IntSize(width: 560, height: 500)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size, scaleFactor: 1)
        let window = Win32Window(title: "Observation showcase", clientSize: size)
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DemoObservationShowcase(model: model)
                Text("Outer gallery content").frame(height: 600)
            }
            .padding(16)
        }
        .accessibilityIdentifier("observation.test.outer")
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Observation showcase", size: size, clearColor: .black, content: [AnyView(content)]),
            platformWindow: window,
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        let harness = Harness(model: model, host: host, window: window, clock: clock)
        harness.frames()
        return harness
    }

    private func firstNode(in root: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
        var pending = [root]
        while let node = pending.popLast() {
            if predicate(node) { return node }
            pending.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    private func identified(_ suffix: String, in runtime: RetainedViewRuntime) throws -> ViewNode {
        try XCTUnwrap(
            firstNode(in: runtime.root) { $0.accessibilityIdentifier == "gallery.observation.\(suffix)" },
            "Missing observation example element: \(suffix)")
    }

    private func readout(_ suffix: String, in runtime: RetainedViewRuntime) throws -> String {
        let node = try identified(suffix, in: runtime)
        return try XCTUnwrap(firstNode(in: node) { $0.text != nil }?.text)
    }

    private func activateFromKeyboard(_ suffix: String, in runtime: RetainedViewRuntime) throws {
        let node = try identified(suffix, in: runtime)
        let target = try XCTUnwrap(firstNode(in: node) { $0.isFocusable && $0.onActivate != nil })
        runtime.requestFocus(target)
        XCTAssertTrue(runtime.focusedNode === target)
        runtime.keyDown(KeyboardEvent(keyCode: 0x20))
    }

    private func center(of node: ViewNode) -> Point {
        var point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)
        var parent = node.parent
        while let ancestor = parent {
            point.x += ancestor.resolvedFrame.origin.x
            point.y += ancestor.resolvedFrame.origin.y
            if ancestor.scrollAxis == .vertical { point.y -= ancestor.resolvedScrollOffset }
            if ancestor.scrollAxis == .horizontal { point.x -= ancestor.resolvedScrollOffset }
            parent = ancestor.parent
        }
        return point
    }

    func testRealScrollReadoutsKeyboardResetAndBindingAnimation() async throws {
        let harness = makeHarness()
        defer { harness.host.windowWillClose(harness.window) }
        let runtime = harness.runtime
        let identifiedScroll = try identified("scroll", in: runtime)
        let inner = try XCTUnwrap(firstNode(in: identifiedScroll) { $0.scrollAxis == .vertical })
        let outer = try XCTUnwrap(firstNode(in: runtime.root) { $0.scrollAxis == .vertical && $0 !== inner })
        XCTAssertEqual(try readout("offset", in: runtime), "Offset: 0 pt")
        XCTAssertEqual(try readout("phase", in: runtime), "Phase: Idle")
        XCTAssertEqual(try readout("visibility", in: runtime), "Row 6: outside")

        runtime.mouseWheel(at: center(of: inner), delta: -120 / inner.scrollStep)
        harness.frames()
        XCTAssertEqual(inner.resolvedScrollOffset, 120, accuracy: 0.001)
        XCTAssertEqual(outer.resolvedScrollOffset, 0)
        XCTAssertEqual(try readout("offset", in: runtime), "Offset: 120 pt")
        XCTAssertEqual(try readout("visibility", in: runtime), "Row 6: visible")
        XCTAssertEqual(try readout("phase", in: runtime), "Phase: Idle (from Interacting)")
        XCTAssertTrue(try identified("scroll", in: runtime) === identifiedScroll)

        runtime.mouseWheel(at: center(of: inner), delta: -1, source: .precise)
        harness.frames()
        XCTAssertTrue(try readout("phase", in: runtime).contains("Decelerating"))
        XCTAssertGreaterThan(inner.resolvedScrollOffset, 120)
        harness.clock.now += 1
        harness.frames()
        XCTAssertTrue(try readout("phase", in: runtime).hasPrefix("Phase: Idle"))
        XCTAssertEqual(outer.resolvedScrollOffset, 0)

        let resetStartedAt = harness.clock.now
        try activateFromKeyboard("reset", in: runtime)
        harness.frames()
        XCTAssertTrue(try readout("phase", in: runtime).contains("Animating"))
        harness.clock.now = resetStartedAt + 0.8
        harness.frames()
        XCTAssertEqual(inner.resolvedScrollOffset, 0, accuracy: 0.001)
        XCTAssertEqual(outer.resolvedScrollOffset, 0)
        XCTAssertEqual(try readout("offset", in: runtime), "Offset: 0 pt")
        XCTAssertEqual(try readout("visibility", in: runtime), "Row 6: outside")

        let preview = try identified("preview", in: runtime)
        XCTAssertEqual(preview.opacity, 1)
        try activateFromKeyboard("toggle", in: runtime)
        XCTAssertFalse(harness.model.galleryState.observation.isPreviewBright)
        XCTAssertEqual(preview.opacity, 1, "The control must keep its binding transaction through host invalidation")
        let animation = try XCTUnwrap(preview.animationStates[.opacity])
        XCTAssertEqual(animation.duration, 0.6)
        harness.clock.now = animation.startTime + 0.3
        harness.host.windowNeedsDisplay(harness.window)
        XCTAssertEqual(preview.opacity, 0.625, accuracy: 0.001)
        harness.clock.now = animation.startTime + 0.65
        harness.host.windowNeedsDisplay(harness.window)
        XCTAssertEqual(preview.opacity, 0.25, accuracy: 0.001)
        XCTAssertNil(preview.animationStates[.opacity])
    }

    func testScrollExampleIsDiscoverableInTheExistingControlsCollection() async {
        let model = DemoDashboardModel()
        model.selectedScreen = .gallery
        model.selectedGalleryCategory = .controls
        model.galleryQuery = "scroll geometry"
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoRootView(model: model), size: IntSize(width: 800, height: 600))
        XCTAssertEqual(DemoGalleryScreen(model: model).visibleCategories, [.controls])
        XCTAssertNotNil(
            firstNode(in: snapshot.runtime.root) { $0.accessibilityIdentifier == "gallery.observation-showcase" })
        XCTAssertNotNil(firstNode(in: snapshot.runtime.root) { $0.text == "Scroll observations" })
    }
}
