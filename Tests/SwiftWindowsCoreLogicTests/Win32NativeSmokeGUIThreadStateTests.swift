import XCTest

@testable import SwiftWindowsPlatform

/// Pure scalar controls; these never call the native reader or qualify an idle interval.
@MainActor
final class Win32NativeSmokeGUIThreadStateTests: XCTestCase {
    func testFailedQueryIgnoresCaretAndGUIFlags() async {
        for hasCaret in [false, true] {
            for matches in [false, true] {
                for flags in [UInt32(0), UInt32(0x1F), UInt32.max] {
                    XCTAssertEqual(
                        Win32NativeSmokeGUIThreadState.encode(
                            querySucceeded: false, hasCaret: hasCaret, matchesRecordedWindow: matches, flags: flags),
                        0)
                }
            }
        }
    }

    func testSuccessfulQueryWithoutCaretHasSuccessBitOnly() async {
        XCTAssertEqual(
            Win32NativeSmokeGUIThreadState.encode(
                querySucceeded: true, hasCaret: false, matchesRecordedWindow: false, flags: 0),
            0x80)
    }

    func testMatchingCaretRetainsClearVisibilityBit() async {
        XCTAssertEqual(
            Win32NativeSmokeGUIThreadState.encode(
                querySucceeded: true, hasCaret: true, matchesRecordedWindow: true, flags: 0),
            0xA0)
        XCTAssertEqual(
            Win32NativeSmokeGUIThreadState.encode(
                querySucceeded: true, hasCaret: true, matchesRecordedWindow: true, flags: 0x1E),
            0xBE)
    }

    func testMatchingVisibleCaretRetainsVisibilityBit() async {
        XCTAssertEqual(
            Win32NativeSmokeGUIThreadState.encode(
                querySucceeded: true, hasCaret: true, matchesRecordedWindow: true, flags: 1),
            0xA1)
    }

    func testDifferentReportedCaretHasSeparateAssociation() async {
        XCTAssertEqual(
            Win32NativeSmokeGUIThreadState.encode(
                querySucceeded: true, hasCaret: true, matchesRecordedWindow: false, flags: 0),
            0xC0)
        XCTAssertEqual(
            Win32NativeSmokeGUIThreadState.encode(
                querySucceeded: true, hasCaret: true, matchesRecordedWindow: false, flags: 1),
            0xC1)
    }

    func testKnownGUIFlagsArePreservedAndUnknownBitsAreDiscarded() async {
        for flags in UInt32(0)...UInt32(0x1F) {
            for unknown in [UInt32(0), UInt32(0x20), UInt32(0xFFFF_FFE0)] {
                XCTAssertEqual(
                    Win32NativeSmokeGUIThreadState.encode(
                        querySucceeded: true, hasCaret: true, matchesRecordedWindow: false, flags: flags | unknown),
                    0xC0 + UInt64(flags))
            }
        }
    }

    func testNoCaretTakesPrecedenceOverSpuriousRecordedWindowMatch() async {
        for flags in UInt32(0)...UInt32(0x1F) {
            XCTAssertEqual(
                Win32NativeSmokeGUIThreadState.encode(
                    querySucceeded: true, hasCaret: false, matchesRecordedWindow: true, flags: flags),
                0x80 + UInt64(flags))
        }
    }
}
