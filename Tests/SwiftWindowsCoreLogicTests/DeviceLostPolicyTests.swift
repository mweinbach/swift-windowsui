import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsRendererD3D11

/// WS-02: device loss is a classification, not a sign test.
///
/// Before this, one swap-chain owner recognised two device-lost HRESULTs,
/// logged them and returned *success* — telling the caller a frame reached
/// the screen when nothing had been recreated — while the other classified
/// nothing and threw on any negative value. Neither noticed
/// `DXGI_STATUS_OCCLUDED`, which is positive and so read as a clean present.
///
/// Everything the recovery path decides is a function from an HRESULT and an
/// attempt number to a value in `DeviceLostPolicy`, so all of it is provable
/// without a GPU. The rebuild itself is covered by `DeviceLossRecoveryTests`.
@MainActor
final class DeviceLostPolicyTests: XCTestCase {

    // MARK: - Present outcome

    func testDeviceLostHRESULTsClassifyAsDeviceLost() async {
        for hresult in [
            DeviceLostPolicy.deviceRemoved,
            DeviceLostPolicy.deviceReset,
            DeviceLostPolicy.deviceHung,
            DeviceLostPolicy.driverInternalError,
        ] {
            XCTAssertTrue(
                DeviceLostPolicy.isDeviceLost(hresult),
                "\(DeviceLostPolicy.describe(hresult)) must be recognised as device loss")
            XCTAssertEqual(
                DeviceLostPolicy.outcome(forPresent: hresult), .deviceLost,
                "\(DeviceLostPolicy.describe(hresult)) must drive the device rebuild path")
        }
    }

    func testOccludedIsThrottleNotCleanPresent() async {
        // 0x087A0001 is a *success* code, so a `hr >= 0` test reads it as a
        // presented frame and the loop keeps rendering invisible work at
        // whatever rate the timer fires — flip-model Present returns
        // immediately instead of blocking on vsync while occluded.
        XCTAssertGreaterThanOrEqual(DeviceLostPolicy.statusOccluded, 0)
        XCTAssertEqual(DeviceLostPolicy.outcome(forPresent: DeviceLostPolicy.statusOccluded), .occluded)
        XCTAssertFalse(DeviceLostPolicy.isDeviceLost(DeviceLostPolicy.statusOccluded))
    }

    func testSuccessAndOrdinaryFailureClassify() async {
        XCTAssertEqual(DeviceLostPolicy.outcome(forPresent: 0), .presented)
        XCTAssertEqual(DeviceLostPolicy.outcome(forPresent: 1), .presented)
        XCTAssertEqual(
            DeviceLostPolicy.outcome(forPresent: HRESULT(bitPattern: 0x8000_4005)), .failed,
            "E_FAIL is a real failure, not device loss")
        XCTAssertEqual(DeviceLostPolicy.outcome(forPresent: DeviceLostPolicy.outOfMemory), .failed)
    }

    // MARK: - Failure kind

    func testFailureKindSeparatesDeviceLossFromPermanentFromTransient() async {
        XCTAssertEqual(DeviceLostPolicy.failureKind(for: DeviceLostPolicy.deviceRemoved), .deviceLost)
        XCTAssertEqual(DeviceLostPolicy.failureKind(for: DeviceLostPolicy.deviceHung), .deviceLost)

        for hresult in [
            DeviceLostPolicy.unsupported,
            DeviceLostPolicy.notCurrentlyAvailable,
            DeviceLostPolicy.noInterface,
            DeviceLostPolicy.notImplemented,
        ] {
            XCTAssertEqual(
                DeviceLostPolicy.failureKind(for: hresult), .permanent,
                "\(DeviceLostPolicy.describe(hresult)) can never succeed on a later retry")
        }

        XCTAssertEqual(DeviceLostPolicy.failureKind(for: DeviceLostPolicy.outOfMemory), .transient)
        XCTAssertEqual(DeviceLostPolicy.failureKind(for: DeviceLostPolicy.wasStillDrawing), .transient)
    }

    // MARK: - Retry schedule

    func testBackoffIsMonotonicAndBounded() async {
        var previous = 0.0
        for attempt in 1...6 {
            let seconds = DeviceLostPolicy.backoffSeconds(forAttempt: attempt)
            XCTAssertGreaterThan(seconds, 0, "Recovery must wait; recreating instantly comes back blank")
            XCTAssertGreaterThanOrEqual(seconds, previous, "Backoff must not shrink as attempts pile up")
            XCTAssertLessThanOrEqual(seconds, 1.5, "A wedged adapter must not stall the UI thread indefinitely")
            previous = seconds
        }
        XCTAssertEqual(
            DeviceLostPolicy.backoffSeconds(forAttempt: 0),
            DeviceLostPolicy.backoffSeconds(forAttempt: 1),
            "A nonsensical attempt number must not produce a zero wait")
    }

    func testRecoveryBudgetIsBounded() async {
        XCTAssertGreaterThan(DeviceLostPolicy.maxRecoveryAttempts, 0)
        XCTAssertLessThanOrEqual(
            DeviceLostPolicy.maxRecoveryAttempts, 8,
            "A device-loss storm must reach the host in bounded time, not retry forever")
    }

    // MARK: - Typed failures reaching the host

    func testBackendErrorsClassifyThemselvesForTheHost() async {
        let lost = BatchRendererError(operation: "IDXGISwapChain1.Present", hresult: DeviceLostPolicy.deviceRemoved)
        XCTAssertEqual(lost.presentationFailureKind, .deviceLost)
        XCTAssertEqual(PresentationFailureKind.classifying(lost), .deviceLost)

        let frameLost = D3D11RendererError(
            operation: "IDXGISwapChain1.Present", hresult: DeviceLostPolicy.deviceReset)
        XCTAssertEqual(PresentationFailureKind.classifying(frameLost), .deviceLost)

        let permanent = BatchRendererError(operation: "CreateSwapChain", hresult: DeviceLostPolicy.unsupported)
        XCTAssertEqual(PresentationFailureKind.classifying(permanent), .permanent)
    }

    func testSceneContentFailuresAreDistinguishableFromDeviceFailures() async {
        // The recovery flap the host used to exhibit came from treating
        // "this one image will not upload" the same as "the GPU went away".
        let sceneContent = BatchRendererError(
            operation: "Resolve image resources",
            hresult: HRESULT(bitPattern: 0x8007_0057),
            details: "no bound resource",
            failureKind: .sceneContent
        )
        XCTAssertEqual(PresentationFailureKind.classifying(sceneContent), .sceneContent)
    }

    func testDeviceLossOutranksAnExplicitSceneContentClaim() async {
        // An atlas upload that fails with DEVICE_REMOVED is device loss, not
        // bad scene content — retrying the same scene on the same dead
        // adapter would fail identically.
        let error = BatchRendererError(
            operation: "ID3D11Device.CreateTexture2D(glyph atlas)",
            hresult: DeviceLostPolicy.deviceRemoved,
            failureKind: .sceneContent
        )
        XCTAssertEqual(error.presentationFailureKind, .deviceLost)
    }

    func testUnclassifiedErrorsAreTreatedAsTransient() async {
        struct Unknown: Error {}
        XCTAssertEqual(
            PresentationFailureKind.classifying(Unknown()), .transient,
            "An error a backend did not classify keeps the historical retry-with-backoff behaviour")
    }
}
