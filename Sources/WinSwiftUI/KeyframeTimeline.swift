import Foundation

/// Compatibility marker for keyframe values. A usable segment also supplies
/// a typed `KeyframeTrackContent` body.
public protocol Keyframe {}

/// Simultaneous tracks that animate an otherwise unconstrained root value.
public protocol Keyframes<Value> {
    associatedtype Value
    associatedtype Body: Keyframes<Value>

    @KeyframesBuilder<Value> var body: Body { get }
}

/// A sequence of segments animating one property's animatable data.
public protocol KeyframeTrackContent<Value>: Keyframe {
    associatedtype Value: Animatable
    associatedtype Body: KeyframeTrackContent<Value>

    @KeyframeTrackContentBuilder<Value> var body: Body { get }
}

/// The concrete result of a track-content builder.
public struct _KeyframeTrackContent<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = _KeyframeTrackContent<Value>

    fileprivate let sources: [_KeyframeSegmentResolver<Value>]

    fileprivate init(sources: [_KeyframeSegmentResolver<Value>]) {
        self.sources = sources
    }

    fileprivate init(segment: _KeyframeSegment<Value>) {
        self.sources = [{ isCurrent in isCurrent() ? [segment] : nil }]
    }

    public var body: Body { return self }
}

/// The concrete result of a simultaneous-tracks builder.
public struct _Keyframes<Root>: Keyframes {
    public typealias Value = Root
    public typealias Body = _Keyframes<Root>

    fileprivate let sources: [_KeyframeFramesResolver<Root>]

    fileprivate init(sources: [_KeyframeFramesResolver<Root>]) {
        self.sources = sources
    }

    fileprivate init(tracks: [_KeyframeTrackSource<Root>]) {
        self.sources = [{ isCurrent in isCurrent() ? tracks : nil }]
    }

    public var body: Body { return self }
}

@resultBuilder
public enum KeyframeTrackContentBuilder<Value: Animatable> {
    public static func buildExpression<Content: KeyframeTrackContent>(
        _ expression: Content
    ) -> Content where Content.Value == Value {
        expression
    }

    public static func buildBlock() -> _KeyframeTrackContent<Value> {
        _KeyframeTrackContent(sources: [])
    }

    public static func buildPartialBlock<Content: KeyframeTrackContent>(
        first: Content
    ) -> Content where Content.Value == Value {
        first
    }

    public static func buildPartialBlock<Accumulated: KeyframeTrackContent, Next: KeyframeTrackContent>(
        accumulated: Accumulated, next: Next
    ) -> _KeyframeTrackContent<Value> where Accumulated.Value == Value, Next.Value == Value {
        _KeyframeTrackContent(sources: [
            { isCurrent in _keyframeCollectSegments(accumulated, isCurrent: isCurrent) },
            { isCurrent in _keyframeCollectSegments(next, isCurrent: isCurrent) },
        ])
    }

    public static func buildEither<Content: KeyframeTrackContent>(
        first component: Content
    ) -> _KeyframeTrackContent<Value> where Content.Value == Value {
        _KeyframeTrackContent(sources: [
            { isCurrent in
                _keyframeCollectSegments(component, isCurrent: isCurrent)
            }
        ])
    }

    public static func buildEither<Content: KeyframeTrackContent>(
        second component: Content
    ) -> _KeyframeTrackContent<Value> where Content.Value == Value {
        _KeyframeTrackContent(sources: [
            { isCurrent in
                _keyframeCollectSegments(component, isCurrent: isCurrent)
            }
        ])
    }

    public static func buildArray<Content: KeyframeTrackContent>(
        _ components: [Content]
    ) -> _KeyframeTrackContent<Value> where Content.Value == Value {
        let sources: [_KeyframeSegmentResolver<Value>] = components.map { component in
            { isCurrent in _keyframeCollectSegments(component, isCurrent: isCurrent) }
        }
        return _KeyframeTrackContent(sources: sources)
    }
}

@resultBuilder
public enum KeyframesBuilder<Root> {
    public static func buildExpression<Frames: Keyframes>(
        _ expression: Frames
    ) -> Frames where Frames.Value == Root {
        expression
    }

    @_disfavoredOverload
    public static func buildBlock() -> _Keyframes<Root> {
        _Keyframes(sources: [])
    }

    public static func buildPartialBlock<Frames: Keyframes>(
        first: Frames
    ) -> Frames where Frames.Value == Root {
        first
    }

    public static func buildPartialBlock<Accumulated: Keyframes, Next: Keyframes>(
        accumulated: Accumulated, next: Next
    ) -> _Keyframes<Root> where Accumulated.Value == Root, Next.Value == Root {
        _Keyframes(sources: [
            { isCurrent in _keyframeCollectTracks(accumulated, isCurrent: isCurrent) },
            { isCurrent in _keyframeCollectTracks(next, isCurrent: isCurrent) },
        ])
    }

    public static func buildFinalResult<Frames: Keyframes>(
        _ content: Frames
    ) -> Frames where Frames.Value == Root {
        content
    }

    // Scalar segment sequencing is distinct from simultaneous property tracks.
    // These overloads intentionally do not admit optional, conditional, or
    // array-valued property tracks.
    public static func buildExpression<Content: KeyframeTrackContent>(
        _ expression: Content
    ) -> Content where Root: Animatable, Content.Value == Root {
        expression
    }

    public static func buildBlock() -> _KeyframeTrackContent<Root> where Root: Animatable {
        _KeyframeTrackContent(sources: [])
    }

    public static func buildPartialBlock<Content: KeyframeTrackContent>(
        first: Content
    ) -> Content where Root: Animatable, Content.Value == Root {
        first
    }

    public static func buildPartialBlock<Accumulated: KeyframeTrackContent, Next: KeyframeTrackContent>(
        accumulated: Accumulated, next: Next
    ) -> _KeyframeTrackContent<Root> where Root: Animatable, Accumulated.Value == Root, Next.Value == Root {
        KeyframeTrackContentBuilder<Root>.buildPartialBlock(accumulated: accumulated, next: next)
    }

    public static func buildEither<Content: KeyframeTrackContent>(
        first component: Content
    ) -> _KeyframeTrackContent<Root> where Root: Animatable, Content.Value == Root {
        KeyframeTrackContentBuilder<Root>.buildEither(first: component)
    }

    public static func buildEither<Content: KeyframeTrackContent>(
        second component: Content
    ) -> _KeyframeTrackContent<Root> where Root: Animatable, Content.Value == Root {
        KeyframeTrackContentBuilder<Root>.buildEither(second: component)
    }

    public static func buildArray<Content: KeyframeTrackContent>(
        _ components: [Content]
    ) -> _KeyframeTrackContent<Root> where Root: Animatable, Content.Value == Root {
        KeyframeTrackContentBuilder<Root>.buildArray(components)
    }

    public static func buildFinalResult<Content: KeyframeTrackContent>(
        _ content: Content
    ) -> _Keyframes<Root> where Root: Animatable, Content.Value == Root {
        if let built = content as? _KeyframeTrackContent<Root>, built.sources.isEmpty {
            return _Keyframes(sources: [])
        }
        return KeyframeTrack<Root, Root, Content>(\Root.self) { content }.body
    }
}

