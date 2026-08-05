/// Renderer-neutral policy for "who is pacing this app's frames".
///
/// A vsync-paced `Present` is a bargain: the app hands the compositor a frame
/// and the compositor blocks the caller until the display is ready for it. On
/// a working display that wait is at most one vblank period, and it is the
/// cheapest, most accurate frame clock in the system.
///
/// The bargain fails when the thing on the other end is not a display. A
/// headless session, a virtual monitor with no EDID, a remote-desktop
/// transport or a broken driver can block `Present(1)` for a quarter of a
/// second per frame — measured on this project at 252 ms p50 on a machine
/// whose own frame cost was 0.6 ms, through *both* renderers, which is what
/// proves it is not the renderer. The app is then a slideshow: 4 frames a
/// second, animations advancing in visible steps, and nothing in the app's own
/// numbers to explain it.
///
/// This type is the escape hatch. It watches what presents actually cost,
/// and when they cost pathologically more than the display period it takes the
/// pacing job back: presents stop waiting (`sync = 0`) and the host paces
/// frames from its own clock instead. It keeps probing, because the machine
/// that behaves this way at 09:00 is a laptop that gets docked to a real
/// monitor at 09:05.
///
/// Deliberately a value type with no clock, no threads and no platform types:
/// every decision here is a pure function of the samples fed to it, which is
/// what makes the policy testable against a fake present clock rather than
/// against a display nobody can reproduce.
public struct PresentPacingPolicy: Equatable, Sendable {
    /// Which clock is pacing presentation right now.
    public enum Mode: String, Equatable, Sendable, CaseIterable {
        /// `Present(1)`: the display is pacing us, and doing it properly.
        /// The normal, preferred state.
        case displayPaced
        /// `Present(1)` for one trial frame while otherwise self-paced — the
        /// recovery probe. Costs one potentially-stalled frame and is the only
        /// way to find out whether the compositor started behaving.
        case probingDisplay
        /// `Present(0)`: the compositor is not a usable clock, so the app
        /// paces itself. Frames are still limited to the display's cadence by
        /// the host's frame gate — this is not "render as fast as possible".
        case selfPaced
        /// Vsync was switched off by explicit request (a measurement run), not
        /// by the watchdog. The watchdog holds its judgement while this is set:
        /// an unpaced present says nothing about whether a paced one would
        /// block.
        case unsynchronized
    }

    /// Thresholds and timings. Defaults are the shipping policy; the
    /// initialiser exists so tests can compress a 30-frame window and a 2-second
    /// backoff into something a unit test can drive.
    public struct Configuration: Equatable, Sendable {
        /// Presents the reported median is taken over. Diagnostics only — the
        /// engage decision is made from the consecutive run below, because a
        /// window measured in *frames* is measured in 7.6 seconds when each
        /// frame costs a quarter of one.
        public var windowSize: Int
        /// Multiple of the display period one present must exceed to count as
        /// pathological. A healthy paced present blocks at most one vblank, or
        /// two when the app is running ahead of a two-buffer chain; 2.5 sits
        /// above everything a working compositor produces and an order of
        /// magnitude below the 15 vblanks measured on the broken one.
        public var engageMultiple: Double
        /// Consecutive pathological presents required before the watchdog acts.
        ///
        /// *Consecutive*, not a majority of a window: a compositor that has
        /// stopped pacing properly stalls every present, while a hitch — a
        /// screen switch, an allocation, a driver blip — is by definition
        /// surrounded by frames that were fine. One good present resets the
        /// count, which makes an isolated stall unable to accumulate however
        /// often it repeats.
        public var minimumConsecutiveBlockedPresents: Int
        /// Seconds of accumulated blocking those consecutive presents must add
        /// up to.
        ///
        /// The second half of the bar, and the one that keeps the count from
        /// being trigger-happy on a merely-busy compositor: six presents at
        /// 255 ms is 1.5 s of visible slideshow and engages immediately, while
        /// six presents at 45 ms is a quarter second and waits for more
        /// evidence.
        public var evidenceSeconds: Double
        /// Multiple of the display period a probe present must come in under
        /// for the display to get the pacing job back. Above `1.0` because a
        /// correct paced present *does* block for about one period.
        public var releaseMultiple: Double
        /// Paced presents a recovery probe throws away before it starts
        /// measuring.
        ///
        /// A probe cannot be one frame, and it cannot be three. DXGI queues up
        /// to `MaximumFrameLatency` — three by default — presents before
        /// `Present` has to wait for anything, so the first presents after a
        /// self-paced run measure the depth of an empty queue and not the
        /// display. Measured on this machine: a four-frame probe passed twice
        /// in one ten-second run, each time handing the pacing job back to a
        /// compositor that immediately blocked for 261 ms again. Four discarded
        /// frames is the queue depth plus one.
        public var probeWarmupFrames: Int
        /// Paced presents the probe judges after the warm-up. All of them must
        /// come in under ``releaseMultiple``; one that does not ends the probe.
        public var probeJudgedFrames: Int
        /// Delay from engaging (or from a failed probe) to the next probe.
        public var initialProbeInterval: Double
        /// Ceiling for the probe backoff. A compositor that is permanently
        /// broken pays one stalled frame per this interval, forever — that is
        /// the standing cost of being able to recover at all.
        public var maximumProbeInterval: Double
        /// How the probe interval grows after each failed probe.
        public var probeBackoffFactor: Double
        /// Consecutive failed probes after which the interval stops climbing
        /// the ladder and jumps straight to ``maximumProbeInterval``.
        ///
        /// A probe is not free: its judged presents block for whatever the
        /// broken compositor charges (~250 ms each here), and they must be
        /// *consecutive* paced presents — DXGI queues `MaximumFrameLatency`
        /// presents before `Present` waits, so spreading them across
        /// nonadjacent frames would re-empty the queue between judged frames
        /// and every one of them would measure queue depth instead of the
        /// display (the deception ``probeWarmupFrames`` exists for; see
        /// `PresentPacingWatchdogTests.testAProbeIsNotFooledByAnEmptyPresentQueue`).
        /// A probe stall is therefore irreducibly a contiguous ~1 s hitch,
        /// and the only real softener is probing less often once the evidence
        /// is strong. Two failed probes on the same display are strong
        /// evidence; a display *change* still probes immediately regardless
        /// of the backoff (`setDisplayFrameInterval`), so laziness here never
        /// delays recovery on dock.
        public var failedProbesBeforeBackoffCap: Int

