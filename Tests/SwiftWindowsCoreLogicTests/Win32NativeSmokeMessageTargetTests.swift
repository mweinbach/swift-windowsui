import Foundation
import XCTest

@testable import SwiftWindowsPlatform

/// Pure metadata and wire controls; no window is created and these are not native qualification evidence.
@MainActor
final class Win32NativeSmokeMessageTargetTests: XCTestCase {
    func testTargetCategoriesHaveFixedRawValues() async {
        XCTAssertEqual(Win32NativeSmokeMessageTarget.allCases.map(\.rawValue), [1, 2, 3, 4])
        XCTAssertEqual(Win32NativeSmokeMessageTarget.threadMessage.rawValue, 1)
        XCTAssertEqual(Win32NativeSmokeMessageTarget.controlWindow.rawValue, 2)
        XCTAssertEqual(Win32NativeSmokeMessageTarget.registeredWindow.rawValue, 3)
        XCTAssertEqual(Win32NativeSmokeMessageTarget.unmatchedWindow.rawValue, 4)
        XCTAssertNil(Win32NativeSmokeMessageTarget(rawValue: 0))
        XCTAssertNil(Win32NativeSmokeMessageTarget(rawValue: .max))
    }

    func testClassificationCoversAllBooleanInputsWithNilAndControlPrecedence() async {
        let cases: [(Bool, Bool, Bool, Win32NativeSmokeMessageTarget)] = [
            (false, false, false, .threadMessage),
            (false, false, true, .threadMessage),
            (false, true, false, .threadMessage),
            (false, true, true, .threadMessage),
            (true, false, false, .unmatchedWindow),
            (true, false, true, .registeredWindow),
            (true, true, false, .controlWindow),
            (true, true, true, .controlWindow),
        ]
        for (hasHandle, isControl, isRegistered, expected) in cases {
            XCTAssertEqual(
                Win32NativeSmokeMessageTarget.classify(
                    hasWindowHandle: hasHandle, matchesControlWindow: isControl,
                    matchesRegisteredWindow: isRegistered), expected)
        }
    }

    func testBothDispatchKindsEncodeTargetWithoutChangingMessageOrFlags() async throws {
        let kinds: [Win32NativeSmokeEventKind] = [.nativeMessageDispatched, .nativeDispatchReturned]
        for kind in kinds {
            for target in Win32NativeSmokeMessageTarget.allCases {
                for flags in [UInt32(1), UInt32(2)] {
                    let observation = Win32NativeSmokeObservation(runID: UUID())
                    XCTAssertTrue(observation.record(kind, value: 0x0118, auxiliary: target.rawValue, flags: flags))
                    let capture = observation.capture()
                    let row = try XCTUnwrap(try JSONSerialization.jsonObject(with: capture.trace) as? [String: Any])
                    XCTAssertEqual(
                        Set(row.keys),
                        Set([
                            "runID", "ordinal", "kind", "uptimeNanoseconds", "threadID", "value", "auxiliary", "flags",
                        ]))
                    XCTAssertEqual(try XCTUnwrap(row["kind"] as? NSNumber).uint16Value, kind.rawValue)
                    XCTAssertEqual(try XCTUnwrap(row["value"] as? NSNumber).int64Value, 0x0118)
                    XCTAssertEqual(try XCTUnwrap(row["auxiliary"] as? NSNumber).uint64Value, target.rawValue)
                    XCTAssertEqual(try XCTUnwrap(row["flags"] as? NSNumber).uint32Value, flags)
                    XCTAssertEqual(capture.snapshot.recordCount, 1)
                    XCTAssertEqual(capture.snapshot.encodedBytes, capture.trace.count)
                    let encoded = try XCTUnwrap(String(data: capture.trace, encoding: .utf8))
                    let token = ",\"auxiliary\":\(target.rawValue)"
                    XCTAssertEqual(token.utf8.count, 14)
                    XCTAssertEqual(encoded.components(separatedBy: token).count, 2)
                }
            }
        }
    }

    func testUnclassifiedDispatchRecordsKeepTheirExistingWireShape() async throws {
        for kind in [Win32NativeSmokeEventKind.nativeMessageDispatched, .nativeDispatchReturned] {
            let observation = Win32NativeSmokeObservation(runID: UUID())
            XCTAssertTrue(observation.record(kind, value: 0x0118, flags: 2))
            let capture = observation.capture()
            let row = try XCTUnwrap(try JSONSerialization.jsonObject(with: capture.trace) as? [String: Any])
            XCTAssertEqual(
                Set(row.keys), Set(["runID", "ordinal", "kind", "uptimeNanoseconds", "threadID", "value", "flags"]))
            XCTAssertNil(row["auxiliary"])
            XCTAssertEqual(try XCTUnwrap(row["kind"] as? NSNumber).uint16Value, kind.rawValue)
            XCTAssertEqual(try XCTUnwrap(row["value"] as? NSNumber).int64Value, 0x0118)
            XCTAssertEqual(try XCTUnwrap(row["flags"] as? NSNumber).uint32Value, 2)
            XCTAssertFalse(try XCTUnwrap(String(data: capture.trace, encoding: .utf8)).contains("auxiliary"))
        }
    }
}