public struct KeyframeTrack<Root, TrackValue: Animatable, Content: KeyframeTrackContent>: Keyframes
where Content.Value == TrackValue {
    public typealias Value = Root
    public typealias Body = _Keyframes<Root>

    private let keyPath: WritableKeyPath<Root, TrackValue>?
    private let content: Content

    public init(
        _ keyPath: WritableKeyPath<Root, TrackValue>,
        @KeyframeTrackContentBuilder<TrackValue> content: () -> Content
    ) {
        self.keyPath = keyPath
        // This nonescaping construction is part of the caller's already-entered
        // authored factory. Guarded compilation expands custom bodies later.
        self.content = content()
    }

    public init(
        @KeyframeTrackContentBuilder<TrackValue> content: () -> Content
    ) where Root == TrackValue {
        self.init(\Root.self, content: content)
    }

    /// Compatibility extension representing no tracks and zero duration.
    public init() where TrackValue == Double, Content == _KeyframeTrackContent<Double> {
        self.keyPath = nil
        self.content = _KeyframeTrackContent(sources: [])
    }

    public var body: Body {
        guard let keyPath else { return _Keyframes(sources: []) }
        let content = content
        return _Keyframes(tracks: [
            _KeyframeTrackSource { initialValue, velocities, isCurrent in
                _keyframeCompileTrack(
                    initialValue: initialValue,
                    initialVelocities: velocities,
                    keyPath: keyPath,
                    content: content,
                    isCurrent: isCurrent
                )
            }
        ])
    }
}

public struct LinearKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = _KeyframeTrackContent<Value>

    public let value: Value
    public let duration: Double
    public let timingCurve: UnitCurve

    public init(_ value: Value, duration: Double, timingCurve: UnitCurve = .linear) {
        _keyframeValidateDuration(duration)
        self.value = value
        self.duration = duration
        self.timingCurve = timingCurve
    }

    public var body: Body {
        return Body(segment: .linear(value, duration, timingCurve))
    }
}

public struct CubicKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = _KeyframeTrackContent<Value>

    public let value: Value
    public let duration: Double
    public let startVelocity: Value?
    public let endVelocity: Value?

    public init(
        _ value: Value,
        duration: Double,
        startVelocity: Value? = nil,
        endVelocity: Value? = nil
    ) {
        _keyframeValidateDuration(duration)
        self.value = value
        self.duration = duration
        self.startVelocity = startVelocity
        self.endVelocity = endVelocity
    }

    public var body: Body {
        return Body(segment: .cubic(value, duration, startVelocity, endVelocity))
    }
}

public struct SpringKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = _KeyframeTrackContent<Value>

    public let value: Value
    public let duration: Double?
    public let spring: Spring
    public let startVelocity: Value?

    public init(
        _ value: Value,
        duration: Double? = nil,
        spring: Spring = Spring(duration: 0.5, bounce: 0),
        startVelocity: Value? = nil
    ) {
        if let duration { _keyframeValidateDuration(duration) }
        _keyframeValidateSpring(spring)
        self.value = value
        self.duration = duration
        self.spring = spring
        self.startVelocity = startVelocity
    }

    /// Compatibility with the former Animation-typed constructor. Its easing
    /// must actually be a spring; other Animation values are diagnosed.
    @_disfavoredOverload
    public init(_ value: Value, duration: Double, spring: Animation) {
        guard case .spring(let response, let dampingRatio) = spring.easing else {
            preconditionFailure("SpringKeyframe requires spring easing; use LinearKeyframe for other animations.")
        }
        self.init(value, duration: duration, spring: Spring(response: response, dampingRatio: dampingRatio))
    }

    public var body: Body {
        return Body(segment: .spring(value, duration, spring, startVelocity))
    }
}

public struct MoveKeyframe<Value: Animatable>: KeyframeTrackContent {
    public typealias Body = _KeyframeTrackContent<Value>

    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public var body: Body {
        return Body(segment: .move(value))
    }
}

internal typealias KeyframeVelocityMap = [AnyKeyPath: Any]

internal struct KeyframeSample<Root> {
    let value: Root
    let velocities: KeyframeVelocityMap
}

/// An immutable interpolation program. Property tracks are sampled in their
/// declaration order, so the last track writing a property wins.
///
/// Finite times before zero sample the beginning; times after the duration hold
/// the final value. Initial Move segments take effect at time zero. Spring and
/// UnitCurve calculations use this package's numerical models, not measured
/// native SwiftUI timing constants.
public struct KeyframeTimeline<Root> {
    public let duration: Double

    private let initialValue: Root
    private let tracks: [_KeyframeCompiledTrack<Root>]

    public init<Frames: Keyframes>(
        initialValue: Root,
        @KeyframesBuilder<Root> content: () -> Frames
    ) where Frames.Value == Root {
        let frames = content()
        guard
            let timeline = Self(
                initialValue: initialValue, initialVelocities: [:], frames: frames, isCurrent: { true }
            )
        else {
            preconditionFailure("A pure KeyframeTimeline cannot lose sampling authority.")
        }
        self = timeline
    }

    internal init?<Frames: Keyframes>(
        initialValue: Root,
        initialVelocities: KeyframeVelocityMap,
        frames: Frames,
        isCurrent: () -> Bool
    ) where Frames.Value == Root {
        guard
            let tracks = _keyframeCompileTimeline(
                initialValue: initialValue,
                initialVelocities: initialVelocities,
                frames: frames,
                isCurrent: isCurrent
            ), isCurrent()
        else { return nil }
        self.initialValue = initialValue
        self.tracks = tracks
        self.duration = tracks.reduce(0) { max($0, $1.duration) }
    }

    public func value(time: Double) -> Root {
        guard let result = sample(time: time, isCurrent: { true }) else {
            preconditionFailure("A pure KeyframeTimeline cannot lose sampling authority.")
        }
        return result.value
    }

    public func value(progress: Double) -> Root {
        precondition(progress.isFinite, "Keyframe progress must be finite.")
        return value(time: duration * min(1, max(0, progress)))
    }

    @inline(never)
    internal func sample(time: Double, isCurrent: () -> Bool) -> KeyframeSample<Root>? {
        guard isCurrent() else { return nil }
        precondition(time.isFinite, "Keyframe sample time must be finite.")
        let result = _keyframeSampleTimeline(
            initialValue: initialValue, tracks: tracks, time: max(0, time), isCurrent: isCurrent
        )
        // The helper has returned and released its temporary authored values.
        guard isCurrent() else { return nil }
        return result
    }
}

fileprivate enum _KeyframeSegment<Value: Animatable> {
    case linear(Value, Double, UnitCurve)
    case cubic(Value, Double, Value?, Value?)
    case spring(Value, Double?, Spring, Value?)
    case move(Value)
}

fileprivate typealias _KeyframeSegmentResolver<Value: Animatable> =
    (() -> Bool) -> [_KeyframeSegment<Value>]?
fileprivate typealias _KeyframeFramesResolver<Root> =
    (() -> Bool) -> [_KeyframeTrackSource<Root>]?

fileprivate struct _KeyframeTrackSource<Root> {
    let compile: (Root, KeyframeVelocityMap, () -> Bool) -> _KeyframeCompiledTrack<Root>?
}

fileprivate struct _KeyframeCompiledTrack<Root> {
    let duration: Double
    let apply: (inout Root, inout KeyframeVelocityMap, Double, () -> Bool) -> Bool
}

