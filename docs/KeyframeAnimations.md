# Keyframe animation

`KeyframeAnimator` now has a source implementation of typed tracks, interpolation,
and playback owned by the mounted view. The previous implementation discarded
the tracks and always rendered the initial value. This change has not yet been
compiled or executed in its private source checkout. It is not native SwiftUI
conformance, a complete pinned API census, or completion of goal section 4.

An ordinary value can contain independently animated properties. Only each
track's property must conform to `Animatable`:

```swift
struct Motion {
    var x = 0.0
    var scale = 1.0
}

KeyframeAnimator(initialValue: Motion(), trigger: counter) { value in
    Circle()
        .scaleEffect(value.scale)
        .offset(x: value.x)
} keyframes: { _ in
    KeyframeTrack(\Motion.x) {
        LinearKeyframe(60.0, duration: 0.2)
        CubicKeyframe(0.0, duration: 0.3)
    }
    KeyframeTrack(\Motion.scale) {
        SpringKeyframe(1.4, duration: 0.3, spring: .snappy)
        LinearKeyframe(1.0, duration: 0.2)
    }
}
```

The inferred builders and the three generic parameters of `KeyframeTrack` and
`KeyframeAnimator` follow the documented SwiftUI shape. Typed custom `Keyframes`
and `KeyframeTrackContent` bodies are expanded instead of being ignored. The
scalar builder can contain segments directly; a whole-value `KeyframeTrack`
also has a closure-only initializer. Segment sequences support empty content,
`for`, and `if`/`else`. Conditional or array-valued property tracks and optional
omission are not added as guessed public syntax. Concrete builder/body result
types, availability, Sendable declarations, and initializer isolation have not
been reconciled with a sealed SDK. In particular, the view remains subject to
the existing main-actor facade, while Apple's initializer is nonisolated.

There were no repository Tests or Demo call sites for the discarded stubs. Their
incorrect one-parameter nominal arities are not preserved. The old empty
`Keyframe` marker remains a compatibility extension, and the new three-parameter
track has an explicitly empty initializer where its generic constraints allow
it. An Animation-valued spring convenience accepts actual spring easing only;
other Animation kinds are diagnosed instead of silently becoming springs.

