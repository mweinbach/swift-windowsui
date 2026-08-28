import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class NativeBitmapFontDrawCaptureTests: XCTestCase {
    func testEmptyCaptureHasNoDrawsOrIncompleteFaces() async {
        let capture = NativeBitmapFontDrawCapture()

        XCTAssertTrue(capture.faces.isEmpty)
        XCTAssertEqual(capture.drawCount, 0)
        XCTAssertEqual(capture.drawFailures, 0)
        XCTAssertFalse(capture.truncated)
    }

    func testDuplicateFaceRetainsOnceAndCaptureReleasesOnlyItsReference() async {
        let face = BitmapCaptureFakeFace()
        var capture: NativeBitmapFontDrawCapture? = NativeBitmapFontDrawCapture()
        for _ in 0..<3 {
            capture?.recordDraw(fontFace: face.rawPointer, result: 0)
        }

        XCTAssertEqual(capture?.faces.map(\.rawPointer), [face.rawPointer])
        XCTAssertEqual(capture?.drawCount, 3)
        XCTAssertEqual(capture?.drawFailures, 0)
        XCTAssertEqual(capture?.truncated, false)
        XCTAssertEqual(face.state.addRefCalls, 1)
        XCTAssertEqual(face.state.referenceCount, 2)

        capture = nil
        XCTAssertEqual(face.state.releaseCalls, 1)
        XCTAssertEqual(face.state.referenceCount, 1)
        XCTAssertFalse(face.state.destroyed)

        face.releaseOwner()
        XCTAssertEqual(face.state.releaseCalls, 2)
        XCTAssertEqual(face.state.referenceCount, 0)
        XCTAssertTrue(face.state.destroyed)
    }

    func testDistinctFaceCapDoesNotRetainRejectedFacesOrFlagDuplicates() async {
        let first = BitmapCaptureFakeFace()
        let second = BitmapCaptureFakeFace()
        let rejected = BitmapCaptureFakeFace()
        var capture: NativeBitmapFontDrawCapture? = NativeBitmapFontDrawCapture(maxFaces: 2)
        capture?.recordDraw(fontFace: first.rawPointer, result: 0)
        capture?.recordDraw(fontFace: second.rawPointer, result: 0)
        capture?.recordDraw(fontFace: first.rawPointer, result: 0)

        XCTAssertEqual(capture?.truncated, false, "A duplicate at capacity is already represented")
        capture?.recordDraw(fontFace: rejected.rawPointer, result: 0)
        capture?.recordDraw(fontFace: rejected.rawPointer, result: 0)
        capture?.recordDraw(fontFace: second.rawPointer, result: 0)

        XCTAssertEqual(capture?.faces.map(\.rawPointer), [first.rawPointer, second.rawPointer])
        XCTAssertEqual(capture?.drawCount, 6)
        XCTAssertEqual(capture?.drawFailures, 0)
        XCTAssertEqual(capture?.truncated, true)
        XCTAssertEqual(first.state.addRefCalls, 1)
        XCTAssertEqual(second.state.addRefCalls, 1)
        XCTAssertEqual(rejected.state.addRefCalls, 0)

        capture = nil
        XCTAssertEqual(first.state.releaseCalls, 1)
        XCTAssertEqual(second.state.releaseCalls, 1)
        XCTAssertEqual(rejected.state.releaseCalls, 0)
    }

    func testZeroAndNegativeLimitsDoNotRetainFaces() async {
        for limit in [0, -1, Int.min] {
            let face = BitmapCaptureFakeFace()
            let capture = NativeBitmapFontDrawCapture(maxFaces: limit)
            capture.recordDraw(fontFace: face.rawPointer, result: 0)
            capture.recordDraw(fontFace: face.rawPointer, result: -1)

            XCTAssertTrue(capture.faces.isEmpty)
            XCTAssertEqual(capture.drawCount, 2)
            XCTAssertEqual(capture.drawFailures, 1)
            XCTAssertTrue(capture.truncated)
            XCTAssertEqual(face.state.addRefCalls, 0)
            XCTAssertEqual(face.state.releaseCalls, 0)
            XCTAssertEqual(face.state.referenceCount, 1)
        }
    }

    func testDefaultAndOverlargeLimitsRetainAtMostEightFaces() async {
        let limits: [Int?] = [nil, 9, Int.max]
        for limit in limits {
            let faces = (0..<9).map { _ in BitmapCaptureFakeFace() }
            var capture: NativeBitmapFontDrawCapture? =
                limit.map { NativeBitmapFontDrawCapture(maxFaces: $0) } ?? NativeBitmapFontDrawCapture()
            for face in faces.prefix(8) {
                capture?.recordDraw(fontFace: face.rawPointer, result: 0)
            }
            XCTAssertEqual(capture?.truncated, false)
            capture?.recordDraw(fontFace: faces[8].rawPointer, result: 0)

            XCTAssertEqual(capture?.faces.map(\.rawPointer), faces.prefix(8).map(\.rawPointer))
            XCTAssertEqual(capture?.drawCount, 9)
            XCTAssertEqual(capture?.truncated, true)
            XCTAssertTrue(faces.prefix(8).allSatisfy { $0.state.addRefCalls == 1 })
            XCTAssertEqual(faces[8].state.addRefCalls, 0)

            capture = nil
            XCTAssertTrue(faces.prefix(8).allSatisfy { $0.state.releaseCalls == 1 })
            XCTAssertEqual(faces[8].state.releaseCalls, 0)
        }
    }

    func testHRESULTSignCountsFailuresAndFailedDrawStillRetainsActualFace() async {
        let successfulFace = BitmapCaptureFakeFace()
        let failedFace = BitmapCaptureFakeFace()
        let capture = NativeBitmapFontDrawCapture()
        let successes: [HRESULT] = [0, 1, .max]
        for result in successes {
            capture.recordDraw(fontFace: successfulFace.rawPointer, result: result)
        }
        let failures: [HRESULT] = [-1, .min]
        for result in failures {
            capture.recordDraw(fontFace: failedFace.rawPointer, result: result)
        }

        XCTAssertEqual(capture.drawCount, 5)
        XCTAssertEqual(capture.drawFailures, 2)
        XCTAssertEqual(capture.faces.map(\.rawPointer), [successfulFace.rawPointer, failedFace.rawPointer])
        XCTAssertFalse(capture.truncated, "Failure and missing face attribution are separate outcomes")
        XCTAssertEqual(successfulFace.state.addRefCalls, 1)
        XCTAssertEqual(failedFace.state.addRefCalls, 1)
    }

    func testMissingFacesMarkIncompleteAndDoNotConsumeFaceCapacity() async {
        let face = BitmapCaptureFakeFace()
        let capture = NativeBitmapFontDrawCapture(maxFaces: 1)
        capture.recordDraw(fontFace: nil, result: 0)
        XCTAssertEqual(capture.drawFailures, 0)
        XCTAssertTrue(capture.truncated)
        XCTAssertTrue(capture.faces.isEmpty)

        capture.recordDraw(fontFace: nil, result: -1)
        capture.recordDraw(fontFace: face.rawPointer, result: 0)
        XCTAssertEqual(capture.drawCount, 3)
        XCTAssertEqual(capture.drawFailures, 1)
        XCTAssertEqual(capture.faces.map(\.rawPointer), [face.rawPointer])
        XCTAssertTrue(capture.truncated)
        XCTAssertEqual(face.state.addRefCalls, 1)
    }

    func testRetainedHandleOutlivesBorrowerAndCaptureUntilLastSwiftReference() async {
        let face = BitmapCaptureFakeFace()
        let borrowedPointer = face.rawPointer
        var capture: NativeBitmapFontDrawCapture? = NativeBitmapFontDrawCapture()
        capture?.recordDraw(fontFace: borrowedPointer, result: 0)
        var retainedFace = capture?.faces.first

        face.releaseOwner()
        XCTAssertEqual(face.state.referenceCount, 1)
        XCTAssertFalse(face.state.destroyed)
        capture = nil
        XCTAssertEqual(face.state.releaseCalls, 1)
        XCTAssertEqual(face.state.referenceCount, 1)
        XCTAssertEqual(retainedFace?.rawPointer, borrowedPointer)
        XCTAssertEqual(face.state.addRefCalls, 1, "Copying the Swift handle must not add another COM reference")

        retainedFace = nil
        XCTAssertEqual(face.state.releaseCalls, 2)
        XCTAssertEqual(face.state.referenceCount, 0)
        XCTAssertTrue(face.state.destroyed)
    }

    func testDefaultObservationRasterOverrideReturnsExactBitmapOnce() async throws {
        NativeTextRenderer.resetTestingOverrides()
        defer { NativeTextRenderer.resetTestingOverrides() }
        let expected = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]))
        let style = PixelTextStyle(color: .white, nativeFontSize: 17)
        var calls = 0
        NativeTextRenderer.testingOverrides.rasterize = { text, receivedStyle, scale in
            calls += 1
            XCTAssertEqual(text, "Fixture")
            XCTAssertEqual(receivedStyle, style)
            XCTAssertEqual(scale, 1.25)
            return expected
        }

        let actual = try XCTUnwrap(NativeTextRenderer.rasterize("Fixture", style: style, scaleFactor: 1.25))
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.contentKey, expected.contentKey)
    }

    func testDefaultObservationNilRasterOverrideDoesNotFallThrough() async {
        NativeTextRenderer.resetTestingOverrides()
        defer { NativeTextRenderer.resetTestingOverrides() }
        var calls = 0
        NativeTextRenderer.testingOverrides.rasterize = { _, _, _ in
            calls += 1
            return nil
        }

        XCTAssertNil(NativeTextRenderer.rasterize("Fixture", style: PixelTextStyle(color: .white), scaleFactor: 1))
        XCTAssertEqual(calls, 1)
    }

    func testDefaultObservationFontAvailabilityKeepsCachedTrueAndFalseVerdicts() async {
        NativeFontAvailability.resetTestingOverrides()
        NativeFontAvailability.resetProbeCacheForTesting()
        defer {
            NativeFontAvailability.resetTestingOverrides()
            NativeFontAvailability.resetProbeCacheForTesting()
        }
        var probeCalls = 0
        NativeFontAvailability.testingOverrides.probe = { _, family in
            probeCalls += 1
            return family == "Available"
        }

        XCTAssertTrue(NativeFontAvailability.hasGlyph("A", fontFamily: "Available"))
        XCTAssertTrue(NativeFontAvailability.hasGlyph("A", fontFamily: "AVAILABLE"))
        XCTAssertFalse(NativeFontAvailability.hasGlyph("A", fontFamily: "Missing"))
        XCTAssertFalse(NativeFontAvailability.hasGlyph("A", fontFamily: "MISSING"))
        XCTAssertEqual(probeCalls, 2)
        XCTAssertEqual(NativeFontAvailability.probeCacheCountForTesting, 2)

        var overrideCalls = 0
        NativeFontAvailability.testingOverrides.hasGlyph = { _, _ in
            overrideCalls += 1
            return false
        }
        XCTAssertFalse(NativeFontAvailability.hasGlyph("A", fontFamily: "Available"))
        XCTAssertEqual(overrideCalls, 1)
        NativeFontAvailability.testingOverrides.hasGlyph = nil
        XCTAssertTrue(NativeFontAvailability.hasGlyph("A", fontFamily: "Available"))
        XCTAssertEqual(probeCalls, 2)
        XCTAssertEqual(NativeFontAvailability.probeCacheCountForTesting, 2)
    }
}