// Every framework entry into an authored getter, operator, or scale is isolated
// in a non-inlined helper. Its caller checks again after helper cleanup. A guard
// is only passed down the current stack, never captured by stored closures.
// This does not claim to interrupt an already-entered application function.
@inline(never)
private func _keyframeOperation<Result>(
    isCurrent: () -> Bool, _ operation: () -> Result
) -> Result? {
    guard isCurrent() else { return nil }
    let result = operation()
    guard isCurrent() else { return nil }
    return result
}

@inline(never)
private func _keyframeCollectSegments<Content: KeyframeTrackContent>(
    _ content: Content, isCurrent: () -> Bool
) -> [_KeyframeSegment<Content.Value>]? {
    guard isCurrent() else { return nil }
    if let built = content as? _KeyframeTrackContent<Content.Value> {
        var result: [_KeyframeSegment<Content.Value>] = []
        for resolve in built.sources {
            guard let segments = resolve(isCurrent), isCurrent() else { return nil }
            result.append(contentsOf: segments)
            guard isCurrent() else { return nil }
        }
        return result
    }
    guard let body = _keyframeOperation(isCurrent: isCurrent, { content.body }), isCurrent() else {
        return nil
    }
    let result = _keyframeCollectSegments(body, isCurrent: isCurrent)
    guard isCurrent() else { return nil }
    return result
}

@inline(never)
private func _keyframeCollectTracks<Frames: Keyframes>(
    _ frames: Frames, isCurrent: () -> Bool
) -> [_KeyframeTrackSource<Frames.Value>]? {
    guard isCurrent() else { return nil }
    if let built = frames as? _Keyframes<Frames.Value> {
        var result: [_KeyframeTrackSource<Frames.Value>] = []
        for resolve in built.sources {
            guard let tracks = resolve(isCurrent), isCurrent() else { return nil }
            result.append(contentsOf: tracks)
            guard isCurrent() else { return nil }
        }
        return result
    }
    guard let body = _keyframeOperation(isCurrent: isCurrent, { frames.body }), isCurrent() else {
        return nil
    }
    let result = _keyframeCollectTracks(body, isCurrent: isCurrent)
    guard isCurrent() else { return nil }
    return result
}

private func _keyframeValidateDuration(_ duration: Double) {
    precondition(duration.isFinite && duration >= 0, "Keyframe duration must be finite and nonnegative.")
}

private func _keyframeValidateSpring(_ spring: Spring) {
    precondition(
        spring.response.isFinite && spring.response > 0,
        "Keyframe spring response must be finite and positive."
    )
    precondition(
        spring.dampingRatio.isFinite && spring.dampingRatio >= 0,
        "Keyframe spring damping ratio must be finite and nonnegative."
    )
    precondition(
        spring.initialVelocity == 0,
        "Use SpringKeyframe's typed startVelocity instead of Spring.initialVelocity."
    )
}

private enum _KeyframeResolvedKind<Data: VectorArithmetic> {
    case linear(Double, UnitCurve)
    case cubic(Double, Data?, Data?)
    case spring(Double?, _KeyframeSpringModel, Data?)
    case move
}

private struct _KeyframeResolvedSegment<Value: Animatable> {
    let target: Value
    let targetData: Value.AnimatableData
    let kind: _KeyframeResolvedKind<Value.AnimatableData>
}

private enum _KeyframeCurve {
    case linear(UnitCurve)
    case cubic
    case spring(_KeyframeSpringModel)
    case move
}

private struct _KeyframeDataSample<Data: VectorArithmetic> {
    let value: Data
    let velocity: Data
}

private struct _KeyframeCompiledSegment<Value: Animatable> {
    let startTime: Double
    let duration: Double
    let startValue: Value
    let targetValue: Value
    let startData: Value.AnimatableData
    let targetData: Value.AnimatableData
    let endData: Value.AnimatableData
    let startVelocity: Value.AnimatableData
    let endVelocity: Value.AnimatableData
    let curve: _KeyframeCurve
}

private struct _KeyframeSequence<Value: Animatable> {
    let initialValue: Value
    let initialData: Value.AnimatableData
    let initialVelocity: Value.AnimatableData
    let segments: [_KeyframeCompiledSegment<Value>]
    let duration: Double
}

@inline(never)
private func _keyframeAdd<Data: VectorArithmetic>(
    _ lhs: Data, _ rhs: Data, isCurrent: () -> Bool
) -> Data? {
    guard isCurrent() else { return nil }
    if let pair = lhs as? any _KeyframeGuardedPair {
        let result = pair.keyframeAdding(rhs, isCurrent: isCurrent)
        guard isCurrent() else { return nil }
        return _keyframePairResult(result, as: Data.self)
    }
    return _keyframeOperation(isCurrent: isCurrent) { lhs + rhs }
}

@inline(never)
private func _keyframeSubtract<Data: VectorArithmetic>(
    _ lhs: Data, _ rhs: Data, isCurrent: () -> Bool
) -> Data? {
    guard isCurrent() else { return nil }
    if let pair = lhs as? any _KeyframeGuardedPair {
        let result = pair.keyframeSubtracting(rhs, isCurrent: isCurrent)
        guard isCurrent() else { return nil }
        return _keyframePairResult(result, as: Data.self)
    }
    return _keyframeOperation(isCurrent: isCurrent) { lhs - rhs }
}

@inline(never)
private func _keyframeScale<Data: VectorArithmetic>(
    _ value: Data, by factor: Double, isCurrent: () -> Bool
) -> Data? {
    guard isCurrent() else { return nil }
    precondition(factor.isFinite, "Keyframe interpolation requires finite derived coefficients.")
    if let pair = value as? any _KeyframeGuardedPair {
        let result = pair.keyframeScaled(by: factor, isCurrent: isCurrent)
        guard isCurrent() else { return nil }
        return _keyframePairResult(result, as: Data.self)
    }
    return _keyframeOperation(isCurrent: isCurrent) {
        var result = value
        result.scale(by: factor)
        return result
    }
}

@inline(never)
private func _keyframeZero<Data: VectorArithmetic>(
    _ type: Data.Type, isCurrent: () -> Bool
) -> Data? {
    guard isCurrent() else { return nil }
    if let pairType = type as? any _KeyframeGuardedPair.Type {
        let result = pairType.keyframeZero(isCurrent: isCurrent)
        guard isCurrent() else { return nil }
        return _keyframePairResult(result, as: Data.self)
    }
    return _keyframeOperation(isCurrent: isCurrent) { Data.zero }
}

@inline(never)
private func _keyframeMagnitudeSquared<Data: VectorArithmetic>(
    _ value: Data, isCurrent: () -> Bool
) -> Double? {
    guard isCurrent() else { return nil }
    if let pair = value as? any _KeyframeGuardedPair {
        let result = pair.keyframeMagnitudeSquared(isCurrent: isCurrent)
        guard isCurrent() else { return nil }
        return result
    }
    return _keyframeOperation(isCurrent: isCurrent) { value.magnitudeSquared }
}

@inline(never)
private func _keyframeReadData<Value: Animatable>(
    _ value: Value, isCurrent: () -> Bool
) -> Value.AnimatableData? {
    _keyframeOperation(isCurrent: isCurrent) { value.animatableData }
}

