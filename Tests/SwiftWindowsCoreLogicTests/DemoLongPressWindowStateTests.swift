import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class DemoLongPressWindowStateTests: XCTestCase {
    func testConfirmationHasKeyboardAndAccessibilityAlternatives() async throws {
        let model = makeLongPressWindowModel()
        let fixture = makeLongPressGalleryWindow(configuration: longPressWindowConfiguration(model: model))
        defer { fixture.close() }
        _ = try revealLongPress(in: fixture)

        func button(_ suffix: String) throws -> ViewNode {
            let identified = try XCTUnwrap(
                longPressWindowNode(in: fixture.runtime.root) {
                    $0.accessibilityIdentifier == "gallery.long-press.\(suffix)"
                })
            return try XCTUnwrap(longPressWindowNode(in: identified) { $0.isFocusable && $0.onActivate != nil })
        }

        let confirmation = try button("confirm")
        fixture.runtime.requestFocus(confirmation)
        XCTAssertTrue(fixture.runtime.focusedNode === confirmation)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x20))
        fixture.frames()
        XCTAssertEqual(try longPressStatus(in: fixture), "Confirmed 1 time")

        let source = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
        let elementID = try XCTUnwrap(source.projectedElementID(forNodeOrAncestor: try button("confirm")))
        let accessibleConfirmation = try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == elementID })
        XCTAssertTrue(accessibleConfirmation.isEnabled)
        XCTAssertTrue(accessibleConfirmation.hasDefaultAction)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: elementID))
        fixture.frames()
        XCTAssertEqual(try longPressStatus(in: fixture), "Confirmed 2 times")

        fixture.runtime.requestFocus(try button("reset"))
        fixture.runtime.keyDown(KeyboardEvent(keyCode: 0x0D))
        fixture.frames()
        XCTAssertEqual(try longPressStatus(in: fixture), "Ready to hold")
    }

    func testSharedModelWindowsKeepPressesIndependentAndNewWindowDoesNotResetAnAttempt() async throws {
        let model = makeLongPressWindowModel()
        let configuration = longPressWindowConfiguration(model: model)
        let first = makeLongPressGalleryWindow(configuration: configuration)
        defer { first.close() }
        let firstPoint = try revealLongPress(in: first)
        let firstStart = first.clock.now
        first.host.window(first.window, leftMouseDownAt: firstPoint)
        first.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Keep holding...")

        let second = makeLongPressGalleryWindow(configuration: configuration)
        defer { second.close() }
        let secondPoint = try revealLongPress(in: second)
        first.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Keep holding...")
        XCTAssertEqual(try longPressStatus(in: second), "Ready to hold")
        let secondStart = second.clock.now
        second.host.window(second.window, leftMouseDownAt: secondPoint)
        second.frames()

        model.lastAction = "Rebuild both windows during independent holds"
        first.frames()
        second.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Keep holding...")
        XCTAssertEqual(try longPressStatus(in: second), "Keep holding...")
        first.host.windowDidCancelPointerInteraction(first.window)
        first.frames()
        second.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Ready to hold")
        XCTAssertEqual(try longPressStatus(in: second), "Keep holding...")

        second.clock.now = secondStart + 0.6
        second.host.window(second.window, animationFrameAt: second.clock.now)
        second.frames()
        first.clock.now = firstStart + 1
        first.host.window(first.window, animationFrameAt: first.clock.now)
        first.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Ready to hold")
        XCTAssertEqual(try longPressStatus(in: second), "Confirmed 1 time")
        second.host.window(second.window, leftMouseUpAt: secondPoint)
        second.frames()
        XCTAssertEqual(try longPressStatus(in: second), "Confirmed 1 time")
    }

    func testWindowConfirmationSurvivesTabRemountButPendingPressIsCanceled() async throws {
        let model = makeLongPressWindowModel()
        let configuration = longPressWindowConfiguration(model: model)
        let first = makeLongPressGalleryWindow(configuration: configuration)
        defer { first.close() }
        let point = try revealLongPress(in: first)
        let start = first.clock.now
        first.host.window(first.window, leftMouseDownAt: point)
        first.clock.now = start + 0.6
        first.host.window(first.window, animationFrameAt: first.clock.now)
        first.host.window(first.window, leftMouseUpAt: point)
        first.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Confirmed 1 time")

        first.host.window(first.window, leftMouseDownAt: point)
        first.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Keep holding...")
        model.selectedScreen = .settings
        first.frames()
        first.clock.now += 1
        first.frames()
        model.selectedScreen = .gallery
        first.frames()
        first.clock.now += 1
        first.frames()
        _ = try revealLongPress(in: first)
        XCTAssertEqual(try longPressStatus(in: first), "Confirmed 1 time")

        let second = makeLongPressGalleryWindow(configuration: configuration)
        defer { second.close() }
        _ = try revealLongPress(in: second)
        first.frames()
        XCTAssertEqual(try longPressStatus(in: first), "Confirmed 1 time")
        XCTAssertEqual(try longPressStatus(in: second), "Ready to hold")
    }
}