        public init(
            windowSize: Int = 30,
            engageMultiple: Double = 2.5,
            minimumConsecutiveBlockedPresents: Int = 6,
            evidenceSeconds: Double = 0.75,
            releaseMultiple: Double = 1.5,
            probeWarmupFrames: Int = 4,
            probeJudgedFrames: Int = 3,
            initialProbeInterval: Double = 2.0,
            maximumProbeInterval: Double = 30.0,
            probeBackoffFactor: Double = 2.0,
            failedProbesBeforeBackoffCap: Int = 2
        ) {
            self.windowSize = max(1, windowSize)
            self.engageMultiple = max(1.0, engageMultiple)
            self.minimumConsecutiveBlockedPresents = max(1, minimumConsecutiveBlockedPresents)
            self.evidenceSeconds = max(0, evidenceSeconds)
            self.releaseMultiple = max(1.0, releaseMultiple)
            self.probeWarmupFrames = max(1, probeWarmupFrames)
            self.probeJudgedFrames = max(1, probeJudgedFrames)
            self.initialProbeInterval = max(0, initialProbeInterval)
            self.maximumProbeInterval = max(initialProbeInterval, maximumProbeInterval)
            self.probeBackoffFactor = max(1.0, probeBackoffFactor)
            self.failedProbesBeforeBackoffCap = max(1, failedProbesBeforeBackoffCap)
        }

        public static let standard = Configuration()
    }

    public private(set) var configuration: Configuration
    public private(set) var mode: Mode = .displayPaced
    /// The display period this policy is judging against, in seconds.
    public private(set) var displayFrameInterval: Double
    public private(set) var lastPresentSeconds: Double = 0
    /// Times the watchdog has taken the pacing job away from the display this
    /// session. A number above one means the mode flapped, which is what the
    /// probe backoff exists to prevent.
    public private(set) var engagementCount: Int = 0
    /// Recovery probes attempted this session.
    public private(set) var probeCount: Int = 0
    /// Presents observed since the last window reset.
    public private(set) var sampleCount: Int = 0
    /// Current probe backoff, in seconds.
    public private(set) var probeIntervalSeconds: Double

    /// Consecutive pathological presents seen, and the blocking they add up
    /// to. The engage decision is these two and nothing else.
    public private(set) var consecutiveBlockedPresents = 0
    public private(set) var consecutiveBlockedSeconds: Double = 0
    /// Recovery probes that have failed in a row on this display. Drives the
    /// backoff jump (``Configuration/failedProbesBeforeBackoffCap``); reset by
    /// a successful probe, a fresh engagement and a display change.
    public private(set) var consecutiveFailedProbes = 0
    /// Paced presents observed in the probe currently running.
    private var probeFramesObserved = 0

