import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// L8-PRESENT: a pathological compositor must not slideshow the app.
//
// Measured on this machine (artifacts/perf/release-vsync.json, release build,
// RTX 5090, 1024x768 headless "Default Monitor" with no EDID):
// `Present(sync = 1)` blocked for 250.9 ms mean / 255.4 ms p50 per frame while
// the app's own frame cost was 0.6 ms, giving 4.05 fps and 49 frames in a
// ten-second run. The same run with presents unpaced
// (release-novsync.json) produced 1481 fps and a 0.028 ms p50 present, through
// the same renderer on the same machine — which is what proves the quarter
// second belongs to the compositor and not to this app.
//
// Every threshold below is stated against that measurement: 255 ms is 15.3
// vblank periods at 60 Hz, so any threshold between "more than a couple of
// vblanks" and "fifteen" separates the two populations. These tests drive the
// policy from a fake present clock, because the display that produces the
// pathology cannot be created inside a test.

@MainActor
final class PresentPacingWatchdogTests: XCTestCase {
    private static let sixtyHertz = 1.0 / 60.0
    /// What a healthy vblank-paced present costs: one display period.
    private static let healthyPresent = 1.0 / 60.0
    /// What this machine's compositor charged per present.
    private static let pathologicalPresent = 0.2554
    /// What the app itself costs per frame here.
    private static let appFrameCost = 0.0006

    private func makePolicy(
        configuration: PresentPacingPolicy.Configuration = .standard
    ) -> PresentPacingPolicy {
        PresentPacingPolicy(configuration: configuration, displayFrameInterval: Self.sixtyHertz)
    }

    /// Feeds `count` presents of the given cost, one per simulated display
    /// period, and returns the clock it left off at.
    @discardableResult
    private func feed(
        _ policy: inout PresentPacingPolicy,
        presentSeconds: Double,
        frameCostSeconds: Double = appFrameCost,
        count: Int,
        from startTime: Double = 1_000
    ) -> Double {
        var now = startTime
        for _ in 0..<count {
            now += max(presentSeconds, Self.sixtyHertz)
            policy.recordPresent(seconds: presentSeconds, frameCostSeconds: frameCostSeconds, at: now)
        }
        return now
    }

    // MARK: - The engage threshold

    func testAHealthyCompositorKeepsThePacingJob() async {
        var policy = makePolicy()
        feed(&policy, presentSeconds: Self.healthyPresent, count: 600)

        XCTAssertEqual(policy.mode, .displayPaced)
        XCTAssertTrue(policy.presentsOnVBlank, "A working vsync is the best frame clock in the system.")
        XCTAssertFalse(policy.requiresSelfPacing)
        XCTAssertEqual(policy.engagementCount, 0)
    }

    func testAQuarterSecondPresentTakesThePacingJobBack() async {
        var policy = makePolicy()
        feed(&policy, presentSeconds: Self.pathologicalPresent, count: 30)

        XCTAssertEqual(policy.mode, .selfPaced)
        XCTAssertFalse(
            policy.presentsOnVBlank,
            "A present that blocks for 15 vblanks is not a frame clock; sync = 0 is the only way off it."
        )
        XCTAssertTrue(policy.requiresSelfPacing, "Someone has to pace the frames once the compositor stops.")
        XCTAssertEqual(policy.engagementCount, 1)
    }

    func testTheWatchdogNeedsARunOfBlockedPresentsBeforeEngaging() async {
        var policy = makePolicy()
        // One present short of the run. A user must not lose vsync over five
        // bad frames when six is the bar.
        feed(&policy, presentSeconds: Self.pathologicalPresent, count: 5)

        XCTAssertEqual(policy.mode, .displayPaced)
        XCTAssertEqual(policy.engagementCount, 0)
    }

    /// The engage bar is a run *and* a time budget, so a present that is merely
    /// over the line does not engage as fast as one that is 15 vblanks over it.
    func testAMildlySlowPresentMustPersistLongerThanAPathologicalOne() async {
        var policy = makePolicy()
        // Three vblanks per present: over the 2.5x line, but six of them are a
        // fifth of a second and not yet worth losing vsync over.
        let mildlySlow = Self.sixtyHertz * 3
        feed(&policy, presentSeconds: mildlySlow, count: 6)
        XCTAssertEqual(policy.mode, .displayPaced, "Six mildly slow presents is 0.3 s of evidence, not 0.75 s.")

        feed(&policy, presentSeconds: mildlySlow, count: 12, from: 2_000)
        XCTAssertEqual(
            policy.mode,
            .selfPaced,
            "Sustained 20 fps presentation is still the compositor failing to pace us."
        )
    }

