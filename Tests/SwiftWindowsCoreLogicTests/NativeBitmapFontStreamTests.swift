import CDirect2DInterop
import Foundation
import WinSDK
import XCTest

@testable import SwiftWindowsUI

/// Projection fixtures are synthetic POD values, never font bytes. The fake
/// COM fixtures below stop before local-path approval or stream creation.
@MainActor
final class NativeBitmapFontStreamTests: XCTestCase {
    func testBudgetHasFixedLimitsAndChargesFailedRequestsWithoutRefunds() async {
        var budget = NativeBitmapFontStreamBudget()
        XCTAssertEqual(NativeBitmapFontStreamBudget.maximumFileBytes, 16_777_216)
        XCTAssertEqual(NativeBitmapFontStreamBudget.maximumSessionBytes, 67_108_864)
        XCTAssertEqual(NativeBitmapFontStreamBudget.fragmentBytes, 65_536)
        XCTAssertEqual(NativeBitmapFontStreamBudget.maximumFileBytes, UInt64(SWU_BITMAP_FONT_MAX_FILE_BYTES))
        XCTAssertEqual(NativeBitmapFontStreamBudget.maximumSessionBytes, UInt64(SWU_BITMAP_FONT_MAX_SESSION_BYTES))
        XCTAssertEqual(NativeBitmapFontStreamBudget.fragmentBytes, UInt64(SWU_BITMAP_FONT_FRAGMENT_BYTES))
        XCTAssertTrue(budget.account(requested: 65_536, read: 0))
        XCTAssertTrue(budget.account(requested: 32, read: 32))
        XCTAssertEqual(budget.requestedBytes, 65_568)
        XCTAssertEqual(budget.readBytes, 32)
        XCTAssertEqual(budget.remainingRequestedBytes, 67_043_296)
    }

    func testInvalidAccountingStopsWorkWithoutInventingByteCounts() async {
        for values in [(UInt64(1), UInt64(2)), (UInt64.max, UInt64(0))] {
            var budget = NativeBitmapFontStreamBudget()
            XCTAssertTrue(budget.account(requested: 12, read: 4))
            XCTAssertFalse(budget.account(requested: values.0, read: values.1))
            XCTAssertEqual(budget.requestedBytes, 12)
            XCTAssertEqual(budget.readBytes, 4)
            XCTAssertEqual(budget.remainingRequestedBytes, 0)
            XCTAssertFalse(budget.account(requested: 1, read: 0))
        }
    }

    func testObservedEmptyAxesAreDistinctFromUnavailableAxes() async {
        var fixture = streamProjectionFixture()
        var budget = NativeBitmapFontStreamBudget()
        let observed = project(fixture, budget: &budget)
        XCTAssertEqual(observed.axes, [])
        XCTAssertEqual(observed.axesStatus, .observed)
        XCTAssertEqual(observed.hasVariations, false)
        fixture.face.axes_status = 2
        fixture.face.has_variations_value = 0
        let unavailable = project(fixture, budget: &budget)
        XCTAssertNil(unavailable.axes)
        XCTAssertEqual(unavailable.axesStatus, .unavailable)
        XCTAssertNil(unavailable.hasVariations)
    }

    func testAxesPreserveCanonicalOrderActualValuesAndIndependentVariationFlag() async {
        var fixture = streamProjectionFixture()
        fixture.axes = [streamAxis("wght", 425.5), streamAxis("opsz", 13), streamAxis("AB12", -2)]
        fixture.face.axis_count = UInt32(fixture.axes.count)
        fixture.face.has_variations = 0
        var budget = NativeBitmapFontStreamBudget()
        let result = project(fixture, budget: &budget)
        XCTAssertEqual(result.axes?.map(\.tag), fixture.axes.map(\.tag))
        XCTAssertEqual(result.axes?.map(\.value), [425.5, 13, -2])
        XCTAssertEqual(result.hasVariations, false, "Static axes are not evidence of a variable font")
        fixture.face.axes_status = 3
        fixture.face.axis_count = 0
        fixture.face.has_variations = 1
        let failed = project(fixture, budget: &budget)
        XCTAssertNil(failed.axes)
        XCTAssertEqual(failed.axesStatus, .failed)
        XCTAssertEqual(failed.hasVariations, true, "A separate successful HasVariations result survives")
    }

    func testAxisTagGrammarUsesLittleEndianLettersDigitsAndTrailingSpaces() async {
        XCTAssertEqual(streamTag("wght"), 0x7468_6777)
        for tag in ["wght", "opsz", "AB12", "A   ", "Ab1 "] {
            XCTAssertTrue(NativeBitmapFontMetadataResolver.validAxisTagV2(streamTag(tag)), tag)
        }
        for tag in ["1abc", " aBc", "a bC", "ab/c", "ab_c", "ab\0c", "ab\nc"] {
            XCTAssertFalse(NativeBitmapFontMetadataResolver.validAxisTagV2(streamTag(tag)), tag)
        }
        XCTAssertFalse(NativeBitmapFontMetadataResolver.validAxisTagV2(UInt32.max))
    }

