import Foundation
import SwiftWindowsCore
import SwiftWindowsUI

@MainActor
private protocol AnyKeyframeTrigger: AnyObject {
    func isEqual(to other: any AnyKeyframeTrigger) -> Bool
}

@MainActor
private final class KeyframeTrigger<Value: Equatable>: AnyKeyframeTrigger {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    func isEqual(to other: any AnyKeyframeTrigger) -> Bool {
        guard let other = other as? KeyframeTrigger<Value> else { return false }
        return value == other.value
    }
}

@MainActor
private enum KeyframePlaybackMode {
    case repeating(Bool)
    case trigger(any AnyKeyframeTrigger)
}

private final class KeyframeProposal {}
private final class KeyframeWork {}

/// Keep both ambient slots, including a nil full transaction with a legacy
/// animation. Sampling is already the animation; its resulting rebuild must
/// not install a second tween between successive samples.
@MainActor
private struct KeyframeTransactionScope {
    let transaction = currentTransaction
    let animation = currentAnimationTransaction

    @inline(never)
    func perform(framePublication: Bool = false, _ body: () -> Void) {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        if framePublication {
            var frame = transaction ?? Transaction()
            frame.animation = nil
            frame.disablesAnimations = true
            currentTransaction = frame
            currentAnimationTransaction = nil
        } else {
            currentTransaction = transaction
            currentAnimationTransaction = animation
        }
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        body()
    }
}

@MainActor
private final class KeyframeConfiguration<Value> {
    typealias Factory = (Value, KeyframeVelocityMap, () -> Bool) -> KeyframeTimeline<Value>?

    let mode: KeyframePlaybackMode
    let reduceMotion: Bool
    let factory: Factory
    let invalidate: () -> Void
    let transaction = KeyframeTransactionScope()

    init(
        mode: KeyframePlaybackMode, reduceMotion: Bool, factory: @escaping Factory,
        invalidate: @escaping () -> Void
    ) {
        self.mode = mode
        self.reduceMotion = reduceMotion
        self.factory = factory
        self.invalidate = invalidate
    }
}

@MainActor
private final class KeyframeRun<Value> {
    let timeline: KeyframeTimeline<Value>
    let transaction: KeyframeTransactionScope
    var startedAt: Double
    var lastTimestamp: Double

    init(timeline: KeyframeTimeline<Value>, startedAt: Double, transaction: KeyframeTransactionScope) {
        self.timeline = timeline
        self.startedAt = startedAt
        self.lastTimestamp = startedAt
        self.transaction = transaction
    }
}

/// This object is the synthetic cell's value, never a process-wide registry.
/// Its runtime slot is weak and each callback is also pinned to a proposal/run.
/// Final cell retirement cancels promptly even if an escaped diagnostic retains
/// the object. Ordinary State's retired snapshot policy is unchanged.
@MainActor
private final class KeyframePlayback<Value>: MountedSyntheticObservationLifetime {
    private weak var owner: StateMountOwner?
    private weak var cell: MountedStateCell<KeyframePlayback<Value>>?
    private weak var runtime: RetainedViewRuntime?
    private let schedulingKey = "keyframe:\(UUID().uuidString)"
    private var retired = false
    private var proposal: KeyframeProposal?
    private var deliveredProposal: KeyframeProposal?
    private var work: KeyframeWork?
    fileprivate var baselineTrigger: (any AnyKeyframeTrigger)?
    private var initialized = false
    private var run: KeyframeRun<Value>?
    private var presented: KeyframeSample<Value>?
    private var beginning: KeyframeSample<Value>?
    fileprivate var configuration: KeyframeConfiguration<Value>?

    init(initialValue: Value) {
        presented = KeyframeSample(value: initialValue, velocities: [:])
    }

    var currentValue: Value? {
        presented?.value
    }

    func bind(
        owner: StateMountOwner, cell: MountedStateCell<KeyframePlayback<Value>>, runtime: RetainedViewRuntime
    ) -> Bool {
        guard !retired else { return false }
        if let currentOwner = self.owner, currentOwner !== owner { return false }
        if let currentCell = self.cell, currentCell !== cell { return false }
        if let currentRuntime = self.runtime, currentRuntime !== runtime { return false }
        self.owner = owner
        self.cell = cell
        self.runtime = runtime
        return true
    }