@inline(never)
private func _keyframeResolveSegment<Value: Animatable>(
    _ segment: _KeyframeSegment<Value>, isCurrent: () -> Bool
) -> _KeyframeResolvedSegment<Value>? {
    guard isCurrent() else { return nil }
    switch segment {
    case .linear(let target, let duration, let curve):
        guard let data = _keyframeReadData(target, isCurrent: isCurrent), isCurrent() else { return nil }
        return _KeyframeResolvedSegment(target: target, targetData: data, kind: .linear(duration, curve))
    case .cubic(let target, let duration, let start, let end):
        guard let data = _keyframeReadData(target, isCurrent: isCurrent), isCurrent() else { return nil }
        var startData: Value.AnimatableData?
        var endData: Value.AnimatableData?
        if let start {
            guard let velocity = _keyframeReadData(start, isCurrent: isCurrent), isCurrent() else { return nil }
            startData = velocity
        }
        guard isCurrent() else { return nil }
        if let end {
            guard let velocity = _keyframeReadData(end, isCurrent: isCurrent), isCurrent() else { return nil }
            endData = velocity
        }
        guard isCurrent() else { return nil }
        return _KeyframeResolvedSegment(
            target: target, targetData: data, kind: .cubic(duration, startData, endData)
        )
    case .spring(let target, let duration, let spring, let start):
        guard let data = _keyframeReadData(target, isCurrent: isCurrent), isCurrent() else { return nil }
        var startData: Value.AnimatableData?
        if let start {
            guard let velocity = _keyframeReadData(start, isCurrent: isCurrent), isCurrent() else { return nil }
            startData = velocity
        }
        guard isCurrent() else { return nil }
        return _KeyframeResolvedSegment(
            target: target, targetData: data, kind: .spring(duration, _KeyframeSpringModel(spring), startData)
        )
    case .move(let target):
        guard let data = _keyframeReadData(target, isCurrent: isCurrent), isCurrent() else { return nil }
        return _KeyframeResolvedSegment(target: target, targetData: data, kind: .move)
    }
}

@inline(never)
private func _keyframeCompileTimeline<Root, Frames: Keyframes>(
    initialValue: Root,
    initialVelocities: KeyframeVelocityMap,
    frames: Frames,
    isCurrent: () -> Bool
) -> [_KeyframeCompiledTrack<Root>]? where Frames.Value == Root {
    guard let sources = _keyframeCollectTracks(frames, isCurrent: isCurrent), isCurrent() else { return nil }
    var result: [_KeyframeCompiledTrack<Root>] = []
    for source in sources {
        guard isCurrent() else { return nil }
        guard let track = source.compile(initialValue, initialVelocities, isCurrent), isCurrent() else { return nil }
        result.append(track)
        guard isCurrent() else { return nil }
    }
    return result
}

@inline(never)
private func _keyframeCompileTrack<Root, Value: Animatable, Content: KeyframeTrackContent>(
    initialValue: Root,
    initialVelocities: KeyframeVelocityMap,
    keyPath: WritableKeyPath<Root, Value>,
    content: Content,
    isCurrent: () -> Bool
) -> _KeyframeCompiledTrack<Root>? where Content.Value == Value {
    guard let initial = _keyframeOperation(isCurrent: isCurrent, { initialValue[keyPath: keyPath] }), isCurrent(),
        let initialData = _keyframeReadData(initial, isCurrent: isCurrent), isCurrent()
    else { return nil }

    guard let stored = _keyframeOperation(isCurrent: isCurrent, { initialVelocities[keyPath] }), isCurrent() else {
        return nil
    }
    let initialVelocity: Value.AnimatableData
    if let stored {
        guard let velocity = stored as? Value.AnimatableData else {
            preconditionFailure("Keyframe interruption velocity does not match its property's animatable data.")
        }
        initialVelocity = velocity
    } else {
        guard let zero = _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent), isCurrent() else {
            return nil
        }
        initialVelocity = zero
    }
    guard isCurrent(),
        let rawSegments = _keyframeCollectSegments(content, isCurrent: isCurrent), isCurrent(),
        let sequence = _keyframeCompileSequence(
            initialValue: initial,
            initialData: initialData,
            initialVelocity: initialVelocity,
            segments: rawSegments,
            isCurrent: isCurrent
        ), isCurrent()
    else { return nil }

    return _KeyframeCompiledTrack(duration: sequence.duration) { root, velocities, time, sampleGuard in
        _keyframeApplySequence(
            sequence, keyPath: keyPath, root: &root, velocities: &velocities, time: time, isCurrent: sampleGuard
        )
    }
}

@inline(never)
private func _keyframeCompileSequence<Value: Animatable>(
    initialValue: Value,
    initialData: Value.AnimatableData,
    initialVelocity: Value.AnimatableData,
    segments: [_KeyframeSegment<Value>],
    isCurrent: () -> Bool
) -> _KeyframeSequence<Value>? {
    guard isCurrent() else { return nil }
    var resolved: [_KeyframeResolvedSegment<Value>] = []
    for segment in segments {
        guard let result = _keyframeResolveSegment(segment, isCurrent: isCurrent), isCurrent() else { return nil }
        resolved.append(result)
        guard isCurrent() else { return nil }
    }

    var compiled: [_KeyframeCompiledSegment<Value>] = []
    var startValue = initialValue
    var startData = initialData
    var incomingVelocity = initialVelocity
    var elapsed = 0.0
    for index in resolved.indices {
        guard isCurrent(),
            let segment = _keyframeCompileSegment(
                resolved[index],
                next: index + 1 < resolved.count ? resolved[index + 1] : nil,
                startTime: elapsed,
                startValue: startValue,
                startData: startData,
                incomingVelocity: incomingVelocity,
                isCurrent: isCurrent
            ), isCurrent()
        else { return nil }
        let endTime = elapsed + segment.duration
        precondition(endTime.isFinite, "The sum of keyframe segment durations must be finite.")
        precondition(
            segment.duration == 0 || endTime > elapsed,
            "A positive keyframe duration is below the timeline's time precision."
        )
        compiled.append(segment)
        startValue = segment.targetValue
        startData = segment.endData
        incomingVelocity = segment.endVelocity
        elapsed = endTime
        // Replacing cached generic values can release authored payloads.
        guard isCurrent() else { return nil }
    }
    return _KeyframeSequence(
        initialValue: initialValue,
        initialData: initialData,
        initialVelocity: initialVelocity,
        segments: compiled,
        duration: elapsed
    )
}