    /// The headline case, timed. On this machine each blocked present costs
    /// 255 ms, so a frame-counted window of 30 would have left the user
    /// watching a slideshow for 7.6 seconds before anything happened — which is
    /// what the first live run after this fix actually measured.
    func testThePathologicalCaseEngagesWithinTwoSecondsOfEvidence() async {
        var policy = makePolicy()
        var now = 1_000.0
        var elapsedUntilEngaged: Double?

        for _ in 0..<60 where elapsedUntilEngaged == nil {
            now += Self.pathologicalPresent
            policy.recordPresent(
                seconds: Self.pathologicalPresent, frameCostSeconds: Self.appFrameCost, at: now)
            if policy.mode == .selfPaced {
                elapsedUntilEngaged = now - 1_000
            }
        }

        XCTAssertNotNil(elapsedUntilEngaged)
        XCTAssertLessThanOrEqual(
            elapsedUntilEngaged ?? .infinity,
            2.0,
            "Evidence measured in frames is evidence measured in seconds when each frame costs a quarter of one."
        )
    }

    func testAnIsolatedStallNeverEngages() async {
        var policy = makePolicy()
        var now = 1_000.0
        // A hitch every tenth frame — a screen switch, an allocation, a driver
        // blip. The measured worst frame in a healthy run was 9.98 ms; this is
        // far worse than that and still must not cost the session its vsync.
        for index in 0..<600 {
            now += Self.sixtyHertz
            let cost = index % 10 == 0 ? 0.12 : Self.healthyPresent
            policy.recordPresent(seconds: cost, frameCostSeconds: Self.appFrameCost, at: now)
        }

        XCTAssertEqual(policy.mode, .displayPaced)
        XCTAssertEqual(policy.engagementCount, 0, "One stalled frame in ten is a hitch, not a broken compositor.")
    }

    func testAnAppThatCannotMakeTheCadenceIsNotACompositorProblem() async {
        var policy = makePolicy()
        // Presents block for a quarter second because *this* app took a third
        // of a second to produce the frame. Unpacing that would only queue
        // frames the GPU has not finished; the display is not the problem.
        feed(&policy, presentSeconds: Self.pathologicalPresent, frameCostSeconds: 0.3, count: 300)

        XCTAssertEqual(policy.mode, .displayPaced)
        XCTAssertEqual(policy.engagementCount, 0)
    }

    // MARK: - Hysteresis and the recovery probe

    func testEngagementDoesNotFlapWhileTheCompositorStaysBroken() async {
        var policy = makePolicy()
        var now = 1_000.0

        // Ten simulated seconds of a permanently broken compositor: every probe
        // stalls, so the policy must stay engaged and must not re-enter
        // `selfPaced` over and over as if it were re-deciding.
        for _ in 0..<600 {
            now += Self.sixtyHertz
            let cost = policy.presentsOnVBlank ? Self.pathologicalPresent : 0.00003
            policy.recordPresent(seconds: cost, frameCostSeconds: Self.appFrameCost, at: now)
        }

        XCTAssertEqual(policy.mode, .selfPaced)
        XCTAssertEqual(
            policy.engagementCount,
            1,
            "Engaging once and staying engaged is the whole point of the backoff."
        )
        XCTAssertGreaterThan(policy.probeCount, 0, "A broken compositor still has to be re-checked.")
        XCTAssertLessThan(
            policy.probeCount,
            10,
            "Probing costs a stalled frame each time; ten seconds must not buy ten of them."
        )
    }

    func testProbeBackoffGrowsAndIsCapped() async {
        var policy = makePolicy(
            configuration: PresentPacingPolicy.Configuration(
                initialProbeInterval: 1,
                maximumProbeInterval: 4,
                probeBackoffFactor: 2
            )
        )
        var now = feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)
        XCTAssertEqual(policy.mode, .selfPaced)
        XCTAssertEqual(policy.probeIntervalSeconds, 1, accuracy: 1e-9)

        var observedIntervals: [Double] = []
        for _ in 0..<200 {
            now += 0.25
            let cost = policy.presentsOnVBlank ? Self.pathologicalPresent : 0.00003
            policy.recordPresent(seconds: cost, frameCostSeconds: Self.appFrameCost, at: now)
            observedIntervals.append(policy.probeIntervalSeconds)
        }