    func testExactlyThirtyTwoAxesAndEightNonlocalFilesStayWithinMetadataCaps() async {
        var files = (0..<8).map { index in
            var file = streamNonlocalFile()
            file.index = UInt32(index)
            return file
        }
        var fixture = streamProjectionFixture(files: files)
        fixture.axes = (0..<32).map { streamAxis(String(format: "A%03d", $0), Float($0)) }
        fixture.face.axis_count = 32
        var budget = NativeBitmapFontStreamBudget()
        let result = project(fixture, budget: &budget)
        XCTAssertEqual(result.axes?.count, 32)
        XCTAssertEqual(result.axesStatus, .observed)
        XCTAssertEqual(result.files.count, 8)
        XCTAssertEqual(result.filesStatus, .partial)
        XCTAssertEqual(budget.requestedBytes, 0)
        var ninth = streamNonlocalFile()
        ninth.index = 8
        files.append(ninth)
        XCTAssertEqual(project(streamProjectionFixture(files: files), budget: &budget).filesStatus, .invalidValue)
    }

    func testInvalidAxesAreRejectedAsAWholeWithoutDroppingIndependentFiles() async {
        let cases = [
            [streamAxis("wght", .nan)],
            [streamAxis("wght", .infinity)],
            [streamAxis("wght", -.infinity)],
            [streamAxis("1bad", 1)],
            [streamAxis("wght", 1), streamAxis("wght", 2)],
        ]
        for axes in cases {
            var fixture = streamProjectionFixture(files: [streamObservedFile()])
            fixture.axes = axes
            fixture.face.axis_count = UInt32(axes.count)
            var budget = NativeBitmapFontStreamBudget()
            let result = project(fixture, budget: &budget)
            XCTAssertNil(result.axes)
            XCTAssertEqual(result.axesStatus, .invalidValue)
            XCTAssertEqual(result.filesStatus, .observed)
            XCTAssertNotNil(result.files.first?.sha256)
        }
    }

    func testAxisCountAndPresenceFlagsCannotTurnMalformedArraysIntoObservations() async {
        var fixture = streamProjectionFixture()
        for count in [UInt32(1), 33, UInt32.max] {
            fixture.face.axis_count = count
            var budget = NativeBitmapFontStreamBudget()
            let result = project(fixture, budget: &budget)
            XCTAssertNil(result.axes)
            XCTAssertEqual(result.axesStatus, .invalidValue)
        }
        fixture.face.axis_count = 0
        fixture.face.has_variations = 2
        var budget = NativeBitmapFontStreamBudget()
        XCTAssertEqual(project(fixture, budget: &budget).axesStatus, .invalidValue)
        fixture.face.axes_status = 99
        XCTAssertEqual(project(fixture, budget: &budget).axesStatus, .invalidValue)
    }