@inline(never)
private func _keyframeCompileSegment<Value: Animatable>(
    _ segment: _KeyframeResolvedSegment<Value>,
    next: _KeyframeResolvedSegment<Value>?,
    startTime: Double,
    startValue: Value,
    startData: Value.AnimatableData,
    incomingVelocity: Value.AnimatableData,
    isCurrent: () -> Bool
) -> _KeyframeCompiledSegment<Value>? {
    guard isCurrent() else { return nil }
    let duration: Double
    let startVelocity: Value.AnimatableData
    let endVelocity: Value.AnimatableData
    let endData: Value.AnimatableData
    let curve: _KeyframeCurve
    switch segment.kind {
    case .move:
        guard let zero = _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent), isCurrent() else {
            return nil
        }
        duration = 0
        startVelocity = zero
        endVelocity = zero
        endData = segment.targetData
        curve = .move
    case .linear(let length, let timingCurve):
        guard
            let end = _keyframeLinearSample(
                start: startData, target: segment.targetData, duration: length, curve: timingCurve,
                time: length, isCurrent: isCurrent
            ), isCurrent()
        else { return nil }
        duration = length
        startVelocity = incomingVelocity
        endVelocity = end.velocity
        endData = end.value
        curve = .linear(timingCurve)
    case .cubic(let length, let explicitStart, let explicitEnd):
        duration = length
        curve = .cubic
        endData = segment.targetData
        if length == 0 {
            guard let zero = _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent), isCurrent() else {
                return nil
            }
            startVelocity = zero
            endVelocity = zero
        } else {
            startVelocity = explicitStart ?? incomingVelocity
            if let explicitEnd {
                endVelocity = explicitEnd
            } else {
                guard
                    let inferred = _keyframeCubicEndVelocity(
                        start: startData, target: segment.targetData, duration: length,
                        next: next, isCurrent: isCurrent
                    ), isCurrent()
                else { return nil }
                endVelocity = inferred
            }
        }
    case .spring(let requestedDuration, let model, let explicitStart):
        startVelocity = explicitStart ?? incomingVelocity
        if let requestedDuration {
            duration = requestedDuration
        } else {
            guard
                let settledDuration = _keyframeAutomaticSpringDuration(
                    start: startData, target: segment.targetData, velocity: startVelocity,
                    model: model, isCurrent: isCurrent
                ), isCurrent()
            else { return nil }
            duration = settledDuration
        }
        guard
            let end = _keyframeSpringSample(
                start: startData, target: segment.targetData, velocity: startVelocity,
                model: model, time: duration, isCurrent: isCurrent
            ), isCurrent()
        else { return nil }
        endData = end.value
        endVelocity = end.velocity
        curve = .spring(model)
    }
    guard isCurrent() else { return nil }
    return _KeyframeCompiledSegment(
        startTime: startTime,
        duration: duration,
        startValue: startValue,
        targetValue: segment.target,
        startData: startData,
        targetData: segment.targetData,
        endData: endData,
        startVelocity: startVelocity,
        endVelocity: endVelocity,
        curve: curve
    )
}

@inline(never)
private func _keyframeCubicEndVelocity<Value: Animatable>(
    start: Value.AnimatableData,
    target: Value.AnimatableData,
    duration: Double,
    next: _KeyframeResolvedSegment<Value>?,
    isCurrent: () -> Bool
) -> Value.AnimatableData? {
    guard isCurrent() else { return nil }
    guard let next else { return _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent) }
    switch next.kind {
    case .move:
        return _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent)
    case .linear(let nextDuration, let curve):
        guard nextDuration > 0 else { return _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent) }
        guard let delta = _keyframeSubtract(next.targetData, target, isCurrent: isCurrent), isCurrent() else {
            return nil
        }
        return _keyframeScale(delta, by: _keyframeCurveDerivative(curve, at: 0) / nextDuration, isCurrent: isCurrent)
    case .cubic(let nextDuration, let explicitStart, _):
        guard nextDuration > 0 else { return _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent) }
        if let explicitStart { return explicitStart }
        guard let leftDelta = _keyframeSubtract(target, start, isCurrent: isCurrent), isCurrent(),
            let rightDelta = _keyframeSubtract(next.targetData, target, isCurrent: isCurrent), isCurrent(),
            let leftSlope = _keyframeScale(leftDelta, by: 1 / duration, isCurrent: isCurrent), isCurrent(),
            let rightSlope = _keyframeScale(rightDelta, by: 1 / nextDuration, isCurrent: isCurrent), isCurrent()
        else { return nil }
        // Nonuniform Catmull-Rom uses the opposite interval's weight.
        let total = duration + nextDuration
        precondition(total.isFinite, "The sum of keyframe segment durations must be finite.")
        guard let left = _keyframeScale(leftSlope, by: nextDuration / total, isCurrent: isCurrent), isCurrent(),
            let right = _keyframeScale(rightSlope, by: duration / total, isCurrent: isCurrent), isCurrent()
        else { return nil }
        return _keyframeAdd(left, right, isCurrent: isCurrent)
    case .spring(let nextDuration, _, let explicitStart):
        if let explicitStart { return explicitStart }
        guard nextDuration != 0 else { return _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent) }
        // The spring inherits this secant. Depending on its eventual settling
        // duration here would create a circular tangent/duration calculation.
        guard let delta = _keyframeSubtract(target, start, isCurrent: isCurrent), isCurrent() else { return nil }
        return _keyframeScale(delta, by: 1 / duration, isCurrent: isCurrent)
    }
}

// These derivatives describe the existing UnitCurve.value(at:) implementation.
// In particular, its circular names currently evaluate linearly and its bouncy
// curve does not end at one. We preserve that value and carry the resulting
// endpoint into the following segment instead of silently repairing UnitCurve.
private func _keyframeCurveDerivative(_ curve: UnitCurve, at progress: Double) -> Double {
    switch curve.description {
    case "easeIn":
        return 2 * progress
    case "easeOut":
        return 2 * (1 - progress)
    case "easeInOut", "smooth":
        return progress < 0.5 ? 4 * progress : 4 * (1 - progress)
    case "bouncy":
        let angle = 2 * Double.pi * progress
        let decay = exp(-2 * progress)
        let unclamped = 1 - decay * cos(angle)
        guard unclamped >= 0 && unclamped < 1 else { return 0 }
        return decay * (2 * cos(angle) + 2 * Double.pi * sin(angle))
    default:
        return 1
    }
}

@inline(never)
private func _keyframeLinearSample<Data: VectorArithmetic>(
    start: Data,
    target: Data,
    duration: Double,
    curve: UnitCurve,
    time: Double,
    isCurrent: () -> Bool
) -> _KeyframeDataSample<Data>? {
    guard isCurrent() else { return nil }
    if duration == 0 {
        guard let zero = _keyframeZero(Data.self, isCurrent: isCurrent), isCurrent() else { return nil }
        return _KeyframeDataSample(value: target, velocity: zero)
    }
    let progress = min(1, max(0, time / duration))
    let amount = curve.value(at: progress)
    guard let delta = _keyframeSubtract(target, start, isCurrent: isCurrent), isCurrent() else { return nil }
    let value: Data
    if amount == 0 {
        value = start
    } else if amount == 1 {
        value = target
    } else {
        guard let offset = _keyframeScale(delta, by: amount, isCurrent: isCurrent), isCurrent(),
            let interpolated = _keyframeAdd(start, offset, isCurrent: isCurrent), isCurrent()
        else { return nil }
        value = interpolated
    }
    guard
        let velocity = _keyframeScale(
            delta, by: _keyframeCurveDerivative(curve, at: progress) / duration, isCurrent: isCurrent
        ), isCurrent()
    else { return nil }
    return _KeyframeDataSample(value: value, velocity: velocity)
}

