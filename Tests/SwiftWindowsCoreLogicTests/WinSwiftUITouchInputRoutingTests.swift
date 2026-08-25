import XCTest

@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class WinSwiftUITouchInputRoutingTests: XCTestCase {
    func testPrimaryTouchRoutesScaledPointerPressMoveAndRelease() async {
        await MainActor.run {
            let fixture = makeTouchRoutingHost(scaleFactor: 2)

            fixture.host.window(fixture.window, touchBegan: [Point(x: 120, y: 80)])
            fixture.host.window(fixture.window, touchMoved: [Point(x: 180, y: 100)])
            fixture.host.window(fixture.window, touchEnded: [Point(x: 220, y: 140)])

            XCTAssertEqual(fixture.recorder.events.count, 3)

            guard case .pointerDown(let pressedPoint, let pressedScale) = fixture.recorder.events[0] else {
                return XCTFail("Expected the first touch to route a retained pointer press")
            }
            XCTAssertEqual(pressedPoint, Point(x: 60, y: 40))
            XCTAssertEqual(pressedScale, 2)

            guard case .pointerMoved(let movedPoint, let movedScale) = fixture.recorder.events[1] else {
                return XCTFail("Expected primary-touch movement to route a retained pointer move")
            }
            XCTAssertEqual(movedPoint, Point(x: 90, y: 50))
            XCTAssertEqual(movedScale, 2)

            guard case .pointerUp(let releasedPoint, let releasedScale) = fixture.recorder.events[2] else {
                return XCTFail("Expected primary-touch release to route a retained pointer release")
            }
            XCTAssertEqual(releasedPoint, Point(x: 110, y: 70))
            XCTAssertEqual(releasedScale, 2)
        }
    }

    func testSecondaryTouchesAndEventsWithoutAnActiveContactAreIgnored() async {
        await MainActor.run {
            let fixture = makeTouchRoutingHost()

            fixture.host.window(fixture.window, touchMoved: [Point(x: 3, y: 4)])
            fixture.host.window(fixture.window, touchEnded: [Point(x: 3, y: 4)])
            fixture.host.window(fixture.window, touchBegan: [])
            fixture.host.window(
                fixture.window,
                touchBegan: [Point(x: 10, y: 20), Point(x: 200, y: 180)]
            )
            fixture.host.window(fixture.window, touchBegan: [Point(x: 260, y: 150)])
            fixture.host.window(fixture.window, touchMoved: [])
            fixture.host.window(fixture.window, touchEnded: [])
            fixture.host.window(
                fixture.window,
                touchMoved: [Point(x: 20, y: 30), Point(x: 250, y: 170)]
            )
            fixture.host.window(fixture.window, touchEnded: [Point(x: 30, y: 40)])
            fixture.host.window(fixture.window, touchMoved: [Point(x: 40, y: 50)])
            fixture.host.window(fixture.window, touchEnded: [Point(x: 40, y: 50)])

            XCTAssertEqual(fixture.recorder.events.count, 3)
            guard case .pointerDown(let down, _) = fixture.recorder.events[0],
                case .pointerMoved(let moved, _) = fixture.recorder.events[1],
                case .pointerUp(let up, _) = fixture.recorder.events[2]
            else {
                return XCTFail("Expected exactly one primary touch sequence")
            }

            XCTAssertEqual(down, Point(x: 10, y: 20))
            XCTAssertEqual(moved, Point(x: 20, y: 30))
            XCTAssertEqual(up, Point(x: 30, y: 40))
        }
    }

    func testTouchTapActivatesRetainedSwiftUIButton() async {
        await MainActor.run {
            var activationCount = 0
            let fixture = makeTouchRoutingHost(
                content: [
                    AnyView(
                        Button("Tap") {
                            activationCount += 1
                        }
                        .frame(width: 120, height: 40)
                    )
                ],
                scaleFactor: 2
            )

            guard let button = firstTouchActivatableNode(in: fixture.host.hostedRuntime.root) else {
                return XCTFail("Expected an activatable retained button")
            }
            let center = touchAbsoluteCenter(of: button)
            let physicalPoint = Point(x: center.x * 2, y: center.y * 2)

            fixture.host.window(fixture.window, touchBegan: [physicalPoint])
            fixture.host.window(fixture.window, touchEnded: [physicalPoint])

            XCTAssertEqual(activationCount, 1)
        }
    }

    func testPointerCancellationClearsTouchWithoutActivatingButton() async {
        await MainActor.run {
            var activationCount = 0
            let fixture = makeTouchRoutingHost(
                content: [
                    AnyView(
                        Button("Tap") {
                            activationCount += 1
                        }
                        .frame(width: 120, height: 40)
                    )
                ]
            )

            guard let button = firstTouchActivatableNode(in: fixture.host.hostedRuntime.root) else {
                return XCTFail("Expected an activatable retained button")
            }
            let center = touchAbsoluteCenter(of: button)

            fixture.host.window(fixture.window, touchBegan: [center])
            XCTAssertEqual(fixture.host.hostedRuntime.interactionPhase(for: button), .pressed)

            fixture.host.windowDidCancelPointerInteraction(fixture.window)
            fixture.host.window(fixture.window, touchEnded: [center])

            XCTAssertEqual(activationCount, 0)
            XCTAssertNotEqual(fixture.host.hostedRuntime.interactionPhase(for: button), .pressed)
            XCTAssertEqual(fixture.recorder.events.count, 2)
            guard case .pointerCancelled = fixture.recorder.events[1] else {
                return XCTFail("Expected lost capture to be observable as pointer cancellation")
            }

            fixture.host.window(fixture.window, touchBegan: [center])
            fixture.host.window(fixture.window, touchEnded: [center])
            XCTAssertEqual(activationCount, 1, "A new contact must work after cancellation")
        }
    }

    func testKeyboardFocusLossCancelsActiveTouchAndIgnoresItsLateRelease() async {
        await MainActor.run {
            let fixture = makeTouchRoutingHost()
            let point = Point(x: 32, y: 24)

            fixture.host.window(fixture.window, touchBegan: [point])
            fixture.host.windowDidLoseKeyboardFocus(fixture.window)
            fixture.host.window(fixture.window, touchEnded: [point])

            XCTAssertEqual(fixture.recorder.events.count, 3)
            guard case .pointerCancelled = fixture.recorder.events[1] else {
                return XCTFail("Expected active touch cancellation before keyboard-focus loss")
            }
            guard case .keyboardFocusDidLeaveWindow = fixture.recorder.events[2] else {
                return XCTFail("Expected keyboard-focus loss to remain observable")
            }

            fixture.host.window(fixture.window, touchBegan: [point])
            fixture.host.window(fixture.window, touchEnded: [point])
            XCTAssertEqual(fixture.recorder.events.count, 5)
        }
    }
}

