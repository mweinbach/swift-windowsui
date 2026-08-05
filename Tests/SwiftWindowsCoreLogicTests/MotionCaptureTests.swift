import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import WinSwiftUI

/// The machinery behind `--diagnostics-capture-motion`.
///
/// The capture itself needs a live swap chain, so what is testable here is
/// everything around it: that the flag is off unless asked for, that the
/// difference metric answers the question the manifest is read for, and that
/// the script's phase boundaries and target selection are what the artifact
/// claims they are.
@MainActor
final class MotionCaptureTests: XCTestCase {

    // MARK: - Configuration

    func testMotionCaptureIsOffUnlessAskedFor() async {
        guard let plain = LiveDiagnosticsConfiguration.fromCommandLine(["app", "--diagnostics"], environment: [:])
        else {
            return XCTFail("--diagnostics must produce a configuration")
        }
        XCTAssertFalse(
            plain.capturesMotion,
            "a full-surface readback on every frame is not something a normal run pays for")
    }

    func testMotionCaptureFlagsParse() async {
        guard
            let configuration = LiveDiagnosticsConfiguration.fromCommandLine(
                [
                    "app", "--diagnostics", "--diagnostics-capture-motion",
                    "--diagnostics-motion-frames", "24",
                    "--diagnostics-motion-output", "artifacts/elsewhere",
                ],
                environment: [:])
        else {
            return XCTFail("the capture flags must produce a configuration")
        }
        XCTAssertTrue(configuration.capturesMotion)
        XCTAssertEqual(configuration.motionFrameCount, 24)
        XCTAssertEqual(configuration.motionOutputDirectory, "artifacts/elsewhere")
    }

    /// A sequence of fewer than a handful of frames cannot show motion, so the
    /// count has a floor rather than honouring a nonsensical request.
    func testMotionFrameCountHasAFloor() async {
        guard
            let configuration = LiveDiagnosticsConfiguration.fromCommandLine(
                ["app", "--diagnostics", "--diagnostics-capture-motion", "--diagnostics-motion-frames", "0"],
                environment: [:])
        else {
            return XCTFail("the capture flags must produce a configuration")
        }
        XCTAssertGreaterThanOrEqual(configuration.motionFrameCount, 4)
    }

    // MARK: - Difference metric

    private func surface(width: Int, height: Int, fill: UInt8) -> BitmapSurface {
        BitmapSurface(
            width: Int32(width),
            height: Int32(height),
            bytesPerRow: Int32(width * 4),
            pixels: Data(repeating: fill, count: width * height * 4),
            format: .bgra8Premultiplied
        )
    }

    func testIdenticalFramesReportNoChange() async {
        let a = surface(width: 8, height: 4, fill: 40)
        let difference = MotionCaptureRecorder.difference(a, a)
        XCTAssertEqual(difference.changedPixelCount, 0)
        XCTAssertEqual(difference.changedFraction, 0, accuracy: 0.0001)
        XCTAssertNil(difference.bounds, "nothing changed, so there is nowhere for it to have changed")
    }

    /// The number the manifest is actually read for: a small step over a
    /// region, which is what one frame of a fade looks like.
    func testAOneLevelStepOverPartOfTheFrameIsMeasured() async {
        let before = surface(width: 8, height: 4, fill: 40)
        var pixels = before.pixels
        // Brighten the blue channel of the four pixels of row 2 by one level.
        for x in 2..<6 {
            pixels[(2 * 8 + x) * 4] = 41
        }
        let after = BitmapSurface(
            width: before.width, height: before.height, bytesPerRow: before.bytesPerRow,
            pixels: pixels, format: .bgra8Premultiplied)

        let difference = MotionCaptureRecorder.difference(before, after)
        XCTAssertEqual(difference.changedPixelCount, 4)
        XCTAssertEqual(difference.meanDeltaOverChanged, 1, accuracy: 0.0001)
        XCTAssertEqual(difference.maxDelta, 1)
        guard let bounds = difference.bounds else { return XCTFail("a change has a location") }
        XCTAssertEqual(bounds.minX, 2)
        XCTAssertEqual(bounds.maxX, 5)
        XCTAssertEqual(bounds.minY, 2)
        XCTAssertEqual(bounds.maxY, 2)
    }