@inline(never)
private func _keyframeCubicSample<Data: VectorArithmetic>(
    start: Data,
    target: Data,
    startVelocity: Data,
    endVelocity: Data,
    duration: Double,
    time: Double,
    isCurrent: () -> Bool
) -> _KeyframeDataSample<Data>? {
    guard isCurrent() else { return nil }
    if duration == 0 {
        guard let zero = _keyframeZero(Data.self, isCurrent: isCurrent), isCurrent() else { return nil }
        return _KeyframeDataSample(value: target, velocity: zero)
    }
    if time <= 0 { return _KeyframeDataSample(value: start, velocity: startVelocity) }
    if time >= duration { return _KeyframeDataSample(value: target, velocity: endVelocity) }
    let t = time / duration
    let squared = t * t
    let cubed = squared * t
    guard let delta = _keyframeSubtract(target, start, isCurrent: isCurrent), isCurrent(),
        let positionDelta = _keyframeScale(delta, by: 3 * squared - 2 * cubed, isCurrent: isCurrent), isCurrent(),
        let startTangent = _keyframeScale(
            startVelocity, by: duration * (cubed - 2 * squared + t), isCurrent: isCurrent
        ), isCurrent(),
        let endTangent = _keyframeScale(
            endVelocity, by: duration * (cubed - squared), isCurrent: isCurrent
        ), isCurrent(),
        let positionBase = _keyframeAdd(start, positionDelta, isCurrent: isCurrent), isCurrent(),
        let withStartTangent = _keyframeAdd(positionBase, startTangent, isCurrent: isCurrent), isCurrent(),
        let value = _keyframeAdd(withStartTangent, endTangent, isCurrent: isCurrent), isCurrent(),
        let velocityDelta = _keyframeScale(
            delta, by: (6 * t - 6 * squared) / duration, isCurrent: isCurrent
        ), isCurrent(),
        let startDerivative = _keyframeScale(
            startVelocity, by: 3 * squared - 4 * t + 1, isCurrent: isCurrent
        ), isCurrent(),
        let endDerivative = _keyframeScale(
            endVelocity, by: 3 * squared - 2 * t, isCurrent: isCurrent
        ), isCurrent(),
        let velocityBase = _keyframeAdd(velocityDelta, startDerivative, isCurrent: isCurrent), isCurrent(),
        let velocity = _keyframeAdd(velocityBase, endDerivative, isCurrent: isCurrent), isCurrent()
    else { return nil }
    return _KeyframeDataSample(value: value, velocity: velocity)
}

private struct _KeyframeSpringCoefficients {
    let displacement: Double
    let incomingVelocity: Double
    let displacementDerivative: Double
    let velocityDerivative: Double

    static let initial = _KeyframeSpringCoefficients(
        displacement: 1, incomingVelocity: 0, displacementDerivative: 0, velocityDerivative: 1
    )
    static let decayed = _KeyframeSpringCoefficients(
        displacement: 0, incomingVelocity: 0, displacementDerivative: 0, velocityDerivative: 0
    )
}

private struct _KeyframeSpringModel {
    private enum Regime {
        case underdamped(decay: Double, frequency: Double)
        case critical
        case overdamped(slow: Double, fast: Double, gap: Double)
    }

    let frequency: Double
    let dampingRatio: Double
    let slowNormalizedRate: Double
    private let regime: Regime

    init(_ spring: Spring) {
        _keyframeValidateSpring(spring)
        let frequency = 2 * Double.pi / spring.response
        precondition(
            frequency.isFinite && frequency > 0,
            "Keyframe spring response must produce a finite positive frequency."
        )
        self.frequency = frequency
        self.dampingRatio = spring.dampingRatio
        if spring.dampingRatio < 1 {
            let decay = frequency * spring.dampingRatio
            let oscillation = frequency * sqrt((1 - spring.dampingRatio) * (1 + spring.dampingRatio))
            self.slowNormalizedRate = spring.dampingRatio
            self.regime = .underdamped(decay: decay, frequency: oscillation)
        } else if spring.dampingRatio == 1 {
            self.slowNormalizedRate = 1
            self.regime = .critical
        } else {
            let inverseDamping = 1 / spring.dampingRatio
            let slowRate = inverseDamping / (1 + sqrt((1 - inverseDamping) * (1 + inverseDamping)))
            let slow = -frequency * slowRate
            let fast = -frequency / slowRate
            let gap = slow - fast
            precondition(
                slowRate > 0 && slow.isFinite && fast.isFinite && gap.isFinite,
                "Keyframe spring parameters must produce finite decay rates."
            )
            self.slowNormalizedRate = slowRate
            self.regime = .overdamped(slow: slow, fast: fast, gap: gap)
        }
    }

    func coefficients(at time: Double) -> _KeyframeSpringCoefficients {
        if time == 0 { return .initial }
        let position: Double
        let velocity: Double
        let displacementDerivative: Double
        let velocityDerivative: Double
        let logTime = log(time)
        let logFrequency = log(frequency)
        switch regime {
        case .underdamped(let decayRate, let oscillation):
            let elapsedDecay = decayRate * time
            if elapsedDecay.isInfinite { return .decayed }
            let angle = oscillation * time
            precondition(angle.isFinite, "Keyframe spring phase exceeds finite numerical precision.")
            let logVelocityScale: Double
            let sign: Double
            if angle < 0.0001 {
                logVelocityScale = logTime + log(_keyframeSinc(angle))
                sign = 1
            } else {
                let sine = sin(angle)
                logVelocityScale = sine == 0 ? -.infinity : log(abs(sine)) - log(oscillation)
                sign = sine == 0 ? 0 : (sine < 0 ? -1 : 1)
            }
            let cosine = exp(-elapsedDecay) * cos(angle)
            velocity = _keyframeExponentialProduct(
                logScale: logVelocityScale, sign: sign, decay: elapsedDecay
            )
            let normalizedVelocity = _keyframeExponentialProduct(
                logScale: logVelocityScale + logFrequency, sign: sign, decay: elapsedDecay
            )
            let decayTerm = dampingRatio * normalizedVelocity
            position = cosine + decayTerm
            velocityDerivative = cosine - decayTerm
            displacementDerivative = _keyframeExponentialProduct(
                logScale: logVelocityScale + 2 * logFrequency, sign: -sign, decay: elapsedDecay
            )
        case .critical:
            let elapsedDecay = frequency * time
            if elapsedDecay.isInfinite { return .decayed }
            position = exp(log1p(elapsedDecay) - elapsedDecay)
            velocity = _keyframeExponentialProduct(logScale: logTime, decay: elapsedDecay)
            displacementDerivative = _keyframeExponentialProduct(
                logScale: logTime + 2 * logFrequency, sign: -1, decay: elapsedDecay
            )
            let derivativeScale = 1 - elapsedDecay
            velocityDerivative =
                derivativeScale == 0
                ? 0
                : _keyframeExponentialProduct(
                    logScale: log(abs(derivativeScale)), sign: derivativeScale < 0 ? -1 : 1, decay: elapsedDecay
                )
        case .overdamped(let slow, let fast, let gap):
            let elapsedDecay = -slow * time
            if elapsedDecay.isInfinite { return .decayed }
            let fastDecay = exp(fast * time)
            let span = gap * time
            let logVelocityScale: Double
            if span < 0.0001 {
                // expm1 and this limit avoid cancellation near critical damping.
                logVelocityScale = logTime + log(_keyframeExponentialRatio(span))
            } else {
                logVelocityScale = log(-expm1(-span)) - log(gap)
            }
            velocity = _keyframeExponentialProduct(logScale: logVelocityScale, decay: elapsedDecay)
            let logSlowScale = slow == 0 ? -Double.infinity : logVelocityScale + log(-slow)
            let slowTerm = _keyframeExponentialProduct(logScale: logSlowScale, decay: elapsedDecay)
            // Combine these positive terms before rounding to a subnormal.
            position = _keyframeExponentialProduct(
                logScale: _keyframeLogAdd(0, logSlowScale), decay: elapsedDecay
            )
            velocityDerivative = fastDecay - slowTerm
            displacementDerivative = _keyframeExponentialProduct(
                logScale: logVelocityScale + 2 * logFrequency, sign: -1, decay: elapsedDecay
            )
        }
        precondition(
            position.isFinite && velocity.isFinite && displacementDerivative.isFinite && velocityDerivative.isFinite,
            "Keyframe spring sampling requires finite derived coefficients."
        )
        return _KeyframeSpringCoefficients(
            displacement: position,
            incomingVelocity: velocity,
            displacementDerivative: displacementDerivative,
            velocityDerivative: velocityDerivative
        )
    }
}