    func commit(_ configuration: KeyframeConfiguration<Value>, proposal: KeyframeProposal) {
        // The update retains the displaced configuration through the entire
        // adopted batch, so these assignments cannot release authored captures.
        self.configuration = configuration
        self.proposal = proposal
    }

    private func isCurrent(_ proposal: KeyframeProposal, run expectedRun: KeyframeRun<Value>? = nil) -> Bool {
        guard !retired, self.proposal === proposal, owner?.isLive == true,
            let cell, cell.isWritable, cell.readValue() === self, runtime != nil
        else { return false }
        return expectedRun == nil || run === expectedRun
    }

    private func isCurrent(_ proposal: KeyframeProposal, work: KeyframeWork) -> Bool {
        self.work === work && isCurrent(proposal)
    }

    private func finishWork(_ work: KeyframeWork) {
        if self.work === work { self.work = nil }
    }

    func deliver(previous: KeyframeConfiguration<Value>?, proposal: KeyframeProposal) {
        guard isCurrent(proposal), let configuration else { return }
        let work = KeyframeWork()
        self.work = work
        defer {
            if isCurrent(proposal) { deliveredProposal = proposal }
            finishWork(work)
        }
        configuration.transaction.perform {
            deliver(previous: previous, configuration: configuration, proposal: proposal, work: work)
        }
    }

    private func deliver(
        previous: KeyframeConfiguration<Value>?, configuration: KeyframeConfiguration<Value>,
        proposal: KeyframeProposal, work: KeyframeWork
    ) {
        guard isCurrent(proposal, work: work) else { return }
        let wasInitialized = initialized
        initialized = true
        switch configuration.mode {
        case .trigger(let trigger):
            if let baseline = baselineTrigger {
                let equal = compare(baseline, trigger)
                guard isCurrent(proposal, work: work) else { return }
                if !equal {
                    // The update's previous configuration pins the prior value
                    // across this publication and any destructor reentry.
                    baselineTrigger = trigger
                    start(configuration, proposal: proposal, work: work, repeating: false)
                    return
                }
            } else {
                baselineTrigger = trigger
                if wasInitialized {
                    stopAtCurrentSample(proposal: proposal)
                }
            }
        case .repeating(let repeating):
            baselineTrigger = nil
            let wasRepeating: Bool?
            if let previous, case .repeating(let value) = previous.mode {
                wasRepeating = value
            } else {
                wasRepeating = nil
            }
            if !wasInitialized || wasRepeating == nil || (repeating && wasRepeating == false) {
                start(configuration, proposal: proposal, work: work, repeating: repeating)
                return
            }
            if !repeating, wasRepeating == true {
                stopAtBeginning(configuration, proposal: proposal, work: work)
                return
            }
        }
        guard isCurrent(proposal, work: work) else { return }
        if configuration.reduceMotion, let run {
            finishAtEnd(run, configuration: configuration, proposal: proposal, work: work)
            return
        }
        if previous?.reduceMotion == true, !configuration.reduceMotion,
            case .repeating(true) = configuration.mode
        {
            start(configuration, proposal: proposal, work: work, repeating: true)
            return
        }
        if let run {
            finishWork(work)
            arm(run, proposal: proposal, at: run.lastTimestamp)
        }
    }

    @inline(never)
    private func compare(_ lhs: any AnyKeyframeTrigger, _ rhs: any AnyKeyframeTrigger) -> Bool {
        lhs.isEqual(to: rhs)
    }

    @inline(never)
    private func makeTimeline(
        configuration: KeyframeConfiguration<Value>, sample: KeyframeSample<Value>,
        isCurrent: () -> Bool
    ) -> KeyframeTimeline<Value>? {
        guard isCurrent() else { return nil }
        return configuration.factory(sample.value, sample.velocities, isCurrent)
    }