        XCTAssertEqual(policy.mode, .selfPaced)
        XCTAssertEqual(
            policy.probeIntervalSeconds,
            4,
            accuracy: 1e-9,
            "The backoff must stop growing at the configured ceiling, not run away."
        )
        XCTAssertTrue(
            observedIntervals.contains(where: { abs($0 - 2) < 1e-9 }),
            "The ladder must actually climb: 1 s, then 2 s, then the 4 s cap."
        )
    }

    func testTheDisplayGetsThePacingJobBackWhenItStartsBehaving() async {
        var policy = makePolicy(
            configuration: PresentPacingPolicy.Configuration(initialProbeInterval: 1)
        )
        var now = feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)
        XCTAssertEqual(policy.mode, .selfPaced)

        // A self-paced frame after the probe came due opens the probe.
        now += 1.5
        policy.recordPresent(seconds: 0.00003, frameCostSeconds: Self.appFrameCost, at: now)
        XCTAssertEqual(policy.mode, .probingDisplay)
        XCTAssertTrue(policy.presentsOnVBlank, "The probe is a real paced present; that is what makes it a probe.")

        // The laptop just got docked to a real 60 Hz monitor. The probe's first
        // four presents drain into an empty queue and are discarded; the three
        // after them land on the vblank.
        for _ in 0..<7 {
            now += Self.sixtyHertz
            policy.recordPresent(seconds: Self.healthyPresent, frameCostSeconds: Self.appFrameCost, at: now)
        }

        XCTAssertEqual(policy.mode, .displayPaced)
        XCTAssertFalse(
            policy.requiresSelfPacing,
            "Once the display paces properly, the app must stop second-guessing it."
        )
        XCTAssertEqual(policy.probeIntervalSeconds, 1, accuracy: 1e-9, "A successful probe resets the ladder.")
    }

    /// The defect the live runs after this fix exposed, in two rounds. A
    /// one-frame probe passed on a 0.04 ms present that was followed by a
    /// 261 ms one; a four-frame probe then passed *twice* in a ten-second run,
    /// because DXGI queues three presents before `Present` has to wait for
    /// anything. Both handed the pacing job back to a compositor that
    /// immediately blocked again, and the measured session was 10.9 fps and
    /// then 20.3 fps instead of 60.
    func testAProbeIsNotFooledByAnEmptyPresentQueue() async {
        var policy = makePolicy(
            configuration: PresentPacingPolicy.Configuration(initialProbeInterval: 1)
        )
        var now = feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)

        now += 1.5
        policy.recordPresent(seconds: 0.00003, frameCostSeconds: Self.appFrameCost, at: now)
        XCTAssertEqual(policy.mode, .probingDisplay)

        // Four presents draining into an empty queue, exactly as measured.
        for _ in 0..<4 {
            now += 0.001
            policy.recordPresent(seconds: 0.00004, frameCostSeconds: Self.appFrameCost, at: now)
            XCTAssertEqual(
                policy.mode,
                .probingDisplay,
                "A present that queued rather than waited is not evidence the compositor recovered."
            )
        }

        // Then the truth, on the first frame the queue makes it wait.
        now += Self.pathologicalPresent
        policy.recordPresent(seconds: 0.261, frameCostSeconds: Self.appFrameCost, at: now)

        XCTAssertEqual(policy.mode, .selfPaced)
        XCTAssertEqual(policy.engagementCount, 1, "A failed probe is not a new engagement.")
    }

    func testAFailedProbeReturnsToSelfPacingAndBacksOff() async {
        var policy = makePolicy(
            configuration: PresentPacingPolicy.Configuration(initialProbeInterval: 1)
        )
        var now = feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)

        now += 1.5
        policy.recordPresent(seconds: 0.00003, frameCostSeconds: Self.appFrameCost, at: now)
        XCTAssertEqual(policy.mode, .probingDisplay)
        XCTAssertEqual(policy.probeCount, 1)

        for _ in 0..<4 {
            now += 0.001
            policy.recordPresent(seconds: 0.00004, frameCostSeconds: Self.appFrameCost, at: now)
        }
        now += Self.pathologicalPresent
        policy.recordPresent(seconds: Self.pathologicalPresent, frameCostSeconds: Self.appFrameCost, at: now)

        XCTAssertEqual(policy.mode, .selfPaced)
        XCTAssertEqual(policy.engagementCount, 1)
        XCTAssertEqual(policy.probeCount, 1)
        XCTAssertEqual(policy.probeIntervalSeconds, 2, accuracy: 1e-9, "A failed probe waits twice as long.")
    }

    // MARK: - Display changes

    func testADisplayChangeProbesImmediatelyInsteadOfWaitingOutTheBackoff() async {
        var policy = makePolicy(
            configuration: PresentPacingPolicy.Configuration(initialProbeInterval: 30)
        )
        var now = feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)
        XCTAssertEqual(policy.mode, .selfPaced)

        // Docked: 144 Hz, a different display entirely. The thing the policy
        // lost faith in is not the thing in front of it now, and the 30-second
        // backoff was earned by a monitor that is no longer attached.
        policy.setDisplayFrameInterval(1.0 / 144.0)
        XCTAssertEqual(policy.mode, .probingDisplay)

        for _ in 0..<7 {
            now += 1.0 / 144.0
            policy.recordPresent(seconds: 1.0 / 144.0, frameCostSeconds: Self.appFrameCost, at: now)
        }
        XCTAssertEqual(policy.mode, .displayPaced)
    }

    func testAnAbsurdDisplayPeriodIsClampedRatherThanBelieved() async {
        var policy = makePolicy()
        policy.setDisplayFrameInterval(0)
        XCTAssertEqual(policy.displayFrameInterval, Self.sixtyHertz, accuracy: 1e-9)

        policy.setDisplayFrameInterval(-1)
        XCTAssertEqual(policy.displayFrameInterval, Self.sixtyHertz, accuracy: 1e-9)

        policy.setDisplayFrameInterval(10)
        XCTAssertLessThanOrEqual(
            policy.displayFrameInterval,
            1.0 / 20.0,
            "A ten-second 'display period' would make every present look healthy forever."
        )
    }

    // MARK: - The explicit measurement override

    func testAnExplicitVSyncOverrideSuspendsTheWatchdogAndRestoresIt() async {
        var policy = makePolicy()

        policy.setUnsynchronizedByRequest(true)
        XCTAssertEqual(policy.mode, .unsynchronized)
        XCTAssertFalse(policy.presentsOnVBlank)
        XCTAssertFalse(
            policy.requiresSelfPacing,
            "A measurement run turned pacing off on purpose; re-imposing a frame gate would defeat it."
        )

        // Unpaced presents cost nothing and say nothing about a paced one.
        feed(&policy, presentSeconds: 0.00003, count: 300)
        XCTAssertEqual(policy.mode, .unsynchronized)
        XCTAssertEqual(policy.engagementCount, 0)

        policy.setUnsynchronizedByRequest(false)
        XCTAssertEqual(policy.mode, .displayPaced, "Lifting the override returns the watchdog's own state.")
    }

    func testTheOverrideRestoresSelfPacingWhenThatIsWhatItInterrupted() async {
        var policy = makePolicy()
        feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)
        XCTAssertEqual(policy.mode, .selfPaced)

        policy.setUnsynchronizedByRequest(true)
        policy.setUnsynchronizedByRequest(false)

        XCTAssertEqual(
            policy.mode,
            .selfPaced,
            "A measurement run must not hand a broken compositor the pacing job back on its way out."
        )
    }

    // MARK: - Reported status

    func testTheStatusReportsWhatTheWatchdogSaw() async {
        var policy = makePolicy()
        feed(&policy, presentSeconds: Self.pathologicalPresent, count: 30)

        let status = policy.status
        XCTAssertEqual(status.mode, .selfPaced)
        XCTAssertTrue(status.requiresSelfPacing)
        XCTAssertEqual(status.engagementCount, 1)
        XCTAssertEqual(status.displayFrameInterval, Self.sixtyHertz, accuracy: 1e-9)
        XCTAssertEqual(status.lastPresentSeconds, Self.pathologicalPresent, accuracy: 1e-9)
    }

    func testTheReportedMedianTracksTheWindow() async {
        var policy = makePolicy()
        feed(&policy, presentSeconds: Self.healthyPresent, count: 120)

        XCTAssertEqual(
            policy.status.medianPresentSeconds,
            Self.healthyPresent,
            accuracy: 1e-9,
            "The median is what a reader compares against the display period."
        )
    }

    // MARK: - Reset

    func testResetDropsTheEvidenceButNotTheDecision() async {
        var policy = makePolicy()
        feed(&policy, presentSeconds: Self.pathologicalPresent, count: 6)
        XCTAssertEqual(policy.mode, .selfPaced)

        // A device rebuild: the samples described a swap chain that is gone.
        policy.reset()

        XCTAssertEqual(
            policy.mode,
            .selfPaced,
            "A new swap chain on the same broken compositor must not start by slideshowing again."
        )
        XCTAssertEqual(policy.status.sampleCount, 0)
    }
}