    func testCompleteObservationUsesOnlySafeReferenceDigestAndFixedMeaning() async throws {
        let fixture = streamProjectionFixture(files: [streamObservedFile()])
        var budget = NativeBitmapFontStreamBudget()
        let result = project(fixture, budget: &budget)
        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(result.faceType, 1)
        XCTAssertEqual(result.filesStatus, .observed)
        XCTAssertEqual(file.reference.scope, .systemFonts)
        XCTAssertEqual(file.reference.basename, "fixture.ttf")
        XCTAssertEqual(file.status, .observed)
        XCTAssertEqual(file.operation, "complete")
        XCTAssertEqual(file.codeDomain, "none")
        XCTAssertNil(file.code)
        XCTAssertEqual(file.streamLength, 16)
        XCTAssertEqual(file.requestedBytes, 16)
        XCTAssertEqual(file.readBytes, 16)
        XCTAssertEqual(file.sha256, "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
        XCTAssertEqual(file.observationKind, "face-file-stream-at-observation")
        XCTAssertEqual(file.loadedBytesDigest, "not-observed")
        XCTAssertEqual(budget.requestedBytes, 16)
        XCTAssertEqual(budget.readBytes, 16)
        let encoded = try JSONEncoder().encode(result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let encodedFiles = try XCTUnwrap(object["files"] as? [[String: Any]])
        XCTAssertEqual(encodedFiles.first?["sha256"] as? String, file.sha256)
        XCTAssertEqual(encodedFiles.first?["observationKind"] as? String, "face-file-stream-at-observation")
        XCTAssertEqual(encodedFiles.first?["loadedBytesDigest"] as? String, "not-observed")
        let json = String(decoding: encoded, as: UTF8.self)
        for forbidden in ["C:\\", "referenceKey", "fontBytes", "rawPointer", "glyphAtlas"] {
            XCTAssertFalse(json.contains(forbidden))
        }
    }

    func testHRESULTWin32AndNTSTATUSCodesRetainSignedValuesAndFailureStages() async throws {
        let cases: [(UInt32, UInt32, Int32)] = [
            (13, 1, Int32(bitPattern: 0x8000_4005)),
            (7, 2, 5),
            (14, 3, Int32(bitPattern: 0xC000_0001)),
        ]
        for (operation, domain, code) in cases {
            var raw = streamObservedFile()
            raw.status = 3
            raw.operation = operation
            raw.code_domain = domain
            raw.has_code = 1
            raw.code = code
            raw.has_sha256 = 0
            raw.requested_bytes = operation >= 13 ? 16 : 0
            raw.read_bytes = operation == 14 ? 16 : 0
            if operation < 10 {
                raw.has_stream_length = 0
                raw.stream_length = 0
            }
            var budget = NativeBitmapFontStreamBudget()
            let result = project(streamProjectionFixture(files: [raw]), budget: &budget)
            let file = try XCTUnwrap(result.files.first)
            XCTAssertEqual(file.status, .failed)
            XCTAssertEqual(file.code, code)
            XCTAssertEqual(file.codeDomain, ["none", "hresult", "win32", "ntstatus"][Int(domain)])
            XCTAssertEqual(file.operation, NativeBitmapFontMetadataResolver.streamOperationNamesV2[Int(operation)])
            XCTAssertNil(file.sha256)
            XCTAssertEqual(budget.requestedBytes, raw.requested_bytes)
            XCTAssertEqual(budget.readBytes, raw.read_bytes)
        }
    }

    func testFinalVerificationFailureKeepsReadCountsButNeverPublishesDigest() async throws {
        var raw = streamObservedFile()
        raw.status = 5
        raw.operation = 16
        raw.has_sha256 = 0
        var budget = NativeBitmapFontStreamBudget()
        let result = project(streamProjectionFixture(files: [raw]), budget: &budget)
        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(file.status, .invalidValue)
        XCTAssertEqual(file.readBytes, 16)
        XCTAssertEqual(file.requestedBytes, 16)
        XCTAssertNil(file.sha256)
        XCTAssertEqual(result.filesStatus, .partial)
    }

    func testOneFailedFileDoesNotDiscardAnotherObservedFileOrItsByteAccounting() async throws {
        var failed = streamObservedFile()
        failed.index = 1
        failed.status = 3
        failed.operation = 13
        failed.code_domain = 1
        failed.has_code = 1
        failed.code = Int32(bitPattern: 0x8000_4005)
        failed.has_sha256 = 0
        failed.read_bytes = 0
        var budget = NativeBitmapFontStreamBudget()
        let result = project(streamProjectionFixture(files: [streamObservedFile(), failed]), budget: &budget)
        XCTAssertEqual(result.filesStatus, .partial)
        XCTAssertEqual(result.files.count, 2)
        XCTAssertNotNil(result.files.first?.sha256)
        XCTAssertNil(result.files.last?.sha256)
        XCTAssertEqual(result.files.last?.status, .failed)
        XCTAssertEqual(budget.requestedBytes, 32)
        XCTAssertEqual(budget.readBytes, 16)
    }

    func testZeroAndOversizedLengthsRemainHonestRejectedMetadata() async throws {
        for length in [UInt64(0), NativeBitmapFontStreamBudget.maximumFileBytes + 1, UInt64.max] {
            var raw = streamObservedFile()
            raw.stream_length = length
            raw.status = length == 0 ? 5 : 4
            raw.operation = length == 0 ? 10 : 11
            raw.has_sha256 = 0
            raw.requested_bytes = 0
            raw.read_bytes = 0
            var budget = NativeBitmapFontStreamBudget()
            let result = project(streamProjectionFixture(files: [raw]), budget: &budget)
            let file = try XCTUnwrap(result.files.first)
            XCTAssertEqual(file.streamLength, length)
            XCTAssertNil(file.sha256)
            XCTAssertEqual(budget.requestedBytes, 0)
        }
    }

    func testFourMaximumFilesExhaustSessionAndAnotherClaimCannotExpandIt() async {
        let maximum = NativeBitmapFontStreamBudget.maximumFileBytes
        var budget = NativeBitmapFontStreamBudget()
        for _ in 0..<4 {
            let result = project(streamProjectionFixture(files: [streamObservedFile(length: maximum)]), budget: &budget)
            XCTAssertEqual(result.filesStatus, .observed)
        }
        XCTAssertEqual(budget.requestedBytes, NativeBitmapFontStreamBudget.maximumSessionBytes)
        XCTAssertEqual(budget.readBytes, NativeBitmapFontStreamBudget.maximumSessionBytes)
        XCTAssertEqual(budget.remainingRequestedBytes, 0)
        let rejected = project(streamProjectionFixture(files: [streamObservedFile(length: 1)]), budget: &budget)
        XCTAssertEqual(rejected.filesStatus, .invalidValue)
        XCTAssertTrue(rejected.files.isEmpty)
        XCTAssertEqual(budget.requestedBytes, NativeBitmapFontStreamBudget.maximumSessionBytes)
    }

    func testStreamLengthCannotAppearBeforeItsCallOrMasqueradeAsAnUnrelatedFailure() async {
        let changes: [(inout SWU_BitmapFontFileEvidenceV2) -> Void] = [
            { $0.operation = 9 },
            {
                $0.operation = 13
                $0.stream_length = 0
            },
            {
                $0.operation = 13
                $0.stream_length = NativeBitmapFontStreamBudget.maximumFileBytes + 1
            },
        ]
        for change in changes {
            var raw = streamObservedFile()
            raw.status = 3
            raw.has_sha256 = 0
            raw.requested_bytes = 0
            raw.read_bytes = 0
            change(&raw)
            var budget = NativeBitmapFontStreamBudget()
            let result = project(streamProjectionFixture(files: [raw]), budget: &budget)
            XCTAssertTrue(result.files.isEmpty)
            XCTAssertEqual(result.filesStatus, .invalidValue)
        }
    }

    func testMalformedBridgeCountersAndCountsStopFurtherReads() async {
        var badSum = streamProjectionFixture(files: [streamObservedFile()])
        badSum.face.requested_bytes += 1
        var badCount = streamProjectionFixture()
        badCount.face.file_count = UInt32.max
        var badFiles = streamProjectionFixture(files: [streamObservedFile()])
        badFiles.files[0].read_bytes += 1
        for fixture in [badSum, badCount, badFiles] {
            var budget = NativeBitmapFontStreamBudget()
            let result = project(fixture, budget: &budget)
            XCTAssertEqual(result.filesStatus, .invalidValue)
            XCTAssertTrue(result.files.isEmpty)
            XCTAssertEqual(budget.remainingRequestedBytes, 0)
            XCTAssertEqual(budget.requestedBytes, 0)
        }
    }

    func testPartialDigestUnknownEnumsAndContradictoryCodesCannotBecomeObserved() async {
        let changes: [(inout SWU_BitmapFontFileEvidenceV2) -> Void] = [
            { $0.has_sha256 = 0 },
            { $0.read_bytes -= 1 },
            { $0.status = 3 },
            { $0.operation = 99 },
            { $0.code_domain = 99 },
            {
                $0.code_domain = 1
                $0.has_code = 0
            },
            { $0.has_code = 1 },
            { $0.status = 99 },
            { $0.index = 1 },
            { $0.has_stream_length = 0 },
        ]
        for change in changes {
            var raw = streamObservedFile()
            change(&raw)
            var budget = NativeBitmapFontStreamBudget()
            let result = project(streamProjectionFixture(files: [raw]), budget: &budget)
            XCTAssertEqual(result.filesStatus, .invalidValue)
            XCTAssertTrue(result.files.isEmpty)
        }
    }

    func testPathLikeBasenamesAndMalformedUTF16NeverEnterEvidence() async {
        for basename in [
            #"C:\secret\fixture.ttf"#, "../fixture.ttf", "fixture.ttf:stream", "CON.ttf", "bad~1.ttf", "bad..ttf",
        ] {
            var raw = streamObservedFile()
            setStreamBasename(&raw, units: Array(basename.utf16))
            var budget = NativeBitmapFontStreamBudget()
            let result = project(streamProjectionFixture(files: [raw]), budget: &budget)
            XCTAssertTrue(result.files.isEmpty, basename)
            XCTAssertEqual(result.filesStatus, .invalidValue, basename)
        }
        for units in [[UInt16(0xD800), 46, 116, 116, 102], [102, 0, 46, 116, 116, 102]] {
            var raw = streamObservedFile()
            setStreamBasename(&raw, units: units)
            var budget = NativeBitmapFontStreamBudget()
            XCTAssertTrue(project(streamProjectionFixture(files: [raw]), budget: &budget).files.isEmpty)
        }
    }

    func testNonlocalRecordsCannotSmuggleAPathSizeOrReadAttempt() async {
        let changes: [(inout SWU_BitmapFontFileEvidenceV2) -> Void] = [
            { $0.scope = 1 },
            { setStreamBasename(&$0, units: Array("fixture.ttf".utf16)) },
            {
                $0.has_stream_length = 1
                $0.stream_length = 1
            },
            { $0.requested_bytes = 1 },
        ]
        for change in changes {
            var raw = streamNonlocalFile()
            change(&raw)
            var budget = NativeBitmapFontStreamBudget()
            XCTAssertTrue(project(streamProjectionFixture(files: [raw]), budget: &budget).files.isEmpty)
        }
    }

    func testFakeCustomLoaderIsRejectedBeforeAnyStreamAndEveryReferenceBalances() async throws {
        let fixture = StreamCOMFixture()
        let result = fixture.resolve()
        let file = try XCTUnwrap(result.files.first)
        XCTAssertEqual(result.faceType, 1)
        XCTAssertNil(result.axes)
        XCTAssertEqual(result.axesStatus, .unavailable)
        XCTAssertEqual(file.status, .nonlocalOrCustom)
        XCTAssertEqual(file.reference.status, .nonlocalOrCustom)
        XCTAssertEqual(file.operation, "query-local-loader")
        XCTAssertNil(file.streamLength)
        XCTAssertNil(file.sha256)
        XCTAssertEqual(file.requestedBytes, 0)
        XCTAssertEqual(fixture.loader.state.streamCalls, 0)
        XCTAssertFalse(fixture.loader.state.keyOwnerReferences.isEmpty)
        XCTAssertTrue(fixture.loader.state.keyOwnerReferences.allSatisfy { $0 > 1 })
        XCTAssertEqual(fixture.loader.state.queriedIIDs.count, 2)
        if fixture.loader.state.queriedIIDs.count == 2 {
            XCTAssertTrue(streamGUIDEqual(fixture.loader.state.queriedIIDs[0], streamRemoteLoaderIID()))
            XCTAssertTrue(streamGUIDEqual(fixture.loader.state.queriedIIDs[1], iidIDWriteLocalFontFileLoader))
        }
        fixture.assertBalanced()
    }

    func testFakeRemoteInterfaceIsRejectedWithoutCreatingItsStream() async throws {
        let fixture = StreamCOMFixture()
        fixture.loader.state.queryResult = fixture.loader.rawPointer
        fixture.loader.state.queryHRESULT = 0
        fixture.loader.state.resultIID = streamRemoteLoaderIID()
        let result = fixture.resolve()
        XCTAssertEqual(try XCTUnwrap(result.files.first).status, .nonlocalOrCustom)
        XCTAssertEqual(fixture.loader.state.streamCalls, 0)
        XCTAssertEqual(fixture.loader.state.queryCalls, 1, "The remote gate must precede local-loader approval")
        XCTAssertTrue(
            fixture.loader.state.queriedIIDs.first.map { streamGUIDEqual($0, streamRemoteLoaderIID()) } ?? false)
        fixture.assertBalanced()
    }

    func testFakeZeroAndExcessiveFileCountsNeverRequestAnOutputArray() async {
        for count in [UInt32(0), 9, UInt32.max] {
            let fixture = StreamCOMFixture()
            fixture.face.state.queriedCount = count
            let result = fixture.resolve()
            XCTAssertEqual(result.filesStatus, count == 0 ? .invalidValue : .limitExceeded)
            XCTAssertTrue(result.files.isEmpty)
            XCTAssertEqual(fixture.face.state.fillCalls, 0)
            XCTAssertEqual(fixture.file.state.keyCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testFakeChangedFileCountReleasesEveryOriginalOutputIncludingDuplicates() async {
        for returnedCount in [UInt32(0), 1, 3, UInt32.max] {
            let fixture = StreamCOMFixture()
            fixture.face.state.files = [fixture.file.rawPointer, fixture.file.rawPointer]
            fixture.face.state.filledCount = returnedCount
            let result = fixture.resolve()
            XCTAssertEqual(result.filesStatus, .invalidValue)
            XCTAssertTrue(result.files.isEmpty)
            XCTAssertEqual(fixture.file.state.addRefs, 2)
            XCTAssertEqual(fixture.file.state.releases, 2)
            XCTAssertEqual(fixture.file.state.keyCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testFakeFailedGetFilesReleasesDuplicateNonNullOutputs() async {
        let fixture = StreamCOMFixture()
        fixture.face.state.files = [fixture.file.rawPointer, fixture.file.rawPointer]
        fixture.face.state.fillHRESULT = HRESULT(bitPattern: 0x8000_4005)
        let result = fixture.resolve()
        XCTAssertEqual(result.filesStatus, .failed)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(fixture.file.state.addRefs, 2)
        XCTAssertEqual(fixture.file.state.releases, 2)
        fixture.assertBalanced()
    }

    func testFakeNullFileSlotReleasesOtherOutputsWithoutDereferencingTheNull() async {
        let fixture = StreamCOMFixture()
        fixture.face.state.files = [fixture.file.rawPointer, nil]
        let result = fixture.resolve()
        XCTAssertEqual(result.filesStatus, .invalidValue)
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(fixture.file.state.addRefs, 1)
        XCTAssertEqual(fixture.file.state.releases, 1)
        XCTAssertEqual(fixture.file.state.keyCalls, 0)
        fixture.assertBalanced()
    }

    func testFakeFailedFace5QueryReleasesItsOutputAndDoesNotEraseIndependentFileStatus() async throws {
        let fixture = StreamCOMFixture()
        fixture.face.state.queryResult = fixture.file.rawPointer
        fixture.face.state.queryHRESULT = HRESULT(bitPattern: 0x8000_4005)
        let result = fixture.resolve()
        XCTAssertEqual(result.axesStatus, .failed)
        XCTAssertNil(result.axes)
        XCTAssertEqual(try XCTUnwrap(result.files.first).status, .nonlocalOrCustom)
        XCTAssertEqual(fixture.file.state.addRefs, 2)
        XCTAssertEqual(fixture.file.state.releases, 2)
        fixture.assertBalanced()
    }

    func testFakeKeyLimitsRejectBeforeLoaderLookup() async throws {
        for count in [UInt32(0), 65_537, UInt32.max] {
            let fixture = StreamCOMFixture()
            fixture.file.state.keyLength = count
            let result = fixture.resolve()
            let file = try XCTUnwrap(result.files.first)
            XCTAssertEqual(file.status, count == 0 ? .invalidValue : .limitExceeded)
            XCTAssertEqual(file.operation, "get-reference-key")
            XCTAssertEqual(fixture.file.state.loaderCalls, 0)
            fixture.assertBalanced()
        }
    }

    func testFakeFailedLoaderAndQueryCallsStillReleaseReturnedInterfaces() async throws {
        for failQuery in [false, true] {
            let fixture = StreamCOMFixture()
            if failQuery {
                fixture.loader.state.queryResult = fixture.loader.rawPointer
                fixture.loader.state.queryHRESULT = HRESULT(bitPattern: 0x8000_4005)
            } else {
                fixture.file.state.loaderHRESULT = HRESULT(bitPattern: 0x8000_4005)
            }
            let result = fixture.resolve()
            XCTAssertEqual(try XCTUnwrap(result.files.first).status, .failed)
            XCTAssertEqual(fixture.loader.state.streamCalls, 0)
            fixture.assertBalanced()
        }
    }

    private func project(
        _ fixture: StreamProjectionFixture, budget: inout NativeBitmapFontStreamBudget
    ) -> NativeBitmapFontFaceEvidenceV2 {
        NativeBitmapFontMetadataResolver.projectV2(
            fixture.face, axes: fixture.axes, files: fixture.files, budget: &budget)
    }
}

private struct StreamProjectionFixture {
    var face: SWU_BitmapFontFaceEvidenceV2
    var axes: [SWU_BitmapFontAxisValueV2]
    var files: [SWU_BitmapFontFileEvidenceV2]
}

private func streamProjectionFixture(files: [SWU_BitmapFontFileEvidenceV2] = []) -> StreamProjectionFixture {
    var face = SWU_BitmapFontFaceEvidenceV2()
    face.has_face_type = 1
    face.face_type = 1
    face.axes_status = 0
    face.has_variations_value = 1
    face.files_status = files.isEmpty ? 2 : (files.allSatisfy { $0.status == 0 } ? 0 : 1)
    face.file_count = UInt32(files.count)
    face.requested_bytes = files.reduce(0) { $0 + $1.requested_bytes }
    face.read_bytes = files.reduce(0) { $0 + $1.read_bytes }
    return StreamProjectionFixture(face: face, axes: [], files: files)
}

private func streamObservedFile(length: UInt64 = 16) -> SWU_BitmapFontFileEvidenceV2 {
    var file = SWU_BitmapFontFileEvidenceV2()
    file.reference_status = 0
    file.scope = 1
    setStreamBasename(&file, units: Array("fixture.ttf".utf16))
    file.status = 0
    file.operation = 17
    file.has_stream_length = 1
    file.stream_length = length
    file.requested_bytes = length
    file.read_bytes = length
    file.has_sha256 = 1
    withUnsafeMutableBytes(of: &file.sha256) { bytes in
        for index in bytes.indices { bytes[index] = UInt8(index) }
    }
    return file
}

private func streamNonlocalFile() -> SWU_BitmapFontFileEvidenceV2 {
    var file = SWU_BitmapFontFileEvidenceV2()
    file.reference_status = 7
    file.status = 7
    file.operation = 4
    file.code_domain = 1
    file.has_code = 1
    file.code = Int32(bitPattern: 0x8000_4002)
    return file
}

private func setStreamBasename(_ file: inout SWU_BitmapFontFileEvidenceV2, units: [UInt16]) {
    file.basename_length = UInt32(units.count)
    withUnsafeMutableBytes(of: &file.basename) { bytes in
        let buffer = bytes.bindMemory(to: UInt16.self)
        for index in buffer.indices { buffer[index] = 0 }
        for index in 0..<min(units.count, buffer.count) { buffer[index] = units[index] }
    }
}

private func streamTag(_ value: String) -> UInt32 {
    Array(value.utf8).prefix(4).enumerated().reduce(0) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
}

private func streamAxis(_ tag: String, _ value: Float) -> SWU_BitmapFontAxisValueV2 {
    var axis = SWU_BitmapFontAxisValueV2()
    axis.tag = streamTag(tag)
    axis.value = value
    return axis
}

private final class StreamCOMState {
    var references: ULONG = 1
    var addRefs = 0
    var releases = 0
    var overReleased = false
    var queryCalls = 0
    var queriedIIDs: [GUID] = []
    var resultIID: GUID?
    var queryResult: UnsafeMutableRawPointer?
    var queryHRESULT = HRESULT(bitPattern: 0x8000_4002)
    var files: [UnsafeMutableRawPointer?] = []
    var queriedCount: UINT32?
    var filledCount: UINT32?
    var fillCalls = 0
    var fillHRESULT: HRESULT = 0
    var key: UnsafeRawPointer?
    var keyLength: UINT32 = 4
    var keyCalls = 0
    var loaderResult: UnsafeMutableRawPointer?
    var loaderHRESULT: HRESULT = 0
    var loaderCalls = 0
    var streamCalls = 0
    var keyOwner: StreamCOMState?
    var keyOwnerReferences: [ULONG] = []
}

private struct StreamCOMStorage {
    var vtable: UnsafeMutableRawPointer
    var state: UnsafeMutableRawPointer
}

private final class StreamCOMObject<Table> {
    let state = StreamCOMState()
    private let table: UnsafeMutablePointer<Table>
    private let storage: UnsafeMutablePointer<StreamCOMStorage>
    var rawPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(storage) }

    init(_ value: Table) {
        table = .allocate(capacity: 1)
        storage = .allocate(capacity: 1)
        table.initialize(to: value)
        storage.initialize(
            to: .init(vtable: UnsafeMutableRawPointer(table), state: Unmanaged.passUnretained(state).toOpaque()))
    }

    func assertBalanced(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state.references, 1, file: file, line: line)
        XCTAssertEqual(state.addRefs, state.releases, file: file, line: line)
        XCTAssertFalse(state.overReleased, file: file, line: line)
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
        table.deinitialize(count: 1)
        table.deallocate()
    }
}

private func streamCOMState(_ pointer: UnsafeMutableRawPointer?) -> StreamCOMState {
    let storage = pointer!.assumingMemoryBound(to: StreamCOMStorage.self)
    return Unmanaged<StreamCOMState>.fromOpaque(storage.pointee.state).takeUnretainedValue()
}

private func streamAddRef(_ pointer: UnsafeMutableRawPointer?) -> ULONG {
    let state = streamCOMState(pointer)
    state.addRefs += 1
    state.references += 1
    return state.references
}

private func streamRelease(_ pointer: UnsafeMutableRawPointer?) -> ULONG {
    let state = streamCOMState(pointer)
    state.releases += 1
    if state.references <= 1 { state.overReleased = true }
    if state.references > 0 { state.references -= 1 }
    return state.references
}

private func streamQuery(
    _ pointer: UnsafeMutableRawPointer?, _ iid: UnsafePointer<GUID>?,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = streamCOMState(pointer)
    state.queryCalls += 1
    if let iid { state.queriedIIDs.append(iid.pointee) }
    if let owner = state.keyOwner { state.keyOwnerReferences.append(owner.references) }
    output?.pointee = nil
    if let expected = state.resultIID,
        !(iid.map { streamGUIDEqual($0.pointee, expected) } ?? false)
    {
        return HRESULT(bitPattern: 0x8000_4002)
    }
    if let result = state.queryResult {
        _ = streamAddRef(result)
        output?.pointee = result
    }
    return state.queryHRESULT
}

private func streamRemoteLoaderIID() -> GUID {
    // Windows SDK 10.0.26100.0 um/dwrite_3.h, IDWriteRemoteFontFileLoader.
    makeGUID(
        data1: 0x6864_8C83, data2: 0x6EDE, data3: 0x46C0,
        data4: (0xAB, 0x46, 0x20, 0x08, 0x3A, 0x88, 0x7F, 0xDE))
}

private func streamGUIDEqual(_ left: GUID, _ right: GUID) -> Bool {
    withUnsafeBytes(of: left) { leftBytes in
        withUnsafeBytes(of: right) { leftBytes.elementsEqual($0) }
    }
}

private func streamGetFiles(
    _ pointer: UnsafeMutableRawPointer?, _ count: UnsafeMutablePointer<UINT32>?,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = streamCOMState(pointer)
    guard let output else {
        count?.pointee = state.queriedCount ?? UINT32(state.files.count)
        return 0
    }
    state.fillCalls += 1
    let capacity = Int(count?.pointee ?? 0)
    for index in 0..<min(capacity, state.files.count) {
        if let value = state.files[index] { _ = streamAddRef(value) }
        output[index] = state.files[index]
    }
    count?.pointee = state.filledCount ?? UINT32(state.files.count)
    return state.fillHRESULT
}

private func streamGetKey(
    _ pointer: UnsafeMutableRawPointer?, _ key: UnsafeMutablePointer<UnsafeRawPointer?>?,
    _ size: UnsafeMutablePointer<UINT32>?
) -> HRESULT {
    let state = streamCOMState(pointer)
    state.keyCalls += 1
    key?.pointee = state.key
    size?.pointee = state.keyLength
    return 0
}

private func streamGetLoader(
    _ pointer: UnsafeMutableRawPointer?, _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    let state = streamCOMState(pointer)
    state.loaderCalls += 1
    output?.pointee = nil
    if let loader = state.loaderResult {
        _ = streamAddRef(loader)
        output?.pointee = loader
    }
    return state.loaderHRESULT
}

private typealias StreamCreateProc =
    @convention(c) (
        UnsafeMutableRawPointer?, UnsafeRawPointer?, UINT32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> HRESULT

private func streamForbiddenCreate(
    _ pointer: UnsafeMutableRawPointer?, _ key: UnsafeRawPointer?, _ size: UINT32,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    streamCOMState(pointer).streamCalls += 1
    output?.pointee = nil
    return HRESULT(bitPattern: 0x8000_4001)
}

private final class StreamCOMFixture {
    let face: StreamCOMObject<SwiftWindowsUI.IDWriteFontFaceVtbl>
    let file: StreamCOMObject<SwiftWindowsUI.IDWriteFontFileVtbl>
    let loader: StreamCOMObject<SwiftWindowsUI.IDWriteFontFileLoaderVtbl>
    private let key: UnsafeMutablePointer<UInt8>

    init() {
        face = StreamCOMObject(
            SwiftWindowsUI.IDWriteFontFaceVtbl(
                QueryInterface: streamQuery, AddRef: streamAddRef, Release: streamRelease,
                GetType: { _ in 1 }, GetFiles: streamGetFiles, GetIndex: { _ in 0 }, GetSimulations: { _ in 0 }))
        file = StreamCOMObject(
            SwiftWindowsUI.IDWriteFontFileVtbl(
                QueryInterface: streamQuery, AddRef: streamAddRef, Release: streamRelease,
                GetReferenceKey: streamGetKey, GetLoader: streamGetLoader))
        loader = StreamCOMObject(
            SwiftWindowsUI.IDWriteFontFileLoaderVtbl(
                QueryInterface: streamQuery, AddRef: streamAddRef, Release: streamRelease,
                CreateStreamFromKey: unsafeBitCast(
                    streamForbiddenCreate as StreamCreateProc, to: UnsafeMutableRawPointer.self)))
        key = .allocate(capacity: 4)
        key.initialize(repeating: 0xA7, count: 4)
        file.state.key = UnsafeRawPointer(key)
        file.state.loaderResult = loader.rawPointer
        loader.state.keyOwner = file.state
        face.state.files = [file.rawPointer]
    }

    @MainActor
    func resolve() -> NativeBitmapFontFaceEvidenceV2 {
        var handle = NativeFontFaceHandle(face.rawPointer)
        var budget = NativeBitmapFontStreamBudget()
        let result = NativeBitmapFontMetadataResolver.resolveV2(handle!, budget: &budget)
        handle = nil
        return result
    }

    func assertBalanced(file sourceFile: StaticString = #filePath, line: UInt = #line) {
        face.assertBalanced(file: sourceFile, line: line)
        file.assertBalanced(file: sourceFile, line: line)
        loader.assertBalanced(file: sourceFile, line: line)
    }

    deinit {
        key.deinitialize(count: 4)
        key.deallocate()
    }
}
