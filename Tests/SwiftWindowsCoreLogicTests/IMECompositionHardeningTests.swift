import Foundation
import SwiftWindowsCore
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform

/// Hostile-input tests for IME composition translation. Composition strings
/// come from the active IME (third-party code in the input path), so the
/// translation layer must tolerate absent, empty, embedded-null, and
/// oversized strings, and garbage message flags, without crashing or
/// emitting phantom events. Tests drive the injectable
/// `IMECompositionContextProvider` seam — no live IME is involved.
final class IMECompositionHardeningTests: XCTestCase {

    private final class FakeProvider: IMECompositionContextProvider, @unchecked Sendable {
        var composition: String?
        var result: String?
        var positions: [Point] = []

        func compositionString(window hwnd: HWND?) -> String? { composition }
        func resultString(window hwnd: HWND?) -> String? { result }
        func setCompositionWindowPosition(_ point: Point, window hwnd: HWND?) {
            positions.append(point)
        }
    }

    // GCS_COMPSTR = 0x0008, GCS_RESULTSTR = 0x0800 (see imm.h).

    func testAbsentStringsProduceNoEventsDespiteFlags() async {
        let provider = FakeProvider()
        let events = await Win32Window.imeCompositionEvents(lParam: 0x0008 | 0x0800, provider: provider, hwnd: nil)
        XCTAssertEqual(events, [])
    }

    func testEmptyCompositionStringStillDeliversUpdate() async {
        // Backspacing to an empty composition is legal; the update must flow
        // so marked text clears.
        let provider = FakeProvider()
        provider.composition = ""
        let events = await Win32Window.imeCompositionEvents(lParam: 0x0008, provider: provider, hwnd: nil)
        XCTAssertEqual(events, [IMECompositionEvent(phase: .updated(""))])
    }

    func testEmbeddedNullsAndControlCharactersPassThroughWithoutCrashing() async {
        // The translation layer is a pipe, not a filter: hostile code units
        // must survive the round trip without crashing or corrupting events.
        let provider = FakeProvider()
        provider.composition = "a\0b\u{1}\u{7F}"
        provider.result = "\0\0"
        let events = await Win32Window.imeCompositionEvents(lParam: 0x0008 | 0x0800, provider: provider, hwnd: nil)
        XCTAssertEqual(
            events,
            [
                IMECompositionEvent(phase: .updated("a\0b\u{1}\u{7F}")),
                IMECompositionEvent(phase: .committed("\0\0")),
            ])
    }

    func testOversizedCompositionStringPassesThroughBounded() async {
        // A pathological IME reporting a huge composition must not crash the
        // translation; the string is passed through as-is.
        let provider = FakeProvider()
        let large = String(repeating: "あ", count: 100_000)
        provider.composition = large
        let events = await Win32Window.imeCompositionEvents(lParam: 0x0008, provider: provider, hwnd: nil)
        XCTAssertEqual(events, [IMECompositionEvent(phase: .updated(large))])
    }

    func testGarbageLParamBitsProduceNoPhantomEvents() async {
        // Every documented string flag unset: no events, whatever else is set.
        let provider = FakeProvider()
        provider.composition = "a"
        provider.result = "b"
        // All bits except GCS_COMPSTR (0x0008) and GCS_RESULTSTR (0x0800).
        let lParam = LPARAM(bitPattern: UInt64(0xFFFF_FFFF) & ~UInt64(0x0008) & ~UInt64(0x0800))
        let events = await Win32Window.imeCompositionEvents(lParam: lParam, provider: provider, hwnd: nil)
        XCTAssertEqual(events, [])
    }

    func testNegativeLParamDoesNotCrashTranslation() async {
        let provider = FakeProvider()
        provider.composition = "x"
        provider.result = "y"
        // -1 sets every bit, including both string flags.
        let events = await Win32Window.imeCompositionEvents(lParam: -1, provider: provider, hwnd: nil)
        XCTAssertEqual(
            events,
            [
                IMECompositionEvent(phase: .updated("x")),
                IMECompositionEvent(phase: .committed("y")),
            ])
    }

    func testWin32ProviderFailsClosedWithoutWindow() async {
        // No window handle: the live provider must return nil instead of
        // calling IMM32 with a nil HWND.
        let provider = Win32IMECompositionContextProvider()
        XCTAssertNil(provider.compositionString(window: nil))
        XCTAssertNil(provider.resultString(window: nil))
        provider.setCompositionWindowPosition(Point(x: 10, y: 10), window: nil)  // must not crash
    }
}
