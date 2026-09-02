import XCTest

@testable import SwiftWindowsUI

final class LazyListUIARejectionDiagnosticsTests: XCTestCase {
    func testDisabledRecordingAndResetAreInert() {
        var diagnostics = RetainedLazyListUIARejectionDiagnostics()
        let original = diagnostics
        XCTAssertFalse(diagnostics.record(entry(1)))
        diagnostics.beginOperation()
        XCTAssertEqual(diagnostics, original)

        diagnostics.isEnabled = true
        XCTAssertTrue(diagnostics.record(entry(2)))
        diagnostics.isEnabled = false
        let disabled = diagnostics
        XCTAssertFalse(diagnostics.record(entry(3)))
        diagnostics.beginOperation()
        XCTAssertEqual(diagnostics, disabled)
    }

    func testEnabledRecordingHasOneFixedBoundAndResetsPerOperation() {
        var diagnostics = RetainedLazyListUIARejectionDiagnostics()
        diagnostics.isEnabled = true
        for index in 0..<128 {
            XCTAssertEqual(diagnostics.record(entry(UInt64(index))), index < 64)
        }
        XCTAssertEqual(RetainedLazyListUIARejectionDiagnostics.maximumEntries, 64)
        XCTAssertEqual(diagnostics.entries.count, 64)
        XCTAssertEqual(diagnostics.entries.first, entry(0))
        XCTAssertEqual(diagnostics.entries.last, entry(63))
        XCTAssertTrue(diagnostics.didDropEntries)

        diagnostics.beginOperation()
        XCTAssertTrue(diagnostics.entries.isEmpty)
        XCTAssertFalse(diagnostics.didDropEntries)
        XCTAssertTrue(diagnostics.record(entry(128)))
        XCTAssertEqual(diagnostics.entries, [entry(128)])
    }

    func testTransportLineContainsOnlyTheRecordedNativeScalars() {
        XCTAssertEqual(
            entry(7).line,
            "UIA_REJECTION site=queryResult phase=finalQuery pass=7 sequence=2 geometry=3"
                + " unmutated=Optional(3) mutation=4 rounds=5 remainingRounds=11 remainingElements=112")
    }

    private func entry(_ pass: UInt64) -> RetainedLazyListUIARejectionDiagnostics.Entry {
        .init(
            site: .queryResult, phase: .finalQuery, pass: pass, sequence: 2, geometry: 3,
            unmutatedGeometry: 3, mutation: 4, rounds: 5, remainingRounds: 11, remainingElements: 112)
    }
}