    /// Ring of recent present costs, for the reported median only.
    private var samples: [Double]
    private var writeIndex = 0
    private var filledCount = 0
    /// Scratch buffer the median is sorted in, allocated once. `status` is
    /// read once per frame by the host's pacing gate, and a frame loop that
    /// allocates and sorts to answer "am I self-paced" is a frame loop paying
    /// for its own diagnostics.
    private var medianScratch: [Double]
    private var windowMedianSeconds: Double = 0
    /// Absolute time of the next recovery probe, in the caller's clock domain.
    private var nextProbeAt: Double = 0
    /// Set while an explicit request holds vsync off, so the mode can be
    /// restored to the watchdog's own state when the request is lifted.
    private var modeBeforeUnsynchronizedRequest: Mode?

    public init(
        configuration: Configuration = .standard,
        displayFrameInterval: Double = 1.0 / 60.0
    ) {
        self.configuration = configuration
        self.displayFrameInterval = Self.sanitizedInterval(displayFrameInterval)
        self.probeIntervalSeconds = configuration.initialProbeInterval
        self.samples = Array(repeating: 0, count: configuration.windowSize)
        self.medianScratch = Array(repeating: 0, count: configuration.windowSize)
    }

    /// A display period no sane driver reports — 0, negative or absurd — would
    /// make every present look pathological (or none of them). Clamped to the
    /// range a real display can occupy: 1000 Hz to 20 Hz.
    private static func sanitizedInterval(_ seconds: Double) -> Double {
        guard seconds.isFinite, seconds > 0 else {
            return 1.0 / 60.0
        }
        return min(max(seconds, 1.0 / 1000.0), 1.0 / 20.0)
    }

    // MARK: - What the next present should do

    /// Whether the next `Present` should wait for vblank. The single question
    /// a backend asks this policy.
    public var presentsOnVBlank: Bool {
        switch mode {
        case .displayPaced, .probingDisplay:
            return true
        case .selfPaced, .unsynchronized:
            return false
        }
    }

    /// Whether an explicit override — not the watchdog — is holding vsync off.
    public var isUnsynchronizedByRequest: Bool {
        mode == .unsynchronized
    }

    /// Whether the host must pace frames from its own clock, because nothing
    /// else is going to.
    ///
    /// False in `.unsynchronized`: a measurement run asked for unpaced
    /// presents *in order to* measure the app's unpaced cost, and a frame gate
    /// would defeat the measurement it was turned on for.
    public var requiresSelfPacing: Bool {
        mode == .selfPaced || mode == .probingDisplay
    }

    // MARK: - Configuration changes

    /// The display changed — a different monitor, a refresh-rate change, a
    /// dock. Both are reasons to stop trusting the accumulated window, and a
    /// reason to probe immediately rather than waiting out the backoff: the
    /// thing the policy lost faith in is not the thing in front of it now.
    public mutating func setDisplayFrameInterval(_ seconds: Double) {
        let sanitized = Self.sanitizedInterval(seconds)
        guard sanitized != displayFrameInterval else {
            return
        }
        displayFrameInterval = sanitized
        clearWindow()
        probeIntervalSeconds = configuration.initialProbeInterval
        consecutiveFailedProbes = 0
        nextProbeAt = 0
        if mode == .selfPaced {
            mode = .probingDisplay
            probeFramesObserved = 0
            probeCount += 1
        }
    }

    /// Starts the session self-paced on the strength of a previous session's
    /// evidence, instead of re-earning it through a fresh slideshow.
    ///
    /// The engage bar exists to protect a healthy display from a trigger-happy
    /// watchdog, but it makes every launch on a permanently broken compositor
    /// pay ~1.5 s of blocked presents before pacing recovers — the same
    /// evidence, re-collected. A host that persisted the last session's
    /// decision calls this before the first present. Only a pristine policy
    /// adopts: once this session has evidence of its own — presents observed,
    /// an engagement, a probe — the memory is stale relative to what the
    /// policy has actually seen and is ignored.
    ///
    /// The adopted state schedules an immediate recovery probe (the display
    /// may have been fixed since last session, and the memory must not outlive
    /// the pathology), but seeds the backoff at its ceiling: the remembered
    /// evidence plus one failed confirmation probe is as strong as evidence
    /// gets, so a launch on a still-broken display pays one probe stall and
    /// then goes quiet for ``Configuration/maximumProbeInterval``. A probe
    /// that passes hands the display the pacing job back and resets the
    /// ladder, exactly as it does for an in-session engagement.
    public mutating func adoptRememberedSelfPacing() {
        guard mode == .displayPaced, engagementCount == 0, probeCount == 0, sampleCount == 0 else {
            return
        }

        mode = .selfPaced
        probeIntervalSeconds = configuration.maximumProbeInterval
        nextProbeAt = 0
        clearWindow()
    }