    private func start(
        _ configuration: KeyframeConfiguration<Value>, proposal: KeyframeProposal,
        work: KeyframeWork, repeating: Bool
    ) {
        guard isCurrent(proposal, work: work), let runtime, let presented else { return }
        let now = runtime.clock()
        guard now.isFinite, isCurrent(proposal, work: work) else { return }
        var startingSample = presented
        if let previousRun = run {
            guard
                let sampled = previousRun.timeline.sample(
                    time: max(0, now - previousRun.startedAt),
                    isCurrent: { self.isCurrent(proposal, work: work) })
            else { return }
            guard isCurrent(proposal, work: work) else { return }
            startingSample = sampled
        }
        guard
            let timeline = makeTimeline(
                configuration: configuration, sample: startingSample,
                isCurrent: { self.isCurrent(proposal, work: work) })
        else { return }
        guard isCurrent(proposal, work: work) else { return }
        let newRun = KeyframeRun(timeline: timeline, startedAt: now, transaction: configuration.transaction)
        let requestsAnimation = repeating || isTriggered(configuration.mode)
        let shouldAnimate = !configuration.reduceMotion && timeline.duration > 0 && requestsAnimation
        guard
            let startSample = timeline.sample(
                time: 0, isCurrent: { self.isCurrent(proposal, work: work) })
        else { return }
        guard isCurrent(proposal, work: work) else { return }
        let sample: KeyframeSample<Value>
        if configuration.reduceMotion && requestsAnimation {
            guard
                let terminal = timeline.sample(
                    time: timeline.duration, isCurrent: { self.isCurrent(proposal, work: work) })
            else { return }
            guard isCurrent(proposal, work: work) else { return }
            sample = terminal
        } else {
            sample = startSample
        }
        replaceRun(shouldAnimate ? newRun : nil, beginning: startSample)
        guard isCurrent(proposal, work: work) else { return }
        publish(sample, configuration: configuration, transaction: newRun.transaction, proposal: proposal)
        guard isCurrent(proposal, work: work), shouldAnimate, run === newRun else { return }
        finishWork(work)
        arm(newRun, proposal: proposal, at: now)
    }

    private func isTriggered(_ mode: KeyframePlaybackMode) -> Bool {
        if case .trigger = mode { return true }
        return false
    }

    /// Dropped run/callback captures finish releasing before the caller's next
    /// scalar check. Never cancel another occurrence or re-resolve an identity.
    @inline(never)
    private func replaceRun(_ replacement: KeyframeRun<Value>?, beginning newBeginning: KeyframeSample<Value>? = nil) {
        let previous = run
        let previousBeginning = beginning
        run = replacement
        if let newBeginning { beginning = newBeginning }
        runtime?.cancelDeferredRebuild(key: schedulingKey)
        withExtendedLifetime((previous, previousBeginning)) {}
    }

    @inline(never)
    private func publish(
        _ sample: KeyframeSample<Value>, configuration: KeyframeConfiguration<Value>,
        transaction: KeyframeTransactionScope, proposal: KeyframeProposal
    ) {
        guard isCurrent(proposal) else { return }
        let previous = presented
        presented = sample
        if isCurrent(proposal) {
            transaction.perform(framePublication: true) {
                if self.isCurrent(proposal) { configuration.invalidate() }
            }
        }
        withExtendedLifetime(previous) {}
    }

    private func stopAtCurrentSample(proposal: KeyframeProposal) {
        guard isCurrent(proposal) else { return }
        replaceRun(nil)
    }

    private func stopAtBeginning(
        _ configuration: KeyframeConfiguration<Value>, proposal: KeyframeProposal, work: KeyframeWork
    ) {
        guard let sample = beginning, isCurrent(proposal, work: work) else { return }
        replaceRun(nil)
        guard isCurrent(proposal, work: work) else { return }
        publish(sample, configuration: configuration, transaction: configuration.transaction, proposal: proposal)
    }

    private func finishAtEnd(
        _ run: KeyframeRun<Value>, configuration: KeyframeConfiguration<Value>,
        proposal: KeyframeProposal, work: KeyframeWork
    ) {
        guard isCurrent(proposal, work: work),
            let sample = run.timeline.sample(
                time: run.timeline.duration, isCurrent: { self.isCurrent(proposal, work: work) })
        else { return }
        guard isCurrent(proposal, work: work) else { return }
        replaceRun(nil)
        guard isCurrent(proposal, work: work) else { return }
        publish(sample, configuration: configuration, transaction: run.transaction, proposal: proposal)
    }