Apple describes the factory's input as the current value: initially the supplied
value, then the previous run's endpoint. The trigger initializer replaces a run
when its typed `Equatable` trigger changes. The repeating initializer's false
state provides the beginning value. The implementation uses these contracts,
including an initial Move segment at time zero. It does not use string
descriptions to compare triggers. [Apple trigger initializer](https://developer.apple.com/documentation/swiftui/keyframeanimator/init%28initialvalue%3Atrigger%3Acontent%3Akeyframes%3A%29),
[Apple repeating initializer](https://developer.apple.com/documentation/swiftui/keyframeanimator/init%28initialvalue%3Arepeating%3Acontent%3Akeyframes%3A%29).

## Interpolation

`KeyframeTimeline(initialValue:content:)` provides `duration`, `value(time:)`,
and `value(progress:)`. Tracks run together; timeline duration is their maximum.
Shorter tracks hold their endpoint. Tracks write in declaration order, so the
last track targeting the same property wins. Finite times before zero sample the
beginning, and times past the duration hold the endpoint. The empty timeline has
zero duration and preserves its root. [Apple KeyframeTimeline](https://developer.apple.com/documentation/swiftui/keyframetimeline).

- Linear uses the existing `UnitCurve` to interpolate animatable data.
- Move changes the value at its boundary and has zero duration.
- Cubic uses Hermite interpolation with typed explicit endpoint velocities.
  Consecutive automatic cubic segments share a nonuniform Catmull-Rom tangent.
  An automatic cubic start inherits incoming velocity, and an automatic exit
  before a fixed linear segment uses that segment's initial slope.
- Spring solves the underdamped, critically damped, or overdamped oscillator
  using the existing `Spring` response/damping model and typed initial velocity.
  A short explicit duration retains its actual physical endpoint; it does not
  force the result to the target. The next segment starts at that endpoint.

An interrupted run supplies its current value and per-property velocity to the
next factory. Cubic and spring inherit that velocity unless an explicit start
velocity overrides it. A spring followed by a fixed linear segment can have a
velocity discontinuity: a fixed target and duration do not, in general, allow
both endpoint and derivative continuity. This implementation does not claim
otherwise. Apple describes Catmull-Rom interpolation and mixed keyframes, but
does not specify all numerical choices used here. [Apple CubicKeyframe](https://developer.apple.com/documentation/swiftui/cubickeyframe),
[Apple animation session](https://developer.apple.com/videos/play/wwdc2023/10157/).

An omitted spring duration uses a local bounded settling rule. Both future
displacement and velocity divided by angular frequency must fit within
`0.001 * max(1, initial displacement norm)`. The search has a 60-second horizon
and 48 bisections. Nonsettling or unrepresentable inputs require an explicit
duration and receive a precondition diagnostic. This is not a measured Apple
settling constant. Explicit spring duration zero keeps its starting value and
velocity. The default spring is the existing local `Spring(duration: 0.5,
bounce: 0)` model; that model and `UnitCurve` remain separate numerical parity
dependencies.

Durations must be finite and nonnegative, and adjacent positive durations must
remain distinguishable in Double timeline coordinates. Sample time/progress
must be finite. Spring response must be finite and positive, with finite
nonnegative damping. The nonnative scalar `Spring.initialVelocity` extension is
not silently converted into a generic property's velocity: use the typed
`SpringKeyframe.startVelocity` parameter. NaN, infinity, invalid durations, and
nonsettling automatic springs are not successful no-op programs.

Double/Float and the facade's Point/Size/Rect/Angle values now provide the
Animatable adapters needed by these tracks. Custom bodies, vector operations,
animatable-data accessors, and writable key paths remain authored code. Mounted
compilation and sampling check the current receipt before and after each
framework-entered operation and after temporary cleanup. Existing
`AnimatablePair` operations are expanded through a private keyframe-only adapter
so one component cannot revoke ownership and leave the next component running.
These checks cannot interrupt an authored function already on the stack or
undo its effects.

## Mounted lifetime and frame timing

Each occurrence has a synthetic cell in its inherited `StateMountCoordinator`.
Construction stages a proposal; only accepted adoption publishes it. All
adopted proposals are committed before their actions are delivered. A rejected
parent or managed contribution cannot compare a trigger, enter a factory, or
arm playback through an ordinary fallback. Independent hosts, siblings, keys,
and explicit identities have independent cells. Unrelated rebuilds keep an
unchanged run's original start and use the latest accepted configuration.

Playback uses the existing retained runtime clock and deferred-rebuild queue.
The package timestamp callback receives the actual `tickAnimations(at:)` value,
without resampling a second clock or imposing 60 Hz. No global timer, Date,
sleep, Task, or process registry owns the animation. Weak callbacks name the
exact run and admit only its latest fully delivered proposal. A sibling's
synchronous rebuild therefore does not invalidate another unchanged run's
already-due callback.

The native queue claims due callbacks before invoking them. If a callback is
temporarily inadmissible during reversible retirement, committed proposal
delivery, or reentrant sampling, it keeps only its weak exact-run wakeup; it
does not enter authored work. Final retirement cancels that slot after the cell
and owner have lost write authority, before releasing captured payloads. An
abandoned retirement can therefore resume the same run, while close, actual
removal, and replaced generations cannot revive it. This works before the first
appearance callback and does not depend on deinit or onDisappear.

Managed List and descriptor components use the existing exact observation
contribution facets. Physical row eviction retires keyframe activity while
declared logical State can remain alive and writable. Returning to the viewport
creates fresh keyframe activity; it does not replay cold frames. Partial
adoption must qualify the exact existing contribution rather than an entire
candidate row. This slice does not change public List membership or adoption
policy, the ordinary State hash path, Button/action ownership, or native focus
authority.

Factory/equality work runs with both captured transaction slots restored.
Publication preserves the run's other transaction fields but clears animation
and sets `disablesAnimations` so sampled values do not receive a second tween.
Ambient transaction state is restored afterward. A later caller's transaction
does not retarget an unchanged run.

Ordinary repeat overshoot stays anchored to the preceding cycle's end. At most
eight crossed boundaries invoke factories in one admitted frame. If a longer
gap remains, the current run's start resets at that frame; elapsed factory calls
are not invented. This bounded suspension policy still needs native comparison.
Zero-duration repeats settle once without an infinite callback loop. Backward
or nonfinite frame timestamps do not rewind or publish a sample.

The current Windows policy seeds trigger mode without playing on first mount.
Reduced Motion publishes the endpoint once when playback is requested and
leaves no repeated frame slot; `repeating: false` still provides the beginning.
Switching Reduced Motion off can restart requested repetition. These exact
mount, environment-change, and physical-return rules need paired native
characterization; Apple's environment documentation is not proof of them.
[Apple Reduce Motion environment](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion).

An unmanaged raw Component has no durable owner. It can sample the beginning of
a repeating timeline, but it cannot start owned playback. The public snapshot
path and other unmanaged hosts therefore remain an explicit lifetime/animation
qualification gap; static output is not evidence that their keyframes played.

## Evidence boundary

The new source fixtures use deterministic values and a supplied retained clock.
They cover timeline mathematics, typed builders, playback, transactions, actual
mounted adoption, rejection, reentry, cleanup, and List eviction/return. They do
not wait for frames, open a native window, synthesize input, or measure hardware
pacing. Existing animation, transaction, observer, task, and List tests are
unchanged and remain required preservation evidence.

At this source checkpoint, all new tests are **unexecuted**. A separate approved
compile/test run must establish source correctness. Paired macOS reference
execution, literal SDK surface reconciliation, rendered motion/pixel evidence,
native suspension/reduced-motion behavior, and live performance remain open.
No goal acceptance condition is removed by this bounded implementation.
