import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics

// MARK: - Recorder

/// Collects consecutive presented frames from a live window and writes them
/// as a numbered image sequence with a manifest describing what changed
/// between each pair.
///
/// This exists because every animation claim in the suite rests on counters
/// and on values sampled out of the runtime, and none of those can fail the
/// way an animation actually fails. A fade that advances perfectly in the
/// runtime while the screen shows the start, one middle frame and the end
/// satisfies a timeline-sampling test completely, and looks like a step to
/// the person watching. Only the presented pixels can tell those apart.
///
/// The frames come from the backend's own render target, read back between
/// the last draw and the present — self-readback, not a desktop or window
/// capture, so the screenshot contract that forbids desktop capture is
/// intact and the bytes are the ones that went to the display.
///
/// Frames are held in memory and encoded when the run ends. Encoding
/// between two presents would add tens of milliseconds to the gap the
/// capture is measuring, which is the one distortion this tool cannot
/// afford: it would stretch the animation timeline it exists to observe.
@MainActor
final class MotionCaptureRecorder {
    struct CapturedFrame {
        var surface: BitmapSurface
        var presentedAt: Double
        /// The scripted step that was in flight when this frame presented.
        var step: String
        var hadActiveAnimations: Bool
    }

    private(set) var frames: [CapturedFrame] = []
    let frameLimit: Int

    init(frameLimit: Int) {
        self.frameLimit = max(4, frameLimit)
    }

    var isComplete: Bool { frames.count >= frameLimit }

    func record(_ surface: BitmapSurface, presentedAt: Double, step: String, hadActiveAnimations: Bool) {
        guard !isComplete else { return }
        frames.append(
            CapturedFrame(
                surface: surface,
                presentedAt: presentedAt,
                step: step,
                hadActiveAnimations: hadActiveAnimations
            )
        )
    }

    // MARK: - Writing

    /// Writes `frame-000.png` … and returns the manifest describing the
    /// sequence, for embedding in the diagnostics report.
    func write(to directory: String) throws -> [String: Any] {
        guard !frames.isEmpty else {
            return ["frameCount": 0, "note": "no frames were captured"]
        }

        let directoryURL = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var frameRecords: [[String: Any]] = []
        frameRecords.reserveCapacity(frames.count)
        var identicalToPrevious = 0
        var longestIdenticalRun = 0
        var currentIdenticalRun = 0
        // The same two counts restricted to frames the runtime said had an
        // animation in flight. An idle window repeating itself is correct
        // behaviour and dominates the whole-sequence counts; a window
        // repeating itself *while animating* is either a wasted present or a
        // dropped step, and it is the only version of the number worth
        // failing on.
        var identicalWhileAnimating = 0
        var longestIdenticalRunWhileAnimating = 0
        var currentIdenticalRunWhileAnimating = 0

        for (index, frame) in frames.enumerated() {
            let name = String(format: "frame-%03d.png", index)
            try frame.surface.writePNG(to: directoryURL.appendingPathComponent(name))

            var record: [String: Any] = [
                "index": index,
                "file": name,
                "step": frame.step,
                "hadActiveAnimations": frame.hadActiveAnimations,
            ]

            if index > 0 {
                let previous = frames[index - 1]
                record["msSincePrevious"] = (frame.presentedAt - previous.presentedAt) * 1000
                let difference = Self.difference(previous.surface, frame.surface)
                record["changedPixelCount"] = difference.changedPixelCount
                record["changedFraction"] = difference.changedFraction
                record["meanAbsoluteDeltaOverChangedPixels"] = difference.meanDeltaOverChanged
                record["maxAbsoluteDelta"] = difference.maxDelta
                if let bounds = difference.bounds {
                    record["changeBounds"] = [
                        "x": bounds.minX, "y": bounds.minY,
                        "width": bounds.maxX - bounds.minX + 1,
                        "height": bounds.maxY - bounds.minY + 1,
                    ]
                }
                if difference.changedPixelCount == 0 {
                    identicalToPrevious += 1
                    currentIdenticalRun += 1
                    longestIdenticalRun = max(longestIdenticalRun, currentIdenticalRun)
                    if frame.hadActiveAnimations {
                        identicalWhileAnimating += 1
                        currentIdenticalRunWhileAnimating += 1
                        longestIdenticalRunWhileAnimating = max(
                            longestIdenticalRunWhileAnimating, currentIdenticalRunWhileAnimating)
                    } else {
                        currentIdenticalRunWhileAnimating = 0
                    }
                } else {
                    currentIdenticalRun = 0
                    currentIdenticalRunWhileAnimating = 0
                }
            }

            frameRecords.append(record)
        }

        var manifest: [String: Any] = [
            "frameCount": frames.count,
            "directory": directory,
            "pixelSize": [
                "width": Int(frames[0].surface.width),
                "height": Int(frames[0].surface.height),
            ],
            // The numbers that decide whether the sequence shows motion or a
            // slideshow: how many frames repeated the one before them, and
            // the worst stretch of repeats. Read the `WhileAnimating` pair —
            // an idle window repeating itself is correct and dominates the
            // unrestricted counts.
            "framesIdenticalToPrevious": identicalToPrevious,
            "longestIdenticalRun": longestIdenticalRun,
            "framesIdenticalToPreviousWhileAnimating": identicalWhileAnimating,
            "longestIdenticalRunWhileAnimating": longestIdenticalRunWhileAnimating,
            "frames": frameRecords,
        ]

        var stepFrameCounts: [String: Int] = [:]
        for frame in frames {
            stepFrameCounts[frame.step, default: 0] += 1
        }
        manifest["framesPerStep"] = stepFrameCounts

        // The cadence the sequence was captured at. Without it every other
        // number here is unreadable: nine steps of one colour level is a
        // smooth fade at 16 ms a frame and a quarter-second freeze at 250,
        // and the images look identical either way.
        let gaps = zip(frames, frames.dropFirst())
            .map { ($1.presentedAt - $0.presentedAt) * 1000 }
            .sorted()
        if !gaps.isEmpty {
            manifest["medianFrameGapMs"] = gaps[gaps.count / 2]
            manifest["maxFrameGapMs"] = gaps[gaps.count - 1]
        }

        let data = try JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directoryURL.appendingPathComponent("manifest.json"), options: .atomic)