    /// Explicit vsync override, for measurement runs. While set, the watchdog
    /// records nothing and decides nothing; clearing it restores the mode the
    /// watchdog was in.
    public mutating func setUnsynchronizedByRequest(_ unsynchronized: Bool) {
        if unsynchronized {
            guard mode != .unsynchronized else { return }
            modeBeforeUnsynchronizedRequest = mode
            mode = .unsynchronized
            clearWindow()
        } else {
            guard mode == .unsynchronized else { return }
            mode = modeBeforeUnsynchronizedRequest ?? .displayPaced
            modeBeforeUnsynchronizedRequest = nil
            clearWindow()
        }
    }

    /// Drops the accumulated judgement without changing the mode. Called when
    /// the swap chain underneath the samples is gone — a device rebuild, a
    /// resize, a detach — because those presents describe a pipeline that no
    /// longer exists.
    public mutating func reset() {
        clearWindow()
    }

    // MARK: - Observation

    /// Feeds one completed present to the policy.
    ///
    /// - Parameters:
    ///   - seconds: wall-clock seconds spent inside `Present`.
    ///   - frameCostSeconds: seconds this frame spent doing the app's own work
    ///     (scene build and draw submission). The discriminator between "the
    ///     compositor is stalling us" and "we are too slow for the display".
    ///   - now: the caller's monotonic clock, used only for probe scheduling.
    public mutating func recordPresent(seconds: Double, frameCostSeconds: Double, at now: Double) {
        let presentSeconds = seconds.isFinite && seconds > 0 ? seconds : 0
        let frameSeconds = frameCostSeconds.isFinite && frameCostSeconds > 0 ? frameCostSeconds : 0
        lastPresentSeconds = presentSeconds

        switch mode {
        case .unsynchronized:
            return

        case .probingDisplay:
            observeProbe(presentSeconds: presentSeconds, at: now)

        case .selfPaced:
            if now >= nextProbeAt {
                mode = .probingDisplay
                probeFramesObserved = 0
                probeCount += 1
            }

        case .displayPaced:
            append(presentSeconds: presentSeconds)

            let isBlocked = presentSeconds > displayFrameInterval * configuration.engageMultiple
            // The app being the slow one is the case a present-cost test alone
            // cannot see: its presents block too, and unpacing them would only
            // queue frames the GPU has not finished. A frame that misses the
            // cadence by its own work breaks the run.
            let appKeepsUp = frameSeconds < displayFrameInterval
            guard isBlocked, appKeepsUp else {
                consecutiveBlockedPresents = 0
                consecutiveBlockedSeconds = 0
                return
            }

            consecutiveBlockedPresents += 1
            consecutiveBlockedSeconds += presentSeconds
            guard
                consecutiveBlockedPresents >= configuration.minimumConsecutiveBlockedPresents,
                consecutiveBlockedSeconds >= configuration.evidenceSeconds
            else {
                return
            }

            engage(at: now)
        }
    }

    /// Takes the pacing job away from the display.
    private mutating func engage(at now: Double) {
        mode = .selfPaced
        engagementCount += 1
        probeIntervalSeconds = configuration.initialProbeInterval
        consecutiveFailedProbes = 0
        nextProbeAt = now + probeIntervalSeconds
        clearWindow()
    }

