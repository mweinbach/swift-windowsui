import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class Win32CapturedPointerInputTests: XCTestCase {
    private struct Sample: Equatable {
        let phase: String
        let point: Point
        let scale: Double
    }

    @MainActor
    private final class Fixture {
        let window: Win32Window
        let host: WinSwiftUIWindowHost
        var samples: [Sample] = []
        var runtimeMoves: [Point] = []
        var runtimeDownCount = 0
        var runtimeUps: [Point] = []
        var afterRouting: (() -> Void)?

        init(scale: Double = 2) {
            let window = Win32Window(title: "Captured pointer", clientSize: IntSize(width: 640, height: 480))
            window.testScaleFactorOverride = scale
            window.testMonitorRefreshRateOverride = 60
            self.window = window
            host = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Captured pointer", size: IntSize(width: 320, height: 240),
                    clearColor: .black, content: []),
                platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: nil,
                startupPresentationMode: .frameDebug, startupProbeConfiguration: nil)
            host.hostedRuntime.setRootSize(IntSize(width: 320, height: 240))
            host.hostedRuntime.root.setChildren([])
            host.hostedRuntime.root.isHitTestVisible = true
            host.hostedRuntime.root.onPointerMove = { [weak self] point in self?.runtimeMoves.append(point) }
            host.hostedRuntime.root.onPointerDown = { [weak self] in self?.runtimeDownCount += 1 }
            host.hostedRuntime.root.onPointerUpInsideAt = { [weak self] point in self?.runtimeUps.append(point) }
            host.onInputEventRouted = { [weak self] event in
                guard let self else { return }
                switch event {
                case .pointerMoved(let point, let scale):
                    samples.append(Sample(phase: "move", point: point, scale: scale))
                case .pointerDown(let point, let scale):
                    samples.append(Sample(phase: "down", point: point, scale: scale))
                case .pointerUp(let point, let scale):
                    samples.append(Sample(phase: "up", point: point, scale: scale))
                default:
                    XCTFail("Unexpected input in the captured-pointer fixture.")
                }
                afterRouting?()
            }
        }

        func finish() {
            afterRouting = nil
            host.onInputEventRouted = nil
            window.delegate = nil
            host.windowWillClose(window)
        }
    }

    @MainActor
    private final class CapturedDelegate: WindowDelegate, Win32CapturedPointerInputDelegate {
        let receive: @MainActor (Win32Window, Win32CapturedPointerInput) -> Void
        private(set) var legacyCount = 0

        init(_ receive: @escaping @MainActor (Win32Window, Win32CapturedPointerInput) -> Void) {
            self.receive = receive
        }

        func window(_ window: Win32Window, capturedPointerInput input: Win32CapturedPointerInput) {
            receive(window, input)
        }

        func window(_ window: Win32Window, pointerMovedTo point: Point) { legacyCount += 1 }
        func window(_ window: Win32Window, leftMouseDownAt point: Point) { legacyCount += 1 }
        func window(_ window: Win32Window, leftMouseUpAt point: Point) { legacyCount += 1 }
    }

    @MainActor
    private final class LegacyDelegate: WindowDelegate {
        let receive: @MainActor (Win32Window, String, Point) -> Void

        init(_ receive: @escaping @MainActor (Win32Window, String, Point) -> Void) { self.receive = receive }

        func window(_ window: Win32Window, pointerMovedTo point: Point) { receive(window, "move", point) }
        func window(_ window: Win32Window, leftMouseDownAt point: Point) { receive(window, "down", point) }
        func window(_ window: Win32Window, leftMouseUpAt point: Point) { receive(window, "up", point) }
    }

    @MainActor
    private final class NeutralHost: PlatformWindowHost {
        let receive: @MainActor (String, Point) -> Void

        init(_ receive: @escaping @MainActor (String, Point) -> Void) { self.receive = receive }

        func platformWindow(_ window: any PlatformWindow, didReceive event: PlatformWindowEvent) {
            switch event {
            case .pointerMoved(let point): receive("move", point)
            case .pointerButton(let event, let phase): receive(phase == .down ? "down" : "up", event.position)
            default: XCTFail("Unexpected neutral event in the captured-pointer fixture.")
            }
        }
    }

    func testCapturedMoveUsesOriginalScaleInsteadOfCurrentWindowScale() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let input = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        fixture.window.testScaleFactorOverride = 1

        fixture.window.deliverCapturedPointerInput(input)

        XCTAssertEqual(fixture.samples, [Sample(phase: "move", point: Point(x: 100, y: 50), scale: 2)])
        XCTAssertEqual(fixture.runtimeMoves, [Point(x: 100, y: 50)])
        XCTAssertFalse(fixture.window.isDeliveringCapturedPointerInput(input))
        let later = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        fixture.window.deliverCapturedPointerInput(later)
        XCTAssertEqual(fixture.samples.last, Sample(phase: "move", point: Point(x: 200, y: 100), scale: 1))
    }

    func testCapturedPressAndReleaseKeepScaleAcrossDelegateCallback() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let host = fixture.host
        let delegate = CapturedDelegate { window, input in
            window.testScaleFactorOverride = 1
            host.window(window, capturedPointerInput: input)
        }
        fixture.window.delegate = delegate

        for kind in [Win32CapturedPointerInput.Kind.leftDown, .leftUp] {
            fixture.window.testScaleFactorOverride = 2
            let input = try XCTUnwrap(fixture.window.capturePointerInput(kind, at: Point(x: 200, y: 100)))
            fixture.window.deliverCapturedPointerInput(input)
        }

        XCTAssertEqual(
            fixture.samples,
            [
                Sample(phase: "down", point: Point(x: 100, y: 50), scale: 2),
                Sample(phase: "up", point: Point(x: 100, y: 50), scale: 2),
            ])
        XCTAssertEqual(fixture.runtimeDownCount, 1)
        XCTAssertEqual(fixture.runtimeUps, [Point(x: 100, y: 50)])
        XCTAssertEqual(delegate.legacyCount, 0)
    }

    func testCapturedScaleKeepsTheExistingFractionalAndClampRule() async throws {
        let cases: [(raw: Double, expected: Double, point: Point)] = [
            (1.25, 1.25, Point(x: 125, y: 75)),
            (0.75, 1, Point(x: 100, y: 60)),
            (.nan, 1, Point(x: 100, y: 60)),
            (.infinity, 1, Point(x: 100, y: 60)),
            (-1, 1, Point(x: 100, y: 60)),
        ]
        for sample in cases {
            let fixture = Fixture(scale: sample.raw)
            defer { fixture.finish() }
            let input = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: sample.point))
            fixture.window.testScaleFactorOverride = 3
            fixture.window.deliverCapturedPointerInput(input)
            XCTAssertEqual(
                fixture.samples, [Sample(phase: "move", point: Point(x: 100, y: 60), scale: sample.expected)])
            XCTAssertEqual(fixture.runtimeMoves, [Point(x: 100, y: 60)])
        }
    }

    func testNestedDeliveryRestoresOuterScopeAndItsCapturedScale() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let host = fixture.host
        let outer = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        var nested = false
        let delegate = CapturedDelegate { window, input in
            if !nested {
                nested = true
                window.testScaleFactorOverride = 1
                guard let inner = window.capturePointerInput(.moved, at: Point(x: 20, y: 30)) else {
                    return XCTFail("The nested input must be capturable.")
                }
                window.deliverCapturedPointerInput(inner)
                XCTAssertTrue(window.isDeliveringCapturedPointerInput(outer))
            } else {
                XCTAssertFalse(window.isDeliveringCapturedPointerInput(outer))
                host.window(window, capturedPointerInput: outer)
                XCTAssertTrue(fixture.samples.isEmpty, "The outer context cannot consume the inner frame.")
            }
            host.window(window, capturedPointerInput: input)
        }
        fixture.window.delegate = delegate

        fixture.window.deliverCapturedPointerInput(outer)

        XCTAssertEqual(
            fixture.samples,
            [
                Sample(phase: "move", point: Point(x: 20, y: 30), scale: 1),
                Sample(phase: "move", point: Point(x: 100, y: 50), scale: 2),
            ])
        XCTAssertEqual(fixture.runtimeMoves, [Point(x: 20, y: 30), Point(x: 100, y: 50)])
        XCTAssertFalse(fixture.window.isDeliveringCapturedPointerInput(outer))
    }

    func testInputIsConsumedBeforeRuntimeCallbacksCanReplayIt() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let input = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        var didReplay = false
        fixture.host.hostedRuntime.root.onPointerMove = { [weak fixture] point in
            guard let fixture else { return }
            fixture.runtimeMoves.append(point)
            guard !didReplay else { return }
            didReplay = true
            fixture.host.window(fixture.window, capturedPointerInput: input)
            fixture.window.deliverCapturedPointerInput(input)
        }

        fixture.window.deliverCapturedPointerInput(input)

        XCTAssertTrue(didReplay)
        XCTAssertEqual(fixture.runtimeMoves, [Point(x: 100, y: 50)])
        XCTAssertEqual(fixture.samples.count, 1)
    }

    func testConsumedInputCannotReplayDuringObserverOrAfterReturn() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let input = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        var didReplay = false
        fixture.afterRouting = { [weak fixture] in
            guard let fixture, !didReplay else { return }
            didReplay = true
            fixture.host.window(fixture.window, capturedPointerInput: input)
            fixture.window.deliverCapturedPointerInput(input)
            fixture.window.testScaleFactorOverride = 1
            guard let nested = fixture.window.capturePointerInput(.moved, at: Point(x: 20, y: 30)) else {
                return XCTFail("The observer's nested input must be capturable.")
            }
            fixture.window.deliverCapturedPointerInput(nested)
            // The restored outer frame must retain its already-consumed bit.
            fixture.host.window(fixture.window, capturedPointerInput: input)
        }

        fixture.window.deliverCapturedPointerInput(input)
        fixture.host.window(fixture.window, capturedPointerInput: input)
        fixture.window.deliverCapturedPointerInput(input)

        XCTAssertTrue(didReplay)
        XCTAssertEqual(
            fixture.samples,
            [
                Sample(phase: "move", point: Point(x: 100, y: 50), scale: 2),
                Sample(phase: "move", point: Point(x: 20, y: 30), scale: 1),
            ])
        XCTAssertEqual(fixture.runtimeMoves, [Point(x: 100, y: 50), Point(x: 20, y: 30)])
    }

    func testStaleAndInactiveContextsCannotConsumeTheCurrentFrame() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let host = fixture.host
        let stale = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 40, y: 60)))
        let current = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        host.window(fixture.window, capturedPointerInput: current)
        XCTAssertTrue(fixture.samples.isEmpty)
        let delegate = CapturedDelegate { window, input in
            host.window(window, capturedPointerInput: stale)
            window.deliverCapturedPointerInput(stale)
            host.window(window, capturedPointerInput: input)
        }
        fixture.window.delegate = delegate

        fixture.window.deliverCapturedPointerInput(current)
        fixture.window.deliverCapturedPointerInput(stale)

        XCTAssertEqual(fixture.samples, [Sample(phase: "move", point: Point(x: 100, y: 50), scale: 2)])
        XCTAssertEqual(fixture.runtimeMoves, [Point(x: 100, y: 50)])
    }

    func testWrongWindowAndHostCannotConsumeTheOriginalDelivery() async throws {
        let first = Fixture()
        let second = Fixture(scale: 1)
        defer {
            first.finish()
            second.finish()
        }
        let input = try XCTUnwrap(first.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))
        let delegate = CapturedDelegate { window, input in
            second.window.deliverCapturedPointerInput(input)
            second.host.window(window, capturedPointerInput: input)
            first.host.window(second.window, capturedPointerInput: input)
            first.host.window(window, capturedPointerInput: input)
        }
        first.window.delegate = delegate

        first.window.deliverCapturedPointerInput(input)

        XCTAssertEqual(first.samples, [Sample(phase: "move", point: Point(x: 100, y: 50), scale: 2)])
        XCTAssertEqual(first.runtimeMoves, [Point(x: 100, y: 50)])
        XCTAssertTrue(second.samples.isEmpty)
        XCTAssertTrue(second.runtimeMoves.isEmpty)
    }

    func testClosedHostRejectsCapturedInputBeforeAnyRuntimeMutation() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let input = try XCTUnwrap(fixture.window.capturePointerInput(.leftDown, at: Point(x: 200, y: 100)))
        fixture.host.windowWillClose(fixture.window)
        let invalidationsAfterClose = fixture.window.invalidateRequestCount

        fixture.window.deliverCapturedPointerInput(input)

        XCTAssertTrue(fixture.samples.isEmpty)
        XCTAssertEqual(fixture.runtimeDownCount, 0)
        XCTAssertEqual(fixture.window.invalidateRequestCount, invalidationsAfterClose)
        XCTAssertFalse(fixture.window.isDeliveringCapturedPointerInput(input))
    }

    func testLegacyAndNeutralDelegatesReceiveEachPhysicalPayloadOnce() async throws {
        let window = Win32Window(title: "Legacy capture", clientSize: IntSize(width: 640, height: 480))
        window.testScaleFactorOverride = 2
        var order: [String] = []
        var points: [Point] = []
        let legacy = LegacyDelegate { window, phase, point in
            order.append("legacy-\(phase)")
            points.append(point)
            window.testScaleFactorOverride = 1
        }
        let neutral = NeutralHost { phase, point in
            order.append("neutral-\(phase)")
            points.append(point)
        }
        window.delegate = legacy
        window.setPlatformWindowHost(neutral)
        let point = Point(x: 200, y: 100)

        for kind in [Win32CapturedPointerInput.Kind.moved, .leftDown, .leftUp] {
            let input = try XCTUnwrap(window.capturePointerInput(kind, at: point))
            window.deliverCapturedPointerInput(input)
        }

        XCTAssertEqual(
            order, ["legacy-move", "neutral-move", "legacy-down", "neutral-down", "legacy-up", "neutral-up"])
        XCTAssertEqual(points, Array(repeating: point, count: 6))
    }

    func testNeutralAdapterForwardsCapturedValueWithoutRecaptureOrLegacyDuplication() async throws {
        let fixture = Fixture()
        defer { fixture.finish() }
        let host = fixture.host
        var order: [String] = []
        var neutralPoints: [Point] = []
        let delegate = CapturedDelegate { window, input in
            order.append("captured")
            window.testScaleFactorOverride = 1
            host.window(window, capturedPointerInput: input)
        }
        let neutral = NeutralHost { phase, point in
            order.append("neutral-\(phase)")
            neutralPoints.append(point)
        }
        fixture.afterRouting = { order.append("retained") }
        fixture.window.delegate = delegate
        fixture.window.setPlatformWindowHost(neutral)
        let input = try XCTUnwrap(fixture.window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))

        fixture.window.deliverCapturedPointerInput(input)

        XCTAssertEqual(order, ["captured", "retained", "neutral-move"])
        XCTAssertEqual(delegate.legacyCount, 0)
        XCTAssertEqual(fixture.samples, [Sample(phase: "move", point: Point(x: 100, y: 50), scale: 2)])
        XCTAssertEqual(neutralPoints, [Point(x: 200, y: 100)])
    }

    func testNestedLegacyAndNeutralDeliveryKeepTheExistingOrder() async throws {
        let window = Win32Window(title: "Nested legacy capture", clientSize: IntSize(width: 640, height: 480))
        window.testScaleFactorOverride = 2
        var order: [String] = []
        var didNest = false
        let legacy = LegacyDelegate { window, _, _ in
            order.append(didNest ? "legacy-inner" : "legacy-outer")
            guard !didNest else { return }
            didNest = true
            guard let inner = window.capturePointerInput(.moved, at: Point(x: 20, y: 30)) else {
                return XCTFail("The nested legacy input must be capturable.")
            }
            window.deliverCapturedPointerInput(inner)
        }
        let neutral = NeutralHost { _, point in
            order.append(point.x == 20 ? "neutral-inner" : "neutral-outer")
        }
        window.delegate = legacy
        window.setPlatformWindowHost(neutral)
        let outer = try XCTUnwrap(window.capturePointerInput(.moved, at: Point(x: 200, y: 100)))

        window.deliverCapturedPointerInput(outer)

        XCTAssertEqual(order, ["legacy-outer", "legacy-inner", "neutral-inner", "neutral-outer"])
    }
}