// Only the IUnknown prefix is implemented. NativeFontFaceHandle must use
// AddRef/Release, never any DirectWrite API, to manage these borrowed pointers.
private struct BitmapCaptureFakeVTable {
    var queryInterface: DWQueryInterfaceProc
    var addRef: DWAddRefProc
    var release: DWReleaseProc
}

private struct BitmapCaptureFakeObject {
    var vtable: UnsafeMutablePointer<BitmapCaptureFakeVTable>
    var state: UnsafeMutableRawPointer
}

private final class BitmapCaptureFakeState {
    var referenceCount: ULONG = 1
    var addRefCalls = 0
    var releaseCalls = 0
    var destroyed = false
}

private final class BitmapCaptureFakeFace {
    let state: BitmapCaptureFakeState
    private let object: UnsafeMutablePointer<BitmapCaptureFakeObject>
    private var ownsReference = true

    init() {
        let state = BitmapCaptureFakeState()
        let vtable = UnsafeMutablePointer<BitmapCaptureFakeVTable>.allocate(capacity: 1)
        vtable.initialize(
            to: BitmapCaptureFakeVTable(
                queryInterface: bitmapCaptureFakeQueryInterface,
                addRef: bitmapCaptureFakeAddRef,
                release: bitmapCaptureFakeRelease))
        let object = UnsafeMutablePointer<BitmapCaptureFakeObject>.allocate(capacity: 1)
        object.initialize(
            to: BitmapCaptureFakeObject(vtable: vtable, state: Unmanaged.passRetained(state).toOpaque()))
        self.state = state
        self.object = object
    }