@MainActor
private struct LongPressGalleryWindow {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    func frames() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
        }
    }

    func close() { host.windowWillClose(window) }
}

@MainActor
private func makeLongPressWindowModel() -> DemoDashboardModel {
    let model = DemoDashboardModel()
    model.selectedScreen = .gallery
    model.selectedGalleryCategory = .controls
    model.galleryQuery = "long press"
    return model
}

@MainActor
private func longPressWindowConfiguration(model: DemoDashboardModel) -> WindowGroupConfiguration {
    WindowGroup("Long-press windows", id: "long-press", size: IntSize(width: 960, height: 760)) {
        DemoRootView(model: model)
    }.makeWindowConfiguration()
}

@MainActor
private func makeLongPressGalleryWindow(configuration: WindowGroupConfiguration) -> LongPressGalleryWindow {
    let size = IntSize(width: 960, height: 760)
    let clock = RuntimeTestClock()
    clock.now = 10
    let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: size, scaleFactor: 1
    )
    let window = Win32Window(title: "Independent long press", clientSize: size)
    let host = WinSwiftUIWindowHost(
        configuration: configuration, platformWindow: window,
        renderer: FakeRenderBackend(), batchRenderer: nil,
        surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil
    )
    host.frameClock = { clock.now }
    host.hostedRuntime.clock = { clock.now }
    host.windowDidCreate(window)
    let fixture = LongPressGalleryWindow(host: host, window: window, clock: clock)
    fixture.frames()
    return fixture
}

@MainActor
private func longPressWindowNode(in node: ViewNode, matching predicate: (ViewNode) -> Bool) -> ViewNode? {
    if predicate(node) { return node }
    for child in node.children {
        if let result = longPressWindowNode(in: child, matching: predicate) { return result }
    }
    return nil
}

@MainActor
private func revealLongPress(in fixture: LongPressGalleryWindow) throws -> Point {
    let showcase = try XCTUnwrap(
        longPressWindowNode(in: fixture.runtime.root) { $0.accessibilityIdentifier == "gallery.long-press-showcase" }
    )
    XCTAssertTrue(fixture.runtime.scrollToDescendant(showcase, anchorY: 0))
    fixture.frames()
    let target = try XCTUnwrap(longPressWindowNode(in: showcase) { $0.longPressGesture != nil })
    var point = Point(x: target.resolvedFrame.midX, y: target.resolvedFrame.midY)
    var ancestor = target.parent
    while let node = ancestor {
        point.x += node.resolvedFrame.origin.x
        point.y += node.resolvedFrame.origin.y
        if node.scrollAxis == .vertical { point.y -= node.resolvedScrollOffset }
        if node.scrollAxis == .horizontal { point.x -= node.resolvedScrollOffset }
        ancestor = node.parent
    }
    return point
}

@MainActor
private func longPressStatus(in fixture: LongPressGalleryWindow) throws -> String {
    let status = try XCTUnwrap(
        longPressWindowNode(in: fixture.runtime.root) { $0.accessibilityIdentifier == "gallery.long-press.status" }
    )
    return try XCTUnwrap(longPressWindowNode(in: status) { $0.text != nil }?.text)
}