        // The report embeds the summary, not the per-frame table: the table
        // belongs next to the images it describes.
        manifest["frames"] = nil
        return manifest
    }

    // MARK: - Difference

    struct FrameDifference {
        var changedPixelCount: Int
        var changedFraction: Double
        var meanDeltaOverChanged: Double
        var maxDelta: Int
        var bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
    }

    /// Per-pixel maximum-channel difference between two frames of the same
    /// size, plus where the differences are.
    ///
    /// Colour channels only. Alpha is excluded because the swap chain is
    /// opaque and a premultiplied readback pins it at 255 — including it
    /// would only ever contribute zero, and reading it as motion on a
    /// backend that reports something else would be a false positive.
    static func difference(_ a: BitmapSurface, _ b: BitmapSurface) -> FrameDifference {
        guard a.width == b.width, a.height == b.height else {
            return FrameDifference(
                changedPixelCount: -1, changedFraction: 1, meanDeltaOverChanged: 0, maxDelta: 255,
                bounds: nil)
        }

        let width = Int(a.width)
        let height = Int(a.height)
        let aRow = Int(a.bytesPerRow)
        let bRow = Int(b.bytesPerRow)
        var changed = 0
        var deltaSum = 0
        var maxDelta = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        a.pixels.withUnsafeBytes { aBytes in
            b.pixels.withUnsafeBytes { bBytes in
                guard let aBase = aBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let bBase = bBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else {
                    return
                }
                for y in 0..<height {
                    let aLine = aBase + y * aRow
                    let bLine = bBase + y * bRow
                    for x in 0..<width {
                        let offset = x * 4
                        var delta = 0
                        for channel in 0..<3 {
                            let lhs = Int(aLine[offset + channel])
                            let rhs = Int(bLine[offset + channel])
                            delta = max(delta, abs(lhs - rhs))
                        }
                        guard delta > 0 else { continue }
                        changed += 1
                        deltaSum += delta
                        maxDelta = max(maxDelta, delta)
                        minX = min(minX, x)
                        maxX = max(maxX, x)
                        minY = min(minY, y)
                        maxY = max(maxY, y)
                    }
                }
            }
        }

        let total = width * height
        return FrameDifference(
            changedPixelCount: changed,
            changedFraction: total == 0 ? 0 : Double(changed) / Double(total),
            meanDeltaOverChanged: changed == 0 ? 0 : Double(deltaSum) / Double(changed),
            maxDelta: maxDelta,
            bounds: maxX < 0 ? nil : (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
        )
    }
}

// MARK: - Script

/// The scripted interaction a motion capture drives, expressed in captured
/// frames rather than wall-clock seconds.
///
/// Frames, because that is the axis the artifact is indexed on: "the fade
/// starts at frame 2 and the switch at frame 20" is checkable against the
/// images, and "the fade starts at 1.7 s" is not. It also makes the capture
/// independent of how fast the window happens to be running.
@MainActor
struct MotionCaptureScript {
    /// Frames of settled window before anything moves, so the sequence has a
    /// before-state to difference against.
    static let baselineFrames = 2
    static let hoverStartFrame = 2
    static let screenSwitchFrame = 20
    static let controlActivateFrame = 40

    enum Step: String {
        case baseline
        case hoverFade = "hover-fade"
        case screenSwitch = "screen-switch"
        case controlActivate = "control-activate"
    }

    private(set) var step: Step = .baseline

    /// Advances the script to the state that should be in flight for the
    /// *next* frame, given how many frames have been captured. Returns the
    /// action to perform, or nil when this frame starts nothing new.
    mutating func advance(capturedFrameCount: Int) -> Step? {
        switch capturedFrameCount {
        case Self.hoverStartFrame:
            step = .hoverFade
            return .hoverFade
        case Self.screenSwitchFrame:
            step = .screenSwitch
            return .screenSwitch
        case Self.controlActivateFrame:
            step = .controlActivate
            return .controlActivate
        default:
            return nil
        }
    }

    /// Picks the two points the script drives, from the controls the runtime
    /// says are actually pressable right now.
    ///
    /// `navigation` is the topmost row of controls — a tab bar or a sidebar —
    /// and the last of them, so a window already showing the first screen
    /// switches to a different one. `content` is the lowest control that is
    /// not in that row, which on any screen is somewhere in the page body.
    static func targets(from centers: [Point]) -> (navigation: Point?, content: Point?) {
        guard let topY = centers.map(\.y).min() else {
            return (nil, nil)
        }
        let navigationBandHeight = 4.0
        let navigation = centers.last { $0.y <= topY + navigationBandHeight }
        let content = centers.filter { $0.y > topY + navigationBandHeight }.max { $0.y < $1.y }
        return (navigation, content)
    }
}