// Exponentials can underflow even though a time- or frequency-scaled
// coefficient remains representable. Form the complete product in log space;
// only an infinite decay exponent proves that every finite scale has decayed.
private func _keyframeExponentialProduct(
    logScale: Double, sign: Double = 1, decay: Double
) -> Double {
    if sign == 0 || logScale == -.infinity { return 0 }
    return sign * exp(logScale - decay)
}

private func _keyframeSinc(_ value: Double) -> Double {
    if abs(value) < 0.0001 {
        let squared = value * value
        return 1 - squared / 6 + squared * squared / 120
    }
    return sin(value) / value
}

private func _keyframeExponentialRatio(_ value: Double) -> Double {
    if value == 0 { return 1 }
    return -expm1(-value) / value
}

@inline(never)
private func _keyframeSpringSample<Data: VectorArithmetic>(
    start: Data,
    target: Data,
    velocity: Data,
    model: _KeyframeSpringModel,
    time: Double,
    isCurrent: () -> Bool
) -> _KeyframeDataSample<Data>? {
    guard isCurrent() else { return nil }
    if time == 0 { return _KeyframeDataSample(value: start, velocity: velocity) }
    let coefficients = model.coefficients(at: time)
    guard let displacement = _keyframeSubtract(start, target, isCurrent: isCurrent), isCurrent(),
        let initialPositionTerm = _keyframeScale(
            displacement, by: coefficients.displacement, isCurrent: isCurrent
        ), isCurrent(),
        let initialVelocityTerm = _keyframeScale(
            velocity, by: coefficients.incomingVelocity, isCurrent: isCurrent
        ), isCurrent(),
        let offset = _keyframeAdd(initialPositionTerm, initialVelocityTerm, isCurrent: isCurrent), isCurrent(),
        let value = _keyframeAdd(target, offset, isCurrent: isCurrent), isCurrent(),
        let positionDerivative = _keyframeScale(
            displacement, by: coefficients.displacementDerivative, isCurrent: isCurrent
        ), isCurrent(),
        let velocityDerivative = _keyframeScale(
            velocity, by: coefficients.velocityDerivative, isCurrent: isCurrent
        ), isCurrent(),
        let derivative = _keyframeAdd(positionDerivative, velocityDerivative, isCurrent: isCurrent), isCurrent()
    else { return nil }
    return _KeyframeDataSample(value: value, velocity: derivative)
}

// This is a conservative bound on ALL future positions and normalized
// velocities, using the norm's triangle inequality, not a sample at a zero
// crossing. Automatic settling accepts a 0.001 * max(1, initial distance)
// bound, within 60 seconds, and refines it with exactly 48 bisections. Failure
// to establish that bound requires an explicit duration. Neither accepted nor
// explicit durations snap a spring to its target.
@inline(never)
private func _keyframeAutomaticSpringDuration<Data: VectorArithmetic>(
    start: Data,
    target: Data,
    velocity: Data,
    model: _KeyframeSpringModel,
    isCurrent: () -> Bool
) -> Double? {
    guard let displacement = _keyframeSubtract(start, target, isCurrent: isCurrent), isCurrent(),
        let normalizedVelocity = _keyframeScale(velocity, by: 1 / model.frequency, isCurrent: isCurrent), isCurrent(),
        let distanceSquared = _keyframeMagnitudeSquared(displacement, isCurrent: isCurrent), isCurrent(),
        let velocitySquared = _keyframeMagnitudeSquared(normalizedVelocity, isCurrent: isCurrent),
        isCurrent()
    else { return nil }
    precondition(
        distanceSquared.isFinite && distanceSquared >= 0 && velocitySquared.isFinite && velocitySquared >= 0,
        "Automatic spring settling requires finite, nonnegative animatable magnitudes; supply an explicit duration."
    )
    let distance = sqrt(distanceSquared)
    let speed = sqrt(velocitySquared)
    if distance == 0 && speed == 0 { return 0 }
    precondition(
        model.dampingRatio > 0,
        "An undamped nonstationary spring needs an explicit finite duration."
    )
    let rate = model.frequency * model.slowNormalizedRate
    precondition(
        rate.isFinite && rate > 0,
        "Automatic spring settling requires a representable positive decay rate; supply an explicit duration."
    )
    let tolerance = log(0.001 * max(1, distance))
    let positionSlope = speed + model.slowNormalizedRate * distance
    let velocitySlope = distance + model.slowNormalizedRate * speed
    func isSettled(at time: Double) -> Bool {
        _keyframeFutureBoundLog(
            constant: distance, slope: positionSlope, normalizedRate: model.slowNormalizedRate,
            elapsedDecay: rate * time
        ) <= tolerance
            && _keyframeFutureBoundLog(
                constant: speed, slope: velocitySlope, normalizedRate: model.slowNormalizedRate,
                elapsedDecay: rate * time
            ) <= tolerance
    }
    let horizon = 60.0
    precondition(
        isSettled(at: horizon),
        "Automatic settling could not be established within 60 seconds; supply an explicit duration."
    )
    if isSettled(at: 0) { return 0 }
    var lower = 0.0
    var upper = horizon
    for _ in 0..<48 {
        let midpoint = lower + (upper - lower) / 2
        if isSettled(at: midpoint) {
            upper = midpoint
        } else {
            lower = midpoint
        }
    }
    guard isCurrent() else { return nil }
    return upper
}

private func _keyframeFutureBoundLog(
    constant: Double, slope: Double, normalizedRate: Double, elapsedDecay: Double
) -> Double {
    if elapsedDecay == .infinity { return -.infinity }
    let constantLog = constant == 0 ? -Double.infinity : log(constant)
    if slope == 0 { return constantLog - elapsedDecay }
    let slopeLog = log(slope)
    let rateLog = log(normalizedRate)
    let peak = constant == 0 ? 1 : max(0, 1 - exp(constantLog + rateLog - slopeLog))
    let decay = max(elapsedDecay, peak)
    let changingLog = decay == 0 ? -Double.infinity : slopeLog - rateLog + log(decay)
    return _keyframeLogAdd(constantLog, changingLog) - decay
}

private func _keyframeLogAdd(_ lhs: Double, _ rhs: Double) -> Double {
    if lhs == -.infinity { return rhs }
    if rhs == -.infinity { return lhs }
    let larger = max(lhs, rhs)
    return larger + log1p(exp(min(lhs, rhs) - larger))
}

private struct _KeyframeRawSample<Value: Animatable> {
    let prototype: Value
    let data: Value.AnimatableData
    let velocity: Value.AnimatableData
}