    /// Alpha is excluded on purpose: the swap chain is opaque and a
    /// premultiplied readback pins it, so counting it could only ever produce
    /// motion that is not there.
    func testAlphaOnlyDifferencesAreNotCountedAsMotion() async {
        let before = surface(width: 4, height: 2, fill: 200)
        var pixels = before.pixels
        for index in stride(from: 3, to: pixels.count, by: 4) {
            pixels[index] = 128
        }
        let after = BitmapSurface(
            width: before.width, height: before.height, bytesPerRow: before.bytesPerRow,
            pixels: pixels, format: .bgra8Premultiplied)

        XCTAssertEqual(MotionCaptureRecorder.difference(before, after).changedPixelCount, 0)
    }

    // MARK: - Script

    /// The phase boundaries are indexed on captured frames so they can be
    /// checked against the images the run writes.
    func testTheScriptStepsAtItsDocumentedFrames() async {
        var script = MotionCaptureScript()
        XCTAssertEqual(script.step, .baseline)

        XCTAssertNil(script.advance(capturedFrameCount: 1), "nothing starts during the baseline")
        XCTAssertEqual(script.advance(capturedFrameCount: MotionCaptureScript.hoverStartFrame), .hoverFade)
        XCTAssertNil(script.advance(capturedFrameCount: MotionCaptureScript.hoverStartFrame + 1))
        XCTAssertEqual(script.step, .hoverFade, "and the step stays in flight between boundaries")
        XCTAssertEqual(script.advance(capturedFrameCount: MotionCaptureScript.screenSwitchFrame), .screenSwitch)
        XCTAssertEqual(
            script.advance(capturedFrameCount: MotionCaptureScript.controlActivateFrame), .controlActivate)
    }

    /// The navigation target is the *last* control in the topmost row, so a
    /// window already showing its first screen switches to a different one.
    func testTargetsPickTheLastNavigationControlAndTheLowestContentControl() async {
        let centers = [
            Point(x: 40, y: 20),  // first tab
            Point(x: 90, y: 20),  // second tab
            Point(x: 140, y: 20),  // third tab
            Point(x: 60, y: 200),
            Point(x: 60, y: 400),  // lowest content control
        ]
        let targets = MotionCaptureScript.targets(from: centers)
        XCTAssertEqual(targets.navigation?.x, 140)
        XCTAssertEqual(targets.content?.y, 400)
    }

    func testTargetsAreAbsentWhenNothingIsPressable() async {
        let targets = MotionCaptureScript.targets(from: [])
        XCTAssertNil(targets.navigation)
        XCTAssertNil(targets.content)
    }

    // MARK: - Recorder

    func testTheRecorderStopsAtItsFrameLimit() async {
        let recorder = MotionCaptureRecorder(frameLimit: 4)
        for index in 0..<10 {
            recorder.record(
                surface(width: 2, height: 2, fill: UInt8(index)),
                presentedAt: Double(index) / 60,
                step: "baseline",
                hadActiveAnimations: true
            )
        }
        XCTAssertEqual(recorder.frames.count, 4)
        XCTAssertTrue(recorder.isComplete)
    }

    /// The manifest is the readable half of the artifact, and the two summary
    /// numbers it exists for are the repeat counts.
    func testTheManifestReportsRepeatedFrames() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("motion-capture-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = MotionCaptureRecorder(frameLimit: 5)
        // Two distinct frames, then three repeats of the second — the last of
        // them after the animation has settled, so the restricted counts have
        // to come out one lower than the unrestricted ones.
        let fills: [UInt8] = [10, 20, 20, 20, 20]
        for (index, fill) in fills.enumerated() {
            recorder.record(
                surface(width: 4, height: 4, fill: fill),
                presentedAt: Double(index) / 60,
                step: "baseline",
                hadActiveAnimations: index < 4
            )
        }

        guard let manifest = try? recorder.write(to: directory.path) else {
            return XCTFail("the recorder must write its sequence")
        }
        XCTAssertEqual(manifest["frameCount"] as? Int, 5)
        XCTAssertEqual(manifest["framesIdenticalToPrevious"] as? Int, 3)
        XCTAssertEqual(manifest["longestIdenticalRun"] as? Int, 3)
        XCTAssertEqual(
            manifest["framesIdenticalToPreviousWhileAnimating"] as? Int, 2,
            "an idle repeat is correct behaviour and must not be counted against motion")
        XCTAssertEqual(manifest["longestIdenticalRunWhileAnimating"] as? Int, 2)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("frame-004.png").path),
            "the frames are written beside the manifest that describes them")
    }
}