    private func arm(_ run: KeyframeRun<Value>, proposal: KeyframeProposal, at timestamp: Double) {
        guard isCurrent(proposal, run: run) else { return }
        deliveredProposal = proposal
        enqueue(run, at: timestamp)
    }

    private func enqueue(_ run: KeyframeRun<Value>, at timestamp: Double) {
        guard !retired, self.run === run, owner?.lazyLifetime.registry.isOpen == true,
            cell != nil, let runtime
        else { return }
        runtime.scheduleDeferredFrameRebuild(key: schedulingKey, at: timestamp) { [weak self, weak run] timestamp in
            // A sibling's sample can rebuild this same, unchanged run before
            // its already-due callback is reached. The native slot owns the
            // run, not one incidental content rebuild. Admit only the latest
            // fully delivered proposal of that exact still-installed run.
            guard let self, let run, !self.retired, self.run === run,
                self.owner?.lazyLifetime.registry.isOpen == true, self.cell != nil, self.runtime != nil
            else { return }
            guard timestamp.isFinite, self.work == nil, let current = self.deliveredProposal,
                self.isCurrent(current, run: run)
            else {
                // The native queue claimed this entry before invoking it. A
                // reversible retirement, committed-but-undelivered proposal,
                // or nested sampling call cannot consume the surviving run's
                // only wakeup. No authored operation is entered here. Final
                // retirement cancels this weak exact-run slot before release.
                self.enqueue(run, at: timestamp.isFinite ? timestamp : run.lastTimestamp)
                return
            }
            self.advance(run, proposal: current, at: timestamp)
        }
    }

    private func advance(_ run: KeyframeRun<Value>, proposal: KeyframeProposal, at timestamp: Double) {
        guard work == nil, timestamp.isFinite, isCurrent(proposal, run: run), let configuration else { return }
        guard timestamp >= run.lastTimestamp else {
            arm(run, proposal: proposal, at: run.lastTimestamp)
            return
        }
        let work = KeyframeWork()
        self.work = work
        defer { finishWork(work) }
        run.transaction.perform {
            advance(
                run, configuration: configuration, proposal: proposal, work: work, at: timestamp)
        }
    }

    private func advance(
        _ originalRun: KeyframeRun<Value>, configuration: KeyframeConfiguration<Value>,
        proposal: KeyframeProposal, work: KeyframeWork, at timestamp: Double
    ) {
        guard isCurrent(proposal, work: work), run === originalRun else { return }
        var active = originalRun
        var crossedCycles = 0
        while timestamp - active.startedAt >= active.timeline.duration {
            guard isCurrent(proposal, work: work), run === active else { return }
            guard
                let end = active.timeline.sample(
                    time: active.timeline.duration, isCurrent: { self.isCurrent(proposal, work: work) })
            else { return }
            guard isCurrent(proposal, work: work), run === active else { return }
            guard case .repeating(true) = configuration.mode, !configuration.reduceMotion,
                active.timeline.duration > 0
            else {
                replaceRun(nil)
                guard isCurrent(proposal, work: work) else { return }
                publish(end, configuration: configuration, transaction: active.transaction, proposal: proposal)
                return
            }
            guard
                let next = makeTimeline(
                    configuration: configuration, sample: end,
                    isCurrent: { self.isCurrent(proposal, work: work) })
            else { return }
            guard isCurrent(proposal, work: work), run === active else { return }
            let nextStart = active.startedAt + active.timeline.duration
            let nextRun = KeyframeRun(timeline: next, startedAt: nextStart, transaction: active.transaction)
            guard
                let nextBeginning = next.sample(
                    time: 0, isCurrent: { self.isCurrent(proposal, work: work) })
            else { return }
            guard isCurrent(proposal, work: work), run === active else { return }
            replaceRun(nextRun, beginning: nextBeginning)
            guard isCurrent(proposal, work: work), run === nextRun else { return }
            active = nextRun
            crossedCycles += 1
            if next.duration == 0 {
                finishAtEnd(active, configuration: configuration, proposal: proposal, work: work)
                return
            }
            // Keep normal frame overshoot anchored to the previous cycle end.
            // A long suspension cannot call an arbitrary factory unboundedly.
            // After eight missed boundaries, pause/reset at this admitted frame.
            // Exact native long-gap semantics remain unqualified.
            if crossedCycles == 8, timestamp - active.startedAt >= next.duration {
                active.startedAt = timestamp
                active.lastTimestamp = timestamp
                break
            }
        }
        guard isCurrent(proposal, work: work), run === active,
            let sample = active.timeline.sample(
                time: max(0, timestamp - active.startedAt),
                isCurrent: { self.isCurrent(proposal, work: work) })
        else { return }
        guard isCurrent(proposal, work: work), run === active else { return }
        active.lastTimestamp = timestamp
        publish(sample, configuration: configuration, transaction: active.transaction, proposal: proposal)
        guard isCurrent(proposal, work: work), run === active else { return }
        finishWork(work)
        arm(active, proposal: proposal, at: timestamp)
    }

