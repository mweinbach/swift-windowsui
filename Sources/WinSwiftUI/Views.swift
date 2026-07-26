import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

import SwiftWindowsUI

// MARK: - AsyncImage

// MARK: - GridItem

// MARK: - LazyVGrid

// MARK: - LazyHGrid

// MARK: - Grid Resolution Helpers

// MARK: - Table

// MARK: - Canvas

// MARK: - Placeholder Panels for Platform-Specific Views

private let defaultRetainedScrollIndicatorInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
private func retainedScrollAnchor(from anchor: UnitPoint?) -> RetainedScrollAnchor? {
    anchor.map { RetainedScrollAnchor(x: $0.x, y: $0.y) }
}
private func stackMainAlignment(from value: Double) -> StackMainAlignment {
    if value <= 0.25 {
        return .start
    }
    if value >= 0.75 {
        return .end
    }
    return .center
}
private func stackCrossAlignment(from value: Double) -> StackCrossAlignment {
    if value <= 0.25 {
        return .leading
    }
    if value >= 0.75 {
        return .trailing
    }
    return .center
}
public struct GeometryProxy {
    public let size: Size
    public let safeAreaInsets: EdgeInsets
    public var frameResolver: ((CoordinateSpace) -> Rect)?

    public init(size: Size, safeAreaInsets: EdgeInsets = .zero, frameResolver: ((CoordinateSpace) -> Rect)? = nil) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
        self.frameResolver = frameResolver
    }

    public func frame(in coordinateSpace: CoordinateSpace) -> Rect {
        if let frameResolver {
            return frameResolver(coordinateSpace)
        }
        return Rect(x: 0, y: 0, width: size.width, height: size.height)
    }

    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> Rect {
        frame(in: coordinateSpace.coordinateSpace)
    }

    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> Rect? {
        frame(in: coordinateSpace.coordinateSpace)
    }

    public subscript<Value>(anchor: Anchor<Value>) -> Value {
        anchor.value
    }
}
public struct GeometryProxy3D {
    public let size: Size3D
    public let safeAreaInsets: EdgeInsets3D

    public init(size: Size3D, safeAreaInsets: EdgeInsets3D = .zero) {
        self.size = size
        self.safeAreaInsets = safeAreaInsets
    }

    public func frame(in coordinateSpace: CoordinateSpace) -> Rect3D {
        let _ = coordinateSpace
        return Rect3D(origin: .zero, size: size)
    }

    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> Rect3D {
        frame(in: coordinateSpace.coordinateSpace)
    }

    public func transform(in coordinateSpace: some CoordinateSpaceProtocol) -> AffineTransform3D? {
        let _ = coordinateSpace
        return .identity
    }

    public subscript<Value>(anchor: Anchor<Value>) -> Value {
        anchor.value
    }
}
@MainActor
public final class PhaseAnimatorTaskManager: @unchecked Sendable {
    public static let shared = PhaseAnimatorTaskManager()
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    public func start<Phase: Equatable>(
        key: String,
        runtime: RetainedViewRuntime,
        signature: String,
        phases: [Phase],
        animation: @escaping (Phase) -> Animation?,
        invalidate: @escaping () -> Void
    ) {
        tasks[key]?.cancel()
        tasks[key] = Task { @MainActor [weak self, weak runtime] in
            guard let self = self else { return }
            guard let runtime = runtime else {
                self.tasks.removeValue(forKey: key)
                return
            }
            for i in 1..<phases.count {
                let animationForPhase = animation(phases[i - 1])
                let duration = animationForPhase?.duration ?? 0.0
                do {
                    if duration > 0 {
                        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    } else {
                        await Task.yield()
                    }
                } catch {
                    self.tasks.removeValue(forKey: key)
                    return
                }

                guard let node = self.findNode(in: runtime.root, signature: signature) else {
                    self.tasks.removeValue(forKey: key)
                    return
                }
                if let state = node.phaseAnimatorState,
                    state.phasesSignature == signature,
                    state.currentPhaseIndex == i - 1
                {
                    node.phaseAnimatorState?.currentPhaseIndex = i
                    node.phaseAnimatorState?.phaseStartTime = Win32Window.currentTimestampSeconds()
                    invalidate()
                }
            }
            self.tasks.removeValue(forKey: key)
        }
    }

    public func hasActiveTask(key: String) -> Bool {
        tasks[key] != nil
    }

    public func cancel(key: String) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }

    private func findNode(in root: ViewNode, signature: String) -> ViewNode? {
        if root.phaseAnimatorState?.phasesSignature == signature {
            return root
        }
        for child in root.children {
            if let found = findNode(in: child, signature: signature) {
                return found
            }
        }
        return nil
    }
}
public protocol Keyframe {}
public protocol Keyframes {}
public struct KeyframeTrack<Value>: Keyframes where Value: Animatable {
    public init() {}
}
public struct LinearKeyframe<Value>: Keyframe where Value: Animatable {
    public let value: Value
    public let duration: Double

    public init(_ value: Value, duration: Double) {
        self.value = value
        self.duration = duration
    }
}
public struct CubicKeyframe<Value>: Keyframe where Value: Animatable {
    public let value: Value
    public let duration: Double

    public init(_ value: Value, duration: Double) {
        self.value = value
        self.duration = duration
    }
}
public struct SpringKeyframe<Value>: Keyframe where Value: Animatable {
    public let value: Value
    public let duration: Double
    public let spring: Animation

    public init(_ value: Value, duration: Double, spring: Animation = .default) {
        self.value = value
        self.duration = duration
        self.spring = spring
    }
}
public struct MoveKeyframe<Value>: Keyframe where Value: Animatable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }
}
@MainActor
public struct KeyframeAnimator<Value>: View where Value: Animatable {
    public typealias Body = Never

    private let initialValue: Value
    private let triggerDescription: String?
    private let content: (Value) -> [AnyView]
    private let keyframes: (KeyframeTrack<Value>) -> Keyframes

    public init(
        initialValue: Value,
        repeating: Bool = true,
        @ViewBuilder content: @escaping (Value) -> [AnyView],
        keyframes: @escaping (KeyframeTrack<Value>) -> Keyframes
    ) {
        self.initialValue = initialValue
        self.triggerDescription = nil
        self.content = content
        self.keyframes = keyframes
    }

    public init<Trigger: Equatable>(
        initialValue: Value,
        trigger: Trigger,
        @ViewBuilder content: @escaping (Value) -> [AnyView],
        keyframes: @escaping (KeyframeTrack<Value>) -> Keyframes
    ) {
        self.initialValue = initialValue
        self.triggerDescription = "\(Trigger.self):\(String(describing: trigger))"
        self.content = content
        self.keyframes = keyframes
    }

    public var body: Never {
        fatalError("KeyframeAnimator has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = keyframes(KeyframeTrack<Value>())
        let views = content(initialValue)
        return Component { runtime in
            let node = ViewNode(
                layoutMode: .absolute,
                children: views.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
            return node
        }
    }
}
@MainActor
public struct PhaseAnimator<Phase: Equatable>: View {
    public typealias Body = Never

    let phases: [Phase]
    let triggerDescription: String?
    let content: (Phase) -> [AnyView]
    let animation: (Phase) -> Animation?
    let fallbackContent: [AnyView]?

    public init<Phases: Sequence>(
        _ phases: Phases,
        @ViewBuilder content: @escaping (Phase) -> [AnyView],
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) where Phases.Element == Phase {
        self.phases = Array(phases)
        self.triggerDescription = nil
        self.content = content
        self.animation = animation
        self.fallbackContent = nil
    }

    public init<Phases: Sequence, Trigger: Equatable>(
        _ phases: Phases,
        trigger: Trigger,
        @ViewBuilder content: @escaping (Phase) -> [AnyView],
        animation: @escaping (Phase) -> Animation? = { _ in .default }
    ) where Phases.Element == Phase {
        self.phases = Array(phases)
        self.triggerDescription = "\(Trigger.self):\(String(describing: trigger))"
        self.content = content
        self.animation = animation
        self.fallbackContent = nil
    }

    init<Phases: Sequence>(
        _ phases: Phases,
        content: @escaping (Phase) -> [AnyView],
        animation: @escaping (Phase) -> Animation?,
        fallbackContent: [AnyView]?
    ) where Phases.Element == Phase {
        self.phases = Array(phases)
        self.triggerDescription = nil
        self.content = content
        self.animation = animation
        self.fallbackContent = fallbackContent
    }

    init<Phases: Sequence, Trigger: Equatable>(
        _ phases: Phases,
        trigger: Trigger,
        content: @escaping (Phase) -> [AnyView],
        animation: @escaping (Phase) -> Animation?,
        fallbackContent: [AnyView]?
    ) where Phases.Element == Phase {
        self.phases = Array(phases)
        self.triggerDescription = "\(Trigger.self):\(String(describing: trigger))"
        self.content = content
        self.animation = animation
        self.fallbackContent = fallbackContent
    }

    public var body: Never {
        fatalError("PhaseAnimator has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let invalidate = context.invalidate
        let signature = phases.map { "\($0)" }.joined(separator: "\n")
        let phases = self.phases
        let animation = self.animation
        let content = self.content
        let fallbackContent = self.fallbackContent
        let triggerDescription = self.triggerDescription

        return Component { runtime in
            let now = Win32Window.currentTimestampSeconds()

            // Search the old runtime tree for an existing PhaseAnimator state.
            let oldState = Self.findState(in: runtime.root, signature: signature)

            var phaseIndex = 0
            var phaseStartTime = now
            var triggerChanged = false

            if let oldState = oldState {
                if triggerDescription != oldState.previousTrigger {
                    phaseIndex = 0
                    phaseStartTime = now
                    triggerChanged = true
                } else if oldState.currentPhaseIndex < phases.count - 1 {
                    let duration = animation(phases[oldState.currentPhaseIndex])?.duration ?? 0.35
                    if now - oldState.phaseStartTime >= duration {
                        phaseIndex = oldState.currentPhaseIndex + 1
                        phaseStartTime = now
                    } else {
                        phaseIndex = oldState.currentPhaseIndex
                        phaseStartTime = oldState.phaseStartTime
                    }
                } else {
                    phaseIndex = oldState.currentPhaseIndex
                    phaseStartTime = oldState.phaseStartTime
                }
            }

            let views: [AnyView]
            if let phase = phases.isEmpty ? nil : phases[phaseIndex] {
                let currentAnimation = animation(phase)
                views = content(phase).map { AnyView($0.animation(currentAnimation)) }
            } else if let fallback = fallbackContent {
                views = fallback
            } else {
                views = []
            }

            let childNodes = views.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            let node: ViewNode
            if childNodes.count == 1 {
                node = childNodes[0]
            } else if childNodes.isEmpty {
                node = ViewNode(layoutMode: .absolute)
            } else {
                node = ViewNode(layoutMode: .absolute, children: childNodes)
            }

            let newState = PhaseAnimatorState(
                phasesSignature: signature,
                triggerDescription: triggerDescription,
                currentPhaseIndex: phaseIndex,
                previousTrigger: triggerDescription,
                phaseStartTime: phaseStartTime
            )
            node.phaseAnimatorState = newState

            let phaseString = phases.isEmpty ? "nil" : "\(phases[phaseIndex])"
            let hasAdditionalPhases = !phases.isEmpty && phases.count > 1
            let animationDesc: String
            if let anim = phases.isEmpty ? nil : animation(phases[phaseIndex]) {
                let easingName: String
                switch anim.easing {
                case .linear: easingName = "linear"
                case .easeIn: easingName = "easeIn"
                case .easeOut: easingName = "easeOut"
                case .easeInOut: easingName = "easeInOut"
                default: easingName = "custom"
                }
                animationDesc = "\(easingName):\(anim.duration)"
            } else {
                animationDesc = "nil"
            }
            var effectParts = [
                "phase:\(phaseString)", "hasAdditionalPhases:\(hasAdditionalPhases)", "animation:\(animationDesc)",
            ]
            if let trigger = triggerDescription {
                effectParts.insert("trigger:\(trigger)", at: 2)
            }
            node.visualEffects.append("phaseAnimator(\(effectParts.joined(separator: ",")))")

            let taskKey = "phaseAnimator:\(signature)"
            let shouldStartTask: Bool
            if phases.count > 1 && phaseIndex < phases.count - 1 {
                if oldState == nil || triggerChanged {
                    shouldStartTask = true
                } else if phaseIndex == oldState?.currentPhaseIndex {
                    shouldStartTask = !PhaseAnimatorTaskManager.shared.hasActiveTask(key: taskKey)
                } else {
                    shouldStartTask = true
                }
            } else {
                shouldStartTask = false
            }

            if shouldStartTask {
                PhaseAnimatorTaskManager.shared.start(
                    key: taskKey,
                    runtime: runtime,
                    signature: signature,
                    phases: phases,
                    animation: animation,
                    invalidate: invalidate
                )
            }

            return node
        }
    }

    private static func findState(in root: ViewNode, signature: String) -> PhaseAnimatorState? {
        if let state = root.phaseAnimatorState, state.phasesSignature == signature {
            return state
        }
        for child in root.children {
            if let found = findState(in: child, signature: signature) {
                return found
            }
        }
        return nil
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct TransitionProxy: Sendable, Equatable {
    public var isActive: Bool
    public var value: Double

    public init(isActive: Bool = false, value: Double = 0) {
        self.isActive = isActive
        self.value = value
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct TransitionReader: View {
    public typealias Body = Never

    private let content: (TransitionProxy) -> [AnyView]

    public init(@ViewBuilder content: @escaping (TransitionProxy) -> [AnyView]) {
        self.content = content
    }

    public var body: Never {
        fatalError("TransitionReader has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: content(TransitionProxy(isActive: false, value: 0)),
            context: context,
            fallbackLayout: .absolute
        )
    }
}
@MainActor
public struct ViewThatFits: View {
    public typealias Body = Never

    private let axes: Axis.Set
    private let content: [AnyView]

    public init(in axes: Axis.Set = .all, @ViewBuilder content: () -> [AnyView]) {
        self.axes = axes
        self.content = content()
    }

    public var body: Never {
        fatalError("ViewThatFits has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let axes = axes
        let components = content.map { $0.makeComponent(context: context) }

        return Component { runtime in
            guard !components.isEmpty else {
                return Controls.panel(preferredSize: .zero, isHitTestVisible: false)
            }

            let availableSize = context.canvasSize
            var fallbackNode: ViewNode?
            for component in components {
                let candidateNode = component.makeNode(runtime: runtime)
                fallbackNode = candidateNode
                let candidateSize = candidateNode.intrinsicContentSize()
                if Self.fits(candidateSize, in: availableSize, axes: axes) {
                    return candidateNode
                }
            }

            return fallbackNode ?? Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }

    private static func fits(_ candidateSize: Size, in availableSize: Size, axes: Axis.Set) -> Bool {
        if axes.contains(.horizontal), candidateSize.width > availableSize.width {
            return false
        }
        if axes.contains(.vertical), candidateSize.height > availableSize.height {
            return false
        }
        return true
    }
}
@MainActor
public struct TimelineView<Schedule: TimelineSchedule, Content: View>: View {
    public typealias Body = Never

    private let schedule: Schedule
    private let content: (TimelineViewContext) -> Content

    public init(
        _ schedule: Schedule,
        @ViewBuilder content: @escaping (TimelineViewContext) -> Content
    ) {
        self.schedule = schedule
        self.content = content
    }

    public var body: Never {
        fatalError("TimelineView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let schedule = schedule
        let content = content
        let entries = Array(schedule.entries(from: Date(), mode: .normal))
        let currentDate = entries.first ?? Date()
        let cadence: TimelineViewCadence = {
            if schedule is EverySecondTimelineSchedule { return .live }
            if schedule is EveryMinuteTimelineSchedule { return .seconds }
            if schedule is EveryHourTimelineSchedule { return .minutes }
            return .live
        }()
        let timelineContext = TimelineViewContext(date: currentDate, cadence: cadence)
        let childComponent = content(timelineContext).makeComponent(context: context)
        let invalidate = context.invalidate
        return Component { runtime in
            let childNode = childComponent.makeNode(runtime: runtime)
            if let nextDate = entries.dropFirst().first {
                let sleepInterval = nextDate.timeIntervalSince(Date())
                if sleepInterval > 0 {
                    childNode.pendingLifecycleTaskLaunches.append(
                        ViewLifecycleTaskLaunch(
                            key: "timeline-view-update",
                            priority: .background,
                            action: {
                                try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
                                await MainActor.run { invalidate() }
                            }
                        )
                    )
                }
            }
            return childNode
        }
    }
}
public struct AnimationTimelineView<Schedule: TimelineSchedule, Content: View>: View {
    public typealias Body = Never

    private let schedule: Schedule
    private let content: (TimelineViewContext) -> Content

    public init(
        _ schedule: Schedule,
        @ViewBuilder content: @escaping (TimelineViewContext) -> Content
    ) {
        self.schedule = schedule
        self.content = content
    }

    public var body: Never {
        fatalError("AnimationTimelineView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let schedule = schedule
        let content = content
        let entries = Array(schedule.entries(from: Date(), mode: .normal))
        let currentDate = entries.first ?? Date()
        let timelineContext = TimelineViewContext(date: currentDate, cadence: .live)
        let childComponent = content(timelineContext).makeComponent(context: context)
        let invalidate = context.invalidate
        return Component { runtime in
            let childNode = childComponent.makeNode(runtime: runtime)
            if let nextDate = entries.dropFirst().first {
                let sleepInterval = nextDate.timeIntervalSince(Date())
                if sleepInterval > 0 {
                    childNode.pendingLifecycleTaskLaunches.append(
                        ViewLifecycleTaskLaunch(
                            key: "animation-timeline-view-update",
                            priority: .background,
                            action: {
                                try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
                                await MainActor.run { invalidate() }
                            }
                        )
                    )
                }
            }
            return childNode
        }
    }
}
extension SwiftWindowsCore.Color: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Color has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(backgroundColor: self, isHitTestVisible: false)
        }
    }
}
public enum RoundedCornerStyle: Sendable, Equatable {
    case circular
    case continuous
}
@MainActor
public struct Rectangle: View {
    public typealias Body = Never

    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Rectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle,
            cornerRadius: 0
        )
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addRect(rect)
        return path
    }

    public func fill(_ color: Color) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Rectangle {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> Rectangle {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> Rectangle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> Rectangle {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> Rectangle {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> Rectangle {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> Rectangle {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> Rectangle {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Rectangle {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Rectangle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> Rectangle {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> Rectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Rectangle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Rectangle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Rectangle {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Rectangle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Rectangle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Rectangle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Rectangle {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Rectangle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> Rectangle {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> Rectangle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Rectangle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Rectangle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Rectangle {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Rectangle {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct RoundedRectangle: View {
    public typealias Body = Never

    public let cornerSize: CGSize
    public let style: RoundedCornerStyle
    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(cornerRadius: Double, style: RoundedCornerStyle = .circular) {
        let radius = max(0, cornerRadius)
        self.init(cornerSize: CGSize(width: radius, height: radius), style: style)
    }

    public init(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) {
        self.cornerSize = CGSize(width: max(0, cornerSize.width), height: max(0, cornerSize.height))
        self.style = style
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("RoundedRectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle,
            cornerRadius: retainedUniformFallbackRadius
        )
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addRoundedRect(rect, cornerRadius: retainedUniformFallbackRadius)
        return path
    }

    public func fill(_ color: Color) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> RoundedRectangle {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> RoundedRectangle {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> RoundedRectangle {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> RoundedRectangle {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> RoundedRectangle {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> RoundedRectangle {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> RoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> RoundedRectangle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> RoundedRectangle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> RoundedRectangle {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> RoundedRectangle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> RoundedRectangle {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> RoundedRectangle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> RoundedRectangle {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> RoundedRectangle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> RoundedRectangle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> RoundedRectangle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> RoundedRectangle {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> RoundedRectangle {
        stroke(gradient, style: style)
    }

    var retainedUniformFallbackRadius: CGFloat {
        max(cornerSize.width, cornerSize.height)
    }
}
public struct RectangleCornerRadii: Sendable, Equatable {
    public var topLeading: CGFloat
    public var bottomLeading: CGFloat
    public var bottomTrailing: CGFloat
    public var topTrailing: CGFloat

    public init(
        topLeading: CGFloat = 0,
        bottomLeading: CGFloat = 0,
        bottomTrailing: CGFloat = 0,
        topTrailing: CGFloat = 0
    ) {
        self.topLeading = max(0, topLeading)
        self.bottomLeading = max(0, bottomLeading)
        self.bottomTrailing = max(0, bottomTrailing)
        self.topTrailing = max(0, topTrailing)
    }

    var retainedUniformFallbackRadius: CGFloat {
        max(topLeading, bottomLeading, bottomTrailing, topTrailing)
    }
}
@MainActor
public struct UnevenRoundedRectangle: View {
    public typealias Body = Never

    public let cornerRadii: RectangleCornerRadii
    public let style: RoundedCornerStyle

    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(
        cornerRadii: RectangleCornerRadii,
        style: RoundedCornerStyle = .continuous
    ) {
        self.cornerRadii = cornerRadii
        self.style = style
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public init(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0,
        style: RoundedCornerStyle = .continuous
    ) {
        self.init(
            cornerRadii: RectangleCornerRadii(
                topLeading: topLeadingRadius,
                bottomLeading: bottomLeadingRadius,
                bottomTrailing: bottomTrailingRadius,
                topTrailing: topTrailingRadius
            ),
            style: style
        )
    }

    public var body: Never {
        fatalError("UnevenRoundedRectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shapeComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle,
            cornerRadius: cornerRadii.retainedUniformFallbackRadius
        )
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addRoundedRect(rect, cornerRadius: cornerRadii.retainedUniformFallbackRadius)
        return path
    }

    public func fill(_ color: Color) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> UnevenRoundedRectangle {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> UnevenRoundedRectangle {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> UnevenRoundedRectangle {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> UnevenRoundedRectangle {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> UnevenRoundedRectangle {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> UnevenRoundedRectangle {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> UnevenRoundedRectangle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> UnevenRoundedRectangle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> UnevenRoundedRectangle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> UnevenRoundedRectangle {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> UnevenRoundedRectangle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> UnevenRoundedRectangle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> UnevenRoundedRectangle {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> UnevenRoundedRectangle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> UnevenRoundedRectangle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> UnevenRoundedRectangle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> UnevenRoundedRectangle {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> UnevenRoundedRectangle {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct Capsule: View {
    public typealias Body = Never

    private let style: RoundedCornerStyle
    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(style: RoundedCornerStyle = .circular) {
        self.style = style
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Capsule has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func path(in rect: Rect) -> Path {
        let radius = min(rect.size.width, rect.size.height) / 2
        var path = Path()
        path.addRoundedRect(rect, cornerRadius: radius)
        return path
    }

    public func fill(_ color: Color) -> Capsule {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Capsule {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> Capsule {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> Capsule {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> Capsule {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> Capsule {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> Capsule {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> Capsule {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> Capsule {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Capsule {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Capsule {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Capsule {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Capsule {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> Capsule {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> Capsule {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Capsule {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Capsule {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Capsule {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Capsule {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Capsule {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Capsule {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Capsule {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Capsule {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> Capsule {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> Capsule {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Capsule {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Capsule {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Capsule {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Capsule {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct Circle: View {
    public typealias Body = Never

    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Circle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }

    public func fill(_ color: Color) -> Circle {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Circle {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> Circle {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> Circle {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> Circle {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> Circle {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> Circle {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> Circle {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> Circle {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Circle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Circle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Circle {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Circle {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> Circle {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> Circle {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Circle {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Circle {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Circle {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Circle {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Circle {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Circle {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Circle {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Circle {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> Circle {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> Circle {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Circle {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Circle {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Circle {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Circle {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct Ellipse: View {
    public typealias Body = Never

    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Ellipse has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }

    public func fill(_ color: Color) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Ellipse {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> Ellipse {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> Ellipse {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> Ellipse {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> Ellipse {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> Ellipse {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> Ellipse {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> Ellipse {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Ellipse {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Ellipse {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> Ellipse {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> Ellipse {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Ellipse {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Ellipse {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Ellipse {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Ellipse {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Ellipse {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Ellipse {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Ellipse {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Ellipse {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> Ellipse {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> Ellipse {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Ellipse {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Ellipse {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Ellipse {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Ellipse {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct Arc: View {
    public typealias Body = Never

    public var startAngle: Angle
    public var endAngle: Angle
    public var clockwise: Bool

    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(startAngle: Angle, endAngle: Angle, clockwise: Bool) {
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.clockwise = clockwise
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("Arc has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let fill = fillStyle ?? context.foregroundStyle
        let stroke = lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : ForegroundStyle.color(.clear)
        let lineWidth = lineWidth
        let strokeLineStyle = strokeLineStyle
        let fillRuleStyle = fillRuleStyle
        let startAngle = startAngle
        let endAngle = endAngle
        let clockwise = clockwise
        return Component { _ in
            let node = Controls.panel(
                backgroundColor: .clear,
                borderColor: .clear,
                borderWidth: 0,
                isHitTestVisible: false
            )
            node.onLayout = { [weak node] bounds in
                guard let node else { return }
                var path = Path()
                let center = Point(x: bounds.midX, y: bounds.midY)
                let radius = max(0, min(bounds.size.width, bounds.size.height) * 0.5)
                path.moveTo(
                    Point(
                        x: center.x + radius * cos(startAngle.radians), y: center.y + radius * sin(startAngle.radians)))
                path.arc(
                    center: center, radius: radius, startAngle: startAngle.radians, endAngle: endAngle.radians,
                    clockwise: clockwise)
                node.backgroundPath = RenderPath(path: path)
                let fillResolved = resolvedFill(from: fill)
                node.backgroundColor = fillResolved.color
                node.backgroundGradient = fillResolved.gradient
                let strokeResolved = resolvedFill(from: stroke)
                node.borderColor = strokeResolved.color
                node.borderGradient = strokeResolved.gradient
                node.borderWidth = lineWidth
                node.borderStrokeStyle =
                    lineWidth > 0 ? (strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: [])) : nil
                node.clipFillStyle = fillRuleStyle
            }
            return node
        }
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        let center = Point(x: rect.midX, y: rect.midY)
        let radius = max(0, min(rect.size.width, rect.size.height) * 0.5)
        path.moveTo(
            Point(x: center.x + radius * cos(startAngle.radians), y: center.y + radius * sin(startAngle.radians)))
        path.arc(
            center: center, radius: radius, startAngle: startAngle.radians, endAngle: endAngle.radians,
            clockwise: clockwise)
        return path
    }

    public func fill(_ color: Color) -> Arc {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> Arc {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> Arc {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> Arc {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> Arc {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> Arc {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> Arc {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> Arc {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> Arc {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> Arc {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> Arc {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Arc {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> Arc {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> Arc {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> Arc {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> Arc {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Arc {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Arc {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> Arc {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> Arc {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> Arc {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> Arc {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> Arc {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> Arc {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> Arc {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> Arc {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> Arc {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> Arc {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> Arc {
        stroke(gradient, style: style)
    }
}
extension Arc: Shape {}
extension Arc: InsettableShape {}
@MainActor
public struct ContainerRelativeShape: View {
    public typealias Body = Never

    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init() {
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("ContainerRelativeShape has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        capsuleComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle
        )
    }

    public func path(in rect: Rect) -> Path {
        var path = Path()
        path.addRoundedRect(rect, cornerRadius: min(rect.size.width, rect.size.height) * 0.1)
        return path
    }

    public func fill(_ color: Color) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> ContainerRelativeShape {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> ContainerRelativeShape {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> ContainerRelativeShape {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> ContainerRelativeShape {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> ContainerRelativeShape {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> ContainerRelativeShape {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> ContainerRelativeShape {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> ContainerRelativeShape {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> ContainerRelativeShape {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> ContainerRelativeShape {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> ContainerRelativeShape {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> ContainerRelativeShape {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> ContainerRelativeShape {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> ContainerRelativeShape {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> ContainerRelativeShape {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> ContainerRelativeShape {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> ContainerRelativeShape {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> ContainerRelativeShape {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> ContainerRelativeShape {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> ContainerRelativeShape {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> ContainerRelativeShape {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> ContainerRelativeShape {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> ContainerRelativeShape {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct AnyShape: Shape, RetainedClipShape, RetainedContentShapeProvider {
    public typealias Body = Never

    private let buildComponent: (ViewBuildContext) -> Component
    private let buildPath: (Rect) -> Path
    private let clipShapeStyle: RetainedClipShapeStyle
    private let contentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle
    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init<S: Shape>(_ shape: S) {
        self.buildComponent = { context in
            ViewBuildContextScope.withCurrent(context) {
                shape.makeComponent(context: context)
            }
        }
        self.buildPath = { rect in shape.path(in: rect) }
        self.clipShapeStyle = (shape as? any RetainedClipShape)?.retainedClipShapeStyle ?? .rectangle
        self.contentShapeStyle = resolvedRetainedContentShapeStyle(for: shape)
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public func path(in rect: Rect) -> Path {
        buildPath(rect)
    }

    public var body: Never {
        fatalError("AnyShape has no body")
    }

    var retainedClipShapeStyle: RetainedClipShapeStyle {
        clipShapeStyle
    }

    var retainedContentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle {
        contentShapeStyle
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        guard fillStyle != nil || fillRuleStyle != nil || strokeStyle != nil || strokeLineStyle != nil || lineWidth > 0
        else {
            return buildComponent(context)
        }

        let fill = fillStyle ?? context.foregroundStyle
        let stroke = lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear)
        let fillResult = resolvedFill(from: fill)
        let strokeResult = resolvedFill(from: stroke)
        let inner = buildComponent(context)
        return Component(key: inner.key) { runtime in
            let node = inner.makeNode(runtime: runtime)
            node.backgroundColor = fillResult.color
            node.backgroundGradient = fillResult.gradient
            node.borderColor = strokeResult.color
            node.borderGradient = strokeResult.gradient
            node.borderWidth = lineWidth
            node.clipFillStyle = fillRuleStyle
            node.borderStrokeStyle =
                lineWidth > 0 ? (strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: [])) : nil
            return node
        }
    }

    public func fill(_ color: Color) -> AnyShape {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> AnyShape {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> AnyShape {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> AnyShape {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> AnyShape {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> AnyShape {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> AnyShape {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> AnyShape {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> AnyShape {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> AnyShape {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> AnyShape {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> AnyShape {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> AnyShape {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> AnyShape {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> AnyShape {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> AnyShape {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> AnyShape {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> AnyShape {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> AnyShape {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> AnyShape {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> AnyShape {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> AnyShape {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> AnyShape {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> AnyShape {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> AnyShape {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> AnyShape {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> AnyShape {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> AnyShape {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> AnyShape {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct InsetShape<Content: Shape>: InsettableShape, RetainedClipShape, RetainedContentShapeProvider {
    public typealias Body = Never

    private let content: Content
    private let buildComponent: (ViewBuildContext) -> Component
    private let amount: Double
    private let clipShapeStyle: RetainedClipShapeStyle
    private let contentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle
    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(_ content: Content, amount: CGFloat) {
        self.content = content
        self.buildComponent = { context in
            ViewBuildContextScope.withCurrent(context) {
                content.makeComponent(context: context)
            }
        }
        self.amount = amount
        self.clipShapeStyle = (content as? any RetainedClipShape)?.retainedClipShapeStyle ?? .rectangle
        self.contentShapeStyle = resolvedRetainedContentShapeStyle(for: content)
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("InsetShape has no body")
    }

    var retainedClipShapeStyle: RetainedClipShapeStyle {
        adjustedClipShapeStyle
    }

    var retainedContentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle {
        adjustedContentShapeStyle
    }

    private var adjustedClipShapeStyle: RetainedClipShapeStyle {
        switch clipShapeStyle {
        case .roundedRectangle(let radius):
            return .roundedRectangle(max(0, radius - amount))
        case .rectangle, .capsule:
            return clipShapeStyle
        }
    }

    private var adjustedContentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle {
        switch contentShapeStyle {
        case .roundedRectangle(let radius):
            return .roundedRectangle(max(0, radius - amount))
        case .rectangle, .capsule, .ellipse:
            return contentShapeStyle
        }
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let renderedComponent: Component
        if fillStyle == nil && fillRuleStyle == nil && strokeStyle == nil && strokeLineStyle == nil && lineWidth <= 0 {
            renderedComponent = buildComponent(context)
        } else {
            let fill = fillStyle ?? context.foregroundStyle
            let stroke = lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear)
            let fillResult = resolvedFill(from: fill)
            let strokeResult = resolvedFill(from: stroke)
            let inner = buildComponent(context)
            renderedComponent = Component(key: inner.key) { runtime in
                let node = inner.makeNode(runtime: runtime)
                node.backgroundColor = fillResult.color
                node.backgroundGradient = fillResult.gradient
                node.borderColor = strokeResult.color
                node.borderGradient = strokeResult.gradient
                node.borderWidth = lineWidth
                node.clipFillStyle = fillRuleStyle
                node.borderStrokeStyle =
                    lineWidth > 0 ? (strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: [])) : nil
                switch adjustedClipShapeStyle {
                case .roundedRectangle(let radius):
                    node.cornerRadius = radius
                case .rectangle, .capsule:
                    break
                }
                return node
            }
        }

        guard amount != 0 else {
            return renderedComponent
        }

        return Component { runtime in
            let childNode = renderedComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .vertical(padding: EdgeInsets.all(amount), alignment: .stretch),
                isHitTestVisible: false,
                children: [childNode]
            )
        }
    }

    public func path(in rect: Rect) -> Path {
        let insetRect = Rect(
            origin: Point(x: rect.minX + amount, y: rect.minY + amount),
            size: Size(width: rect.size.width - amount * 2, height: rect.size.height - amount * 2)
        )
        return content.path(in: insetRect)
    }

    public func inset(by amount: CGFloat) -> InsetShape<Content> {
        InsetShape(content, amount: self.amount + amount)
    }

    public func fill(_ color: Color) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> InsetShape<Content> {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> InsetShape<Content> {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> InsetShape<Content> {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> InsetShape<Content> {
        var copy = fill(foregroundStyle.retainedForegroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> InsetShape<Content> {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> InsetShape<Content> {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> InsetShape<Content> {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> InsetShape<Content> {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> InsetShape<Content> {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> InsetShape<Content> {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> InsetShape<Content> {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> InsetShape<Content> {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> InsetShape<Content> {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> InsetShape<Content> {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> InsetShape<Content> {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> InsetShape<Content> {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> InsetShape<Content> {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> InsetShape<Content> {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> InsetShape<Content> {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> InsetShape<Content> {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> InsetShape<Content> {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> InsetShape<Content> {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> InsetShape<Content> {
        stroke(gradient, style: style)
    }
}
@MainActor
public struct TrimmedShape<Content: Shape>: Shape, RetainedClipShape, RetainedContentShapeProvider {
    public typealias Body = Never

    private let content: Content
    private let startFraction: CGFloat
    private let endFraction: CGFloat
    private let clipShapeStyle: RetainedClipShapeStyle
    private let contentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle
    private var fillStyle: ForegroundStyle?
    private var fillRuleStyle: RetainedClipFillStyle?
    private var strokeStyle: ForegroundStyle?
    private var lineWidth: Double
    private var strokeLineStyle: StrokeStyle?

    public init(content: Content, startFraction: CGFloat = 0, endFraction: CGFloat = 1) {
        self.content = content
        self.startFraction = startFraction
        self.endFraction = endFraction
        self.clipShapeStyle = (content as? any RetainedClipShape)?.retainedClipShapeStyle ?? .rectangle
        self.contentShapeStyle = resolvedRetainedContentShapeStyle(for: content)
        self.fillStyle = nil
        self.fillRuleStyle = nil
        self.strokeStyle = nil
        self.lineWidth = 0
        self.strokeLineStyle = nil
    }

    public var body: Never {
        fatalError("TrimmedShape has no body")
    }

    var retainedClipShapeStyle: RetainedClipShapeStyle {
        clipShapeStyle
    }

    var retainedContentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle {
        contentShapeStyle
    }

    public func path(in rect: Rect) -> Path {
        content.path(in: rect)
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let fill = context.foregroundStyle
        let fillColor: Color
        switch fill {
        case .color(let c): fillColor = c
        case .linearGradient(let g): fillColor = g.startColor
        case .radialGradient(let g): fillColor = g.stops.first?.color ?? .clear
        case .conicGradient(let g): fillColor = g.stops.first?.color ?? .clear
        case .materialFill(let tint, _): fillColor = tint
        }
        let unitPath = self.path(in: Rect(x: 0, y: 0, width: 1, height: 1))
        return Component { _ in
            let node = Controls.panel(
                backgroundColor: fillColor,
                isHitTestVisible: false
            )
            var segments: [RenderPath.Segment] = []
            for element in unitPath.elements {
                switch element {
                case .moveTo(let p): segments.append(.moveTo(p))
                case .lineTo(let p): segments.append(.lineTo(p))
                case .quadraticCurveTo(let c, let e): segments.append(.quadCurveTo(control: c, end: e))
                case .cubicCurveTo(let c1, let c2, let e):
                    segments.append(.cubicCurveTo(control1: c1, control2: c2, end: e))
                case .arc(let center, let radius, let startAngle, let endAngle, _):
                    let steps = max(4, Int(ceil(abs(endAngle - startAngle) * radius * 0.5)))
                    let step = (endAngle - startAngle) / Double(steps)
                    for i in 1...steps {
                        let a = startAngle + step * Double(i)
                        let p = Point(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
                        segments.append(.lineTo(p))
                    }
                case .close: segments.append(.close)
                }
            }
            node.backgroundPath = RenderPath(segments: segments)
            return node
        }
    }

    public func fill(_ color: Color) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = .color(color)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(_ style: ForegroundStyle) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = style
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill<S: ShapeStyle>(_ style: S) -> TrimmedShape<Content> {
        fill(style.retainedForegroundStyle)
    }

    public func fill(_ gradient: LinearGradient) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = .linearGradient(gradient)
        copy.fillRuleStyle = nil
        return copy
    }

    public func fill(style: FillStyle) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = nil
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ color: Color, style: FillStyle) -> TrimmedShape<Content> {
        var copy = fill(color)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill(_ foregroundStyle: ForegroundStyle, style: FillStyle) -> TrimmedShape<Content> {
        var copy = fill(foregroundStyle)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func fill<S: ShapeStyle>(_ foregroundStyle: S, style: FillStyle) -> TrimmedShape<Content> {
        fill(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func fill(_ gradient: LinearGradient, style: FillStyle) -> TrimmedShape<Content> {
        var copy = fill(gradient)
        copy.fillRuleStyle = style.retainedClipFillStyle
        return copy
    }

    public func stroke(_ color: Color, lineWidth: Double = 1) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = .color(color)
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke(_ style: ForegroundStyle, lineWidth: Double = 1) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = style
        copy.lineWidth = max(0, lineWidth)
        copy.strokeLineStyle = StrokeStyle(lineWidth: copy.lineWidth, dashPattern: [])
        return copy
    }

    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> TrimmedShape<Content> {
        stroke(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func stroke(_ gradient: LinearGradient, lineWidth: Double = 1) -> TrimmedShape<Content> {
        stroke(.linearGradient(gradient), lineWidth: lineWidth)
    }

    public func stroke(lineWidth: Double = 1) -> TrimmedShape<Content> {
        stroke(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(style: StrokeStyle) -> TrimmedShape<Content> {
        var copy = self
        copy.fillStyle = .color(.clear)
        copy.fillRuleStyle = nil
        copy.strokeStyle = nil
        copy.lineWidth = max(0, style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ color: Color, style: StrokeStyle) -> TrimmedShape<Content> {
        var copy = stroke(color, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> TrimmedShape<Content> {
        var copy = stroke(foregroundStyle, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func stroke<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> TrimmedShape<Content> {
        stroke(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func stroke(_ gradient: LinearGradient, style: StrokeStyle) -> TrimmedShape<Content> {
        var copy = stroke(gradient, lineWidth: style.lineWidth)
        copy.strokeLineStyle = style.retainedShapeStrokeStyle
        return copy
    }

    public func strokeBorder(_ color: Color, lineWidth: Double = 1) -> TrimmedShape<Content> {
        stroke(color, lineWidth: lineWidth)
    }

    public func strokeBorder(_ style: ForegroundStyle, lineWidth: Double = 1) -> TrimmedShape<Content> {
        stroke(style, lineWidth: lineWidth)
    }

    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Double = 1) -> TrimmedShape<Content> {
        strokeBorder(style.retainedForegroundStyle, lineWidth: lineWidth)
    }

    public func strokeBorder(_ gradient: LinearGradient, lineWidth: Double = 1) -> TrimmedShape<Content> {
        stroke(gradient, lineWidth: lineWidth)
    }

    public func strokeBorder(lineWidth: Double = 1) -> TrimmedShape<Content> {
        strokeBorder(style: StrokeStyle(lineWidth: lineWidth))
    }

    public func strokeBorder(style: StrokeStyle) -> TrimmedShape<Content> {
        stroke(style: style)
    }

    public func strokeBorder(_ color: Color, style: StrokeStyle) -> TrimmedShape<Content> {
        stroke(color, style: style)
    }

    public func strokeBorder(_ foregroundStyle: ForegroundStyle, style: StrokeStyle) -> TrimmedShape<Content> {
        stroke(foregroundStyle, style: style)
    }

    public func strokeBorder<S: ShapeStyle>(_ foregroundStyle: S, style: StrokeStyle) -> TrimmedShape<Content> {
        strokeBorder(foregroundStyle.retainedForegroundStyle, style: style)
    }

    public func strokeBorder(_ gradient: LinearGradient, style: StrokeStyle) -> TrimmedShape<Content> {
        stroke(gradient, style: style)
    }
}
extension TrimmedShape where Content: InsettableShape {
    public func inset(by amount: CGFloat) -> TrimmedShape<Content> {
        return self
    }
}
@MainActor
public struct RotatedShape<Content: Shape>: Shape {
    public typealias Body = Never

    private let shape: Content
    private let angle: Angle
    private let anchor: UnitPoint

    public init(shape: Content, angle: Angle, anchor: UnitPoint = .center) {
        self.shape = shape
        self.angle = angle
        self.anchor = anchor
    }

    public var body: Never {
        fatalError("RotatedShape has no body")
    }

    public func path(in rect: Rect) -> Path {
        shape.path(in: rect)
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let child = shape.makeComponent(context: context)
        return Component { runtime in
            let childNode = child.makeNode(runtime: runtime)
            childNode.transform = childNode.transform.concatenating(Transform2D(rotation: angle.radians))
            return childNode
        }
    }
}
@MainActor
public struct ScaledShape<Content: Shape>: Shape {
    public typealias Body = Never

    private let shape: Content
    private let scale: CGSize
    private let anchor: UnitPoint

    public init(shape: Content, scale: CGSize, anchor: UnitPoint = .center) {
        self.shape = shape
        self.scale = scale
        self.anchor = anchor
    }

    public var body: Never {
        fatalError("ScaledShape has no body")
    }

    public func path(in rect: Rect) -> Path {
        shape.path(in: rect)
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let child = shape.makeComponent(context: context)
        return Component { runtime in
            let childNode = child.makeNode(runtime: runtime)
            childNode.transform = childNode.transform.concatenating(.scale(x: scale.width, y: scale.height))
            return childNode
        }
    }
}
@MainActor
public struct OffsetShape<Content: Shape>: Shape {
    public typealias Body = Never

    private let shape: Content
    private let offset: CGSize

    public init(shape: Content, offset: CGSize) {
        self.shape = shape
        self.offset = offset
    }

    public var body: Never {
        fatalError("OffsetShape has no body")
    }

    public func path(in rect: Rect) -> Path {
        shape.path(in: rect)
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let child = shape.makeComponent(context: context)
        return Component { runtime in
            let childNode = child.makeNode(runtime: runtime)
            childNode.transform = childNode.transform.concatenating(.translation(x: offset.width, y: offset.height))
            return childNode
        }
    }
}
@MainActor
public struct TransformedShape<Content: Shape>: Shape {
    public typealias Body = Never

    private let shape: Content
    private let transform: Transform2D

    public init(shape: Content, transform: Transform2D) {
        self.shape = shape
        self.transform = transform
    }

    public var body: Never {
        fatalError("TransformedShape has no body")
    }

    public func path(in rect: Rect) -> Path {
        shape.path(in: rect)
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let child = shape.makeComponent(context: context)
        return Component { runtime in
            let childNode = child.makeNode(runtime: runtime)
            childNode.transform = childNode.transform.concatenating(transform)
            return childNode
        }
    }
}
public struct StrokeBorder<Content: Shape>: View {
    public typealias Body = Never

    private let shape: Content
    private let style: StrokeStyle

    public init(shape: Content, style: StrokeStyle) {
        self.shape = shape
        self.style = style
    }

    public var body: Never {
        fatalError("StrokeBorder has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        shape.makeComponent(context: context)
    }
}
public struct UnionShape<Content: Shape, Other: Shape>: Shape {
    public typealias Body = Never

    private let first: Content
    private let second: Other

    public init(first: Content, second: Other) {
        self.first = first
        self.second = second
    }

    public var body: Never {
        fatalError("UnionShape has no body")
    }

    public func path(in rect: Rect) -> Path {
        first.path(in: rect)
    }
}
public struct IntersectionShape<Content: Shape, Other: Shape>: Shape {
    public typealias Body = Never

    private let first: Content
    private let second: Other

    public init(first: Content, second: Other) {
        self.first = first
        self.second = second
    }

    public var body: Never {
        fatalError("IntersectionShape has no body")
    }

    public func path(in rect: Rect) -> Path {
        first.path(in: rect)
    }
}
extension Shape where Self == Rectangle {
    public static var rect: Rectangle {
        Rectangle()
    }
}
extension Shape where Self == RoundedRectangle {
    public static func rect(
        cornerRadius: CGFloat,
        style: RoundedCornerStyle = .continuous
    ) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }

    public static func rect(
        cornerSize: CGSize,
        style: RoundedCornerStyle = .continuous
    ) -> RoundedRectangle {
        RoundedRectangle(cornerSize: cornerSize, style: style)
    }
}
extension Shape where Self == UnevenRoundedRectangle {
    public static func rect(
        cornerRadii: RectangleCornerRadii,
        style: RoundedCornerStyle = .continuous
    ) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: style)
    }

    public static func rect(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0,
        style: RoundedCornerStyle = .continuous
    ) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topLeadingRadius,
            bottomLeadingRadius: bottomLeadingRadius,
            bottomTrailingRadius: bottomTrailingRadius,
            topTrailingRadius: topTrailingRadius,
            style: style
        )
    }
}
extension Shape where Self == Capsule {
    public static var capsule: Capsule {
        Capsule()
    }

    public static func capsule(style: RoundedCornerStyle) -> Capsule {
        Capsule(style: style)
    }
}
extension Shape where Self == Circle {
    public static var circle: Circle {
        Circle()
    }
}
extension Shape where Self == Ellipse {
    public static var ellipse: Ellipse {
        Ellipse()
    }
}
extension Shape where Self == ContainerRelativeShape {
    public static var containerRelative: ContainerRelativeShape {
        ContainerRelativeShape()
    }
}
extension Rectangle: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .rectangle
    }
}
extension RoundedRectangle: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .roundedRectangle(retainedUniformFallbackRadius)
    }
}
extension UnevenRoundedRectangle: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .roundedRectangle(cornerRadii.retainedUniformFallbackRadius)
    }
}
extension Capsule: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}
extension Circle: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}
extension Ellipse: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}
extension Path: Shape {
    public func path(in rect: Rect) -> Path {
        self
    }
}
extension ContainerRelativeShape: InsettableShape, RetainedClipShape {
    var retainedClipShapeStyle: RetainedClipShapeStyle {
        .capsule
    }
}
@MainActor
private func shapeComponent(
    fillStyle: ForegroundStyle,
    fillRuleStyle: RetainedClipFillStyle?,
    strokeStyle: ForegroundStyle,
    lineWidth: Double,
    strokeLineStyle: StrokeStyle?,
    cornerRadius: Double
) -> Component {
    Component { _ in
        let fill = resolvedFill(from: fillStyle)
        let stroke = resolvedFill(from: strokeStyle)
        let node = Controls.panel(
            backgroundColor: fill.color,
            backgroundGradient: fill.gradient,
            borderColor: stroke.color,
            borderGradient: stroke.gradient,
            borderWidth: lineWidth,
            cornerRadius: cornerRadius,
            isHitTestVisible: false
        )
        node.clipFillStyle = fillRuleStyle
        node.borderStrokeStyle =
            lineWidth > 0 ? strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: []) : nil
        return node
    }
}
@MainActor
private func capsuleComponent(
    fillStyle: ForegroundStyle,
    fillRuleStyle: RetainedClipFillStyle?,
    strokeStyle: ForegroundStyle,
    lineWidth: Double,
    strokeLineStyle: StrokeStyle?
) -> Component {
    Component { _ in
        let fill = resolvedFill(from: fillStyle)
        let stroke = resolvedFill(from: strokeStyle)
        let node = Controls.panel(
            backgroundColor: fill.color,
            backgroundGradient: fill.gradient,
            borderColor: stroke.color,
            borderGradient: stroke.gradient,
            borderWidth: lineWidth,
            isHitTestVisible: false
        )
        node.clipFillStyle = fillRuleStyle
        node.borderStrokeStyle =
            lineWidth > 0 ? strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: []) : nil
        node.onLayout = { [weak node] bounds in
            let radius = max(0, min(bounds.size.width, bounds.size.height) * 0.5)
            if node?.cornerRadius != radius {
                node?.cornerRadius = radius
            }
        }
        return node
    }
}
extension StrokeStyle {
    fileprivate var retainedShapeStrokeStyle: StrokeStyle {
        var copy = self
        copy.lineWidth = max(0, lineWidth)
        return copy
    }
}
extension FillStyle {
    fileprivate var retainedClipFillStyle: RetainedClipFillStyle {
        RetainedClipFillStyle(eoFill: isEOFilled, antialiased: isAntialiased)
    }
}
private func resolvedFill(from style: ForegroundStyle) -> (color: Color, gradient: GradientType?) {
    switch style {
    case .color(let color):
        return (color, nil)
    case .linearGradient(let gradient):
        return (gradient.startColor, .linear(.init(gradient)))
    case .radialGradient(let gradient):
        return (gradient.stops.first?.color ?? .clear, .radial(.init(gradient)))
    case .conicGradient(let gradient):
        return (gradient.stops.first?.color ?? .clear, .conic(.init(gradient)))
    case .materialFill(let tint, _):
        return (tint, nil)
    }
}
@MainActor
public struct Group: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Group has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: content, context: context)
    }
}
@MainActor
private struct NavigationStackEntry {
    var destination: [AnyView]
    var onDismiss: (@MainActor () -> Void)?
}
@MainActor
private final class NavigationContainerState {
    var destinationStack: [NavigationStackEntry] = []
}
@MainActor
private struct NavigationPathBinding {
    var values: () -> [AnyHashable]
    var append: (AnyHashable) -> Bool
    var removeLast: () -> Void
}
@MainActor
public struct NavigationStack: View {
    public typealias Body = Never

    private let state: NavigationContainerState
    private let pathBinding: NavigationPathBinding?
    private let content: [AnyView]

    public init(@ViewBuilder root: () -> [AnyView]) {
        self.state = NavigationContainerState()
        self.pathBinding = nil
        self.content = root()
    }

    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> [AnyView]) {
        self.state = NavigationContainerState()
        self.pathBinding = NavigationPathBinding(
            values: {
                path.wrappedValue.anyElements
            },
            append: { value in
                var updatedPath = path.wrappedValue
                updatedPath.appendAnyHashable(value)
                path.wrappedValue = updatedPath
                return true
            },
            removeLast: {
                var updatedPath = path.wrappedValue
                updatedPath.removeLast()
                path.wrappedValue = updatedPath
            }
        )
        self.content = root()
    }

    public init<Data>(
        path: Binding<Data>,
        @ViewBuilder root: () -> [AnyView]
    ) where Data: MutableCollection & RandomAccessCollection & RangeReplaceableCollection, Data.Element: Hashable {
        self.state = NavigationContainerState()
        self.pathBinding = NavigationPathBinding(
            values: {
                path.wrappedValue.map { AnyHashable($0) }
            },
            append: { value in
                guard let typedValue = value.base as? Data.Element else {
                    return false
                }

                var updatedPath = path.wrappedValue
                updatedPath.append(typedValue)
                path.wrappedValue = updatedPath
                return true
            },
            removeLast: {
                var updatedPath = path.wrappedValue
                if !updatedPath.isEmpty {
                    updatedPath.removeLast()
                    path.wrappedValue = updatedPath
                }
            }
        )
        self.content = root()
    }

    public var body: Never {
        fatalError("NavigationStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        navigationContainerComponent(
            from: content,
            state: state,
            pathBinding: pathBinding,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}
@MainActor
public struct NavigationView: View {
    public typealias Body = Never

    private let state: NavigationContainerState
    private let pathBinding: NavigationPathBinding?
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.state = NavigationContainerState()
        self.pathBinding = nil
        self.content = content()
    }

    public var body: Never {
        fatalError("NavigationView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        navigationContainerComponent(
            from: content,
            state: state,
            pathBinding: pathBinding,
            context: context,
            navigationViewStyle: context.navigationViewStyle,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}
private struct RetainedNavigationViewChrome {
    var containerBackground: Color?
    var containerBorderColor: Color
    var containerBorderWidth: Double
    var containerCornerRadius: Double
    var headerBackground: Color
    var headerBorderColor: Color
    var headerBorderWidth: Double
    var headerCornerRadius: Double
    var spacing: Double
}
private func retainedNavigationViewChrome(for style: NavigationViewStyle?) -> RetainedNavigationViewChrome {
    let defaultChrome = RetainedNavigationViewChrome(
        containerBackground: nil,
        containerBorderColor: .clear,
        containerBorderWidth: 0,
        containerCornerRadius: 0,
        headerBackground: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.92),
        headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
        headerBorderWidth: 1,
        headerCornerRadius: 10,
        spacing: 10
    )

    guard let style else {
        return defaultChrome
    }

    switch style.kind {
    case .automatic:
        return defaultChrome
    case .stack:
        return RetainedNavigationViewChrome(
            containerBackground: nil,
            containerBorderColor: .clear,
            containerBorderWidth: 0,
            containerCornerRadius: 0,
            headerBackground: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.96),
            headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
            headerBorderWidth: 1,
            headerCornerRadius: 10,
            spacing: 10
        )
    case .doubleColumn:
        return RetainedNavigationViewChrome(
            containerBackground: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.28),
            containerBorderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08),
            containerBorderWidth: 1,
            containerCornerRadius: 12,
            headerBackground: Color(red: 0.06, green: 0.09, blue: 0.14, alpha: 0.94),
            headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            headerBorderWidth: 1,
            headerCornerRadius: 8,
            spacing: 12
        )
    case .columns:
        return RetainedNavigationViewChrome(
            containerBackground: Color(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.24),
            containerBorderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
            containerBorderWidth: 1,
            containerCornerRadius: 14,
            headerBackground: Color(red: 0.09, green: 0.13, blue: 0.19, alpha: 0.90),
            headerBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
            headerBorderWidth: 1,
            headerCornerRadius: 12,
            spacing: 12
        )
    }
}
@MainActor
private func navigationContainerComponent(
    from content: [AnyView],
    state: NavigationContainerState,
    pathBinding: NavigationPathBinding?,
    context: ViewBuildContext,
    navigationViewStyle: NavigationViewStyle? = nil,
    fallbackLayout: ViewLayoutMode
) -> Component {
    navigationContainerComponent(
        from: content,
        destinationStack: state.destinationStack,
        setDestinationStack: { state.destinationStack = $0 },
        pathBinding: pathBinding,
        context: context,
        navigationViewStyle: navigationViewStyle,
        fallbackLayout: fallbackLayout
    )
}
@MainActor
private func navigationContainerComponent(
    from content: [AnyView],
    destinationStack: [NavigationStackEntry],
    setDestinationStack: @escaping ([NavigationStackEntry]) -> Void,
    pathBinding: NavigationPathBinding?,
    context: ViewBuildContext,
    navigationViewStyle: NavigationViewStyle? = nil,
    fallbackLayout: ViewLayoutMode
) -> Component {
    let rootDestinationRegistrations =
        context.navigationDestinationRegistrations
        + navigationDestinations(in: content)
    let rootPresentedDestinations =
        context.navigationPresentedDestinations
        + navigationPresentedDestinations(in: content)
    let pathDestinationStack = resolvedNavigationStack(
        from: pathBinding?.values() ?? [],
        registrations: rootDestinationRegistrations
    )
    let activePresentation = activeNavigationPresentation(in: rootPresentedDestinations)
    let presentedDestination = activePresentation?.destination
    let pushedDestinationStack = destinationStack.map(\.destination)
    let combinedDestinationStack =
        pathDestinationStack + pushedDestinationStack + [presentedDestination].compactMap { $0 }
    let visibleContent = combinedDestinationStack.last ?? content
    let destinationRegistrations =
        rootDestinationRegistrations
        + navigationDestinations(in: visibleContent)

    func pushDestination(_ destination: [AnyView], onDismiss: (@MainActor () -> Void)? = nil) {
        guard !destination.isEmpty else {
            return
        }

        var updatedStack = destinationStack
        updatedStack.append(NavigationStackEntry(destination: destination, onDismiss: onDismiss))
        setDestinationStack(updatedStack)
        context.invalidate()
    }

    func dismissVisibleDestination() {
        var didDismiss = false
        if let activePresentation {
            activePresentation.dismiss()
            didDismiss = true
        } else if !destinationStack.isEmpty {
            var updatedStack = destinationStack
            let dismissed = updatedStack.popLast()
            setDestinationStack(updatedStack)
            dismissed?.onDismiss?()
            didDismiss = true
        } else if let pathBinding, !pathBinding.values().isEmpty {
            pathBinding.removeLast()
            didDismiss = true
        }

        if didDismiss {
            context.invalidate()
        }
    }

    let navigationContext =
        context
        .withEnvironmentValue(
            \.dismiss,
            DismissAction {
                dismissVisibleDestination()
            }
        )
        .withEnvironmentValue(\.isPresented, !combinedDestinationStack.isEmpty)
        .withNavigationDestinationHandler { destination, onDismiss in
            pushDestination(destination, onDismiss: onDismiss)
        }
        .withNavigationValueHandler { value in
            guard
                let destination = resolveNavigationDestination(
                    for: value,
                    registrations: destinationRegistrations
                )
            else {
                return false
            }

            if pathBinding?.append(value) == true {
                context.invalidate()
            } else {
                pushDestination(destination)
            }
            return true
        }
    let body = composeComponent(
        from: visibleContent,
        context: navigationContext,
        fallbackLayout: fallbackLayout
    )

    let title = navigationTitle(in: visibleContent) ?? navigationTitle(in: content)
    let subtitle = navigationSubtitle(in: visibleContent) ?? navigationSubtitle(in: content)
    let hidesNavigationBar = navigationBarHidden(in: visibleContent) ?? navigationBarHidden(in: content) ?? false
    guard !hidesNavigationBar else {
        return body
    }

    let shouldShowChrome = title != nil || subtitle != nil || !combinedDestinationStack.isEmpty
    guard shouldShowChrome else {
        return body
    }

    let hidesBackButton = navigationBarBackButtonHidden(in: visibleContent) ?? false
    let displayMode =
        navigationTitleDisplayMode(in: visibleContent) ?? navigationTitleDisplayMode(in: content) ?? .automatic
    let titleFont: Font =
        displayMode == .inline
        ? .system(size: 2, weight: .semibold)
        : .system(size: 3, weight: .bold)
    let chrome = retainedNavigationViewChrome(for: navigationViewStyle)
    let titleContext =
        context
        .withForegroundColor(Color(red: 0.92, green: 0.96, blue: 1.0))
        .withFont(titleFont)
    let subtitleContext =
        context
        .withForegroundColor(Color(red: 0.70, green: 0.78, blue: 0.90, alpha: 0.86))
        .withFont(.system(size: 1.35, weight: .regular))

    let titleComponent = composeComponent(
        from: title ?? [AnyView(Text("BACK"))],
        context: titleContext,
        fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
    )
    let subtitleComponent = subtitle.map {
        composeComponent(
            from: $0,
            context: subtitleContext,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )
    }

    return Component { runtime in
        let titleNode = titleComponent.makeNode(runtime: runtime)
        let subtitleNode = subtitleComponent?.makeNode(runtime: runtime)
        let bodyNode = body.makeNode(runtime: runtime)
        var headerChildren: [ViewNode] = []

        // Extract toolbar items from the body and hoist them into the header.
        let effectiveBodyNode: ViewNode
        if let toolbarInfo = extractToolbarContent(from: bodyNode) {
            headerChildren.append(contentsOf: toolbarInfo.toolbarContent)
            effectiveBodyNode = toolbarInfo.remainingBody
        } else {
            effectiveBodyNode = bodyNode
        }

        if !combinedDestinationStack.isEmpty && !hidesBackButton {
            let backLabel = Controls.label(
                "<",
                preferredSize: Size(width: 22, height: 26),
                color: Color(red: 0.92, green: 0.96, blue: 1.0),
                scale: 1.5,
                weight: .bold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            let backButton = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8),
                        alignment: .center,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled,
                action: {
                    dismissVisibleDestination()
                },
                children: [backLabel]
            )
            headerChildren.append(backButton)
        }
        if let subtitleNode {
            headerChildren.append(
                Controls.stackPanel(
                    stackLayout: .vertical(
                        spacing: 2,
                        padding: .zero,
                        alignment: .leading
                    ),
                    isHitTestVisible: false,
                    children: [titleNode, subtitleNode]
                )
            )
        } else {
            headerChildren.append(titleNode)
        }

        let headerNode = Controls.stackPanel(
            backgroundColor: chrome.headerBackground,
            borderColor: chrome.headerBorderColor,
            borderWidth: chrome.headerBorderWidth,
            cornerRadius: chrome.headerCornerRadius,
            stackLayout: .horizontal(
                spacing: 8,
                padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: headerChildren
        )

        return Controls.stackPanel(
            backgroundColor: chrome.containerBackground,
            borderColor: chrome.containerBorderColor,
            borderWidth: chrome.containerBorderWidth,
            cornerRadius: chrome.containerCornerRadius,
            stackLayout: .vertical(spacing: chrome.spacing, alignment: .stretch),
            isHitTestVisible: false,
            children: [headerNode, effectiveBodyNode]
        )
    }
}
@MainActor
private func extractToolbarContent(from node: ViewNode) -> (toolbarContent: [ViewNode], remainingBody: ViewNode)? {
    // The .toolbar() modifier wraps content as:
    // stackPanel(vertical, children: [toolbarNode, baseNode])
    // where toolbarNode is a stackPanel(horizontal, children: [toolbarContentNode])
    guard case .stack(let layout) = node.layoutMode, layout.axis == .vertical else {
        return nil
    }
    guard let toolbarIndex = node.children.firstIndex(where: { $0.isToolbarContainer }) else {
        return nil
    }
    let toolbarNode = node.children[toolbarIndex]
    let toolbarContent = toolbarNode.children
    node.removeChild(at: toolbarIndex)
    return (toolbarContent, node)
}
@MainActor
private func navigationTitle(in content: [AnyView]) -> [AnyView]? {
    content.lazy.compactMap(\.navigationTitle).first
}
@MainActor
private func navigationSubtitle(in content: [AnyView]) -> [AnyView]? {
    content.lazy.compactMap(\.navigationSubtitle).first
}
@MainActor
private func navigationTitleDisplayMode(in content: [AnyView]) -> NavigationBarItem.TitleDisplayMode? {
    content.lazy.compactMap(\.navigationTitleDisplayMode).first
}
@MainActor
private func navigationBarBackButtonHidden(in content: [AnyView]) -> Bool? {
    content.lazy.compactMap(\.navigationBarBackButtonHidden).first
}
@MainActor
private func navigationBarHidden(in content: [AnyView]) -> Bool? {
    content.lazy.compactMap(\.navigationBarHidden).first
}
@MainActor
private func navigationDestinations(in content: [AnyView]) -> [NavigationDestinationRegistration] {
    content.flatMap(\.navigationDestinationRegistrations)
}
@MainActor
private func navigationPresentedDestinations(in content: [AnyView]) -> [NavigationPresentedDestination] {
    content.flatMap(\.navigationPresentedDestinations)
}
@MainActor
private func activeNavigationPresentation(
    in presentations: [NavigationPresentedDestination]
) -> (destination: [AnyView], dismiss: () -> Void)? {
    for presentation in presentations.reversed() {
        guard let destination = presentation.destination(), !destination.isEmpty else {
            continue
        }

        return (destination, presentation.dismiss)
    }

    return nil
}
@MainActor
private func resolveNavigationDestination(
    for value: AnyHashable,
    registrations: [NavigationDestinationRegistration]
) -> [AnyView]? {
    for registration in registrations.reversed() {
        if let destination = registration.resolve(value) {
            return destination
        }
    }

    return nil
}
@MainActor
private func resolvedNavigationStack(
    from values: [AnyHashable],
    registrations: [NavigationDestinationRegistration]
) -> [[AnyView]] {
    var stack: [[AnyView]] = []
    var availableRegistrations = registrations
    for value in values {
        guard let destination = resolveNavigationDestination(for: value, registrations: availableRegistrations) else {
            break
        }

        stack.append(destination)
        availableRegistrations += navigationDestinations(in: destination)
    }

    return stack
}
@MainActor
public struct NavigationSplitView: View {
    public typealias Body = Never

    private let columns: [[AnyView]]
    private let columnVisibility: Binding<NavigationSplitViewVisibility>?
    private let preferredCompactColumn: Binding<NavigationSplitViewColumn?>?

    public init(
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), detail()]
        self.columnVisibility = nil
        self.preferredCompactColumn = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), detail()]
        self.columnVisibility = columnVisibility
        self.preferredCompactColumn = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn?>,
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), detail()]
        self.columnVisibility = columnVisibility
        self.preferredCompactColumn = preferredCompactColumn
    }

    public init(
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), content(), detail()]
        self.columnVisibility = nil
        self.preferredCompactColumn = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), content(), detail()]
        self.columnVisibility = columnVisibility
        self.preferredCompactColumn = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn?>,
        @ViewBuilder sidebar: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder detail: () -> [AnyView]
    ) {
        self.columns = [sidebar(), content(), detail()]
        self.columnVisibility = columnVisibility
        self.preferredCompactColumn = preferredCompactColumn
    }

    public var body: Never {
        fatalError("NavigationSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let visibleColumns = visibleColumns()
        let style = context.navigationSplitViewStyle
        let columnComponents = visibleColumns.map { column in
            composeComponent(
                from: column,
                context: context.withStackAxis(.vertical),
                fallbackLayout: .stack(.vertical(alignment: .stretch))
            )
        }

        let compactColumn = preferredCompactColumn
        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .horizontal(spacing: 0, alignment: .stretch),
                isHitTestVisible: false,
                children: columnComponents.enumerated().map { index, component in
                    let node = component.makeNode(runtime: runtime)
                    Self.applyRetainedColumnStyle(
                        to: node,
                        index: index,
                        count: columnComponents.count,
                        style: style
                    )
                    node.preferredCompactColumn = compactColumn?.wrappedValue
                    return node
                }
            )
        }
    }

    private static func applyRetainedColumnStyle(
        to node: ViewNode,
        index: Int,
        count: Int,
        style: NavigationSplitViewStyle
    ) {
        switch style.kind {
        case .automatic:
            node.layoutPriority = 1
            node.borderColor = index == count - 1 ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08)
            node.borderWidth = index == count - 1 ? 0 : 1
        case .balanced:
            node.layoutPriority = 1
            node.backgroundColor = Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.24)
            node.borderColor = index == count - 1 ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10)
            node.borderWidth = index == count - 1 ? 0 : 1
        case .prominentDetail:
            let isDetail = index == count - 1
            node.layoutPriority = isDetail ? 2 : 0.75
            node.backgroundColor =
                isDetail
                ? Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.30)
                : Color(red: 0.06, green: 0.09, blue: 0.13, alpha: 0.28)
            node.borderColor = isDetail ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.12)
            node.borderWidth = isDetail ? 0 : 1
        case .prominentDetailAndSidebar:
            let isDetail = index == count - 1
            node.layoutPriority = isDetail ? 2 : 0.75
            node.backgroundColor =
                isDetail
                ? Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.30)
                : Color(red: 0.06, green: 0.09, blue: 0.13, alpha: 0.28)
            node.borderColor = isDetail ? .clear : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.12)
            node.borderWidth = isDetail ? 0 : 1
        }
    }

    private func visibleColumns() -> [[AnyView]] {
        guard let visibility = columnVisibility?.wrappedValue else {
            return columns
        }

        switch visibility {
        case .automatic, .all:
            return columns
        case .doubleColumn:
            guard columns.count > 2 else {
                return columns
            }
            return Array(columns.suffix(2))
        case .detailOnly:
            return columns.last.map { [$0] } ?? []
        }
    }
}
@MainActor
public struct NavigationLink: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let destination: [AnyView]
    private let value: AnyHashable?
    private let isActive: Binding<Bool>?
    private let activateSelection: (@MainActor () -> Void)?
    private let dismissSelection: (@MainActor () -> Void)?

    public init<Destination: View>(
        destination: Destination,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init(
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.value = nil
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<Destination: View>(
        destination: Destination,
        isActive: Binding<Bool>,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = isActive
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init(
        isActive: Binding<Bool>,
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.value = nil
        self.isActive = isActive
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<Destination: View, Selection: Hashable>(
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = nil
        self.activateSelection = {
            selection.wrappedValue = tag
        }
        self.dismissSelection = {
            if selection.wrappedValue == tag {
                selection.wrappedValue = nil
            }
        }
    }

    public init<Selection: Hashable>(
        tag: Selection,
        selection: Binding<Selection?>,
        @ViewBuilder destination: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = destination()
        self.value = nil
        self.isActive = nil
        self.activateSelection = {
            selection.wrappedValue = tag
        }
        self.dismissSelection = {
            if selection.wrappedValue == tag {
                selection.wrappedValue = nil
            }
        }
    }

    public init<Destination: View>(
        _ title: String,
        destination: Destination
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<S: StringProtocol, Destination: View>(
        _ title: S,
        destination: Destination
    ) {
        self.init(String(title), destination: destination)
    }

    public init<Destination: View>(
        _ titleKey: LocalizedStringKey,
        destination: Destination
    ) {
        self.init(titleKey.resolvedString, destination: destination)
    }

    public init<Destination: View>(
        _ title: String,
        destination: Destination,
        isActive: Binding<Bool>
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = [AnyView(destination)]
        self.value = nil
        self.isActive = isActive
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<S: StringProtocol, Destination: View>(
        _ title: S,
        destination: Destination,
        isActive: Binding<Bool>
    ) {
        self.init(String(title), destination: destination, isActive: isActive)
    }

    public init<Destination: View>(
        _ titleKey: LocalizedStringKey,
        destination: Destination,
        isActive: Binding<Bool>
    ) {
        self.init(titleKey.resolvedString, destination: destination, isActive: isActive)
    }

    public init<Destination: View, Selection: Hashable>(
        _ title: String,
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>
    ) {
        self.init(destination: destination, tag: tag, selection: selection) {
            Text(title)
        }
    }

    public init<S: StringProtocol, Destination: View, Selection: Hashable>(
        _ title: S,
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>
    ) {
        self.init(String(title), destination: destination, tag: tag, selection: selection)
    }

    public init<Destination: View, Selection: Hashable>(
        _ titleKey: LocalizedStringKey,
        destination: Destination,
        tag: Selection,
        selection: Binding<Selection?>
    ) {
        self.init(titleKey.resolvedString, destination: destination, tag: tag, selection: selection)
    }

    public init<Value: Hashable>(
        value: Value,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.destination = []
        self.value = AnyHashable(value)
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<Value: Hashable>(
        _ title: String,
        value: Value
    ) {
        self.label = [AnyView(Text(title))]
        self.destination = []
        self.value = AnyHashable(value)
        self.isActive = nil
        self.activateSelection = nil
        self.dismissSelection = nil
    }

    public init<S: StringProtocol, Value: Hashable>(
        _ title: S,
        value: Value
    ) {
        self.init(String(title), value: value)
    }

    public init<Value: Hashable>(
        _ titleKey: LocalizedStringKey,
        value: Value
    ) {
        self.init(titleKey.resolvedString, value: value)
    }

    public var body: Never {
        fatalError("NavigationLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )

        if destination.isEmpty, value == nil {
            return labelComponent
        }

        let destinationViews = destination
        let navigationValue = value
        let activeBinding = isActive
        let activateSelection = activateSelection
        let dismissSelection = dismissSelection
        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                        alignment: .stretch,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled,
                action: {
                    if let navigationValue {
                        _ = context.pushNavigationValue(navigationValue)
                    } else if let activeBinding {
                        activeBinding.wrappedValue = true
                        _ = context.pushNavigationDestination(destinationViews) {
                            activeBinding.wrappedValue = false
                        }
                    } else if let activateSelection {
                        activateSelection()
                        _ = context.pushNavigationDestination(destinationViews, onDismiss: dismissSelection)
                    } else {
                        _ = context.pushNavigationDestination(destinationViews)
                    }
                },
                children: [labelNode]
            )
        }
    }
}
@MainActor
public struct TabView: View {
    public typealias Body = Never

    private final class TabState {
        var selectedIndex = 0
    }

    private let state = TabState()
    private let content: [AnyView]
    private let selectedTag: (@MainActor () -> AnyHashable?)?
    private let setSelectedTag: (@MainActor (AnyHashable) -> Void)?

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
        self.selectedTag = nil
        self.setSelectedTag = nil
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectedTag = {
            AnyHashable(selection.wrappedValue)
        }
        self.setSelectedTag = { tag in
            guard let value = tag.base as? SelectionValue else {
                return
            }
            selection.wrappedValue = value
        }
    }

    public var body: Never {
        fatalError("TabView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        guard !content.isEmpty else {
            return composeComponent(from: [], context: context)
        }

        let selectedIndex = selectedPageIndex()
        let page = composeComponent(
            from: [content[selectedIndex]],
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
        let tabBar = tabBarComponent(selectedIndex: selectedIndex, context: context)

        return Component { runtime in
            let tabBarNode = tabBar.makeNode(runtime: runtime)
            let pageNode = page.makeNode(runtime: runtime)
            var children = [tabBarNode, pageNode]
            if let pageIndexNode = Self.retainedPageIndexNode(
                selectedIndex: selectedIndex,
                count: content.count,
                tabViewStyle: context.tabViewStyle,
                indexViewStyle: context.indexViewStyle,
                tint: context.tint
            ) {
                children.append(pageIndexNode)
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 10, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private func selectedPageIndex() -> Int {
        guard !content.isEmpty else {
            return 0
        }

        if let selectedTag = selectedTag?(),
            let selectedIndex = content.firstIndex(where: { $0.selectionTag == selectedTag })
        {
            return selectedIndex
        }

        if selectedTag == nil {
            state.selectedIndex = min(max(0, state.selectedIndex), content.count - 1)
            return state.selectedIndex
        }

        return 0
    }

    private func tabBarComponent(selectedIndex: Int, context: ViewBuildContext) -> Component {
        Component { runtime in
            let chrome = Self.retainedTabChrome(for: context.tabViewStyle)
            let tabNodes = content.enumerated().map { index, view in
                let labelViews = view.tabItem ?? [AnyView(Text("TAB \(index + 1)"))]
                let labelNode = composeComponent(
                    from: labelViews,
                    context: context,
                    fallbackLayout: .stack(.horizontal(spacing: 4, alignment: .center))
                )
                .makeNode(runtime: runtime)
                let tabContentNode: ViewNode
                if let badgeViews = view.badge {
                    tabContentNode = Controls.stackPanel(
                        stackLayout: .horizontal(spacing: 6, padding: .zero, alignment: .center),
                        isHitTestVisible: false,
                        children: [
                            labelNode,
                            context.makeRetainedBadgeNode(from: badgeViews, runtime: runtime),
                        ]
                    )
                } else {
                    tabContentNode = labelNode
                }
                let isSelected = index == selectedIndex
                let palette =
                    isSelected
                    ? ButtonSurfaceStyle.default.palette
                    : ButtonSurfaceStyle.plain.palette

                return Controls.button(
                    runtime: runtime,
                    layoutPriority: 1,
                    cornerRadius: chrome.tabCornerRadius,
                    palette: palette,
                    chrome: SurfaceChrome(
                        borderColor: isSelected
                            ? context.tint.opacity(chrome.selectedBorderAlpha) : chrome.unselectedBorderColor,
                        borderHoveredColor: context.tint.opacity(isSelected ? 0.62 : chrome.hoverBorderAlpha),
                        borderFocusedColor: context.tint.opacity(0.68),
                        borderPressedColor: context.tint.opacity(0.78),
                        borderWidth: isSelected ? chrome.selectedBorderWidth : chrome.unselectedBorderWidth,
                        focusRingColor: context.tint.opacity(0.24),
                        focusRingWidth: 2
                    ),
                    layoutMode: .stack(
                        .vertical(
                            padding: chrome.tabPadding,
                            alignment: .center,
                            mainAlignment: .center
                        )),
                    isEnabled: context.isEnabled,
                    action: {
                        if let tag = view.selectionTag {
                            setSelectedTag?(tag)
                        }
                        state.selectedIndex = index
                        context.invalidate()
                    },
                    children: [tabContentNode]
                )
            }

            return Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                borderColor: chrome.borderColor,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                clipsToBounds: true,
                stackLayout: .horizontal(
                    spacing: chrome.spacing,
                    padding: chrome.padding,
                    alignment: .stretch
                ),
                isHitTestVisible: false,
                children: tabNodes
            )
        }
    }

    private struct RetainedTabChrome {
        var backgroundColor: Color
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
        var spacing: Double
        var padding: EdgeInsets
        var tabCornerRadius: Double
        var tabPadding: EdgeInsets
        var selectedBorderAlpha: Double
        var selectedBorderWidth: Double
        var unselectedBorderColor: Color
        var unselectedBorderWidth: Double
        var hoverBorderAlpha: Double
    }

    private struct RetainedPageIndexChrome {
        var backgroundColor: Color?
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
    }

    private static func retainedPageIndexNode(
        selectedIndex: Int,
        count: Int,
        tabViewStyle: TabViewStyle,
        indexViewStyle: IndexViewStyle,
        tint: Color
    ) -> ViewNode? {
        guard count > 1, shouldRenderPageIndex(for: tabViewStyle) else {
            return nil
        }

        let chrome = retainedPageIndexChrome(for: indexViewStyle)
        let dots = (0..<count).map { index in
            let isSelected = index == selectedIndex
            let node = Controls.panel(
                preferredSize: Size(width: isSelected ? 18 : 6, height: 6),
                backgroundColor: isSelected
                    ? tint.opacity(0.92)
                    : Color(red: 0.74, green: 0.80, blue: 0.90, alpha: 0.42),
                cornerRadius: 3,
                isHitTestVisible: false
            )
            node.nodeTag = isSelected ? "tab-page-index-selected" : "tab-page-index-unselected"
            return node
        }

        let node = Controls.stackPanel(
            backgroundColor: chrome.backgroundColor,
            borderColor: chrome.borderColor,
            borderWidth: chrome.borderWidth,
            cornerRadius: chrome.cornerRadius,
            stackLayout: .horizontal(
                spacing: 5,
                padding: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: dots
        )
        node.nodeTag = "tab-page-index"
        return node
    }

    private static func shouldRenderPageIndex(for style: TabViewStyle) -> Bool {
        switch style.kind {
        case .page(let indexDisplayMode):
            return indexDisplayMode != .never
        case .verticalPage:
            return true
        case .automatic, .sidebarAdaptable, .tabBarOnly, .grouped, .carousel:
            return false
        }
    }

    private static func retainedPageIndexChrome(for style: IndexViewStyle) -> RetainedPageIndexChrome {
        switch style.kind {
        case .page(let backgroundDisplayMode):
            switch backgroundDisplayMode.kind {
            case .automatic:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.34),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderWidth: 1,
                    cornerRadius: 9
                )
            case .always:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.72),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderWidth: 1,
                    cornerRadius: 10
                )
            case .interactive:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.52),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                    borderWidth: 1,
                    cornerRadius: 10
                )
            case .never:
                return RetainedPageIndexChrome(
                    backgroundColor: nil,
                    borderColor: .clear,
                    borderWidth: 0,
                    cornerRadius: 0
                )
            }
        }
    }

    private static func retainedTabChrome(for style: TabViewStyle) -> RetainedTabChrome {
        switch style.kind {
        case .automatic, .tabBarOnly:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.88),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 12,
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                tabCornerRadius: 8,
                tabPadding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                selectedBorderAlpha: 0.42,
                selectedBorderWidth: 1,
                unselectedBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                unselectedBorderWidth: 1,
                hoverBorderAlpha: 0.24
            )
        case .grouped:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.74),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                borderWidth: 1,
                cornerRadius: 16,
                spacing: 8,
                padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                tabCornerRadius: 10,
                tabPadding: EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14),
                selectedBorderAlpha: 0.50,
                selectedBorderWidth: 1,
                unselectedBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.06),
                unselectedBorderWidth: 1,
                hoverBorderAlpha: 0.28
            )
        case .sidebarAdaptable:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.70),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 8,
                spacing: 3,
                padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5),
                tabCornerRadius: 6,
                tabPadding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                selectedBorderAlpha: 0.48,
                selectedBorderWidth: 2,
                unselectedBorderColor: .clear,
                unselectedBorderWidth: 0,
                hoverBorderAlpha: 0.22
            )
        case .page, .verticalPage:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 0.48),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.06),
                borderWidth: 1,
                cornerRadius: 20,
                spacing: 6,
                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                tabCornerRadius: 16,
                tabPadding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12),
                selectedBorderAlpha: 0.58,
                selectedBorderWidth: 1,
                unselectedBorderColor: .clear,
                unselectedBorderWidth: 0,
                hoverBorderAlpha: 0.18
            )
        case .carousel:
            return RetainedTabChrome(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.58),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: 18,
                spacing: 10,
                padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10),
                tabCornerRadius: 14,
                tabPadding: EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16),
                selectedBorderAlpha: 0.56,
                selectedBorderWidth: 1,
                unselectedBorderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.05),
                unselectedBorderWidth: 1,
                hoverBorderAlpha: 0.20
            )
        }
    }
}
@MainActor
public struct TabSection<Content: View>: View {
    public typealias Body = Never

    private let title: String?
    private let content: [AnyView]

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.title = title
        self.content = content()
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.title = String(describing: titleKey)
        self.content = content()
    }

    public var body: Never {
        fatalError("TabSection has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.vertical(alignment: .stretch))
        )
    }
}
@MainActor
public struct TableOfContents: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("TableOfContents has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: [], context: context)
    }
}
@MainActor
public protocol DynamicViewContent<Data>: View {
    associatedtype Data: Collection

    var data: Data { get }
}
@MainActor
public struct ForEach<Data: RandomAccessCollection, ID: Hashable>: View {
    public typealias Body = Never

    public let data: Data
    let contentViews: [AnyView]

    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: (Data.Element) -> [AnyView]) {
        self.data = data
        self.contentViews = Self.buildContentViews(data: data, id: id, content: content)
    }

    private init(data: Data, contentViews: [AnyView]) {
        self.data = data
        self.contentViews = contentViews
    }

    public var body: Never {
        fatalError("ForEach has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: contentViews, context: context)
    }

    private static func buildContentViews(
        data: Data,
        id: KeyPath<Data.Element, ID>,
        content: (Data.Element) -> [AnyView]
    ) -> [AnyView] {
        var views: [AnyView] = []
        for (elementIndex, element) in data.enumerated() {
            let elementID = String(describing: element[keyPath: id])
            let elementViews = content(element)
            for (index, view) in elementViews.enumerated() {
                views.append(
                    AnyView(
                        DynamicListEditMetadataView(
                            content: AnyView(view.id("\(elementID)#\(index)")),
                            dynamicContentIndex: elementIndex
                        )
                    )
                )
            }
        }
        return views
    }
}
extension ForEach: DynamicViewContent {}
extension ForEach {
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> ForEach<Data, ID> {
        ForEach(
            data: data,
            contentViews: contentViews.map { view in
                AnyView(
                    DynamicListEditMetadataView(
                        content: view,
                        deleteAction: .some(action)
                    )
                )
            }
        )
    }

    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> ForEach<Data, ID> {
        ForEach(
            data: data,
            contentViews: contentViews.map { view in
                AnyView(
                    DynamicListEditMetadataView(
                        content: view,
                        moveAction: .some(action)
                    )
                )
            }
        )
    }

    public func onInsert(
        of supportedContentTypes: [UTType],
        perform action: @escaping (Int, [NSItemProvider]) -> Void
    ) -> ForEach<Data, ID> {
        let identifiers = supportedContentTypes.map(\.identifier)
        return ForEach(
            data: data,
            contentViews: contentViews.map { view in
                AnyView(
                    DynamicListEditMetadataView(
                        content: view,
                        insertContentTypes: identifiers,
                        insertAction: action
                    )
                )
            }
        )
    }

    public func onInsert(
        of acceptedTypeIdentifiers: [String],
        perform action: @escaping (Int, [NSItemProvider]) -> Void
    ) -> ForEach<Data, ID> {
        ForEach(
            data: data,
            contentViews: contentViews.map { view in
                AnyView(
                    DynamicListEditMetadataView(
                        content: view,
                        insertContentTypes: acceptedTypeIdentifiers,
                        insertAction: action
                    )
                )
            }
        )
    }

    public func dropDestination<T: Transferable>(
        for payloadType: T.Type = T.self,
        action: @escaping ([T], Int) -> Void
    ) -> ForEach<Data, ID> {
        ForEach(
            data: data,
            contentViews: contentViews.map { view in
                AnyView(
                    DynamicListEditMetadataView(
                        content: view,
                        dropPayloadType: String(reflecting: payloadType),
                        dropAction: { payloads, offset in
                            action(payloads.compactMap { $0 as? T }, offset)
                        }
                    )
                )
            }
        )
    }
}
@MainActor
private struct DynamicListEditMetadataView: View, TaggedViewMetadata {
    typealias Body = Never

    let content: AnyView
    var dynamicContentIndex: Int? = nil
    var deleteAction: (((IndexSet) -> Void)?)? = nil
    var moveAction: (((IndexSet, Int) -> Void)?)? = nil
    var insertContentTypes: [String]? = nil
    var insertAction: ((Int, [NSItemProvider]) -> Void)? = nil
    var dropPayloadType: String? = nil
    var dropAction: (([Any], Int) -> Void)? = nil

    var anySelectionTag: AnyHashable? {
        content.selectionTag
    }

    var anyTabItem: [AnyView]? {
        content.tabItem
    }

    var anyBadge: [AnyView]? {
        content.badge
    }

    var anyNavigationTitle: [AnyView]? {
        content.navigationTitle
    }

    var anyNavigationSubtitle: [AnyView]? {
        content.navigationSubtitle
    }

    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? {
        content.navigationTitleDisplayMode
    }

    var anyNavigationBarBackButtonHidden: Bool? {
        content.navigationBarBackButtonHidden
    }

    var anyNavigationBarHidden: Bool? {
        content.navigationBarHidden
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        content.toolbarItemPlacement
    }

    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        content.navigationDestinationRegistrations
    }

    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        content.navigationPresentedDestinations
    }

    var body: Never {
        fatalError("DynamicListEditMetadataView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let component = content.makeComponent(context: context)
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            if let dynamicContentIndex {
                node.dynamicContentIndex = dynamicContentIndex
            }
            if let deleteAction {
                node.onDeleteRows = deleteAction
            }
            if let moveAction {
                node.onMoveRows = moveAction
            }
            if let insertContentTypes {
                node.dynamicInsertContentTypes = insertContentTypes
            }
            if let insertAction {
                node.onInsertRows = { offset, items in
                    insertAction(offset, items.compactMap { $0 as? NSItemProvider })
                }
            }
            if let dropPayloadType {
                node.dynamicDropPayloadType = dropPayloadType
            }
            if let dropAction {
                node.onDropRows = dropAction
            }
            return node
        }
    }
}
@MainActor
public struct BindingCollectionElement<Element, ID: Hashable> {
    public let id: ID
    public let binding: Binding<Element>
}
extension ForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: (Data.Element) -> [AnyView]) {
        self.init(data, id: \.id, content: content)
    }
}
extension ForEach {
    public init<Collection>(
        _ data: Binding<Collection>,
        @ViewBuilder content: (Binding<Collection.Element>) -> [AnyView]
    )
    where
        Data == [BindingCollectionElement<Collection.Element, ID>],
        Collection: MutableCollection & RandomAccessCollection,
        Collection.Element: Identifiable,
        Collection.Index: Hashable,
        ID == Collection.Element.ID
    {
        let elements = data.wrappedValue.indices.map { index in
            BindingCollectionElement(
                id: data.wrappedValue[index].id,
                binding: Binding<Collection.Element>(
                    get: {
                        data.wrappedValue[index]
                    },
                    set: { newValue in
                        var collection = data.wrappedValue
                        collection[index] = newValue
                        data.wrappedValue = collection
                    }
                )
            )
        }

        self.data = elements
        self.contentViews = Self.buildContentViews(data: elements, id: \.id) { element in
            content(element.binding)
        }
    }

    public init<Collection>(
        _ data: Binding<Collection>,
        id: KeyPath<Collection.Element, ID>,
        @ViewBuilder content: (Binding<Collection.Element>) -> [AnyView]
    )
    where
        Data == [BindingCollectionElement<Collection.Element, ID>],
        Collection: MutableCollection & RandomAccessCollection,
        Collection.Index: Hashable
    {
        let elements = data.wrappedValue.indices.map { index in
            BindingCollectionElement(
                id: data.wrappedValue[index][keyPath: id],
                binding: Binding<Collection.Element>(
                    get: {
                        data.wrappedValue[index]
                    },
                    set: { newValue in
                        var collection = data.wrappedValue
                        collection[index] = newValue
                        data.wrappedValue = collection
                    }
                )
            )
        }

        self.data = elements
        self.contentViews = Self.buildContentViews(data: elements, id: \.id) { element in
            content(element.binding)
        }
    }
}
extension ForEach where Data == Range<Int>, ID == Int {
    public init(_ data: Range<Int>, @ViewBuilder content: (Int) -> [AnyView]) {
        self.init(data, id: \.self, content: content)
    }
}
extension ForEach where Data == ClosedRange<Int>, ID == Int {
    public init(_ data: ClosedRange<Int>, @ViewBuilder content: (Int) -> [AnyView]) {
        self.init(data, id: \.self, content: content)
    }
}
@MainActor
public struct Text: View {
    public typealias Body = Never

    public enum TruncationMode: Sendable, Equatable {
        case head
        case tail
        case middle
    }

    public enum Case: Sendable, Equatable {
        case uppercase
        case lowercase
    }

    public struct Scale: Sendable, Equatable, Hashable {
        private let rawValue: String

        private init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public static let `default` = Scale("default")
        public static let secondary = Scale("secondary")
    }

    public struct Layout: Sendable {
        public struct Run: Sendable {
            public struct Slice: Sendable {
                public init() {}
            }

            public init() {}
        }

        public init() {}
    }

    public struct DateStyle: Sendable, Equatable, Hashable, Codable {
        fileprivate enum Kind: String, Sendable, Equatable, Hashable, Codable {
            case date
            case time
            case relative
            case offset
            case timer
        }

        fileprivate let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawKind = try container.decode(String.self)
            guard let kind = Kind(rawValue: rawKind) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown Text.DateStyle value: \(rawKind)"
                )
            }
            self.kind = kind
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(kind.rawValue)
        }

        public static let date = DateStyle(kind: .date)
        public static let time = DateStyle(kind: .time)
        public static let relative = DateStyle(kind: .relative)
        public static let offset = DateStyle(kind: .offset)
        public static let timer = DateStyle(kind: .timer)
    }

    public struct TimerStyle: Sendable, Equatable, Hashable {
        fileprivate enum Kind: String, Sendable, Equatable, Hashable {
            case minutes
            case hoursMinutes
            case hoursMinutesSeconds
            case countdown
            case countdownShort
            case countdownAbbreviated
        }

        fileprivate let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let minutes = TimerStyle(kind: .minutes)
        public static let hoursMinutes = TimerStyle(kind: .hoursMinutes)
        public static let hoursMinutesSeconds = TimerStyle(kind: .hoursMinutesSeconds)
        public static let countdown = TimerStyle(kind: .countdown)
        public static let countdownShort = TimerStyle(kind: .countdownShort)
        public static let countdownAbbreviated = TimerStyle(kind: .countdownAbbreviated)
    }

    public struct ReferenceType: Sendable, Equatable, Hashable {
        fileprivate enum Kind: String, Sendable, Equatable, Hashable {
            case normal
            case destination
            case source
        }

        fileprivate let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let normal = ReferenceType(kind: .normal)
        public static let destination = ReferenceType(kind: .destination)
        public static let source = ReferenceType(kind: .source)
    }

    public struct LineStyle: Sendable, Equatable {
        public enum Pattern: Sendable, Equatable, Hashable {
            case solid
            case dot
            case dash
            case dashDot
            case dashDotDot
        }

        public var pattern: Pattern
        public var color: Color?

        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }
    }

    private let content: String
    private var color: Color?
    private var font: Font??
    private var fontDesign: Font.Design?
    private var fontWidth: Font.Width??
    private var isItalic: Bool?
    private var monospacedDigits: Bool
    private var alignment: TextAlignment?
    private var lineLimit: Int??
    private var minimumLineLimit: Int??
    private var lineLimitReservesSpace: Bool?
    private var truncationMode: TruncationMode?
    private var letterSpacing: Double?
    private var lineSpacing: Double?
    private var textScale: Scale?
    private var minimumScaleFactor: CGFloat?
    private var allowsTightening: Bool?
    private var textCase: Case??
    private var baselineOffset: CGFloat?
    private var underline: Bool?
    private var underlinePattern: LineStyle.Pattern
    private var underlineColor: Color?
    private var strikethrough: Bool?
    private var strikethroughPattern: LineStyle.Pattern
    private var strikethroughColor: Color?
    private var timerStyle: TimerStyle?
    private var lineBreakMode: LineBreakMode?
    private var hyphenationFrequency: HyphenationFrequency?
    private var allowsDefaultTighteningForTruncation: Bool?
    private var typesettingLanguage: String?

    public var retainedTextDescription: String { content }

    public init(_ content: String) {
        self.content = content
        self.color = nil
        self.font = nil
        self.fontDesign = nil
        self.fontWidth = nil
        self.isItalic = nil
        self.monospacedDigits = false
        self.alignment = nil
        self.lineLimit = nil
        self.minimumLineLimit = nil
        self.lineLimitReservesSpace = nil
        self.truncationMode = nil
        self.letterSpacing = nil
        self.lineSpacing = nil
        self.textScale = nil
        self.minimumScaleFactor = nil
        self.allowsTightening = nil
        self.textCase = nil
        self.baselineOffset = nil
        self.underline = nil
        self.underlinePattern = .solid
        self.underlineColor = nil
        self.strikethrough = nil
        self.strikethroughPattern = .solid
        self.strikethroughColor = nil
        self.timerStyle = nil
        self.lineBreakMode = nil
        self.hyphenationFrequency = nil
        self.allowsDefaultTighteningForTruncation = nil
        self.typesettingLanguage = nil
    }

    public init(_ titleKey: LocalizedStringKey) {
        self.init(titleKey.resolvedString)
    }

    public init(_ key: LocalizedStringKey, tableName: String?) {
        self.init(key.resolvedString)
    }

    private init(
        content: String,
        color: Color?,
        font: Font??,
        fontDesign: Font.Design?,
        fontWidth: Font.Width??,
        isItalic: Bool?,
        monospacedDigits: Bool,
        alignment: TextAlignment?,
        lineLimit: Int??,
        minimumLineLimit: Int??,
        lineLimitReservesSpace: Bool?,
        truncationMode: TruncationMode?,
        letterSpacing: Double?,
        lineSpacing: Double?,
        textScale: Scale?,
        minimumScaleFactor: CGFloat?,
        allowsTightening: Bool?,
        textCase: Case??,
        baselineOffset: CGFloat?,
        underline: Bool?,
        underlinePattern: LineStyle.Pattern,
        underlineColor: Color?,
        strikethrough: Bool?,
        strikethroughPattern: LineStyle.Pattern,
        strikethroughColor: Color?,
        timerStyle: TimerStyle? = nil,
        lineBreakMode: LineBreakMode? = nil,
        hyphenationFrequency: HyphenationFrequency? = nil,
        allowsDefaultTighteningForTruncation: Bool? = nil,
        typesettingLanguage: String? = nil
    ) {
        self.content = content
        self.color = color
        self.font = font
        self.fontDesign = fontDesign
        self.fontWidth = fontWidth
        self.isItalic = isItalic
        self.monospacedDigits = monospacedDigits
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.minimumLineLimit = minimumLineLimit
        self.lineLimitReservesSpace = lineLimitReservesSpace
        self.truncationMode = truncationMode
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.textScale = textScale
        self.minimumScaleFactor = minimumScaleFactor
        self.allowsTightening = allowsTightening
        self.textCase = textCase
        self.baselineOffset = baselineOffset
        self.underline = underline
        self.underlinePattern = underline == true ? underlinePattern : .solid
        self.underlineColor = underline == true ? underlineColor : nil
        self.strikethrough = strikethrough
        self.strikethroughPattern = strikethrough == true ? strikethroughPattern : .solid
        self.strikethroughColor = strikethrough == true ? strikethroughColor : nil
        self.timerStyle = timerStyle
        self.lineBreakMode = lineBreakMode
        self.hyphenationFrequency = hyphenationFrequency
        self.allowsDefaultTighteningForTruncation = allowsDefaultTighteningForTruncation
        self.typesettingLanguage = typesettingLanguage
    }

    public init(
        _ key: LocalizedStringKey,
        tableName: String? = nil,
        bundle: Bundle? = nil,
        comment: StaticString? = nil
    ) {
        _ = tableName
        _ = bundle
        _ = comment
        self.init(key.resolvedString)
    }

    public init(_ resource: LocalizedStringResource) {
        self.init(resource.resolvedString)
    }

    public init(_ date: Date, style: DateStyle) {
        self.init(Self.formattedDateText(date, style: style))
    }

    public init(_ interval: DateInterval) {
        let startText = Self.formattedDateTimeText(interval.start)
        let endText = Self.formattedDateTimeText(interval.end)
        self.init("\(startText) - \(endText)")
    }

    public init(
        timerInterval: ClosedRange<Date>,
        pauseTime: Date? = nil,
        countsDown: Bool = true,
        showsHours: Bool = true
    ) {
        self.init(
            Self.formattedTimerIntervalText(
                timerInterval,
                pauseTime: pauseTime,
                countsDown: countsDown,
                showsHours: showsHours
            )
        )
    }

    public init<Subject>(_ subject: Subject, formatter: Formatter) {
        self.init(formatter.string(for: subject) ?? String(describing: subject))
    }

    public init(_ attributedContent: AttributedString) {
        self.init(Self.flattenedAttributedText(attributedContent))
    }

    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(format.format(input))
    }

    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == AttributedString {
        self.init(Self.flattenedAttributedText(format.format(input)))
    }

    public init<S: StringProtocol>(_ content: S) {
        self.init(String(content))
    }

    public init(verbatim content: String) {
        self.init(content)
    }

    public init(_ image: Image) {
        self.init(image.imageAccessibilityLabel ?? "Image")
    }

    public var body: Never {
        fatalError("Text has no body")
    }

    private static func formattedDateText(_ date: Date, style: DateStyle) -> String {
        switch style.kind {
        case .date:
            return formattedDateOnlyText(date)
        case .time:
            return formattedTimeOnlyText(date)
        case .relative, .offset, .timer:
            return formattedDateTimeText(date)
        }
    }

    private static func formattedDateOnlyText(_ date: Date) -> String {
        let components = retainedUTCDateComponents(for: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private static func formattedTimeOnlyText(_ date: Date) -> String {
        let components = retainedUTCDateComponents(for: date)
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private static func formattedDateTimeText(_ date: Date) -> String {
        "\(formattedDateOnlyText(date)) \(formattedTimeOnlyText(date))"
    }

    private static func retainedUTCDateComponents(for date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private static func flattenedAttributedText(_ attributedContent: AttributedString) -> String {
        String(attributedContent.characters)
    }

    private static func formattedTimerIntervalText(
        _ interval: ClosedRange<Date>,
        pauseTime: Date?,
        countsDown: Bool,
        showsHours: Bool
    ) -> String {
        let duration = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard duration > 0 else {
            return formatTimerDuration(0, showsHours: showsHours)
        }

        let referenceDate = pauseTime ?? Date()
        let elapsed = referenceDate.timeIntervalSince(interval.lowerBound)
        let unclampedSeconds = countsDown ? duration - elapsed : elapsed
        let clampedSeconds = min(max(unclampedSeconds, 0), duration)
        return formatTimerDuration(clampedSeconds, showsHours: showsHours)
    }

    private static func formatTimerDuration(_ seconds: TimeInterval, showsHours: Bool) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if showsHours, hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        let totalMinutes = totalSeconds / 60
        return String(format: "%d:%02d", totalMinutes, seconds)
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        Text(
            content: lhs.content + rhs.content,
            color: lhs.color ?? rhs.color,
            font: lhs.font != nil ? lhs.font : rhs.font,
            fontDesign: lhs.fontDesign ?? rhs.fontDesign,
            fontWidth: lhs.fontWidth != nil ? lhs.fontWidth : rhs.fontWidth,
            isItalic: lhs.isItalic != nil ? lhs.isItalic : rhs.isItalic,
            monospacedDigits: lhs.monospacedDigits || rhs.monospacedDigits,
            alignment: lhs.alignment ?? rhs.alignment,
            lineLimit: lhs.lineLimit != nil ? lhs.lineLimit : rhs.lineLimit,
            minimumLineLimit: lhs.minimumLineLimit != nil ? lhs.minimumLineLimit : rhs.minimumLineLimit,
            lineLimitReservesSpace: lhs.lineLimitReservesSpace ?? rhs.lineLimitReservesSpace,
            truncationMode: lhs.truncationMode ?? rhs.truncationMode,
            letterSpacing: lhs.letterSpacing ?? rhs.letterSpacing,
            lineSpacing: lhs.lineSpacing ?? rhs.lineSpacing,
            textScale: lhs.textScale ?? rhs.textScale,
            minimumScaleFactor: lhs.minimumScaleFactor ?? rhs.minimumScaleFactor,
            allowsTightening: lhs.allowsTightening ?? rhs.allowsTightening,
            textCase: lhs.textCase != nil ? lhs.textCase : rhs.textCase,
            baselineOffset: lhs.baselineOffset ?? rhs.baselineOffset,
            underline: lhs.underline != nil ? lhs.underline : rhs.underline,
            underlinePattern: lhs.underline != nil ? lhs.underlinePattern : rhs.underlinePattern,
            underlineColor: lhs.underline != nil ? lhs.underlineColor : rhs.underlineColor,
            strikethrough: lhs.strikethrough != nil ? lhs.strikethrough : rhs.strikethrough,
            strikethroughPattern: lhs.strikethrough != nil ? lhs.strikethroughPattern : rhs.strikethroughPattern,
            strikethroughColor: lhs.strikethrough != nil ? lhs.strikethroughColor : rhs.strikethroughColor,
            timerStyle: lhs.timerStyle ?? rhs.timerStyle,
            lineBreakMode: lhs.lineBreakMode ?? rhs.lineBreakMode,
            hyphenationFrequency: lhs.hyphenationFrequency ?? rhs.hyphenationFrequency,
            allowsDefaultTighteningForTruncation: lhs.allowsDefaultTighteningForTruncation
                ?? rhs.allowsDefaultTighteningForTruncation,
            typesettingLanguage: lhs.typesettingLanguage ?? rhs.typesettingLanguage
        )
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let retainedListTintColor = context.listItemTint?.retainedTint.color
        let resolvedColor = (color ?? retainedListTintColor ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let inheritedFont = context.fontWeight.map { context.font.weight($0) } ?? context.font
        var resolvedFont: Font
        if let font {
            resolvedFont = font ?? .system(size: 2)
        } else {
            resolvedFont = inheritedFont
        }
        if let fontDesign {
            resolvedFont = resolvedFont.withDesign(fontDesign)
        }
        if let fontWidth {
            resolvedFont = resolvedFont.width(fontWidth ?? .standard)
        }
        resolvedFont =
            resolvedFont
            .scaled(for: context.dynamicTypeSize)
            .scaled(by: textScale ?? context.textScale)
        let resolvedAlignment = alignment ?? context.textAlignment
        let resolvedLineLimit: Int?
        if let lineLimit {
            resolvedLineLimit = lineLimit
        } else {
            resolvedLineLimit = context.lineLimit
        }
        let resolvedMinimumLineLimit: Int?
        if let minimumLineLimit {
            resolvedMinimumLineLimit = minimumLineLimit
        } else {
            resolvedMinimumLineLimit = context.minimumLineLimit
        }

        let resolvedContent = content.resolvedTextCase(textCase ?? context.textCase)
        let redactionReasons = context.environmentValues.redactionReasons.retainedReasons
        let isPrivacySensitive = context.environmentValues.isPrivacySensitive
        let resolvedUnderline = underline ?? context.underlineStyle?.isActive ?? false
        let resolvedUnderlinePattern = (underline != nil ? underlinePattern : context.underlineStyle?.pattern ?? .solid)
            .retainedTextDecorationPattern
        let resolvedUnderlineColor = underline != nil ? underlineColor : context.underlineStyle?.color
        let resolvedStrikethrough = strikethrough ?? context.strikethroughStyle?.isActive ?? false
        let resolvedStrikethroughPattern =
            (strikethrough != nil ? strikethroughPattern : context.strikethroughStyle?.pattern ?? .solid)
            .retainedTextDecorationPattern
        let resolvedStrikethroughColor = strikethrough != nil ? strikethroughColor : context.strikethroughStyle?.color

        return Component { _ in
            let node = Controls.label(
                resolvedContent,
                color: resolvedColor,
                scale: resolvedFont.resolvedScale,
                weight: resolvedFont.weight.textWeight,
                isItalic: isItalic ?? (resolvedFont.isItalic || context.isFontItalic),
                monospacedDigits: monospacedDigits || resolvedFont.usesMonospacedDigits || context.usesMonospacedDigits,
                lowercaseSmallCaps: resolvedFont.usesLowercaseSmallCaps,
                uppercaseSmallCaps: resolvedFont.usesUppercaseSmallCaps,
                fontFamily: resolvedFont.resolvedFamily,
                nativeFontSize: resolvedFont.resolvedNativeTextSize,
                fontWidth: resolvedFont.width.retainedTextFontWidth,
                alignment: resolvedAlignment.textAlignment(layoutDirection: context.layoutDirection),
                letterSpacing: letterSpacing ?? context.letterSpacing ?? 1,
                lineSpacing: lineSpacing ?? context.lineSpacing ?? resolvedFont.resolvedLineSpacing,
                lineBreakMode: self.lineBreakMode?.retainedTextLineBreakMode
                    ?? resolvedLineBreakMode(
                        lineLimit: resolvedLineLimit,
                        truncationMode: truncationMode ?? context.truncationMode
                    ),
                maximumNumberOfLines: resolvedLineLimit,
                minimumNumberOfLines: resolvedMinimumLineLimit,
                minimumScaleFactor: minimumScaleFactor ?? context.minimumScaleFactor,
                reservesLineLimitSpace: (lineLimitReservesSpace ?? context.lineLimitReservesSpace)
                    && resolvedLineLimit != nil,
                underline: resolvedUnderline,
                underlinePattern: resolvedUnderlinePattern,
                underlineColor: resolvedUnderlineColor,
                strikethrough: resolvedStrikethrough,
                strikethroughPattern: resolvedStrikethroughPattern,
                strikethroughColor: resolvedStrikethroughColor,
                enableKerning: allowsTightening ?? context.allowsTightening
            )
            node.redactionReasons = redactionReasons
            node.isPrivacySensitive = isPrivacySensitive
            node.textSelectability = context.environmentValues.textSelectability?.retainedSelectability
            node.textSelectionAffinity = context.textSelectionAffinity.retainedAffinity
            node.writingToolsBehavior = context.writingToolsBehavior?.retainedBehavior
            let resolvedBaselineOffset = baselineOffset ?? context.baselineOffset
            if let resolvedBaselineOffset, resolvedBaselineOffset != 0 {
                node.transform = node.transform.concatenating(.translation(x: 0, y: -Double(resolvedBaselineOffset)))
            }
            return node
        }
    }

    public func foregroundColor(_ color: Color) -> Text {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundColor(_ color: Color?) -> Text {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundStyle(_ color: Color) -> Text {
        foregroundColor(color)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color) -> Text {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Text {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ style: ForegroundStyle) -> Text {
        foregroundColor(resolvedFill(from: style).color)
    }

    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        foregroundStyle(style.retainedForegroundStyle)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle) -> Text {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle<Primary: ShapeStyle, Secondary: ShapeStyle>(
        _ primary: Primary,
        _ secondary: Secondary
    ) -> Text {
        _ = secondary
        return foregroundStyle(primary.retainedForegroundStyle)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle, _ tertiary: ForegroundStyle)
        -> Text
    {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle<Primary: ShapeStyle, Secondary: ShapeStyle, Tertiary: ShapeStyle>(
        _ primary: Primary,
        _ secondary: Secondary,
        _ tertiary: Tertiary
    ) -> Text {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary.retainedForegroundStyle)
    }

    public func foregroundStyle(_ gradient: LinearGradient) -> Text {
        foregroundStyle(.linearGradient(gradient))
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient) -> Text {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient, _ tertiary: LinearGradient)
        -> Text
    {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func font(_ font: Font) -> Text {
        var copy = self
        copy.font = .some(font)
        return copy
    }

    public func font(_ font: Font?) -> Text {
        var copy = self
        copy.font = .some(font)
        return copy
    }

    public func monospaced() -> Text {
        monospaced(true)
    }

    public func monospaced(_ isActive: Bool) -> Text {
        var copy = self
        copy.fontDesign = isActive ? .monospaced : .default
        return copy
    }

    public func fontDesign(_ design: Font.Design?) -> Text {
        var copy = self
        copy.fontDesign = design
        return copy
    }

    public func fontWidth(_ width: Font.Width?) -> Text {
        var copy = self
        copy.fontWidth = .some(width)
        return copy
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var copy = self
        guard let weight else {
            if let font = copy.font, let resolvedFont = font {
                copy.font = .some(resolvedFont.weight(.regular))
            }
            return copy
        }

        let baseFont: Font
        if let font = copy.font {
            baseFont = font ?? .system(size: 2)
        } else {
            baseFont = .system(size: 2)
        }
        copy.font = .some(baseFont.weight(weight))
        return copy
    }

    public func bold() -> Text {
        bold(true)
    }

    public func bold(_ isActive: Bool) -> Text {
        fontWeight(isActive ? .bold : .regular)
    }

    public func italic() -> Text {
        italic(true)
    }

    public func italic(_ isActive: Bool) -> Text {
        var copy = self
        copy.isItalic = isActive
        return copy
    }

    public func monospacedDigit() -> Text {
        var copy = self
        copy.monospacedDigits = true
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func lineLimit(_ lineLimit: Int?) -> Text {
        var copy = self
        copy.lineLimit = .some(lineLimit)
        copy.minimumLineLimit = .some(nil)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func lineLimit(_ lineLimit: Int, reservesSpace: Bool) -> Text {
        var copy = self
        copy.lineLimit = .some(lineLimit)
        copy.minimumLineLimit = .some(reservesSpace ? lineLimit : nil)
        copy.lineLimitReservesSpace = reservesSpace
        return copy
    }

    public func lineLimit(_ limit: PartialRangeThrough<Int>) -> Text {
        var copy = self
        copy.lineLimit = .some(limit.upperBound)
        copy.minimumLineLimit = .some(nil)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> Text {
        var copy = self
        copy.lineLimit = .some(nil)
        copy.minimumLineLimit = .some(limit.lowerBound)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func lineLimit(_ limits: ClosedRange<Int>) -> Text {
        var copy = self
        copy.lineLimit = .some(limits.upperBound)
        copy.minimumLineLimit = .some(limits.lowerBound)
        copy.lineLimitReservesSpace = false
        return copy
    }

    public func truncationMode(_ mode: TruncationMode) -> Text {
        var copy = self
        copy.truncationMode = mode
        return copy
    }

    public func lineSpacing(_ lineSpacing: Double) -> Text {
        var copy = self
        copy.lineSpacing = lineSpacing
        return copy
    }

    public func textScale(_ scale: Scale, isEnabled: Bool = true) -> Text {
        guard isEnabled else {
            return self
        }

        var copy = self
        copy.textScale = scale
        return copy
    }

    public func minimumScaleFactor(_ factor: CGFloat) -> Text {
        var copy = self
        copy.minimumScaleFactor = EnvironmentValues.clampedMinimumScaleFactor(factor)
        return copy
    }

    public func kerning(_ kerning: Double) -> Text {
        var copy = self
        copy.letterSpacing = kerning
        return copy
    }

    public func tracking(_ tracking: Double) -> Text {
        kerning(tracking)
    }

    public func allowsTightening(_ flag: Bool) -> Text {
        var copy = self
        copy.allowsTightening = flag
        return copy
    }

    public func textCase(_ textCase: Case?) -> Text {
        var copy = self
        copy.textCase = .some(textCase)
        return copy
    }

    public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        var copy = self
        copy.baselineOffset = baselineOffset
        return copy
    }

    public func underline(
        _ active: Bool = true,
        pattern: LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> Text {
        var copy = self
        copy.underline = active
        copy.underlinePattern = active ? pattern : .solid
        copy.underlineColor = active ? color : nil
        return copy
    }

    public func underline(_ style: LineStyle) -> Text {
        underline(true, pattern: style.pattern, color: style.color)
    }

    public func strikethrough(
        _ active: Bool = true,
        pattern: LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> Text {
        var copy = self
        copy.strikethrough = active
        copy.strikethroughPattern = active ? pattern : .solid
        copy.strikethroughColor = active ? color : nil
        return copy
    }

    public func strikethrough(_ style: LineStyle) -> Text {
        strikethrough(true, pattern: style.pattern, color: style.color)
    }

    public func timerStyle(_ style: Text.TimerStyle) -> Text {
        var copy = self
        copy.timerStyle = style
        return copy
    }

    public func lineBreakMode(_ lineBreakMode: LineBreakMode?) -> Text {
        var copy = self
        copy.lineBreakMode = lineBreakMode
        return copy
    }

    public func hyphenationFrequency(_ frequency: HyphenationFrequency?) -> Text {
        var copy = self
        copy.hyphenationFrequency = frequency
        return copy
    }

    public func allowsDefaultTighteningForTruncation(_ allows: Bool?) -> Text {
        var copy = self
        copy.allowsDefaultTighteningForTruncation = allows
        return copy
    }

    public func typesettingLanguage(_ language: Locale.Language?) -> Text {
        var copy = self
        copy.typesettingLanguage = language?.minimalIdentifier
        return copy
    }

    public func typesettingLanguage(_ language: String?) -> Text {
        var copy = self
        copy.typesettingLanguage = language
        return copy
    }

    private func resolvedLineBreakMode(lineLimit: Int?, truncationMode: TruncationMode?) -> TextLineBreakMode {
        guard let lineLimit else {
            return .wrap
        }
        guard lineLimit == 1 || truncationMode != nil else {
            return .wrap
        }

        switch truncationMode {
        case .head:
            return .truncateHead
        case .tail, nil:
            return .truncateTail
        case .middle:
            return .truncateMiddle
        }
    }
}
extension String {
    fileprivate func resolvedTextCase(_ textCase: Text.Case?) -> String {
        switch textCase {
        case .uppercase:
            return uppercased()
        case .lowercase:
            return lowercased()
        case nil:
            return self
        }
    }
}
extension Text.LineStyle.Pattern {
    fileprivate var retainedTextDecorationPattern: TextDecorationPattern {
        switch self {
        case .solid:
            return .solid
        case .dot:
            return .dot
        case .dash:
            return .dash
        case .dashDot:
            return .dashDot
        case .dashDotDot:
            return .dashDotDot
        }
    }
}
@MainActor
public struct Image: View {
    public typealias Body = Never

    public enum Scale: Sendable, Equatable {
        case small
        case medium
        case large
    }

    public enum ResizingMode: Sendable, Equatable {
        case tile
        case stretch
    }

    public enum TemplateRenderingMode: Sendable, Equatable {
        case template
        case original
    }

    public enum RenderingMode: Sendable, Equatable {
        case template
        case original
    }

    public enum Interpolation: Sendable, Equatable {
        case none
        case low
        case medium
        case high
    }

    private enum Storage {
        case systemName(String)
        case bitmap(BitmapSurface?)
    }

    private let storage: Storage
    private var color: Color?
    private var font: Font
    private var alignment: TextAlignment
    private var isResizable: Bool
    private var resizingMode: ResizingMode
    private var capInsets: EdgeInsets
    private var aspectRatioValue: Double?
    private var contentMode: ContentMode?
    private var renderingMode: TemplateRenderingMode?
    private var interpolation: Interpolation
    private var antialiased: Bool?
    private var accessibilityLabel: String?
    private var isAccessibilityHidden: Bool
    private var symbolVariableValue: Double?

    var imageAccessibilityLabel: String? {
        accessibilityLabel
    }

    public init(systemName: String) {
        self.init(storage: .systemName(systemName))
    }

    public init(systemName: String, label: Text) {
        self.init(systemName: systemName)
        self.accessibilityLabel = label.plainContent
    }

    public init(systemName: String, variableValue: Double?) {
        self.init(systemName: systemName)
        self.symbolVariableValue = variableValue
    }

    public init(systemName: String, variableValue: Double?, label: Text) {
        self.init(systemName: systemName, variableValue: variableValue)
        self.accessibilityLabel = label.plainContent
    }

    public init(_ name: String, bundle: Bundle? = nil) {
        self.init(storage: .bitmap(Self.loadResource(named: name, bundle: bundle)))
    }

    public init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.init(name, bundle: bundle)
        self.symbolVariableValue = variableValue
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self.init(name, bundle: bundle)
        self.accessibilityLabel = label.plainContent
    }

    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil, label: Text) {
        self.init(name, variableValue: variableValue, bundle: bundle)
        self.accessibilityLabel = label.plainContent
    }

    public init(decorative name: String, bundle: Bundle? = nil) {
        self.init(name, bundle: bundle)
        self.isAccessibilityHidden = true
    }

    public init(decorative name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.init(name, variableValue: variableValue, bundle: bundle)
        self.isAccessibilityHidden = true
    }

    public init(bitmap: BitmapSurface) {
        self.init(storage: .bitmap(bitmap))
    }

    public init(uiImage: BitmapSurface) {
        self.init(bitmap: uiImage)
    }

    public init(nsImage: BitmapSurface) {
        self.init(bitmap: nsImage)
    }

    public init(cgImage: BitmapSurface) {
        self.init(bitmap: cgImage)
    }

    private init(storage: Storage) {
        self.storage = storage
        self.color = nil
        self.font = .system(size: 1.9)
        self.alignment = .center
        self.isResizable = false
        self.resizingMode = .stretch
        self.capInsets = .zero
        self.aspectRatioValue = nil
        self.contentMode = nil
        self.renderingMode = nil
        self.interpolation = .medium
        self.antialiased = nil
        self.accessibilityLabel = nil
        self.isAccessibilityHidden = false
        self.symbolVariableValue = nil
    }

    public var body: Never {
        fatalError("Image has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        switch storage {
        case .systemName(let systemName):
            let symbolVariants = context.symbolVariants
            let symbol = resolvedSymbolIcon(for: systemName, variants: symbolVariants)
            let resolvedColor = (color ?? context.foregroundColor)
                .resolvedForVisualEnvironment(
                    contrast: context.colorSchemeContrast,
                    backgroundProminence: context.backgroundProminence
                )
            let renderedColor = retainedSymbolColor(
                base: resolvedColor,
                mode: context.symbolRenderingMode,
                tint: context.tint
            )
            let imageScale = context.imageScale.resolvedMultiplier
            let resolvedScale = font.resolvedScale * imageScale
            let baseSize = Size(
                width: font.resolvedNativeTextSize * imageScale, height: font.resolvedNativeTextSize * imageScale)
            let preferredSize = resolvedPreferredSize(baseSize: baseSize, requiresExplicitOptIn: true)
            return Component { _ in
                let node = Controls.icon(
                    symbol,
                    preferredSize: preferredSize,
                    color: renderedColor,
                    scale: resolvedScale,
                    alignment: alignment.textAlignment(layoutDirection: context.layoutDirection)
                )
                if symbolVariants.contains(.fill) {
                    node.textStyle.weight = .bold
                }
                applyImageMetadata(to: node, context: context)
                return retainedSymbolVariantNode(
                    iconNode: node,
                    iconSize: preferredSize ?? baseSize,
                    variants: symbolVariants,
                    tint: renderedColor,
                    context: context
                )
            }
        case .bitmap(let bitmap):
            let preferredSize = resolvedPreferredSize(baseSize: bitmap?.logicalSize, requiresExplicitOptIn: false)
            return Component { _ in
                guard let bitmap else {
                    let node = Controls.panel(preferredSize: preferredSize, isHitTestVisible: false)
                    applyImageMetadata(to: node, context: context)
                    return node
                }

                let renderedBitmap = resolvedBitmapSurface(bitmap, context: context)
                let node = Controls.image(renderedBitmap, preferredSize: preferredSize)
                applyImageMetadata(to: node, context: context)
                return node
            }
        }
    }

    public func foregroundColor(_ color: Color) -> Image {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundColor(_ color: Color?) -> Image {
        var copy = self
        copy.color = color
        return copy
    }

    public func font(_ font: Font) -> Image {
        var copy = self
        copy.font = font
        return copy
    }

    public func multilineTextAlignment(_ alignment: TextAlignment) -> Image {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func resizable(capInsets: EdgeInsets = .zero, resizingMode: ResizingMode = .stretch) -> Image {
        var copy = self
        copy.isResizable = true
        copy.resizingMode = resizingMode
        copy.capInsets = capInsets
        return copy
    }

    public func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> Image {
        var copy = self
        copy.aspectRatioValue = aspectRatio
        copy.contentMode = contentMode
        return copy
    }

    public func scaledToFit() -> Image {
        aspectRatio(contentMode: .fit)
    }

    public func scaledToFill() -> Image {
        aspectRatio(contentMode: .fill)
    }

    public func renderingMode(_ renderingMode: TemplateRenderingMode?) -> Image {
        var copy = self
        copy.renderingMode = renderingMode
        return copy
    }

    public func interpolation(_ interpolation: Interpolation) -> Image {
        var copy = self
        copy.interpolation = interpolation
        return copy
    }

    public func antialiased(_ isAntialiased: Bool) -> Image {
        var copy = self
        copy.antialiased = isAntialiased
        return copy
    }

    private func resolvedPreferredSize(baseSize: Size?, requiresExplicitOptIn: Bool) -> Size? {
        guard let baseSize else {
            return nil
        }

        guard isResizable || contentMode != nil || !requiresExplicitOptIn else {
            return nil
        }

        let nativeRatio = baseSize.width > 0 && baseSize.height > 0 ? baseSize.width / baseSize.height : 1
        let requestedRatio = aspectRatioValue ?? nativeRatio
        let ratio = requestedRatio.isFinite && requestedRatio > 0 ? requestedRatio : 1
        guard let contentMode else {
            return baseSize
        }

        let baseRatio = nativeRatio.isFinite && nativeRatio > 0 ? nativeRatio : 1
        switch contentMode {
        case .fit:
            return ratio >= baseRatio
                ? Size(width: baseSize.width, height: baseSize.width / ratio)
                : Size(width: baseSize.height * ratio, height: baseSize.height)
        case .fill:
            return ratio >= baseRatio
                ? Size(width: baseSize.height * ratio, height: baseSize.height)
                : Size(width: baseSize.width, height: baseSize.width / ratio)
        }
    }

    private static func loadResource(named name: String, bundle: Bundle?) -> BitmapSurface? {
        guard let path = resolveResourcePath(named: name, bundle: bundle) else {
            return nil
        }

        return ImageLoader.load(contentsOfFile: path)
    }

    private static func resolveResourcePath(named name: String, bundle: Bundle?) -> String? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: name) {
            return name
        }

        let resourceBundle = bundle ?? .main
        let fileURL = URL(fileURLWithPath: name)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let extensionName = fileURL.pathExtension
        if !extensionName.isEmpty, let url = resourceBundle.url(forResource: baseName, withExtension: extensionName) {
            return url.path
        }

        if let url = resourceBundle.url(forResource: name, withExtension: nil) {
            return url.path
        }

        for extensionName in ["png", "jpg", "jpeg", "bmp"] {
            if let url = resourceBundle.url(forResource: name, withExtension: extensionName) {
                return url.path
            }
        }

        return nil
    }

    private func applyAccessibility(to node: ViewNode) {
        node.accessibilityLabel = accessibilityLabel
        node.isAccessibilityHidden = isAccessibilityHidden
    }

    private func resolvedBitmapSurface(_ bitmap: BitmapSurface, context: ViewBuildContext) -> BitmapSurface {
        guard renderingMode == .template else {
            return bitmap
        }

        let tint = (color ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let tintChannels = tint.rgba
        let tintRed = templateByte(tintChannels.0)
        let tintGreen = templateByte(tintChannels.1)
        let tintBlue = templateByte(tintChannels.2)
        let tintAlpha = max(0, min(1, tintChannels.3))
        let width = max(0, Int(bitmap.width))
        let height = max(0, Int(bitmap.height))
        let bytesPerRow = max(width * 4, Int(bitmap.bytesPerRow))
        var pixels = bitmap.pixels

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                guard offset + 3 < pixels.count else {
                    continue
                }

                let sourceAlpha = Float(pixels[offset + 3]) / 255
                pixels[offset] = tintBlue
                pixels[offset + 1] = tintGreen
                pixels[offset + 2] = tintRed
                pixels[offset + 3] = templateByte(sourceAlpha * tintAlpha)
            }
        }

        return BitmapSurface(
            width: bitmap.width, height: bitmap.height, bytesPerRow: bitmap.bytesPerRow, pixels: pixels)
    }

    private func templateByte(_ value: Float) -> UInt8 {
        UInt8((max(0, min(1, value)) * 255).rounded())
    }

    private func retainedSymbolColor(
        base: Color,
        mode: SymbolRenderingMode?,
        tint: Color
    ) -> Color {
        guard let mode else {
            return base
        }

        switch mode.kind {
        case .monochrome:
            return base
        case .hierarchical:
            return base.opacity(0.72)
        case .palette:
            return tint
        case .multicolor:
            return Color(red: 0.30, green: 0.74, blue: 0.92, alpha: 1.0)
        }
    }

    private func retainedSymbolVariantNode(
        iconNode: ViewNode,
        iconSize: Size,
        variants: SymbolVariants,
        tint: Color,
        context: ViewBuildContext
    ) -> ViewNode {
        guard
            variants.contains(.circle)
                || variants.contains(.square)
                || variants.contains(.rectangle)
                || variants.contains(.slash)
        else {
            return iconNode
        }

        let hasShape = variants.contains(.circle) || variants.contains(.square) || variants.contains(.rectangle)
        let isRectangle = variants.contains(.rectangle)
        let widthMultiplier = isRectangle ? 1.65 : 1.35
        let boxSize = Size(
            width: max(iconSize.width, iconSize.width * widthMultiplier),
            height: max(iconSize.height, iconSize.height * 1.35)
        )
        let shapeCornerRadius: Double
        if variants.contains(.circle) {
            shapeCornerRadius = min(boxSize.width, boxSize.height) * 0.5
        } else if variants.contains(.square) {
            shapeCornerRadius = max(2, min(boxSize.width, boxSize.height) * 0.16)
        } else {
            shapeCornerRadius = max(2, min(boxSize.width, boxSize.height) * 0.12)
        }

        iconNode.frame = Rect(
            x: (boxSize.width - iconSize.width) * 0.5,
            y: (boxSize.height - iconSize.height) * 0.5,
            width: iconSize.width,
            height: iconSize.height
        )
        iconNode.preferredSize = iconSize

        var children = [iconNode]
        if variants.contains(.slash) {
            let slashThickness = max(2, min(boxSize.width, boxSize.height) * 0.10)
            let slashNode = Controls.panel(
                frame: Rect(
                    x: boxSize.width * 0.18,
                    y: (boxSize.height - slashThickness) * 0.5,
                    width: boxSize.width * 0.64,
                    height: slashThickness
                ),
                backgroundColor: tint,
                cornerRadius: slashThickness * 0.5,
                isHitTestVisible: false
            )
            slashNode.transform = Transform2D(rotation: -0.78)
            slashNode.nodeTag = "symbol-variant-slash"
            children.append(slashNode)
        }

        let variantNode = Controls.panel(
            preferredSize: boxSize,
            backgroundColor: hasShape && variants.contains(.fill) ? tint.opacity(0.18) : nil,
            borderColor: hasShape ? tint.opacity(variants.contains(.fill) ? 0.34 : 0.68) : .clear,
            borderWidth: hasShape ? 1 : 0,
            cornerRadius: hasShape ? shapeCornerRadius : 0,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: children
        )
        variantNode.nodeTag = "symbol-variant"
        applyImageMetadata(to: variantNode, context: context)
        return variantNode
    }

    private func applyImageMetadata(to node: ViewNode, context: ViewBuildContext) {
        applyAccessibility(to: node)
        node.symbolVariableValue = symbolVariableValue ?? context.symbolVariableValue
        node.symbolRenderingMode = context.symbolRenderingMode?.retainedSymbolRenderingMode
        node.symbolVariants = context.symbolVariants.retainedSymbolVariants
        node.imageResizingMode = isResizable ? resizingMode.retainedImageResizingMode : nil
        node.imageCapInsets = isResizable ? capInsets : nil
        node.imageRenderingMode = renderingMode?.retainedImageRenderingMode
        node.imageInterpolation = interpolation.retainedImageInterpolation
        node.imageAntialiased = antialiased
    }
}
extension Image.ResizingMode {
    var retainedImageResizingMode: RetainedImageResizingMode {
        switch self {
        case .stretch:
            return .stretch
        case .tile:
            return .tile
        }
    }
}
extension Image.TemplateRenderingMode {
    var retainedImageRenderingMode: RetainedImageRenderingMode {
        switch self {
        case .original:
            return .original
        case .template:
            return .template
        }
    }
}
extension Image.Interpolation {
    var retainedImageInterpolation: RetainedImageInterpolation {
        switch self {
        case .none:
            return .none
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }
}
extension BitmapSurface {
    fileprivate var logicalSize: Size {
        Size(width: Double(width), height: Double(height))
    }
}
public enum AsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)

    public var image: Image? {
        switch self {
        case .success(let image):
            return image
        default:
            return nil
        }
    }

    public var error: Error? {
        switch self {
        case .failure(let error):
            return error
        default:
            return nil
        }
    }
}
public struct AsyncImageError: Error {
    public static let decodingFailed = AsyncImageError()
    private init() {}
}
@MainActor
public final class AsyncImageLoader: ObservableObject {
    @Published public var phase: AsyncImagePhase = .empty
    private var isLoading = false

    public func load(url: URL?, scale: Double = 1) {
        guard let url = url else {
            phase = .empty
            isLoading = false
            return
        }
        guard !isLoading else { return }
        isLoading = true
        phase = .empty
        Task.detached { [weak self] in
            do {
                let data = try Data(contentsOf: url)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    defer { self.isLoading = false }
                    do {
                        let tempDir = FileManager.default.temporaryDirectory
                        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".tmp")
                        try data.write(to: tempFile)
                        if let bitmap = ImageLoader.load(contentsOfFile: tempFile.path) {
                            let image = Image(bitmap: bitmap)
                            self.phase = .success(image)
                        } else {
                            self.phase = .failure(AsyncImageError.decodingFailed)
                        }
                        try? FileManager.default.removeItem(at: tempFile)
                    } catch {
                        self.phase = .failure(error)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.phase = .failure(error)
                    self?.isLoading = false
                }
            }
        }
    }
}
@MainActor
private final class AsyncImageLoaderCache {
    static let shared = AsyncImageLoaderCache()
    private var loaders: [URL: AsyncImageLoader] = [:]

    func loader(for url: URL) -> AsyncImageLoader {
        if let loader = loaders[url] {
            return loader
        }
        let loader = AsyncImageLoader()
        loaders[url] = loader
        return loader
    }
}
@MainActor
public struct AsyncImage: View {
    public typealias Body = Never

    private let url: URL?
    private let scale: Double
    private let content: (AsyncImagePhase) -> AnyView

    public init(url: URL?, scale: Double = 1) {
        self.url = url
        self.scale = scale
        self.content = { phase in
            switch phase {
            case .empty:
                return AnyView(EmptyView())
            case .success(let image):
                return AnyView(image)
            case .failure:
                return AnyView(EmptyView())
            }
        }
    }

    public init<Content: View, Placeholder: View>(
        url: URL?,
        scale: Double = 1,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.content = { phase in
            switch phase {
            case .empty, .failure:
                return AnyView(Group { placeholder() })
            case .success(let image):
                return AnyView(Group { content(image) })
            }
        }
    }

    public init<Content: View>(
        url: URL?,
        scale: Double = 1,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.content = { phase in AnyView(Group { content(phase) }) }
    }

    public var body: Never {
        fatalError("AsyncImage has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let loader: AsyncImageLoader
        if let url = url {
            loader = AsyncImageLoaderCache.shared.loader(for: url)
            loader.load(url: url, scale: scale)
        } else {
            loader = AsyncImageLoader()
        }
        context.observe(loader)
        return content(loader.phase).makeComponent(context: context)
    }
}
extension Text {
    var plainContent: String {
        content
    }
}
extension Image.Scale {
    fileprivate var resolvedMultiplier: Double {
        switch self {
        case .small:
            return 0.82
        case .medium:
            return 1.0
        case .large:
            return 1.25
        }
    }
}
@MainActor
public struct LabeledContent: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public init<Title: StringProtocol, Value: StringProtocol>(_ title: Title, value: Value) {
        self.init(String(title)) {
            Text(String(value))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }

    public init<Value: StringProtocol>(_ titleKey: LocalizedStringKey, value: Value) {
        self.init(titleKey.resolvedString, value: String(value))
    }

    public init<F: FormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: F.FormatInput,
        format: F
    ) where F.FormatOutput == String {
        self.init(titleKey.resolvedString, value: format.format(value))
    }

    public init<S: StringProtocol, F: FormatStyle>(
        _ title: S,
        value: F.FormatInput,
        format: F
    ) where F.FormatOutput == String {
        self.init(String(title), value: format.format(value))
    }

    public var body: Never {
        fatalError("LabeledContent has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context:
                context
                .withForegroundColor(.secondary)
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let contentComponent = composeComponent(
            from: content,
            context:
                context
                .withTextAlignment(.trailing)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            let contentNode = contentComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, contentNode]
            )
        }
    }
}
@MainActor
public struct ToolbarItem: View, TaggedViewMetadata {
    public typealias Body = Never

    public let id: String?
    public let placement: ToolbarItemPlacement
    public let showsByDefault: Bool
    private let content: [AnyView]

    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = nil
        self.placement = placement
        self.showsByDefault = true
        self.content = content()
    }

    public init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        showsByDefault: Bool = true,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = id
        self.placement = placement
        self.showsByDefault = showsByDefault
        self.content = content()
    }

    public var body: Never {
        fatalError("ToolbarItem has no body")
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        placement
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let item = composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
            isHitTestVisible: false
        )
        guard let id else {
            return item
        }

        return Component { runtime in
            let node = item.makeNode(runtime: runtime)
            node.nodeTag = id
            return node
        }
    }
}
@MainActor
public struct ToolbarItemGroup: View, TaggedViewMetadata {
    public typealias Body = Never

    public let id: String?
    public let placement: ToolbarItemPlacement
    public let showsByDefault: Bool
    private let content: [AnyView]

    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = nil
        self.placement = placement
        self.showsByDefault = true
        self.content = content()
    }

    public init(
        id: String,
        placement: ToolbarItemPlacement = .automatic,
        showsByDefault: Bool = true,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.id = id
        self.placement = placement
        self.showsByDefault = showsByDefault
        self.content = content()
    }

    public var body: Never {
        fatalError("ToolbarItemGroup has no body")
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        placement
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let group = composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
            isHitTestVisible: false
        )
        guard let id else {
            return group
        }

        return Component { runtime in
            let node = group.makeNode(runtime: runtime)
            node.nodeTag = id
            return node
        }
    }
}
@MainActor
public struct ToolbarTitleMenu: View {
    public typealias Body = Never

    private let content: [AnyView]
    private let label: [AnyView]?

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
        self.label = nil
    }

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.content = content()
        self.label = label()
    }

    public var body: Never {
        fatalError("ToolbarTitleMenu has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = label
        return composeComponent(
            from: content,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 8, alignment: .leading)),
            isHitTestVisible: false
        )
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
@preconcurrency public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    var body: Self.Body { get }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
extension Never: @preconcurrency ToolbarContent {}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public protocol CustomToolbarContent: ToolbarContent {
    associatedtype Content: ToolbarContent
    func makeContent(in context: ToolbarContentContext) -> Content
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct ToolbarContentContext: Sendable {
    public init() {}
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
@resultBuilder
public struct ToolbarContentBuilder {
    public static func buildBlock(_ content: any ToolbarContent) -> any ToolbarContent {
        content
    }

    public static func buildOptional(_ content: (any ToolbarContent)?) -> any ToolbarContent {
        content ?? EmptyToolbarContent()
    }

    public static func buildEither(first content: any ToolbarContent) -> any ToolbarContent {
        content
    }

    public static func buildEither(second content: any ToolbarContent) -> any ToolbarContent {
        content
    }

    public static func buildArray(_ components: [any ToolbarContent]) -> any ToolbarContent {
        EmptyToolbarContent()
    }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct EmptyToolbarContent: ToolbarContent {
    public typealias Body = Never
    public var body: Never { fatalError("EmptyToolbarContent has no body") }
}
@available(macOS 11.0, iOS 14.0, watchOS 9.0, tvOS 14.0, *)
public struct AnyToolbarContent: ToolbarContent {
    public typealias Body = Never
    public var body: Never { fatalError("AnyToolbarContent has no body") }

    private let content: any ToolbarContent

    public init(_ content: any ToolbarContent) {
        self.content = content
    }
}
@MainActor
public struct Label: View {
    public typealias Body = Never

    private let title: [AnyView]
    private let icon: [AnyView]
    private var color: Color?
    private var font: Font
    private var spacing: Double

    public init(_ title: String, image name: String) {
        self.title = [
            AnyView(
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.icon = [
            AnyView(Image(name))
        ]
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init<S: StringProtocol>(_ title: S, image name: String) {
        self.init(String(title), image: name)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.init(titleKey.resolvedString, image: name)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource) {
        self.title = [
            AnyView(
                Text(String(title))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.icon = [
            AnyView(Image(resource))
        ]
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource) {
        self.init(titleKey.resolvedString, image: resource)
    }

    public init(_ title: String, systemImage: String) {
        self.title = [
            AnyView(
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.icon = [
            AnyView(Image(systemName: systemImage))
        ]
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String) {
        self.init(String(title), systemImage: systemImage)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String) {
        self.init(titleKey.resolvedString, systemImage: systemImage)
    }

    public init(@ViewBuilder title: () -> [AnyView], @ViewBuilder icon: () -> [AnyView]) {
        self.title = title()
        self.icon = icon()
        self.color = nil
        self.font = .system(size: 1.6, weight: .semibold)
        self.spacing = 10
    }

    public var body: Never {
        fatalError("Label has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let resolvedColor = (color ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let labelContext =
            context
            .withForegroundColor(resolvedColor)
            .withFont(font)
            .withTextAlignment(.leading)
            .withLineLimit(1)
        switch context.labelStyle.kind {
        case .automatic, .titleAndIcon:
            return HStack(spacing: spacing) {
                icon
                title
            }
            .makeComponent(context: labelContext)
        case .iconOnly:
            return composeComponent(from: icon, context: labelContext)
        case .titleOnly:
            return composeComponent(from: title, context: labelContext)
        }
    }

    public func foregroundColor(_ color: Color) -> Label {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundColor(_ color: Color?) -> Label {
        var copy = self
        copy.color = color
        return copy
    }

    public func foregroundStyle(_ color: Color) -> Label {
        foregroundColor(color)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color) -> Label {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Label {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ style: ForegroundStyle) -> Label {
        foregroundColor(resolvedFill(from: style).color)
    }

    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Label {
        foregroundStyle(style.retainedForegroundStyle)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle) -> Label {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle<Primary: ShapeStyle, Secondary: ShapeStyle>(
        _ primary: Primary,
        _ secondary: Secondary
    ) -> Label {
        _ = secondary
        return foregroundStyle(primary.retainedForegroundStyle)
    }

    public func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle, _ tertiary: ForegroundStyle)
        -> Label
    {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func foregroundStyle<Primary: ShapeStyle, Secondary: ShapeStyle, Tertiary: ShapeStyle>(
        _ primary: Primary,
        _ secondary: Secondary,
        _ tertiary: Tertiary
    ) -> Label {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary.retainedForegroundStyle)
    }

    public func foregroundStyle(_ gradient: LinearGradient) -> Label {
        foregroundStyle(.linearGradient(gradient))
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient) -> Label {
        _ = secondary
        return foregroundStyle(primary)
    }

    public func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient, _ tertiary: LinearGradient)
        -> Label
    {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    public func font(_ font: Font) -> Label {
        var copy = self
        copy.font = font
        return copy
    }
}
@MainActor
public struct ContentUnavailableView: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let description: [AnyView]
    private let actions: [AnyView]

    public init(
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder description: () -> [AnyView] = { [] },
        @ViewBuilder actions: () -> [AnyView] = { [] }
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public init(_ title: String, image name: String, description: Text? = nil) {
        self.label = [
            AnyView(
                Label(title, image: name)
                    .font(.headline)
            )
        ]
        self.description = description.map { [AnyView($0)] } ?? []
        self.actions = []
    }

    public init<S: StringProtocol>(_ title: S, image name: String, description: Text? = nil) {
        self.init(String(title), image: name, description: description)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, description: Text? = nil) {
        self.init(titleKey.resolvedString, image: name, description: description)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, description: Text? = nil) {
        self.label = [
            AnyView(
                Label(title, image: resource)
                    .font(.headline)
            )
        ]
        self.description = description.map { [AnyView($0)] } ?? []
        self.actions = []
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, description: Text? = nil) {
        self.init(titleKey.resolvedString, image: resource, description: description)
    }

    public init(_ title: String, systemImage: String, description: Text? = nil) {
        self.label = [
            AnyView(
                Label(title, systemImage: systemImage)
                    .font(.headline)
            )
        ]
        self.description = description.map { [AnyView($0)] } ?? []
        self.actions = []
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, description: Text? = nil) {
        self.init(String(title), systemImage: systemImage, description: description)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.init(titleKey.resolvedString, systemImage: systemImage, description: description)
    }

    public static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
    }

    public static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No results for \(text)")
        )
    }

    public var body: Never {
        fatalError("ContentUnavailableView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context:
                context
                .withTextAlignment(.center)
                .withLineLimit(2),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false
        )
        let descriptionComponent = composeComponent(
            from: description,
            context:
                context
                .withForegroundColor(.secondary)
                .withFont(.caption)
                .withTextAlignment(.center),
            fallbackLayout: .stack(.vertical(spacing: 4, alignment: .center)),
            isHitTestVisible: false
        )
        let actionsComponent = composeComponent(
            from: actions,
            context: context.withButtonStyle(.bordered),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            var children = [labelComponent.makeNode(runtime: runtime)]
            if !description.isEmpty {
                children.append(descriptionComponent.makeNode(runtime: runtime))
            }
            if !actions.isEmpty {
                children.append(actionsComponent.makeNode(runtime: runtime))
            }

            return Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: 10,
                    padding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
                    alignment: .center,
                    mainAlignment: .center
                ),
                isHitTestVisible: false,
                children: children
            )
        }
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
public struct ContentUnavailableConfiguration: Sendable {
    public var title: String?
    public var image: Image?
    public var description: String?
    public var actions: ContentUnavailableActions?

    public init(
        title: String? = nil,
        image: Image? = nil,
        description: String? = nil,
        actions: ContentUnavailableActions? = nil
    ) {
        self.title = title
        self.image = image
        self.description = description
        self.actions = actions
    }

    public static let empty = ContentUnavailableConfiguration()
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
public struct ContentUnavailableActions: Sendable {
    public var primary: ContentUnavailableButton?
    public var secondary: [ContentUnavailableButton]

    public init(
        primary: ContentUnavailableButton? = nil,
        secondary: [ContentUnavailableButton] = []
    ) {
        self.primary = primary
        self.secondary = secondary
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
public struct ContentUnavailableButton: Sendable {
    public var label: String
    public var action: (@MainActor () -> Void)?

    public init(
        _ label: String,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.label = label
        self.action = action
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
public struct ContentUnavailableDescription: View {
    public typealias Body = Never

    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Never {
        fatalError("ContentUnavailableDescription has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Text(text).makeComponent(context: context)
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
public struct ContentUnavailableImage: View {
    public typealias Body = Never

    private let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var body: Never {
        fatalError("ContentUnavailableImage has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Image(name).makeComponent(context: context)
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
@MainActor
public struct ContentUnavailableTitle: View {
    public typealias Body = Never

    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: Never {
        fatalError("ContentUnavailableTitle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Text(text).font(.headline).makeComponent(context: context)
    }
}
@MainActor
public struct Spacer: View {
    public typealias Body = Never

    private let minLength: Double?

    public init(minLength: Double? = nil) {
        self.minLength = minLength
    }

    public var body: Never {
        fatalError("Spacer has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let preferredSize: Size
        switch context.stackAxis {
        case .horizontal:
            preferredSize = Size(width: minLength ?? 0, height: 0)
        case .vertical:
            preferredSize = Size(width: 0, height: minLength ?? 0)
        case nil:
            preferredSize = Size(width: minLength ?? 0, height: minLength ?? 0)
        }

        return Component { _ in
            Controls.panel(
                preferredSize: preferredSize,
                layoutPriority: 1,
                isHitTestVisible: false
            )
        }
    }
}
@MainActor
public struct Divider: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("Divider has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let isVertical = context.stackAxis == .horizontal
        return Component { _ in
            Controls.panel(
                preferredSize: Size(
                    width: isVertical ? 1 : 16,
                    height: isVertical ? 16 : 1
                ),
                backgroundColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22),
                isHitTestVisible: false
            )
        }
    }
}
@MainActor
public struct VStack: View {
    public typealias Body = Never

    private let alignment: HorizontalAlignment
    private let spacing: Double
    private let content: [AnyView]

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> [AnyView])
    {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.content = content()
    }

    public var body: Never {
        fatalError("VStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let childContext = context.withStackAxis(.vertical)
            return Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: spacing,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                ),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}
@MainActor
public struct HStack: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let spacing: Double
    private let content: [AnyView]

    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.content = content()
    }

    public var body: Never {
        fatalError("HStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let childContext = context.withStackAxis(.horizontal)
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}
@MainActor
public struct VStackLayout {
    public var alignment: HorizontalAlignment
    public var spacing: Double?

    public init(alignment: HorizontalAlignment = .center, spacing: Double? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .vertical
        return properties
    }

    public func callAsFunction(@ViewBuilder content: () -> [AnyView]) -> some View {
        VStack(alignment: alignment, spacing: spacing, content: content)
    }
}
@MainActor
public struct HStackLayout {
    public var alignment: VerticalAlignment
    public var spacing: Double?

    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }

    public func callAsFunction(@ViewBuilder content: () -> [AnyView]) -> some View {
        HStack(alignment: alignment, spacing: spacing, content: content)
    }
}
@MainActor
public struct ZStackLayout {
    public var alignment: Alignment

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }

    public static var layoutProperties: LayoutProperties {
        LayoutProperties()
    }

    public func callAsFunction(@ViewBuilder content: () -> [AnyView]) -> some View {
        ZStack(alignment: alignment, content: content)
    }
}
@MainActor
public struct GridLayout {
    public var alignment: Alignment
    public var horizontalSpacing: Double?
    public var verticalSpacing: Double?

    public init(alignment: Alignment = .center, horizontalSpacing: Double? = nil, verticalSpacing: Double? = nil) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public func callAsFunction(@ViewBuilder content: () -> [AnyView]) -> some View {
        Grid(
            alignment: alignment, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing,
            content: content)
    }
}
@MainActor
public struct GridRowLayout {
    public var alignment: VerticalAlignment

    public init(alignment: VerticalAlignment = .center) {
        self.alignment = alignment
    }

    public func callAsFunction(@ViewBuilder content: () -> [AnyView]) -> some View {
        GridRow(alignment: alignment, content: content)
    }
}
@MainActor
public struct AnyLayout {
    private enum Storage {
        case horizontal(HStackLayout)
        case vertical(VStackLayout)
        case zStack(ZStackLayout)
    }

    private let storage: Storage

    public init(_ layout: HStackLayout) {
        storage = .horizontal(layout)
    }

    public init(_ layout: VStackLayout) {
        storage = .vertical(layout)
    }

    public init(_ layout: ZStackLayout) {
        storage = .zStack(layout)
    }

    public func callAsFunction(@ViewBuilder content: () -> [AnyView]) -> some View {
        AnyLayoutView(layout: self, content: content())
    }

    fileprivate func makeView(content: [AnyView]) -> AnyView {
        switch storage {
        case .horizontal(let layout):
            return AnyView(HStack(alignment: layout.alignment, spacing: layout.spacing) { content })
        case .vertical(let layout):
            return AnyView(VStack(alignment: layout.alignment, spacing: layout.spacing) { content })
        case .zStack(let layout):
            return AnyView(ZStack(alignment: layout.alignment) { content })
        }
    }
}
@MainActor
private struct AnyLayoutView: View {
    typealias Body = Never

    let layout: AnyLayout
    let content: [AnyView]

    var body: Never {
        fatalError("AnyLayoutView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        layout.makeView(content: content).makeComponent(context: context)
    }
}
@MainActor
public struct LazyVStack: View {
    public typealias Body = Never

    private let alignment: HorizontalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Component { runtime in
            let childContext = context.withStackAxis(.vertical)
            let children = retainedLazyStackChildren(
                from: content,
                context: childContext,
                runtime: runtime,
                pinnedViews: pinnedViews
            )
            return Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: spacing,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                ),
                isHitTestVisible: false,
                children: children
            )
        }
    }
}
@MainActor
public struct LazyHStack: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Component { runtime in
            let childContext = context.withStackAxis(.horizontal)
            let children = retainedLazyStackChildren(
                from: content,
                context: childContext,
                runtime: runtime,
                pinnedViews: pinnedViews
            )
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: children
            )
        }
    }
}
@MainActor
private func retainedLazyStackChildren(
    from content: [AnyView],
    context: ViewBuildContext,
    runtime: RetainedViewRuntime,
    pinnedViews: PinnedScrollableViews
) -> [ViewNode] {
    let children = content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
    guard !pinnedViews.isEmpty else {
        return children
    }

    for child in children {
        applyRetainedPinnedSectionHints(to: child, pinnedViews: pinnedViews)
    }
    return children
}
@MainActor
private func applyRetainedPinnedSectionHints(to node: ViewNode, pinnedViews: PinnedScrollableViews) {
    if pinnedViews.contains(.sectionHeaders), node.sectionHeaderChildCount > 0 {
        for child in node.children.prefix(node.sectionHeaderChildCount) {
            child.paintsInDeferredPhase = true
        }
    }

    if pinnedViews.contains(.sectionFooters), node.sectionFooterChildCount > 0 {
        for child in node.children.suffix(node.sectionFooterChildCount) {
            child.paintsInDeferredPhase = true
        }
    }

    for child in node.children {
        applyRetainedPinnedSectionHints(to: child, pinnedViews: pinnedViews)
    }
}
@MainActor
public struct Grid: View {
    public typealias Body = Never

    private let alignment: Alignment
    private let horizontalSpacing: Double
    private let verticalSpacing: Double
    private let content: [AnyView]

    public init(
        alignment: Alignment = .center,
        horizontalSpacing: Double? = nil,
        verticalSpacing: Double? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing ?? 0
        self.verticalSpacing = verticalSpacing ?? 0
        self.content = content()
    }

    public var body: Never {
        fatalError("Grid has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let verticalSpacing = verticalSpacing
        let horizontalSpacing = horizontalSpacing
        let childContext =
            context
            .withStackAxis(.vertical)
            .withEnvironmentValue(\.gridHorizontalSpacing, horizontalSpacing)
        let content = content

        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: verticalSpacing,
                    alignment: alignment.horizontal.stackAlignment(layoutDirection: context.layoutDirection)
                ),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}
@MainActor
public struct GridRow: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let content: [AnyView]

    public init(alignment: VerticalAlignment = .center, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("GridRow has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let childContext = context.withStackAxis(.horizontal)
        let horizontalSpacing = context.gridHorizontalSpacing ?? 0
        return Component { runtime in
            Controls.stackPanel(
                stackLayout: .horizontal(spacing: horizontalSpacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: childContext).makeNode(runtime: runtime) }
            )
        }
    }
}
public struct GridCell<Content: View>: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("GridCell has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: content, context: context, fallbackLayout: .stack(.vertical(alignment: .stretch)))
    }
}
public struct GridCellAnchor: Sendable, Equatable {
    public let unitPoint: UnitPoint

    public init(_ unitPoint: UnitPoint) {
        self.unitPoint = unitPoint
    }
}
extension GridCellAnchor: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(unitPoint.x)
        hasher.combine(unitPoint.y)
    }
}
public struct GridColumn: Equatable, Hashable {
    public let id: AnyHashable

    public init<ID: Hashable>(_ id: ID) {
        self.id = AnyHashable(id)
    }
}
public enum GridRowAlignment: Sendable, Equatable, Hashable {
    case firstTextBaseline
    case lastTextBaseline
    case center
    case top
    case bottom
}
public enum GridColumnAlignment: Sendable, Equatable, Hashable {
    case leading
    case trailing
    case center
}
public struct GridItem: Sendable {
    public var size: Size
    public var spacing: Double?
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: Double? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }

    public enum Size: Sendable, Equatable {
        case fixed(Double)
        case flexible(minimum: Double = 10, maximum: Double = .infinity)
        case adaptive(minimum: Double, maximum: Double = .infinity)
    }
}
@MainActor
public struct LazyVGrid: View {
    public typealias Body = Never

    private let columns: [GridItem]
    private let alignment: HorizontalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        columns: [GridItem],
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.columns = columns
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVGrid has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Component { runtime in
            let resolvedSpecs = resolveVGridSpecs(self.columns, availableWidth: context.canvasSize.width)
            let columnCount = resolvedSpecs.count
            let content = self.content

            guard columnCount > 0, !content.isEmpty else {
                return Controls.panel(
                    frame: .zero,
                    layoutMode: .stack(.vertical(spacing: 0, padding: .zero, alignment: .stretch)),
                    children: []
                )
            }

            let horizontalSpacing = self.columns.first?.spacing ?? 0
            let childContext = context.withStackAxis(.vertical)

            var rowNodes: [ViewNode] = []
            var index = 0
            while index < content.count {
                var cellNodes: [ViewNode] = []
                for columnIndex in 0..<columnCount {
                    guard index < content.count else { break }
                    let cell = content[index].makeComponent(context: childContext).makeNode(runtime: runtime)
                    applyGridSpec(resolvedSpecs[columnIndex], to: cell, axis: .horizontal)
                    cellNodes.append(cell)
                    index += 1
                }
                let row = Controls.stackPanel(
                    stackLayout: .horizontal(
                        spacing: horizontalSpacing,
                        alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection),
                        distribution: .fill
                    ),
                    isHitTestVisible: false,
                    children: cellNodes
                )
                rowNodes.append(row)
            }

            for row in rowNodes {
                applyRetainedPinnedSectionHints(to: row, pinnedViews: pinnedViews)
            }

            return Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: spacing,
                    alignment: .stretch
                ),
                isHitTestVisible: false,
                children: rowNodes
            )
        }
    }
}
@MainActor
public struct LazyHGrid: View {
    public typealias Body = Never

    private let rows: [GridItem]
    private let alignment: VerticalAlignment
    private let spacing: Double
    private let pinnedViews: PinnedScrollableViews
    private let content: [AnyView]

    public init(
        rows: [GridItem],
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        pinnedViews: PinnedScrollableViews = [],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.rows = rows
        self.alignment = alignment
        self.spacing = spacing ?? 0
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHGrid has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Component { runtime in
            let resolvedSpecs = resolveHGridSpecs(self.rows, availableHeight: context.canvasSize.height)
            let rowCount = resolvedSpecs.count
            let content = self.content

            guard rowCount > 0, !content.isEmpty else {
                return Controls.panel(
                    frame: .zero,
                    layoutMode: .stack(.horizontal(spacing: 0, padding: .zero, alignment: .stretch)),
                    children: []
                )
            }

            let verticalSpacing = self.rows.first?.spacing ?? 0
            let childContext = context.withStackAxis(.horizontal)

            var columnNodes: [ViewNode] = []
            var index = 0
            while index < content.count {
                var cellNodes: [ViewNode] = []
                for rowIndex in 0..<rowCount {
                    guard index < content.count else { break }
                    let cell = content[index].makeComponent(context: childContext).makeNode(runtime: runtime)
                    applyGridSpec(resolvedSpecs[rowIndex], to: cell, axis: .vertical)
                    cellNodes.append(cell)
                    index += 1
                }
                let column = Controls.stackPanel(
                    stackLayout: .vertical(
                        spacing: verticalSpacing,
                        alignment: alignment.stackAlignment,
                        distribution: .fill
                    ),
                    isHitTestVisible: false,
                    children: cellNodes
                )
                columnNodes.append(column)
            }

            for column in columnNodes {
                applyRetainedPinnedSectionHints(to: column, pinnedViews: pinnedViews)
            }

            return Controls.stackPanel(
                stackLayout: .horizontal(
                    spacing: spacing,
                    alignment: .stretch
                ),
                isHitTestVisible: false,
                children: columnNodes
            )
        }
    }
}
private struct ResolvedGridSpec {
    var size: GridItem.Size
    var spacing: Double?
    var alignment: Alignment?
}
private func resolveVGridSpecs(_ columns: [GridItem], availableWidth: Double) -> [ResolvedGridSpec] {
    let nonAdaptive = columns.filter {
        if case .adaptive = $0.size { return false }
        return true
    }
    let adaptive = columns.filter {
        if case .adaptive = $0.size { return true }
        return false
    }

    if adaptive.isEmpty {
        return columns.map { ResolvedGridSpec(size: $0.size, spacing: $0.spacing, alignment: $0.alignment) }
    }

    if nonAdaptive.isEmpty {
        guard let first = adaptive.first else { return [] }
        if case .adaptive(let min, _) = first.size {
            let count = max(1, Int(availableWidth / min))
            let width = availableWidth / Double(count)
            return (0..<count).map { _ in
                ResolvedGridSpec(size: .fixed(width), spacing: first.spacing, alignment: first.alignment)
            }
        }
        return []
    }

    // Mixed: reserve space for non-adaptive columns, then fit adaptive columns in remainder.
    let reservedWidth = nonAdaptive.reduce(0) { sum, item in
        if case .fixed(let w) = item.size { return sum + w }
        if case .flexible(let min, _) = item.size { return sum + max(0, min) }
        return sum
    }
    let remainingWidth = max(0, availableWidth - reservedWidth)
    guard let firstAdaptive = adaptive.first else { return [] }
    if case .adaptive(let min, _) = firstAdaptive.size {
        let adaptiveCount = max(1, Int(remainingWidth / min))
        var result: [ResolvedGridSpec] = []
        for item in columns {
            if case .adaptive = item.size {
                let width = remainingWidth / Double(adaptiveCount)
                for _ in 0..<adaptiveCount {
                    result.append(
                        ResolvedGridSpec(size: .fixed(width), spacing: item.spacing, alignment: item.alignment))
                }
            } else {
                result.append(ResolvedGridSpec(size: item.size, spacing: item.spacing, alignment: item.alignment))
            }
        }
        return result
    }
    return []
}
private func resolveHGridSpecs(_ rows: [GridItem], availableHeight: Double) -> [ResolvedGridSpec] {
    let nonAdaptive = rows.filter {
        if case .adaptive = $0.size { return false }
        return true
    }
    let adaptive = rows.filter {
        if case .adaptive = $0.size { return true }
        return false
    }

    if adaptive.isEmpty {
        return rows.map { ResolvedGridSpec(size: $0.size, spacing: $0.spacing, alignment: $0.alignment) }
    }

    if nonAdaptive.isEmpty {
        guard let first = adaptive.first else { return [] }
        if case .adaptive(let min, _) = first.size {
            let count = max(1, Int(availableHeight / min))
            let height = availableHeight / Double(count)
            return (0..<count).map { _ in
                ResolvedGridSpec(size: .fixed(height), spacing: first.spacing, alignment: first.alignment)
            }
        }
        return []
    }

    let reservedHeight = nonAdaptive.reduce(0) { sum, item in
        if case .fixed(let h) = item.size { return sum + h }
        if case .flexible(let min, _) = item.size { return sum + max(0, min) }
        return sum
    }
    let remainingHeight = max(0, availableHeight - reservedHeight)
    guard let firstAdaptive = adaptive.first else { return [] }
    if case .adaptive(let min, _) = firstAdaptive.size {
        let adaptiveCount = max(1, Int(remainingHeight / min))
        var result: [ResolvedGridSpec] = []
        for item in rows {
            if case .adaptive = item.size {
                let height = remainingHeight / Double(adaptiveCount)
                for _ in 0..<adaptiveCount {
                    result.append(
                        ResolvedGridSpec(size: .fixed(height), spacing: item.spacing, alignment: item.alignment))
                }
            } else {
                result.append(ResolvedGridSpec(size: item.size, spacing: item.spacing, alignment: item.alignment))
            }
        }
        return result
    }
    return []
}
@MainActor
private func applyGridSpec(_ spec: ResolvedGridSpec, to node: ViewNode, axis: StackAxis) {
    switch spec.size {
    case .fixed(let value):
        if axis == .horizontal {
            node.preferredSize = Size(width: value, height: node.preferredSize?.height ?? 0)
        } else {
            node.preferredSize = Size(width: node.preferredSize?.width ?? 0, height: value)
        }
        node.flexItem = FlexProperties(grow: 0, shrink: 0)
    case .flexible(let min, let max):
        node.flexItem = FlexProperties(flex: 1)
        var constraints = node.layoutConstraints ?? .unconstrained
        if axis == .horizontal {
            constraints = LayoutConstraints(
                minWidth: min > 0 ? min : constraints.minWidth,
                maxWidth: max.isFinite ? max : constraints.maxWidth,
                minHeight: constraints.minHeight,
                maxHeight: constraints.maxHeight
            )
        } else {
            constraints = LayoutConstraints(
                minWidth: constraints.minWidth,
                maxWidth: constraints.maxWidth,
                minHeight: min > 0 ? min : constraints.minHeight,
                maxHeight: max.isFinite ? max : constraints.maxHeight
            )
        }
        if constraints != .unconstrained {
            node.layoutConstraints = constraints
        }
    case .adaptive:
        // Adaptive sizes should have been resolved to fixed before application.
        break
    }
}
@MainActor
public struct ZStack: View {
    public typealias Body = Never

    private let alignment: Alignment
    private let content: [AnyView]

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.content = content()
    }

    public var body: Never {
        fatalError("ZStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let childNodes = content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            let root = Controls.panel(layoutMode: .absolute, isHitTestVisible: false, children: childNodes)
            root.onLayout = { bounds in
                for child in childNodes {
                    let childSize = child.intrinsicContentSize()
                    let origin = alignment.frameOrigin(
                        for: childSize,
                        in: bounds.size,
                        layoutDirection: context.layoutDirection
                    )
                    let frame = Rect(origin: origin, size: childSize)
                    if child.frame != frame {
                        child.frame = frame
                    }
                }
            }
            return root
        }
    }
}
@MainActor
public struct GeometryReader: View {
    public typealias Body = Never

    private let content: (GeometryProxy) -> [AnyView]

    public init(@ViewBuilder content: @escaping (GeometryProxy) -> [AnyView]) {
        self.content = content
    }

    public var body: Never {
        fatalError("GeometryReader has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(
            from: content(GeometryProxy(size: context.canvasSize)),
            context: context,
            fallbackLayout: .absolute
        )
    }
}
@MainActor
public struct ScrollView: View {
    public typealias Body = Never

    private let axis: Axis
    private let style: ScrollViewStyle
    private let showsIndicators: Bool?
    private let content: [AnyView]

    @_disfavoredOverload
    public init(_ axis: Axis = .vertical, style: ScrollViewStyle = .default, @ViewBuilder content: () -> [AnyView]) {
        self.axis = axis
        self.style = style
        self.showsIndicators = nil
        self.content = content()
    }

    public init(_ axes: Axis.Set, showsIndicators: Bool = true, @ViewBuilder content: () -> [AnyView]) {
        self.axis = axes.preferredRetainedAxis
        self.style = .default
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: Never {
        fatalError("ScrollView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let scrollIndicatorInsets = context.contentInsets(
                for: .scrollIndicators,
                defaultInsets: defaultRetainedScrollIndicatorInsets
            )
            let initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
            let scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
            let alignmentAnchor = context.defaultScrollAnchor(for: .alignment)
            let node = Controls.scrollPanel(
                axis: axis.scrollAxis,
                backgroundColor: context.scrollContentBackgroundVisibility.hidesRetainedScrollContentBackground
                    ? nil : style.backgroundColor,
                borderColor: style.borderColor,
                borderWidth: style.borderWidth,
                shadowColor: style.shadowColor,
                shadowOffset: style.shadowOffset,
                shadowSpread: style.shadowSpread,
                cornerRadius: style.cornerRadius,
                stackLayout: scrollStackLayout(
                    layoutDirection: context.layoutDirection,
                    padding: context.contentInsets(for: .scrollContent, defaultInsets: style.padding),
                    alignmentAnchor: alignmentAnchor
                ),
                scrollStep: style.scrollStep,
                scrollIndicatorColor: style.indicatorColor,
                scrollIndicatorHoverColor: style.indicatorHoverColor,
                scrollIndicatorActiveColor: style.indicatorActiveColor,
                scrollIndicatorThickness: style.indicatorThickness,
                scrollIndicatorInsets: scrollIndicatorInsets,
                initialScrollAnchor: initialScrollAnchor,
                scrollSizeChangeAnchor: scrollSizeChangeAnchor,
                isHitTestVisible: style.isHitTestVisible,
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
            node.horizontalScrollBounceBehavior = context.horizontalScrollBounceBehavior.description
            node.verticalScrollBounceBehavior = context.verticalScrollBounceBehavior.description
            node.scrollTargetBehavior = context.scrollTargetBehavior?.description
            node.scrollInputBehaviors = context.retainedScrollInputBehaviors
            node.scrollIndicatorsFlashOnAppear = context.scrollIndicatorsFlashOnAppear
            node.scrollIndicatorsFlashTrigger = context.scrollIndicatorsFlashTrigger
            node.scrollPosition = context.scrollPositionMetadata
            if !context.isScrollEnabled {
                node.scrollAxis = nil
                node.showsScrollIndicator = false
            } else {
                node.showsScrollIndicator =
                    (showsIndicators ?? true)
                    && context.scrollIndicatorVisibility(for: axis).showsRetainedScrollIndicator
            }
            if context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            return node
        }
    }

    private func scrollStackLayout(
        layoutDirection: LayoutDirection,
        padding: EdgeInsets,
        alignmentAnchor: UnitPoint?
    ) -> StackLayout {
        switch axis {
        case .horizontal:
            return .horizontal(
                spacing: style.spacing,
                padding: padding,
                alignment: alignmentAnchor.map { stackCrossAlignment(from: $0.y) } ?? .center,
                mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.x) } ?? .start
            )
        case .vertical:
            return .vertical(
                spacing: style.spacing,
                padding: padding,
                alignment: alignmentAnchor.map { stackCrossAlignment(from: $0.x) }
                    ?? style.alignment.stackAlignment(layoutDirection: layoutDirection),
                mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
            )
        }
    }
}
@MainActor
public struct ScrollViewReader: View {
    public typealias Body = Never

    private let proxy: ScrollViewProxy
    private let content: [AnyView]

    public init(@ViewBuilder content: (ScrollViewProxy) -> [AnyView]) {
        let proxy = ScrollViewProxy()
        self.proxy = proxy
        self.content = content(proxy)
    }

    public var body: Never {
        fatalError("ScrollViewReader has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let component = composeComponent(from: content, context: context)
        let proxy = proxy
        return Component { runtime in
            let node = component.makeNode(runtime: runtime)
            node.scrollReaderID = proxy.retainedIdentifier
            node.scrollProxyRequests = proxy.retainedRequests
            return node
        }
    }
}
@MainActor
private enum ListSelectionMode {
    case single(get: () -> AnyHashable?, set: (AnyHashable?) -> Void)
    case multiple(get: () -> Set<AnyHashable>, set: (Set<AnyHashable>) -> Void)

    static func single<Value: Hashable>(_ selection: Binding<Value?>) -> ListSelectionMode {
        .single(
            get: {
                selection.wrappedValue.map { AnyHashable($0) }
            },
            set: { value in
                selection.wrappedValue = value?.base as? Value
            }
        )
    }

    static func requiredSingle<Value: Hashable>(_ selection: Binding<Value>) -> ListSelectionMode {
        .single(
            get: {
                AnyHashable(selection.wrappedValue)
            },
            set: { value in
                guard let value = value?.base as? Value else {
                    return
                }
                selection.wrappedValue = value
            }
        )
    }

    static func multiple<Value: Hashable>(_ selection: Binding<Set<Value>>) -> ListSelectionMode {
        .multiple(
            get: {
                Set(selection.wrappedValue.map { AnyHashable($0) })
            },
            set: { values in
                selection.wrappedValue = Set(values.compactMap { $0.base as? Value })
            }
        )
    }

    func contains(_ value: AnyHashable) -> Bool {
        switch self {
        case .single(let get, _):
            return get() == value
        case .multiple(let get, _):
            return get().contains(value)
        }
    }

    @discardableResult
    func activate(_ value: AnyHashable) -> Bool {
        switch self {
        case .single(let get, let set):
            guard get() != value else {
                return false
            }
            set(value)
            return true
        case .multiple(let get, let set):
            var values = get()
            if values.contains(value) {
                values.remove(value)
            } else {
                values.insert(value)
            }
            set(values)
            return true
        }
    }
}
@MainActor
public struct List: View {
    public typealias Body = Never

    private let content: [AnyView]
    private let selectionMode: ListSelectionMode?

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
        self.selectionMode = nil
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<SelectionValue?>?,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectionMode = selection.map { .single($0) }
    }

    public init<SelectionValue: Hashable>(
        selection: Binding<Set<SelectionValue>>?,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.content = content()
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = ForEach(data, id: id, content: rowContent).contentViews
        self.selectionMode = nil
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<ID?>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = Self.taggedRows(data, id: id, rowContent: rowContent)
        self.selectionMode = selection.map { .single($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<ID>>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) {
        self.content = Self.taggedRows(data, id: id, rowContent: rowContent)
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init(
        _ data: Range<Int>,
        selection: Binding<Int>,
        @ViewBuilder rowContent: (Int) -> [AnyView]
    ) {
        self.content = Self.taggedRows(data, id: \.self, rowContent: rowContent)
        self.selectionMode = .requiredSingle(selection)
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.content = ForEach(data, content: rowContent).contentViews
        self.selectionMode = nil
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        selection: Binding<Data.Element.ID?>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.content = Self.taggedRows(data, id: \.id, rowContent: rowContent)
        self.selectionMode = selection.map { .single($0) }
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        selection: Binding<Set<Data.Element.ID>>?,
        @ViewBuilder rowContent: (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.content = Self.taggedRows(data, id: \.id, rowContent: rowContent)
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Binding<Data>,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Set<ID>>?,
        @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> [AnyView]
    ) {
        self.content = data.wrappedValue.enumerated().map { index, element in
            rowContent(Binding(get: { element }, set: { _ in }))
        }.flatMap { $0 }
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        children: KeyPath<Data.Element, [Data.Element]?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.content = [
            AnyView(
                OutlineGroup(data, children: children) { item in
                    Group { rowContent(item) }
                })
        ]
        self.selectionMode = nil
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        children: KeyPath<Data.Element, [Data.Element]?>,
        @ViewBuilder rowContent: @escaping (Data.Element) -> [AnyView]
    ) {
        self.content = [
            AnyView(
                OutlineGroup(data, id: id, children: children) { item in
                    Group { rowContent(item) }
                })
        ]
        self.selectionMode = nil
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        children: KeyPath<Data.Element, [Data.Element]?>,
        selection: Binding<Data.Element.ID?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.content = [
            AnyView(
                OutlineGroup(data, children: children) { item in
                    Group { rowContent(item) }
                })
        ]
        self.selectionMode = selection.map { .single($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        children: KeyPath<Data.Element, [Data.Element]?>,
        selection: Binding<ID?>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> [AnyView]
    ) {
        self.content = [
            AnyView(
                OutlineGroup(data, id: id, children: children) { item in
                    Group { rowContent(item) }
                })
        ]
        self.selectionMode = selection.map { .single($0) }
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        children: KeyPath<Data.Element, [Data.Element]?>,
        selection: Binding<Set<Data.Element.ID>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> [AnyView]
    ) where Data.Element: Identifiable {
        self.content = [
            AnyView(
                OutlineGroup(data, children: children) { item in
                    Group { rowContent(item) }
                })
        ]
        self.selectionMode = selection.map { .multiple($0) }
    }

    public init<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        children: KeyPath<Data.Element, [Data.Element]?>,
        selection: Binding<Set<ID>>?,
        @ViewBuilder rowContent: @escaping (Data.Element) -> [AnyView]
    ) {
        self.content = [
            AnyView(
                OutlineGroup(data, id: id, children: children) { item in
                    Group { rowContent(item) }
                })
        ]
        self.selectionMode = selection.map { .multiple($0) }
    }

    public var body: Never {
        fatalError("List has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let listChrome = context.listStyle.retainedChrome
            let alignmentAnchor = context.defaultScrollAnchor(for: .alignment)
            let isEditing = context.environmentValues.editMode?.wrappedValue.isEditing == true
            let node = Controls.scrollPanel(
                axis: .vertical,
                backgroundColor: listChrome.backgroundColor,
                borderColor: listChrome.borderColor,
                borderWidth: listChrome.borderWidth,
                cornerRadius: listChrome.cornerRadius,
                stackLayout: .vertical(
                    spacing: context.listRowSpacing
                        ?? context.listSectionSpacing(defaultSpacing: listChrome.defaultSpacing),
                    padding: context.contentInsets(for: .scrollContent, defaultInsets: listChrome.padding),
                    alignment: .stretch,
                    mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
                ),
                isHitTestVisible: false,
                children: content.enumerated().map { pair in
                    let index = pair.offset
                    let view = pair.element
                    let tag = view.selectionTag
                    let isSelected = tag.map { selectionMode?.contains($0) == true } == true
                    let rowContext =
                        isSelected
                        ? context.withEnvironmentValue(\.backgroundProminence, .increased)
                        : context
                    var row = view.makeComponent(context: rowContext).makeNode(runtime: runtime)
                    if context.isSelectionDisabled, row.selectionDisabledOverride == nil {
                        row.selectionDisabled = true
                    }
                    if context.isDeleteDisabled, row.deleteDisabledOverride == nil {
                        row.deleteDisabled = true
                    }
                    if context.isMoveDisabled, row.moveDisabledOverride == nil {
                        row.moveDisabled = true
                    }
                    if let selectionMode, let tag, !row.selectionDisabled {
                        row = Self.selectableRow(
                            wrapping: row,
                            tag: tag,
                            selectionMode: selectionMode,
                            isSelected: isSelected,
                            isEditing: isEditing,
                            context: context
                        )
                    }
                    row = Self.alternatingRowIfNeeded(
                        row,
                        index: index,
                        isSelected: isSelected,
                        listChrome: listChrome
                    )
                    if context.defaultMinListRowHeight > 0 {
                        row.applyDefaultMinimumHeight(context.defaultMinListRowHeight)
                    }
                    return row
                }
            )
            node.horizontalScrollBounceBehavior = context.horizontalScrollBounceBehavior.description
            node.verticalScrollBounceBehavior = context.verticalScrollBounceBehavior.description
            node.scrollTargetBehavior = context.scrollTargetBehavior?.description
            node.scrollInputBehaviors = context.retainedScrollInputBehaviors
            node.scrollIndicatorsFlashOnAppear = context.scrollIndicatorsFlashOnAppear
            node.scrollIndicatorsFlashTrigger = context.scrollIndicatorsFlashTrigger
            node.scrollPosition = context.scrollPositionMetadata
            node.scrollIndicatorInsets = context.contentInsets(
                for: .scrollIndicators,
                defaultInsets: defaultRetainedScrollIndicatorInsets
            )
            node.initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
            node.scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
            if !context.isScrollEnabled {
                node.scrollAxis = nil
                node.showsScrollIndicator = false
            } else {
                node.showsScrollIndicator = context.verticalScrollIndicatorVisibility.showsRetainedScrollIndicator
            }
            if context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            return node
        }
    }

    private static func taggedRows<Data: RandomAccessCollection, ID: Hashable>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        rowContent: (Data.Element) -> [AnyView]
    ) -> [AnyView] {
        var views: [AnyView] = []
        for (elementIndex, element) in data.enumerated() {
            let elementID = element[keyPath: id]
            let elementIDDescription = String(describing: elementID)
            let elementViews = rowContent(element)
            for (index, view) in elementViews.enumerated() {
                views.append(
                    AnyView(
                        DynamicListEditMetadataView(
                            content: AnyView(view.id("\(elementIDDescription)#\(index)").tag(elementID)),
                            dynamicContentIndex: elementIndex
                        )
                    )
                )
            }
        }
        return views
    }

    private static func selectableRow(
        wrapping row: ViewNode,
        tag: AnyHashable,
        selectionMode: ListSelectionMode,
        isSelected: Bool,
        isEditing: Bool,
        context: ViewBuildContext
    ) -> ViewNode {
        let selectionTint = context.tint
        if isEditing {
            row.layoutPriority = max(row.layoutPriority, 1)
        }
        let rowContent =
            isEditing
            ? Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(spacing: 10, padding: .zero, alignment: .center),
                isHitTestVisible: false,
                children: [
                    Self.editSelectionIndicator(isSelected: isSelected, tint: selectionTint),
                    row,
                ]
            )
            : row
        let rowNode = Controls.stackPanel(
            backgroundColor: isSelected ? selectionTint.opacity(0.16) : nil,
            borderColor: isSelected ? selectionTint.opacity(0.52) : .clear,
            borderWidth: isSelected ? 1 : 0,
            cornerRadius: 10,
            stackLayout: .vertical(
                spacing: 0,
                padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                alignment: .stretch
            ),
            isHitTestVisible: true,
            children: [rowContent]
        )
        rowNode.nodeTag = row.nodeTag ?? "selection:\(String(describing: tag.base))"

        guard context.isEnabled else {
            return rowNode
        }

        rowNode.isFocusable = true
        rowNode.onActivate = {
            if selectionMode.activate(tag) {
                context.invalidate()
            }
        }
        return rowNode
    }

    private static func alternatingRowIfNeeded(
        _ row: ViewNode,
        index: Int,
        isSelected: Bool,
        listChrome: RetainedListChrome
    ) -> ViewNode {
        guard listChrome.alternatesRowBackgrounds,
            !isSelected,
            index % 2 == 1,
            row.backgroundColor == nil,
            row.backgroundGradient == nil,
            let backgroundColor = listChrome.alternatingRowBackgroundColor
        else {
            return row
        }

        row.backgroundColor = backgroundColor
        row.cornerRadius = max(row.cornerRadius, 8)
        return row
    }

    private static func editSelectionIndicator(isSelected: Bool, tint: Color) -> ViewNode {
        let innerNode = Controls.panel(
            preferredSize: Size(width: 8, height: 8),
            backgroundColor: isSelected ? .white : nil,
            cornerRadius: 4,
            isHitTestVisible: false
        )
        innerNode.nodeTag = "list-edit-selection-dot"

        let indicator = Controls.stackPanel(
            preferredSize: Size(width: 18, height: 18),
            backgroundColor: isSelected ? tint.opacity(0.92) : nil,
            borderColor: isSelected ? tint.opacity(0.96) : tint.opacity(0.46),
            borderWidth: 1,
            cornerRadius: 9,
            stackLayout: .vertical(alignment: .center, mainAlignment: .center),
            isHitTestVisible: false,
            children: isSelected ? [innerNode] : []
        )
        indicator.nodeTag = isSelected ? "list-edit-selection-selected" : "list-edit-selection-unselected"
        return indicator
    }

    public init<Collection>(
        _ data: Binding<Collection>,
        @ViewBuilder rowContent: (Binding<Collection.Element>) -> [AnyView]
    )
    where
        Collection: MutableCollection & RandomAccessCollection,
        Collection.Element: Identifiable,
        Collection.Index: Hashable
    {
        self.content = ForEach(data, content: rowContent).contentViews
        self.selectionMode = nil
    }

    public init<Collection, ID: Hashable>(
        _ data: Binding<Collection>,
        id: KeyPath<Collection.Element, ID>,
        @ViewBuilder rowContent: (Binding<Collection.Element>) -> [AnyView]
    )
    where
        Collection: MutableCollection & RandomAccessCollection,
        Collection.Index: Hashable
    {
        self.content = ForEach(data, id: id, content: rowContent).contentViews
        self.selectionMode = nil
    }
}
@resultBuilder
public enum TableColumnBuilder {
    public static func buildBlock<RowValue>(_ columns: [AnyTableColumn<RowValue>]...) -> [AnyTableColumn<RowValue>] {
        columns.flatMap { $0 }
    }

    public static func buildOptional<RowValue>(_ component: [AnyTableColumn<RowValue>]?) -> [AnyTableColumn<RowValue>] {
        component ?? []
    }

    public static func buildEither<RowValue>(first component: [AnyTableColumn<RowValue>]) -> [AnyTableColumn<RowValue>]
    {
        component
    }

    public static func buildEither<RowValue>(second component: [AnyTableColumn<RowValue>]) -> [AnyTableColumn<RowValue>]
    {
        component
    }

    public static func buildArray<RowValue>(_ components: [[AnyTableColumn<RowValue>]]) -> [AnyTableColumn<RowValue>] {
        components.flatMap { $0 }
    }

    @MainActor
    public static func buildExpression<RowValue>(_ expression: AnyTableColumn<RowValue>) -> [AnyTableColumn<RowValue>] {
        [expression]
    }

    @MainActor
    public static func buildExpression<RowValue>(_ expression: TableColumn<RowValue>) -> [AnyTableColumn<RowValue>] {
        [expression.eraseToAnyTableColumn()]
    }

    public static func buildLimitedAvailability<RowValue>(_ component: [AnyTableColumn<RowValue>]) -> [AnyTableColumn<
        RowValue
    >] {
        component
    }
}
@MainActor
public struct AnyTableColumn<RowValue> {
    public let title: String
    public let width: TableColumnWidth
    public let sortKey: AnyHashable?
    public let isSortable: Bool
    public let cellBuilder: (RowValue) -> [AnyView]
    public let headerBuilder: () -> [AnyView]

    public init(
        title: String,
        width: TableColumnWidth = .default,
        sortKey: AnyHashable? = nil,
        isSortable: Bool = false,
        cellBuilder: @escaping (RowValue) -> [AnyView],
        headerBuilder: @escaping () -> [AnyView]
    ) {
        self.title = title
        self.width = width
        self.sortKey = sortKey
        self.isSortable = isSortable
        self.cellBuilder = cellBuilder
        self.headerBuilder = headerBuilder
    }
}
public enum TableColumnWidth: Sendable, Equatable {
    case `default`
    case fixed(Double)
    case flexible(flex: Double = 1)
    case minMax(min: Double?, max: Double?)

    public static func width(_ value: Double) -> TableColumnWidth {
        .fixed(value)
    }

    public static func min(_ min: Double) -> TableColumnWidth {
        .minMax(min: min, max: nil)
    }

    public static func max(_ max: Double) -> TableColumnWidth {
        .minMax(min: nil, max: max)
    }

    public static func min(_ min: Double, max: Double) -> TableColumnWidth {
        .minMax(min: min, max: max)
    }
}
public enum TableColumnAlignment: Sendable, Equatable, Hashable {
    case leading
    case trailing
    case center
}
public struct TableColumnSort: Equatable, Hashable {
    public let key: AnyHashable
    public let isAscending: Bool

    public init<ID: Hashable>(_ key: ID, isAscending: Bool = true) {
        self.key = AnyHashable(key)
        self.isAscending = isAscending
    }
}
@MainActor
public struct TableColumn<RowValue> {
    public let title: String
    public let width: TableColumnWidth
    public let sortKey: AnyHashable?
    public let isSortable: Bool
    public let cellBuilder: (RowValue) -> [AnyView]
    public let headerBuilder: () -> [AnyView]

    public init(
        _ title: String,
        width: TableColumnWidth = .default,
        sort: AnyHashable? = nil,
        @ViewBuilder cellBuilder: @escaping (RowValue) -> [AnyView]
    ) {
        self.title = title
        self.width = width
        self.sortKey = sort
        self.isSortable = sort != nil
        self.cellBuilder = cellBuilder
        self.headerBuilder = { [AnyView(Text(title))] }
    }

    public init<Content: Hashable>(
        _ title: String,
        value: KeyPath<RowValue, Content>,
        width: TableColumnWidth = .default,
        sort: AnyHashable? = nil
    ) {
        self.title = title
        self.width = width
        self.sortKey = sort
        self.isSortable = sort != nil
        self.cellBuilder = { row in
            let content = row[keyPath: value]
            return [AnyView(Text(String(describing: content)))]
        }
        self.headerBuilder = { [AnyView(Text(title))] }
    }

    public func eraseToAnyTableColumn() -> AnyTableColumn<RowValue> {
        AnyTableColumn(
            title: title,
            width: width,
            sortKey: sortKey,
            isSortable: isSortable,
            cellBuilder: cellBuilder,
            headerBuilder: headerBuilder
        )
    }
}
extension TableColumn {
    public func makeTableColumn() -> AnyTableColumn<RowValue> {
        eraseToAnyTableColumn()
    }
}
@MainActor
public struct Table<Data: RandomAccessCollection>: View where Data.Element: Identifiable {
    public typealias Body = Never

    private let data: Data
    private let columns: [AnyTableColumn<Data.Element>]
    private let selectionMode: ListSelectionMode?
    private let onSort: ((AnyHashable?, SortOrder) -> Void)?
    private let currentSort: (key: AnyHashable, order: SortOrder)?

    public init(
        _ data: Data,
        selection: Binding<Data.Element.ID?>? = nil,
        sort: (key: AnyHashable, order: SortOrder)? = nil,
        onSort: ((AnyHashable?, SortOrder) -> Void)? = nil,
        @TableColumnBuilder columns: () -> [AnyTableColumn<Data.Element>]
    ) {
        self.data = data
        self.columns = columns()
        self.selectionMode = selection.map { .single($0) }
        self.onSort = onSort
        self.currentSort = sort
    }

    public init(
        _ data: Data,
        selection: Binding<Set<Data.Element.ID>>? = nil,
        sort: (key: AnyHashable, order: SortOrder)? = nil,
        onSort: ((AnyHashable?, SortOrder) -> Void)? = nil,
        @TableColumnBuilder columns: () -> [AnyTableColumn<Data.Element>]
    ) {
        self.data = data
        self.columns = columns()
        self.selectionMode = selection.map { .multiple($0) }
        self.onSort = onSort
        self.currentSort = sort
    }

    public var body: Never {
        fatalError("Table has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let columnCount = columns.count
            guard columnCount > 0 else {
                return Controls.panel(
                    frame: .zero,
                    layoutMode: .stack(.vertical(spacing: 0, padding: .zero, alignment: .stretch)),
                    children: []
                )
            }

            let style = context.tableStyle
            let isDark = context.backgroundProminence == .increased

            // Resolve style-driven chrome
            let headerBackground: Color
            let rowAltBackground: Color
            let borderColor: Color
            let borderWidth: Double
            let cornerRadius: Double
            let rowSpacing: Double
            let headerPadding: EdgeInsets
            let rowPadding: EdgeInsets

            switch style.kind {
            case .inset:
                headerBackground =
                    isDark
                    ? Color(red: 0.10, green: 0.12, blue: 0.14, alpha: 1)
                    : Color(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
                rowAltBackground =
                    isDark
                    ? Color(red: 0.09, green: 0.11, blue: 0.13, alpha: 1)
                    : Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 1)
                borderColor =
                    isDark
                    ? Color(red: 0.24, green: 0.28, blue: 0.32, alpha: 1)
                    : Color(red: 0.78, green: 0.82, blue: 0.86, alpha: 1)
                borderWidth = 1
                cornerRadius = 10
                rowSpacing = 0
                headerPadding = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
                rowPadding = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .bordered:
                headerBackground =
                    isDark
                    ? Color(red: 0.14, green: 0.16, blue: 0.18, alpha: 1)
                    : Color(red: 0.92, green: 0.94, blue: 0.96, alpha: 1)
                rowAltBackground =
                    isDark
                    ? Color(red: 0.11, green: 0.13, blue: 0.15, alpha: 1)
                    : Color(red: 0.96, green: 0.97, blue: 0.98, alpha: 1)
                borderColor =
                    isDark
                    ? Color(red: 0.35, green: 0.40, blue: 0.45, alpha: 1)
                    : Color(red: 0.65, green: 0.70, blue: 0.75, alpha: 1)
                borderWidth = 2
                cornerRadius = 6
                rowSpacing = 0
                headerPadding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                rowPadding = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .automatic:
                headerBackground =
                    isDark
                    ? Color(red: 0.12, green: 0.14, blue: 0.16, alpha: 1)
                    : Color(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
                rowAltBackground =
                    isDark
                    ? Color(red: 0.10, green: 0.11, blue: 0.12, alpha: 1)
                    : Color(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
                borderColor = Color(red: 0.85, green: 0.87, blue: 0.89, alpha: 1)
                borderWidth = 1
                cornerRadius = 4
                rowSpacing = 0
                headerPadding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                rowPadding = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }

            // Build header row
            let headerCells = columns.enumerated().map { pair in
                let column = pair.element
                let headerNode = self.buildHeaderCell(
                    column: column,
                    columnIndex: pair.offset,
                    context: context,
                    runtime: runtime
                )
                return headerNode
            }

            let headerRow = Controls.stackPanel(
                stackLayout: .horizontal(
                    spacing: 0,
                    padding: headerPadding,
                    alignment: .center,
                    distribution: .fill
                ),
                children: headerCells
            )
            headerRow.backgroundColor = headerBackground

            // Build data rows
            let dataRows = data.enumerated().map { pair in
                let element = pair.element
                let elementID = AnyHashable(element.id)
                let isSelected = self.selectionMode?.contains(elementID) == true

                let cells = columns.enumerated().map { cellPair in
                    let column = cellPair.element
                    let cellNode = self.buildDataCell(
                        column: column,
                        element: element,
                        columnIndex: cellPair.offset,
                        context: context,
                        runtime: runtime
                    )
                    return cellNode
                }

                var row = Controls.stackPanel(
                    stackLayout: .horizontal(
                        spacing: 0,
                        padding: rowPadding,
                        alignment: .center,
                        distribution: .fill
                    ),
                    children: cells
                )

                // Alternating row background
                if pair.offset % 2 == 1, !isSelected {
                    row.backgroundColor = rowAltBackground
                }

                if let selectionMode = self.selectionMode {
                    row = self.selectableTableRow(
                        wrapping: row,
                        tag: elementID,
                        selectionMode: selectionMode,
                        isSelected: isSelected,
                        context: context,
                        runtime: runtime
                    )
                }

                return row
            }

            let tableContent = Controls.scrollPanel(
                axis: .vertical,
                stackLayout: .vertical(
                    spacing: rowSpacing,
                    padding: .zero,
                    alignment: .stretch
                ),
                children: [headerRow] + dataRows
            )
            tableContent.borderColor = borderColor
            tableContent.borderWidth = borderWidth
            tableContent.cornerRadius = cornerRadius

            return tableContent
        }
    }

    private func buildHeaderCell(
        column: AnyTableColumn<Data.Element>,
        columnIndex: Int,
        context: ViewBuildContext,
        runtime: RetainedViewRuntime
    ) -> ViewNode {
        let headerViews = column.headerBuilder()
        let headerNode =
            headerViews.first?.makeComponent(context: context).makeNode(runtime: runtime)
            ?? Controls.panel(frame: .zero, text: column.title)

        // Apply column width constraints
        applyColumnWidth(column.width, to: headerNode)

        // Sort indicator
        if column.isSortable {
            let isSorted = currentSort?.key == column.sortKey
            let sortOrder = currentSort?.order ?? .forward
            let indicatorText = isSorted ? (sortOrder == .forward ? " ▲" : " ▼") : ""
            let sortIndicator = Controls.label(
                indicatorText,
                color: isSorted ? context.tint : Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                scale: 1.4,
                alignment: .trailing
            )
            let sortNode = sortIndicator
            let combined = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 4, padding: .zero, alignment: .center, distribution: .fill),
                children: [headerNode, sortNode]
            )
            if isSorted {
                combined.backgroundColor = context.tint.opacity(0.08)
            }
            return combined
        }

        return headerNode
    }

    private func buildDataCell(
        column: AnyTableColumn<Data.Element>,
        element: Data.Element,
        columnIndex: Int,
        context: ViewBuildContext,
        runtime: RetainedViewRuntime
    ) -> ViewNode {
        let cellViews = column.cellBuilder(element)
        let cellNode =
            cellViews.first?.makeComponent(context: context).makeNode(runtime: runtime)
            ?? Controls.panel(frame: .zero)
        applyColumnWidth(column.width, to: cellNode)
        return cellNode
    }

    private func applyColumnWidth(_ width: TableColumnWidth, to node: ViewNode) {
        switch width {
        case .default:
            node.flexItem = FlexProperties(flex: 1)
        case .fixed(let value):
            node.preferredSize = Size(width: value, height: 0)
            node.flexItem = FlexProperties(grow: 0, shrink: 0)
        case .flexible(let flex):
            node.flexItem = FlexProperties(flex: flex)
        case .minMax(let min, let max):
            var constraints = node.layoutConstraints ?? .unconstrained
            constraints = LayoutConstraints(
                minWidth: min ?? constraints.minWidth,
                maxWidth: max ?? constraints.maxWidth,
                minHeight: constraints.minHeight,
                maxHeight: constraints.maxHeight
            )
            node.layoutConstraints = constraints
            node.flexItem = FlexProperties(flex: 1)
        }
    }

    private func selectableTableRow(
        wrapping row: ViewNode,
        tag: AnyHashable,
        selectionMode: ListSelectionMode,
        isSelected: Bool,
        context: ViewBuildContext,
        runtime: RetainedViewRuntime
    ) -> ViewNode {
        let tint = context.tint
        let rowNode = Controls.stackPanel(
            backgroundColor: isSelected ? tint.opacity(0.12) : nil,
            borderColor: isSelected ? tint.opacity(0.5) : .clear,
            borderWidth: isSelected ? 1 : 0,
            cornerRadius: 6,
            stackLayout: .vertical(
                spacing: 0, padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4), alignment: .stretch),
            children: [row]
        )
        rowNode.nodeTag = "table-selection:\(String(describing: tag.base))"

        guard context.isEnabled else {
            return rowNode
        }

        rowNode.isFocusable = true
        rowNode.onActivate = {
            if selectionMode.activate(tag) {
                context.invalidate()
            }
        }
        return rowNode
    }
}
public enum SortOrder: Sendable, Equatable {
    case forward
    case reverse
}
@MainActor
public struct TableRow<Content: View>: View {
    public typealias Body = Never

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        fatalError("TableRow has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        content.makeComponent(context: context)
    }
}
@MainActor
public enum TableRowBuilder {
    public static func buildBlock(_ rows: [AnyView]...) -> [AnyView] {
        rows.flatMap { $0 }
    }

    public static func buildOptional(_ component: [AnyView]?) -> [AnyView] {
        component ?? []
    }

    public static func buildEither(first component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildEither(second component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildArray(_ components: [[AnyView]]) -> [AnyView] {
        components.flatMap { $0 }
    }

    public static func buildExpression(_ expression: AnyView) -> [AnyView] {
        [expression]
    }

    public static func buildLimitedAvailability(_ component: [AnyView]) -> [AnyView] {
        component
    }
}
extension ViewNode {
    fileprivate func applyDefaultMinimumHeight(_ minimumHeight: Double) {
        let resolvedMinimumHeight = max(0, minimumHeight)
        let constraints = layoutConstraints ?? .unconstrained
        layoutConstraints = LayoutConstraints(
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth,
            minHeight: max(constraints.minHeight, resolvedMinimumHeight),
            maxHeight: max(constraints.maxHeight, resolvedMinimumHeight)
        )
    }
}
@MainActor
public struct Form: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Form has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let chrome = Self.retainedChrome(for: context.formStyle)
            return Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                borderColor: chrome.borderColor,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                stackLayout: .vertical(spacing: chrome.spacing, padding: chrome.padding, alignment: .stretch),
                isHitTestVisible: false,
                children: content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
        }
    }

    private struct RetainedChrome {
        var spacing: Double
        var padding: EdgeInsets
        var backgroundColor: Color?
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
    }

    private static func retainedChrome(for style: FormStyle) -> RetainedChrome {
        switch style.kind {
        case .automatic:
            return RetainedChrome(
                spacing: 12,
                padding: EdgeInsets.all(12),
                backgroundColor: nil,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0
            )
        case .columns:
            return RetainedChrome(
                spacing: 8,
                padding: EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18),
                backgroundColor: nil,
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 8
            )
        case .grouped:
            return RetainedChrome(
                spacing: 10,
                padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
                backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.62),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 16
            )
        }
    }
}
@MainActor
public struct Section: View {
    public typealias Body = Never

    private let header: [AnyView]
    private let footer: [AnyView]
    private let style: SectionStyle
    private let isExpanded: Binding<Bool>?
    private let content: [AnyView]

    public init(
        _ title: String,
        isExpanded: Binding<Bool>? = nil,
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = [
            AnyView(
                Text(title)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.footer = []
        self.style = style
        self.isExpanded = isExpanded
        self.content = content()
    }

    public init<S: StringProtocol>(
        _ title: S,
        isExpanded: Binding<Bool>? = nil,
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(String(title), isExpanded: isExpanded, style: style, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>? = nil,
        style: SectionStyle = .default,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(titleKey.resolvedString, isExpanded: isExpanded, style: style, content: content)
    }

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.header = []
        self.footer = []
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = []
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder footer: () -> [AnyView]
    ) {
        self.header = []
        self.footer = footer()
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init<Header: View>(
        header: Header,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = [AnyView(header)]
        self.footer = []
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init<Footer: View>(
        footer: Footer,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = []
        self.footer = [AnyView(footer)]
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init<Header: View, Footer: View>(
        header: Header,
        footer: Footer,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.header = [AnyView(header)]
        self.footer = [AnyView(footer)]
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = []
        self.style = .default
        self.isExpanded = isExpanded
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder header: () -> [AnyView],
        @ViewBuilder footer: () -> [AnyView]
    ) {
        self.header = header()
        self.footer = footer()
        self.style = .default
        self.isExpanded = nil
        self.content = content()
    }

    public var body: Never {
        fatalError("Section has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let expansionBinding = isExpanded
        return Component { runtime in
            let headerFont = style.headerFont.resolvedHeaderFont(for: context.headerProminence)
            let headerContext =
                context
                .withForegroundColor(style.headerColor)
                .withFont(headerFont)
                .withTextAlignment(.leading)
                .withLineLimit(1)
            let footerContext =
                context
                .withForegroundColor(.secondary)
                .withFont(.caption)
                .withTextAlignment(.leading)

            let headerNodes = header.map {
                $0.makeComponent(context: headerContext).makeNode(runtime: runtime)
            }
            let resolvedHeaderNodes: [ViewNode]
            if let expansionBinding, !headerNodes.isEmpty {
                let chevronNode = Controls.label(
                    expansionBinding.wrappedValue ? "V" : ">",
                    preferredSize: Size(width: 18, height: 24),
                    color: style.headerColor,
                    scale: 1.2,
                    weight: .semibold,
                    lineBreakMode: .truncateTail,
                    maximumNumberOfLines: 1
                )
                let headerContent = Controls.stackPanel(
                    layoutPriority: 1,
                    stackLayout: .horizontal(
                        spacing: 8, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4), alignment: .center),
                    isHitTestVisible: false,
                    children: [chevronNode] + headerNodes
                )
                let headerButton = Controls.button(
                    runtime: runtime,
                    cornerRadius: 8,
                    palette: ButtonSurfaceStyle.plain.palette,
                    chrome: ButtonSurfaceStyle.plain.chrome,
                    clipsToBounds: false,
                    layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                    isEnabled: context.isEnabled,
                    action: {
                        expansionBinding.wrappedValue.toggle()
                        context.invalidate()
                    },
                    children: [headerContent]
                )
                resolvedHeaderNodes = [headerButton]
            } else {
                resolvedHeaderNodes = headerNodes
            }
            if let minimumHeaderHeight = context.defaultMinListHeaderHeight, minimumHeaderHeight > 0 {
                for headerNode in resolvedHeaderNodes {
                    headerNode.applyDefaultMinimumHeight(minimumHeaderHeight)
                }
            }

            let contentNodes =
                expansionBinding?.wrappedValue == false
                ? []
                : content.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            let children =
                resolvedHeaderNodes + contentNodes
                + footer.map { $0.makeComponent(context: footerContext).makeNode(runtime: runtime) }
            let hidesScrollContentBackground =
                style.scrollAxis != nil
                && context.scrollContentBackgroundVisibility.hidesRetainedScrollContentBackground
            let alignmentAnchor = style.scrollAxis == nil ? nil : context.defaultScrollAnchor(for: .alignment)

            let node = Controls.stackPanel(
                backgroundColor: hidesScrollContentBackground ? nil : style.backgroundColor,
                backgroundGradient: hidesScrollContentBackground ? nil : style.backgroundGradient,
                borderColor: style.borderColor,
                borderWidth: 1,
                shadowColor: style.shadowColor,
                shadowOffset: Point(x: 0, y: 20),
                shadowSpread: 10,
                cornerRadius: style.cornerRadius,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: style.spacing,
                    padding: style.scrollAxis == nil
                        ? style.padding
                        : context.contentInsets(for: .scrollContent, defaultInsets: style.padding),
                    alignment: style.alignment.stackAlignment(layoutDirection: context.layoutDirection),
                    mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
                ),
                isHitTestVisible: style.isHitTestVisible,
                children: children
            )

            if context.isScrollEnabled, let axis = style.scrollAxis {
                node.scrollAxis = axis.scrollAxis
                node.scrollStep = style.scrollStep
                node.showsScrollIndicator = context.scrollIndicatorVisibility(for: axis).showsRetainedScrollIndicator
                node.horizontalScrollBounceBehavior = context.horizontalScrollBounceBehavior.description
                node.verticalScrollBounceBehavior = context.verticalScrollBounceBehavior.description
                node.scrollTargetBehavior = context.scrollTargetBehavior?.description
                node.scrollInputBehaviors = context.retainedScrollInputBehaviors
                node.scrollIndicatorsFlashOnAppear = context.scrollIndicatorsFlashOnAppear
                node.scrollIndicatorsFlashTrigger = context.scrollIndicatorsFlashTrigger
                node.scrollPosition = context.scrollPositionMetadata
                node.scrollIndicatorInsets = context.contentInsets(
                    for: .scrollIndicators,
                    defaultInsets: defaultRetainedScrollIndicatorInsets
                )
                node.initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
                node.scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
                node.scrollIndicatorColor = style.indicatorColor
                node.scrollIndicatorIdleColor = style.indicatorColor
                node.scrollIndicatorHoverColor = style.indicatorHoverColor
                node.scrollIndicatorActiveColor = style.indicatorActiveColor
                node.scrollIndicatorThickness = style.indicatorThickness
            }
            if style.scrollAxis != nil, context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            node.sectionHeaderChildCount = resolvedHeaderNodes.count
            node.sectionFooterChildCount = footer.count

            return node
        }
    }
}
public struct Header<Content: View>: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Header has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: content, context: context, fallbackLayout: .stack(.vertical(alignment: .stretch)))
    }
}
public struct Footer<Content: View>: View {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Footer has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: content, context: context, fallbackLayout: .stack(.vertical(alignment: .stretch)))
    }
}
extension Font {
    fileprivate func resolvedHeaderFont(for prominence: Prominence) -> Font {
        switch prominence {
        case .standard:
            return self
        case .increased:
            return weight(.bold)
        }
    }
}
@MainActor
public struct GroupBox: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.label = []
        self.content = content()
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.content = content()
    }

    public init(
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .font(.system(size: 1.5, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public var body: Never {
        fatalError("GroupBox has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let views = label + content
        return Component { runtime in
            Controls.panel(
                backgroundColor: Color(red: 0.12, green: 0.15, blue: 0.20, alpha: 0.54),
                borderColor: Color(red: 0.78, green: 0.86, blue: 1.0, alpha: 0.14),
                borderWidth: 1,
                cornerRadius: 12,
                layoutMode: .stack(.vertical(spacing: 8, padding: .all(12), alignment: .stretch)),
                isHitTestVisible: false,
                children: views.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
            )
        }
    }
}
@MainActor
public struct DisclosureGroup: View {
    public typealias Body = Never

    private final class ExpansionState {
        var isExpanded = false
    }

    private let isExpanded: Binding<Bool>?
    private let expansionState: ExpansionState
    private let label: [AnyView]
    private let content: [AnyView]

    public init(
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.isExpanded = isExpanded
        self.expansionState = ExpansionState()
        self.label = label()
        self.content = content()
    }

    public init(
        _ title: String,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(isExpanded: isExpanded, content: content) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(
        _ title: S,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(String(title), isExpanded: isExpanded, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(titleKey.resolvedString, isExpanded: isExpanded, content: content)
    }

    public var body: Never {
        fatalError("DisclosureGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let binding = isExpanded
        let fallbackState = expansionState
        let contentViews = content
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let contentComponent = composeComponent(
            from: contentViews,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 6, alignment: .stretch)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let isOpen = binding?.wrappedValue ?? fallbackState.isExpanded
            let chevronNode = Controls.label(
                isOpen ? "V" : ">",
                preferredSize: Size(width: 18, height: 24),
                color: context.foregroundColor,
                scale: 1.3,
                weight: .semibold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let headerContent = Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(
                    spacing: 8, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8), alignment: .center),
                isHitTestVisible: false,
                children: [chevronNode, labelNode]
            )
            let headerButton = Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                clipsToBounds: false,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                action: {
                    if let binding {
                        binding.wrappedValue.toggle()
                    } else {
                        fallbackState.isExpanded.toggle()
                    }
                    context.invalidate()
                },
                children: [headerContent]
            )

            var children: [ViewNode] = [headerButton]
            if isOpen {
                let contentNode = contentComponent.makeNode(runtime: runtime)
                let insetContent = Controls.stackPanel(
                    stackLayout: .vertical(
                        padding: EdgeInsets(top: 2, leading: 34, bottom: 2, trailing: 0), alignment: .stretch),
                    isHitTestVisible: false,
                    children: [contentNode]
                )
                children.append(insetContent)
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 4, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }
}
private final class OutlineExpansionState {
    var isExpanded = false
}
@MainActor
public struct OutlineGroup<Element, ID: Hashable, Content: View>: View {
    public typealias Body = Never

    private let items: [Element]
    private let childrenKeyPath: KeyPath<Element, [Element]?>
    private let content: (Element) -> Content

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        children: KeyPath<Data.Element, [Data.Element]?>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) where Data.Element == Element, Element: Identifiable, Element.ID == ID {
        self.items = Array(data)
        self.childrenKeyPath = children
        self.content = content
    }

    public init(
        _ root: Element,
        children: KeyPath<Element, [Element]?>,
        @ViewBuilder content: @escaping (Element) -> Content
    ) where Element: Identifiable, Element.ID == ID {
        self.items = [root]
        self.childrenKeyPath = children
        self.content = content
    }

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        children: KeyPath<Data.Element, [Data.Element]?>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) where Data.Element == Element {
        self.items = Array(data)
        self.childrenKeyPath = children
        self.content = content
    }

    public init(
        _ root: Element,
        id: KeyPath<Element, ID>,
        children: KeyPath<Element, [Element]?>,
        @ViewBuilder content: @escaping (Element) -> Content
    ) {
        self.items = [root]
        self.childrenKeyPath = children
        self.content = content
    }

    public var body: Never {
        fatalError("OutlineGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Self.makeOutlineComponent(
            items: items,
            childrenKeyPath: childrenKeyPath,
            content: content,
            context: context,
            indentLevel: 0
        )
    }

    private static func makeOutlineComponent(
        items: [Element],
        childrenKeyPath: KeyPath<Element, [Element]?>,
        content: @escaping (Element) -> Content,
        context: ViewBuildContext,
        indentLevel: Int
    ) -> Component {
        let childComponents: [Component] = items.map { item in
            let itemContent = content(item).makeComponent(context: context)
            let childData = item[keyPath: childrenKeyPath]

            if let childData = childData, !childData.isEmpty {
                let expansionState = OutlineExpansionState()
                let labelComponent = itemContent
                let nestedComponent = Self.makeOutlineComponent(
                    items: childData,
                    childrenKeyPath: childrenKeyPath,
                    content: content,
                    context: context,
                    indentLevel: indentLevel + 1
                )

                return Component { runtime in
                    let isExpanded = expansionState.isExpanded
                    let chevronNode = Controls.label(
                        isExpanded ? "V" : ">",
                        preferredSize: Size(width: 18, height: 24),
                        color: context.foregroundColor,
                        scale: 1.3,
                        weight: .semibold,
                        lineBreakMode: .truncateTail,
                        maximumNumberOfLines: 1
                    )
                    let labelNode = labelComponent.makeNode(runtime: runtime)
                    let headerContent = Controls.stackPanel(
                        layoutPriority: 1,
                        stackLayout: .horizontal(
                            spacing: 8, padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                            alignment: .center),
                        isHitTestVisible: false,
                        children: [chevronNode, labelNode]
                    )
                    let headerButton = Controls.button(
                        runtime: runtime,
                        cornerRadius: 8,
                        palette: ButtonSurfaceStyle.plain.palette,
                        chrome: ButtonSurfaceStyle.plain.chrome,
                        clipsToBounds: false,
                        layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                        isEnabled: context.isEnabled,
                        action: {
                            expansionState.isExpanded.toggle()
                            context.invalidate()
                        },
                        children: [headerContent]
                    )

                    var childrenNodes: [ViewNode] = [headerButton]
                    if isExpanded {
                        let contentNode = nestedComponent.makeNode(runtime: runtime)
                        let leadingPadding = Double(indentLevel + 1) * 24.0
                        let insetContent = Controls.stackPanel(
                            stackLayout: .vertical(
                                padding: EdgeInsets(top: 2, leading: leadingPadding, bottom: 2, trailing: 0),
                                alignment: .stretch),
                            isHitTestVisible: false,
                            children: [contentNode]
                        )
                        childrenNodes.append(insetContent)
                    }

                    return Controls.stackPanel(
                        stackLayout: .vertical(spacing: 4, alignment: .stretch),
                        isHitTestVisible: false,
                        children: childrenNodes
                    )
                }
            } else {
                return itemContent
            }
        }

        return Component { runtime in
            let nodes = childComponents.map { $0.makeNode(runtime: runtime) }
            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 4, alignment: .stretch),
                isHitTestVisible: false,
                children: nodes
            )
        }
    }
}
@MainActor
public struct Menu: View {
    public typealias Body = Never

    private final class MenuState {
        var isOpen = false
    }

    private let state = MenuState()
    private let label: [AnyView]
    private let content: [AnyView]
    private let primaryAction: (@MainActor () -> Void)?

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(content: content, label: label, primaryAction: nil)
    }

    public init(
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.label = label()
        self.content = content()
        self.primaryAction = primaryAction
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, content: content, primaryAction: nil)
    }

    public init(
        _ title: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(
            content: content,
            label: {
                Text(title)
                    .font(.system(size: 1.6, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }, primaryAction: primaryAction)
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init<S: StringProtocol>(
        _ title: S,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(String(title), content: content, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, content: content, primaryAction: primaryAction)
    }

    public init(_ title: String, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, image: name, content: content, primaryAction: nil)
    }

    public init(
        _ title: String,
        image name: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(
            content: content,
            label: {
                Label(title, image: name)
            }, primaryAction: primaryAction)
    }

    public init<S: StringProtocol>(_ title: S, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), image: name, content: content)
    }

    public init<S: StringProtocol>(
        _ title: S,
        image name: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(String(title), image: name, content: content, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: name, content: content)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, image: resource, content: content, primaryAction: nil)
    }

    public init<S: StringProtocol>(
        _ title: S,
        image resource: ImageResource,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(
            content: content,
            label: {
                Label(title, image: resource)
            }, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: resource, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image resource: ImageResource,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, image: resource, content: content, primaryAction: primaryAction)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image name: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, image: name, content: content, primaryAction: primaryAction)
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(title, systemImage: systemImage, content: content, primaryAction: nil)
    }

    public init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(
            content: content,
            label: {
                Label(title, systemImage: systemImage)
            }, primaryAction: primaryAction)
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), systemImage: systemImage, content: content)
    }

    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(String(title), systemImage: systemImage, content: content, primaryAction: primaryAction)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, systemImage: systemImage, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> [AnyView],
        primaryAction: (@MainActor () -> Void)?
    ) {
        self.init(titleKey.resolvedString, systemImage: systemImage, content: content, primaryAction: primaryAction)
    }

    public var body: Never {
        fatalError("Menu has no body")
    }

    private func attachMenuDismiss(to node: ViewNode, dismiss: @escaping @MainActor () -> Void) {
        if let activate = node.onActivate {
            node.onActivate = {
                activate()
                dismiss()
            }
        }

        for child in node.children {
            attachMenuDismiss(to: child, dismiss: dismiss)
        }
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let menuState = state
        let menuItems = content
        let primaryAction = primaryAction
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let menuStyle = context.menuStyle
            let menuSurfaceStyle: ButtonSurfaceStyle
            let styleShowsMenuIndicator: Bool
            switch menuStyle.kind {
            case .borderlessButtonStyle(let showsMenuIndicator):
                menuSurfaceStyle = .plain
                styleShowsMenuIndicator = showsMenuIndicator
            case .borderedButtonStyle(let showsMenuIndicator):
                menuSurfaceStyle = .default
                styleShowsMenuIndicator = showsMenuIndicator
            case .automatic, .button:
                menuSurfaceStyle = .default
                styleShowsMenuIndicator = true
            }
            let showsMenuIndicator: Bool
            switch context.environmentValues.menuIndicatorVisibility {
            case .hidden:
                showsMenuIndicator = false
            case .visible:
                showsMenuIndicator = true
            case .automatic:
                showsMenuIndicator = styleShowsMenuIndicator
            }
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let disclosureNode = Controls.label(
                menuState.isOpen ? "V" : ">",
                preferredSize: Size(width: 18, height: 24),
                color: context.foregroundColor,
                scale: 1.2,
                weight: .semibold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            let headerChildren = showsMenuIndicator ? [labelNode, disclosureNode] : [labelNode]
            let headerContent = Controls.stackPanel(
                layoutPriority: 1,
                stackLayout: .horizontal(
                    spacing: 8, padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10), alignment: .center),
                isHitTestVisible: false,
                children: headerChildren
            )
            let menuButton = Controls.button(
                runtime: runtime,
                cornerRadius: menuSurfaceStyle.cornerRadius,
                palette: menuSurfaceStyle.palette,
                chrome: menuSurfaceStyle.chrome,
                clipsToBounds: menuSurfaceStyle.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                animation: menuSurfaceStyle.animation,
                action: {
                    if let primaryAction {
                        primaryAction()
                    } else {
                        menuState.isOpen.toggle()
                    }
                    context.invalidate()
                },
                children: [headerContent]
            )

            let dismissMenu: @MainActor () -> Void = {
                guard menuState.isOpen else {
                    return
                }

                menuState.isOpen = false
                context.invalidate()
            }
            var children: [ViewNode] = [menuButton]
            if menuState.isOpen {
                let itemContext =
                    context
                    .withButtonStyle(.plain)
                    .withEnvironmentValue(\.dismiss, DismissAction(handler: dismissMenu))
                    .withEnvironmentValue(\.isPresented, true)
                let itemNodes = menuItems.map { item -> ViewNode in
                    let node = item.makeComponent(context: itemContext).makeNode(runtime: runtime)
                    attachMenuDismiss(to: node, dismiss: dismissMenu)
                    return node
                }
                let menuPanel = Controls.stackPanel(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.96),
                    borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderWidth: 1,
                    shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.28),
                    shadowOffset: Point(x: 0, y: 10),
                    shadowSpread: 8,
                    cornerRadius: 10,
                    stackLayout: .vertical(
                        spacing: 2, padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6), alignment: .stretch
                    ),
                    isHitTestVisible: false,
                    children: itemNodes
                )
                children.append(menuPanel)
            }

            let root = Controls.panel(
                preferredSize: menuButton.intrinsicContentSize(),
                layoutMode: .absolute,
                isHitTestVisible: false,
                children: children
            )
            root.onLayout = { bounds in
                let buttonSize = menuButton.intrinsicContentSize()
                let buttonFrame = Rect(origin: .zero, size: buttonSize)
                if menuButton.frame != buttonFrame {
                    menuButton.frame = buttonFrame
                }

                guard children.count > 1 else {
                    return
                }

                let panel = children[1]
                let panelSize = panel.intrinsicContentSize()
                let x: Double
                switch context.layoutDirection {
                case .leftToRight:
                    x = 0
                case .rightToLeft:
                    x = max(0, buttonSize.width - panelSize.width)
                }
                let panelFrame = Rect(
                    x: x,
                    y: min(bounds.size.height, buttonSize.height + 4),
                    width: panelSize.width,
                    height: panelSize.height
                )
                if panel.frame != panelFrame {
                    panel.frame = panelFrame
                }
            }

            return root
        }
    }
}
@MainActor
public struct MenuButton<Label: View>: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let action: (@MainActor () -> Void)?

    public init(action: (@MainActor () -> Void)?, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
    }

    public var body: Never {
        fatalError("MenuButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { runtime in
            let labelNode = composeComponent(
                from: label,
                context: context,
                fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
                isHitTestVisible: false
            ).makeNode(runtime: runtime)
            return Controls.button(
                runtime: runtime,
                cornerRadius: 8,
                palette: .default,
                chrome: .default,
                clipsToBounds: true,
                layoutMode: .stack(.horizontal(spacing: 0, alignment: .center)),
                isEnabled: context.isEnabled,
                action: { action?() },
                children: [labelNode]
            )
        }
    }
}
@MainActor
public struct ControlGroup: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.label = []
        self.content = content()
    }

    public init(@ViewBuilder content: () -> [AnyView], @ViewBuilder label: () -> [AnyView]) {
        self.label = label()
        self.content = content()
    }

    public init(_ title: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), content: content)
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, content: content)
    }

    public init(_ title: String, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Label(title, image: name)
        }
    }

    public init<S: StringProtocol>(_ title: S, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), image: name, content: content)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: name, content: content)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Label(title, image: resource)
        }
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, image: resource, content: content)
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(content: content) {
            Label(title, systemImage: systemImage)
        }
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(String(title), systemImage: systemImage, content: content)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> [AnyView]) {
        self.init(titleKey.resolvedString, systemImage: systemImage, content: content)
    }

    public var body: Never {
        fatalError("ControlGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponents = label.map { $0.makeComponent(context: context) }
        let chrome = Self.retainedChrome(for: context.controlGroupStyle, tint: context.tint)
        let controlComponents = content.map {
            $0.makeComponent(context: context.withButtonStyle(chrome.childButtonStyle))
        }

        return Component { runtime in
            var children = labelComponents.map { component in
                let node = component.makeNode(runtime: runtime)
                node.layoutPriority = max(node.layoutPriority, 1)
                return node
            }
            children += controlComponents.map { $0.makeNode(runtime: runtime) }

            return Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                borderColor: chrome.borderColor,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                stackLayout: .horizontal(
                    spacing: chrome.spacing,
                    padding: chrome.padding,
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private struct RetainedChrome {
        var backgroundColor: Color
        var borderColor: Color
        var borderWidth: Double
        var cornerRadius: Double
        var spacing: Double
        var padding: EdgeInsets
        var childButtonStyle: ButtonStyle
    }

    private static func retainedChrome(for style: ControlGroupStyle, tint: Color) -> RetainedChrome {
        switch style.kind {
        case .automatic:
            return RetainedChrome(
                backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.72),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 10,
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
                childButtonStyle: .borderless
            )
        case .compactMenu:
            return RetainedChrome(
                backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.17, alpha: 0.58),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 7,
                spacing: 2,
                padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4),
                childButtonStyle: .borderless
            )
        case .menu:
            return RetainedChrome(
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.64),
                borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.13),
                borderWidth: 1,
                cornerRadius: 12,
                spacing: 5,
                padding: EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7),
                childButtonStyle: .borderless
            )
        case .navigation:
            return RetainedChrome(
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.62),
                borderColor: tint.opacity(0.24),
                borderWidth: 1,
                cornerRadius: 9,
                spacing: 3,
                padding: EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5),
                childButtonStyle: .borderless
            )
        case .palette:
            return RetainedChrome(
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.50),
                borderColor: tint.opacity(0.34),
                borderWidth: 1,
                cornerRadius: 8,
                spacing: 2,
                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                childButtonStyle: .bordered
            )
        }
    }
}
@MainActor
public struct TextField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>
    private let prompt: String?
    private let axis: Axis
    private let label: [AnyView]?
    private let selection: Binding<TextSelection?>?
    private let onEditingChanged: (@MainActor (Bool) -> Void)?
    private let onCommit: (@MainActor () -> Void)?

    public init(_ title: String, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.title = title
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = axis
        self.label = nil
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(String(title), text: text, prompt: prompt, axis: axis)
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(titleKey.resolvedString, text: text, prompt: prompt, axis: axis)
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value>,
        formatter: Formatter,
        prompt: Text? = nil
    ) {
        self.init(
            String(title),
            text: formatterBackedTextBinding(value: value, formatter: formatter),
            prompt: prompt
        )
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value>,
        formatter: Formatter,
        prompt: Text? = nil
    ) {
        self.init(titleKey.resolvedString, value: value, formatter: formatter, prompt: prompt)
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value?>,
        formatter: Formatter,
        prompt: Text? = nil
    ) {
        self.init(
            String(title),
            text: optionalFormatterBackedTextBinding(value: value, formatter: formatter),
            prompt: prompt
        )
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value?>,
        formatter: Formatter,
        prompt: Text? = nil
    ) {
        self.init(titleKey.resolvedString, value: value, formatter: formatter, prompt: prompt)
    }

    public init<S: StringProtocol, F: ParseableFormatStyle>(
        _ title: S,
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil
    ) where F.FormatOutput == String {
        self.init(
            String(title),
            text: parseableFormatBackedTextBinding(value: value, format: format),
            prompt: prompt
        )
    }

    public init<F: ParseableFormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil
    ) where F.FormatOutput == String {
        self.init(titleKey.resolvedString, value: value, format: format, prompt: prompt)
    }

    public init<S: StringProtocol, F: ParseableFormatStyle>(
        _ title: S,
        value: Binding<F.FormatInput?>,
        format: F,
        prompt: Text? = nil
    ) where F.FormatOutput == String {
        self.init(
            String(title),
            text: optionalParseableFormatBackedTextBinding(value: value, format: format),
            prompt: prompt
        )
    }

    public init<F: ParseableFormatStyle>(
        _ titleKey: LocalizedStringKey,
        value: Binding<F.FormatInput?>,
        format: F,
        prompt: Text? = nil
    ) where F.FormatOutput == String {
        self.init(titleKey.resolvedString, value: value, format: format, prompt: prompt)
    }

    public init(
        _ title: String,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis = .horizontal
    ) {
        self.title = title
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = axis
        self.label = nil
        self.selection = selection
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis = .horizontal
    ) {
        self.init(String(title), text: text, selection: selection, prompt: prompt, axis: axis)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis = .horizontal
    ) {
        self.init(titleKey.resolvedString, text: text, selection: selection, prompt: prompt, axis: axis)
    }

    public init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.selection = selection
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<Value>(
        value: Binding<Value>,
        formatter: Formatter,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = formatterBackedTextBinding(value: value, formatter: formatter)
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<Value>(
        value: Binding<Value?>,
        formatter: Formatter,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = optionalFormatterBackedTextBinding(value: value, formatter: formatter)
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<F: ParseableFormatStyle>(
        value: Binding<F.FormatInput>,
        format: F,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) where F.FormatOutput == String {
        self.title = ""
        self.text = parseableFormatBackedTextBinding(value: value, format: format)
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<F: ParseableFormatStyle>(
        value: Binding<F.FormatInput?>,
        format: F,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) where F.FormatOutput == String {
        self.title = ""
        self.text = optionalParseableFormatBackedTextBinding(value: value, format: format)
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = .horizontal
        self.label = label()
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = axis
        self.label = label()
        self.selection = selection
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        axis: Axis,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.axis = axis
        self.label = label()
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.title = String(title)
        self.text = text
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.selection = nil
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            titleKey.resolvedString,
            text: text,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value>,
        formatter: Formatter,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.title = String(title)
        self.text = formatterBackedTextBinding(value: value, formatter: formatter)
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.selection = nil
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value>,
        formatter: Formatter,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            titleKey.resolvedString,
            value: value,
            formatter: formatter,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value?>,
        formatter: Formatter,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.title = String(title)
        self.text = optionalFormatterBackedTextBinding(value: value, formatter: formatter)
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.selection = nil
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value?>,
        formatter: Formatter,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            titleKey.resolvedString,
            value: value,
            formatter: formatter,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.title = String(title)
        self.text = text
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = onCommit
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, text: text, onCommit: onCommit)
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value>,
        formatter: Formatter,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.title = String(title)
        self.text = formatterBackedTextBinding(value: value, formatter: formatter)
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = onCommit
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value>,
        formatter: Formatter,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, value: value, formatter: formatter, onCommit: onCommit)
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value?>,
        formatter: Formatter,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.title = String(title)
        self.text = optionalFormatterBackedTextBinding(value: value, formatter: formatter)
        self.prompt = nil
        self.axis = .horizontal
        self.label = nil
        self.selection = nil
        self.onEditingChanged = nil
        self.onCommit = onCommit
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value?>,
        formatter: Formatter,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, value: value, formatter: formatter, onCommit: onCommit)
    }

    public var body: Never {
        fatalError("TextField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let allowsNewlines: Bool
        switch axis {
        case .horizontal:
            allowsNewlines = false
        case .vertical:
            allowsNewlines = true
        }
        return textInputComponent(
            title: label == nil ? (prompt ?? title) : prompt,
            text: text,
            isSecure: false,
            allowsNewlines: allowsNewlines,
            preferredSize: allowsNewlines
                ? context.controlSize.multilineTextInputSize : context.controlSize.singleLineTextInputSize,
            label: label,
            selection: selection,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit,
            context: context
        )
    }
}
@MainActor
public struct SecureField: View {
    public typealias Body = Never

    private let title: String
    private let text: Binding<String>
    private let prompt: String?
    private let label: [AnyView]?
    private let onCommit: (@MainActor () -> Void)?

    public init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
        self.title = title
        self.text = text
        self.prompt = prompt?.plainContent
        self.label = nil
        self.onCommit = nil
    }

    public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) {
        self.init(String(title), text: text, prompt: prompt)
    }

    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) {
        self.init(titleKey.resolvedString, text: text, prompt: prompt)
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.title = ""
        self.text = text
        self.prompt = prompt?.plainContent
        self.label = label()
        self.onCommit = nil
    }

    public init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.title = String(title)
        self.text = text
        self.prompt = nil
        self.label = nil
        self.onCommit = onCommit
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        onCommit: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, text: text, onCommit: onCommit)
    }

    public var body: Never {
        fatalError("SecureField has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        textInputComponent(
            title: label == nil ? (prompt ?? title) : prompt,
            text: text,
            isSecure: true,
            allowsNewlines: false,
            preferredSize: context.controlSize.singleLineTextInputSize,
            label: label,
            selection: nil,
            onEditingChanged: nil,
            onCommit: onCommit,
            context: context
        )
    }
}
@MainActor
public struct TextEditor: View {
    public typealias Body = Never

    private let text: Binding<String>
    private let selection: Binding<TextSelection?>?

    public init(text: Binding<String>, selection: Binding<TextSelection?>? = nil) {
        self.text = text
        self.selection = selection
    }

    public var body: Never {
        fatalError("TextEditor has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        textInputComponent(
            title: nil,
            text: text,
            isSecure: false,
            allowsNewlines: true,
            preferredSize: context.controlSize.multilineTextInputSize,
            label: nil,
            selection: selection,
            onEditingChanged: nil,
            onCommit: nil,
            context: context
        )
    }
}
@MainActor
private func formatterBackedTextBinding<Value>(
    value: Binding<Value>,
    formatter: Formatter
) -> Binding<String> {
    Binding<String>(
        get: {
            formatter.string(for: value.wrappedValue) ?? String(describing: value.wrappedValue)
        },
        set: { text in
            if let parsedValue: Value = parsedFormatterValue(text, formatter: formatter) {
                value.wrappedValue = parsedValue
            }
        }
    )
}
@MainActor
private func optionalFormatterBackedTextBinding<Value>(
    value: Binding<Value?>,
    formatter: Formatter
) -> Binding<String> {
    Binding<String>(
        get: {
            value.wrappedValue.flatMap { formatter.string(for: $0) } ?? ""
        },
        set: { text in
            if text.isEmpty {
                value.wrappedValue = nil
                return
            }
            if let parsedValue: Value = parsedFormatterValue(text, formatter: formatter) {
                value.wrappedValue = parsedValue
            }
        }
    )
}
private func parsedFormatterValue<Value>(_ text: String, formatter: Formatter) -> Value? {
    if Value.self == String.self {
        return text as? Value
    }

    if let numberFormatter = formatter as? NumberFormatter,
        let number = numberFormatter.number(from: text),
        let value: Value = convertedFormatterValue(number)
    {
        return value
    }

    if let dateFormatter = formatter as? DateFormatter,
        let date = dateFormatter.date(from: text) as? Value
    {
        return date
    }

    return nil
}
@MainActor
private func parseableFormatBackedTextBinding<F: ParseableFormatStyle>(
    value: Binding<F.FormatInput>,
    format: F
) -> Binding<String> where F.FormatOutput == String {
    Binding<String>(
        get: {
            format.format(value.wrappedValue)
        },
        set: { text in
            if let parsed = try? format.parseStrategy.parse(text) {
                value.wrappedValue = parsed
            }
        }
    )
}
@MainActor
private func optionalParseableFormatBackedTextBinding<F: ParseableFormatStyle>(
    value: Binding<F.FormatInput?>,
    format: F
) -> Binding<String> where F.FormatOutput == String {
    Binding<String>(
        get: {
            value.wrappedValue.map { format.format($0) } ?? ""
        },
        set: { text in
            value.wrappedValue = try? format.parseStrategy.parse(text)
        }
    )
}
private func convertedFormatterValue<Value>(_ object: Any) -> Value? {
    if let value = object as? Value {
        return value
    }

    guard let number = object as? NSNumber else {
        return nil
    }

    switch Value.self {
    case is Int.Type:
        return number.intValue as? Value
    case is Int8.Type:
        return number.int8Value as? Value
    case is Int16.Type:
        return number.int16Value as? Value
    case is Int32.Type:
        return number.int32Value as? Value
    case is Int64.Type:
        return number.int64Value as? Value
    case is UInt.Type:
        return number.uintValue as? Value
    case is UInt8.Type:
        return number.uint8Value as? Value
    case is UInt16.Type:
        return number.uint16Value as? Value
    case is UInt32.Type:
        return number.uint32Value as? Value
    case is UInt64.Type:
        return number.uint64Value as? Value
    case is Float.Type:
        return number.floatValue as? Value
    case is Double.Type:
        return number.doubleValue as? Value
    case is Decimal.Type:
        return number.decimalValue as? Value
    default:
        return nil
    }
}
extension View {
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic
    ) -> some View {
        searchable(text: text, placement: placement, prompt: "Search")
    }

    public func searchable<S: StringProtocol>(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: S
    ) -> some View {
        ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: nil,
                prompt: String(prompt),
                placement: placement
            )
        }
    }

    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, placement: placement, prompt: prompt.resolvedString)
    }

    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text
    ) -> some View {
        searchable(text: text, placement: placement, prompt: prompt.plainContent)
    }

    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: "Search")
    }

    public func searchable<S: StringProtocol>(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: S
    ) -> some View {
        ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: isPresented,
                prompt: String(prompt),
                placement: placement
            )
        }
    }

    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt.resolvedString)
    }

    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt.plainContent)
    }

    public func searchable<T>(
        text: Binding<String>,
        tokens: Binding<[T]>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search",
        @ViewBuilder token: @escaping (T) -> [AnyView]
    ) -> some View {
        searchable(text: text, placement: placement, prompt: prompt)
    }

    public func searchable<T>(
        text: Binding<String>,
        tokens: Binding<[T]>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search",
        @ViewBuilder token: @escaping (T) -> [AnyView]
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt)
    }

    public func searchable<T>(
        text: Binding<String>,
        tokens: Binding<[T]>,
        suggestedTokens: Binding<[T]>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search",
        @ViewBuilder token: @escaping (T) -> [AnyView]
    ) -> some View {
        let _ = suggestedTokens
        return searchable(text: text, placement: placement, prompt: prompt)
    }

    public func searchable<T>(
        text: Binding<String>,
        tokens: Binding<[T]>,
        suggestedTokens: Binding<[T]>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search",
        @ViewBuilder token: @escaping (T) -> [AnyView]
    ) -> some View {
        let _ = suggestedTokens
        return searchable(text: text, isPresented: isPresented, placement: placement, prompt: prompt)
    }

    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search",
        @ViewBuilder suggestions: @escaping () -> [AnyView]
    ) -> some View {
        searchable(text: text, placement: placement, prompt: prompt)
    }

    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text,
        @ViewBuilder suggestions: @escaping () -> [AnyView]
    ) -> some View {
        return searchable(text: text, placement: placement, prompt: prompt)
    }

    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: String = "Search",
        @ViewBuilder suggestions: @escaping () -> [AnyView]
    ) -> some View {
        let _ = suggestions
        return ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: isPresented,
                prompt: prompt,
                placement: placement
            )
        }
    }

    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        suggestionsPlacement: SearchSuggestionsPlacement = .automatic,
        prompt: String = "Search"
    ) -> some View {
        let _ = suggestionsPlacement
        return ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: nil,
                prompt: prompt,
                placement: placement
            )
        }
    }

    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        suggestionsPlacement: SearchSuggestionsPlacement = .automatic,
        prompt: String = "Search"
    ) -> some View {
        let _ = suggestionsPlacement
        return ModifiedView(content: self) { content, context in
            searchableComponent(
                content: content,
                context: context,
                text: text,
                isPresented: isPresented,
                prompt: prompt,
                placement: placement
            )
        }
    }

    public func searchSuggestions(@ViewBuilder _ suggestions: @escaping () -> [AnyView]) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.searchSuggestions, suggestions()))
        }
    }

    public func searchSuggestions<Data: RandomAccessCollection>(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> [AnyView]
    ) -> some View where Data.Element: Identifiable {
        searchSuggestions {
            ForEach(data, content: content)
        }
    }

    public func searchPresentationBehavior(_ behavior: SearchPresentationBehavior) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
    }

    public func searchCompletion(_ completion: String) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.searchCompletion, completion))
        }
    }

    public func searchScopes<V: Hashable>(
        _ scope: Binding<V>,
        activation: SearchScopeActivation = .automatic,
        @ViewBuilder scopes: @escaping () -> [AnyView]
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let scopeViews = scopes()
            let child = content.makeComponent(context: context.withEnvironmentValue(\.searchSuggestions, scopeViews))
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return childNode
            }
        }
    }

    public func searchFocused(_ isFocused: FocusState<Bool>.Binding) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isFocusable = true
                return childNode
            }
        }
    }

    public func searchPresentationDestination<Destination: View>(@ViewBuilder destination: @escaping () -> Destination)
        -> some View
    {
        ModifiedView(content: self) { content, context in
            let _ = destination()
            return content.makeComponent(context: context)
        }
    }

    public func searchPresentationToolbarBehavior(_ behavior: SearchPresentationToolbarBehavior) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
    }
}
@MainActor
private func searchableComponent<Content: View>(
    content: Content,
    context: ViewBuildContext,
    text: Binding<String>,
    isPresented: Binding<Bool>?,
    prompt: String,
    placement: SearchFieldPlacement
) -> Component {
    let isSearching = isPresented?.wrappedValue ?? !text.wrappedValue.isEmpty
    let title = prompt.isEmpty ? "Search" : prompt
    let dismissSearch = DismissSearchAction {
        let isCurrentlySearching = isPresented?.wrappedValue ?? !text.wrappedValue.isEmpty
        guard isCurrentlySearching else {
            return
        }

        if !text.wrappedValue.isEmpty {
            text.wrappedValue = ""
        }
        if let isPresented, isPresented.wrappedValue {
            isPresented.wrappedValue = false
        }
        context.invalidate()
    }

    let searchContext =
        context
        .withEnvironmentValue(\.isSearching, isSearching)
        .withEnvironmentValue(\.dismissSearch, dismissSearch)
    let searchField = TextField(title, text: text)
        .submitLabel(.search)
        .makeComponent(context: searchContext)
    let child = content.makeComponent(context: searchContext)

    return Component { runtime in
        var children: [ViewNode] = []
        let showsSearchField = isPresented?.wrappedValue ?? true
        if showsSearchField {
            let searchNode = searchField.makeNode(runtime: runtime)
            applySearchPlacementChrome(to: searchNode, placement: placement, context: context)
            searchNode.textInputDictationBehavior = context.searchDictationBehavior?.retainedBehavior
            let existingOnFocusEnter = searchNode.onFocusEnter
            searchNode.onFocusEnter = {
                existingOnFocusEnter?()
                guard let isPresented, !isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = true
                context.invalidate()
            }
            let existingOnFocusExit = searchNode.onFocusExit
            searchNode.onFocusExit = {
                existingOnFocusExit?()
                applySearchPlacementChrome(to: searchNode, placement: placement, context: context)
            }
            children.append(searchNode)
        }

        children.append(child.makeNode(runtime: runtime))
        return Controls.stackPanel(
            stackLayout: .vertical(spacing: 8, alignment: .stretch),
            children: children
        )
    }
}
private struct RetainedSearchChrome {
    var nodeTag: String
    var preferredSize: Size?
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: Double
    var cornerRadius: Double
}
@MainActor
private func applySearchPlacementChrome(
    to node: ViewNode,
    placement: SearchFieldPlacement,
    context: ViewBuildContext
) {
    guard let chrome = retainedSearchChrome(for: placement, context: context) else {
        return
    }

    node.nodeTag = chrome.nodeTag
    node.preferredSize = chrome.preferredSize ?? node.preferredSize
    node.backgroundColor = chrome.backgroundColor
    node.borderColor = chrome.borderColor
    node.borderWidth = chrome.borderWidth
    node.cornerRadius = chrome.cornerRadius
}
@MainActor
private func retainedSearchChrome(
    for placement: SearchFieldPlacement,
    context: ViewBuildContext
) -> RetainedSearchChrome? {
    if placement == .toolbar {
        return RetainedSearchChrome(
            nodeTag: "search-field-toolbar",
            preferredSize: Size(width: 240, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.92),
            borderColor: context.tint.opacity(0.26),
            borderWidth: 1,
            cornerRadius: 12
        )
    }

    if placement == .sidebar {
        return RetainedSearchChrome(
            nodeTag: "search-field-sidebar",
            preferredSize: Size(width: 210, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.17, alpha: 0.72),
            borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.10),
            borderWidth: 1,
            cornerRadius: 8
        )
    }

    let isNavigationDrawer =
        placement == .navigationBarDrawer
        || placement == .navigationBarDrawer(displayMode: .automatic)
        || placement == .navigationBarDrawer(displayMode: .always)
    if isNavigationDrawer {
        return RetainedSearchChrome(
            nodeTag: "search-field-navigation-drawer",
            preferredSize: Size(width: 280, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.84),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            borderWidth: 1,
            cornerRadius: 10
        )
    }

    return nil
}
extension ControlSize {
    fileprivate var singleLineTextInputSize: Size {
        switch self {
        case .mini:
            return Size(width: 180, height: 28)
        case .small:
            return Size(width: 200, height: 32)
        case .regular:
            return Size(width: 220, height: 36)
        case .large:
            return Size(width: 260, height: 44)
        case .extraLarge:
            return Size(width: 300, height: 52)
        }
    }

    fileprivate var multilineTextInputSize: Size {
        switch self {
        case .mini:
            return Size(width: 220, height: 88)
        case .small:
            return Size(width: 240, height: 104)
        case .regular:
            return Size(width: 260, height: 120)
        case .large:
            return Size(width: 300, height: 144)
        case .extraLarge:
            return Size(width: 340, height: 168)
        }
    }

    fileprivate var togglePreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 44, height: 28)
        case .small:
            return Size(width: 48, height: 30)
        case .regular:
            return Size(width: 52, height: 32)
        case .large:
            return Size(width: 60, height: 38)
        case .extraLarge:
            return Size(width: 68, height: 44)
        }
    }

    fileprivate var pickerMenuPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 160, height: 30)
        case .small:
            return Size(width: 180, height: 32)
        case .regular:
            return Size(width: 200, height: 36)
        case .large:
            return Size(width: 232, height: 44)
        case .extraLarge:
            return Size(width: 264, height: 52)
        }
    }

    fileprivate var stepperButtonPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 28, height: 24)
        case .small:
            return Size(width: 30, height: 26)
        case .regular:
            return Size(width: 34, height: 30)
        case .large:
            return Size(width: 40, height: 36)
        case .extraLarge:
            return Size(width: 46, height: 42)
        }
    }

    fileprivate var sliderPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 160, height: 22)
        case .small:
            return Size(width: 180, height: 24)
        case .regular:
            return Size(width: 200, height: 28)
        case .large:
            return Size(width: 240, height: 34)
        case .extraLarge:
            return Size(width: 280, height: 40)
        }
    }

    fileprivate var progressPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 160, height: 5)
        case .small:
            return Size(width: 180, height: 6)
        case .regular:
            return Size(width: 200, height: 8)
        case .large:
            return Size(width: 240, height: 10)
        case .extraLarge:
            return Size(width: 280, height: 12)
        }
    }

    fileprivate var circularProgressPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 18, height: 18)
        case .small:
            return Size(width: 22, height: 22)
        case .regular:
            return Size(width: 28, height: 28)
        case .large:
            return Size(width: 34, height: 34)
        case .extraLarge:
            return Size(width: 40, height: 40)
        }
    }

    fileprivate var colorSwatchPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 28, height: 22)
        case .small:
            return Size(width: 30, height: 24)
        case .regular:
            return Size(width: 34, height: 28)
        case .large:
            return Size(width: 40, height: 34)
        case .extraLarge:
            return Size(width: 46, height: 40)
        }
    }
}
@MainActor
private func textInputComponent(
    title: String?,
    text: Binding<String>,
    isSecure: Bool,
    allowsNewlines: Bool,
    preferredSize: Size,
    label: [AnyView]?,
    selection: Binding<TextSelection?>?,
    onEditingChanged: (@MainActor (Bool) -> Void)?,
    onCommit: (@MainActor () -> Void)?,
    context: ViewBuildContext
) -> Component {
    let binding = text
    let placeholder = title
    let labelViews = label
    return Component { runtime in
        let currentText = binding.wrappedValue
        let isShowingPlaceholder = currentText.isEmpty
        let resolvedPlaceholder =
            placeholder
            ?? labelViews.flatMap { retainedPlainText(from: $0, context: context, runtime: runtime) }
        let displayText =
            isSecure && !isShowingPlaceholder ? String(repeating: "*", count: currentText.count) : currentText
        let textColor: Color
        if !context.isEnabled {
            textColor = Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.78)
        } else if isShowingPlaceholder {
            textColor = Color(red: 0.70, green: 0.74, blue: 0.80, alpha: 0.84)
        } else {
            textColor = context.foregroundColor
        }

        let resolvedFont = (context.fontWeight.map { context.font.weight($0) } ?? context.font)
            .scaled(for: context.dynamicTypeSize)
            .scaled(by: context.textScale)

        let labelNode = Controls.label(
            isShowingPlaceholder ? (resolvedPlaceholder ?? "") : displayText,
            color: textColor,
            scale: resolvedFont.resolvedScale,
            weight: resolvedFont.weight.textWeight,
            isItalic: resolvedFont.isItalic || context.isFontItalic,
            monospacedDigits: resolvedFont.usesMonospacedDigits || context.usesMonospacedDigits,
            lowercaseSmallCaps: resolvedFont.usesLowercaseSmallCaps,
            uppercaseSmallCaps: resolvedFont.usesUppercaseSmallCaps,
            fontFamily: resolvedFont.resolvedFamily,
            nativeFontSize: resolvedFont.resolvedNativeTextSize,
            fontWidth: resolvedFont.width.retainedTextFontWidth,
            alignment: context.textAlignment.textAlignment(layoutDirection: context.layoutDirection),
            insets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
            letterSpacing: context.letterSpacing ?? 1,
            lineSpacing: context.lineSpacing ?? resolvedFont.resolvedLineSpacing,
            lineBreakMode: allowsNewlines ? .wrap : .truncateTail,
            maximumNumberOfLines: allowsNewlines ? nil : 1
        )
        if let baselineOffset = context.baselineOffset, baselineOffset != 0 {
            labelNode.transform = labelNode.transform.concatenating(.translation(x: 0, y: -Double(baselineOffset)))
        }
        let style = context.textFieldStyle.resolvedTextInputStyle(isEnabled: context.isEnabled)
        let node = Controls.stackPanel(
            preferredSize: preferredSize,
            backgroundColor: style.backgroundColor,
            borderColor: style.borderColor,
            borderWidth: style.borderWidth,
            cornerRadius: style.cornerRadius,
            stackLayout: .vertical(padding: style.padding, alignment: .stretch),
            isHitTestVisible: context.isEnabled,
            children: [labelNode]
        )
        node.textInputSubmitLabel = context.submitLabel.retainedSubmitLabel
        let selectionValue = selection?.wrappedValue
        node.textInputCaretOffset = selectionValue?.caretOffset(in: currentText) ?? currentText.count
        node.textSelectionAffinity = context.textSelectionAffinity.retainedAffinity
        node.textInputSelection = selectionValue?.retainedSelection(in: currentText)
        node.textContentType = context.textContentType?.retainedContentType
        node.textInputKeyboardType = context.keyboardType.retainedKeyboardType
        node.textInputSuggestions = retainedTextInputSuggestions(
            from: context.textInputSuggestions,
            context: context,
            runtime: runtime
        )
        node.writingToolsBehavior = context.writingToolsBehavior?.retainedBehavior
        node.writingToolsAffordanceVisibility =
            context.writingToolsAffordanceVisibility.retainedWritingToolsAffordanceVisibility
        node.isFindDisabled = context.isFindDisabled
        node.isReplaceDisabled = context.isReplaceDisabled
        node.isFindNavigatorPresented = context.isFindNavigatorPresented

        guard context.isEnabled else {
            return node
        }

        node.isFocusable = true
        node.onFocusEnter = { [weak node] in
            node?.borderColor = context.tint
            node?.outlineColor = context.tint.opacity(0.28)
            node?.outlineWidth = 2
            onEditingChanged?(true)
        }
        node.onFocusExit = { [weak node] in
            node?.borderColor = style.borderColor
            node?.outlineColor = .clear
            node?.outlineWidth = 0
            onEditingChanged?(false)
        }
        node.onKeyDown = { event in
            let clampedCaret = clampedTextOffset(node.textInputCaretOffset, in: binding.wrappedValue)
            let selectedRange = selection?.wrappedValue?.editableSelectedOffsetRange(in: binding.wrappedValue)
            @MainActor func setCaretOffset(_ offset: Int) {
                let clampedOffset = clampedTextOffset(offset, in: binding.wrappedValue)
                node.textInputCaretOffset = clampedOffset
                if let selection {
                    let nextSelection = TextSelection.insertion(
                        at: clampedOffset,
                        in: binding.wrappedValue,
                        affinity: context.textSelectionAffinity
                    )
                    selection.wrappedValue = nextSelection
                    node.textInputSelection = nextSelection.retainedSelection(in: binding.wrappedValue)
                } else {
                    node.textInputSelection = nil
                }
            }

            if event.key == .enter, !allowsNewlines {
                if let onCommit {
                    onCommit()
                    context.invalidate()
                }
                return
            }

            if event.key == .backspace {
                if let selectedRange {
                    binding.wrappedValue = binding.wrappedValue.removingText(in: selectedRange)
                    setCaretOffset(selectedRange.lowerBound)
                    context.invalidate()
                    return
                }

                guard clampedCaret > 0 else {
                    return
                }

                let updatedText = binding.wrappedValue.removingText(
                    in: (clampedCaret - 1)..<clampedCaret
                )
                binding.wrappedValue = updatedText
                setCaretOffset(clampedCaret - 1)
                context.invalidate()
                return
            }

            if event.key == .deleteForward {
                if let selectedRange {
                    binding.wrappedValue = binding.wrappedValue.removingText(in: selectedRange)
                    setCaretOffset(selectedRange.lowerBound)
                    context.invalidate()
                    return
                }

                guard clampedCaret < binding.wrappedValue.count else {
                    return
                }

                binding.wrappedValue = binding.wrappedValue.removingText(
                    in: clampedCaret..<(clampedCaret + 1)
                )
                setCaretOffset(clampedCaret)
                context.invalidate()
                return
            }

            switch event.key {
            case .leftArrow:
                setCaretOffset(max(0, clampedCaret - 1))
                context.invalidate()
                return
            case .rightArrow:
                setCaretOffset(min(binding.wrappedValue.count, clampedCaret + 1))
                context.invalidate()
                return
            case .home:
                setCaretOffset(0)
                context.invalidate()
                return
            case .end:
                setCaretOffset(binding.wrappedValue.count)
                context.invalidate()
                return
            case .backspace, .deleteForward:
                return
            case nil, .tab, .enter, .shift, .control, .alt, .escape, .pageUp, .pageDown, .upArrow, .downArrow, .space,
                .mediaPlayPause:
                break
            }

            let replacementRange = selectedRange ?? (clampedCaret..<clampedCaret)
            guard
                let character = textFieldInsertedCharacter(
                    for: event,
                    allowsNewlines: allowsNewlines,
                    currentText: binding.wrappedValue.textPrefix(upTo: replacementRange.lowerBound),
                    textInputAutocapitalization: context.textInputAutocapitalization
                )
            else {
                return
            }

            binding.wrappedValue = binding.wrappedValue.replacingText(in: replacementRange, with: character)
            setCaretOffset(replacementRange.lowerBound + character.count)
            context.invalidate()
        }

        return node
    }
}
@MainActor
private func retainedTextInputSuggestions(
    from views: [AnyView]?,
    context: ViewBuildContext,
    runtime: RetainedViewRuntime
) -> [RetainedTextInputSuggestion] {
    guard let views, !views.isEmpty else {
        return []
    }

    let suggestionContext = context.withEnvironmentValue(\.textInputSuggestions, Optional<[AnyView]>.none)
    var suggestions: [RetainedTextInputSuggestion] = []
    for view in views {
        let node = view.makeComponent(context: suggestionContext).makeNode(runtime: runtime)
        appendRetainedTextInputSuggestions(from: node, to: &suggestions)
    }
    return suggestions
}
@MainActor
private func appendRetainedTextInputSuggestions(
    from node: ViewNode,
    to suggestions: inout [RetainedTextInputSuggestion]
) {
    if node.sectionHeaderChildCount > 0 || node.sectionFooterChildCount > 0 {
        let lowerBound = min(node.sectionHeaderChildCount, node.children.count)
        let upperBound = max(lowerBound, node.children.count - node.sectionFooterChildCount)
        for child in node.children[lowerBound..<upperBound] {
            appendRetainedTextInputSuggestions(from: child, to: &suggestions)
        }
        return
    }

    if let displayText = firstRetainedText(in: node), !displayText.isEmpty {
        suggestions.append(
            RetainedTextInputSuggestion(
                displayText: displayText,
                completion: firstTextInputCompletion(in: node)
            )
        )
        return
    }

    for child in node.children {
        appendRetainedTextInputSuggestions(from: child, to: &suggestions)
    }
}
@MainActor
private func firstTextInputCompletion(in node: ViewNode) -> String? {
    if let completion = node.textInputCompletion {
        return completion
    }
    for child in node.children {
        if let completion = firstTextInputCompletion(in: child) {
            return completion
        }
    }
    return nil
}
@MainActor
private func retainedPlainText(
    from views: [AnyView],
    context: ViewBuildContext,
    runtime: RetainedViewRuntime
) -> String? {
    for view in views {
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        if let text = firstRetainedText(in: node), !text.isEmpty {
            return text
        }
    }
    return nil
}
@MainActor
private func firstRetainedText(in node: ViewNode) -> String? {
    let candidates = retainedTextCandidates(in: node)
    return candidates.preferred ?? candidates.fallback
}
@MainActor
private func retainedTextCandidates(in node: ViewNode) -> (preferred: String?, fallback: String?) {
    var fallback: String?
    if let text = node.text, !text.isEmpty {
        if node.textStyle.fontFamily != "Segoe Fluent Icons" {
            return (text, nil)
        }
        fallback = text
    }
    for child in node.children {
        let childCandidates = retainedTextCandidates(in: child)
        if let preferred = childCandidates.preferred {
            return (preferred, fallback ?? childCandidates.fallback)
        }
        fallback = fallback ?? childCandidates.fallback
    }
    return (nil, fallback)
}
public struct DatePickerComponents: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 0)
    public static let date = DatePickerComponents(rawValue: 1 << 1)
    public static let all: DatePickerComponents = [.date, .hourAndMinute]
}
private struct DatePickerRange: Sendable {
    var lowerBound: Date?
    var upperBound: Date?
    var includesUpperBound: Bool

    static let unbounded = DatePickerRange(
        lowerBound: nil,
        upperBound: nil,
        includesUpperBound: true
    )

    init(
        lowerBound: Date? = nil,
        upperBound: Date? = nil,
        includesUpperBound: Bool = true
    ) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.includesUpperBound = includesUpperBound
    }

    func contains(_ date: Date) -> Bool {
        if let lowerBound, date < lowerBound {
            return false
        }
        if let upperBound {
            return includesUpperBound ? date <= upperBound : date < upperBound
        }
        return true
    }
}
@MainActor
public struct DatePicker: View {
    public typealias Body = Never

    private let selection: Binding<Date>
    private let displayedComponents: DatePickerComponents
    private let label: [AnyView]
    private let range: DatePickerRange

    public init(
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(selection: selection, displayedComponents: displayedComponents, range: .unbounded, label: label)
    }

    private init(
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents,
        range: DatePickerRange,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.displayedComponents = displayedComponents
        self.label = label()
        self.range = range
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(lowerBound: range.lowerBound, upperBound: range.upperBound),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(lowerBound: range.lowerBound),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(upperBound: range.upperBound),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public init(
        selection: Binding<Date>,
        in range: PartialRangeUpTo<Date>,
        displayedComponents: DatePickerComponents = .all,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(
            selection: selection,
            displayedComponents: displayedComponents,
            range: DatePickerRange(upperBound: range.upperBound, includesUpperBound: false),
            label: label
        )
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeUpTo<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(selection: selection, in: range, displayedComponents: displayedComponents) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeUpTo<Date>,
        displayedComponents: DatePickerComponents = .all
    ) {
        self.init(titleKey.resolvedString, selection: selection, in: range, displayedComponents: displayedComponents)
    }

    public var body: Never {
        fatalError("DatePicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelViews = label
        let selection = selection
        let displayedComponents = displayedComponents
        let range = range
        let environmentValues = context.environmentValues
        let datePickerStyle = context.datePickerStyle
        var interactionCalendar = environmentValues.calendar
        interactionCalendar.timeZone = environmentValues.timeZone
        let labelComponent = composeComponent(
            from: labelViews,
            context:
                context
                .withForegroundColor(.secondary)
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let valueNode = Text(
                Self.formattedValue(
                    selection.wrappedValue,
                    components: displayedComponents,
                    calendar: environmentValues.calendar,
                    timeZone: environmentValues.timeZone,
                    locale: environmentValues.locale
                )
            )
            .monospaced()
            .lineLimit(1)
            .makeComponent(
                context:
                    context
                    .withTextAlignment(.trailing)
                    .withLineLimit(1)
            )
            .makeNode(runtime: runtime)
            valueNode.layoutPriority = max(valueNode.layoutPriority, 1)
            let controlNode = Self.retainedValueControl(
                for: valueNode,
                style: datePickerStyle,
                context: context
            )

            guard !context.labelsHidden, !labelViews.isEmpty else {
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    range: range,
                    components: displayedComponents,
                    calendar: interactionCalendar,
                    isEnabled: context.isEnabled,
                    invalidate: context.invalidate
                )
                return controlNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            let node = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [labelNode, controlNode]
            )
            Self.configureInteraction(
                on: node,
                selection: selection,
                range: range,
                components: displayedComponents,
                calendar: interactionCalendar,
                isEnabled: context.isEnabled,
                invalidate: context.invalidate
            )
            return node
        }
    }

    private static func retainedValueControl(
        for valueNode: ViewNode,
        style: DatePickerStyle,
        context: ViewBuildContext
    ) -> ViewNode {
        switch style.kind {
        case .automatic:
            return valueNode
        case .compact:
            let disclosureNode = Controls.icon(
                .chevronDown,
                preferredSize: Size(width: 14, height: 14),
                color: context.foregroundColor.opacity(context.isEnabled ? 0.78 : 0.45),
                scale: 1.1
            )
            return Controls.stackPanel(
                preferredSize: context.controlSize.singleLineTextInputSize,
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.17, alpha: context.isEnabled ? 0.64 : 0.34),
                borderColor: context.tint.opacity(context.isEnabled ? 0.32 : 0.16),
                borderWidth: 1,
                cornerRadius: 8,
                stackLayout: .horizontal(
                    spacing: 8,
                    padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 8),
                    alignment: .center
                ),
                isHitTestVisible: context.isEnabled,
                children: [valueNode, disclosureNode]
            )
        case .field:
            return Controls.stackPanel(
                preferredSize: context.controlSize.singleLineTextInputSize,
                backgroundColor: Color(red: 0.05, green: 0.07, blue: 0.10, alpha: context.isEnabled ? 0.52 : 0.28),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.22 : 0.10),
                borderWidth: 1,
                cornerRadius: 3,
                stackLayout: .vertical(
                    padding: EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9),
                    alignment: .stretch
                ),
                isHitTestVisible: context.isEnabled,
                children: [valueNode]
            )
        case .stepperField:
            let stepperNode = Controls.stackPanel(
                preferredSize: Size(width: 22, height: context.controlSize.singleLineTextInputSize.height),
                backgroundColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.08 : 0.04),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: 4,
                stackLayout: .vertical(
                    spacing: 0,
                    padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: [
                    Controls.label(
                        "+", color: context.foregroundColor.opacity(context.isEnabled ? 0.70 : 0.38), scale: 1.0),
                    Controls.label(
                        "-", color: context.foregroundColor.opacity(context.isEnabled ? 0.70 : 0.38), scale: 1.0),
                ]
            )
            return Controls.stackPanel(
                preferredSize: Size(
                    width: context.controlSize.singleLineTextInputSize.width + 30,
                    height: context.controlSize.singleLineTextInputSize.height
                ),
                backgroundColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: context.isEnabled ? 0.58 : 0.30),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.24 : 0.11),
                borderWidth: 1,
                cornerRadius: 7,
                stackLayout: .horizontal(
                    spacing: 8,
                    padding: EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 4),
                    alignment: .center
                ),
                isHitTestVisible: context.isEnabled,
                children: [valueNode, stepperNode]
            )
        case .wheel:
            let guideColor = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.14 : 0.07)
            let topGuide = Controls.panel(
                preferredSize: Size(width: 1, height: 7),
                backgroundColor: guideColor,
                isHitTestVisible: false
            )
            let bottomGuide = Controls.panel(
                preferredSize: Size(width: 1, height: 7),
                backgroundColor: guideColor,
                isHitTestVisible: false
            )
            return Controls.stackPanel(
                preferredSize: Size(width: context.controlSize.singleLineTextInputSize.width, height: 64),
                backgroundColor: Color(red: 0.07, green: 0.09, blue: 0.13, alpha: context.isEnabled ? 0.60 : 0.30),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.18 : 0.08),
                borderWidth: 1,
                cornerRadius: 10,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: 4,
                    padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10),
                    alignment: .stretch
                ),
                isHitTestVisible: context.isEnabled,
                children: [topGuide, valueNode, bottomGuide]
            )
        case .graphical:
            let headerLine = Controls.panel(
                preferredSize: Size(width: 1, height: 2),
                backgroundColor: context.tint.opacity(context.isEnabled ? 0.34 : 0.16),
                cornerRadius: 1,
                isHitTestVisible: false
            )
            let gridHint = Controls.stackPanel(
                backgroundColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.05 : 0.02),
                cornerRadius: 5,
                stackLayout: .horizontal(
                    spacing: 3,
                    padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: (0..<5).map { index in
                    Controls.panel(
                        preferredSize: Size(width: 10, height: 10),
                        backgroundColor: index == 2
                            ? context.tint.opacity(context.isEnabled ? 0.62 : 0.26)
                            : Color(red: 0.95, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.10 : 0.04),
                        cornerRadius: 3,
                        isHitTestVisible: false
                    )
                }
            )
            return Controls.stackPanel(
                preferredSize: Size(width: context.controlSize.singleLineTextInputSize.width, height: 78),
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: context.isEnabled ? 0.68 : 0.34),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: context.isEnabled ? 0.18 : 0.08),
                borderWidth: 1,
                cornerRadius: 12,
                stackLayout: .vertical(
                    spacing: 7,
                    padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
                    alignment: .stretch
                ),
                isHitTestVisible: context.isEnabled,
                children: [headerLine, valueNode, gridHint]
            )
        }
    }

    private static func configureInteraction(
        on node: ViewNode,
        selection: Binding<Date>,
        range: DatePickerRange,
        components: DatePickerComponents,
        calendar: Calendar,
        isEnabled: Bool,
        invalidate: @escaping () -> Void
    ) {
        guard isEnabled else {
            return
        }

        node.isFocusable = true
        node.isHitTestVisible = true
        node.onKeyDown = { event in
            let direction: Int
            switch event.key {
            case .upArrow, .rightArrow:
                direction = 1
            case .downArrow, .leftArrow:
                direction = -1
            default:
                return
            }

            guard
                let proposedDate = steppedDate(
                    from: selection.wrappedValue,
                    direction: direction,
                    components: components,
                    calendar: calendar
                ), range.contains(proposedDate)
            else {
                return
            }

            selection.wrappedValue = proposedDate
            invalidate()
        }
    }

    private static func steppedDate(
        from date: Date,
        direction: Int,
        components: DatePickerComponents,
        calendar: Calendar
    ) -> Date? {
        let component: Calendar.Component = components == .date ? .day : .minute
        return calendar.date(byAdding: component, value: direction, to: date)
    }

    private static func formattedValue(
        _ date: Date,
        components: DatePickerComponents,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        if locale.identifier != Locale.current.identifier {
            return localizedFormattedValue(
                date,
                components: components,
                calendar: calendar,
                timeZone: timeZone,
                locale: locale
            )
        }

        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let dateText = String(
            format: "%04d-%02d-%02d",
            dateComponents.year ?? 0,
            dateComponents.month ?? 1,
            dateComponents.day ?? 1
        )
        let timeText = String(
            format: "%02d:%02d",
            dateComponents.hour ?? 0,
            dateComponents.minute ?? 0
        )

        if components.contains(.date), components.contains(.hourAndMinute) {
            return "\(dateText) \(timeText)"
        }
        if components.contains(.date) {
            return dateText
        }
        if components.contains(.hourAndMinute) {
            return timeText
        }
        return dateText
    }

    private static func localizedFormattedValue(
        _ date: Date,
        components: DatePickerComponents,
        calendar: Calendar,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = locale

        if components.contains(.date), components.contains(.hourAndMinute) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        } else if components.contains(.date) {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        } else if components.contains(.hourAndMinute) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }

        return formatter.string(from: date)
    }
}
@MainActor
public struct MultiDatePicker: View {
    public typealias Body = Never

    private let selection: Binding<Set<DateComponents>>
    private let label: [AnyView]

    public init(
        selection: Binding<Set<DateComponents>>,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = label()
    }

    public init(_ title: String, selection: Binding<Set<DateComponents>>) {
        self.init(selection: selection) {
            Text(title)
        }
    }

    public init(_ titleKey: LocalizedStringKey, selection: Binding<Set<DateComponents>>) {
        self.init(titleKey.resolvedString, selection: selection)
    }

    public var body: Never {
        fatalError("MultiDatePicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let selection = selection
        let isEnabled = context.isEnabled
        let invalidate = context.invalidate
        let calendar = context.environmentValues.calendar

        let daySymbols = calendar.shortWeekdaySymbols
        let today = Date()
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: today)
        let currentMonth = todayComponents.month ?? 1
        let currentYear = todayComponents.year ?? 2026
        let dateComponents = DateComponents(year: currentYear, month: currentMonth, day: 1)
        let firstOfMonth = calendar.date(from: dateComponents)!
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth) - 1

        return VStack(alignment: .leading, spacing: 8) {
            label
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(daySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 32, height: 24)
                    }
                }
                let totalCells = ((firstWeekday + daysInMonth + 6) / 7) * 7
                let rows = totalCells / 7
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let index = row * 7 + col
                            let day = index - firstWeekday + 1
                            if day >= 1 && day <= daysInMonth {
                                let dc = DateComponents(year: currentYear, month: currentMonth, day: day)
                                let isSelected = selection.wrappedValue.contains(dc)
                                Text("\(day)")
                                    .font(.body)
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(isSelected ? Color.accentColor : Color.clear)
                                    )
                                    .onTapGesture {
                                        guard isEnabled else { return }
                                        var newSelection = selection.wrappedValue
                                        if newSelection.contains(dc) {
                                            newSelection.remove(dc)
                                        } else {
                                            newSelection.insert(dc)
                                        }
                                        selection.wrappedValue = newSelection
                                        invalidate()
                                    }
                            } else {
                                Spacer().frame(width: 32, height: 32)
                            }
                        }
                    }
                }
            }
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct ColorPicker: View {
    public typealias Body = Never

    private let selection: Binding<Color>
    private let supportsOpacity: Bool
    private let label: [AnyView]

    public init(
        selection: Binding<Color>,
        supportsOpacity: Bool = true,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = label()
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) {
        self.init(selection: selection, supportsOpacity: supportsOpacity) {
            Text(String(title))
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Color>,
        supportsOpacity: Bool = true
    ) {
        self.init(titleKey.resolvedString, selection: selection, supportsOpacity: supportsOpacity)
    }

    public var body: Never {
        fatalError("ColorPicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelViews = label
        let selection = selection
        let supportsOpacity = supportsOpacity
        let labelComponent = composeComponent(
            from: labelViews,
            context:
                context
                .withForegroundColor(.secondary)
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let color = selection.wrappedValue
            let swatchNode = Controls.panel(
                preferredSize: context.controlSize.colorSwatchPreferredSize,
                backgroundColor: color,
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.30),
                borderWidth: 1,
                cornerRadius: 6,
                isHitTestVisible: false
            )
            let valueNode = Text(Self.hexValue(color, includesOpacity: supportsOpacity))
                .monospaced()
                .lineLimit(1)
                .makeComponent(
                    context:
                        context
                        .withTextAlignment(.trailing)
                        .withLineLimit(1)
                )
                .makeNode(runtime: runtime)
            let controlNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [swatchNode, valueNode]
            )

            guard !context.labelsHidden, !labelViews.isEmpty else {
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    supportsOpacity: supportsOpacity,
                    isEnabled: context.isEnabled,
                    invalidate: context.invalidate
                )
                return controlNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            let node = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 12, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [labelNode, controlNode]
            )
            Self.configureInteraction(
                on: node,
                selection: selection,
                supportsOpacity: supportsOpacity,
                isEnabled: context.isEnabled,
                invalidate: context.invalidate
            )
            return node
        }
    }

    private static func configureInteraction(
        on node: ViewNode,
        selection: Binding<Color>,
        supportsOpacity: Bool,
        isEnabled: Bool,
        invalidate: @escaping () -> Void
    ) {
        guard isEnabled else {
            return
        }

        node.isFocusable = true
        node.isHitTestVisible = true
        node.onActivate = {
            applyPaletteStep(to: selection, direction: 1, supportsOpacity: supportsOpacity, invalidate: invalidate)
        }
        node.onKeyDown = { event in
            switch event.key {
            case .rightArrow:
                applyPaletteStep(to: selection, direction: 1, supportsOpacity: supportsOpacity, invalidate: invalidate)
            case .leftArrow:
                applyPaletteStep(to: selection, direction: -1, supportsOpacity: supportsOpacity, invalidate: invalidate)
            case .upArrow where supportsOpacity:
                applyOpacityStep(to: selection, direction: 1, invalidate: invalidate)
            case .downArrow where supportsOpacity:
                applyOpacityStep(to: selection, direction: -1, invalidate: invalidate)
            default:
                return
            }
        }
    }

    private static func applyPaletteStep(
        to selection: Binding<Color>,
        direction: Int,
        supportsOpacity: Bool,
        invalidate: () -> Void
    ) {
        let currentColor = selection.wrappedValue
        let nextColor = steppedPaletteColor(from: currentColor, direction: direction, preservesOpacity: supportsOpacity)
        guard nextColor != currentColor else {
            return
        }

        selection.wrappedValue = nextColor
        invalidate()
    }

    private static func applyOpacityStep(
        to selection: Binding<Color>,
        direction: Int,
        invalidate: () -> Void
    ) {
        let currentColor = selection.wrappedValue
        let currentComponents = currentColor.rgba
        let nextAlpha = Float(clampedUnitIntervalValue(Double(currentComponents.3) + (Double(direction) * 0.10)))
        guard nextAlpha != currentComponents.3 else {
            return
        }

        selection.wrappedValue = Color(
            red: currentComponents.0,
            green: currentComponents.1,
            blue: currentComponents.2,
            alpha: nextAlpha
        )
        invalidate()
    }

    private static func steppedPaletteColor(from color: Color, direction: Int, preservesOpacity: Bool) -> Color {
        let palette = retainedKeyboardPalette
        guard !palette.isEmpty else {
            return color
        }

        let baseIndex = nearestPaletteIndex(to: color, in: palette)
        let nextIndex = (baseIndex + direction + palette.count) % palette.count
        let nextBaseColor = palette[nextIndex]
        let alpha = preservesOpacity ? color.rgba.3 : 1
        return nextBaseColor.opacity(Double(alpha))
    }

    private static func nearestPaletteIndex(to color: Color, in palette: [Color]) -> Int {
        let components = color.rgba
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude

        for (index, paletteColor) in palette.enumerated() {
            let paletteComponents = paletteColor.rgba
            let redDistance = Double(components.0 - paletteComponents.0)
            let greenDistance = Double(components.1 - paletteComponents.1)
            let blueDistance = Double(components.2 - paletteComponents.2)
            let distance = (redDistance * redDistance) + (greenDistance * greenDistance) + (blueDistance * blueDistance)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private static let retainedKeyboardPalette: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .purple,
        .pink,
        .brown,
        .gray,
        .black,
        .white,
    ]

    private static func clampedUnitIntervalValue(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    private static func hexValue(_ color: Color, includesOpacity: Bool) -> String {
        let components = color.rgba
        let alphaText = includesOpacity ? String(format: "%02X", byte(from: components.3)) : ""
        return String(
            format: "#%02X%02X%02X%@",
            byte(from: components.0),
            byte(from: components.1),
            byte(from: components.2),
            alphaText
        )
    }

    private static func byte(from channel: Float) -> Int {
        let clampedChannel = min(max(Double(channel), 0), 1)
        return Int((clampedChannel * 255).rounded())
    }
}
@MainActor
public struct Toggle: View {
    public typealias Body = Never

    private let isOn: Binding<Bool>
    private let label: [AnyView]

    public init(_ title: String, isOn: Binding<Bool>) {
        self.isOn = isOn
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.6, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
    }

    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
        self.init(String(title), isOn: isOn)
    }

    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(titleKey.resolvedString, isOn: isOn)
    }

    public init(_ title: String, image name: String, isOn: Binding<Bool>) {
        self.isOn = isOn
        self.label = [
            AnyView(Label(title, image: name))
        ]
    }

    public init<S: StringProtocol>(_ title: S, image name: String, isOn: Binding<Bool>) {
        self.init(String(title), image: name, isOn: isOn)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, isOn: Binding<Bool>) {
        self.init(titleKey.resolvedString, image: name, isOn: isOn)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, isOn: Binding<Bool>) {
        self.isOn = isOn
        self.label = [
            AnyView(Label(title, image: resource))
        ]
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, isOn: Binding<Bool>) {
        self.init(titleKey.resolvedString, image: resource, isOn: isOn)
    }

    public init(_ title: String, systemImage: String, isOn: Binding<Bool>) {
        self.isOn = isOn
        self.label = [
            AnyView(Label(title, systemImage: systemImage))
        ]
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, isOn: Binding<Bool>) {
        self.init(String(title), systemImage: systemImage, isOn: isOn)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) {
        self.init(titleKey.resolvedString, systemImage: systemImage, isOn: isOn)
    }

    public init<C>(
        _ title: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(title, isOn: Self.aggregateBinding(sources: sources, isOn: isOn))
    }

    public init<S: StringProtocol, C>(
        _ title: S,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(String(title), sources: sources, isOn: isOn)
    }

    public init<C>(
        _ titleKey: LocalizedStringKey,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(titleKey.resolvedString, sources: sources, isOn: isOn)
    }

    public init<C>(
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>,
        @ViewBuilder label: () -> [AnyView]
    ) where C: RandomAccessCollection {
        self.isOn = Self.aggregateBinding(sources: sources, isOn: isOn)
        self.label = label()
    }

    public init<C>(
        _ title: String,
        image name: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(title, image: name, isOn: Self.aggregateBinding(sources: sources, isOn: isOn))
    }

    public init<S: StringProtocol, C>(
        _ title: S,
        image name: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(String(title), image: name, sources: sources, isOn: isOn)
    }

    public init<C>(
        _ titleKey: LocalizedStringKey,
        image name: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(titleKey.resolvedString, image: name, sources: sources, isOn: isOn)
    }

    public init<S: StringProtocol, C>(
        _ title: S,
        image resource: ImageResource,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(title, image: resource, isOn: Self.aggregateBinding(sources: sources, isOn: isOn))
    }

    public init<C>(
        _ titleKey: LocalizedStringKey,
        image resource: ImageResource,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(titleKey.resolvedString, image: resource, sources: sources, isOn: isOn)
    }

    public init<C>(
        _ title: String,
        systemImage: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(title, systemImage: systemImage, isOn: Self.aggregateBinding(sources: sources, isOn: isOn))
    }

    public init<S: StringProtocol, C>(
        _ title: S,
        systemImage: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(String(title), systemImage: systemImage, sources: sources, isOn: isOn)
    }

    public init<C>(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) where C: RandomAccessCollection {
        self.init(titleKey.resolvedString, systemImage: systemImage, sources: sources, isOn: isOn)
    }

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> [AnyView]) {
        self.isOn = isOn
        self.label = label()
    }

    public var body: Never {
        fatalError("Toggle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let binding = isOn

        return Component { runtime in
            switch context.toggleStyle.kind {
            case .automatic, .switch:
                return Self.switchNode(
                    runtime: runtime,
                    context: context,
                    binding: binding,
                    labelComponent: labelComponent
                )
            case .checkbox:
                return Self.checkboxNode(
                    runtime: runtime,
                    context: context,
                    binding: binding,
                    labelComponent: labelComponent
                )
            case .button:
                return Self.buttonNode(
                    runtime: runtime,
                    context: context,
                    binding: binding,
                    labelComponent: labelComponent
                )
            }
        }
    }

    private static func switchNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        binding: Binding<Bool>,
        labelComponent: Component
    ) -> ViewNode {
        let toggleNode = Controls.toggle(
            runtime: runtime,
            isOn: binding.wrappedValue,
            isEnabled: context.isEnabled,
            preferredSize: context.controlSize.togglePreferredSize,
            onColor: context.tint,
            onToggle: { newValue in
                binding.wrappedValue = newValue
                context.invalidate()
            }
        )

        guard !context.labelsHidden else {
            return toggleNode
        }

        let labelNode = labelComponent.makeNode(runtime: runtime)
        return Controls.stackPanel(
            stackLayout: .horizontal(spacing: 10, alignment: .center),
            isHitTestVisible: false,
            children: [labelNode, toggleNode]
        )
    }

    private static func checkboxNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        binding: Binding<Bool>,
        labelComponent: Component
    ) -> ViewNode {
        let boxSize: Double = 20
        let surfaceStyle = ButtonSurfaceStyle.default
        let checkIcon =
            binding.wrappedValue
            ? Controls.icon(
                .checkmark,
                preferredSize: Size(width: boxSize - 4, height: boxSize - 4),
                color: context.isEnabled ? .white : surfaceStyle.palette.disabledForeground,
                scale: 1.2
            )
            : Controls.panel(
                preferredSize: Size(width: boxSize - 4, height: boxSize - 4),
                isHitTestVisible: false
            )
        let box = Controls.panel(
            preferredSize: Size(width: boxSize, height: boxSize),
            backgroundColor: context.isEnabled
                ? (binding.wrappedValue ? context.tint : surfaceStyle.palette.idle)
                : surfaceStyle.palette.disabledBackground,
            borderColor: context.isEnabled
                ? (binding.wrappedValue ? context.tint.opacity(0.92) : surfaceStyle.chrome.borderColor)
                : surfaceStyle.palette.disabledBorder,
            borderWidth: 1,
            cornerRadius: 4,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false,
            children: [checkIcon]
        )
        let children =
            context.labelsHidden
            ? [box]
            : [box, labelComponent.makeNode(runtime: runtime)]
        let hiddenPreferredSize = Size(
            width: max(context.controlSize.togglePreferredSize.height, boxSize + 16),
            height: max(context.controlSize.togglePreferredSize.height, boxSize + 16)
        )

        return Controls.button(
            runtime: runtime,
            preferredSize: context.labelsHidden ? hiddenPreferredSize : nil,
            cornerRadius: 8,
            palette: SurfacePalette(
                idle: .clear,
                hovered: Color(red: 0.20, green: 0.26, blue: 0.34, alpha: 0.44),
                focused: Color(red: 0.24, green: 0.32, blue: 0.42, alpha: 0.56),
                pressed: Color(red: 0.30, green: 0.40, blue: 0.52, alpha: 0.64),
                activated: Color(red: 0.30, green: 0.40, blue: 0.52, alpha: 0.64)
            ),
            chrome: SurfaceChrome(
                borderColor: .clear,
                borderHoveredColor: Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.16),
                borderFocusedColor: context.tint.opacity(0.42),
                borderPressedColor: context.tint.opacity(0.58),
                borderWidth: 1,
                focusRingColor: context.tint.opacity(0.26),
                focusRingWidth: 2
            ),
            clipsToBounds: true,
            layoutMode: .stack(
                .horizontal(
                    spacing: context.labelsHidden ? 0 : 10,
                    padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 8),
                    alignment: .center
                )
            ),
            isEnabled: context.isEnabled,
            action: {
                binding.wrappedValue.toggle()
                context.invalidate()
            },
            children: children
        )
    }

    private static func buttonNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        binding: Binding<Bool>,
        labelComponent: Component
    ) -> ViewNode {
        let surfaceStyle = ButtonSurfaceStyle.default
        let palette =
            binding.wrappedValue
            ? SurfacePalette(
                idle: context.tint.opacity(0.82),
                hovered: context.tint.opacity(0.90),
                focused: context.tint.opacity(0.96),
                pressed: context.tint,
                activated: context.tint
            )
            : surfaceStyle.palette
        let children: [ViewNode]
        if context.labelsHidden {
            let iconNode =
                binding.wrappedValue
                ? Controls.icon(
                    .checkmark,
                    preferredSize: Size(width: 20, height: 20),
                    color: context.isEnabled ? .white : surfaceStyle.palette.disabledForeground,
                    scale: 1.25
                )
                : Controls.panel(
                    preferredSize: Size(width: 20, height: 20),
                    isHitTestVisible: false
                )
            children = [
                iconNode
            ]
        } else {
            children = [labelComponent.makeNode(runtime: runtime)]
        }
        let hiddenPreferredSize = Size(
            width: max(context.controlSize.togglePreferredSize.width, 44),
            height: max(context.controlSize.togglePreferredSize.height, 36)
        )

        return Controls.button(
            runtime: runtime,
            preferredSize: context.labelsHidden ? hiddenPreferredSize : nil,
            cornerRadius: surfaceStyle.cornerRadius,
            palette: palette,
            chrome: surfaceStyle.chrome,
            clipsToBounds: surfaceStyle.clipsToBounds,
            layoutMode: .stack(
                .horizontal(
                    spacing: 0,
                    padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                    alignment: .center,
                    mainAlignment: .center
                )
            ),
            isEnabled: context.isEnabled,
            animation: surfaceStyle.animation,
            action: {
                binding.wrappedValue.toggle()
                context.invalidate()
            },
            children: children
        )
    }

    private static func aggregateBinding<C>(
        sources: C,
        isOn: KeyPath<C.Element, Binding<Bool>>
    ) -> Binding<Bool> where C: RandomAccessCollection {
        Binding<Bool>(
            get: {
                guard !sources.isEmpty else {
                    return false
                }
                return sources.allSatisfy { source in
                    source[keyPath: isOn].wrappedValue
                }
            },
            set: { newValue in
                for source in sources {
                    source[keyPath: isOn].wrappedValue = newValue
                }
            }
        )
    }
}
@MainActor
public struct Picker<SelectionValue: Hashable>: View {
    public typealias Body = Never

    private let selection: Binding<SelectionValue>
    private let label: [AnyView]
    private let currentValueLabel: [AnyView]
    private let content: [AnyView]

    private struct Option {
        var value: SelectionValue?
        var node: ViewNode
    }

    public init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.6, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.currentValueLabel = []
        self.content = content()
    }

    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(String(title), selection: selection, content: content)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.init(titleKey.resolvedString, selection: selection, content: content)
    }

    public init<Label: View>(
        selection: Binding<SelectionValue>,
        label: Label,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = [AnyView(label)]
        self.currentValueLabel = []
        self.content = content()
    }

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = label()
        self.currentValueLabel = []
        self.content = content()
    }

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> [AnyView],
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.selection = selection
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.content = content()
    }

    public var body: Never {
        fatalError("Picker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let selection = selection
        let labelViews = label
        let currentValueLabelViews = currentValueLabel
        let contentViews = content
        let labelComponent = composeComponent(
            from: labelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let currentValueLabelComponent = composeComponent(
            from: currentValueLabelViews,
            context:
                context
                .withTextAlignment(.trailing)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let selectedValue = selection.wrappedValue
            let selectedAnyValue = AnyHashable(selectedValue)
            let options: [Option] = contentViews.enumerated().map { index, option in
                let representedValue = Self.selectionValue(for: option, fallbackIndex: index)
                let optionNode = option.makeComponent(context: context).makeNode(runtime: runtime)
                return Option(value: representedValue, node: optionNode)
            }

            let pickerNode: ViewNode
            switch context.pickerStyle.kind {
            case .automatic, .segmented:
                pickerNode = Self.segmentedPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .inline:
                pickerNode = Self.inlinePickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .navigationLink:
                pickerNode = Self.navigationLinkPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    options: options
                )
            case .palette:
                pickerNode = Self.palettePickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .radioGroup:
                pickerNode = Self.radioGroupPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .wheel:
                pickerNode = Self.wheelPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedAnyValue: selectedAnyValue,
                    options: options
                )
            case .menu, .popUpButton:
                pickerNode = Self.menuPickerNode(
                    runtime: runtime,
                    context: context,
                    selection: selection,
                    selectedValue: selectedValue,
                    options: options
                )
            }

            guard !context.labelsHidden && (!labelViews.isEmpty || !currentValueLabelViews.isEmpty) else {
                return pickerNode
            }

            guard !currentValueLabelViews.isEmpty else {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    stackLayout: .vertical(spacing: 8, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [labelNode, pickerNode]
                )
            }

            var headerChildren: [ViewNode] = []
            if !labelViews.isEmpty {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
                headerChildren.append(labelNode)
            }
            headerChildren.append(currentValueLabelComponent.makeNode(runtime: runtime))
            let headerNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: headerChildren
            )
            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [headerNode, pickerNode]
            )
        }
    }

    private static func selectionValue(for option: AnyView, fallbackIndex: Int) -> SelectionValue? {
        if let tagValue = option.selectionTag?.base as? SelectionValue {
            return tagValue
        }
        return fallbackIndex as? SelectionValue
    }

    private static func segmentedPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedValue: SelectionValue,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let palette = isSelected ? selectedPalette(tint: context.tint) : unselectedPalette

            return Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 8,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected
                        ? context.tint.opacity(0.45) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderHoveredColor: isSelected
                        ? context.tint.opacity(0.62) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18),
                    borderFocusedColor: isSelected
                        ? context.tint.opacity(0.76) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.26),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
                    borderWidth: 1,
                    focusRingColor: context.tint.opacity(0.28),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                        alignment: .center,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled && option.value != nil,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [option.node]
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.90),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .horizontal(
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func inlinePickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let indicatorNode =
                isSelected
                ? Controls.icon(
                    .checkmark,
                    preferredSize: Size(width: 18, height: 18),
                    color: context.isEnabled ? context.tint : Color(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.70),
                    scale: 1.2
                )
                : Controls.panel(
                    preferredSize: Size(width: 18, height: 18),
                    isHitTestVisible: false
                )
            option.node.layoutPriority = max(option.node.layoutPriority, 1)

            return Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 6,
                palette: SurfacePalette(
                    idle: isSelected
                        ? context.tint.opacity(0.14)
                        : Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.34),
                    hovered: isSelected
                        ? context.tint.opacity(0.22)
                        : Color(red: 0.18, green: 0.24, blue: 0.32, alpha: 0.54),
                    focused: isSelected
                        ? context.tint.opacity(0.28)
                        : Color(red: 0.22, green: 0.30, blue: 0.40, alpha: 0.64),
                    pressed: isSelected
                        ? context.tint.opacity(0.34)
                        : Color(red: 0.28, green: 0.38, blue: 0.50, alpha: 0.72)
                ),
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.36) : .clear,
                    borderHoveredColor: isSelected
                        ? context.tint.opacity(0.50) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                    borderFocusedColor: context.tint.opacity(0.64),
                    borderPressedColor: context.tint.opacity(0.72),
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: context.tint.opacity(0.26),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(
                    .horizontal(
                        spacing: 8,
                        padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 10),
                        alignment: .center
                    )),
                isEnabled: context.isEnabled && option.value != nil,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [indicatorNode, option.node]
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.46),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 10,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 2,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func navigationLinkPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedValue: SelectionValue,
        options: [Option]
    ) -> ViewNode {
        let titles = options.enumerated().map { index, option in
            firstText(in: option.node) ?? "OPTION \(index + 1)"
        }
        let selectedIndex = options.firstIndex { $0.value == selectedValue } ?? 0
        let hasSelectableOption = options.contains { $0.value != nil }

        return Controls.dropdown(
            runtime: runtime,
            options: titles,
            selectedIndex: selectedIndex,
            isEnabled: context.isEnabled && hasSelectableOption,
            preferredSize: Size(
                width: context.controlSize.pickerMenuPreferredSize.width + 24,
                height: context.controlSize.pickerMenuPreferredSize.height + 4
            ),
            palette: SurfacePalette(
                idle: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.52),
                hovered: Color(red: 0.13, green: 0.18, blue: 0.26, alpha: 0.64),
                focused: Color(red: 0.17, green: 0.24, blue: 0.34, alpha: 0.76),
                pressed: Color(red: 0.22, green: 0.31, blue: 0.44, alpha: 0.84)
            ),
            chrome: SurfaceChrome(
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12),
                borderHoveredColor: context.tint.opacity(0.36),
                borderFocusedColor: context.tint.opacity(0.54),
                borderPressedColor: context.tint.opacity(0.66),
                borderWidth: 1,
                focusRingColor: context.tint.opacity(0.26),
                focusRingWidth: 2
            ),
            onSelect: { index in
                guard options.indices.contains(index), let value = options[index].value else {
                    return
                }

                selection.wrappedValue = value
                context.invalidate()
            }
        )
    }

    private static func palettePickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let itemHeight = context.controlSize.pickerMenuPreferredSize.height
        let itemSize = Size(width: max(44, itemHeight * 1.45), height: itemHeight)
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let palette = isSelected ? selectedPalette(tint: context.tint) : unselectedPalette
            return Controls.button(
                runtime: runtime,
                preferredSize: itemSize,
                layoutPriority: 1,
                cornerRadius: 10,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected
                        ? context.tint.opacity(0.62) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10),
                    borderHoveredColor: isSelected
                        ? context.tint.opacity(0.78) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22),
                    borderFocusedColor: isSelected
                        ? context.tint.opacity(0.88) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.30),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.36),
                    borderWidth: isSelected ? 2 : 1,
                    focusRingColor: context.tint.opacity(0.30),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
                        alignment: .center,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled && option.value != nil,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [option.node]
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.72),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .horizontal(
                spacing: 6,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func wheelPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let itemHeight = max(1, Double(context.environmentValues.defaultWheelPickerItemHeight))
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let title = firstText(in: option.node) ?? "OPTION \(index + 1)"
            let palette = isSelected ? selectedPalette(tint: context.tint) : unselectedPalette
            let optionNode = Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 8,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected ? context.tint.opacity(0.48) : .clear,
                    borderHoveredColor: isSelected
                        ? context.tint.opacity(0.64) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderFocusedColor: isSelected
                        ? context.tint.opacity(0.78) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.24),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: context.tint.opacity(0.28),
                    focusRingWidth: 2
                ),
                clipsToBounds: true,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12),
                        alignment: .center,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled && option.value != nil,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [
                    Controls.label(
                        title,
                        layoutPriority: 1,
                        color: isSelected ? .white : .secondary,
                        scale: 1.6,
                        weight: isSelected ? .semibold : .regular,
                        alignment: .center,
                        lineBreakMode: .truncateTail,
                        maximumNumberOfLines: 1
                    )
                ]
            )
            optionNode.applyDefaultMinimumHeight(itemHeight)
            return optionNode
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.68),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 2,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func radioGroupPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let title = firstText(in: option.node) ?? "OPTION \(index + 1)"
            return Controls.radioButton(
                runtime: runtime,
                label: title,
                isSelected: isSelected,
                isEnabled: context.isEnabled && option.value != nil,
                layoutPriority: 1,
                chrome: SurfaceChrome(
                    borderColor: isSelected
                        ? context.tint.opacity(0.40) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderHoveredColor: isSelected
                        ? context.tint.opacity(0.58) : Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18),
                    borderFocusedColor: isSelected
                        ? context.tint.opacity(0.72) : Color(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.26),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.34),
                    borderWidth: 1,
                    focusRingColor: context.tint.opacity(0.28),
                    focusRingWidth: 2
                ),
                selectedColor: context.tint,
                onSelect: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                }
            )
        }

        return Controls.stackPanel(
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.72),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
            borderWidth: 1,
            cornerRadius: 12,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 6,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
    }

    private static func menuPickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedValue: SelectionValue,
        options: [Option]
    ) -> ViewNode {
        let titles = options.enumerated().map { index, option in
            firstText(in: option.node) ?? "OPTION \(index + 1)"
        }
        let selectedIndex = options.firstIndex { $0.value == selectedValue } ?? 0
        let hasSelectableOption = options.contains { $0.value != nil }

        return Controls.dropdown(
            runtime: runtime,
            options: titles,
            selectedIndex: selectedIndex,
            isEnabled: context.isEnabled && hasSelectableOption,
            preferredSize: context.controlSize.pickerMenuPreferredSize,
            onSelect: { index in
                guard options.indices.contains(index), let value = options[index].value else {
                    return
                }

                selection.wrappedValue = value
                context.invalidate()
            }
        )
    }

    private static func firstText(in node: ViewNode) -> String? {
        if let text = node.text {
            return text
        }

        for child in node.children {
            if let text = firstText(in: child) {
                return text
            }
        }

        return nil
    }

    private static func selectedPalette(tint: Color) -> SurfacePalette {
        SurfacePalette(
            idle: tint.opacity(0.82),
            hovered: tint.opacity(0.90),
            focused: tint.opacity(0.96),
            pressed: tint,
            activated: tint
        )
    }

    private static var unselectedPalette: SurfacePalette {
        SurfacePalette(
            idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.78),
            hovered: Color(red: 0.22, green: 0.29, blue: 0.39, alpha: 0.86),
            focused: Color(red: 0.26, green: 0.35, blue: 0.47, alpha: 0.90),
            pressed: Color(red: 0.31, green: 0.42, blue: 0.56, alpha: 0.96),
            activated: Color(red: 0.36, green: 0.48, blue: 0.63, alpha: 0.96)
        )
    }
}
@MainActor
public struct Stepper: View {
    public typealias Body = Never

    private let label: [AnyView]
    private let canDecrement: @MainActor () -> Bool
    private let canIncrement: @MainActor () -> Bool
    private let decrement: @MainActor () -> Void
    private let increment: @MainActor () -> Void

    public init(
        _ title: String,
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(
        _ title: S,
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            String(title),
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            titleKey.resolvedString,
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    public init(
        onIncrement: (@MainActor () -> Void)? = nil,
        onDecrement: (@MainActor () -> Void)? = nil,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.label = label()
        self.canDecrement = {
            onDecrement != nil
        }
        self.canIncrement = {
            onIncrement != nil
        }
        self.decrement = {
            guard let onDecrement else {
                return
            }
            onEditingChanged(true)
            onDecrement()
            onEditingChanged(false)
        }
        self.increment = {
            guard let onIncrement else {
                return
            }
            onEditingChanged(true)
            onIncrement()
            onEditingChanged(false)
        }
    }

    public init<Value>(
        _ title: String,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.init(
            value: value,
            in: bounds,
            step: step,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.init(String(title), value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.init(titleKey.resolvedString, value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init<Value>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.label = label()
        self.canDecrement = {
            value.wrappedValue > bounds.lowerBound
        }
        self.canIncrement = {
            value.wrappedValue < bounds.upperBound
        }
        self.decrement = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedStrideable(value.wrappedValue, by: -step, in: bounds)
            onEditingChanged(false)
        }
        self.increment = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedStrideable(value.wrappedValue, by: step, in: bounds)
            onEditingChanged(false)
        }
    }

    public init<Value>(
        _ title: String,
        value: Binding<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.init(
            value: value,
            step: step,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol, Value>(
        _ title: S,
        value: Binding<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.init(String(title), value: value, step: step, onEditingChanged: onEditingChanged)
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Binding<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.init(titleKey.resolvedString, value: value, step: step, onEditingChanged: onEditingChanged)
    }

    public init<Value>(
        value: Binding<Value>,
        step: Value.Stride = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        self.label = label()
        self.canDecrement = { true }
        self.canIncrement = { true }
        self.decrement = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedStrideable(value.wrappedValue, by: -step, in: nil)
            onEditingChanged(false)
        }
        self.increment = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedStrideable(value.wrappedValue, by: step, in: nil)
            onEditingChanged(false)
        }
    }

    public init(
        _ title: String,
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: value,
            in: bounds,
            step: step,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(
        _ title: S,
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(String(title), value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(titleKey.resolvedString, value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude,
        step: Double = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) {
        let resolvedStep = Self.resolvedDoubleStep(step)
        self.label = label()
        self.canDecrement = {
            value.wrappedValue > bounds.lowerBound
        }
        self.canIncrement = {
            value.wrappedValue < bounds.upperBound
        }
        self.decrement = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedDouble(value.wrappedValue, by: -resolvedStep, in: bounds)
            onEditingChanged(false)
        }
        self.increment = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedDouble(value.wrappedValue, by: resolvedStep, in: bounds)
            onEditingChanged(false)
        }
    }

    public init(
        _ title: String,
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: value,
            in: bounds,
            step: step,
            onEditingChanged: onEditingChanged
        ) {
            Text(title)
                .font(.system(size: 1.6, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }

    public init<S: StringProtocol>(
        _ title: S,
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(String(title), value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init(
        _ titleKey: LocalizedStringKey,
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(titleKey.resolvedString, value: value, in: bounds, step: step, onEditingChanged: onEditingChanged)
    }

    public init(
        value: Binding<Int>,
        in bounds: ClosedRange<Int> = Int.min...Int.max,
        step: Int = 1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> [AnyView]
    ) {
        let resolvedStep = max(1, step)
        self.label = label()
        self.canDecrement = {
            value.wrappedValue > bounds.lowerBound
        }
        self.canIncrement = {
            value.wrappedValue < bounds.upperBound
        }
        self.decrement = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedInt(value.wrappedValue, by: -resolvedStep, in: bounds)
            onEditingChanged(false)
        }
        self.increment = {
            onEditingChanged(true)
            value.wrappedValue = Self.steppedInt(value.wrappedValue, by: resolvedStep, in: bounds)
            onEditingChanged(false)
        }
    }

    public var body: Never {
        fatalError("Stepper has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let canDecrement = canDecrement
        let canIncrement = canIncrement
        let decrement = decrement
        let increment = increment

        return Component { runtime in
            let decrementNode = Self.controlButton(
                runtime: runtime,
                title: "-",
                isEnabled: context.isEnabled && canDecrement(),
                preferredSize: context.controlSize.stepperButtonPreferredSize,
                action: {
                    decrement()
                    context.invalidate()
                }
            )
            let incrementNode = Self.controlButton(
                runtime: runtime,
                title: "+",
                isEnabled: context.isEnabled && canIncrement(),
                preferredSize: context.controlSize.stepperButtonPreferredSize,
                action: {
                    increment()
                    context.invalidate()
                }
            )

            guard !context.labelsHidden else {
                return Controls.stackPanel(
                    stackLayout: .horizontal(spacing: 8, alignment: .center),
                    isHitTestVisible: false,
                    children: [decrementNode, incrementNode]
                )
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: [labelNode, decrementNode, incrementNode]
            )
        }
    }

    private static func controlButton(
        runtime: RetainedViewRuntime,
        title: String,
        isEnabled: Bool,
        preferredSize: Size,
        action: @escaping @MainActor () -> Void
    ) -> ViewNode {
        let surfaceStyle = ButtonSurfaceStyle.default
        let titleNode = Controls.label(
            title,
            color: isEnabled ? .white : surfaceStyle.palette.disabledForeground,
            scale: 1.6,
            weight: .bold,
            lineBreakMode: .truncateTail,
            maximumNumberOfLines: 1
        )
        return Controls.button(
            runtime: runtime,
            preferredSize: preferredSize,
            cornerRadius: 12,
            palette: surfaceStyle.palette,
            chrome: surfaceStyle.chrome,
            clipsToBounds: surfaceStyle.clipsToBounds,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: isEnabled,
            animation: surfaceStyle.animation,
            action: action,
            children: [titleNode]
        )
    }

    private static func resolvedDoubleStep(_ step: Double) -> Double {
        step.isFinite && step > 0 ? step : 1
    }

    private static func steppedDouble(_ value: Double, by delta: Double, in bounds: ClosedRange<Double>) -> Double {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        let candidate = clampedValue + delta
        guard candidate.isFinite else {
            return delta > 0 ? bounds.upperBound : bounds.lowerBound
        }
        return min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }

    private static func steppedInt(_ value: Int, by delta: Int, in bounds: ClosedRange<Int>) -> Int {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        if delta >= 0 {
            let (candidate, overflow) = clampedValue.addingReportingOverflow(delta)
            guard !overflow else {
                return bounds.upperBound
            }
            return min(max(candidate, bounds.lowerBound), bounds.upperBound)
        }

        let (candidate, overflow) = clampedValue.addingReportingOverflow(delta)
        guard !overflow else {
            return bounds.lowerBound
        }
        return min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }

    private static func steppedStrideable<Value>(
        _ value: Value,
        by delta: Value.Stride,
        in bounds: ClosedRange<Value>
    ) -> Value where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        let candidate = clampedValue.advanced(by: delta)
        return min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }

    private static func steppedStrideable<Value>(
        _ value: Value,
        by delta: Value.Stride,
        in bounds: ClosedRange<Value>?
    ) -> Value where Value: Strideable & Comparable, Value.Stride: SignedNumeric {
        let candidate = value.advanced(by: delta)
        guard let bounds else {
            return candidate
        }
        return min(max(candidate, bounds.lowerBound), bounds.upperBound)
    }
}
@MainActor
public struct Slider: View {
    public typealias Body = Never

    private let value: Binding<Double>
    private let bounds: ClosedRange<Double>
    private let step: Double?
    private let onEditingChanged: @MainActor (Bool) -> Void
    private let label: [AnyView]
    private let minimumValueLabel: [AnyView]
    private let maximumValueLabel: [AnyView]

    public init<Value: BinaryFloatingPoint>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: Self.doubleBinding(value),
            in: Self.doubleRange(bounds),
            onEditingChanged: onEditingChanged
        )
    }

    public init<Value: BinaryFloatingPoint>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: Self.doubleBinding(value),
            in: Self.doubleRange(bounds),
            step: Double(step),
            onEditingChanged: onEditingChanged
        )
    }

    public init<Value: BinaryFloatingPoint>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: Self.doubleBinding(value),
            in: Self.doubleRange(bounds),
            label: label,
            onEditingChanged: onEditingChanged
        )
    }

    public init<Value: BinaryFloatingPoint>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value,
        @ViewBuilder label: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: Self.doubleBinding(value),
            in: Self.doubleRange(bounds),
            step: Double(step),
            label: label,
            onEditingChanged: onEditingChanged
        )
    }

    public init<Value: BinaryFloatingPoint>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: Self.doubleBinding(value),
            in: Self.doubleRange(bounds),
            label: label,
            minimumValueLabel: minimumValueLabel,
            maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged
        )
    }

    public init<Value: BinaryFloatingPoint>(
        value: Binding<Value>,
        in bounds: ClosedRange<Value> = 0...1,
        step: Value,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.init(
            value: Self.doubleBinding(value),
            in: Self.doubleRange(bounds),
            step: Double(step),
            label: label,
            minimumValueLabel: minimumValueLabel,
            maximumValueLabel: maximumValueLabel,
            onEditingChanged: onEditingChanged
        )
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        @ViewBuilder label: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
    }

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
    }

    public init<MinimumValueLabel: View, MaximumValueLabel: View>(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        minimumValueLabel: MinimumValueLabel,
        maximumValueLabel: MaximumValueLabel,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.step = nil
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = [AnyView(minimumValueLabel)]
        self.maximumValueLabel = [AnyView(maximumValueLabel)]
    }

    public init<MinimumValueLabel: View, MaximumValueLabel: View>(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        step: Double,
        onEditingChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        minimumValueLabel: MinimumValueLabel,
        maximumValueLabel: MaximumValueLabel,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.minimumValueLabel = [AnyView(minimumValueLabel)]
        self.maximumValueLabel = [AnyView(maximumValueLabel)]
    }

    public var body: Never {
        fatalError("Slider has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let binding = value
        let range = bounds
        let step = step
        let onEditingChanged = onEditingChanged
        let labelViews = label
        let minimumLabelViews = minimumValueLabel
        let maximumLabelViews = maximumValueLabel
        let labelComponent = composeComponent(
            from: labelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let minimumLabelComponent = composeComponent(
            from: minimumLabelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let maximumLabelComponent = composeComponent(
            from: maximumLabelViews,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let defaultSliderSize = context.controlSize.sliderPreferredSize
        let hasRangeLabels = !minimumLabelViews.isEmpty || !maximumLabelViews.isEmpty
        let sliderPreferredSize = Size(
            width: hasRangeLabels ? min(defaultSliderSize.width, 100) : defaultSliderSize.width,
            height: defaultSliderSize.height
        )

        return Component { runtime in
            let sliderNode = Controls.slider(
                runtime: runtime,
                value: binding.wrappedValue,
                range: range,
                isEnabled: context.isEnabled,
                preferredSize: sliderPreferredSize,
                layoutPriority: minimumLabelViews.isEmpty && maximumLabelViews.isEmpty ? 0 : 1,
                filledColor: context.tint,
                onValueChanged: { newValue in
                    binding.wrappedValue = Self.snappedValue(newValue, in: range, step: step)
                    context.invalidate()
                },
                onEditingChanged: { isEditing in
                    onEditingChanged(isEditing)
                }
            )

            guard !context.labelsHidden else {
                return sliderNode
            }

            guard !labelViews.isEmpty || !minimumLabelViews.isEmpty || !maximumLabelViews.isEmpty else {
                return sliderNode
            }

            var rowChildren: [ViewNode] = []
            if !minimumLabelViews.isEmpty {
                rowChildren.append(minimumLabelComponent.makeNode(runtime: runtime))
            }
            rowChildren.append(sliderNode)
            if !maximumLabelViews.isEmpty {
                rowChildren.append(maximumLabelComponent.makeNode(runtime: runtime))
            }

            let rowNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: rowChildren
            )

            guard !labelViews.isEmpty else {
                return rowNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 6, alignment: .stretch),
                isHitTestVisible: false,
                children: [labelNode, rowNode]
            )
        }
    }

    private static func snappedValue(_ value: Double, in bounds: ClosedRange<Double>, step: Double?) -> Double {
        let clampedValue = min(max(value, bounds.lowerBound), bounds.upperBound)
        guard let step, step.isFinite, step > 0 else {
            return clampedValue
        }
        if clampedValue <= bounds.lowerBound {
            return bounds.lowerBound
        }
        if clampedValue >= bounds.upperBound {
            return bounds.upperBound
        }

        let snapped = ((clampedValue - bounds.lowerBound) / step).rounded() * step + bounds.lowerBound
        return min(max(snapped, bounds.lowerBound), bounds.upperBound)
    }

    private static func doubleBinding<Value: BinaryFloatingPoint>(_ value: Binding<Value>) -> Binding<Double> {
        Binding<Double>(
            get: {
                Double(value.wrappedValue)
            },
            set: { newValue in
                value.wrappedValue = Value(newValue)
            }
        )
    }

    private static func doubleRange<Value: BinaryFloatingPoint>(_ bounds: ClosedRange<Value>) -> ClosedRange<Double> {
        Double(bounds.lowerBound)...Double(bounds.upperBound)
    }
}
@MainActor
public struct ProgressView: View {
    public typealias Body = Never

    private let value: Double?
    private let total: Double
    private let label: [AnyView]
    private let currentValueLabel: [AnyView]

    public init<Value: BinaryFloatingPoint>(value: Value?, total: Value = 1.0) {
        self.init(value: value.map { Double($0) }, total: Double(total))
    }

    public init(value: Double? = nil, total: Double = 1.0) {
        self.value = value
        self.total = total
        self.label = []
        self.currentValueLabel = []
    }

    public init<Value: BinaryFloatingPoint>(_ title: String, value: Value?, total: Value = 1.0) {
        self.init(title, value: value.map { Double($0) }, total: Double(total))
    }

    public init(_ title: String, value: Double? = nil, total: Double = 1.0) {
        self.value = value
        self.total = total
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.5, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.currentValueLabel = []
    }

    public init<S: StringProtocol, Value: BinaryFloatingPoint>(_ title: S, value: Value?, total: Value = 1.0) {
        self.init(String(title), value: value, total: total)
    }

    public init<S: StringProtocol>(_ title: S, value: Double? = nil, total: Double = 1.0) {
        self.init(String(title), value: value, total: total)
    }

    public init<Value: BinaryFloatingPoint>(_ titleKey: LocalizedStringKey, value: Value?, total: Value = 1.0) {
        self.init(titleKey.resolvedString, value: value, total: total)
    }

    public init(_ titleKey: LocalizedStringKey, value: Double? = nil, total: Double = 1.0) {
        self.init(titleKey.resolvedString, value: value, total: total)
    }

    public init<Value: BinaryFloatingPoint>(
        value: Value?,
        total: Value = 1.0,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.init(value: value.map { Double($0) }, total: Double(total), label: label)
    }

    public init(value: Double? = nil, total: Double = 1.0, @ViewBuilder label: () -> [AnyView]) {
        self.value = value
        self.total = total
        self.label = label()
        self.currentValueLabel = []
    }

    public init<Value: BinaryFloatingPoint>(
        value: Value?,
        total: Value = 1.0,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.init(
            value: value.map { Double($0) },
            total: Double(total),
            label: label,
            currentValueLabel: currentValueLabel
        )
    }

    public init(
        value: Double? = nil,
        total: Double = 1.0,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = value
        self.total = total
        self.label = label()
        self.currentValueLabel = currentValueLabel()
    }

    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true) {
        self.value = Self.timerProgressValue(timerInterval: timerInterval, countsDown: countsDown)
        self.total = 1.0
        self.label = []
        self.currentValueLabel = []
    }

    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = Self.timerProgressValue(timerInterval: timerInterval, countsDown: countsDown)
        self.total = 1.0
        self.label = label()
        self.currentValueLabel = []
    }

    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = Self.timerProgressValue(timerInterval: timerInterval, countsDown: countsDown)
        self.total = 1.0
        self.label = label()
        self.currentValueLabel = currentValueLabel()
    }

    public var body: Never {
        fatalError("ProgressView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 0, alignment: .leading)),
            isHitTestVisible: false
        )
        let currentValueLabelComponent = composeComponent(
            from: currentValueLabel,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let progressNode: ViewNode
            switch context.progressViewStyle.kind {
            case .circular, .timer:
                progressNode = Controls.circularProgress(
                    value: value,
                    total: total,
                    preferredSize: context.controlSize.circularProgressPreferredSize,
                    filledColor: context.tint
                )
            case .automatic, .linear:
                progressNode = Controls.progressBar(
                    value: value ?? 0,
                    total: total,
                    preferredSize: context.controlSize.progressPreferredSize,
                    filledColor: context.tint
                )
            }
            guard !context.labelsHidden else {
                return progressNode
            }

            guard !label.isEmpty || !currentValueLabel.isEmpty else {
                return progressNode
            }

            guard !currentValueLabel.isEmpty else {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    stackLayout: .vertical(spacing: 8, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [labelNode, progressNode]
                )
            }

            var headerChildren: [ViewNode] = []
            if !label.isEmpty {
                headerChildren.append(labelComponent.makeNode(runtime: runtime))
            }
            headerChildren.append(currentValueLabelComponent.makeNode(runtime: runtime))

            let headerNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: headerChildren
            )

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [headerNode, progressNode]
            )
        }
    }

    private static func timerProgressValue(timerInterval: ClosedRange<Date>, countsDown: Bool) -> Double {
        let duration = timerInterval.upperBound.timeIntervalSince(timerInterval.lowerBound)
        guard duration > 0, duration.isFinite else {
            return countsDown ? 0 : 1
        }

        let elapsed = Date().timeIntervalSince(timerInterval.lowerBound)
        let progress = min(max(elapsed / duration, 0), 1)
        return countsDown ? 1 - progress : progress
    }
}
@MainActor
public struct Gauge: View {
    public typealias Body = Never

    private let value: Double
    private let bounds: ClosedRange<Double>
    private let label: [AnyView]
    private let currentValueLabel: [AnyView]
    private let minimumValueLabel: [AnyView]
    private let maximumValueLabel: [AnyView]
    private let markedValueLabels: [AnyView]

    public init(value: Double, in bounds: ClosedRange<Double> = 0...1, @ViewBuilder label: () -> [AnyView]) {
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.currentValueLabel = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init(_ title: String, value: Double, in bounds: ClosedRange<Double> = 0...1) {
        self.value = value
        self.bounds = bounds
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 1.5, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            )
        ]
        self.currentValueLabel = []
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(_ title: String, value: V, in bounds: ClosedRange<V> = 0...1) {
        self.init(title, value: Double(value), in: Self.doubleBounds(bounds))
    }

    public init<S: StringProtocol>(_ title: S, value: Double, in bounds: ClosedRange<Double> = 0...1) {
        self.init(String(title), value: value, in: bounds)
    }

    public init<S: StringProtocol, V: BinaryFloatingPoint>(
        _ title: S,
        value: V,
        in bounds: ClosedRange<V> = 0...1
    ) {
        self.init(String(title), value: Double(value), in: Self.doubleBounds(bounds))
    }

    public init(_ titleKey: LocalizedStringKey, value: Double, in bounds: ClosedRange<Double> = 0...1) {
        self.init(titleKey.resolvedString, value: value, in: bounds)
    }

    public init<V: BinaryFloatingPoint>(
        _ titleKey: LocalizedStringKey,
        value: V,
        in bounds: ClosedRange<V> = 0...1
    ) {
        self.init(titleKey.resolvedString, value: Double(value), in: Self.doubleBounds(bounds))
    }

    public init(
        value: Double,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder markedValueLabels: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = []
        self.maximumValueLabel = []
        self.markedValueLabels = markedValueLabels()
    }

    public init(
        value: Double,
        in bounds: ClosedRange<Double> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView]
    ) {
        self.value = value
        self.bounds = bounds
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = []
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView],
        @ViewBuilder markedValueLabels: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = markedValueLabels()
    }

    public init<V: BinaryFloatingPoint>(
        value: V,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> [AnyView],
        @ViewBuilder currentValueLabel: () -> [AnyView],
        @ViewBuilder minimumValueLabel: () -> [AnyView],
        @ViewBuilder maximumValueLabel: () -> [AnyView]
    ) {
        self.value = Double(value)
        self.bounds = Self.doubleBounds(bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = []
    }

    public var body: Never {
        fatalError("Gauge has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 0, alignment: .leading)),
            isHitTestVisible: false
        )
        let currentValueLabelComponent = composeComponent(
            from: currentValueLabel,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let minimumValueLabelComponent = composeComponent(
            from: minimumValueLabel,
            context: context.withFont(.caption).withForegroundColor(.secondary),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .leading)),
            isHitTestVisible: false
        )
        let maximumValueLabelComponent = composeComponent(
            from: maximumValueLabel,
            context: context.withFont(.caption).withForegroundColor(.secondary),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .trailing)),
            isHitTestVisible: false
        )
        let markedValueLabelsComponent = composeComponent(
            from: markedValueLabels,
            context: context.withFont(.caption).withForegroundColor(.secondary),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let rangeTotal = max(0, bounds.upperBound - bounds.lowerBound)
            let gaugeValue = value - bounds.lowerBound
            let gaugeNode: ViewNode
            switch context.gaugeStyle.kind {
            case .circular, .accessoryCircular, .accessoryCircularCapacity:
                gaugeNode = Controls.circularProgress(
                    value: gaugeValue,
                    total: rangeTotal,
                    preferredSize: context.controlSize.circularProgressPreferredSize,
                    filledColor: context.tint
                )
            case .automatic, .linear, .linearCapacity, .accessoryLinear, .accessoryLinearCapacity:
                gaugeNode = Controls.progressBar(
                    value: gaugeValue,
                    total: rangeTotal,
                    preferredSize: context.controlSize.progressPreferredSize,
                    filledColor: context.tint
                )
            }
            guard !context.labelsHidden else {
                return gaugeNode
            }

            let hasHeader = !label.isEmpty || !currentValueLabel.isEmpty
            let hasBounds = !minimumValueLabel.isEmpty || !maximumValueLabel.isEmpty
            let hasMarkedLabels = !markedValueLabels.isEmpty
            guard hasHeader || hasBounds || hasMarkedLabels else {
                return gaugeNode
            }

            var children: [ViewNode] = []
            if hasHeader {
                var headerChildren: [ViewNode] = []
                if !label.isEmpty {
                    headerChildren.append(labelComponent.makeNode(runtime: runtime))
                }
                if !currentValueLabel.isEmpty {
                    headerChildren.append(currentValueLabelComponent.makeNode(runtime: runtime))
                }

                children.append(
                    Controls.stackPanel(
                        stackLayout: .horizontal(spacing: 8, alignment: .center),
                        isHitTestVisible: false,
                        children: headerChildren
                    )
                )
            }

            children.append(gaugeNode)

            if hasMarkedLabels {
                children.append(markedValueLabelsComponent.makeNode(runtime: runtime))
            }

            if hasBounds {
                var boundsChildren: [ViewNode] = []
                if !minimumValueLabel.isEmpty {
                    boundsChildren.append(minimumValueLabelComponent.makeNode(runtime: runtime))
                }
                boundsChildren.append(Controls.panel(layoutPriority: 1, isHitTestVisible: false))
                if !maximumValueLabel.isEmpty {
                    boundsChildren.append(maximumValueLabelComponent.makeNode(runtime: runtime))
                }

                children.append(
                    Controls.stackPanel(
                        stackLayout: .horizontal(spacing: 8, alignment: .center),
                        isHitTestVisible: false,
                        children: boundsChildren
                    )
                )
            }

            return Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
        }
    }

    private static func doubleBounds<V: BinaryFloatingPoint>(_ bounds: ClosedRange<V>) -> ClosedRange<Double> {
        Double(bounds.lowerBound)...Double(bounds.upperBound)
    }
}
@MainActor
public struct Link: View {
    public typealias Body = Never

    private let destination: URL
    private let label: [AnyView]

    public init(destination: URL, @ViewBuilder label: () -> [AnyView]) {
        self.destination = destination
        self.label = label()
    }

    public init(_ title: String, destination: URL) {
        self.destination = destination
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            )
        ]
    }

    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.init(String(title), destination: destination)
    }

    public init(_ titleKey: LocalizedStringKey, destination: URL) {
        self.init(titleKey.resolvedString, destination: destination)
    }

    public var body: Never {
        fatalError("Link has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context:
                context
                .withForegroundColor(context.tint)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )
        let openURL = context.environmentValues.openURL
        let destination = destination

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            return Controls.button(
                runtime: runtime,
                cornerRadius: ButtonSurfaceStyle.plain.cornerRadius,
                palette: ButtonSurfaceStyle.plain.palette,
                chrome: ButtonSurfaceStyle.plain.chrome,
                clipsToBounds: ButtonSurfaceStyle.plain.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                animation: ButtonSurfaceStyle.plain.animation,
                action: {
                    _ = openURL(destination)
                    context.invalidate()
                },
                children: [labelNode]
            )
        }
    }
}
@MainActor
public struct RenameButton: View {
    public typealias Body = Never

    private let customAction: (@MainActor () -> Void)?

    public init() {
        self.customAction = nil
    }

    public init(action: @escaping @MainActor () -> Void) {
        self.customAction = action
    }

    public var body: Never {
        fatalError("RenameButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let rename: (@MainActor () -> Void)?
        if let customAction {
            rename = customAction
        } else {
            if let renameAction = context.environmentValues.rename {
                rename = { renameAction() }
            } else {
                rename = nil
            }
        }
        return Button("Rename") {
            rename?()
        }
        .disabled(rename == nil)
        .makeComponent(context: context)
    }
}
@MainActor
public struct NewDocumentButton: View {
    public typealias Body = Never

    private let title: String
    private let customAction: (@MainActor () -> Void)?

    public init(_ title: String = "New Document") {
        self.title = title
        self.customAction = nil
    }

    public init(_ titleKey: LocalizedStringKey) {
        self.title = titleKey.resolvedString
        self.customAction = nil
    }

    public init(action: @escaping @MainActor () -> Void) {
        self.title = "New Document"
        self.customAction = action
    }

    public var body: Never {
        fatalError("NewDocumentButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let action: @MainActor () -> Void
        if let customAction {
            action = customAction
        } else {
            let newDocument = context.environmentValues.newDocument
            action = { newDocument() }
        }
        return Button(title) {
            action()
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct DefaultSettingsLinkLabel: View {
    public init() {}

    public var body: some View {
        Text("Settings")
    }
}
@MainActor
public struct SettingsLink: View {
    public typealias Body = Never

    private let label: [AnyView]

    public init() {
        self.label = [AnyView(DefaultSettingsLinkLabel())]
    }

    public init(@ViewBuilder label: () -> [AnyView]) {
        self.label = label()
    }

    public var body: Never {
        fatalError("SettingsLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let openSettings = context.environmentValues.openSettings
        return Button {
            openSettings()
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct HelpLink: View {
    public typealias Body = Never

    private let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }

    public var body: Never {
        fatalError("HelpLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let openURL = context.environmentValues.openURL
        return Button {
            openURL(destination)
        } label: {
            [AnyView(Text("Help"))]
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct SharePreview {
    public let title: String
    public let image: Image?

    public init(_ title: String, image: Image) {
        self.title = title
        self.image = image
    }

    public init(_ title: String, icon: Image) {
        self.title = title
        self.image = icon
    }
}
@MainActor
public struct ShareLink: View {
    public typealias Body = Never

    private let items: [Any]
    private let subject: String?
    private let message: String?
    private let preview: SharePreview?
    private let label: [AnyView]

    public init(
        item: some Transferable,
        preview: SharePreview? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.items = [item]
        self.subject = nil
        self.message = nil
        self.preview = preview
        self.label = label()
    }

    public init(
        items: [some Transferable],
        preview: SharePreview? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.items = items
        self.subject = nil
        self.message = nil
        self.preview = preview
        self.label = label()
    }

    public init(
        item: some Transferable,
        subject: String?,
        message: String?,
        preview: SharePreview? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.items = [item]
        self.subject = subject
        self.message = message
        self.preview = preview
        self.label = label()
    }

    public init(
        items: [some Transferable],
        subject: String?,
        message: String?,
        preview: SharePreview? = nil,
        @ViewBuilder label: () -> [AnyView]
    ) {
        self.items = items
        self.subject = subject
        self.message = message
        self.preview = preview
        self.label = label()
    }

    public init(
        item: some Transferable,
        preview: SharePreview? = nil
    ) {
        self.init(
            item: item, preview: preview,
            label: {
                Label("Share", systemImage: "square.and.arrow.up")
            })
    }

    public init(
        items: [some Transferable],
        preview: SharePreview? = nil
    ) {
        self.init(
            items: items, preview: preview,
            label: {
                Label("Share", systemImage: "square.and.arrow.up")
            })
    }

    public init(
        item: some Transferable,
        subject: String?,
        message: String?,
        preview: SharePreview? = nil
    ) {
        self.init(
            item: item, subject: subject, message: message, preview: preview,
            label: {
                Label("Share", systemImage: "square.and.arrow.up")
            })
    }

    public init(
        items: [some Transferable],
        subject: String?,
        message: String?,
        preview: SharePreview? = nil
    ) {
        self.init(
            items: items, subject: subject, message: message, preview: preview,
            label: {
                Label("Share", systemImage: "square.and.arrow.up")
            })
    }

    public init(_ title: String, item: some Transferable) {
        self.init(
            item: item,
            label: {
                Label(title, systemImage: "square.and.arrow.up")
            })
    }

    public init<S: StringProtocol>(_ title: S, item: some Transferable) {
        self.init(String(title), item: item)
    }

    public init(_ titleKey: LocalizedStringKey, item: some Transferable) {
        self.init(titleKey.resolvedString, item: item)
    }

    public init(_ title: String, items: [some Transferable]) {
        self.init(
            items: items,
            label: {
                Label(title, systemImage: "square.and.arrow.up")
            })
    }

    public init<S: StringProtocol>(_ title: S, items: [some Transferable]) {
        self.init(String(title), items: items)
    }

    public init(_ titleKey: LocalizedStringKey, items: [some Transferable]) {
        self.init(titleKey.resolvedString, items: items)
    }

    public var body: Never {
        fatalError("ShareLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let items = items
        let _ = subject
        let _ = message
        let _ = preview
        return Button {
            ClipboardManager.copyItems(items)
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@available(macOS 16.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@MainActor
public struct ShortcutsLink: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ShortcutsLink has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 120, height: 32), isHitTestVisible: true)
        }
    }
}
@available(macOS 16.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@MainActor
public struct ShortcutsButton: View {
    public typealias Body = Never

    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    public var body: Never {
        fatalError("ShortcutsButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Button {
            action()
        } label: {
            Text("Shortcuts")
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct LocationButton: View {
    public typealias Body = Never

    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    public var body: Never {
        fatalError("LocationButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Button {
            action()
        } label: {
            Text("Location")
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct PasteButton: View {
    public typealias Body = Never

    private let supportedContentTypes: [UTType]
    private let onPaste: @MainActor ([Any]) -> Void
    private let label: [AnyView]

    public init(
        supportedContentTypes: [UTType],
        @ViewBuilder label: () -> [AnyView],
        onPaste: @escaping @MainActor ([Any]) -> Void
    ) {
        self.supportedContentTypes = supportedContentTypes
        self.label = label()
        self.onPaste = onPaste
    }

    public init(
        supportedContentTypes: [UTType],
        onPaste: @escaping @MainActor ([Any]) -> Void
    ) {
        self.init(
            supportedContentTypes: supportedContentTypes,
            label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            },
            onPaste: onPaste
        )
    }

    public init(
        payloadType: UTType,
        @ViewBuilder label: () -> [AnyView],
        onPaste: @escaping @MainActor ([Any]) -> Void
    ) {
        self.init(supportedContentTypes: [payloadType], label: label, onPaste: onPaste)
    }

    public init(
        payloadType: UTType,
        onPaste: @escaping @MainActor ([Any]) -> Void
    ) {
        self.init(supportedContentTypes: [payloadType], onPaste: onPaste)
    }

    public var body: Never {
        fatalError("PasteButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let types = supportedContentTypes
        let onPaste = onPaste
        return Button {
            let items = ClipboardManager.pasteItems(for: types)
            onPaste(items)
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct CopyButton: View {
    public typealias Body = Never

    private let items: [Any]
    private let label: [AnyView]

    public init(
        @ViewBuilder label: () -> [AnyView],
        items: [Any]
    ) {
        self.label = label()
        self.items = items
    }

    public init(
        @ViewBuilder label: () -> [AnyView],
        item: Any
    ) {
        self.init(label: label, items: [item])
    }

    public init(items: [Any]) {
        self.init(
            label: {
                Label("Copy", systemImage: "doc.on.doc")
            }, items: items)
    }

    public init(item: Any) {
        self.init(items: [item])
    }

    public var body: Never {
        fatalError("CopyButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let items = items
        return Button {
            ClipboardManager.copyItems(items)
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct CutButton: View {
    public typealias Body = Never

    private let items: [Any]
    private let label: [AnyView]

    public init(
        @ViewBuilder label: () -> [AnyView],
        items: [Any]
    ) {
        self.label = label()
        self.items = items
    }

    public init(
        @ViewBuilder label: () -> [AnyView],
        item: Any
    ) {
        self.init(label: label, items: [item])
    }

    public init(items: [Any]) {
        self.init(
            label: {
                Label("Cut", systemImage: "scissors")
            }, items: items)
    }

    public init(item: Any) {
        self.init(items: [item])
    }

    public var body: Never {
        fatalError("CutButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let items = items
        return Button {
            ClipboardManager.copyItems(items)
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct DeleteButton: View {
    public typealias Body = Never

    private let items: [Any]
    private let label: [AnyView]

    public init(
        @ViewBuilder label: () -> [AnyView],
        items: [Any]
    ) {
        self.label = label()
        self.items = items
    }

    public init(
        @ViewBuilder label: () -> [AnyView],
        item: Any
    ) {
        self.init(label: label, items: [item])
    }

    public init(items: [Any]) {
        self.init(
            label: {
                Label("Delete", systemImage: "trash")
            }, items: items)
    }

    public init(item: Any) {
        self.init(items: [item])
    }

    public var body: Never {
        fatalError("DeleteButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let items = items
        return Button {
            let fileURLs = items.compactMap { $0 as? URL }
            if !fileURLs.isEmpty {
                FileDialogManager.moveToRecycleBin(fileURLs: fileURLs)
            }
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct ExportButton: View {
    public typealias Body = Never

    private let items: [Any]
    private let label: [AnyView]

    public init(
        @ViewBuilder label: () -> [AnyView],
        items: [Any]
    ) {
        self.label = label()
        self.items = items
    }

    public init(
        @ViewBuilder label: () -> [AnyView],
        item: Any
    ) {
        self.init(label: label, items: [item])
    }

    public init(items: [Any]) {
        self.init(
            label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }, items: items)
    }

    public init(item: Any) {
        self.init(items: [item])
    }

    public var body: Never {
        fatalError("ExportButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let items = items
        return Button {
            ClipboardManager.copyItems(items)
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@MainActor
public struct ImportButton: View {
    public typealias Body = Never

    private let supportedContentTypes: [UTType]
    private let onImport: @MainActor ([Any]) -> Void
    private let label: [AnyView]

    public init(
        supportedContentTypes: [UTType],
        @ViewBuilder label: () -> [AnyView],
        onImport: @escaping @MainActor ([Any]) -> Void
    ) {
        self.supportedContentTypes = supportedContentTypes
        self.label = label()
        self.onImport = onImport
    }

    public init(
        supportedContentTypes: [UTType],
        onImport: @escaping @MainActor ([Any]) -> Void
    ) {
        self.init(
            supportedContentTypes: supportedContentTypes,
            label: {
                Label("Import", systemImage: "square.and.arrow.down")
            },
            onImport: onImport
        )
    }

    public var body: Never {
        fatalError("ImportButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let label = label
        let onImport = onImport
        return Button {
            let urls = FileDialogManager.showOpenFileDialog(
                allowsMultipleSelection: true
            )
            if !urls.isEmpty {
                onImport(urls)
            }
        } label: {
            label
        }
        .makeComponent(context: context)
    }
}
@MainActor
public struct Button: View {
    public typealias Body = Never

    let action: @MainActor () -> Void
    private let label: [AnyView]
    let role: ButtonRole?
    private var style: ButtonSurfaceStyle
    private var resolvedButtonStyle: ButtonStyle
    private var hasCustomSurfaceStyle: Bool
    var _storedTitle: String?

    public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = nil
    }

    public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> [AnyView]) {
        self.action = action
        self.label = label()
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = nil
    }

    public init(_ title: String, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            )
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = title
    }

    public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
        self.init(String(title), action: action)
    }

    public init(_ title: String, image name: String, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: name))
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = title
    }

    public init<S: StringProtocol>(_ title: S, image name: String, action: @escaping @MainActor () -> Void) {
        self.init(String(title), image: name, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, image: name, action: action)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: resource))
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = String(title)
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource, action: @escaping @MainActor () -> Void)
    {
        self.init(titleKey.resolvedString, image: resource, action: action)
    }

    public init(_ title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, systemImage: systemImage))
        ]
        self.role = nil
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = title
    }

    public init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(String(title), systemImage: systemImage, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, systemImage: systemImage, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, action: action)
    }

    public init(_ title: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(
                Text(title)
                    .font(.system(size: 2, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            )
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = title
    }

    public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(String(title), role: role, action: action)
    }

    public init(_ title: String, image name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: name))
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = title
    }

    public init<S: StringProtocol>(
        _ title: S, image name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void
    ) {
        self.init(String(title), image: name, role: role, action: action)
    }

    public init(
        _ titleKey: LocalizedStringKey, image name: String, role: ButtonRole?, action: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, image: name, role: role, action: action)
    }

    public init<S: StringProtocol>(
        _ title: S, image resource: ImageResource, role: ButtonRole?, action: @escaping @MainActor () -> Void
    ) {
        self.action = action
        self.label = [
            AnyView(Label(title, image: resource))
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = String(title)
    }

    public init(
        _ titleKey: LocalizedStringKey, image resource: ImageResource, role: ButtonRole?,
        action: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, image: resource, role: role, action: action)
    }

    public init(_ title: String, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.action = action
        self.label = [
            AnyView(Label(title, systemImage: systemImage))
        ]
        self.role = role
        self.style = .default
        self.resolvedButtonStyle = .automatic
        self.hasCustomSurfaceStyle = false
        self._storedTitle = title
    }

    public init<S: StringProtocol>(
        _ title: S, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void
    ) {
        self.init(String(title), systemImage: systemImage, role: role, action: action)
    }

    public init(
        _ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void
    ) {
        self.init(titleKey.resolvedString, systemImage: systemImage, role: role, action: action)
    }

    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(titleKey.resolvedString, role: role, action: action)
    }

    public var body: Never {
        fatalError("Button has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let labelComponent = composeComponent(
            from: label,
            context: context,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let buttonStyle =
                resolvedButtonStyle == .automatic && !hasCustomSurfaceStyle ? context.buttonStyle : resolvedButtonStyle
            let surfaceStyle = resolvedSurfaceStyle(for: buttonStyle, context: context)
            let buttonBorderShape = context.environmentValues.buttonBorderShape
            let node = Controls.button(
                runtime: runtime,
                layoutPriority: context.environmentValues.buttonSizing.retainedLayoutPriority,
                cornerRadius: buttonBorderShape.retainedCornerRadius(default: surfaceStyle.cornerRadius),
                palette: surfaceStyle.palette,
                chrome: surfaceStyle.chrome,
                clipsToBounds: surfaceStyle.clipsToBounds,
                layoutMode: .stack(.vertical(alignment: .stretch, mainAlignment: .center)),
                isEnabled: context.isEnabled,
                repeatBehavior: context.environmentValues.buttonRepeatBehavior.retainedBehavior,
                animation: surfaceStyle.animation,
                action: {
                    ViewBuildContextScope.withCurrent(context) {
                        action()
                    }
                    context.invalidate()
                },
                children: [labelNode]
            )
            buttonBorderShape.applyRetainedDynamicCornerRadius(to: node)
            return node
        }
    }

    public func buttonSurface(_ style: ButtonSurfaceStyle) -> Button {
        var copy = self
        copy.style = style
        copy.resolvedButtonStyle = .automatic
        copy.hasCustomSurfaceStyle = true
        return copy
    }

    public func buttonStyle(_ style: ButtonStyle) -> Button {
        var copy = self
        copy.resolvedButtonStyle = style
        return copy
    }

    private func resolvedSurfaceStyle(for buttonStyle: ButtonStyle, context: ViewBuildContext) -> ButtonSurfaceStyle {
        if buttonStyle == .borderedProminent {
            return ButtonSurfaceStyle(
                cornerRadius: 16,
                palette: SurfacePalette(
                    idle: context.tint.opacity(0.84),
                    hovered: context.tint.opacity(0.92),
                    focused: context.tint.opacity(0.98),
                    pressed: context.tint,
                    activated: context.tint,
                    disabledBackground: Color(red: 0.20, green: 0.24, blue: 0.30, alpha: 0.50),
                    disabledForeground: Color(red: 0.66, green: 0.70, blue: 0.78, alpha: 0.72),
                    disabledBorder: Color(red: 0.50, green: 0.58, blue: 0.68, alpha: 0.20)
                ),
                chrome: SurfaceChrome(
                    borderColor: context.tint.opacity(0.34),
                    borderHoveredColor: context.tint.opacity(0.48),
                    borderFocusedColor: context.tint.opacity(0.60),
                    borderPressedColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.38),
                    borderWidth: 1,
                    focusRingColor: context.tint.opacity(0.34),
                    focusRingWidth: 2,
                    shadowColor: context.tint.opacity(0.20),
                    shadowHoveredColor: context.tint.opacity(0.26),
                    shadowFocusedColor: context.tint.opacity(0.32),
                    shadowPressedColor: context.tint.opacity(0.12),
                    shadowOffset: Point(x: 0, y: 14),
                    shadowSpread: 8
                ),
                clipsToBounds: true,
                animation: .default
            )
        }

        guard buttonStyle == .automatic else {
            return buttonStyle.surfaceStyle
        }

        if hasCustomSurfaceStyle {
            return style
        }

        switch role {
        case .destructive:
            return .destructive
        case .cancel, .none:
            return style
        }
    }
}
@MainActor
public struct EditButton: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("EditButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let editMode = context.environmentValues.editMode
        let isEditing = editMode?.wrappedValue.isEditing == true
        return Button(isEditing ? "Done" : "Edit") {
            guard let editMode else {
                return
            }

            editMode.wrappedValue = isEditing ? .inactive : .active
        }
        .disabled(editMode == nil)
        .makeComponent(context: context)
    }
}
public struct HelpButton: View {
    public typealias Body = Never

    public let action: (@MainActor () -> Void)?

    public init(action: (@MainActor () -> Void)? = nil) {
        self.action = action
    }

    public var body: Never {
        fatalError("HelpButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Button("?") {
            action?()
        }.makeComponent(context: context)
    }
}
public struct CloseButton: View {
    public typealias Body = Never

    public let action: (@MainActor () -> Void)?

    public init(action: (@MainActor () -> Void)? = nil) {
        self.action = action
    }

    public var body: Never {
        fatalError("CloseButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Button("X") {
            action?()
        }.makeComponent(context: context)
    }
}
public struct BackButton: View {
    public typealias Body = Never

    public let action: (@MainActor () -> Void)?

    public init(action: (@MainActor () -> Void)? = nil) {
        self.action = action
    }

    public var body: Never {
        fatalError("BackButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Button("<") {
            action?()
        }.makeComponent(context: context)
    }
}
@MainActor
public struct HSplitView: View {
    public typealias Body = Never

    private let ratio: Double?
    private let minPrimaryExtent: Double
    private let minSecondaryExtent: Double
    private let dividerThickness: Double
    private let dividerIdleColor: Color
    private let dividerHoverColor: Color
    private let dividerActiveColor: Color
    private let onRatioChanged: ((Double) -> Void)?
    private let content: [AnyView]

    public init(
        ratio: Double? = nil,
        minPrimaryExtent: Double = 180,
        minSecondaryExtent: Double = 220,
        dividerThickness: Double = 16,
        dividerIdleColor: Color = Color(red: 0.36, green: 0.46, blue: 0.58, alpha: 0.10),
        dividerHoverColor: Color = Color(red: 0.50, green: 0.64, blue: 0.80, alpha: 0.28),
        dividerActiveColor: Color = Color(red: 0.70, green: 0.84, blue: 0.98, alpha: 0.48),
        onRatioChanged: ((Double) -> Void)? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.ratio = ratio
        self.minPrimaryExtent = minPrimaryExtent
        self.minSecondaryExtent = minSecondaryExtent
        self.dividerThickness = dividerThickness
        self.dividerIdleColor = dividerIdleColor
        self.dividerHoverColor = dividerHoverColor
        self.dividerActiveColor = dividerActiveColor
        self.onRatioChanged = onRatioChanged
        self.content = content()
    }

    public var body: Never {
        fatalError("HSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        splitComponent(axis: .horizontal, context: context)
    }
}
@MainActor
public struct VSplitView: View {
    public typealias Body = Never

    private let ratio: Double?
    private let minPrimaryExtent: Double
    private let minSecondaryExtent: Double
    private let dividerThickness: Double
    private let dividerIdleColor: Color
    private let dividerHoverColor: Color
    private let dividerActiveColor: Color
    private let onRatioChanged: ((Double) -> Void)?
    private let content: [AnyView]

    public init(
        ratio: Double? = nil,
        minPrimaryExtent: Double = 180,
        minSecondaryExtent: Double = 220,
        dividerThickness: Double = 16,
        dividerIdleColor: Color = Color(red: 0.36, green: 0.46, blue: 0.58, alpha: 0.10),
        dividerHoverColor: Color = Color(red: 0.50, green: 0.64, blue: 0.80, alpha: 0.28),
        dividerActiveColor: Color = Color(red: 0.70, green: 0.84, blue: 0.98, alpha: 0.48),
        onRatioChanged: ((Double) -> Void)? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.ratio = ratio
        self.minPrimaryExtent = minPrimaryExtent
        self.minSecondaryExtent = minSecondaryExtent
        self.dividerThickness = dividerThickness
        self.dividerIdleColor = dividerIdleColor
        self.dividerHoverColor = dividerHoverColor
        self.dividerActiveColor = dividerActiveColor
        self.onRatioChanged = onRatioChanged
        self.content = content()
    }

    public var body: Never {
        fatalError("VSplitView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        splitComponent(axis: .vertical, context: context)
    }
}
extension HSplitView {
    fileprivate func splitComponent(axis: SplitAxis, context: ViewBuildContext) -> Component {
        buildSplitComponent(
            content: content,
            axis: axis,
            ratio: ratio,
            minPrimaryExtent: minPrimaryExtent,
            minSecondaryExtent: minSecondaryExtent,
            dividerThickness: dividerThickness,
            dividerIdleColor: dividerIdleColor,
            dividerHoverColor: dividerHoverColor,
            dividerActiveColor: dividerActiveColor,
            onRatioChanged: onRatioChanged,
            context: context
        )
    }
}
extension VSplitView {
    fileprivate func splitComponent(axis: SplitAxis, context: ViewBuildContext) -> Component {
        buildSplitComponent(
            content: content,
            axis: axis,
            ratio: ratio,
            minPrimaryExtent: minPrimaryExtent,
            minSecondaryExtent: minSecondaryExtent,
            dividerThickness: dividerThickness,
            dividerIdleColor: dividerIdleColor,
            dividerHoverColor: dividerHoverColor,
            dividerActiveColor: dividerActiveColor,
            onRatioChanged: onRatioChanged,
            context: context
        )
    }
}
@MainActor
private func buildSplitComponent(
    content: [AnyView],
    axis: SplitAxis,
    ratio: Double?,
    minPrimaryExtent: Double,
    minSecondaryExtent: Double,
    dividerThickness: Double,
    dividerIdleColor: Color,
    dividerHoverColor: Color,
    dividerActiveColor: Color,
    onRatioChanged: ((Double) -> Void)?,
    context: ViewBuildContext
) -> Component {
    let primaryViews = content.isEmpty ? [] : [content[0]]
    let secondaryViews = content.count > 1 ? Array(content.dropFirst()) : []
    let primaryComponent = composeComponent(from: primaryViews, context: context)
    let secondaryComponent = composeComponent(
        from: secondaryViews,
        context: context,
        fallbackLayout: .stack(.vertical(alignment: .stretch))
    )

    return Component { runtime in
        let primaryNode = primaryComponent.makeNode(runtime: runtime)
        let secondaryNode = secondaryComponent.makeNode(runtime: runtime)
        let defaultExtent = axis == .horizontal ? context.canvasSize.width : context.canvasSize.height
        let primaryExtent =
            axis == .horizontal ? primaryNode.intrinsicContentSize().width : primaryNode.intrinsicContentSize().height
        let inferredRatio = max(0.1, min(0.9, primaryExtent / max(1, defaultExtent - dividerThickness)))

        return Controls.splitView(
            runtime: runtime,
            axis: axis,
            ratio: ratio ?? inferredRatio,
            minPrimaryExtent: minPrimaryExtent,
            minSecondaryExtent: minSecondaryExtent,
            dividerThickness: dividerThickness,
            dividerIdleColor: dividerIdleColor,
            dividerHoverColor: dividerHoverColor,
            dividerActiveColor: dividerActiveColor,
            onRatioChanged: onRatioChanged,
            primary: [primaryNode],
            secondary: [secondaryNode]
        )
    }
}
private func resolvedSymbolIcon(for systemName: String, variants: SymbolVariants = .none) -> SymbolIcon {
    let resolvedName =
        variants.contains(.fill) && !systemName.hasSuffix(".fill")
        ? "\(systemName).fill"
        : systemName

    switch resolvedName {
    case "magnifyingglass":
        return .search
    case "folder", "folder.fill":
        return .folder
    case "gear", "gear.fill", "gearshape", "gearshape.fill":
        return .settings
    case "bolt", "bolt.fill":
        return .lightning
    case "rectangle.3.group", "rectangle.3.group.fill", "square.grid.3x1.folder.badge.plus",
        "square.grid.2x2", "square.grid.2x2.fill", "rectangle.grid.3x2", "rectangle.grid.3x2.fill":
        return .layout
    case "keyboard", "keyboard.fill":
        return .keyboard
    case "sparkles", "sparkle":
        return .sparkle
    case "info", "info.fill", "info.circle", "info.circle.fill":
        return .info
    case "waveform.path.ecg", "waveform.path.ecg.fill", "chart.line.uptrend.xyaxis",
        "chart.line.uptrend.xyaxis.fill", "waveform":
        return .activity
    case "doc", "doc.fill", "doc.text", "doc.text.fill", "textformat", "textformat.fill",
        "text.alignleft", "text.alignright", "text.aligncenter":
        return .document
    case "rectangle.split.3x1", "rectangle.split.3x1.fill", "rectangle.split.2x1",
        "rectangle.split.2x1.fill", "square.split.2x1", "square.split.2x1.fill":
        return .split
    case "switch.2", "switch.2.fill", "togglepower", "power", "power.circle",
        "slider.horizontal.3", "switch.programmable", "switch.programmable.fill":
        return .settings
    case "checkmark", "checkmark.circle", "checkmark.circle.fill", "checkmark.square",
        "checkmark.square.fill":
        return .checkmark
    case "chevron.down", "chevron.down.circle", "chevron.down.circle.fill", "arrowtriangle.down",
        "arrowtriangle.down.fill":
        return .chevronDown
    default:
        return .sparkle
    }
}
private struct ResolvedTextInputStyle {
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: Double
    var cornerRadius: Double
    var padding: EdgeInsets
}
extension TextFieldStyle {
    fileprivate func resolvedTextInputStyle(isEnabled: Bool) -> ResolvedTextInputStyle {
        switch kind {
        case .automatic, .roundedBorder:
            return ResolvedTextInputStyle(
                backgroundColor: isEnabled
                    ? Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.82)
                    : Color(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.58),
                borderColor: isEnabled
                    ? Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.18)
                    : Color(red: 0.45, green: 0.48, blue: 0.52, alpha: 0.20),
                borderWidth: 1,
                cornerRadius: 8,
                padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            )
        case .squareBorder:
            return ResolvedTextInputStyle(
                backgroundColor: isEnabled
                    ? Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.82)
                    : Color(red: 0.08, green: 0.09, blue: 0.11, alpha: 0.58),
                borderColor: isEnabled
                    ? Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.18)
                    : Color(red: 0.45, green: 0.48, blue: 0.52, alpha: 0.20),
                borderWidth: 1,
                cornerRadius: 0,
                padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            )
        case .plain:
            return ResolvedTextInputStyle(
                backgroundColor: .clear,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0,
                padding: EdgeInsets(top: 7, leading: 0, bottom: 7, trailing: 0)
            )
        }
    }
}
private func textFieldInsertedCharacter(
    for event: KeyboardEvent,
    allowsNewlines: Bool,
    currentText: String,
    textInputAutocapitalization: TextInputAutocapitalization?
) -> String? {
    let insertedCharacter: String
    if event.key == .enter {
        guard allowsNewlines else {
            return nil
        }
        insertedCharacter = "\n"
        return insertedCharacter
    }

    if event.key == .space {
        insertedCharacter = " "
        return insertedCharacter
    }

    switch event.keyCode {
    case 0x30...0x39:
        insertedCharacter = String(UnicodeScalar(event.keyCode)!)
    case 0x41...0x5A:
        guard let scalar = UnicodeScalar(event.keyCode) else {
            return nil
        }

        let character = String(scalar)
        insertedCharacter = event.modifiers.contains(.shift) ? character : character.lowercased()
    case 0xBA:
        insertedCharacter = event.modifiers.contains(.shift) ? ":" : ";"
    case 0xBB:
        insertedCharacter = event.modifiers.contains(.shift) ? "+" : "="
    case 0xBC:
        insertedCharacter = event.modifiers.contains(.shift) ? "<" : ","
    case 0xBD:
        insertedCharacter = event.modifiers.contains(.shift) ? "_" : "-"
    case 0xBE:
        insertedCharacter = event.modifiers.contains(.shift) ? ">" : "."
    case 0xBF:
        insertedCharacter = event.modifiers.contains(.shift) ? "?" : "/"
    default:
        return nil
    }

    return autocapitalizedInsertedCharacter(
        insertedCharacter,
        currentText: currentText,
        textInputAutocapitalization: textInputAutocapitalization
    )
}
private func clampedTextOffset(_ offset: Int, in text: String) -> Int {
    min(max(0, offset), text.count)
}
extension String {
    fileprivate func textPrefix(upTo offset: Int) -> String {
        let clampedOffset = clampedTextOffset(offset, in: self)
        return String(prefix(clampedOffset))
    }

    fileprivate func insertingText(_ insertedText: String, at offset: Int) -> String {
        let clampedOffset = clampedTextOffset(offset, in: self)
        let insertionIndex = index(startIndex, offsetBy: clampedOffset)
        var copy = self
        copy.insert(contentsOf: insertedText, at: insertionIndex)
        return copy
    }

    fileprivate func removingText(in offsets: Range<Int>) -> String {
        let lowerBound = clampedTextOffset(offsets.lowerBound, in: self)
        let upperBound = clampedTextOffset(offsets.upperBound, in: self)
        guard lowerBound < upperBound else {
            return self
        }

        let lowerIndex = index(startIndex, offsetBy: lowerBound)
        let upperIndex = index(startIndex, offsetBy: upperBound)
        var copy = self
        copy.removeSubrange(lowerIndex..<upperIndex)
        return copy
    }

    fileprivate func replacingText(in offsets: Range<Int>, with replacement: String) -> String {
        let lowerBound = clampedTextOffset(offsets.lowerBound, in: self)
        let upperBound = clampedTextOffset(offsets.upperBound, in: self)
        let lowerIndex = index(startIndex, offsetBy: lowerBound)
        let upperIndex = index(startIndex, offsetBy: upperBound)
        var copy = self
        copy.replaceSubrange(lowerIndex..<upperIndex, with: replacement)
        return copy
    }
}
private func autocapitalizedInsertedCharacter(
    _ character: String,
    currentText: String,
    textInputAutocapitalization: TextInputAutocapitalization?
) -> String {
    switch textInputAutocapitalization {
    case .characters:
        return character.uppercased()
    case .words:
        return currentText.last.map { $0.isWhitespace || $0.isNewline } ?? true
            ? character.uppercased()
            : character
    case .sentences:
        guard shouldCapitalizeSentenceInsertion(after: currentText) else {
            return character
        }
        return character.uppercased()
    case .never, nil:
        return character
    }
}
private func shouldCapitalizeSentenceInsertion(after text: String) -> Bool {
    guard let lastCharacter = text.last else {
        return true
    }
    if lastCharacter.isNewline {
        return true
    }
    guard let lastMeaningfulCharacter = text.last(where: { !$0.isWhitespace && !$0.isNewline }) else {
        return true
    }
    return lastMeaningfulCharacter == "." || lastMeaningfulCharacter == "!" || lastMeaningfulCharacter == "?"
}
@MainActor
public struct Canvas: View {
    public typealias Body = Never

    private let renderer: @MainActor (inout GraphicsContext, CGSize) -> Void

    public init(renderer: @escaping @MainActor (inout GraphicsContext, CGSize) -> Void) {
        self.renderer = renderer
    }

    public init<F: View>(
        renderer: @escaping @MainActor (inout GraphicsContext, CGSize) -> Void,
        symbols: @escaping () -> F
    ) {
        self.renderer = renderer
    }

    public var body: Never {
        fatalError("Canvas has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        SwiftWindowsUI.UI.canvas { runtimeContext, size in
            var graphicsContext = GraphicsContext()
            graphicsContext.underlying = runtimeContext
            self.renderer(&graphicsContext, size)
            runtimeContext = graphicsContext.underlying
        }
    }
}
public struct Map: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("Map has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "Map", systemImage: "map", preferredSize: Size(width: 300, height: 200))
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct MapStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case standard
        case imagery
        case hybrid
    }
    public let kind: Kind

    public static let standard = MapStyle(kind: .standard)
    public static let imagery = MapStyle(kind: .imagery)
    public static let hybrid = MapStyle(kind: .hybrid)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct MapCameraPosition: Sendable, Equatable {
    public indirect enum Kind: Sendable, Equatable {
        case automatic
        case region(latitude: Double, longitude: Double, latitudeDelta: Double, longitudeDelta: Double)
        case item(latitude: Double, longitude: Double)
        case rect(minLatitude: Double, minLongitude: Double, maxLatitude: Double, maxLongitude: Double)
        case userLocation(fallback: MapCameraPosition)
        case camera(latitude: Double, longitude: Double, distance: Double)
    }
    public let kind: Kind

    public static let automatic = MapCameraPosition(kind: .automatic)

    public static func region(
        centerLatitude: Double,
        centerLongitude: Double,
        latitudeDelta: Double,
        longitudeDelta: Double
    ) -> MapCameraPosition {
        MapCameraPosition(
            kind: .region(
                latitude: centerLatitude,
                longitude: centerLongitude,
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            ))
    }

    public static func item(latitude: Double, longitude: Double) -> MapCameraPosition {
        MapCameraPosition(kind: .item(latitude: latitude, longitude: longitude))
    }

    public static func rect(
        minLatitude: Double,
        minLongitude: Double,
        maxLatitude: Double,
        maxLongitude: Double
    ) -> MapCameraPosition {
        MapCameraPosition(
            kind: .rect(
                minLatitude: minLatitude,
                minLongitude: minLongitude,
                maxLatitude: maxLatitude,
                maxLongitude: maxLongitude
            ))
    }

    public static func userLocation(fallback: MapCameraPosition = .automatic) -> MapCameraPosition {
        MapCameraPosition(kind: .userLocation(fallback: fallback))
    }

    public static func camera(
        latitude: Double,
        longitude: Double,
        distance: Double
    ) -> MapCameraPosition {
        MapCameraPosition(kind: .camera(latitude: latitude, longitude: longitude, distance: distance))
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct MapCameraBounds: Sendable, Equatable {
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var latitudeDelta: Double
    public var longitudeDelta: Double

    public init(
        centerLatitude: Double = 0,
        centerLongitude: Double = 0,
        latitudeDelta: Double = 180,
        longitudeDelta: Double = 360
    ) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public enum MapProjection: Sendable, Equatable {
    case mercator
    case equalArea
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct MapReader<Content: View>: View {
    public typealias Body = Never

    private let content: (MapProxy) -> Content

    public init(@ViewBuilder content: @escaping (MapProxy) -> Content) {
        self.content = content
    }

    public var body: Never {
        fatalError("MapReader has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let proxy = MapProxy()
        return content(proxy).makeComponent(context: context)
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct MapProxy {
    public init() {}
    public func convert(_ coordinate: (latitude: Double, longitude: Double), to: CoordinateSpace) -> Point? { nil }
    public func convert(_ point: Point, from: CoordinateSpace) -> (latitude: Double, longitude: Double)? { nil }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct LookAroundViewer: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("LookAroundViewer has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 300, height: 200), isHitTestVisible: false)
        }
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct Marker: View {
    public typealias Body = Never

    private let title: String
    private let latitude: Double
    private let longitude: Double

    public init(_ title: String, coordinate: (latitude: Double, longitude: Double)) {
        self.title = title
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    public var body: Never {
        fatalError("Marker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 20, height: 20), isHitTestVisible: false)
        }
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct Annotation<Content: View>: View {
    public typealias Body = Never

    private let title: String
    private let latitude: Double
    private let longitude: Double
    private let content: Content

    public init(
        _ title: String,
        coordinate: (latitude: Double, longitude: Double),
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.content = content()
    }

    public var body: Never {
        fatalError("Annotation has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        content.makeComponent(context: context)
    }
}
public struct PhotosPicker: View {
    public typealias Body = Never

    private let selection: Binding<PhotosPickerItem?>?
    private let selections: Binding<[PhotosPickerItem]>?

    public init() {
        self.selection = nil
        self.selections = nil
    }

    public init(selection: Binding<PhotosPickerItem?>) {
        self.selection = selection
        self.selections = nil
    }

    public init(selections: Binding<[PhotosPickerItem]>) {
        self.selection = nil
        self.selections = selections
    }

    public var body: Never {
        fatalError("PhotosPicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let single = selection
        let multiple = selections
        return Button {
            let urls = FileDialogManager.showOpenFileDialog(allowsMultipleSelection: multiple != nil)
            let items = urls.map { PhotosPickerItem(fileURL: $0) }
            if let multiple {
                multiple.wrappedValue = items
            } else if let first = items.first, let single {
                single.wrappedValue = first
            }
        } label: {
            Label("Photos", systemImage: "photo")
        }
        .makeComponent(context: context)
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct PhotosPickerItem: Sendable, Equatable {
    public let itemIdentifier: String
    public var fileURL: URL?

    public init(itemIdentifier: String = UUID().uuidString, fileURL: URL? = nil) {
        self.itemIdentifier = itemIdentifier
        self.fileURL = fileURL
    }
}
public struct VideoPlayer<VideoOverlay: View>: View {
    public typealias Body = Never

    private let videoOverlay: [AnyView]

    public init() {
        self.videoOverlay = []
    }

    public init(@ViewBuilder videoOverlay: () -> VideoOverlay) {
        self.videoOverlay = [AnyView(videoOverlay())]
    }

    public var body: Never {
        fatalError("VideoPlayer has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(
            label: "Video Player", systemImage: "play.rectangle", preferredSize: Size(width: 300, height: 200))
    }
}
public struct MapKitMap: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("MapKitMap has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "Map", systemImage: "map", preferredSize: Size(width: 300, height: 200))
    }
}
public struct AVPlayerView: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("AVPlayerView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "AVPlayer", systemImage: "play.circle", preferredSize: Size(width: 300, height: 200))
    }
}
public struct LivePhotoView: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("LivePhotoView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "Live Photo", systemImage: "livephoto", preferredSize: Size(width: 200, height: 200))
    }
}
public struct Camera: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("Camera has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "Camera", systemImage: "camera", preferredSize: Size(width: 300, height: 200))
    }
}
public struct ImagePicker: View {
    public typealias Body = Never

    private let selection: Binding<URL?>?

    public init() {
        self.selection = nil
    }

    public init(selection: Binding<URL?>) {
        self.selection = selection
    }

    public var body: Never {
        fatalError("ImagePicker has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let binding = selection
        return Button {
            let urls = FileDialogManager.showOpenFileDialog(allowsMultipleSelection: false)
            if let url = urls.first, let binding {
                binding.wrappedValue = url
            }
        } label: {
            Label("Choose Photo", systemImage: "photo")
        }
        .makeComponent(context: context)
    }
}
public struct QuickLookPreview: View {
    public typealias Body = Never

    private let url: URL?
    private let item: Any?

    public init(url: URL) {
        self.url = url
        self.item = nil
    }

    public init(item: some Sendable) {
        self.url = nil
        self.item = item
    }

    public var body: Never {
        fatalError("QuickLookPreview has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = url
        let _ = item
        return placeholderPanel(label: "Quick Look", systemImage: "eye", preferredSize: Size(width: 300, height: 400))
    }
}
public struct PDFView: View {
    public typealias Body = Never

    private let url: URL?
    private let data: Data?

    public init(url: URL) {
        self.url = url
        self.data = nil
    }

    public init(data: Data) {
        self.url = nil
        self.data = data
    }

    public var body: Never {
        fatalError("PDFView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = url
        let _ = data
        return placeholderPanel(label: "PDF", systemImage: "doc.text", preferredSize: Size(width: 300, height: 400))
    }
}
public struct WebView: View {
    public typealias Body = Never

    private let url: URL?
    private let html: String?

    public init(url: URL) {
        self.url = url
        self.html = nil
    }

    public init(html: String) {
        self.url = nil
        self.html = html
    }

    public var body: Never {
        fatalError("WebView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = url
        let _ = html
        return placeholderPanel(label: "WebView", systemImage: "globe", preferredSize: Size(width: 300, height: 200))
    }
}
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct SpriteView: View {
    public typealias Body = Never

    private let scene: Any
    private let isPaused: Bool

    public init(scene: Any, isPaused: Bool = false) {
        self.scene = scene
        self.isPaused = isPaused
    }

    public var body: Never {
        fatalError("SpriteView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = scene
        let _ = isPaused
        return placeholderPanel(
            label: "SpriteKit", systemImage: "sparkles", preferredSize: Size(width: 300, height: 200))
    }
}
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct SceneView: View {
    public typealias Body = Never

    private let scene: Any
    private let options: [String]

    public init(scene: Any, options: [String] = []) {
        self.scene = scene
        self.options = options
    }

    public var body: Never {
        fatalError("SceneView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = scene
        let _ = options
        return placeholderPanel(label: "SceneKit", systemImage: "cube", preferredSize: Size(width: 300, height: 200))
    }
}
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct RealityView: View {
    public typealias Body = Never

    private let update: (@MainActor (inout Any) -> Void)?

    public init(update: (@MainActor (inout Any) -> Void)? = nil) {
        self.update = update
    }

    public var body: Never {
        fatalError("RealityView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = update
        return placeholderPanel(
            label: "RealityKit", systemImage: "visionpro", preferredSize: Size(width: 300, height: 200))
    }
}
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct Model3D: View {
    public typealias Body = Never

    private let url: URL?
    private let name: String?

    public init(url: URL) {
        self.url = url
        self.name = nil
    }

    public init(named name: String) {
        self.url = nil
        self.name = name
    }

    public var body: Never {
        fatalError("Model3D has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = url
        let _ = name
        return placeholderPanel(label: "3D Model", systemImage: "cube", preferredSize: Size(width: 200, height: 200))
    }
}
public enum Model3DPhase: Sendable {
    case loading
    case ready
    case error(Error)
}
public struct Model3DPlaceholderStyle: Sendable, Equatable, Hashable {
    public init() {}
}
public struct SceneRealityView: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("SceneRealityView has no body")
    }
}
public struct RealityViewCameraContent: Sendable, Equatable {
    public init() {}
}
public struct RealityViewAttachmentContent: Sendable, Equatable {
    public init() {}
}
public struct RealityViewEntityContent: Sendable, Equatable {
    public init() {}
}
public struct SceneRealityViewCameraContent: Sendable, Equatable {
    public init() {}
}
public struct SceneRealityViewAttachmentContent: Sendable, Equatable {
    public init() {}
}
public struct SceneRealityViewEntityContent: Sendable, Equatable {
    public init() {}
}
public struct ImmersiveSpaceContent: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ImmersiveSpaceContent has no body")
    }
}
public struct ImmersiveSpaceRoot: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ImmersiveSpaceRoot has no body")
    }
}
public struct ImmersiveScene: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ImmersiveScene has no body")
    }
}
public struct Volumetric: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("Volumetric has no body")
    }
}
public struct Ornament<Content: View>: View {
    public typealias Body = Never

    private let content: Content
    private let attachmentAnchor: UnitPoint
    private let contentAnchor: UnitPoint

    public init(
        attachmentAnchor: UnitPoint = .bottom,
        contentAnchor: UnitPoint = .top,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.attachmentAnchor = attachmentAnchor
        self.contentAnchor = contentAnchor
    }

    public var body: Never {
        fatalError("Ornament has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = attachmentAnchor
        let _ = contentAnchor
        return content.makeComponent(context: context)
    }
}
public struct AppStoreOverlay: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("AppStoreOverlay has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
public struct SubscriptionStoreView: View {
    public typealias Body = Never

    private let productIDs: [String]

    public init(productIDs: [String]) {
        self.productIDs = productIDs
    }

    public var body: Never {
        fatalError("SubscriptionStoreView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = productIDs
        return Component { _ in
            Controls.panel(preferredSize: Size(width: 300, height: 200), isHitTestVisible: false)
        }
    }
}
public struct SubscriptionView: View {
    public typealias Body = Never

    private let productID: String

    public init(productID: String) {
        self.productID = productID
    }

    public var body: Never {
        fatalError("SubscriptionView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = productID
        return Component { _ in
            Controls.panel(preferredSize: Size(width: 300, height: 120), isHitTestVisible: false)
        }
    }
}
public protocol ChartContent: View {}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AnyChart: ChartContent {
    public typealias Body = Never

    private let buildComponent: (ViewBuildContext) -> Component

    public init<C: ChartContent>(_ chart: C) {
        self.buildComponent = { context in
            chart.makeComponent(context: context)
        }
    }

    public var body: Never {
        fatalError("AnyChart has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        buildComponent(context)
    }
}
public struct Chart<Content: ChartContent>: View {
    public typealias Body = Never

    private let content: Content

    public init(@ChartContentBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Chart has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "Chart", systemImage: "chart.bar", preferredSize: Size(width: 300, height: 200))
    }
}
public protocol Mark: ChartContent {}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct BarMark: Mark {
    public typealias Body = Never

    public var x: PlottableValue
    public var y: PlottableValue
    public var height: Double?
    public var width: Double?

    public init(
        x: PlottableValue,
        y: PlottableValue,
        height: Double? = nil,
        width: Double? = nil
    ) {
        self.x = x
        self.y = y
        self.height = height
        self.width = width
    }

    public var body: Never {
        fatalError("BarMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 40, height: 40), isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct LineMark: Mark {
    public typealias Body = Never

    public var x: PlottableValue
    public var y: PlottableValue
    public var series: PlottableValue?

    public init(
        x: PlottableValue,
        y: PlottableValue,
        series: PlottableValue? = nil
    ) {
        self.x = x
        self.y = y
        self.series = series
    }

    public var body: Never {
        fatalError("LineMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AreaMark: Mark {
    public typealias Body = Never

    public var x: PlottableValue
    public var y: PlottableValue
    public var series: PlottableValue?

    public init(
        x: PlottableValue,
        y: PlottableValue,
        series: PlottableValue? = nil
    ) {
        self.x = x
        self.y = y
        self.series = series
    }

    public var body: Never {
        fatalError("AreaMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct RuleMark: Mark {
    public typealias Body = Never

    public var x: PlottableValue?
    public var y: PlottableValue?

    public init(
        x: PlottableValue? = nil,
        y: PlottableValue? = nil
    ) {
        self.x = x
        self.y = y
    }

    public var body: Never {
        fatalError("RuleMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct PointMark: Mark {
    public typealias Body = Never

    public var x: PlottableValue
    public var y: PlottableValue
    public var series: PlottableValue?

    public init(
        x: PlottableValue,
        y: PlottableValue,
        series: PlottableValue? = nil
    ) {
        self.x = x
        self.y = y
        self.series = series
    }

    public var body: Never {
        fatalError("PointMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 8, height: 8), isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct RectangleMark: Mark {
    public typealias Body = Never

    public var xStart: PlottableValue?
    public var xEnd: PlottableValue?
    public var yStart: PlottableValue?
    public var yEnd: PlottableValue?

    public init(
        xStart: PlottableValue? = nil,
        xEnd: PlottableValue? = nil,
        yStart: PlottableValue? = nil,
        yEnd: PlottableValue? = nil
    ) {
        self.xStart = xStart
        self.xEnd = xEnd
        self.yStart = yStart
        self.yEnd = yEnd
    }

    public var body: Never {
        fatalError("RectangleMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 40, height: 40), isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct SectorMark: Mark {
    public typealias Body = Never

    public var angle: PlottableValue
    public var innerRadius: Double?
    public var outerRadius: Double?
    public var angularInset: Double?

    public init(
        angle: PlottableValue,
        innerRadius: Double? = nil,
        outerRadius: Double? = nil,
        angularInset: Double? = nil
    ) {
        self.angle = angle
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.angularInset = angularInset
    }

    public var body: Never {
        fatalError("SectorMark has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: Size(width: 40, height: 40), isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AxisMarks: ChartContent {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("AxisMarks has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AxisValueLabel: ChartContent {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("AxisValueLabel has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AxisGridLine: ChartContent {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("AxisGridLine has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct AxisTick: ChartContent {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("AxisTick has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public struct ChartProxy {
    public init() {}
}
public protocol ChartSymbolShape: Shape {
    init()
}
public struct AxisValue: Sendable, Equatable {
    public let value: Double

    public init(_ value: Double) {
        self.value = value
    }
}
public struct Plot: Sendable, Equatable {
    public init() {}
}
public struct PlottableDomain: Sendable, Equatable {
    public var min: Double
    public var max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
}
public struct ChartBackground: View, ChartContent {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ChartBackground has no body")
    }
}
public struct ChartForegroundStyleScale: Sendable, Equatable {
    public init() {}
}
public struct ChartXAxis: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ChartXAxis has no body")
    }
}
public struct ChartYAxis: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("ChartYAxis has no body")
    }
}
public struct ChartScrollTargetBehavior: Sendable, Equatable {
    public init() {}
}
@MainActor
public protocol Tip {
    associatedtype Title: View
    associatedtype Message: View
    associatedtype Image: View

    var title: Title { get }
    var message: Message? { get }
    var image: Image? { get }

    static var options: [TipOption] { get }
}
extension Tip {
    public var message: Message? { nil }
    public var image: Image? { nil }
    public static var options: [TipOption] { [] }
}
public struct TipOption: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case maxDisplayCount(Int)
    }
    public let kind: Kind

    public static func maxDisplayCount(_ count: Int) -> TipOption {
        TipOption(kind: .maxDisplayCount(count))
    }
}
public struct TipView<TipType: Tip>: View {
    public typealias Body = Never

    private let tip: TipType
    private let arrowEdge: Edge?
    private let action: (TipType) -> Void

    public init(
        _ tip: TipType,
        arrowEdge: Edge? = nil,
        action: @escaping (TipType) -> Void = { _ in }
    ) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.action = action
    }

    public var body: Never {
        fatalError("TipView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = arrowEdge
        let _ = tip
        return placeholderPanel(label: "Tip", systemImage: "lightbulb", preferredSize: Size(width: 200, height: 80))
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct TipViewStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case inline
        case floating
    }
    public let kind: Kind

    public static let automatic = TipViewStyle(kind: .automatic)
    public static let inline = TipViewStyle(kind: .inline)
    public static let floating = TipViewStyle(kind: .floating)
}
public struct TipAction: Sendable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
public struct TipDismissal: Sendable, Equatable {
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
public struct StoreView: View {
    public typealias Body = Never

    private let productIDs: [String]

    public init(ids: [String]) {
        self.productIDs = ids
    }

    public var body: Never {
        fatalError("StoreView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = productIDs
        return placeholderPanel(label: "App Store", systemImage: "bag", preferredSize: Size(width: 300, height: 400))
    }
}
public struct ProductView: View {
    public typealias Body = Never

    private let productID: String

    public init(id: String) {
        self.productID = id
    }

    public var body: Never {
        fatalError("ProductView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let _ = productID
        return placeholderPanel(label: "Product", systemImage: "tag", preferredSize: Size(width: 280, height: 120))
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct ProductViewStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case compact
        case large
    }
    public let kind: Kind

    public static let automatic = ProductViewStyle(kind: .automatic)
    public static let compact = ProductViewStyle(kind: .compact)
    public static let large = ProductViewStyle(kind: .large)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct SubscriptionStoreViewStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case compact
        case large
        case fullHeight
    }
    public let kind: Kind

    public static let automatic = SubscriptionStoreViewStyle(kind: .automatic)
    public static let compact = SubscriptionStoreViewStyle(kind: .compact)
    public static let large = SubscriptionStoreViewStyle(kind: .large)
    public static let fullHeight = SubscriptionStoreViewStyle(kind: .fullHeight)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct SubscriptionStoreControlStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case compact
        case pageSheet
    }
    public let kind: Kind

    public static let automatic = SubscriptionStoreControlStyle(kind: .automatic)
    public static let compact = SubscriptionStoreControlStyle(kind: .compact)
    public static let pageSheet = SubscriptionStoreControlStyle(kind: .pageSheet)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public enum SubscriptionStoreButtonLabel: Sendable, Equatable, Hashable {
    case singleLine
    case multiline
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct StoreButton: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case cancel
        case restore
        case actions
        case complete
    }
    public let kind: Kind

    public static let cancel = StoreButton(kind: .cancel)
    public static let restore = StoreButton(kind: .restore)
    public static let actions = StoreButton(kind: .actions)
    public static let complete = StoreButton(kind: .complete)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct SubscriptionStorePickerItemBackground: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case hidden
    }
    public let kind: Kind

    public static let automatic = SubscriptionStorePickerItemBackground(kind: .automatic)
    public static let hidden = SubscriptionStorePickerItemBackground(kind: .hidden)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct StoreViewStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case compact
        case large
    }
    public let kind: Kind

    public static let automatic = StoreViewStyle(kind: .automatic)
    public static let compact = StoreViewStyle(kind: .compact)
    public static let large = StoreViewStyle(kind: .large)
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct InAppPurchaseButton: View {
    public typealias Body = Never

    public init(productID: String) {}

    public var body: Never {
        fatalError("InAppPurchaseButton has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        placeholderPanel(label: "Purchase", systemImage: "cart", preferredSize: Size(width: 120, height: 44))
    }
}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public struct StoreButtonStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case automatic
        case prominent
    }

    public let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = StoreButtonStyle(kind: .automatic)
    public static let prominent = StoreButtonStyle(kind: .prominent)
}
@MainActor
private func placeholderPanel(
    label: String,
    systemImage: String? = nil,
    preferredSize: Size = Size(width: 300, height: 200)
) -> Component {
    let text = systemImage.map { "\($0)\n\(label)" } ?? label
    return Component { _ in
        Controls.panel(
            preferredSize: preferredSize,
            backgroundColor: Color(red: 0.11, green: 0.15, blue: 0.21, alpha: 0.98),
            text: text,
            textStyle: PixelTextStyle(
                color: Color(red: 0.56, green: 0.60, blue: 0.68, alpha: 0.80),
                scale: 1.4,
                alignment: .center,
                verticalAlignment: .center,
                weight: .semibold
            ),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            borderWidth: 1,
            cornerRadius: 12,
            isHitTestVisible: false
        )
    }
}