@inline(never)
private func _keyframeSampleSequence<Value: Animatable>(
    _ sequence: _KeyframeSequence<Value>, time: Double, isCurrent: () -> Bool
) -> _KeyframeRawSample<Value>? {
    guard isCurrent() else { return nil }
    var prototype = sequence.initialValue
    var data = sequence.initialData
    var velocity = sequence.initialVelocity
    for segment in sequence.segments {
        guard isCurrent() else { return nil }
        let end = segment.startTime + segment.duration
        if segment.duration > 0 && time < end {
            let localTime = max(0, time - segment.startTime)
            guard let sample = _keyframeSampleSegment(segment, time: localTime, isCurrent: isCurrent), isCurrent()
            else {
                return nil
            }
            return _KeyframeRawSample(prototype: segment.startValue, data: sample.value, velocity: sample.velocity)
        }
        // Boundary sampling is right-continuous: zero-time moves, including a
        // sequence of moves at time zero, are applied in declaration order.
        prototype = segment.targetValue
        data = segment.endData
        velocity = segment.endVelocity
        guard isCurrent() else { return nil }
    }
    if time > sequence.duration || sequence.segments.isEmpty {
        guard let zero = _keyframeZero(Value.AnimatableData.self, isCurrent: isCurrent), isCurrent() else { return nil }
        velocity = zero
        guard isCurrent() else { return nil }
    }
    return _KeyframeRawSample(prototype: prototype, data: data, velocity: velocity)
}

@inline(never)
private func _keyframeSampleSegment<Value: Animatable>(
    _ segment: _KeyframeCompiledSegment<Value>, time: Double, isCurrent: () -> Bool
) -> _KeyframeDataSample<Value.AnimatableData>? {
    guard isCurrent() else { return nil }
    switch segment.curve {
    case .linear(let curve):
        return _keyframeLinearSample(
            start: segment.startData, target: segment.targetData, duration: segment.duration,
            curve: curve, time: time, isCurrent: isCurrent
        )
    case .cubic:
        return _keyframeCubicSample(
            start: segment.startData, target: segment.targetData,
            startVelocity: segment.startVelocity, endVelocity: segment.endVelocity,
            duration: segment.duration, time: time, isCurrent: isCurrent
        )
    case .spring(let model):
        return _keyframeSpringSample(
            start: segment.startData, target: segment.targetData, velocity: segment.startVelocity,
            model: model, time: time, isCurrent: isCurrent
        )
    case .move:
        return _KeyframeDataSample(value: segment.endData, velocity: segment.endVelocity)
    }
}

@inline(never)
private func _keyframeApplySequence<Root, Value: Animatable>(
    _ sequence: _KeyframeSequence<Value>,
    keyPath: WritableKeyPath<Root, Value>,
    root: inout Root,
    velocities: inout KeyframeVelocityMap,
    time: Double,
    isCurrent: () -> Bool
) -> Bool {
    guard let sample = _keyframeSampleSequence(sequence, time: time, isCurrent: isCurrent), isCurrent(),
        let value = _keyframeOperation(
            isCurrent: isCurrent,
            {
                var value = sample.prototype
                value.animatableData = sample.data
                return value
            }), isCurrent()
    else { return false }
    guard _keyframeWrite(value, to: &root, keyPath: keyPath, isCurrent: isCurrent), isCurrent() else { return false }
    guard
        _keyframeStoreVelocity(
            sample.velocity, keyPath: keyPath, velocities: &velocities, isCurrent: isCurrent
        ), isCurrent()
    else { return false }
    return true
}

@inline(never)
private func _keyframeWrite<Root, Value>(
    _ value: Value, to root: inout Root, keyPath: WritableKeyPath<Root, Value>, isCurrent: () -> Bool
) -> Bool {
    guard isCurrent() else { return false }
    root[keyPath: keyPath] = value
    return isCurrent()
}

@inline(never)
private func _keyframeStoreVelocity<Data>(
    _ velocity: Data, keyPath: AnyKeyPath, velocities: inout KeyframeVelocityMap, isCurrent: () -> Bool
) -> Bool {
    guard isCurrent() else { return false }
    velocities[keyPath] = velocity
    return isCurrent()
}

@inline(never)
private func _keyframeSampleTimeline<Root>(
    initialValue: Root,
    tracks: [_KeyframeCompiledTrack<Root>],
    time: Double,
    isCurrent: () -> Bool
) -> KeyframeSample<Root>? {
    guard isCurrent() else { return nil }
    var value = initialValue
    var velocities: KeyframeVelocityMap = [:]
    for track in tracks {
        guard isCurrent(), track.apply(&value, &velocities, time, isCurrent), isCurrent() else { return nil }
    }
    return KeyframeSample(value: value, velocities: velocities)
}

// The ordinary AnimatablePair implementation remains unchanged. Keyframes must
// additionally check between its component operations because that composition
// is framework-owned: one component can retire playback before the next runs.
private protocol _KeyframeGuardedPair {
    func keyframeAdding(_ other: Any, isCurrent: () -> Bool) -> Any?
    func keyframeSubtracting(_ other: Any, isCurrent: () -> Bool) -> Any?
    func keyframeScaled(by factor: Double, isCurrent: () -> Bool) -> Any?
    func keyframeMagnitudeSquared(isCurrent: () -> Bool) -> Double?
    static func keyframeZero(isCurrent: () -> Bool) -> Any?
}

@inline(never)
private func _keyframePairResult<Data>(_ result: Any?, as type: Data.Type) -> Data? {
    guard let result else { return nil }
    guard let typed = result as? Data else {
        preconditionFailure("Internal keyframe pair arithmetic returned an incompatible vector.")
    }
    return typed
}

extension AnimatablePair: _KeyframeGuardedPair {
    @inline(never)
    fileprivate func keyframeAdding(_ other: Any, isCurrent: () -> Bool) -> Any? {
        guard isCurrent() else { return nil }
        guard let other = other as? Self else {
            preconditionFailure("Internal keyframe pair operands must have the same type.")
        }
        guard let first = _keyframeAdd(self.first, other.first, isCurrent: isCurrent), isCurrent(),
            let second = _keyframeAdd(self.second, other.second, isCurrent: isCurrent), isCurrent()
        else { return nil }
        return Self(first, second)
    }

    @inline(never)
    fileprivate func keyframeSubtracting(_ other: Any, isCurrent: () -> Bool) -> Any? {
        guard isCurrent() else { return nil }
        guard let other = other as? Self else {
            preconditionFailure("Internal keyframe pair operands must have the same type.")
        }
        guard let first = _keyframeSubtract(self.first, other.first, isCurrent: isCurrent), isCurrent(),
            let second = _keyframeSubtract(self.second, other.second, isCurrent: isCurrent), isCurrent()
        else { return nil }
        return Self(first, second)
    }

    @inline(never)
    fileprivate func keyframeScaled(by factor: Double, isCurrent: () -> Bool) -> Any? {
        guard let first = _keyframeScale(self.first, by: factor, isCurrent: isCurrent), isCurrent(),
            let second = _keyframeScale(self.second, by: factor, isCurrent: isCurrent), isCurrent()
        else { return nil }
        return Self(first, second)
    }

    @inline(never)
    fileprivate func keyframeMagnitudeSquared(isCurrent: () -> Bool) -> Double? {
        guard let first = _keyframeMagnitudeSquared(self.first, isCurrent: isCurrent), isCurrent(),
            let second = _keyframeMagnitudeSquared(self.second, isCurrent: isCurrent), isCurrent()
        else { return nil }
        return first + second
    }

    @inline(never)
    fileprivate static func keyframeZero(isCurrent: () -> Bool) -> Any? {
        guard let first = _keyframeZero(First.AnimatableData.self, isCurrent: isCurrent), isCurrent(),
            let second = _keyframeZero(Second.AnimatableData.self, isCurrent: isCurrent), isCurrent()
        else { return nil }
        return Self(first, second)
    }
}