    func finishMountedObservation() {
        guard !retired else { return }
        retired = true
        proposal = nil
        deliveredProposal = nil
        work = nil
        let oldRun = run
        let oldConfiguration = configuration
        let oldSample = presented
        let oldBeginning = beginning
        let oldTrigger = baselineTrigger
        run = nil
        configuration = nil
        presented = nil
        beginning = nil
        baselineTrigger = nil
        runtime?.cancelDeferredRebuild(key: schedulingKey)
        runtime = nil
        owner = nil
        cell = nil
        withExtendedLifetime((oldRun, oldConfiguration, oldSample, oldBeginning, oldTrigger)) {}
    }
}

@MainActor
private final class KeyframeUpdate<Value>: MountedOnChangeUpdate {
    let owner: StateMountOwner
    private let cell: MountedStateCell<KeyframePlayback<Value>>
    private let configuration: KeyframeConfiguration<Value>
    private let proposal = KeyframeProposal()
    private var previous: KeyframeConfiguration<Value>?
    private var previousTrigger: (any AnyKeyframeTrigger)?
    private var didCommit = false
    private var didDeliver = false

    init(
        owner: StateMountOwner, cell: MountedStateCell<KeyframePlayback<Value>>,
        configuration: KeyframeConfiguration<Value>
    ) {
        self.owner = owner
        self.cell = cell
        self.configuration = configuration
    }

    func commit() {
        guard !didCommit, owner.isLive, cell.isWritable else { return }
        didCommit = true
        let playback = cell.readValue()
        previous = playback.configuration
        previousTrigger = playback.baselineTrigger
        playback.commit(configuration, proposal: proposal)
    }

    func deliver() {
        guard didCommit, !didDeliver, owner.isLive, cell.isWritable else { return }
        didDeliver = true
        cell.readValue().deliver(previous: previous, proposal: proposal)
    }
}

@MainActor
private final class KeyframeMaterialization<Value> {
    var playback: KeyframePlayback<Value>?
}