    /// Judges one frame of a running recovery probe.
    private mutating func observeProbe(presentSeconds: Double, at now: Double) {
        probeFramesObserved += 1

        // The opening presents of a probe drain into an empty DXGI present
        // queue and return immediately whatever the compositor is doing.
        // Measured here as three sub-millisecond presents followed by a 261 ms
        // one. They are not evidence of anything.
        guard probeFramesObserved > configuration.probeWarmupFrames else {
            return
        }

        if presentSeconds > displayFrameInterval * configuration.releaseMultiple {
            mode = .selfPaced
            probeFramesObserved = 0
            consecutiveFailedProbes += 1
            // Each judged frame of a failed probe blocked the user for a
            // quarter second, and repeating that on a geometric ladder is
            // five visible hitches in the first minute. Once enough probes
            // in a row have failed, the evidence is strong: stop climbing
            // and go straight to the ceiling.
            if consecutiveFailedProbes >= configuration.failedProbesBeforeBackoffCap {
                probeIntervalSeconds = configuration.maximumProbeInterval
            } else {
                probeIntervalSeconds = min(
                    probeIntervalSeconds * configuration.probeBackoffFactor,
                    configuration.maximumProbeInterval
                )
            }
            nextProbeAt = now + probeIntervalSeconds
            return
        }

        guard
            probeFramesObserved >= configuration.probeWarmupFrames + configuration.probeJudgedFrames
        else {
            return
        }

        // Every judged frame of the probe was paced properly: the display has
        // the job back, and the backoff ladder starts over from the next
        // failure rather than from where this one left off.
        mode = .displayPaced
        probeFramesObserved = 0
        probeIntervalSeconds = configuration.initialProbeInterval
        consecutiveFailedProbes = 0
        clearWindow()
    }

    private mutating func append(presentSeconds: Double) {
        if filledCount < configuration.windowSize {
            filledCount += 1
        }

        samples[writeIndex] = presentSeconds
        writeIndex = (writeIndex + 1) % configuration.windowSize
        sampleCount += 1

        // The reported median is refreshed twice per window rather than every
        // frame: it is a diagnostics figure, and the decision it would inform
        // is made from the consecutive run, not from here.
        if filledCount == configuration.windowSize,
            sampleCount % max(1, configuration.windowSize / 2) == 0
        {
            refreshWindowMedian()
        }
    }

    private mutating func refreshWindowMedian() {
        for index in 0..<filledCount {
            medianScratch[index] = samples[index]
        }
        medianScratch[0..<filledCount].sort()
        windowMedianSeconds = medianScratch[filledCount / 2]
    }

    private mutating func clearWindow() {
        writeIndex = 0
        filledCount = 0
        sampleCount = 0
        windowMedianSeconds = 0
        consecutiveBlockedPresents = 0
        consecutiveBlockedSeconds = 0
    }

    // MARK: - Reporting

    /// A snapshot for health reporting, the diagnostics JSON and the host's
    /// per-frame pacing gate. Allocation-free: see ``medianScratch``.
    public var status: PresentPacingStatus {
        PresentPacingStatus(
            mode: mode,
            displayFrameInterval: displayFrameInterval,
            lastPresentSeconds: lastPresentSeconds,
            medianPresentSeconds: windowMedianSeconds,
            engagementCount: engagementCount,
            probeCount: probeCount,
            sampleCount: sampleCount,
            probeIntervalSeconds: probeIntervalSeconds
        )
    }
}

/// What a presentation path reports about its own pacing.
///
/// Typed, not a log line: "the app is self-pacing because the compositor
/// blocks" is a state a diagnostics run has to be able to assert on, and a
/// state a support conversation has to be able to read off a JSON file.
public struct PresentPacingStatus: Equatable, Sendable {
    public var mode: PresentPacingPolicy.Mode
    /// The display period the pacing decision was judged against, in seconds.
    public var displayFrameInterval: Double
    public var lastPresentSeconds: Double
    /// Median present cost over the judgement window. Zero once the window has
    /// been cleared by a mode change.
    public var medianPresentSeconds: Double
    public var engagementCount: Int
    public var probeCount: Int
    public var sampleCount: Int
    public var probeIntervalSeconds: Double

    public init(
        mode: PresentPacingPolicy.Mode = .displayPaced,
        displayFrameInterval: Double = 1.0 / 60.0,
        lastPresentSeconds: Double = 0,
        medianPresentSeconds: Double = 0,
        engagementCount: Int = 0,
        probeCount: Int = 0,
        sampleCount: Int = 0,
        probeIntervalSeconds: Double = 0
    ) {
        self.mode = mode
        self.displayFrameInterval = displayFrameInterval
        self.lastPresentSeconds = lastPresentSeconds
        self.medianPresentSeconds = medianPresentSeconds
        self.engagementCount = engagementCount
        self.probeCount = probeCount
        self.sampleCount = sampleCount
        self.probeIntervalSeconds = probeIntervalSeconds
    }

    /// Whether the host must pace frames itself for this presentation path.
    public var requiresSelfPacing: Bool {
        mode == .selfPaced || mode == .probingDisplay
    }
}