@MainActor
private func makeTouchRoutingHost(
    content: [AnyView] = [],
    scaleFactor: Double = 1
) -> (host: WinSwiftUIWindowHost, window: Win32Window, recorder: RoutedInputEventRecorder) {
    let logicalSize = IntSize(width: 320, height: 200)
    let pixelSize = IntSize(
        width: Int32((Double(logicalSize.width) * scaleFactor).rounded()),
        height: Int32((Double(logicalSize.height) * scaleFactor).rounded())
    )
    let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: pixelSize,
        scaleFactor: scaleFactor
    )
    let configuration = WindowGroupConfiguration(
        title: "Touch routing",
        size: logicalSize,
        clearColor: .black,
        content: content
    )
    let host = WinSwiftUIWindowHost(
        configuration: configuration,
        renderer: FakeRenderBackend(),
        batchRenderer: nil,
        surfaceDescriptorProvider: { _ in surface }
    )
    let recorder = RoutedInputEventRecorder()
    host.onInputEventRouted = { recorder.record($0) }

    let window = Win32Window(title: "Touch routing", clientSize: pixelSize)
    window.testScaleFactorOverride = scaleFactor
    host.windowDidCreate(window)

    return (host, window, recorder)
}

@MainActor
private func firstTouchActivatableNode(in root: ViewNode) -> ViewNode? {
    if root.onActivate != nil {
        return root
    }
    for child in root.children {
        if let match = firstTouchActivatableNode(in: child) {
            return match
        }
    }
    return nil
}

@MainActor
private func touchAbsoluteCenter(of node: ViewNode) -> Point {
    var point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)
    var ancestor = node.parent
    while let current = ancestor {
        point.x += current.resolvedFrame.origin.x
        point.y += current.resolvedFrame.origin.y
        ancestor = current.parent
    }
    return point
}