/// A typed keyframe container. The root need not be Animatable: individual
/// writable-key-path tracks carry that requirement.
@MainActor
public struct KeyframeAnimator<Value, KeyframePath: Keyframes, Content: View>: View
where Value == KeyframePath.Value {
    public typealias Body = Never

    private let initialValue: Value
    private let mode: KeyframePlaybackMode
    private let content: (Value) -> Content
    private let keyframes: (Value) -> KeyframePath

    public init(
        initialValue: Value, repeating: Bool = true,
        @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) {
        self.initialValue = initialValue
        mode = .repeating(repeating)
        self.content = content
        self.keyframes = keyframes
    }

    public init<Trigger: Equatable>(
        initialValue: Value, trigger: Trigger,
        @ViewBuilder content: @escaping (Value) -> Content,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) {
        self.initialValue = initialValue
        mode = .trigger(KeyframeTrigger(trigger))
        self.content = content
        self.keyframes = keyframes
    }

    public var body: Never {
        fatalError("KeyframeAnimator has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let originalEpoch = context.viewIdentity.installedEpoch
            let request = context.stateMountCoordinator?.captureBuildRequest()
            let materialization = KeyframeMaterialization<Value>()
            let configuration = KeyframeConfiguration(
                mode: mode, reduceMotion: context.accessibilityReduceMotion,
                factory: { value, velocities, isCurrent in
                    guard isCurrent() else { return nil }
                    let frames = keyframes(value)
                    guard isCurrent() else { return nil }
                    return KeyframeTimeline(
                        initialValue: value, initialVelocities: velocities, frames: frames, isCurrent: isCurrent)
                },
                invalidate: context.invalidate)

            @MainActor
            func canConstruct() -> Bool {
                guard request?.isCurrent != false,
                    context.viewIdentity.lazyList?.admission.isCurrent != false,
                    context.viewIdentity.descriptorComponent?.canConstruct != false
                else { return false }
                if context.stateMountCoordinator != nil {
                    return originalEpoch?.observationConstructionRevision != nil
                }
                return true
            }

            @MainActor
            func update(
                _ owner: StateMountOwner, _ cell: MountedStateCell<KeyframePlayback<Value>>
            ) -> (any MountedOnChangeUpdate)? {
                guard canConstruct() else { return nil }
                let playback = cell.readValue()
                guard playback.bind(owner: owner, cell: cell, runtime: runtime), canConstruct() else { return nil }
                materialization.playback = playback
                return KeyframeUpdate(owner: owner, cell: cell, configuration: configuration)
            }

            let identity = context.retainedViewIdentity.appending(.view(ObjectIdentifier(KeyframePlayback<Value>.self)))
            let component = Component { runtime in
                guard canConstruct() else { return rejectedRetainedViewNode() }
                let value: Value
                if let playback = materialization.playback, let current = playback.currentValue {
                    value = current
                } else if context.stateMountCoordinator == nil {
                    // An unmanaged component has no durable owner. It can
                    // render a beginning sample, but must not arm playback.
                    if case .repeating = mode {
                        guard let timeline = configuration.factory(initialValue, [:], canConstruct),
                            canConstruct(), let beginning = timeline.sample(time: 0, isCurrent: canConstruct),
                            canConstruct()
                        else { return rejectedRetainedViewNode() }
                        value = beginning.value
                    } else {
                        value = initialValue
                    }
                } else {
                    return rejectedRetainedViewNode()
                }
                let view = content(value)
                guard canConstruct() else { return rejectedRetainedViewNode() }
                let child = makeViewComponent(view, context: context.withViewIdentityRole(.content))
                guard canConstruct() else { return rejectedRetainedViewNode() }
                var nodes: [ViewNode] = []
                child.appendChildNodes(runtime: runtime, to: &nodes)
                guard canConstruct() else { return rejectedRetainedViewNode() }
                return ViewNode(layoutMode: .absolute, children: nodes)
            }

            if let attribution = context.viewIdentity.lazyList {
                return lazyListSyntheticComponent(
                    in: component, context: context, attribution: attribution, kind: .observation,
                    prepare: { group in
                        context.stateMountCoordinator?.stageOnChange(
                            at: identity, attribution: attribution, kind: .keyframe, group: group,
                            seedObservation: { KeyframePlayback(initialValue: initialValue) }, makeUpdate: update)
                    }
                ).makeNode(runtime: runtime)
            }
            if let attribution = context.viewIdentity.descriptorComponent {
                return descriptorSyntheticComponent(
                    in: component, context: context, attribution: attribution, kind: .observation,
                    prepare: { group in
                        context.stateMountCoordinator?.stageOnChange(
                            at: identity, descriptorAttribution: attribution, kind: .keyframe, group: group,
                            seedObservation: { KeyframePlayback(initialValue: initialValue) }, makeUpdate: update)
                    }
                ).makeNode(runtime: runtime)
            }
            context.stateMountCoordinator?.stageOnChange(
                at: identity, seedObservation: { KeyframePlayback(initialValue: initialValue) }, makeUpdate: update)
            guard canConstruct() else { return rejectedRetainedViewNode() }
            return component.makeNode(runtime: runtime)
        }
    }
}