    var rawPointer: UnsafeMutableRawPointer {
        precondition(!state.destroyed)
        return UnsafeMutableRawPointer(object)
    }

    func releaseOwner() {
        guard ownsReference else { return }
        ownsReference = false
        _ = bitmapCaptureFakeRelease(UnsafeMutableRawPointer(object))
    }

    deinit {
        if ownsReference {
            _ = bitmapCaptureFakeRelease(UnsafeMutableRawPointer(object))
        }
    }
}

private func bitmapCaptureFakeQueryInterface(
    _ object: UnsafeMutableRawPointer?, _ iid: UnsafePointer<GUID>?,
    _ result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    result?.pointee = nil
    return HRESULT(bitPattern: 0x8000_4002)
}

private func bitmapCaptureFakeAddRef(_ rawObject: UnsafeMutableRawPointer?) -> ULONG {
    guard let rawObject else { return 0 }
    let object = rawObject.assumingMemoryBound(to: BitmapCaptureFakeObject.self)
    let state = Unmanaged<BitmapCaptureFakeState>.fromOpaque(object.pointee.state).takeUnretainedValue()
    state.addRefCalls += 1
    state.referenceCount += 1
    return state.referenceCount
}

private func bitmapCaptureFakeRelease(_ rawObject: UnsafeMutableRawPointer?) -> ULONG {
    guard let rawObject else { return 0 }
    let object = rawObject.assumingMemoryBound(to: BitmapCaptureFakeObject.self)
    let statePointer = object.pointee.state
    let state = Unmanaged<BitmapCaptureFakeState>.fromOpaque(statePointer).takeUnretainedValue()
    state.releaseCalls += 1
    state.referenceCount -= 1
    let remaining = state.referenceCount
    if remaining == 0 {
        state.destroyed = true
        let vtable = object.pointee.vtable
        object.deinitialize(count: 1)
        object.deallocate()
        vtable.deinitialize(count: 1)
        vtable.deallocate()
        Unmanaged<BitmapCaptureFakeState>.fromOpaque(statePointer).release()
    }
    return remaining
}
