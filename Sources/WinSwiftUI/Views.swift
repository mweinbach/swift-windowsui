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

// MARK: - Grouped form rows
//
// A macOS grouped form is a two-column grid, not a stack of independent
// controls: trailing-aligned labels share one leading column, and the
// controls lead the value column beside them. These pieces are the whole
// mechanism — a control that owns a label builds a row with
// `groupedFormRowNode`, the container it lands in (a `Section`, or the
// `Form` itself) resolves that group's shared column width with
// `alignedGroupedFormRows` once every row exists, and the enclosing
// `Form` widens every group to one column with `GroupedFormColumnScope`.

/// The one label column a `Form` shares across all of its sections.
///
/// macOS aligns a settings pane on a single leading column: the label
/// edges in "General" line up with the label edges in "Appearance", and
/// the boxes are grouping, not separate grids. Each `Section` still
/// resolves its own group first — it has to, because a section outside a
/// `Form` has no wider scope to defer to — and registers the result here.
/// The `Form` then takes the widest of those and applies it to every
/// registered column and value-column indent, which is idempotent because
/// the recorded width is each group's *intrinsic* answer rather than
/// whatever it was last set to.
///
/// Reference type on purpose: it travels down the build as an environment
/// value so a section can register into the form that is still building
/// it, which is the inherited-environment shape the runtime already uses
/// rather than a second piece of global UI state.
@MainActor
final class GroupedFormColumnScope {
    private var labelColumns: [ViewNode] = []
    private var valueColumnIndents: [ViewNode] = []
    private var widestGroupWidth: Double = 0

    /// Records one resolved group: its label columns, the label-less rows
    /// it indented into the value column, and the width it settled on.
    func adopt(labelColumns: [ViewNode], valueColumnIndents: [ViewNode], groupWidth: Double) {
        self.labelColumns.append(contentsOf: labelColumns)
        self.valueColumnIndents.append(contentsOf: valueColumnIndents)
        widestGroupWidth = max(widestGroupWidth, groupWidth)
    }

    /// Widens every group in the form to the form-wide column.
    func resolve() {
        guard widestGroupWidth > 0 else {
            return
        }
        for column in labelColumns {
            column.preferredSize = Size(
                width: widestGroupWidth,
                height: column.preferredSize?.height ?? 0
            )
        }
        let valueColumnInset = widestGroupWidth + MacOSControlMetrics.Form.labelColumnGap
        for indent in valueColumnIndents {
            guard var layout = indent.layoutMode.stackLayout else {
                continue
            }
            layout.padding = EdgeInsets(top: 0, leading: valueColumnInset, bottom: 0, trailing: 0)
            indent.layoutMode = .stack(layout)
        }
    }
}

/// One grouped-form row: `label` trailing-aligned in the label column,
/// `content` leading-aligned in the value column.
///
/// The label column carries no width of its own here. It is deliberately
/// left at its intrinsic size until the container pins every row in the
/// group to the same width — a row cannot know how wide its siblings'
/// labels are, and a per-row column is exactly the ragged layout this
/// replaces.
@MainActor
func groupedFormRowNode(label: ViewNode, content: ViewNode, isHitTestVisible: Bool = false) -> ViewNode {
    // Several controls raise their label's layout priority so a squeezed row
    // sacrifices the control before the words. Inside the column that
    // reading has no work left to do — the column pins the width and the
    // shrink pass floors text at its measured extent — while the stack
    // allocator's other reading of priority, flex-grow weight, would let the
    // label swallow the column's slack and land leading in a column whose
    // whole point is a trailing edge.
    label.layoutPriority = 0
    let labelColumn = Controls.stackPanel(
        stackLayout: .horizontal(spacing: 0, alignment: .center, mainAlignment: .end),
        isHitTestVisible: false,
        children: [label]
    )
    let valueColumn = Controls.stackPanel(
        stackLayout: .horizontal(spacing: 0, alignment: .center, mainAlignment: .start),
        isHitTestVisible: isHitTestVisible,
        children: [content]
    )
    // The value column owns the rest of the row. Content that is itself
    // greedy (a text field, a slider) fills it; content that is not (a
    // switch, a segmented track, a stepper) leads it at its intrinsic
    // width, which is what a settings pane looks like.
    valueColumn.layoutFillAxes = .horizontalOnly
    let row = Controls.stackPanel(
        stackLayout: .horizontal(
            spacing: MacOSControlMetrics.Form.labelColumnGap,
            alignment: .center
        ),
        isHitTestVisible: isHitTestVisible,
        children: [labelColumn, valueColumn]
    )
    row.layoutFillAxes = .horizontalOnly
    row.formRowLabelChildIndex = 0
    return row
}

/// Gives every grouped-form row in `nodes` one shared label-column width,
/// and indents the group's label-less rows to the value column so a button
/// or a plain row lines up with the controls above it.
///
/// Answers the children the container should actually host: unchanged when
/// the group holds no form rows at all, which is what keeps a `Form` of
/// bare `Section`s (and every `Section` outside a `Form`) untouched.
///
/// `scope` is the enclosing `Form`'s column, when there is one. This group
/// still resolves itself — a `Section` may be the outermost grouping there
/// is — and hands the result up so the form can widen every group to the
/// same edge once all of them exist.
@MainActor
func alignedGroupedFormRows(_ nodes: [ViewNode], scope: GroupedFormColumnScope? = nil) -> [ViewNode] {
    var labelColumns: [ViewNode] = []
    for node in nodes {
        guard let index = node.formRowLabelChildIndex, node.children.indices.contains(index) else {
            continue
        }
        labelColumns.append(node.children[index])
    }
    guard !labelColumns.isEmpty else {
        return nodes
    }

    let columnWidth = labelColumns.reduce(0.0) { widest, column in
        max(widest, column.intrinsicContentSize().width)
    }
    guard columnWidth > 0 else {
        return nodes
    }
    for column in labelColumns {
        column.preferredSize = Size(width: columnWidth, height: column.preferredSize?.height ?? 0)
    }

    let valueColumnInset = columnWidth + MacOSControlMetrics.Form.labelColumnGap
    var valueColumnIndents: [ViewNode] = []
    let resolved = nodes.map { node -> ViewNode in
        // A rule spans the group edge to edge, and a row that already has a
        // label is already aligned. Everything else — a button, a bare
        // `Text` — belongs in the value column beside its labelled siblings.
        guard node.formRowLabelChildIndex == nil, !node.layoutFillAxes.horizontal else {
            return node
        }
        let indented = Controls.stackPanel(
            stackLayout: .horizontal(
                padding: EdgeInsets(top: 0, leading: valueColumnInset, bottom: 0, trailing: 0),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: [node]
        )
        indented.layoutFillAxes = .horizontalOnly
        valueColumnIndents.append(indented)
        return indented
    }
    scope?.adopt(
        labelColumns: labelColumns,
        valueColumnIndents: valueColumnIndents,
        groupWidth: columnWidth
    )
    return resolved
}

/// An overlay scroller floats a pill over the content a few points in from
/// the edge; it does not reserve a gutter. Pinned by
/// `MacOSControlMetrics.Scroller.overlayInset`.
private let defaultRetainedScrollIndicatorInsets = EdgeInsets(
    top: MacOSControlMetrics.Scroller.overlayInset,
    leading: MacOSControlMetrics.Scroller.overlayInset,
    bottom: MacOSControlMetrics.Scroller.overlayInset,
    trailing: MacOSControlMetrics.Scroller.overlayInset
)
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
/// Advances a `PhaseAnimator` from one phase to the next.
///
/// This used to be a detached `Task` per animator, awaiting
/// `Task.sleep(nanoseconds:)` for each phase's duration. Two things were wrong
/// with that and neither was about the animator. The sleep is wall-clock and
/// unsynchronised with the frame clock, so a phase boundary landed wherever the
/// scheduler put it rather than on a frame — and it could not be reproduced
/// under a controlled clock at all. And a pending sleep was invisible to
/// `hasActiveAnimations`: for a phase whose animation is nil or zero-duration
/// there is nothing else registered, so the runtime looked idle between phases
/// and the host was free to switch its timer off.
///
/// It is a deadline on the runtime's animation clock now — the same shape as
/// every other timed mechanism in the runtime — armed one boundary at a time
/// and re-armed by the rebuild the boundary causes.
@MainActor
public final class PhaseAnimatorTaskManager: @unchecked Sendable {
    public static let shared = PhaseAnimatorTaskManager()

    private struct ScheduledPhase {
        weak var runtime: RetainedViewRuntime?
    }

    private var scheduled: [String: ScheduledPhase] = [:]

    private init() {}

    /// Arms the boundary out of the phase the build just produced.
    ///
    /// `currentPhaseIndex` is passed rather than read back off the tree
    /// because `start` is called from inside the build, with the node it
    /// describes not yet reconciled into `runtime.root` — a lookup there finds
    /// the previous tree, or on a first build nothing at all. The *fire*
    /// closure does look the node up, by which point the tree is in place.
    public func start<Phase: Equatable>(
        key: String,
        runtime: RetainedViewRuntime,
        signature: String,
        phases: [Phase],
        currentPhaseIndex: Int,
        animation: @escaping (Phase) -> Animation?,
        invalidate: @escaping () -> Void
    ) {
        cancel(key: key)
        armNextPhase(
            key: key, runtime: runtime, signature: signature, phases: phases, index: currentPhaseIndex,
            animation: animation, invalidate: invalidate)
    }

    private func armNextPhase<Phase: Equatable>(
        key: String,
        runtime: RetainedViewRuntime,
        signature: String,
        phases: [Phase],
        index: Int,
        animation: @escaping (Phase) -> Animation?,
        invalidate: @escaping () -> Void
    ) {
        guard index >= 0, index < phases.count - 1 else {
            cancel(key: key)
            return
        }

        let duration = animation(phases[index])?.duration ?? 0.0
        scheduled[key] = ScheduledPhase(runtime: runtime)
        runtime.scheduleDeferredRebuild(key: key, delay: duration) { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            self.scheduled.removeValue(forKey: key)

            guard let node = self.findNode(in: runtime.root, signature: signature),
                let current = node.phaseAnimatorState,
                current.phasesSignature == signature,
                current.currentPhaseIndex == index
            else {
                return
            }

            node.phaseAnimatorState?.currentPhaseIndex = index + 1
            node.phaseAnimatorState?.phaseStartTime = runtime.clock()
            invalidate()

            // The rebuild normally re-arms this through `start`. It does not
            // when the host refused the rebuild (`shouldUpdate`), so the
            // sequence is armed here too rather than stalling mid-run.
            if self.scheduled[key] == nil {
                self.armNextPhase(
                    key: key, runtime: runtime, signature: signature, phases: phases, index: index + 1,
                    animation: animation, invalidate: invalidate)
            }
        }
    }

    public func hasActiveTask(key: String) -> Bool {
        scheduled[key] != nil
    }

    public func cancel(key: String) {
        guard let entry = scheduled.removeValue(forKey: key) else {
            return
        }
        entry.runtime?.cancelDeferredRebuild(key: key)
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
                children: viewIdentityOccurrences(views).map {
                    $0.makeComponent(context: context).makeNode(runtime: runtime)
                }
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
            // The same clock the phase deadline is armed on: a build that read
            // the wall clock while the boundary was scheduled on the injected
            // one would compare two unrelated timelines.
            let now = runtime.clock()

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
                views = content(phase).map { $0.mappingViewIdentity { AnyView($0.animation(currentAnimation)) } }
            } else if let fallback = fallbackContent {
                views = fallback
            } else {
                views = []
            }

            let childNodes = viewIdentityOccurrences(views).map {
                $0.makeComponent(context: context).makeNode(runtime: runtime)
            }
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
                    currentPhaseIndex: phaseIndex,
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
        let views = viewIdentityOccurrences(content)
        // Distinct flattened fragments can have prefix-related paths. Make
        // each complete relative identity one key before building it, so a
        // rejected candidate's scope can never include the selected sibling.
        let candidateContexts = views.map { view in
            let key = RetainedViewIdentity.Key(RetainedViewIdentity(segments: view.structuralIdentity))
            return context.withViewIdentityRole(.content).withViewIdentityPrefix([.keyed(key)])
        }
        let declarations =
            context.stateMountCoordinator == nil
            ? [] : views.indices.map { views[$0].declaredStateMountScopes(context: candidateContexts[$0]) }

        return Component { runtime in
            guard !views.isEmpty else {
                return Controls.panel(preferredSize: .zero, isHitTestVisible: false)
            }

            let availableSize = context.canvasSize
            for (index, view) in views.enumerated() {
                let candidateNode = view.makeComponent(context: candidateContexts[index]).makeNode(runtime: runtime)
                let candidateSize = candidateNode.intrinsicContentSize()
                if Self.fits(candidateSize, in: availableSize, axes: axes) || index == views.count - 1 {
                    if let coordinator = context.stateMountCoordinator {
                        for otherIndex in views.indices where otherIndex != index {
                            coordinator.discardUnadoptedSubtree(
                                at: candidateContexts[otherIndex].retainedViewIdentity, preserveCommitted: false)
                            coordinator.preserveDeclaredScopes(declarations[otherIndex])
                        }
                    }
                    return candidateNode
                }
                if let coordinator = context.stateMountCoordinator {
                    coordinator.discardUnadoptedSubtree(
                        at: candidateContexts[index].retainedViewIdentity, preserveCommitted: false)
                    coordinator.preserveDeclaredScopes(declarations[index])
                }
            }

            return Controls.panel(preferredSize: .zero, isHitTestVisible: false)
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
        let childComponent = makeViewComponent(content(timelineContext), context: context)
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
        let childComponent = makeViewComponent(content(timelineContext), context: context)
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
            let node = Controls.panel(backgroundColor: self, isHitTestVisible: false)
            // A `Color` accepts whatever it is proposed on both axes — that is
            // the whole of its layout behaviour in SwiftUI, and it is why
            // `Color.red.frame(height: 1)` is a full-width hairline rather
            // than an invisible 0x1 node. Without the declaration a colour
            // measured its (nonexistent) intrinsic width, so every rule the
            // app drew this way — the settings row rules, the data table row
            // rules, the hero's lit top edge — was in the tree at 0pt wide
            // and painted nothing. An explicit `.frame(width:)` still wins:
            // it pins the node's preferred size, which ends the greed.
            node.layoutFillAxes = .both
            return node
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
        // Map leading/trailing onto the renderer's absolute left/right
        // corners; in RTL the leading edge is on the right.
        let isRTL = context.layoutDirection == .rightToLeft
        let radii = RetainedCornerRadii(
            topLeft: isRTL ? cornerRadii.topTrailing : cornerRadii.topLeading,
            topRight: isRTL ? cornerRadii.topLeading : cornerRadii.topTrailing,
            bottomRight: isRTL ? cornerRadii.bottomLeading : cornerRadii.bottomTrailing,
            bottomLeft: isRTL ? cornerRadii.bottomTrailing : cornerRadii.bottomLeading
        )
        return shapeComponent(
            fillStyle: fillStyle ?? context.foregroundStyle,
            fillRuleStyle: fillRuleStyle,
            strokeStyle: lineWidth > 0 ? (strokeStyle ?? context.foregroundStyle) : .color(.clear),
            lineWidth: lineWidth,
            strokeLineStyle: strokeLineStyle,
            cornerRadius: cornerRadii.retainedUniformFallbackRadius,
            cornerRadii: radii
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
        let paint = ResolvedShapePaint(
            fillStyle: fillStyle, fillRuleStyle: fillRuleStyle, strokeStyle: strokeStyle,
            lineWidth: lineWidth, strokeLineStyle: strokeLineStyle, foregroundStyle: context.foregroundStyle)
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
            node.layoutFillAxes = .both
            paint.apply(to: ShapePaintOwner(node: node))
            node.onLayoutWithNode = { node, bounds in
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
    private let resolvePaintOwner: (ViewNode) -> ShapePaintOwner?
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
            makeViewComponent(shape, context: context)
        }
        self.resolvePaintOwner = { node in resolveShapePaintOwner(for: shape, in: node) }
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

        let paint = ResolvedShapePaint(
            fillStyle: fillStyle, fillRuleStyle: fillRuleStyle, strokeStyle: strokeStyle,
            lineWidth: lineWidth, strokeLineStyle: strokeLineStyle, foregroundStyle: context.foregroundStyle)
        let inner = buildComponent(context)
        return Component(key: inner.key) { runtime in
            let node = inner.makeNode(runtime: runtime)
            if let owner = resolvePaintOwner(node) {
                paint.apply(to: owner)
            }
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
            makeViewComponent(content, context: context)
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
            let paint = ResolvedShapePaint(
                fillStyle: fillStyle, fillRuleStyle: fillRuleStyle, strokeStyle: strokeStyle,
                lineWidth: lineWidth, strokeLineStyle: strokeLineStyle, foregroundStyle: context.foregroundStyle)
            let inner = buildComponent(context)
            renderedComponent = Component(key: inner.key) { runtime in
                let node = inner.makeNode(runtime: runtime)
                if let owner = contentPaintOwner(in: node) {
                    paint.apply(to: owner)
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
        let paint = ResolvedShapePaint(
            fillStyle: fillStyle, fillRuleStyle: fillRuleStyle, strokeStyle: strokeStyle,
            lineWidth: lineWidth, strokeLineStyle: strokeLineStyle, foregroundStyle: context.foregroundStyle)
        let unitPath = self.path(in: Rect(x: 0, y: 0, width: 1, height: 1))
        return Component { _ in
            let node = Controls.panel(
                backgroundColor: .clear,
                isHitTestVisible: false
            )
            node.layoutFillAxes = .both
            paint.apply(to: ShapePaintOwner(node: node))
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
        let child = makeViewComponent(shape, context: context)
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
        let child = makeViewComponent(shape, context: context)
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
        let child = makeViewComponent(shape, context: context)
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
        let child = makeViewComponent(shape, context: context)
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
        makeViewComponent(shape, context: context)
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
/// Resolved only while constructing a component; never stored on a retained node.
/// Known wrappers can direct paint to their shape without decorating layout nodes.
@MainActor
fileprivate struct ShapePaintOwner {
    let node: ViewNode
    var cornerRadius: Double? = nil
}

@MainActor
fileprivate protocol ShapePaintOwnerProvider {
    func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner?
}

@MainActor
private func resolveShapePaintOwner<S: Shape>(for shape: S, in root: ViewNode) -> ShapePaintOwner? {
    if let provider = shape as? any ShapePaintOwnerProvider {
        // A failed known route must not fall back to painting its layout root.
        return provider.shapePaintOwner(in: root)
    }
    return ShapePaintOwner(node: root)
}

extension AnyShape: ShapePaintOwnerProvider {
    fileprivate func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        resolvePaintOwner(root)
    }
}

extension InsetShape: ShapePaintOwnerProvider {
    fileprivate func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        if amount == 0 {
            return contentPaintOwner(in: root)
        }
        // State installation may return a placeholder instead of our wrapper.
        // Descend only through the padded stack this producer actually builds.
        guard case .stack(let layout) = root.layoutMode,
            layout == .vertical(padding: EdgeInsets.all(amount), alignment: .stretch),
            root.children.count == 1
        else { return nil }
        return contentPaintOwner(in: root.children[0])
    }

    private func contentPaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        guard var owner = resolveShapePaintOwner(for: content, in: root) else { return nil }
        if case .roundedRectangle(let radius) = adjustedClipShapeStyle {
            // The absolute value preserves each nested inset's clamping and
            // avoids subtracting twice when another erasure applies paint.
            owner.cornerRadius = radius
        }
        return owner
    }
}

extension RotatedShape: ShapePaintOwnerProvider {
    fileprivate func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        resolveShapePaintOwner(for: shape, in: root)
    }
}

extension ScaledShape: ShapePaintOwnerProvider {
    fileprivate func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        resolveShapePaintOwner(for: shape, in: root)
    }
}

extension OffsetShape: ShapePaintOwnerProvider {
    fileprivate func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        resolveShapePaintOwner(for: shape, in: root)
    }
}

extension TransformedShape: ShapePaintOwnerProvider {
    fileprivate func shapePaintOwner(in root: ViewNode) -> ShapePaintOwner? {
        resolveShapePaintOwner(for: shape, in: root)
    }
}

@MainActor
private struct ResolvedShapePaint {
    let fill: (color: Color, gradient: GradientType?)
    let stroke: (color: Color, gradient: GradientType?)
    let lineWidth: Double
    let strokeLineStyle: StrokeStyle?
    let fillRuleStyle: RetainedClipFillStyle?

    init(
        fillStyle: ForegroundStyle?, fillRuleStyle: RetainedClipFillStyle?, strokeStyle: ForegroundStyle?,
        lineWidth: Double, strokeLineStyle: StrokeStyle?, foregroundStyle: ForegroundStyle
    ) {
        fill = resolvedFill(from: fillStyle ?? foregroundStyle)
        stroke = resolvedFill(from: lineWidth > 0 ? (strokeStyle ?? foregroundStyle) : .color(.clear))
        self.lineWidth = lineWidth
        self.strokeLineStyle =
            lineWidth > 0 ? (strokeLineStyle ?? StrokeStyle(lineWidth: lineWidth, dashPattern: [])) : nil
        self.fillRuleStyle = fillRuleStyle
    }

    func apply(to owner: ShapePaintOwner) {
        let node = owner.node
        // Active outer styling replaces the whole bundle, including nil values.
        node.backgroundColor = fill.color
        node.backgroundGradient = fill.gradient
        node.borderColor = stroke.color
        node.borderGradient = stroke.gradient
        node.borderWidth = lineWidth
        node.clipFillStyle = fillRuleStyle
        node.borderStrokeStyle = strokeLineStyle
        if let radius = owner.cornerRadius {
            node.cornerRadius = radius
        }
    }
}

@MainActor
private func shapeComponent(
    fillStyle: ForegroundStyle,
    fillRuleStyle: RetainedClipFillStyle?,
    strokeStyle: ForegroundStyle,
    lineWidth: Double,
    strokeLineStyle: StrokeStyle?,
    cornerRadius: Double,
    cornerRadii: RetainedCornerRadii? = nil
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
        node.cornerRadii = cornerRadii
        node.clipFillStyle = fillRuleStyle
        node.layoutFillAxes = .both
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
        node.layoutFillAxes = .both
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
public struct Group: View, StateMountDeclarationView, ViewListProjectionProvider {
    public typealias Body = Never

    private let content: [AnyView]

    public init(@ViewBuilder content: () -> [AnyView]) {
        self.content = content()
    }

    public var body: Never {
        fatalError("Group has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let context = context.withViewIdentityType(Self.self)
        return preservingViewIdentity(
            of: composeStructuralComponent(from: content, context: context.withViewIdentityRole(.content)),
            context: context)
    }

    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        let context = context.withViewIdentityType(Self.self)
        let contentContext = context.withViewIdentityRole(.content)
        return [StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .modifierContent)]
            + viewIdentityOccurrences(content).flatMap { $0.declaredStateMountScopes(context: contentContext) }
    }

    func viewListProjection() -> ViewListProjection {
        .scope(
            .type(ObjectIdentifier(Self.self)), excluding: .modifierContent,
            children: [
                .scope(
                    .prefix([.role(.content)]), excluding: nil,
                    children: viewIdentityOccurrences(content).map { .value($0) })
            ])
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
    /// Minimum band height. The `.automatic`/`.stack` styles read as
    /// window chrome and use `MacOSControlMetrics.Toolbar.regularHeight`;
    /// the split styles keep a compact card header.
    var headerMinHeight: Double = MacOSControlMetrics.Toolbar.unifiedCompactHeight
    var headerPadding: EdgeInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    /// Hairline drawn under the band instead of a boxed border. Nil keeps
    /// the bordered-card header.
    var headerSeparatorColor: Color? = nil
}
private func retainedNavigationViewChrome(
    for style: NavigationViewStyle?,
    palette: ControlPalette
) -> RetainedNavigationViewChrome {
    // macOS parity: the navigation title band is a toolbar, not a card —
    // full bleed, `MacOSControlMetrics.Toolbar.regularHeight` tall, one
    // hairline along the bottom, and the body starts directly under it.
    let defaultChrome = RetainedNavigationViewChrome(
        containerBackground: nil,
        containerBorderColor: .clear,
        containerBorderWidth: 0,
        containerCornerRadius: 0,
        headerBackground: palette.windowBackground,
        headerBorderColor: .clear,
        headerBorderWidth: 0,
        headerCornerRadius: 0,
        spacing: 0,
        headerMinHeight: MacOSControlMetrics.Toolbar.regularHeight,
        headerPadding: EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20),
        headerSeparatorColor: palette.separator
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
            headerBackground: palette.windowBackground,
            headerBorderColor: .clear,
            headerBorderWidth: 0,
            headerCornerRadius: 0,
            spacing: 0,
            headerMinHeight: MacOSControlMetrics.Toolbar.regularHeight,
            headerPadding: EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20),
            headerSeparatorColor: palette.separator
        )
    case .doubleColumn:
        return RetainedNavigationViewChrome(
            containerBackground: palette.controlBackground,
            containerBorderColor: palette.separator,
            containerBorderWidth: 1,
            containerCornerRadius: 12,
            headerBackground: palette.windowBackground,
            headerBorderColor: palette.separator,
            headerBorderWidth: 1,
            headerCornerRadius: 8,
            spacing: 12
        )
    case .columns:
        return RetainedNavigationViewChrome(
            containerBackground: palette.controlBackground,
            containerBorderColor: palette.separator,
            containerBorderWidth: 1,
            containerCornerRadius: 14,
            headerBackground: palette.windowBackground,
            headerBorderColor: palette.separator,
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
    // This band is the *content pane's* header, not the OS title bar: macOS
    // puts `NSWindow.title` in chrome this stack does not own, so what is
    // drawn here is the pane title a Finder or System Settings window shows
    // above its content. Those are set at largeTitle (26), which is also what
    // `Toolbar.regularHeight` (52) has room for; `.inline` is the compact
    // toolbar variant and takes title2 semibold (17).
    //
    // Setting it at `windowTitleSize` (13) — the previous value — sized a
    // *window* title into a *pane* header, which is why "Settings" read as a
    // stray 13pt label floating in an otherwise empty 52pt band.
    let titleFont: Font =
        displayMode == .inline
        ? .system(size: MacOSControlMetrics.Typography.title2Size, weight: .semibold)
        : .system(size: MacOSControlMetrics.Typography.largeTitleSize, weight: .bold)
    let chrome = retainedNavigationViewChrome(for: navigationViewStyle, palette: context.controlPalette)
    let palette = context.controlPalette
    let titleContext =
        context
        .withForegroundColor(palette.label)
        .withFont(titleFont)
    let subtitleContext =
        context
        .withForegroundColor(palette.secondaryLabel)
        .withFont(.system(size: MacOSControlMetrics.Typography.windowSubtitleSize, weight: .regular))

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
        // The navigation title is a header by construction; the projection
        // maps isHeader to the UIA header control type.
        titleNode.accessibilityTraits.formUnion(.isHeader)
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
                color: Color(red: 0.954, green: 0.954, blue: 0.954),
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
            // The "<" glyph is a poor accessible name; default to "Back" (an
            // explicit accessibilityLabel still wins).
            backButton.accessibilityLabel = "Back"
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
                padding: chrome.headerPadding,
                alignment: .center
            ),
            isHitTestVisible: false,
            children: headerChildren
        )
        headerNode.applyDefaultMinimumHeight(chrome.headerMinHeight)

        // A toolbar band is a full-bleed strip closed by one hairline, not
        // a bordered card floating over the content.
        let bandNode: ViewNode
        if let separatorColor = chrome.headerSeparatorColor {
            // `isSeparatorRule` is not decoration: it is how a container
            // knows a child is already a rule, and how the painter knows to
            // pin it to the device pixel grid. This one used to be a hairline
            // by thickness and colour only, so at 125% it drew at half the
            // weight of every other rule in the window.
            let bandRule = Controls.panel(
                preferredSize: Size(width: 0, height: retainedHairlineThickness(for: context)),
                backgroundColor: separatorColor,
                isHitTestVisible: false
            )
            bandRule.isSeparatorRule = true
            bandNode = Controls.stackPanel(
                stackLayout: .vertical(spacing: 0, alignment: .stretch),
                isHitTestVisible: false,
                children: [headerNode, bandRule]
            )
        } else {
            bandNode = headerNode
        }

        let container = Controls.stackPanel(
            backgroundColor: chrome.containerBackground,
            borderColor: chrome.containerBorderColor,
            borderWidth: chrome.containerBorderWidth,
            cornerRadius: chrome.containerCornerRadius,
            stackLayout: .vertical(spacing: chrome.spacing, alignment: .stretch),
            isHitTestVisible: false,
            children: [bandNode, effectiveBodyNode]
        )
        // The navigation container is greedy, like an NSWindow content
        // view: the title band spans the window and the body takes the
        // rest of it rather than shrink-wrapping the widest screen.
        container.layoutFillAxes = .both
        return container
    }
}
/// Content bezel of a push button: the insets between the button's
/// chrome and its label, plus the minimum height of the pill.
struct RetainedButtonContentMetrics {
    var padding: EdgeInsets
    var minimumHeight: Double

    static let none = RetainedButtonContentMetrics(padding: .zero, minimumHeight: 0)
}
/// macOS push-button (NSButton, `.push` bezel) content metrics, anchored
/// to `MacOSControlMetrics.Button`.
///
/// Bezelled styles (`.automatic`, `.bordered`, `.borderedProminent`,
/// `.card`) get symmetric content insets and a control-size minimum
/// height, so a label never paints outside its own chrome. The bezel-less
/// styles (`.plain`, `.borderless`, `.link`, the accessory bars) opt out:
/// on macOS they are bare labels with a hit region.
func retainedButtonContentMetrics(
    style: ButtonStyle,
    controlSize: ControlSize
) -> RetainedButtonContentMetrics {
    switch style {
    case .plain, .borderless, .link, .accessoryBar, .accessoryBarAction:
        return .none
    default:
        break
    }

    switch controlSize {
    case .mini:
        return RetainedButtonContentMetrics(
            padding: EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6),
            minimumHeight: MacOSControlMetrics.Button.miniHeight
        )
    case .small:
        return RetainedButtonContentMetrics(
            padding: EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8),
            minimumHeight: MacOSControlMetrics.Button.smallHeight
        )
    case .regular:
        return RetainedButtonContentMetrics(
            padding: EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12),
            minimumHeight: MacOSControlMetrics.Button.regularHeight
        )
    case .large, .extraLarge:
        return RetainedButtonContentMetrics(
            padding: EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16),
            minimumHeight: MacOSControlMetrics.Button.largeHeight
        )
    }
}
/// One physical pixel in logical points — a macOS separator hairline
/// stays a hairline at every backing-scale factor, rather than doubling
/// to 2px at 2x the way a 1pt rule does.
@MainActor
func retainedHairlineThickness(for context: ViewBuildContext) -> Double {
    let pixelLength = context.pixelLength
    guard pixelLength.isFinite, pixelLength > 0 else {
        return 1
    }
    return min(1, pixelLength)
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
        let context = context.withViewIdentityType(Self.self)
        let visibleColumns = visibleColumns()
        let style = context.navigationSplitViewStyle
        let columnComponents = visibleColumns.map { column in
            let columnContext = context.withViewIdentityRole(column.role).withStackAxis(.vertical)
            return preservingViewIdentity(
                of: composeComponent(
                    from: column.views,
                    context: columnContext,
                    fallbackLayout: .stack(.vertical(alignment: .stretch))
                ),
                context: columnContext
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
            node.borderColor = index == count - 1 ? .clear : Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.08)
            node.borderWidth = index == count - 1 ? 0 : 1
        case .balanced:
            node.layoutPriority = 1
            node.backgroundColor = Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.24)
            node.borderColor = index == count - 1 ? .clear : Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.10)
            node.borderWidth = index == count - 1 ? 0 : 1
        case .prominentDetail:
            let isDetail = index == count - 1
            node.layoutPriority = isDetail ? 2 : 0.75
            node.backgroundColor =
                isDetail
                ? Color(red: 0.136, green: 0.136, blue: 0.136, alpha: 0.30)
                : Color(red: 0.087, green: 0.087, blue: 0.087, alpha: 0.28)
            node.borderColor = isDetail ? .clear : Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.12)
            node.borderWidth = isDetail ? 0 : 1
        case .prominentDetailAndSidebar:
            let isDetail = index == count - 1
            node.layoutPriority = isDetail ? 2 : 0.75
            node.backgroundColor =
                isDetail
                ? Color(red: 0.136, green: 0.136, blue: 0.136, alpha: 0.30)
                : Color(red: 0.087, green: 0.087, blue: 0.087, alpha: 0.28)
            node.borderColor = isDetail ? .clear : Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.12)
            node.borderWidth = isDetail ? 0 : 1
        }
    }

    private func visibleColumns() -> [(role: RetainedViewIdentity.Role, views: [AnyView])] {
        let columns = self.columns.enumerated().map { index, views in
            let role: RetainedViewIdentity.Role =
                index == 0 ? .sidebar : (index == self.columns.count - 1 ? .detail : .content)
            return (role: role, views: views)
        }
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
        let pages = viewIdentityOccurrences(content)
        let selectedPage = pages[selectedIndex]
        let pageIdentityContext = context.withViewIdentityRole(.page)
        for (index, page) in pages.enumerated() where index != selectedIndex {
            context.stateMountCoordinator?.preserveDeclaredScopes(
                page.declaredStateMountScopes(context: pageIdentityContext))
        }
        let tabBar = tabBarComponent(selectedIndex: selectedIndex, context: context)

        let chrome = Self.retainedTabChrome(
            for: context.tabViewStyle, palette: context.controlPalette)

        return Component { runtime in
            // A selector bar, not a groove. The band is the page tone with no
            // fill of its own, square, and closed by one hairline; the items
            // are transparent at rest and the selection is an underline. The
            // recessed track with a raised pill in it — three chained buttons
            // inside a fourth — is what made the top of every screen read as
            // a stack of rounded slabs rather than one chrome region.
            let hairline = Controls.panel(
                preferredSize: Size(width: 0, height: 1),
                backgroundColor: chrome.bandHairline,
                isHitTestVisible: false
            )
            hairline.layoutFillAxes = .horizontalOnly
            hairline.isSeparatorRule = true

            let tabBarNode = Controls.stackPanel(
                backgroundColor: chrome.bandFill,
                stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .stretch),
                isHitTestVisible: false,
                children: [tabBar.makeNode(runtime: runtime), hairline]
            )
            tabBarNode.layoutFillAxes = .horizontalOnly
            // The page is composed against the slot it will actually get,
            // not the whole window: the bar is measured first and its band
            // (plus the container's spacing) comes off the canvas a nested
            // GeometryReader reads. Without this the page lays out one
            // chrome-height too tall and runs off the bottom edge.
            let bandHeight = tabBarNode.intrinsicContentSize().height + Self.retainedTabPageSpacing
            let canvasSize = context.canvasSize
            let pageContext = pageIdentityContext.withCanvasSize(
                Size(
                    width: canvasSize.width,
                    height: max(0, canvasSize.height - bandHeight)
                )
            )
            let pageNode = selectedPage.makeComponent(context: pageContext).makeNode(runtime: runtime)
            // Selecting a different tab replaces the page rather than editing
            // it. Without an identity that moves with the selection the
            // reconciler matched the outgoing page to the incoming one by
            // position and rewrote it in place, so the switch was a hard cut:
            // a live capture of the demo switching screens showed 92 % of the
            // window changing in a single frame with nothing in flight on
            // either side of it, where macOS cross-dissolves. Tagging the page
            // with the selected index makes the old page depart — which is
            // what turns it into a fading removal overlay — and the new one
            // arrive, which is what gives it an insertion transition to play.
            pageNode.nodeTag = "tabview-page:\(selectedIndex)"
            pageNode.transition = RetainedTransition(kind: .opacity)
            pageNode.implicitReconcileAnimation = Self.retainedTabPageCrossfadeAnimation
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

            let container = Controls.stackPanel(
                stackLayout: .vertical(spacing: Self.retainedTabPageSpacing, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
            // The tab container is the window's content view: it takes the
            // whole proposal so the bar's geometry stops depending on which
            // page happens to be selected.
            container.layoutFillAxes = .both
            return container
        }
    }

    /// Gap between the tab band and the page it selects.
    ///
    /// Zero, and deliberately: the band and whatever chrome the page starts
    /// with have to read as *one* continuous region. A 10pt gutter between
    /// them put a stripe of window backdrop across the top of every screen,
    /// which is the third of the "three stacked slabs" the shell used to be.
    /// The band's own bottom hairline is the boundary.
    static let retainedTabPageSpacing: Double = 0

    /// The cross-dissolve between two pages.
    ///
    /// `NSTabViewController`'s automatic transition is a cross-fade, and
    /// SwiftUI's `TabView` on macOS dissolves rather than cutting. 0.25 s
    /// ease-in-out, the same interval and curve the disclosure reveal uses:
    /// both are "one piece of the window is replaced by another", and giving
    /// them different timings would read as two different apps. Carried on
    /// the node rather than waiting for an ambient `withAnimation`, because a
    /// tab press never has one.
    static let retainedTabPageCrossfadeAnimation = AnimationTransaction(
        duration: Controls.disclosureDuration, easing: .easeInOut)

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
            let palette = context.controlPalette
            let chrome = Self.retainedTabChrome(for: context.tabViewStyle, palette: palette)
            let tabNodes = viewIdentityOccurrences(content).enumerated().map { index, view in
                let isSelected = index == selectedIndex
                let labelViews = view.tabItem ?? [AnyView(Text("TAB \(index + 1)"))]
                let itemContext = context.withViewIdentityPrefix(view.structuralIdentity)
                let labelIdentityContext = itemContext.withViewIdentityRole(.label)
                // The selection is carried by the label's own rung and weight
                // plus the bar under it — there is no pill for a label colour
                // to have to survive. Selected is the primary rung at the
                // body-strong weight; everything else is the secondary rung,
                // which is what an unselected tab is.
                let labelContext =
                    isSelected
                    ? labelIdentityContext
                        .withForegroundColor(palette.label)
                        .withFontWeight(chrome.selectedLabelWeight)
                    : labelIdentityContext.withForegroundColor(palette.secondaryLabel)
                let labelNode = composeComponent(
                    from: labelViews,
                    context: labelContext,
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
                            itemContext.withViewIdentityRole(.value)
                                .makeRetainedBadgeNode(from: badgeViews, runtime: runtime),
                        ]
                    )
                } else {
                    tabContentNode = labelNode
                }
                // The indicator is in the tree for every tab, transparent on
                // the ones that are not selected: a bar that appears and
                // disappears would move the label by its own height on every
                // switch, and a selector bar's label must not move.
                let indicator = Controls.panel(
                    preferredSize: chrome.indicatorSize,
                    backgroundColor: isSelected ? palette.accentForeground : .clear,
                    cornerRadius: chrome.indicatorCornerRadius,
                    isHitTestVisible: false
                )
                indicator.nodeTag = isSelected ? "tab-indicator-selected" : "tab-indicator"

                // Transparent at rest, no border, no shadow, ever. The whole
                // affordance is the label's rung and the bar beneath it; the
                // hover fill exists so the pointer has something to land on.
                let tabPalette = SurfacePalette(
                    idle: .clear,
                    hovered: palette.pageItemHoverFill,
                    focused: .clear,
                    pressed: palette.surface2,
                    disabledForeground: palette.disabledLabel
                )

                return Controls.button(
                    runtime: runtime,
                    cornerRadius: chrome.tabCornerRadius,
                    palette: tabPalette,
                    chrome: SurfaceChrome(
                        borderColor: .clear,
                        borderWidth: 0,
                        focusRingColor: palette.accentRing,
                        focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth,
                        shadowColor: .clear,
                        shadowPressedColor: .clear
                    ),
                    layoutMode: .stack(
                        .vertical(
                            spacing: chrome.indicatorGap,
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
                    children: [tabContentNode, indicator]
                )
            }

            let row = Controls.stackPanel(
                preferredSize: Size(width: 0, height: chrome.bandHeight),
                stackLayout: .horizontal(
                    spacing: chrome.spacing,
                    padding: chrome.padding,
                    alignment: .center,
                    mainAlignment: .center
                ),
                isHitTestVisible: false,
                children: tabNodes
            )
            row.layoutFillAxes = .horizontalOnly
            return row
        }
    }

    private struct RetainedTabChrome {
        /// The band: the page tone, square, full bleed.
        var bandFill: Color
        /// The one line that closes it.
        var bandHairline: Color
        var bandHeight: Double
        var spacing: Double
        var padding: EdgeInsets
        var tabCornerRadius: Double
        var tabPadding: EdgeInsets
        /// The selection bar under the label.
        var indicatorSize: Size
        var indicatorCornerRadius: Double
        var indicatorGap: Double
        /// `body-strong`: the selected label moves one weight step, not one
        /// size step. Size is what a tab bar cannot spend, because a label
        /// that grows on selection re-lays the whole bar out.
        var selectedLabelWeight: Font.Weight
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
                    : Color(red: 0.794, green: 0.794, blue: 0.794, alpha: 0.42),
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
                    backgroundColor: Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.34),
                    borderColor: Color(red: 0.977, green: 0.977, blue: 0.977, alpha: 0.08),
                    borderWidth: 1,
                    cornerRadius: 9
                )
            case .always:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.72),
                    borderColor: Color(red: 0.977, green: 0.977, blue: 0.977, alpha: 0.14),
                    borderWidth: 1,
                    cornerRadius: 10
                )
            case .interactive:
                return RetainedPageIndexChrome(
                    backgroundColor: Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.52),
                    borderColor: Color(red: 0.977, green: 0.977, blue: 0.977, alpha: 0.12),
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

    private static func retainedTabChrome(for style: TabViewStyle, palette: ControlPalette) -> RetainedTabChrome {
        // The band is the *chrome* tone with a hairline under it, in every
        // style. Only the item's own box changes: a page-style bar is a
        // denser row than a window's primary navigation, and a carousel's is
        // looser. Neither of them grows a groove.
        //
        // `chromeBand`, not `base`: the selector bar and the toolbar band
        // below it are one chrome unit, and a unit painted in the window's own
        // backdrop tone is a unit you cannot see. Both now sit a full ramp rung
        // above the columns beside them — the bar opaquely, the toolbar through
        // `.bar`, which solves for the same landing tone.
        let metrics = MacOSControlMetrics.SelectorBar.self
        let base = RetainedTabChrome(
            bandFill: palette.chromeBand,
            bandHairline: palette.separator,
            bandHeight: metrics.bandHeight,
            spacing: metrics.itemSpacing,
            padding: EdgeInsets(
                top: 0,
                leading: MacOSControlMetrics.Spacing.s4,
                bottom: 0,
                trailing: MacOSControlMetrics.Spacing.s4
            ),
            tabCornerRadius: metrics.itemCornerRadius,
            tabPadding: EdgeInsets(
                top: 0,
                leading: metrics.itemHorizontalPadding,
                bottom: 0,
                trailing: metrics.itemHorizontalPadding
            ),
            indicatorSize: metrics.indicatorSize,
            indicatorCornerRadius: metrics.indicatorCornerRadius,
            indicatorGap: metrics.indicatorGap,
            selectedLabelWeight: .medium
        )
        switch style.kind {
        case .automatic, .tabBarOnly, .grouped, .sidebarAdaptable:
            return base
        case .page, .verticalPage:
            var chrome = base
            chrome.bandHeight = 32
            chrome.tabPadding = EdgeInsets(
                top: 0, leading: MacOSControlMetrics.Spacing.s2,
                bottom: 0, trailing: MacOSControlMetrics.Spacing.s2)
            return chrome
        case .carousel:
            var chrome = base
            chrome.spacing = MacOSControlMetrics.Spacing.s2
            chrome.tabPadding = EdgeInsets(
                top: 0, leading: MacOSControlMetrics.Spacing.s4,
                bottom: 0, trailing: MacOSControlMetrics.Spacing.s4)
            return chrome
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
public struct ForEach<Data: RandomAccessCollection, ID: Hashable>: View, StateMountDeclarationView,
    ViewListProjectionProvider
{
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
        let context = context.withViewIdentityType(Self.self)
        return preservingViewIdentity(
            of: composeStructuralComponent(from: contentViews, context: context.withViewIdentityRole(.content)),
            context: context)
    }

    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        let context = context.withViewIdentityType(Self.self)
        let contentContext = context.withViewIdentityRole(.content)
        return [StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .modifierContent)]
            + viewIdentityOccurrences(contentViews).flatMap { $0.declaredStateMountScopes(context: contentContext) }
    }

    func viewListProjection() -> ViewListProjection {
        .scope(
            .type(ObjectIdentifier(Self.self)), excluding: .modifierContent,
            children: [
                .scope(
                    .prefix([.role(.content)]), excluding: nil,
                    children: viewIdentityOccurrences(contentViews).map { .value($0) })
            ])
    }

    private static func buildContentViews(
        data: Data,
        id: KeyPath<Data.Element, ID>,
        content: (Data.Element) -> [AnyView]
    ) -> [AnyView] {
        var views: [AnyView] = []
        for (elementIndex, element) in data.enumerated() {
            let elementID = element[keyPath: id]
            let elementViews = normalizedProjectedViewList(content(element))
            for (index, view) in elementViews.enumerated() {
                views.append(
                    view.ensuringViewIdentitySlot(index).mappingViewIdentity { content in
                        AnyView(
                            DynamicListEditMetadataView(
                                content: AnyView(content.implicitForEachScrollTarget(elementID, index: index)),
                                dynamicContentIndex: elementIndex
                            )
                        )
                    }
                    .prefixedViewIdentity([.keyed(RetainedViewIdentity.Key(elementID))])
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
                view.mappingViewIdentity { content in
                    AnyView(
                        DynamicListEditMetadataView(
                            content: content,
                            deleteAction: .some(action)
                        )
                    )
                }
            }
        )
    }

    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> ForEach<Data, ID> {
        ForEach(
            data: data,
            contentViews: contentViews.map { view in
                view.mappingViewIdentity { content in
                    AnyView(
                        DynamicListEditMetadataView(
                            content: content,
                            moveAction: .some(action)
                        )
                    )
                }
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
                view.mappingViewIdentity { content in
                    AnyView(
                        DynamicListEditMetadataView(
                            content: content,
                            insertContentTypes: identifiers,
                            insertAction: action
                        )
                    )
                }
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
                view.mappingViewIdentity { content in
                    AnyView(
                        DynamicListEditMetadataView(
                            content: content,
                            insertContentTypes: acceptedTypeIdentifiers,
                            insertAction: action
                        )
                    )
                }
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
                view.mappingViewIdentity { content in
                    AnyView(
                        DynamicListEditMetadataView(
                            content: content,
                            dropPayloadType: String(reflecting: payloadType),
                            dropAction: { payloads, offset in
                                action(payloads.compactMap { $0 as? T }, offset)
                            }
                        )
                    )
                }
            }
        )
    }
}
@MainActor
private struct DynamicListEditMetadataView: View, TaggedViewMetadata, StateMountDeclarationView {
    typealias Body = Never

    let content: AnyView
    var dynamicContentIndex: Int? = nil
    var deleteAction: (((IndexSet) -> Void)?)? = nil
    var moveAction: (((IndexSet, Int) -> Void)?)? = nil
    var insertContentTypes: [String]? = nil
    var insertAction: ((Int, [NSItemProvider]) -> Void)? = nil
    var dropPayloadType: String? = nil
    var dropAction: (([Any], Int) -> Void)? = nil

    func declaredStateMountScopes(context: ViewBuildContext) -> [StateMountDeclarationScope] {
        let context = context.withViewIdentityType(Self.self)
        return [StateMountDeclarationScope(prefix: context.retainedViewIdentity, excluding: .typedContent)]
            + content.declaredStateMountScopes(context: context)
    }

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
    private var fontWeight: Font.Weight?
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
        self.fontWeight = nil
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
        fontWeight: Font.Weight?,
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
        self.fontWeight = fontWeight
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
            fontWeight: lhs.fontWeight ?? rhs.fontWeight,
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
                colorScheme: context.colorScheme,
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        let inheritedFont = context.fontWeight.map { context.font.weight($0) } ?? context.font
        var resolvedFont: Font
        if let font {
            // `.font(nil)` is "clear the ambient font", which SwiftUI
            // resolves to the system default — `.body` — not to some other
            // size.
            resolvedFont = font ?? .body
        } else {
            resolvedFont = inheritedFont
        }
        if let fontWeight {
            resolvedFont = resolvedFont.weight(fontWeight)
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
                // Native tracking only when the app actually asked, or when
                // the text is uppercase. The `?? 1` above is the 5x7 atlas
                // gap, not a point value.
                //
                // Uppercase runs need positive tracking: capitals are drawn
                // with sidebearings tuned for mixed case, so set solid they
                // read as a shouty banner rather than a label. macOS uses
                // roughly 0.06em on caption-scale caps, which is exactly
                // where uppercase labels live.
                nativeLetterSpacing: letterSpacing ?? context.letterSpacing
                    ?? uppercaseTracking(for: resolvedFont, textCase: textCase ?? context.textCase),
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
        copy.fontWeight = weight
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

    /// Default tracking for an uppercase run, in points, or `nil` when the
    /// text is not uppercase and should keep the face's own metrics.
    private func uppercaseTracking(for font: Font, textCase: Text.Case?) -> Double? {
        guard textCase == .uppercase else {
            return nil
        }
        return font.resolvedNativeTextSize * MacOSControlMetrics.Typography.uppercaseTrackingRatio
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
    /// `nil` means "inherit the ambient font", which is what SwiftUI does:
    /// a symbol sits at the size of the text it is beside. This used to be
    /// a non-optional `.system(size: 1.9)` — a legacy 5x7 scale unit that
    /// expanded to a fixed 19.4px box regardless of the surrounding type.
    private var font: Font?
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
        self.font = nil
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
                    colorScheme: context.colorScheme,
                    contrast: context.colorSchemeContrast,
                    backgroundProminence: context.backgroundProminence
                )
            let renderedColor = retainedSymbolColor(
                base: resolvedColor,
                mode: context.symbolRenderingMode,
                tint: context.tint
            )
            let imageScale = context.imageScale.resolvedMultiplier
            let symbolFont = font ?? context.font
            // An SF Symbol's image box is taller than the point size of the
            // text it accompanies — the glyph is drawn to the font's
            // ascender-to-descender box, not its cap height. Without the
            // ratio a 13pt row label would sit beside a 13px icon and read
            // as the larger element.
            let symbolBox = symbolFont.resolvedNativeTextSize * MacOSControlMetrics.Typography.symbolBoxRatio
            let resolvedScale = symbolFont.resolvedScale * imageScale
            let baseSize = Size(width: symbolBox * imageScale, height: symbolBox * imageScale)
            let preferredSize = resolvedPreferredSize(baseSize: baseSize, requiresExplicitOptIn: true)
            return Component { _ in
                let node = Controls.icon(
                    symbol,
                    preferredSize: preferredSize,
                    color: renderedColor,
                    scale: resolvedScale,
                    weight: symbolVariants.contains(.fill) ? .bold : .regular,
                    alignment: alignment.textAlignment(layoutDirection: context.layoutDirection),
                    // From this view's environment, not the process-global
                    // default: two hosts on monitors at different DPI each
                    // rasterize at their own scale.
                    displayScale: context.iconRasterDisplayScale,
                    bitmapFontAttribution: context.bitmapFontAttribution
                )
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
            // Ordinary stretching accepts layout's finite proposal. Keep the
            // bitmap as its intrinsic fallback instead of pinning an explicit
            // preferred size, which also defeats fill in absolute containers.
            // Aspect, tile, and cap-inset modes need their own sizing/paint rules.
            let stretchesToProposal =
                isResizable && resizingMode == .stretch && capInsets == .zero && contentMode == nil
            let preferredSize =
                stretchesToProposal
                ? nil : resolvedPreferredSize(baseSize: bitmap?.logicalSize, requiresExplicitOptIn: false)
            return Component { _ in
                guard let bitmap else {
                    let node = Controls.panel(preferredSize: preferredSize, isHitTestVisible: false)
                    applyImageMetadata(to: node, context: context)
                    return node
                }

                let renderedBitmap = resolvedBitmapSurface(bitmap, context: context)
                let node = Controls.image(renderedBitmap, preferredSize: preferredSize)
                if stretchesToProposal { node.layoutFillAxes = .both }
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
                colorScheme: context.colorScheme,
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
        let context = context.withViewIdentityType(Self.self)
        // In a grouped form the label belongs to the shared label column and
        // reads at the row's own prominence; standing alone it is the
        // secondary half of a label/value pair.
        let isFormRow = context.isInsideGroupedForm
        let labelComponent = composeComponent(
            from: label,
            context: isFormRow
                ? context
                    .withViewIdentityRole(.label)
                    .withTextAlignment(.trailing)
                    .withLineLimit(1)
                : context
                    .withViewIdentityRole(.label)
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
                .withViewIdentityRole(.value)
                .withTextAlignment(isFormRow ? .leading : .trailing)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            let contentNode = contentComponent.makeNode(runtime: runtime)
            guard !isFormRow else {
                return groupedFormRowNode(label: labelNode, content: contentNode)
            }
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
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
    /// `nil` means "inherit the ambient font", which is what a macOS
    /// `Label` does. This used to be a hardcoded `.system(size: 1.6,
    /// weight: .semibold)` — 17.6px semibold via the legacy scale-unit rule
    /// — applied with `.withFont`, so it *overrode* any `.font()` the app
    /// had set on the list around it and turned every plain row into a
    /// banner. A macOS list row is regular weight at the ambient size.
    private var font: Font?
    private var spacing: Double

    public init(_ title: String, image name: String) {
        self.title = [
            AnyView(Text(title).multilineTextAlignment(.leading))
        ]
        self.icon = [
            AnyView(Image(name))
        ]
        self.color = nil
        self.font = nil
        self.spacing = MacOSControlMetrics.Layout.labelIconSpacing
    }

    public init<S: StringProtocol>(_ title: S, image name: String) {
        self.init(String(title), image: name)
    }

    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.init(titleKey.resolvedString, image: name)
    }

    public init<S: StringProtocol>(_ title: S, image resource: ImageResource) {
        self.title = [
            AnyView(Text(String(title)).multilineTextAlignment(.leading))
        ]
        self.icon = [
            AnyView(Image(resource))
        ]
        self.color = nil
        self.font = nil
        self.spacing = MacOSControlMetrics.Layout.labelIconSpacing
    }

    public init(_ titleKey: LocalizedStringKey, image resource: ImageResource) {
        self.init(titleKey.resolvedString, image: resource)
    }

    public init(_ title: String, systemImage: String) {
        self.title = [
            AnyView(Text(title).multilineTextAlignment(.leading))
        ]
        self.icon = [
            AnyView(Image(systemName: systemImage))
        ]
        self.color = nil
        self.font = nil
        self.spacing = MacOSControlMetrics.Layout.labelIconSpacing
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
        self.font = nil
        self.spacing = MacOSControlMetrics.Layout.labelIconSpacing
    }

    public var body: Never {
        fatalError("Label has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let resolvedColor = (color ?? context.foregroundColor)
            .resolvedForVisualEnvironment(
                colorScheme: context.colorScheme,
                contrast: context.colorSchemeContrast,
                backgroundProminence: context.backgroundProminence
            )
        // Only narrow what the label actually owns. Forcing `lineLimit(1)`
        // here is not something SwiftUI does, and it made every wrapped
        // label in the app truncate.
        var labelContext =
            context
            .withForegroundColor(resolvedColor)
            .withTextAlignment(.leading)
        if let font {
            labelContext = labelContext.withFont(font)
        }
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
        let context = context.withViewIdentityType(Self.self)
        let labelComponent = composeComponent(
            from: label,
            context:
                context
                .withViewIdentityRole(.label)
                .withTextAlignment(.center)
                .withLineLimit(2),
            fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center, mainAlignment: .center)),
            isHitTestVisible: false
        )
        let descriptionComponent = composeComponent(
            from: description,
            context:
                context
                .withViewIdentityRole(.description)
                .withForegroundColor(.secondary)
                .withFont(.caption)
                .withTextAlignment(.center),
            fallbackLayout: .stack(.vertical(spacing: 4, alignment: .center)),
            isHitTestVisible: false
        )
        let actionsComponent = composeComponent(
            from: actions,
            context: context.withViewIdentityRole(.actions).withButtonStyle(.bordered),
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
        // A Spacer is greedy along the axis it sits on: SwiftUI hands it the
        // proposal and it expands to fill whatever the row's other children
        // leave. Declaring that as a fill axis is what makes the *row* take
        // the width it is offered instead of the width of its content — a
        // toolbar spanning its window rather than stopping at its last
        // button. Off the stack axis it stays inert, and with no stack at
        // all it is a plain `minLength` box.
        let fillAxes: LayoutFillAxes
        switch context.stackAxis {
        case .horizontal:
            preferredSize = Size(width: minLength ?? 0, height: 0)
            fillAxes = .horizontalOnly
        case .vertical:
            preferredSize = Size(width: 0, height: minLength ?? 0)
            fillAxes = .verticalOnly
        case nil:
            preferredSize = Size(width: minLength ?? 0, height: minLength ?? 0)
            fillAxes = LayoutFillAxes()
        }

        return Component { _ in
            let node = Controls.panel(
                preferredSize: preferredSize,
                layoutPriority: 1,
                isHitTestVisible: false
            )
            node.layoutFillAxes = fillAxes
            return node
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
        let thickness = retainedHairlineThickness(for: context)
        // NSColor.separatorColor: white/black at 10%. The 0.22 white this
        // used to draw is roughly twice the macOS rule and carried the same
        // blue cast as the rest of the retired palette.
        let separatorColor = context.controlPalette.separator
        return Component { _ in
            // A Divider has thickness on one axis and no extent of its own
            // on the other: it fills whatever its container proposes across,
            // exactly like a macOS separator. Leaving the cross axis at zero
            // (rather than the old 16pt stub) is what lets a stretch stack —
            // or the greedy cross-axis fill below — give it the full width.
            let node = Controls.panel(
                preferredSize: Size(
                    width: isVertical ? thickness : 0,
                    height: isVertical ? 0 : thickness
                ),
                backgroundColor: separatorColor,
                isHitTestVisible: false
            )
            node.layoutFillAxes = isVertical ? .verticalOnly : .horizontalOnly
            node.isSeparatorRule = true
            return node
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
        self.spacing = spacing ?? MacOSControlMetrics.Layout.defaultStackSpacing
        self.content = content()
    }

    public var body: Never {
        fatalError("VStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let context = context.withViewIdentityType(Self.self)
        return Component { runtime in
            let childContext = context.withViewIdentityRole(.content).withStackAxis(.vertical)
            var children: [ViewNode] = []
            children.reserveCapacity(content.count)
            for view in viewIdentityOccurrences(content) {
                view.makeComponent(context: childContext).appendChildNodes(runtime: runtime, to: &children)
            }
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
public struct HStack: View {
    public typealias Body = Never

    private let alignment: VerticalAlignment
    private let spacing: Double
    private let content: [AnyView]

    public init(alignment: VerticalAlignment = .center, spacing: Double? = nil, @ViewBuilder content: () -> [AnyView]) {
        self.alignment = alignment
        self.spacing = spacing ?? MacOSControlMetrics.Layout.defaultStackSpacing
        self.content = content()
    }

    public var body: Never {
        fatalError("HStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let context = context.withViewIdentityType(Self.self)
        return Component { runtime in
            let childContext = context.withViewIdentityRole(.content).withStackAxis(.horizontal)
            var children: [ViewNode] = []
            children.reserveCapacity(content.count)
            for view in viewIdentityOccurrences(content) {
                view.makeComponent(context: childContext).appendChildNodes(runtime: runtime, to: &children)
            }
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: children
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
        self.spacing = spacing ?? MacOSControlMetrics.Layout.defaultStackSpacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyVStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let context = context.withViewIdentityType(Self.self)
        return Component { runtime in
            let childContext = context.withViewIdentityRole(.content).withStackAxis(.vertical)
            let children = retainedLazyStackChildren(
                from: content,
                context: childContext,
                runtime: runtime,
                pinnedViews: pinnedViews
            )
            let panel = Controls.stackPanel(
                stackLayout: .vertical(
                    spacing: spacing,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                ),
                isHitTestVisible: false,
                children: children
            )
            // The "lazy" in LazyVStack: rows the scroll viewport (plus a
            // viewport of overscan) cannot reach are placed but not laid out
            // recursively. Falls back to eager behaviour verbatim when there
            // is no scrollable ancestor to bound the work.
            panel.layoutMode = .lazyStack(
                .vertical(
                    spacing: spacing,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                ))
            return panel
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
        self.spacing = spacing ?? MacOSControlMetrics.Layout.defaultStackSpacing
        self.pinnedViews = pinnedViews
        self.content = content()
    }

    public var body: Never {
        fatalError("LazyHStack has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        let context = context.withViewIdentityType(Self.self)
        return Component { runtime in
            let childContext = context.withViewIdentityRole(.content).withStackAxis(.horizontal)
            let children = retainedLazyStackChildren(
                from: content,
                context: childContext,
                runtime: runtime,
                pinnedViews: pinnedViews
            )
            let panel = Controls.stackPanel(
                stackLayout: .horizontal(spacing: spacing, alignment: alignment.stackAlignment),
                isHitTestVisible: false,
                children: children
            )
            panel.layoutMode = .lazyStack(
                .horizontal(spacing: spacing, alignment: alignment.stackAlignment))
            return panel
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
    let children = viewIdentityOccurrences(content).map {
        $0.makeComponent(context: context).makeNode(runtime: runtime)
    }
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
                children: viewIdentityOccurrences(content).map {
                    $0.makeComponent(context: childContext).makeNode(runtime: runtime)
                }
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
                children: viewIdentityOccurrences(content).map {
                    $0.makeComponent(context: childContext).makeNode(runtime: runtime)
                }
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
        self.spacing = spacing ?? MacOSControlMetrics.Layout.defaultStackSpacing
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
        self.spacing = spacing ?? MacOSControlMetrics.Layout.defaultStackSpacing
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
            let childNodes = viewIdentityOccurrences(content).map {
                $0.makeComponent(context: context).makeNode(runtime: runtime)
            }
            let root = Controls.panel(layoutMode: .absolute, isHitTestVisible: false, children: childNodes)
            // A ZStack containing flexible content must accept its parent's
            // proposal too. Otherwise a framed Color background stops at the
            // tallest fixed overlay rather than filling the frame.
            root.layoutFillAxes = LayoutFillAxes(
                horizontal: childNodes.contains { !$0.isHidden && $0.layoutFillAxes.horizontal },
                vertical: childNodes.contains { !$0.isHidden && $0.layoutFillAxes.vertical }
            )
            root.absoluteChildFrame = { child, bounds in
                let intrinsic = child.intrinsicContentSize()
                // Flexible children accept the stack's proposal; fixed ones
                // keep their intrinsic size. Placement must not write the
                // authored frame, or an allocated width becomes the next
                // measurement's intrinsic width and columns never settle.
                let fill = child.layoutFillAxes
                let childSize = Size(
                    width: fill.horizontal ? bounds.size.width : intrinsic.width,
                    height: fill.vertical ? bounds.size.height : intrinsic.height
                )
                let origin = alignment.frameOrigin(
                    for: childSize,
                    in: bounds.size,
                    layoutDirection: context.layoutDirection
                )
                return Rect(origin: origin, size: childSize)
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
        withInstalledViewValue(self, context: context, isInstalledDelegate: true) { reader, scopedContext in
            reader.makeReaderComponent(context: scopedContext)
        }
    }

    private func makeReaderComponent(context: ViewBuildContext) -> Component {
        let seedSize = context.canvasSize
        let content = self.content
        let contentContext = context.withViewIdentityRole(.geometryContent)
        let contentPrefix = contentContext.retainedViewIdentity
        let lease =
            context.viewIdentity.installedOwner.map { owner in
                context.stateMountCoordinator?.subtreeLease(owner: owner, contentPrefix: contentPrefix)
            } ?? nil
        let views = ViewBuildContextScope.withCurrent(contentContext) {
            content(GeometryProxy(size: seedSize))
        }
        let composed = composeComponent(
            from: views,
            context: contentContext,
            fallbackLayout: .absolute
        )
        return Component { runtime in
            let bodyNode = composed.makeNode(runtime: runtime)
            // A GeometryReader is greedy in its parent's proposal, and the
            // proxy is supposed to describe exactly that slot. Containers
            // that consume chrome narrow the canvas they hand down (see
            // `ViewBuildContext.withCanvasSize`), so the seed is already
            // right wherever a container knows what it took.
            bodyNode.layoutFillAxes = .both

            // The reader gets a node of its own rather than collapsing into
            // its body, because a body is free to pin its own extent —
            // `GeometryReader { Text().frame(width: 80) }` — and a collapsed
            // reader would then have no node whose resolved frame is the
            // slot. The wrapper is greedy and lays out absolutely, so the
            // body sits where it always sat and the wrapper's frame is the
            // slot the parent actually handed over.
            let node = Controls.panel(layoutMode: .absolute, isHitTestVisible: false, children: [bodyNode])
            node.retainedViewIdentity = context.retainedViewIdentity
            node.layoutFillAxes = .both

            // Wherever no container narrowed — nested stacks, split panes,
            // a sidebar beside the reader — the seed is the whole canvas and
            // the body over-reports until the layout has run. Build order
            // cannot fix that: the reader's siblings have not been measured
            // yet. So the seed is a hint, and the resolved slot is the
            // authority: the runtime re-invokes this closure once the frame
            // is known and adopts the result onto the node it already has
            // (see `RetainedViewRuntime.resolveGeometryReaderSlots`).
            node.geometryReaderBuiltSize = seedSize
            node.retainedSubtreeBuildLease = lease
            context.stateMountCoordinator?.materializeSubtreeLease(lease)
            node.geometryReaderBuild = { runtime, size in
                if let coordinator = context.stateMountCoordinator {
                    guard lease?.canBuild == true,
                        coordinator.canEvaluateDeferredSubtree(at: contentPrefix)
                    else { return [] }
                }
                // Rebuilt as a whole reader, not just as its body, so the
                // node the runtime adopts carries the next round's build
                // closure and its own record of the size it was built from.
                // The narrowed context also re-seeds any reader nested in
                // this body, so nesting converges in rounds rather than in
                // one round per level.
                let rebuilt = GeometryReader(content: content)
                    .makeReaderComponent(context: context.withCanvasSize(size))
                    .makeNode(runtime: runtime)
                if let coordinator = context.stateMountCoordinator {
                    guard lease?.canBuild == true,
                        coordinator.canEvaluateDeferredSubtree(at: contentPrefix)
                    else { return [] }
                }
                return [rebuilt]
            }
            return node
        }
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
            let palette = context.controlPalette
            let usesOverlayIndicator =
                context.scrollIndicatorVisibility(for: axis).usesRetainedOverlayScrollIndicator
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
                scrollIndicatorColor: style.indicatorColor ?? palette.scrollerKnob,
                scrollIndicatorHoverColor: style.indicatorHoverColor ?? palette.scrollerKnobHovered,
                scrollIndicatorActiveColor: style.indicatorActiveColor ?? palette.scrollerKnobActive,
                scrollIndicatorThickness: style.indicatorThickness,
                scrollIndicatorInsets: scrollIndicatorInsets,
                scrollIndicatorAutoHides: usesOverlayIndicator,
                initialScrollAnchor: initialScrollAnchor,
                scrollSizeChangeAnchor: scrollSizeChangeAnchor,
                isHitTestVisible: style.isHitTestVisible,
                children: viewIdentityOccurrences(content).map {
                    $0.makeComponent(context: context).makeNode(runtime: runtime)
                }
            )
            // macOS parity: a scroll view is greedy. It takes the whole
            // proposal on both axes and proposes its viewport across to
            // its content, which is what keeps a form column attached to
            // the scroller instead of floating at its intrinsic width.
            node.layoutFillAxes = .both
            node.horizontalScrollBounceBehavior = context.horizontalScrollBounceBehavior.description
            node.verticalScrollBounceBehavior = context.verticalScrollBounceBehavior.description
            node.scrollTargetBehavior = context.scrollTargetBehavior?.description
            node.scrollInputBehaviors = context.retainedScrollInputBehaviors
            node.scrollIndicatorsFlashOnAppear = context.scrollIndicatorsFlashOnAppear
            node.scrollIndicatorsFlashTrigger = context.scrollIndicatorsFlashTrigger
            node.scrollPosition = context.scrollPositionMetadata
            node.isScrollInputEnabled = context.isScrollEnabled
            if !context.isScrollEnabled {
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
        // The default cross axis is `.stretch` because a scroll view
        // proposes its viewport across to its content, exactly as macOS
        // does: a Form or a card column fills the width and the scroller
        // stays attached to the content edge instead of standing off in
        // bare background. An explicit `ScrollViewStyle.alignment` — or a
        // `defaultScrollAnchor` — still wins.
        let styleAlignment = style.explicitAlignment?.stackAlignment(layoutDirection: layoutDirection)
        switch axis {
        case .horizontal:
            return .horizontal(
                spacing: style.spacing,
                padding: padding,
                // A horizontal scroller's cross axis is vertical, which
                // `style.alignment` (a horizontal alignment) cannot describe.
                alignment: alignmentAnchor.map { stackCrossAlignment(from: $0.y) } ?? .stretch,
                mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.x) } ?? .start
            )
        case .vertical:
            return .vertical(
                spacing: style.spacing,
                padding: padding,
                alignment: alignmentAnchor.map { stackCrossAlignment(from: $0.x) } ?? styleAlignment ?? .stretch,
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
            proxy.attach(to: node, runtime: runtime)
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

    /// Moves a single selection to a neighboring tag within the ordered
    /// selectable tags and returns the newly selected tag, or nil when the
    /// selection did not change (boundary reached, empty list, or a
    /// multi-selection list, where arrow-key movement would destroy the
    /// existing selection anchor).
    func moveSelection(
        within orderedTags: [AnyHashable],
        indicesByTag: [AnyHashable: Int],
        delta: Int
    ) -> AnyHashable? {
        guard case .single(let get, let set) = self, !orderedTags.isEmpty, delta != 0 else {
            return nil
        }

        let current = get()
        let nextIndex: Int
        if let current, let currentIndex = indicesByTag[current] {
            nextIndex = min(max(currentIndex + delta, 0), orderedTags.count - 1)
        } else {
            nextIndex = delta > 0 ? 0 : orderedTags.count - 1
        }

        let next = orderedTags[nextIndex]
        guard next != current else {
            return nil
        }

        set(next)
        return next
    }
}
/// Per-build keyboard navigation state for a selection-bound `List`.
///
/// Selectable rows register themselves in build order so an arrow-key press
/// on the focused row can resolve the neighboring selectable tag, move focus,
/// and scroll the target row into the viewport. The runtime owns the placed
/// geometry and scroll clamp, including rows deferred by list virtualization;
/// mirroring frames through `onLayout` would lose precisely those rows.
@MainActor
private final class ListKeyboardNavigationState {
    @MainActor
    private final class RowEntry {
        weak var node: ViewNode?

        init(node: ViewNode) {
            self.node = node
        }
    }

    private weak var runtime: RetainedViewRuntime?
    private var orderedRowTags: [AnyHashable] = []
    private var entriesByTag: [AnyHashable: RowEntry] = [:]
    private var indicesByTag: [AnyHashable: Int] = [:]

    init(runtime: RetainedViewRuntime) {
        self.runtime = runtime
    }

    func registerRow(tag: AnyHashable, node: ViewNode) {
        let entry = RowEntry(node: node)
        let index = orderedRowTags.count
        orderedRowTags.append(tag)

        // Preserve the previous `first(where:)`/`firstIndex(of:)` behavior
        // if application data accidentally repeats a selection identity.
        if entriesByTag[tag] == nil {
            entriesByTag[tag] = entry
            indicesByTag[tag] = index
        }
    }

    func rowNode(for tag: AnyHashable) -> ViewNode? {
        entriesByTag[tag]?.node
    }

    func moveSelection(_ mode: ListSelectionMode, delta: Int) -> AnyHashable? {
        mode.moveSelection(within: orderedRowTags, indicesByTag: indicesByTag, delta: delta)
    }

    /// Uses the already-placed row frame rather than a lifecycle callback, so
    /// keyboard selection can reach a row whose subtree is still deferred.
    func scrollRowIntoView(tag: AnyHashable) {
        guard
            let entry = entriesByTag[tag],
            let rowNode = entry.node
        else {
            return
        }

        if !rowNode.scrollIntoView(), let runtime {
            let requestKey = "list.selection.\(String(describing: tag.base))"
            runtime.scheduleAfterLayout(key: requestKey) { [weak runtime, weak rowNode] in
                guard let runtime, let rowNode else { return }
                _ = runtime.scrollToDescendant(rowNode)
            }
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
        // A List's rows are table rows, not grouped-form rows: a List nested
        // inside a Form must not inherit the two-column grid, or its cells
        // start reserving a label column the table has no use for.
        let context = context.withEnvironmentValue(\.isInsideGroupedForm, false)
        return Component { runtime in
            let listChrome = context.listStyle.retainedChrome(palette: context.controlPalette)
            let alignmentAnchor = context.defaultScrollAnchor(for: .alignment)
            let isEditing = context.environmentValues.editMode?.wrappedValue.isEditing == true
            let navigationState = ListKeyboardNavigationState(runtime: runtime)
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
                children: Self.rowNodesWithSeparators(
                    listChrome: listChrome,
                    palette: context.controlPalette,
                    displayScale: context.displayScale,
                    rows: content.enumerated().map { pair -> (node: ViewNode, isSelected: Bool) in
                        let index = pair.offset
                        let view = pair.element
                        let tag = view.selectionTag
                        let isSelected = tag.map { selectionMode?.contains($0) == true } == true
                        // A selected row is an accent *wash* now, not a solid
                        // accent fill (§1.6), so its content is **not**
                        // inverted to white: white on `#E4E2F8` in the light
                        // appearance is unreadable, and the wash plus the
                        // row's leading indicator already says "this one".
                        // The inherited default is the primary rung — a
                        // selected row is the one you are meant to read — and
                        // a row whose content sets its own colour still wins.
                        //
                        // `.increased` background prominence stays what it
                        // has always been, the "this content sits on a filled
                        // emphasised surface" signal, and is therefore *not*
                        // set here: this surface is no longer filled.
                        var rowContext = context
                        if isSelected, context.environmentValues.controlActiveState != .inactive {
                            rowContext = rowContext.withForegroundColor(context.controlPalette.label)
                        }
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
                        var isSelectionBoundRow = false
                        if let selectionMode, let tag, !row.selectionDisabled {
                            row = Self.selectableRow(
                                wrapping: row,
                                tag: tag,
                                selectionMode: selectionMode,
                                isSelected: isSelected,
                                isEditing: isEditing,
                                context: context,
                                runtime: runtime,
                                navigationState: navigationState
                            )
                            isSelectionBoundRow = true
                        }
                        row = Self.alternatingRowIfNeeded(
                            row,
                            index: index,
                            isSelected: isSelected,
                            listChrome: listChrome
                        )
                        // Rows keep a consistent minimum height so selection and
                        // hover chrome never changes row metrics. An explicit
                        // `defaultMinListRowHeight` environment value wins over
                        // the built-in default for selection-bound rows.
                        let rowMinHeight =
                            context.defaultMinListRowHeight > 0
                            ? context.defaultMinListRowHeight
                            : max(
                                listChrome.rowMinHeight,
                                isSelectionBoundRow ? Self.defaultSelectionRowMinHeight : 0
                            )
                        if rowMinHeight > 0 {
                            row.applyDefaultMinimumHeight(rowMinHeight)
                        }
                        if isSelectionBoundRow, context.isEnabled, let tag {
                            navigationState.registerRow(tag: tag, node: row)
                        }
                        return (row, isSelected)
                    }
                )
            )
            // A List is greedy on macOS: it takes the space it is offered
            // and proposes the row width across, instead of shrink-wrapping
            // its widest row.
            node.layoutFillAxes = .both
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
            // A List's scroller is the same overlay scroller a ScrollView gets;
            // it used to keep the retained defaults, which are a blue-tinted
            // near-white bar that is always on and invisible in light mode.
            let listPalette = context.controlPalette
            node.scrollIndicatorThickness = MacOSControlMetrics.Scroller.overlayThumbThickness
            node.scrollIndicatorIdleColor = listPalette.scrollerKnob
            node.scrollIndicatorHoverColor = listPalette.scrollerKnobHovered
            node.scrollIndicatorActiveColor = listPalette.scrollerKnobActive
            node.scrollIndicatorAutoHides =
                context.verticalScrollIndicatorVisibility.usesRetainedOverlayScrollIndicator
            node.scrollIndicatorColor = node.restingScrollIndicatorColor
            node.initialScrollAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .initialOffset))
            node.scrollSizeChangeAnchor = retainedScrollAnchor(from: context.defaultScrollAnchor(for: .sizeChanges))
            node.isScrollInputEnabled = context.isScrollEnabled
            if !context.isScrollEnabled {
                node.showsScrollIndicator = false
            } else {
                node.showsScrollIndicator = context.verticalScrollIndicatorVisibility.showsRetainedScrollIndicator
            }
            if context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            // Preserve the historical eager layout for small lists (and the
            // compatibility tests inspecting it), while bounding recursive
            // layout work for genuinely long, scrollable collections.
            // `scrollToDescendant` can reveal placed-but-deferred rows, so
            // keyboard navigation no longer needs an eager `onLayout` mirror.
            if content.count > Self.layoutVirtualizationRowThreshold,
                node.scrollAxis != nil,
                let stackLayout = node.layoutMode.stackLayout
            {
                node.layoutMode = .lazyStack(stackLayout)
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
            let elementViews = normalizedProjectedViewList(rowContent(element))
            for (index, view) in elementViews.enumerated() {
                views.append(
                    view.ensuringViewIdentitySlot(index).mappingViewIdentity { content in
                        AnyView(
                            DynamicListEditMetadataView(
                                content: AnyView(
                                    content.implicitForEachScrollTarget(elementIDDescription, index: index)
                                        .tag(elementID)
                                ),
                                dynamicContentIndex: elementIndex
                            )
                        )
                    }
                    .prefixedViewIdentity([.role(.row), .keyed(RetainedViewIdentity.Key(elementID))])
                )
            }
        }
        return views
    }

    /// Minimum total height applied to selection-bound rows when no explicit
    /// `defaultMinListRowHeight` environment value is set. Keeps row metrics
    /// stable regardless of selection, hover, or focus chrome.
    /// Interleaves the style's hairline rule between adjacent rows.
    ///
    /// macOS rules *between* rows: never after the last one, and never on
    /// either side of a selected row (the selection fill is the boundary).
    /// The rule is one physical pixel at any backing scale, like an AppKit
    /// separator — a 1pt line would double to 2px at 2x.
    @MainActor
    private static func rowNodesWithSeparators(
        listChrome: RetainedListChrome,
        palette: ControlPalette,
        displayScale: Double,
        rows: [(node: ViewNode, isSelected: Bool)]
    ) -> [ViewNode] {
        guard listChrome.drawsRowSeparators, rows.count > 1 else {
            return rows.map(\.node)
        }

        let thickness = displayScale > 0 ? 1 / displayScale : 1
        var children: [ViewNode] = []
        children.reserveCapacity(rows.count * 2 - 1)
        @MainActor func isGroupedContainer(_ node: ViewNode) -> Bool {
            node.sectionHeaderChildCount > 0 || node.sectionFooterChildCount > 0
        }

        for (index, row) in rows.enumerated() {
            let previous: (node: ViewNode, isSelected: Bool)? = index > 0 ? rows[index - 1] : nil
            // macOS never rules between grouped sections — each section is
            // its own box — nor on either side of a selected row, where the
            // selection fill is the boundary.
            if let previous, !row.isSelected, !previous.isSelected,
                !isGroupedContainer(row.node), !isGroupedContainer(previous.node)
            {
                let rule = Controls.panel(
                    preferredSize: Size(width: 0, height: thickness),
                    backgroundColor: palette.separator,
                    isHitTestVisible: false
                )
                rule.layoutFillAxes = .horizontalOnly
                rule.isSeparatorRule = true
                if listChrome.separatorLeadingInset > 0 {
                    children.append(
                        Controls.panel(
                            layoutMode: .stack(
                                .horizontal(
                                    padding: EdgeInsets(
                                        top: 0,
                                        leading: listChrome.separatorLeadingInset,
                                        bottom: 0,
                                        trailing: 0
                                    ),
                                    alignment: .stretch
                                )),
                            isHitTestVisible: false,
                            children: [rule]
                        )
                    )
                } else {
                    children.append(rule)
                }
            }
            children.append(row.node)
        }
        return children
    }

    private static var defaultSelectionRowMinHeight: Double { 28 }
    private static var layoutVirtualizationRowThreshold: Int { 64 }

    /// Corner radius of the selection fill. macOS inset/sidebar selection is
    /// a small ~6pt round rect; the 10 this used to use reads as a floating
    /// chip on a 28pt row.
    private static var selectionRowCornerRadius: Double { MacOSControlMetrics.Button.regularCornerRadius }

    private static func selectableRow(
        wrapping row: ViewNode,
        tag: AnyHashable,
        selectionMode: ListSelectionMode,
        isSelected: Bool,
        isEditing: Bool,
        context: ViewBuildContext,
        runtime: RetainedViewRuntime,
        navigationState: ListKeyboardNavigationState
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
        // Border width and padding stay constant across selection states so
        // toggling selection never changes the painted row extents; the
        // unselected border is simply fully transparent.
        //
        // A selected row is an accent **wash** at `Radius.sm`, inset from the
        // list's own horizontal edges — not a full-bleed saturated band with
        // white text on it, which is the loudest object a list can contain
        // and says nothing the wash and the row's leading indicator do not.
        // An unfocused list falls back to the neutral `surface3` fill.
        let palette = context.controlPalette
        let selectionFill =
            context.environmentValues.controlActiveState == .inactive
            ? palette.unemphasizedSelectedBackground
            : palette.listSelectionBackground(tint: selectionTint)
        let rowNode = Controls.stackPanel(
            backgroundColor: isSelected ? selectionFill : nil,
            borderColor: .clear,
            borderWidth: 0,
            cornerRadius: Self.selectionRowCornerRadius,
            stackLayout: .vertical(
                spacing: 0,
                padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                alignment: .stretch
            ),
            isHitTestVisible: true,
            children: [rowContent]
        )
        rowNode.nodeTag = row.nodeTag ?? "selection:\(String(describing: tag.base))"
        rowNode.retainedViewIdentity = row.retainedViewIdentity

        // Mark both selected and unselected rows so platform accessibility
        // providers can expose a complete SelectionItem pattern.
        rowNode.accessibilityTraits.formUnion(.isSelectable)
        if isSelected {
            rowNode.accessibilityTraits.formUnion(.isSelected)
        }

        guard context.isEnabled else {
            return rowNode
        }

        rowNode.isFocusable = true
        // Arrow keys move the selection instead of scrolling the enclosing
        // panel; the runtime consults this flag before its scroll-key path.
        rowNode.interceptsVerticalArrowKeys = true
        // Hover chrome repaints through the retained runtime: `isHovered`
        // invalidates paint automatically when a hover effect is installed.
        rowNode.hoverEffect = .highlight
        rowNode.onActivate = {
            if selectionMode.activate(tag) {
                context.invalidate()
            }
        }
        rowNode.onKeyDown = { [weak runtime] event in
            guard event.modifiers.isEmpty else {
                return
            }
            let delta: Int
            switch event.key {
            case .upArrow:
                delta = -1
            case .downArrow:
                delta = 1
            default:
                return
            }

            guard let target = navigationState.moveSelection(selectionMode, delta: delta)
            else {
                return
            }

            context.invalidate()
            if let targetNode = navigationState.rowNode(for: target) {
                runtime?.requestFocus(targetNode)
            }
            navigationState.scrollRowIntoView(tag: target)
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
        let context = context.withViewIdentityType(Self.self)
        return Component { runtime in
            let columnCount = columns.count
            guard columnCount > 0 else {
                return Controls.panel(
                    frame: .zero,
                    layoutMode: .stack(.vertical(spacing: 0, padding: .zero, alignment: .stretch)),
                    children: []
                )
            }

            let style = context.tableStyle
            // A table's chrome is an *appearance* question, and it used to be
            // asked of `backgroundProminence` — a per-row selection signal
            // that is `.increased` only inside an emphasised row. A table on a
            // dark app therefore drew its light-mode header everywhere except
            // on a selected row, and the `.automatic` border stayed a single
            // near-white literal in both appearances.
            let palette = context.controlPalette

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
                headerBackground = palette.controlBackground
                rowAltBackground = palette.quinaryFill
                borderColor = palette.separator
                borderWidth = 1
                cornerRadius = 10
                rowSpacing = 0
                headerPadding = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
                rowPadding = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            case .bordered:
                headerBackground = palette.raisedSurface
                rowAltBackground = palette.quinaryFill
                borderColor = palette.controlBorder
                borderWidth = 2
                cornerRadius = 6
                rowSpacing = 0
                headerPadding = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
                rowPadding = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .automatic:
                headerBackground = palette.controlBackground
                rowAltBackground = palette.quinaryFill
                borderColor = palette.separator
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
            headerRow.retainedViewIdentity = context.withViewIdentityRole(.header).retainedViewIdentity

            // Build data rows
            let dataRows = data.enumerated().map { pair in
                let element = pair.element
                let elementID = AnyHashable(element.id)
                let rowContext = context.withViewIdentityRole(.row)
                    .withViewIdentityPrefix([.keyed(RetainedViewIdentity.Key(element.id))])
                let isSelected = self.selectionMode?.contains(elementID) == true

                let cells = columns.enumerated().map { cellPair in
                    let column = cellPair.element
                    let cellNode = self.buildDataCell(
                        column: column,
                        element: element,
                        columnIndex: cellPair.offset,
                        context: rowContext,
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
                row.retainedViewIdentity = rowContext.retainedViewIdentity

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
        let context = context.withViewIdentityRole(.columnHeader).withViewIdentityPrefix([.slot(columnIndex)])
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
        let context = context.withViewIdentityRole(.column).withViewIdentityPrefix([.slot(columnIndex)])
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
        rowNode.retainedViewIdentity = row.retainedViewIdentity
        rowNode.accessibilityTraits.formUnion(.isSelectable)
        if isSelected {
            rowNode.accessibilityTraits.formUnion(.isSelected)
        }

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
        makeViewComponent(content, context: context)
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
        // Everything below a Form builds grouped-form rows: a trailing
        // label column, a leading value column, and section headers outside
        // the boxes they name.
        let content = self.content
        return Component { runtime in
            // One column for the whole form. Every section resolves its own
            // group as it builds — it cannot see its siblings — and registers
            // the answer here; `resolve()` then widens all of them to the
            // widest, which is the single leading edge macOS settings panes
            // align on.
            let columnScope = GroupedFormColumnScope()
            let rowContext =
                context
                .withEnvironmentValue(\.isInsideGroupedForm, true)
                .withEnvironmentValue(\.groupedFormColumnScope, columnScope)
            let chrome = Self.retainedChrome(for: context.formStyle, palette: context.controlPalette)
            let rows = alignedGroupedFormRows(
                viewIdentityOccurrences(content).map {
                    $0.makeComponent(context: rowContext).makeNode(runtime: runtime)
                },
                scope: columnScope
            )
            columnScope.resolve()
            let column = Controls.stackPanel(
                backgroundColor: chrome.backgroundColor,
                backgroundGradient: chrome.backgroundGradient,
                borderColor: chrome.borderColor,
                borderGradient: chrome.borderGradient,
                borderWidth: chrome.borderWidth,
                cornerRadius: chrome.cornerRadius,
                // Card-style forms clip content to the rounded card so section
                // groups read as clean, distinct surfaces.
                clipsToBounds: chrome.cornerRadius > 0
                    && (chrome.backgroundColor != nil || chrome.borderWidth > 0),
                stackLayout: .vertical(spacing: chrome.spacing, padding: chrome.padding, alignment: .stretch),
                isHitTestVisible: false,
                children: rows
            )
            // A Form takes the width it is offered *up to its content
            // column*, and is centred in whatever is left. macOS settings
            // live in a ~600–715pt column with generous margins; a form
            // stretched edge to edge across a 1256pt window is a web page,
            // and it is what made a three-segment picker 1215pt wide.
            column.layoutFillAxes = .horizontalOnly
            column.layoutConstraints = LayoutConstraints(
                minWidth: 0,
                maxWidth: chrome.contentMaxWidth,
                minHeight: 0,
                maxHeight: .infinity
            )
            let centeredColumn = Controls.stackPanel(
                stackLayout: .vertical(spacing: 0, alignment: .center),
                isHitTestVisible: false,
                children: [column]
            )
            centeredColumn.layoutFillAxes = .horizontalOnly
            return centeredColumn
        }
    }

    private struct RetainedChrome {
        var spacing: Double
        var padding: EdgeInsets
        var backgroundColor: Color?
        var backgroundGradient: GradientType?
        var borderColor: Color
        var borderGradient: GradientType?
        var borderWidth: Double
        var cornerRadius: Double
        var contentMaxWidth: Double
    }

    private static func retainedChrome(for style: FormStyle, palette: ControlPalette) -> RetainedChrome {
        let margin = MacOSControlMetrics.Form.contentHorizontalMargin
        switch style.kind {
        case .automatic:
            return RetainedChrome(
                spacing: MacOSControlMetrics.Form.sectionSpacing,
                padding: EdgeInsets(top: 16, leading: margin, bottom: margin, trailing: margin),
                backgroundColor: nil,
                backgroundGradient: nil,
                borderColor: .clear,
                borderGradient: nil,
                borderWidth: 0,
                cornerRadius: 0,
                contentMaxWidth: MacOSControlMetrics.Form.contentMaxWidth
            )
        case .columns:
            return RetainedChrome(
                spacing: 8,
                padding: EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18),
                backgroundColor: nil,
                backgroundGradient: nil,
                borderColor: palette.separator,
                borderGradient: nil,
                borderWidth: 1,
                cornerRadius: 8,
                contentMaxWidth: MacOSControlMetrics.Form.contentMaxWidth
            )
        case .grouped:
            // The one Form style that draws a card of its own takes the same
            // panel material its section boxes do.
            return RetainedChrome(
                spacing: MacOSControlMetrics.Form.sectionSpacing,
                padding: EdgeInsets(top: 16, leading: margin, bottom: margin, trailing: margin),
                backgroundColor: palette.raisedSurface,
                backgroundGradient: palette.raisedSurfaceFill,
                borderColor: palette.raisedSurfaceHighlight,
                borderGradient: palette.raisedSurfaceRing,
                borderWidth: 1,
                cornerRadius: MacOSControlMetrics.GroupBox.cornerRadius,
                contentMaxWidth: MacOSControlMetrics.Form.contentMaxWidth
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
        let context = context.withViewIdentityType(Self.self)
        let expansionBinding = isExpanded
        // A **grouped-form** section header is a heading, not a label:
        // 15/600 at the primary rung, attached to the group under it. The
        // 11pt secondary-rung header it used to be is a System Settings
        // idiom, and an 11pt dim string floating between two boxes belongs
        // to neither of them.
        //
        // A **list** group header is the other thing, and keeps the eyebrow
        // it has always had: it names the rows under it and is not something
        // you read on the way past. One call site, two roles, which is why
        // `Typography` pins two sizes.
        let palette = context.controlPalette
        let isFormSectionHeader = context.isInsideGroupedForm && style.usesContainerChrome
        let headerColor = style.headerColor ?? (isFormSectionHeader ? palette.label : palette.secondaryLabel)
        // A grouped section box is a raised surface closed by a hairline,
        // in whichever appearance it is drawn in. These used to be dark
        // literals, so a light-mode app showed light controls on dark cards.
        let sectionBackground = style.backgroundColor ?? palette.raisedSurface
        let sectionBorder = style.borderColor ?? palette.separator
        let indicatorColor = style.indicatorColor ?? palette.scrollerKnob
        let indicatorHoverColor = style.indicatorHoverColor ?? palette.scrollerKnobHovered
        let indicatorActiveColor = style.indicatorActiveColor ?? palette.scrollerKnobActive
        // A macOS grouped form puts the section header *outside and above*
        // the box it names, and draws that box near-flat: a 10pt radius, a
        // hairline, and only an ambient contact shadow. A section that was
        // given its own style keeps it; a section outside a Form keeps the
        // list-group chrome it has always had.
        let usesGroupedFormChrome = context.isInsideGroupedForm && style.usesContainerChrome
        let sectionShadow = usesGroupedFormChrome ? palette.groupedContainerShadow : style.shadowColor
        let sectionCornerRadius =
            usesGroupedFormChrome ? MacOSControlMetrics.GroupBox.cornerRadius : style.cornerRadius
        // A grouped section rules *between* its rows, and the rule sits in
        // the middle of the gap: half the remaining rhythm above it, half
        // below, so two rows stay exactly `Form.rowSpacing` apart and the
        // hairline costs the pane no height at all.
        //
        // Subtracting the hairline is what keeps that true at every backing
        // scale. A rule is one *device* pixel (docs/MacOSDesignParity.md), so
        // a fixed half-gap would make a settings pane a few points shorter at
        // 2x than at 1x — and in a scrolling pane, a fold that moves with the
        // display is a different app at every DPI.
        let groupedFormRuleThickness = usesGroupedFormChrome ? retainedHairlineThickness(for: context) : 0
        let sectionSpacing =
            usesGroupedFormChrome
            ? max(0, MacOSControlMetrics.Form.rowSpacing - groupedFormRuleThickness) / 2
            : style.spacing
        let sectionPadding =
            usesGroupedFormChrome
            ? EdgeInsets(
                top: MacOSControlMetrics.Form.boxVerticalPadding,
                leading: MacOSControlMetrics.Form.boxHorizontalPadding,
                bottom: MacOSControlMetrics.Form.boxVerticalPadding,
                trailing: MacOSControlMetrics.Form.boxHorizontalPadding
            )
            : style.padding
        return Component { runtime in
            let headerFont =
                (style.headerFont
                ?? .system(
                    size: isFormSectionHeader
                        ? MacOSControlMetrics.Typography.formSectionHeaderSize
                        : MacOSControlMetrics.Typography.sectionHeaderSize,
                    weight: .semibold))
                .resolvedHeaderFont(for: context.headerProminence)
            let headerContext =
                context
                .withViewIdentityRole(.header)
                .withForegroundColor(headerColor)
                .withFont(headerFont)
                .withTextAlignment(.leading)
                .withLineLimit(1)
            let footerContext =
                context
                .withViewIdentityRole(.footer)
                .withForegroundColor(palette.secondaryLabel)
                .withFont(.footnote)
                .withTextAlignment(.leading)

            let headerNodes = viewIdentityOccurrences(header).map {
                let node = $0.makeComponent(context: headerContext).makeNode(runtime: runtime)
                // Section headers are headers by construction; the projection
                // maps isHeader to the UIA header control type.
                node.accessibilityTraits.formUnion(.isHeader)
                return node
            }
            let resolvedHeaderNodes: [ViewNode]
            if let expansionBinding, !headerNodes.isEmpty {
                let chevronNode = Controls.label(
                    expansionBinding.wrappedValue ? "V" : ">",
                    preferredSize: Size(width: 18, height: 24),
                    color: headerColor,
                    scale: 1.2,
                    weight: .semibold,
                    lineBreakMode: .truncateTail,
                    maximumNumberOfLines: 1
                )
                // The chevron is chrome, not content: keep it out of the
                // accessibility tree so folded header names stay clean.
                chevronNode.isAccessibilityHidden = true
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
                // An expandable header is a button (the retained builder
                // default) that is also a header; the projection's
                // first-match table keeps the button type and the provider
                // wave can still see the header trait.
                headerButton.accessibilityTraits.formUnion(.isHeader)
                resolvedHeaderNodes = [headerButton]
            } else {
                resolvedHeaderNodes = headerNodes
            }
            if let minimumHeaderHeight = context.defaultMinListHeaderHeight, minimumHeaderHeight > 0 {
                for headerNode in resolvedHeaderNodes {
                    headerNode.applyDefaultMinimumHeight(minimumHeaderHeight)
                }
            }

            let builtContentNodes =
                expansionBinding?.wrappedValue == false
                ? []
                : viewIdentityOccurrences(content).map {
                    $0.makeComponent(context: context.withViewIdentityRole(.content)).makeNode(runtime: runtime)
                }
            // This section resolves its own group first — the widest label in
            // *this* box — and hands the result to the enclosing form, which
            // widens every group to one column once all of them exist. A
            // section is a grouping, not a separate grid.
            let contentNodes =
                usesGroupedFormChrome
                ? Self.groupedFormRowsWithSeparators(
                    alignedGroupedFormRows(builtContentNodes, scope: context.groupedFormColumnScope),
                    palette: palette,
                    thickness: groupedFormRuleThickness
                )
                : builtContentNodes
            let children =
                (usesGroupedFormChrome ? [] : resolvedHeaderNodes) + contentNodes
                + viewIdentityOccurrences(footer).map {
                    $0.makeComponent(context: footerContext).makeNode(runtime: runtime)
                }
            let hidesScrollContentBackground =
                style.scrollAxis != nil
                && context.scrollContentBackgroundVisibility.hidesRetainedScrollContentBackground
            let alignmentAnchor = style.scrollAxis == nil ? nil : context.defaultScrollAnchor(for: .alignment)

            // A grouped box takes the panel material: the appearance's own
            // near-flat vertical fill and a ring that is lightest along its
            // top edge. A section that was given an explicit background
            // gradient keeps it — the material is the *default* surface, not
            // an override of one the app authored.
            let sectionFill =
                style.backgroundGradient
                ?? (usesGroupedFormChrome && style.backgroundColor == nil ? palette.raisedSurfaceFill : nil)
            let sectionRing = usesGroupedFormChrome && style.borderColor == nil ? palette.raisedSurfaceRing : nil
            let node = Controls.stackPanel(
                backgroundColor: hidesScrollContentBackground ? nil : sectionBackground,
                backgroundGradient: hidesScrollContentBackground ? nil : sectionFill,
                borderColor: sectionRing?.startColor ?? sectionBorder,
                borderGradient: sectionRing,
                borderWidth: 1,
                shadowColor: sectionShadow,
                // Tight, low shadow so stacked sections read as grouped cards
                // rather than floating panels.
                shadowOffset: Point(
                    x: 0,
                    y: usesGroupedFormChrome ? MacOSControlMetrics.GroupBox.shadowOffsetY : 8
                ),
                shadowSpread: usesGroupedFormChrome ? MacOSControlMetrics.GroupBox.shadowSpread : 4,
                cornerRadius: sectionCornerRadius,
                clipsToBounds: true,
                stackLayout: .vertical(
                    spacing: sectionSpacing,
                    padding: style.scrollAxis == nil
                        ? sectionPadding
                        : context.contentInsets(for: .scrollContent, defaultInsets: sectionPadding),
                    alignment: style.alignment.stackAlignment(layoutDirection: context.layoutDirection),
                    mainAlignment: alignmentAnchor.map { stackMainAlignment(from: $0.y) } ?? .start
                ),
                isHitTestVisible: style.isHitTestVisible,
                children: children
            )

            if let axis = style.scrollAxis {
                node.scrollAxis = axis.scrollAxis
                node.isScrollInputEnabled = context.isScrollEnabled
                node.scrollStep = style.scrollStep
                node.showsScrollIndicator =
                    context.isScrollEnabled
                    && context.scrollIndicatorVisibility(for: axis).showsRetainedScrollIndicator
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
                node.scrollIndicatorIdleColor = indicatorColor
                node.scrollIndicatorHoverColor = indicatorHoverColor
                node.scrollIndicatorActiveColor = indicatorActiveColor
                node.scrollIndicatorThickness = style.indicatorThickness
                node.scrollIndicatorAutoHides =
                    context.scrollIndicatorVisibility(for: axis).usesRetainedOverlayScrollIndicator
                node.scrollIndicatorColor = node.restingScrollIndicatorColor
            }
            if style.scrollAxis != nil, context.isScrollClipDisabled {
                node.clipsToBounds = false
            }
            node.sectionHeaderChildCount = usesGroupedFormChrome ? 0 : resolvedHeaderNodes.count
            node.sectionFooterChildCount = footer.count

            guard usesGroupedFormChrome, !resolvedHeaderNodes.isEmpty else {
                return node
            }
            return Self.groupedFormSectionNode(header: resolvedHeaderNodes, box: node)
        }
    }

    /// Interleaves a hairline rule between adjacent rows of a grouped-form
    /// section box.
    ///
    /// macOS System Settings separates *every* row inside a grouped box, the
    /// same way a `List` rules between its rows — a box whose rows are only
    /// separated where the app happened to write a `Divider` reads as an
    /// arbitrary rhythm rather than a settings pane. Apps therefore no longer
    /// need to write those rules themselves, and one that still does keeps
    /// exactly one line: a row that is already a rule suppresses the
    /// automatic one on either side of it.
    ///
    /// The rule spans the box's *content* width rather than bleeding to its
    /// edges: the section's own horizontal padding is applied by the stack to
    /// every child, and a full-bleed rule would need a negative margin the
    /// retained layout has no concept of. Recorded in docs/MacOSDesignParity.md.
    ///
    /// `thickness` comes from the same `retainedHairlineThickness` the box's
    /// row spacing was computed against, so the rule and the gap it sits in
    /// can never disagree about how tall a hairline is.
    @MainActor
    private static func groupedFormRowsWithSeparators(
        _ rows: [ViewNode],
        palette: ControlPalette,
        thickness: Double
    ) -> [ViewNode] {
        guard rows.count > 1, thickness > 0 else {
            return rows
        }

        var children: [ViewNode] = []
        children.reserveCapacity(rows.count * 2 - 1)
        for (index, row) in rows.enumerated() {
            if index > 0, !row.isSeparatorRule, !rows[index - 1].isSeparatorRule {
                let rule = Controls.panel(
                    preferredSize: Size(width: 0, height: thickness),
                    backgroundColor: palette.separator,
                    isHitTestVisible: false
                )
                rule.layoutFillAxes = .horizontalOnly
                rule.isSeparatorRule = true
                children.append(rule)
            }
            children.append(row)
        }
        return children
    }

    /// A grouped-form section: the header outside and above the box, the
    /// way macOS System Settings sets one. Out of line so the header
    /// treatment is one readable place rather than another branch inside an
    /// already long builder.
    private static func groupedFormSectionNode(header: [ViewNode], box: ViewNode) -> ViewNode {
        let headerRow = Controls.stackPanel(
            stackLayout: .horizontal(
                padding: EdgeInsets(
                    top: 0,
                    leading: MacOSControlMetrics.Form.headerLeadingInset,
                    bottom: 0,
                    trailing: 0
                ),
                alignment: .center
            ),
            isHitTestVisible: false,
            children: header
        )
        let node = Controls.stackPanel(
            stackLayout: .vertical(
                spacing: MacOSControlMetrics.Form.headerSpacing,
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: [headerRow, box]
        )
        node.layoutFillAxes = .horizontalOnly
        node.sectionHeaderChildCount = 1
        return node
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
        let context = context.withViewIdentityType(Self.self)
        let views =
            label.map { $0.prefixedViewIdentity([.role(.label)]) }
            + content.map { $0.prefixedViewIdentity([.role(.content)]) }
        return Component { runtime in
            // An `NSBox` is the same grouped container a `Form` section is:
            // the appearance's raised surface, the panel material on it, a
            // separator-tone ring lightest along its top edge, and the pinned
            // 10pt corner. The literals this used to carry were a translucent
            // dark charcoal and a near-white ring at a 12pt radius — a box
            // that could only ever be right in one appearance, and was not the
            // same box the settings pane beside it drew.
            let palette = context.controlPalette
            let node = Controls.panel(
                backgroundColor: palette.raisedSurface,
                backgroundGradient: palette.raisedSurfaceFill,
                borderColor: palette.raisedSurfaceHighlight,
                borderGradient: palette.raisedSurfaceRing,
                borderWidth: 1,
                shadowColor: palette.groupedContainerShadow,
                shadowOffset: Point(x: 0, y: MacOSControlMetrics.GroupBox.shadowOffsetY),
                shadowSpread: MacOSControlMetrics.GroupBox.shadowSpread,
                cornerRadius: MacOSControlMetrics.GroupBox.cornerRadius,
                layoutMode: .stack(.vertical(spacing: 8, padding: .all(12), alignment: .stretch)),
                isHitTestVisible: false,
                children: viewIdentityOccurrences(views).map {
                    $0.makeComponent(context: context).makeNode(runtime: runtime)
                }
            )
            // Preserve the retained container contract: an explicit frame
            // sizes the chrome, while ordinary layout keeps it content-sized.
            node.explicitFrameFillAxes = .both
            return node
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
        let context = context.withViewIdentityType(Self.self)
        let binding = isExpanded
        let fallbackState = expansionState
        let contentViews = content
        let labelComponent = composeComponent(
            from: label,
            context: context.withViewIdentityRole(.label),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        let contentComponent = composeComponent(
            from: contentViews,
            context: context.withViewIdentityRole(.content),
            fallbackLayout: .stack(.vertical(spacing: 6, alignment: .stretch)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let isOpen = binding?.wrappedValue ?? fallbackState.isExpanded
            // One glyph that turns. It used to be two glyphs that swap ("V"
            // open, ">" closed), which is a step function: the header was
            // rebuilt with the opposite character and there was nothing in
            // flight for the runtime to tick. NSOutlineView turns its triangle.
            let chevronNode = Controls.label(
                ">",
                preferredSize: Size(width: 18, height: 24),
                color: context.foregroundColor,
                scale: 1.3,
                weight: .semibold,
                lineBreakMode: .truncateTail,
                maximumNumberOfLines: 1
            )
            chevronNode.transform = Transform2D(rotation: isOpen ? Controls.disclosureOpenRotation : 0)
            chevronNode.implicitReconcileAnimation = Controls.disclosureAnimation
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
                // The body slides out from under the header and fades, the
                // reveal AppKit gives a disclosure. The reconciler seeds this
                // for us on both edges: an inserted node with a non-identity
                // transition gets `applyInsertionTransition`, and a removed one
                // becomes a transition overlay that fades out where it stood.
                insetContent.transition = RetainedTransition(
                    kind: .combined(
                        RetainedTransition(kind: .opacity),
                        RetainedTransition(kind: .offset(x: 0, y: -Controls.disclosureContentRevealOffset))
                    )
                )
                insetContent.implicitReconcileAnimation = Controls.disclosureAnimation
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
    private let idKeyPath: KeyPath<Element, ID>
    private let childrenKeyPath: KeyPath<Element, [Element]?>
    private let content: (Element) -> Content

    public init<Data: RandomAccessCollection>(
        _ data: Data,
        children: KeyPath<Data.Element, [Data.Element]?>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) where Data.Element == Element, Element: Identifiable, Element.ID == ID {
        self.items = Array(data)
        self.idKeyPath = \.id
        self.childrenKeyPath = children
        self.content = content
    }

    public init(
        _ root: Element,
        children: KeyPath<Element, [Element]?>,
        @ViewBuilder content: @escaping (Element) -> Content
    ) where Element: Identifiable, Element.ID == ID {
        self.items = [root]
        self.idKeyPath = \.id
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
        self.idKeyPath = id
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
        self.idKeyPath = id
        self.childrenKeyPath = children
        self.content = content
    }

    public var body: Never {
        fatalError("OutlineGroup has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Self.makeOutlineComponent(
            items: items,
            idKeyPath: idKeyPath,
            childrenKeyPath: childrenKeyPath,
            content: content,
            context: context,
            indentLevel: 0
        )
    }

    private static func makeOutlineComponent(
        items: [Element],
        idKeyPath: KeyPath<Element, ID>,
        childrenKeyPath: KeyPath<Element, [Element]?>,
        content: @escaping (Element) -> Content,
        context: ViewBuildContext,
        indentLevel: Int
    ) -> Component {
        var occurrences: [RetainedViewIdentity.Key: Int] = [:]
        let childComponents: [Component] = items.map { item in
            let key = RetainedViewIdentity.Key(item[keyPath: idKeyPath])
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            let rowContext = context.withViewIdentityRole(.row)
                .withViewIdentityPrefix([.keyed(key), .occurrence(occurrence)])
            let itemContent = makeViewComponent(content(item), context: rowContext.withViewIdentityRole(.content))
            let childData = item[keyPath: childrenKeyPath]

            if let childData = childData, !childData.isEmpty {
                let expansionState = OutlineExpansionState()
                let labelComponent = itemContent
                let nestedComponent = Self.makeOutlineComponent(
                    items: childData,
                    idKeyPath: idKeyPath,
                    childrenKeyPath: childrenKeyPath,
                    content: content,
                    context: rowContext,
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

                    let rowNode = Controls.stackPanel(
                        stackLayout: .vertical(spacing: 4, alignment: .stretch),
                        isHitTestVisible: false,
                        children: childrenNodes
                    )
                    rowNode.retainedViewIdentity = rowContext.retainedViewIdentity
                    return rowNode
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
        // Set when the menu dismisses so the next rebuild can return keyboard
        // focus to the menu's source button (approximating SwiftUI's
        // focus restoration to the control focused before presentation).
        var restoreFocusOnClose = false
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

        let existingKeyDown = node.onKeyDown
        node.onKeyDown = { event in
            existingKeyDown?(event)
            if event.key == .escape {
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
            // The disclosure glyph is chrome, not content: keep it out of the
            // accessibility tree so folded menu names stay clean.
            disclosureNode.isAccessibilityHidden = true
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
            // Default accessibility name from the label content; an explicit
            // accessibilityLabel modifier applies after this and wins.
            menuButton.accessibilityLabel = firstRetainedText(in: labelNode)

            if menuState.restoreFocusOnClose, !menuState.isOpen {
                menuState.restoreFocusOnClose = false
                runtime.requestFocus(menuButton)
            }

            let dismissMenu: @MainActor () -> Void = {
                guard menuState.isOpen else {
                    return
                }

                menuState.isOpen = false
                menuState.restoreFocusOnClose = true
                context.invalidate()
            }
            menuButton.onKeyDown = { event in
                guard menuState.isOpen, event.key == .escape else {
                    return
                }

                dismissMenu()
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
                    backgroundColor: context.controlPalette.elevatedSurface,
                    borderColor: context.controlPalette.elevatedSurfaceBorder,
                    borderWidth: 1,
                    shadowColor: ControlPalette.black(0.28),
                    shadowOffset: Point(x: 0, y: 10),
                    shadowSpread: 8,
                    cornerRadius: 10,
                    stackLayout: .vertical(
                        spacing: 2, padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6), alignment: .stretch
                    ),
                    // Hit-test visible so clicks on the panel's padding do not
                    // fall through to the dismissal scrim behind it.
                    isHitTestVisible: true,
                    children: itemNodes
                )
                // Full-canvas transparent scrim: sits behind the panel inside
                // the deferred overlay and dismisses on outside pointer-down.
                let scrimNode = Controls.panel(isHitTestVisible: true)
                scrimNode.nodeTag = "menu-dismiss-scrim"
                scrimNode.onPointerDown = {
                    dismissMenu()
                }
                // Deferred painting keeps the open menu above all base content
                // and gives its subtree hit-test priority over base content.
                let overlayContainer = Controls.panel(
                    layoutMode: .absolute,
                    isHitTestVisible: false,
                    children: [scrimNode, menuPanel]
                )
                overlayContainer.paintsInDeferredPhase = true
                overlayContainer.nodeTag = "menu-overlay"
                overlayContainer.accessibilityTraits.insert(.isModal)
                children.append(overlayContainer)
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

                let overlayContainer = children[1]
                let containerFrame = Rect(origin: .zero, size: bounds.size)
                if overlayContainer.frame != containerFrame {
                    overlayContainer.frame = containerFrame
                }
                guard overlayContainer.children.count > 1 else {
                    return
                }

                let scrim = overlayContainer.children[0]
                let panel = overlayContainer.children[1]
                let panelSize = panel.intrinsicContentSize()
                let canvasSize = context.canvasSize
                let rootOrigin = retainedMenuAbsoluteOrigin(of: root)

                // The scrim always covers the full canvas, no matter where the
                // menu's source button sits in the window.
                let scrimFrame = Rect(
                    x: -rootOrigin.x,
                    y: -rootOrigin.y,
                    width: canvasSize.width,
                    height: canvasSize.height
                )
                if scrim.frame != scrimFrame {
                    scrim.frame = scrimFrame
                }

                let x: Double
                switch context.layoutDirection {
                case .leftToRight:
                    x = 0
                case .rightToLeft:
                    x = max(0, buttonSize.width - panelSize.width)
                }
                let naturalOrigin = Point(
                    x: x,
                    y: min(bounds.size.height, buttonSize.height + 4)
                )
                let panelOrigin = retainedMenuClampedPanelOrigin(
                    naturalOrigin,
                    panelSize: panelSize,
                    rootOrigin: rootOrigin,
                    canvasSize: canvasSize
                )
                let panelFrame = Rect(origin: panelOrigin, size: panelSize)
                if panel.frame != panelFrame {
                    panel.frame = panelFrame
                }
            }

            return root
        }
    }
}

/// Absolute origin of `node` within the window, approximated by walking the
/// parent chain. Ancestor scroll offsets are not accounted for, matching the
/// retained popover's attachment approximation.
@MainActor
private func retainedMenuAbsoluteOrigin(of node: ViewNode) -> Point {
    var origin = Point.zero
    var current: ViewNode? = node
    while let currentNode = current {
        origin = Point(
            x: origin.x + currentNode.frame.origin.x,
            y: origin.y + currentNode.frame.origin.y
        )
        current = currentNode.parent
    }
    return origin
}

/// Clamps the menu panel's local origin so the panel never paints outside the
/// canvas, mirroring `clampedPopoverOrigin` in Core.swift.
private func retainedMenuClampedPanelOrigin(
    _ origin: Point,
    panelSize: Size,
    rootOrigin: Point,
    canvasSize: Size
) -> Point {
    Point(
        x: min(max(0, canvasSize.width - panelSize.width), max(0, rootOrigin.x + origin.x)) - rootOrigin.x,
        y: min(max(0, canvasSize.height - panelSize.height), max(0, rootOrigin.y + origin.y)) - rootOrigin.y
    )
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
                backgroundColor: Color(red: 0.156, green: 0.156, blue: 0.156, alpha: 0.72),
                borderColor: Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.10),
                borderWidth: 1,
                cornerRadius: 10,
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
                childButtonStyle: .borderless
            )
        case .compactMenu:
            return RetainedChrome(
                backgroundColor: Color(red: 0.117, green: 0.117, blue: 0.117, alpha: 0.58),
                borderColor: Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 7,
                spacing: 2,
                padding: EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4),
                childButtonStyle: .borderless
            )
        case .menu:
            return RetainedChrome(
                backgroundColor: Color(red: 0.097, green: 0.097, blue: 0.097, alpha: 0.64),
                borderColor: Color(red: 0.975, green: 0.975, blue: 0.975, alpha: 0.13),
                borderWidth: 1,
                cornerRadius: 12,
                spacing: 5,
                padding: EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7),
                childButtonStyle: .borderless
            )
        case .navigation:
            return RetainedChrome(
                backgroundColor: Color(red: 0.116, green: 0.116, blue: 0.116, alpha: 0.62),
                borderColor: tint.opacity(0.24),
                borderWidth: 1,
                cornerRadius: 9,
                spacing: 3,
                padding: EdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5),
                childButtonStyle: .borderless
            )
        case .palette:
            return RetainedChrome(
                backgroundColor: Color(red: 0.107, green: 0.107, blue: 0.107, alpha: 0.50),
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
        // In a grouped form the title is the row's *label*, not the field's
        // placeholder: macOS writes "Display Name" in the label column and
        // leaves the field itself empty unless a prompt was given. Outside a
        // form the title stands in as the placeholder, as it always has.
        let isFormRow = context.isInsideGroupedForm && !context.labelsHidden && label == nil && !title.isEmpty
        let fieldComponent = textInputComponent(
            title: label == nil ? (isFormRow ? prompt : (prompt ?? title)) : prompt,
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
        guard isFormRow else {
            return fieldComponent
        }

        let title = self.title
        let labelComponent = composeComponent(
            from: [AnyView(Text(title).multilineTextAlignment(.trailing).lineLimit(1))],
            context: context.withTextAlignment(.trailing).withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        return Component { runtime in
            let fieldNode = fieldComponent.makeNode(runtime: runtime)
            let labelNode = labelComponent.makeNode(runtime: runtime)
            if fieldNode.accessibilityLabel == nil {
                fieldNode.accessibilityLabel = title
            }
            // The well spans the value column, the way an NSTextField in a
            // form does.
            fieldNode.layoutFillAxes = .horizontalOnly
            return groupedFormRowNode(label: labelNode, content: fieldNode, isHitTestVisible: true)
        }
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
        // Same rule as `TextField`: in a grouped form the title is the row's
        // *label*, not the well's placeholder. Without this branch a settings
        // pane rendered "User [admin]" above a nameless password well — the
        // one row in the pane with an empty label column.
        let isFormRow =
            context.isInsideGroupedForm && !context.labelsHidden && label == nil && !title.isEmpty
        let fieldComponent = textInputComponent(
            title: label == nil ? (isFormRow ? prompt : (prompt ?? title)) : prompt,
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
        guard isFormRow else {
            return fieldComponent
        }

        let title = self.title
        let labelComponent = composeComponent(
            from: [AnyView(Text(title).multilineTextAlignment(.trailing).lineLimit(1))],
            context: context.withTextAlignment(.trailing).withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )
        return Component { runtime in
            let fieldNode = fieldComponent.makeNode(runtime: runtime)
            let labelNode = labelComponent.makeNode(runtime: runtime)
            if fieldNode.accessibilityLabel == nil {
                fieldNode.accessibilityLabel = title
            }
            // The well spans the value column, the way an NSSecureTextField
            // in a form does.
            fieldNode.layoutFillAxes = .horizontalOnly
            return groupedFormRowNode(label: labelNode, content: fieldNode, isHitTestVisible: true)
        }
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
/// Clipboard interface used by `TextField`, `SecureField`, and `TextEditor`
/// for Ctrl+C/X/V editing commands. Route tests through a fake by assigning
/// `TextInputClipboardProvider.current`.
@MainActor
public protocol TextInputClipboard: AnyObject {
    func copyString(_ text: String)
    func pasteString() -> String?
}
@MainActor
private final class SystemTextInputClipboard: TextInputClipboard {
    func copyString(_ text: String) {
        ClipboardManager.copyString(text)
    }

    func pasteString() -> String? {
        ClipboardManager.pasteString()
    }
}
/// Process-wide clipboard provider for retained text inputs. Production uses
/// the Win32 Unicode clipboard; tests swap in a fake implementation. An
/// `.environment(\.textInputClipboard, ...)` override takes precedence over
/// this provider for views beneath the modifier.
@MainActor
public enum TextInputClipboardProvider {
    public static var current: any TextInputClipboard = SystemTextInputClipboard()
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
    // A search field is a recessed text field wherever it is placed, and a
    // recessed field is an appearance role. These were dark literals, so a
    // light-mode toolbar carried a black search field.
    let palette = context.controlPalette
    if placement == .toolbar {
        return RetainedSearchChrome(
            nodeTag: "search-field-toolbar",
            preferredSize: Size(width: 240, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: palette.fieldSurface,
            // A resting search field is not focused, so it is closed by the
            // field ring like every other field. The accent belonged to the
            // focus ring and drew a permanent tinted outline in the toolbar.
            borderColor: palette.controlBorder,
            borderWidth: 1,
            cornerRadius: MacOSControlMetrics.Radius.sm
        )
    }

    if placement == .sidebar {
        return RetainedSearchChrome(
            nodeTag: "search-field-sidebar",
            preferredSize: Size(width: 210, height: context.controlSize.singleLineTextInputSize.height),
            backgroundColor: palette.fieldSurface,
            borderColor: palette.controlBorder,
            borderWidth: 1,
            cornerRadius: MacOSControlMetrics.Radius.sm
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
            backgroundColor: palette.fieldSurface,
            borderColor: palette.controlBorder,
            borderWidth: 1,
            cornerRadius: MacOSControlMetrics.Radius.sm
        )
    }

    return nil
}
extension ControlSize {
    /// Every shipped control height is `macOS reference + this`.
    ///
    /// macOS is designed for a trackpad; Windows is a mouse-and-touch
    /// platform whose UX guidance asks for larger pointer targets. Rather
    /// than let each control drift on its own — which is how the text
    /// field reached 36pt against a 21pt reference and the pop-up button
    /// 36 against 22 — the divergence is one named constant applied to the
    /// reference constants. `MacOSControlMetricsWiringTests` asserts the
    /// shipped sizes equal reference + delta, so a new divergence cannot
    /// be introduced without changing this number and its doc row.
    static var windowsPointerPadding: Double { 6 }

    /// Scale applied to the pointer padding per control size, so a `.mini`
    /// control is not padded as much as an `.extraLarge` one.
    var pointerPaddingScale: Double {
        switch self {
        case .mini:
            return 0.5
        case .small:
            return 0.75
        case .regular:
            return 1
        case .large:
            return 1.25
        case .extraLarge:
            return 1.5
        }
    }

    /// `macOS reference height + the Windows pointer delta`, rounded to a
    /// whole point.
    func ergonomicHeight(reference: Double) -> Double {
        (reference + ControlSize.windowsPointerPadding * pointerPaddingScale).rounded()
    }

    /// Reference height for a size variant, interpolated from the two
    /// heights macOS publishes (regular and large).
    func referenceHeight(regular: Double, large: Double) -> Double {
        switch self {
        case .mini:
            return (regular - 4).rounded()
        case .small:
            return (regular - 2).rounded()
        case .regular:
            return regular
        case .large:
            return large
        case .extraLarge:
            return (large + (large - regular)).rounded()
        }
    }

    var singleLineTextInputSize: Size {
        let height = ergonomicHeight(
            reference: referenceHeight(
                regular: MacOSControlMetrics.TextField.regularHeight,
                large: MacOSControlMetrics.TextField.largeHeight
            )
        )
        switch self {
        case .mini:
            return Size(width: 180, height: height)
        case .small:
            return Size(width: 200, height: height)
        case .regular:
            return Size(width: 220, height: height)
        case .large:
            return Size(width: 260, height: height)
        case .extraLarge:
            return Size(width: 300, height: height)
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

    /// The switch is the one control sized outside the "macOS reference +
    /// pointer padding" rule, and `MacOSControlMetrics.Toggle` says so: a
    /// padded 38×22 comes out at 52×32, which is an iOS switch and the
    /// largest object in a settings pane. The reference size ships as-is.
    fileprivate var togglePreferredSize: Size {
        let regular = MacOSControlMetrics.Toggle.regularSize
        let large = MacOSControlMetrics.Toggle.largeSize
        switch self {
        case .mini:
            return Size(width: regular.width - 6, height: regular.height - 4)
        case .small:
            return Size(width: regular.width - 3, height: regular.height - 2)
        case .regular:
            return regular
        case .large:
            return large
        case .extraLarge:
            return Size(
                width: large.width + (large.width - regular.width),
                height: large.height + (large.height - regular.height))
        }
    }

    var pickerMenuPreferredSize: Size {
        let height = ergonomicHeight(
            reference: referenceHeight(
                regular: MacOSControlMetrics.PopUpButton.regularHeight,
                large: MacOSControlMetrics.PopUpButton.largeHeight
            )
        )
        switch self {
        case .mini:
            return Size(width: 160, height: height)
        case .small:
            return Size(width: 180, height: height)
        case .regular:
            return Size(width: 200, height: height)
        case .large:
            return Size(width: 232, height: height)
        case .extraLarge:
            return Size(width: 264, height: height)
        }
    }

    /// One half of the vertical NSStepper bezel: `Stepper.buttonSize`
    /// (19x11) plus the pointer delta on the height only — a stepper half
    /// stays narrow, it is the stack of two that has to stay hittable.
    var stepperButtonPreferredSize: Size {
        let reference = MacOSControlMetrics.Stepper.buttonSize
        let width = (reference.width + ControlSize.windowsPointerPadding * pointerPaddingScale).rounded()
        let height = (reference.height + ControlSize.windowsPointerPadding * 0.5 * pointerPaddingScale).rounded()
        return Size(width: width, height: height)
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

    /// A progress bar is not a pointer target, so it takes the macOS
    /// thickness (`ProgressBar.regularHeight`) with no ergonomic delta.
    var progressPreferredSize: Size {
        let reference = MacOSControlMetrics.ProgressBar.regularHeight
        switch self {
        case .mini:
            return Size(width: 160, height: reference - 2)
        case .small:
            return Size(width: 180, height: reference - 1)
        case .regular:
            return Size(width: 200, height: reference)
        case .large:
            return Size(width: 240, height: reference + 2)
        case .extraLarge:
            return Size(width: 280, height: reference + 4)
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

    /// NSColorWell — `MacOSControlMetrics.ColorWell.regularSize` (34x22) at
    /// regular size. A colour well is not a pointer *target* the way a push
    /// button is (it is as wide as the swatch it shows), so it takes the
    /// macOS reference exactly, with no ergonomic delta.
    fileprivate var colorSwatchPreferredSize: Size {
        switch self {
        case .mini:
            return Size(width: 28, height: 18)
        case .small:
            return Size(width: 30, height: 20)
        case .regular:
            return MacOSControlMetrics.ColorWell.regularSize
        case .large:
            return Size(width: 40, height: 34)
        case .extraLarge:
            return Size(width: 46, height: 40)
        }
    }
}
/// One build's editing configuration, rebound to the retained node on adoption.
/// In-flight callbacks resolve `current` after calling application code, so a
/// synchronous rebuild can replace bindings and a removal can end the operation.
@MainActor
private final class TextInputInteractionController: TextInputAccessibilityValueReplacing, DocumentTextUndoClient {
    struct SelectionUpdate {
        var anchor: Int
        var extent: Int
        var preparation: TextEditorSelectionPreparation? = nil
        var affinity: RetainedTextSelectionAffinity? = nil
        var pointerAnchor: Int? = nil
        var preferredVisualX: Double? = nil
        var resetsPreferredVisualX = false
        var documentValidation: (@MainActor () -> Bool)? = nil
    }

    private(set) weak var node: ViewNode?
    private(set) var isAttached = false
    private weak var constructionNode: ViewNode?
    private var constructionNodeWasAttached = false
    let characterCount: Int
    let authoredCaret: Int
    let authoredSelection: RetainedTextSelection?
    let hasSelectionBinding: Bool
    let isSecure: Bool
    let allowsNewlines: Bool
    let isEnabled: Bool
    weak var undoRuntime: RetainedViewRuntime?
    private weak var configuredUndoManager: UndoManager?
    private let accessibilityValueBinding: Binding<String>
    private var accessibilityValueOwner = TextInputAccessibilityValueOwner()
    var undoSession: TextInputUndoSession?
    let documentSource: DocumentBindingSource?
    let documentProjection: [AnyKeyPath]?
    var documentEndpoint: DocumentTextSelectionEndpoint?
    var isComposing = false
    var pointerDragAnchor = 0
    var isSelectingWithPointer = false
    var readText: (() -> String)?
    var readSelection: (() -> TextSelection?)?
    var observedDocumentSelection: TextSelection?
    var applySelection: ((SelectionUpdate) -> Bool)?
    var refreshChrome: (() -> Void)?
    var prepareFieldChromeForAdoption: (@MainActor (ViewNode, TextInputEditingChromeState.EditingState) -> Void)?
    var textPosition: ((Point) -> RetainedTextCaretPosition?)?
    var invalidate: (() -> Void)?
    var writeUndoText: ((String, TextInputUndoSelection) -> Void)?
    var restoreUndoSelection: ((TextInputUndoSelection) -> Void)?
    var restoreDocumentSelectionBody: ((DocumentTextSelectionRestoration) -> Void)?
    var editorLayoutState: TextEditorLayoutState?
    var preferredVisualX: Double?
    var visualCaretAffinity: RetainedTextSelectionAffinity = .downstream
    private var editorRevealQueued = false

    init(
        node: ViewNode, characterCount: Int, hasSelectionBinding: Bool,
        isSecure: Bool, allowsNewlines: Bool, isEnabled: Bool,
        runtime: RetainedViewRuntime, undoManager: UndoManager?, text: Binding<String>,
        documentSource: DocumentBindingSource?, documentProjection: [AnyKeyPath]?
    ) {
        self.node = node
        constructionNode = node
        self.characterCount = characterCount
        authoredCaret = node.textInputCaretOffset
        authoredSelection = node.textInputSelection
        self.hasSelectionBinding = hasSelectionBinding
        self.isSecure = isSecure
        self.allowsNewlines = allowsNewlines
        self.isEnabled = isEnabled
        undoRuntime = runtime
        configuredUndoManager = undoManager
        accessibilityValueBinding = text
        self.documentSource = documentSource
        self.documentProjection = documentProjection
        if allowsNewlines {
            editorLayoutState = TextEditorLayoutState()
            visualCaretAffinity = node.textInputSelection?.affinity ?? node.textSelectionAffinity
        }
    }

    var current: TextInputInteractionController? {
        guard let node, let current = node.textInputController as? TextInputInteractionController,
            current.node === node
        else { return nil }
        return current
    }

    var hasCurrentAccessibilityValueOwnership: Bool {
        current === self && isAttached && accessibilityValueOwner.isValid
    }

    func replaceValueForAccessibility(
        _ value: String, validation: TextInputAccessibilityValueValidation
    ) -> TextInputAccessibilityValueResult {
        guard current === self, isAttached, isEnabled, !isSecure, !isComposing,
            let node, node.textInputMarkedText == nil, let runtime = undoRuntime,
            runtime.focusedNode === node
        else { return .refused }
        let owner = accessibilityValueOwner
        guard let attempt = owner.beginAttempt() else { return .refused }
        defer { owner.endAttempt(attempt) }
        let session = undoSession
        let manager = configuredUndoManager
        let source = documentSource
        let endpoint = documentEndpoint
        let endpointGeneration = endpoint?.generation
        let sourceRevision = source?.owner?.documentMutationRevision
        let previousBoundSelection = observedDocumentSelection

        // This proof never invokes a replacement controller's application
        // closures. A custom Binding still uses the documented retained .id
        // boundary; equal-text rebinding is not a discoverable document switch.
        @MainActor func retainedController() -> TextInputInteractionController? {
            guard owner.isCurrent(attempt), let current = self.current,
                current.accessibilityValueOwner === owner, current.node === node,
                current.isAttached, current.isEnabled, !current.isSecure, !current.isComposing,
                current.allowsNewlines == allowsNewlines, current.undoRuntime === runtime,
                node.textInputMarkedText == nil, runtime.focusedNode === node
            else { return nil }
            if let source {
                guard current.sharesDocumentLocation(with: self), source.belongs(to: runtime),
                    current.documentEndpoint === endpoint, endpoint?.isValid == true,
                    endpoint?.generation == endpointGeneration
                else { return nil }
            } else {
                guard current.documentSource == nil, current.configuredUndoManager === manager,
                    current.undoSession === session, session?.isValid != false
                else { return nil }
            }
            return current
        }
        @MainActor func originalMayDispatch() -> Bool {
            guard retainedController() === self, validation.mayDispatch() else { return false }
            return retainedController() === self
        }
        guard originalMayDispatch() else { return .refused }
        let originalText = accessibilityValueBinding.wrappedValue
        guard originalMayDispatch() else { return .refused }
        var beforeSelection = TextInputUndoSelection(node: node, text: originalText)
        if allowsNewlines { beforeSelection.affinity = visualCaretAffinity }
        let requiresMutation =
            session != nil && manager?.isUndoRegistrationEnabled == true
            && manager?.isUndoing == false && manager?.isRedoing == false && originalText != value
        let mutation = session?.beginEdit(before: originalText, expected: value, selection: beforeSelection)
        let generation = session?.generation
        let ticket = source?.beginEdit(
            before: originalText, proposed: value, selection: beforeSelection, endpoint: endpoint)
        defer {
            session?.cancelEdit(mutation)
            ticket?.cancel()
        }
        guard !requiresMutation || mutation != nil else { return .refused }
        guard source == nil || ticket != nil else { return .refused }
        @MainActor func historyPermitsDispatch() -> Bool {
            guard session?.generation == generation, session?.isValid != false else { return false }
            if let mutation, session?.isCurrent(mutation) != true { return false }
            return ticket?.permitsWrite != false
        }
        @MainActor func mayWrite() -> Bool {
            guard historyPermitsDispatch(), originalMayDispatch() else { return false }
            return historyPermitsDispatch()
        }
        guard mayWrite() else { return .refused }
        // History pruning may release arbitrary payloads. Check the original
        // binding again before staging or submitting the one whole-text write.
        let currentText = accessibilityValueBinding.wrappedValue
        guard mayWrite(), currentText.utf8.elementsEqual(originalText.utf8) else { return .refused }
        let previousPreferredX = preferredVisualX
        node.textInputCaretOffset = value.count
        node.textInputSelection = nil
        preferredVisualX = nil
        visualCaretAffinity = .downstream
        owner.stageSelection(for: attempt)
        // Generated projections consult this predicate around their own
        // getter/setter work. It lives only for this synchronous submission.
        accessibilityValueBinding.limitingWrites { mayWrite() }.write(value, mutation: ticket)

        @MainActor func historyPermitsObservation() -> Bool {
            guard session?.isValid != false else { return false }
            if session?.generation != generation {
                // With registration disabled there was no pending Mutation.
                // A compatible adoption observes the accepted text and clears
                // its old checkpoint once. Ordinary editing entry points
                // supersede this attempt, so they cannot use this allowance.
                guard mutation == nil, let generation,
                    session?.generation == generation &+ 1, retainedController() !== self
                else { return false }
            }
            if let mutation, session?.isCurrent(mutation) != true { return false }
            if let ticket {
                if ticket.receipt != nil { return ticket.permitsCompletion }
                return source?.isLive == true && source?.owner?.documentMutationRevision == sourceRevision
            }
            return true
        }
        @MainActor func mayObserveOriginalValue() -> Bool {
            guard retainedController() != nil, historyPermitsObservation(),
                validation.isRetainedTargetCurrent()
            else { return false }
            return retainedController() != nil && historyPermitsObservation()
        }
        guard mayObserveOriginalValue() else { return .interrupted }
        // Only the originally selected getter can report setter acceptance.
        // A replacement controller's cached or freshly read text is no proof.
        let actualText = accessibilityValueBinding.wrappedValue
        guard mayObserveOriginalValue(), let latest = retainedController() else { return .interrupted }
        let acceptedValue = actualText.utf8.elementsEqual(value.utf8)
        var authoredSelectionChanged = false
        if latest === self, hasSelectionBinding {
            // A custom setter can author selection without rebuilding. Only
            // this original getter may observe that override before history
            // captures it; a replacement controller's getter is never called.
            let boundSelection = readSelection?()
            guard mayObserveOriginalValue(), retainedController() === self else { return .interrupted }
            let verifiedText = accessibilityValueBinding.wrappedValue
            guard mayObserveOriginalValue(), retainedController() === self,
                verifiedText.utf8.elementsEqual(actualText.utf8)
            else { return .interrupted }
            if boundSelection != previousBoundSelection {
                authoredSelectionChanged = true
                node.textInputCaretOffset = boundSelection?.caretOffset(in: actualText) ?? actualText.count
                node.textInputSelection = boundSelection?.retainedSelection(in: actualText)
                preferredVisualX = nil
                visualCaretAffinity = node.textInputSelection?.affinity ?? .downstream
            }
        }
        if !acceptedValue, !authoredSelectionChanged,
            actualText.utf8.elementsEqual(originalText.utf8),
            latest.observedDocumentSelection == previousBoundSelection,
            latest.hasSelectionBinding == hasSelectionBinding,
            node.textInputCaretOffset == (latest === self ? value.count : min(value.count, actualText.count)),
            node.textInputSelection == nil, latest.preferredVisualX == nil, latest.visualCaretAffinity == .downstream
        {
            // Restore only our still-owned internal staging, never an authored
            // binding selection. A compatible adoption may have clamped the
            // staged caret, but has not acquired a different attempt owner.
            node.textInputCaretOffset = beforeSelection.caret
            node.textInputSelection = beforeSelection.selection
            latest.preferredVisualX = previousPreferredX
            latest.visualCaretAffinity = beforeSelection.affinity
        }
        var afterSelection = TextInputUndoSelection(node: node, text: actualText)
        if latest.allowsNewlines { afterSelection.affinity = latest.visualCaretAffinity }
        let completionRevision = source?.owner?.documentMutationRevision
        let completionGeneration = session?.generation
        let hasDocumentReceipt = source == nil || ticket?.receipt != nil
        if let ticket {
            if ticket.permitsCompletion { ticket.finish(text: actualText, selection: afterSelection) }
        } else {
            session?.finishEdit(mutation, text: actualText, selection: afterSelection)
        }
        @MainActor func finishGenerationMatches() -> Bool {
            if session?.generation == completionGeneration { return true }
            guard let completionGeneration, session?.generation == completionGeneration &+ 1 else {
                return false
            }
            // A nonrecording completion clears a changed checkpoint. A
            // recording completion can also decline registration after
            // application code disables it. Neither is a newer edit:
            // every ordinary replacement/replay supersedes this owner.
            return mutation == nil || actualText != value || manager?.isUndoRegistrationEnabled == false
        }
        guard finishGenerationMatches() else { return .interrupted }
        // The allowance above applies only to the finish we just performed,
        // never a further reset caused by the final application invalidation.
        let finishedGeneration = session?.generation
        @MainActor func completionIsCurrent() -> Bool {
            guard retainedController() != nil, session?.isValid != false,
                session?.generation == finishedGeneration,
                source?.owner?.documentMutationRevision == completionRevision,
                validation.isRetainedTargetCurrent()
            else { return false }
            return retainedController() != nil && session?.generation == finishedGeneration
                && source?.owner?.documentMutationRevision == completionRevision
        }
        guard completionIsCurrent(), let completed = retainedController() else { return .interrupted }
        if completed === self {
            // Publish the observed value before the final application callback.
            // A compatible rebuild already owns its incoming metadata.
            node.accessibilityValue = actualText.isEmpty ? nil : actualText
        }
        runtime.invalidateTextInputLayout(for: node, controller: completed)
        // Plain custom Bindings need the original build's invalidation. A
        // synchronous setter rebuild has already done that work. This is the
        // final application callback; only pure availability checks follow.
        if completed === self, completionIsCurrent(), retainedController() === self { invalidate?() }
        return TextInputAccessibilityValueResult(
            didDispatch: true,
            accepted: acceptedValue && hasDocumentReceipt && completionIsCurrent())
    }

    func attach(to node: ViewNode) {
        if node === constructionNode { constructionNodeWasAttached = true }
        self.node = node
        isAttached = true
    }

    func detach(from node: ViewNode) {
        if self.node === node {
            accessibilityValueOwner.invalidate()
            undoSession?.invalidate()
            invalidateDocumentEndpoint()
            editorRevealQueued = false
            self.node = nil
            isAttached = false
        }
    }

    func revokeOwnership(from node: ViewNode) {
        // Reconciliation also moves fresh nodes out of their unattached
        // construction parents. Only a live attachment owns history to revoke;
        // attaching a previously retired controller never revives its session.
        if isAttached, self.node === node {
            accessibilityValueOwner.invalidate()
            undoSession?.markInvalid()
            invalidateDocumentEndpoint()
        }
    }

    func willDetach(from node: ViewNode) {
        if self.node === node {
            accessibilityValueOwner.invalidate()
            undoSession?.invalidate()
            invalidateDocumentEndpoint()
        }
    }

    func invalidateDocumentEndpoint() {
        if documentEndpoint?.client === self { documentEndpoint?.invalidate() }
    }

    func sharesDocumentLocation(with other: TextInputInteractionController) -> Bool {
        guard let documentSource, documentSource === other.documentSource else { return false }
        return self === other || (documentProjection != nil && documentProjection == other.documentProjection)
    }

    var documentSelectionIsCurrent: Bool { current === self && isAttached && isEnabled && !isSecure }
    var documentSelectionIsComposing: Bool { isComposing || node?.textInputMarkedText != nil }
    var documentHasSelectionBinding: Bool { hasSelectionBinding }
    var documentBoundSelection: TextSelection? { observedDocumentSelection }

    func restoreDocumentSelection(
        _ selection: TextInputUndoSelection, expectedText: String, expectedBoundSelection: TextSelection?,
        validate: @escaping @MainActor () -> Bool
    ) {
        restoreDocumentSelectionBody?(
            DocumentTextSelectionRestoration(
                selection: selection, expectedText: expectedText,
                expectedBoundSelection: expectedBoundSelection, validate: validate))
    }

    var undoText: String? { current === self && isAttached ? readText?() : nil }

    var undoSelection: TextInputUndoSelection? {
        guard let node, let text = undoText else { return nil }
        var result = TextInputUndoSelection(node: node, text: text)
        if allowsNewlines { result.affinity = visualCaretAffinity }
        return result
    }

    var permitsUndoReplay: Bool {
        guard current === self, isAttached, isEnabled, !isSecure, !isComposing,
            writeUndoText != nil, let node, let undoRuntime
        else { return false }
        if let documentSource, !documentSource.belongs(to: undoRuntime) { return false }
        let allowed = undoRuntime.permitsTextInputReplay(on: node)
        return allowed && current === self && isAttached && !isComposing
    }

    func refreshUndoConfiguration() { invalidate?() }
    func invalidateUndoDisplay() { current?.invalidate?() }
    func applyUndoText(_ text: String, selection: TextInputUndoSelection) { writeUndoText?(text, selection) }

    func requestEditorCaretReveal() {
        guard isEnabled, let state = editorLayoutState else { return }
        state.needsCaretReveal = true
        state.revealDeferrals = 0
        queueEditorCaretReveal()
    }

    func queueEditorCaretReveal() {
        guard !editorRevealQueued, current === self, isAttached, isEnabled,
            let node, node.isFocused, let runtime = undoRuntime,
            let state = editorLayoutState, state.needsCaretReveal, state.revealDeferrals < 2
        else { return }
        editorRevealQueued = true
        runtime.scheduleAfterLayout(key: "text-editor-caret-\(ObjectIdentifier(node))") { [weak self, weak runtime] in
            guard let self, let runtime else { return }
            self.editorRevealQueued = false
            guard self.current === self, self.isAttached, self.isEnabled,
                let node = self.node, node.isFocused,
                let state = self.editorLayoutState, state.needsCaretReveal,
                let caretRect = state.caretRect,
                let viewport = textEditorViewport(in: node)
            else { return }
            if runtime.revealTextInputRect(caretRect, in: viewport, ownedBy: node, controller: self) {
                state.needsCaretReveal = false
                state.revealDeferrals = 0
            } else {
                // A preceding after-layout callback may have changed the
                // editor. One further settled pass can resolve that change;
                // a permanently invalid owner never spins the frame loop.
                state.revealDeferrals += 1
                self.queueEditorCaretReveal()
            }
        }
    }

    private func transferableUndoSession(from previous: TextInputInteractionController?) -> TextInputUndoSession? {
        guard documentSource == nil, previous?.documentSource == nil,
            !isSecure, readText != nil, let manager = configuredUndoManager,
            let old = previous?.undoSession, old.isValid, old.manager === manager,
            previous?.isSecure == isSecure, previous?.allowsNewlines == allowsNewlines
        else { return nil }
        return old
    }

    private func canTransferAccessibilityValueOwner(from previous: TextInputInteractionController) -> Bool {
        guard previous.accessibilityValueOwner.isValid, isEnabled, previous.isEnabled,
            !isSecure, !previous.isSecure, allowsNewlines == previous.allowsNewlines
        else { return false }
        if documentSource != nil || previous.documentSource != nil {
            return sharesDocumentLocation(with: previous)
        }
        return configuredUndoManager === previous.configuredUndoManager
    }

    func prepareForReconciliation(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        guard let previous = previous as? TextInputInteractionController, previous.node === node else { return }
        if !canTransferAccessibilityValueOwner(from: previous) { previous.accessibilityValueOwner.invalidate() }
        if let documentSource, !isSecure, previous.isSecure == isSecure, previous.allowsNewlines == allowsNewlines,
            previous.documentEndpoint?.matches(source: documentSource, projection: documentProjection) == true
        {
            return
        }
        if transferableUndoSession(from: previous) == nil {
            // Nil history does not end a compatible value-replacement attempt.
            // History still retires before any outgoing application callback.
            if previous.isAttached {
                previous.undoSession?.markInvalid()
                previous.invalidateDocumentEndpoint()
            }
        }
    }

    func configureUndoSession(from previous: TextInputInteractionController? = nil) {
        if let documentSource {
            // A retained provenance marker stays authoritative even after its
            // weak owner expires or supplies no manager. Never fall back to a
            // second text history for the same document location.
            previous?.undoSession?.invalidate()
            undoSession = nil
            if isSecure {
                previous?.invalidateDocumentEndpoint()
                invalidateDocumentEndpoint()
                documentEndpoint = nil
            } else {
                let previousEndpoint = previous?.documentEndpoint ?? documentEndpoint
                if documentEndpoint !== previousEndpoint { invalidateDocumentEndpoint() }
                documentEndpoint = documentSource.endpoint(
                    for: self, projection: documentProjection, previous: previousEndpoint)
            }
            return
        }
        previous?.invalidateDocumentEndpoint()
        if !isSecure, let manager = configuredUndoManager, let text = readText?() {
            if let old = transferableUndoSession(from: previous) {
                undoSession = old
            } else {
                previous?.undoSession?.invalidate()
                undoSession = TextInputUndoSession(manager: manager, text: text)
            }
            undoSession?.adopt(self, text: text)
        } else {
            previous?.undoSession?.invalidate()
            undoSession = nil
        }
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        self.node = node
        let previous = previous as? TextInputInteractionController
        if let previous, canTransferAccessibilityValueOwner(from: previous) {
            accessibilityValueOwner = previous.accessibilityValueOwner
        }
        // The retained node's controller setter already attached this value
        // when it belongs to a runtime. A slot without a previous controller
        // must retain that attachment even when its child list is unchanged.
        let preservesDocumentLocation =
            previous.map {
                (documentSource == nil && $0.documentSource == nil) || sharesDocumentLocation(with: $0)
            } ?? false
        let preservesEditing =
            previous?.isSecure == isSecure && previous?.allowsNewlines == allowsNewlines
            && preservesDocumentLocation
        configureUndoSession(from: previous)
        if preservesEditing {
            isComposing = previous?.isComposing ?? false
            pointerDragAnchor = min(max(0, previous?.pointerDragAnchor ?? 0), characterCount)
            isSelectingWithPointer = previous?.isSelectingWithPointer ?? false
            if let previousState = previous?.editorLayoutState, let state = editorLayoutState {
                state.key = previousState.key
                state.layout = previousState.layout
                state.viewportWidth = previousState.viewportWidth
                state.viewportHeight = previousState.viewportHeight
                state.geometryGeneration = previousState.geometryGeneration
                state.revealSignature = previousState.revealSignature
                state.needsCaretReveal = previousState.needsCaretReveal
                preferredVisualX = previous?.preferredVisualX
                visualCaretAffinity = previous?.visualCaretAffinity ?? .downstream
            }
        } else {
            node.textInputMarkedText = nil
        }

        let preservesAccessibilitySelection =
            accessibilityValueOwner.hasStagedSelection
            && previous?.accessibilityValueOwner === accessibilityValueOwner
            && previous?.hasSelectionBinding == hasSelectionBinding
            && previous?.observedDocumentSelection == observedDocumentSelection
        if preservesEditing,
            !hasSelectionBinding || authoredSelection == node.textInputSelection || preservesAccessibilitySelection
        {
            node.textInputCaretOffset = min(max(0, node.textInputCaretOffset), characterCount)
            node.textInputSelection = node.textInputSelection.map { selection in
                func clamp(_ offset: Int) -> Int { min(max(0, offset), characterCount) }
                var result = selection
                switch selection.indices {
                case .insertionPoint(let offset):
                    result.indices = .insertionPoint(clamp(offset))
                case .range(let range):
                    result.indices = .range(clamp(range.lowerBound)..<clamp(range.upperBound))
                case .ranges(let ranges):
                    result.indices = .ranges(ranges.map { clamp($0.lowerBound)..<clamp($0.upperBound) })
                }
                return result
            }
        } else {
            node.textInputCaretOffset = authoredCaret
            node.textInputSelection = authoredSelection
            preferredVisualX = nil
            visualCaretAffinity = authoredSelection?.affinity ?? .downstream
        }

        // Complete this edit's predictable Field chrome on the incoming
        // construction tree. ComponentHost adopts those children after this
        // method returns; refreshing live children here would be overwritten.
        // The constructor's cached text/style need no replacement getter.
        if let previous, previous.accessibilityValueOwner === accessibilityValueOwner,
            accessibilityValueOwner.isValid, accessibilityValueOwner.hasStagedSelection,
            self.node === node, current === self, isAttached, !isSecure, !allowsNewlines,
            let constructionNode, constructionNode !== node, !constructionNodeWasAttached,
            constructionNode.textInputController === self
        {
            prepareFieldChromeForAdoption?(
                constructionNode,
                TextInputEditingChromeState.EditingState(
                    caret: node.textInputCaretOffset, selection: node.textInputSelection,
                    isFocused: node.isFocused,
                    markedText: node.textInputMarkedText.flatMap { $0.isEmpty ? nil : $0 }))
        }
    }

    func revokeAccessibilityValueOwnership() { accessibilityValueOwner.invalidate() }
    func supersedeAccessibilityValueAttempt() { accessibilityValueOwner.supersedeAttempt() }
}

/// First revoke every closing session without releasing history payloads.
/// The host can then revoke its other owners before purging history, and still
/// deliver normal focus-exit callbacks before detaching the controllers.
@MainActor
func prepareTextInputUndoForWindowClose(in runtime: RetainedViewRuntime) -> (
    purgeHistory: @MainActor () -> Void, detach: @MainActor () -> Void
) {
    var pending = [runtime.root]
    var controllers: [(ViewNode, TextInputInteractionController)] = []
    while let node = pending.popLast() {
        pending.append(contentsOf: node.children)
        if let controller = node.textInputController as? TextInputInteractionController {
            controllers.append((node, controller))
        }
    }
    for (_, controller) in controllers {
        controller.revokeAccessibilityValueOwnership()
        controller.undoSession?.markInvalid()
        controller.invalidateDocumentEndpoint()
    }
    return (
        purgeHistory: {
            for (_, controller) in controllers { controller.undoSession?.purgeHistory() }
        },
        detach: {
            for (node, controller) in controllers { controller.detach(from: node) }
        }
    )
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
            isSecure && !isShowingPlaceholder
            ? String(repeating: secureFieldMaskCharacter, count: currentText.count) : currentText
        let inputPalette = context.controlPalette
        let textColor: Color
        if !context.isEnabled {
            textColor = inputPalette.disabledLabel
        } else if isShowingPlaceholder {
            // Placeholder renders at the macOS secondary-label prominence.
            textColor = inputPalette.tertiaryLabel
        } else {
            textColor = context.foregroundColor
        }

        let resolvedFont = (context.fontWeight.map { context.font.weight($0) } ?? context.font)
            .scaled(for: context.dynamicTypeSize)
            .scaled(by: context.textScale)

        @MainActor func makeTextLabel(_ content: String, underlined: Bool = false) -> ViewNode {
            Controls.label(
                content,
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
                nativeLetterSpacing: context.letterSpacing,
                lineSpacing: context.lineSpacing ?? resolvedFont.resolvedLineSpacing,
                lineBreakMode: allowsNewlines ? .wrap : .truncateTail,
                maximumNumberOfLines: allowsNewlines ? nil : 1,
                underline: underlined
            )
        }
        let contentText = isShowingPlaceholder ? (resolvedPlaceholder ?? "") : displayText
        let labelNode = makeTextLabel(contentText)
        if let baselineOffset = context.baselineOffset, baselineOffset != 0 {
            labelNode.transform = labelNode.transform.concatenating(.translation(x: 0, y: -Double(baselineOffset)))
        }
        let style = context.textFieldStyle.resolvedTextInputStyle(
            isEnabled: context.isEnabled, palette: context.controlPalette)
        let node = Controls.stackPanel(
            preferredSize: preferredSize,
            backgroundColor: style.backgroundColor,
            backgroundGradient: style.backgroundGradient,
            borderColor: style.borderColor,
            borderWidth: style.borderWidth,
            cornerRadius: style.cornerRadius,
            stackLayout: .vertical(padding: style.padding, alignment: .stretch),
            isHitTestVisible: context.isEnabled,
            children: [labelNode]
        )
        if allowsNewlines {
            // The focusable input remains the public retained identity. Its
            // only child is a clipped viewport inside the fixed bezel.
            // Typography belongs to the real content, not a hidden label.
            let content = ViewNode(isHitTestVisible: false)
            let viewport = Controls.scrollPanel(
                axis: .vertical,
                stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .stretch),
                scrollIndicatorAutoHides: true,
                isHitTestVisible: false,
                children: [content]
            )
            viewport.textStyle = labelNode.textStyle
            viewport.layoutFillAxes = .both
            node.removeAllChildren()
            node.addChild(viewport)
            node.explicitFrameFillAxes = .both
            node.forwardsStackMainAxisProposal = true
            node.interceptsVerticalArrowKeys = true
        }
        node.textInputSubmitLabel = context.submitLabel.retainedSubmitLabel
        // Default accessibility metadata: the isTextInput trait maps to the
        // UIA edit control type, the placeholder/title is the field's name,
        // and the current text is its value (secure fields never expose
        // their text). Explicit accessibility modifiers apply after this
        // and win.
        node.accessibilityTraits.formUnion(.isTextInput)
        if isSecure {
            node.accessibilityTraits.formUnion(.isSecureTextInput)
        }
        if let resolvedPlaceholder, !resolvedPlaceholder.isEmpty {
            node.accessibilityLabel = resolvedPlaceholder
        }
        if !isSecure, !currentText.isEmpty {
            node.accessibilityValue = currentText
        }
        let selectionValue = selection?.wrappedValue
        node.textInputCaretOffset = selectionValue?.caretOffset(in: currentText) ?? currentText.count
        node.textSelectionAffinity = context.textSelectionAffinity.retainedAffinity
        node.textInputSelection = selectionValue?.retainedSelection(in: currentText)
        let controller = TextInputInteractionController(
            node: node, characterCount: currentText.count, hasSelectionBinding: selection != nil,
            isSecure: isSecure, allowsNewlines: allowsNewlines, isEnabled: context.isEnabled,
            runtime: runtime, undoManager: context.environmentValues.undoManager, text: binding,
            documentSource: binding.mutationSource as? DocumentBindingSource,
            documentProjection: binding.mutationProjection)
        node.textInputController = controller
        controller.readText = { binding.wrappedValue }
        controller.observedDocumentSelection = selectionValue
        controller.readSelection = { [weak controller] in
            let value = selection?.wrappedValue
            if let controller, controller.current === controller { controller.observedDocumentSelection = value }
            return value
        }
        controller.invalidate = { context.invalidate() }
        controller.configureUndoSession()
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

        guard context.isEnabled || allowsNewlines else {
            return node
        }

        let caretLineHeight = resolvedFont.resolvedNativeTextSize
        let chromeState = TextInputEditingChromeState()
        if !allowsNewlines, !isSecure {
            let constructedLabelStyle = labelNode.textStyle
            let constructedSelectionColor = context.tint.opacity(0.35)
            controller.prepareFieldChromeForAdoption = {
                [weak controller, weak node, weak labelNode] candidate, editing in
                guard let controller, let node, let labelNode, candidate === node,
                    let retained = controller.node, retained !== candidate,
                    controller.current === controller, candidate.textInputController === controller,
                    chromeState.signature == nil,
                    candidate.children.count == 1, candidate.children.first === labelNode,
                    labelNode.parent === candidate, labelNode.children.isEmpty,
                    labelNode.textInputController == nil, !labelNode.isHidden,
                    labelNode.text == contentText, labelNode.textStyle == constructedLabelStyle
                else { return }
                // Unexpected authored children or a reused candidate remain
                // untouched. Only these fresh framework rows are appended;
                // even the original label is never removed and reattached.
                updateTextInputEditingChrome(
                    node: candidate, labelNode: labelNode, contentText: contentText,
                    isShowingPlaceholder: isShowingPlaceholder, caretColor: textColor,
                    selectionColor: constructedSelectionColor,
                    caretSize: Size(width: 1.5, height: caretLineHeight),
                    state: chromeState, editingState: editing, preparingDetachedCandidate: true,
                    makeSegmentLabel: { makeTextLabel($0) },
                    makeMarkedSegmentLabel: { makeTextLabel($0, underlined: true) })
            }
        }
        @MainActor func refreshChrome() {
            controller.current?.refreshChrome?()
        }
        controller.refreshChrome = { [weak controller] in
            guard let controller, let node = controller.node,
                node.textInputController === controller
            else { return }
            let currentText = binding.wrappedValue
            guard controller.current === controller, controller.node === node else { return }
            let isShowingPlaceholder = currentText.isEmpty
            let contentText =
                isShowingPlaceholder
                ? (resolvedPlaceholder ?? "")
                : isSecure ? String(repeating: secureFieldMaskCharacter, count: currentText.count) : currentText
            let marked = node.textInputMarkedText.flatMap { text -> String? in
                guard !text.isEmpty else { return nil }
                return isSecure ? String(repeating: secureFieldMaskCharacter, count: text.count) : text
            }
            if allowsNewlines {
                guard let viewport = textEditorViewport(in: node) else { return }
                updateTextEditorChrome(
                    controller: controller,
                    style: viewport.textStyle,
                    text: contentText,
                    markedText: marked,
                    caretColor: textColor,
                    selectionColor: context.tint.opacity(0.35),
                    displayScale: controller.undoRuntime?.displayScale ?? 1,
                    baselineOffset: Double(context.baselineOffset ?? 0)
                )
                return
            }
            guard let labelNode = node.children.first else { return }
            let labelChanged = labelNode.text != contentText
            if labelChanged { labelNode.text = contentText }
            let changedChrome = updateTextInputEditingChrome(
                node: node,
                labelNode: labelNode,
                contentText: contentText,
                isShowingPlaceholder: isShowingPlaceholder,
                caretColor: textColor,
                selectionColor: context.tint.opacity(0.35),
                caretSize: Size(width: 1.5, height: caretLineHeight),
                markedText: marked,
                state: chromeState,
                makeSegmentLabel: { makeTextLabel($0) },
                makeMarkedSegmentLabel: { makeTextLabel($0, underlined: true) }
            )
            if labelChanged || changedChrome != nil {
                queueTextFieldContentLayout(controller: controller, content: changedChrome ?? labelNode)
            }
        }
        // Rebuild caret/selection chrome after every layout pass so it tracks
        // focus, caret, and selection changes across runtime rebuilds.
        node.onLayout = { _ in refreshChrome() }
        if let viewport = textEditorViewport(in: node) {
            viewport.onLayout = { [weak controller] bounds in
                guard let controller, controller.current === controller,
                    let state = controller.editorLayoutState
                else { return }
                state.viewportWidth = bounds.size.width
                state.viewportHeight = bounds.size.height
                controller.refreshChrome?()
            }
            // Before attachment an authored callback still needs a faithful
            // layout at the component's ideal width. A placed viewport replaces
            // this proposal before its first retained paint.
            controller.editorLayoutState?.viewportWidth = max(
                0, preferredSize.width - style.padding.leading - style.padding.trailing)
            controller.editorLayoutState?.viewportHeight = max(
                0, preferredSize.height - style.padding.top - style.padding.bottom)
            refreshChrome()
        }

        // Caret rectangle in root coordinates for the OS IME candidate
        // window (ImmSetCompositionWindow via the window host). Follows the
        // composition display state so the candidate window tracks the end of
        // the marked text while composing.
        node.textInputCaretRectProvider = { [weak controller, weak runtime] in
            guard let controller, let node = controller.node,
                node.textInputController === controller,
                let contentOrigin = textInputContentOrigin(controller: controller, runtime: runtime)
            else {
                return nil
            }
            if allowsNewlines {
                guard let state = controller.editorLayoutState,
                    let caretRect = state.caretRect
                else { return nil }
                return caretRect.offsetBy(dx: contentOrigin.x, dy: contentOrigin.y)
            }
            guard let labelNode = node.children.first else { return nil }
            let currentText = binding.wrappedValue
            let sourceText =
                isSecure && !currentText.isEmpty
                ? String(repeating: secureFieldMaskCharacter, count: currentText.count) : currentText
            let selection = node.textInputSelection?.editableCharacterRange(in: sourceText)
            let caret = clampedTextOffset(node.textInputCaretOffset, in: sourceText)
            let display = textInputCompositionDisplayState(
                contentText: sourceText,
                caret: caret,
                selection: selection,
                markedText: node.textInputMarkedText.map {
                    isSecure ? String(repeating: secureFieldMaskCharacter, count: $0.count) : $0
                }
            )
            let lineRanges = textInputHardLineRanges(in: display.text)
            let caretLineIndex = lineRanges.lastIndex(where: { $0.lowerBound <= display.caret }) ?? 0
            var rowTop = 0.0
            var rowHeight = max(1, caretLineHeight)
            for (index, lineRange) in lineRanges.enumerated() {
                let line = display.text.textSubstring(in: lineRange)
                let height = max(
                    1,
                    RetainedTextMetrics.size(
                        of: line.isEmpty ? " " : line,
                        style: labelNode.textStyle,
                        displayScale: runtime?.displayScale ?? 1
                    ).height
                )
                if index == caretLineIndex {
                    rowHeight = height
                    break
                }
                rowTop += height
            }
            let caretLine = display.text.textSubstring(in: lineRanges[caretLineIndex])
            let caretX = RetainedTextMetrics.caretX(
                atOffset: display.caret - lineRanges[caretLineIndex].lowerBound,
                in: caretLine,
                style: labelNode.textStyle,
                displayScale: runtime?.displayScale ?? 1
            )
            let rootPoint = Point(x: contentOrigin.x + caretX, y: contentOrigin.y + rowTop)
            return Rect(x: rootPoint.x, y: rootPoint.y, width: 0, height: rowHeight)
        }

        guard context.isEnabled else { return node }

        node.isFocusable = true
        // The bezel and ring are the runtime's to resolve — see
        // `RetainedInteractionSurface`. Setting them from these closures meant
        // a focused field lost its ring on the next rebuild (the build writes
        // the unfocused border back), and, worse, the closures were copied
        // onto the retained node still addressing the *discarded* build's
        // node, so after one rebuild focusing the field changed nothing at
        // all. What is left here is the part that genuinely belongs to the
        // field: the editing callback and the caret/selection chrome.
        node.interactionSurface = RetainedInteractionSurface(
            idleBorder: style.borderColor,
            focusedBorder: context.tint,
            focusRingColor: ControlPalette.opaque(context.tint)
                .opacity(Double(ControlPalette.focusRingAlpha)),
            focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth
        )
        node.outlineWidth = 0
        node.onFocusEnter = {
            guard controller.current === controller else { return }
            onEditingChanged?(true)
            refreshChrome()
        }
        node.onFocusExit = {
            guard controller.current === controller else { return }
            controller.isComposing = false
            controller.preferredVisualX = nil
            controller.isSelectingWithPointer = false
            controller.node?.textInputMarkedText = nil
            onEditingChanged?(false)
            refreshChrome()
        }
        @MainActor func currentSelectionState(in sourceText: String? = nil) -> (
            caret: Int, range: Range<Int>?, anchor: Int
        ) {
            guard let node = controller.current?.node else { return (0, nil, 0) }
            let text = sourceText ?? binding.wrappedValue
            let caret = clampedTextOffset(node.textInputCaretOffset, in: text)
            guard let range = node.textInputSelection?.editableCharacterRange(in: text) else {
                return (caret, nil, caret)
            }
            let anchor = caret == range.lowerBound ? range.upperBound : range.lowerBound
            return (caret, range, anchor)
        }
        @MainActor func applySelection(anchor: Int, extent: Int) {
            _ = controller.current?.applySelection?(.init(anchor: anchor, extent: extent))
        }
        controller.applySelection = { [weak controller] update in
            guard let controller, let node = controller.node, node.textInputController === controller else {
                return false
            }
            let wasAttached = controller.isAttached
            let text = binding.wrappedValue
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, update.documentValidation?() ?? true
            else { return false }
            if let preparation = update.preparation, !text.utf8.elementsEqual(preparation.text.utf8) {
                // A getter can replace the source without replacing this
                // controller. A destination from older geometry is not an
                // instruction to select a different document's characters.
                controller.undoRuntime?.invalidateTextInputLayout(for: node, controller: controller)
                controller.invalidate?()
                return false
            }
            if let preparation = update.preparation {
                guard !controller.isComposing, node.textInputMarkedText == nil else { return false }
                // A getter may change layout while leaving the controller
                // and text intact. Settle that geometry, then validate the
                // prepared destination before any selection write.
                if controller.isAttached {
                    guard textInputContentOrigin(controller: controller, runtime: controller.undoRuntime) != nil else {
                        return false
                    }
                }
                guard controller.current === controller, controller.node === node,
                    !wasAttached || controller.isAttached,
                    !controller.isComposing, node.textInputMarkedText == nil,
                    controller.editorLayoutState?.geometryGeneration == preparation.geometryGeneration,
                    controller.editorLayoutState?.key?.text.utf8.elementsEqual(preparation.text.utf8) == true
                else { return false }
            }
            guard update.documentValidation?() ?? true else { return false }
            if let affinity = update.affinity { controller.visualCaretAffinity = affinity }
            if update.resetsPreferredVisualX {
                controller.preferredVisualX = nil
            } else if let preferredVisualX = update.preferredVisualX {
                controller.preferredVisualX = preferredVisualX
            }
            if let pointerAnchor = update.pointerAnchor {
                controller.pointerDragAnchor = clampedTextOffset(pointerAnchor, in: text)
                controller.isSelectingWithPointer = true
            }
            let clampedAnchor = clampedTextOffset(update.anchor, in: text)
            let clampedExtent = clampedTextOffset(update.extent, in: text)
            let lower = min(clampedAnchor, clampedExtent)
            let upper = max(clampedAnchor, clampedExtent)
            node.textInputCaretOffset = clampedExtent
            if lower == upper {
                if let selection {
                    let nextSelection = TextSelection.insertion(
                        at: lower,
                        in: text,
                        affinity: allowsNewlines
                            ? textEditorSelectionAffinity(controller.visualCaretAffinity)
                            : context.textSelectionAffinity
                    )
                    node.textInputSelection = nextSelection.retainedSelection(in: text)
                    controller.observedDocumentSelection = nextSelection
                    selection.wrappedValue = nextSelection
                } else {
                    node.textInputSelection = nil
                }
            } else {
                let affinity: TextSelectionAffinity = clampedExtent >= clampedAnchor ? .downstream : .upstream
                node.textInputSelection = RetainedTextSelection(
                    indices: .range(lower..<upper),
                    affinity: affinity.retainedAffinity
                )
                if let selection {
                    let lowerIndex = text.index(text.startIndex, offsetBy: lower)
                    let upperIndex = text.index(text.startIndex, offsetBy: upper)
                    let nextSelection = TextSelection(
                        indices: .selection(lowerIndex..<upperIndex),
                        affinity: affinity
                    )
                    controller.observedDocumentSelection = nextSelection
                    selection.wrappedValue = nextSelection
                }
            }
            controller.current?.refreshChrome?()
            return true
        }
        controller.restoreUndoSelection = { [weak controller] snapshot in
            guard let controller, let node = controller.node, controller.current === controller else { return }
            let text = binding.wrappedValue
            guard controller.current === controller, controller.node === node else { return }
            controller.preferredVisualX = nil
            controller.visualCaretAffinity = snapshot.affinity
            node.textInputCaretOffset = min(max(0, snapshot.caret), text.count)
            node.textInputSelection = snapshot.selection
            node.textSelectionAffinity = snapshot.affinity
            let restored = snapshot.boundValue(in: text)
            controller.observedDocumentSelection = restored
            selection?.wrappedValue = restored
            controller.current?.refreshChrome?()
        }
        controller.restoreDocumentSelectionBody = { [weak controller] request in
            guard let controller, controller.documentSelectionIsCurrent, request.validate(),
                let node = controller.node, let runtime = controller.undoRuntime,
                runtime.permitsTextInputReplay(on: node), request.validate(), controller.current === controller,
                let replayScopeRevision = runtime.textInputReplayScopeRevision
            else { return }
            let text = binding.wrappedValue
            guard request.validate(), controller.current === controller, controller.node === node,
                text.utf8.elementsEqual(request.expectedText.utf8)
            else { return }
            let boundSelection = selection?.wrappedValue
            guard request.validate(), controller.current === controller, controller.node === node,
                boundSelection == request.expectedBoundSelection
            else { return }
            // A getter can invalidate scope or run a nested layout that
            // drains selection-changing callbacks. Compare without running
            // more application callbacks after sampling the selection.
            guard request.validate(), controller.current === controller, controller.node === node,
                runtime.textInputReplayScopeRevision == replayScopeRevision
            else { return }
            let restored = request.selection.boundValue(in: text)
            controller.preferredVisualX = nil
            controller.visualCaretAffinity = request.selection.affinity
            node.textInputCaretOffset = min(max(0, request.selection.caret), text.count)
            node.textInputSelection = restored?.retainedSelection(in: text)
            node.textSelectionAffinity = request.selection.affinity
            controller.observedDocumentSelection = restored
            selection?.wrappedValue = restored
            guard request.validate(), controller.current === controller else { return }
            controller.refreshChrome?()
            controller.invalidate?()
        }
        @MainActor func invalidate() {
            controller.current?.invalidate?()
        }
        @MainActor func setCaretOffset(_ offset: Int) {
            applySelection(anchor: offset, extent: offset)
        }
        @MainActor func replaceDocumentText(in range: Range<Int>, with inserted: String) {
            guard controller.current === controller, !isSecure, controller.isEnabled,
                let node = controller.node, let source = controller.documentSource,
                let runtime = controller.undoRuntime, source.belongs(to: runtime)
            else { return }
            controller.supersedeAccessibilityValueAttempt()
            let wasAttached = controller.isAttached
            let originalText = binding.wrappedValue
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, source.isLive
            else { return }
            let updatedText = originalText.replacingText(in: range, with: inserted)
            var beforeSelection = TextInputUndoSelection(node: node, text: originalText)
            if allowsNewlines { beforeSelection.affinity = controller.visualCaretAffinity }
            guard
                let ticket = source.beginEdit(
                    before: originalText, proposed: updatedText, selection: beforeSelection,
                    endpoint: controller.documentEndpoint)
            else { return }
            defer { ticket.cancel() }
            let originalRevision = source.owner?.documentMutationRevision
            let previousSelection = controller.readSelection?()
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, ticket.permitsWrite
            else { return }
            let currentText = binding.wrappedValue
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, ticket.permitsWrite
            else { return }
            guard currentText.utf8.elementsEqual(originalText.utf8) else {
                invalidate()
                return
            }
            let caret = range.lowerBound + inserted.count
            let previousPreferredX = controller.preferredVisualX
            node.textInputCaretOffset = caret
            node.textInputSelection = nil
            controller.preferredVisualX = nil
            controller.visualCaretAffinity = .downstream
            binding.write(updatedText, mutation: ticket)

            guard ticket.receipt != nil else {
                // A revoked/limited binding can reject the write. Restore only
                // the internal selection we staged, never newer application
                // text, selection, or an editor adopted by another document.
                guard controller.current === controller, controller.node === node,
                    !wasAttached || controller.isAttached, source.isLive,
                    source.owner?.documentMutationRevision == originalRevision
                else { return }
                let text = binding.wrappedValue
                guard controller.current === controller, source.isLive,
                    source.owner?.documentMutationRevision == originalRevision,
                    text.utf8.elementsEqual(originalText.utf8)
                else { return }
                let boundSelection = controller.readSelection?()
                guard controller.current === controller, controller.node === node,
                    !wasAttached || controller.isAttached, source.isLive,
                    source.owner?.documentMutationRevision == originalRevision,
                    boundSelection == previousSelection,
                    node.textInputCaretOffset == caret, node.textInputSelection == nil
                else { return }
                node.textInputCaretOffset = beforeSelection.caret
                node.textInputSelection = beforeSelection.selection
                controller.visualCaretAffinity = beforeSelection.affinity
                controller.preferredVisualX = previousPreferredX
                controller.refreshChrome?()
                return
            }
            guard let current = controller.current, current.node === node,
                current.sharesDocumentLocation(with: controller), ticket.permitsCompletion
            else { return }
            let selectionWasReplaced = current.hasSelectionBinding && current.readSelection?() != previousSelection
            guard current.current === current, ticket.permitsCompletion else { return }
            let acceptedText = current.readText?()
            guard current.current === current, ticket.permitsCompletion else { return }
            if acceptedText?.utf8.elementsEqual(updatedText.utf8) == true, !selectionWasReplaced {
                let validate: @MainActor () -> Bool = { [weak controller, weak current, weak ticket] in
                    guard let controller, let current, let ticket else { return false }
                    return current.current === current && current.sharesDocumentLocation(with: controller)
                        && ticket.permitsCompletion
                }
                _ = current.applySelection?(.init(anchor: caret, extent: caret, documentValidation: validate))
            }
            guard let latest = controller.current, latest.node === node,
                latest.sharesDocumentLocation(with: controller), ticket.permitsCompletion,
                let text = latest.undoText
            else { return }
            guard latest.current === latest, ticket.permitsCompletion else { return }
            let selection = latest.undoSelection
            guard latest.current === latest, ticket.permitsCompletion else { return }
            ticket.finish(text: text, selection: selection)
            controller.current?.invalidate?()
        }
        @MainActor func replaceText(in range: Range<Int>, with inserted: String) {
            if controller.documentSource != nil {
                replaceDocumentText(in: range, with: inserted)
                return
            }
            guard controller.current === controller, let node = controller.node else { return }
            controller.supersedeAccessibilityValueAttempt()
            let wasAttached = controller.isAttached
            let originalText = binding.wrappedValue
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached
            else { return }
            let updatedText = originalText.replacingText(in: range, with: inserted)
            let session = controller.undoSession
            var beforeSelection = TextInputUndoSelection(node: node, text: originalText)
            if allowsNewlines { beforeSelection.affinity = controller.visualCaretAffinity }
            let mutation = session?.beginEdit(
                before: originalText, expected: updatedText,
                selection: beforeSelection)
            defer { session?.cancelEdit(mutation) }
            let generation = session?.generation
            // Stale-history cleanup can close or rebuild the editor before
            // this callback has performed any binding write.
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, controller.undoSession === session,
                session?.isValid != false
            else { return }
            let caret = range.lowerBound + inserted.count
            let previousSelection = controller.readSelection?()
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, controller.undoSession === session,
                session?.isValid != false, session?.generation == generation
            else { return }
            let currentText = binding.wrappedValue
            guard controller.current === controller, controller.node === node,
                !wasAttached || controller.isAttached, controller.undoSession === session,
                session?.isValid != false, session?.generation == generation
            else { return }
            guard currentText == originalText else {
                invalidate()
                return
            }
            // Stage the live selection before a Binding setter can synchronously
            // rebuild. Continue only while this editor still presents the edit;
            // a callback may instead remove it or install another document.
            node.textInputCaretOffset = caret
            node.textInputSelection = nil
            controller.preferredVisualX = nil
            controller.visualCaretAffinity = .downstream
            binding.wrappedValue = updatedText
            guard let current = controller.current, current.node === node else { return }
            // An explicit selection changed by the setter belongs to newer
            // application state, even when it kept the text we just wrote.
            let selectionWasReplaced = current.hasSelectionBinding && current.readSelection?() != previousSelection
            if current.readText?() == updatedText, !selectionWasReplaced {
                _ = current.applySelection?(.init(anchor: caret, extent: caret))
            }
            if let latest = controller.current, latest.undoSession === session, let text = latest.undoText,
                let selection = latest.undoSelection
            {
                session?.finishEdit(mutation, text: text, selection: selection)
            }
            controller.current?.invalidate?()
        }
        controller.writeUndoText = { [weak controller] text, snapshot in
            guard let controller, controller.current === controller, let node = controller.node,
                let session = controller.undoSession, session.isValid
            else { return }
            controller.supersedeAccessibilityValueAttempt()
            let generation = session.generation
            let previousSelection = controller.readSelection?()
            guard controller.current === controller, controller.node === node,
                session.isValid, session.generation == generation, controller.undoSession === session
            else { return }
            let currentText = binding.wrappedValue
            guard controller.current === controller, controller.node === node,
                controller.undoSession === session,
                session.canWriteReplacement(over: currentText, generation: generation)
            else { return }
            node.textInputCaretOffset = snapshot.caret
            node.textInputSelection = snapshot.selection
            node.textSelectionAffinity = snapshot.affinity
            controller.preferredVisualX = nil
            controller.visualCaretAffinity = snapshot.affinity
            binding.wrappedValue = text
            guard session.isValid, session.generation == generation,
                let current = controller.current, current.undoSession === session,
                current.readText?() == text
            else { return }
            let selectionWasReplaced = current.hasSelectionBinding && current.readSelection?() != previousSelection
            if !selectionWasReplaced {
                current.restoreUndoSelection?(snapshot)
            }
        }
        @MainActor func deleteSelection(_ range: Range<Int>) {
            replaceText(in: range, with: "")
        }
        node.onKeyDown = { event in
            guard controller.current === controller, let node = controller.node else { return }

            let isUndo = event.keyCode == 0x5A && event.modifiers == [.control]
            let isRedo =
                (event.keyCode == 0x5A && event.modifiers == [.control, .shift])
                || (event.keyCode == 0x59 && event.modifiers == [.control])
            if isUndo || isRedo {
                controller.invalidate?()
                guard let current = controller.current, current.permitsUndoReplay, let runtime = current.undoRuntime
                else { return }
                if let source = current.documentSource {
                    guard source.belongs(to: runtime), let owner = source.owner,
                        let manager = owner.documentUndoManager
                    else { return }
                    let permitsTarget: @MainActor (AnyObject) -> Bool = {
                        [weak current, weak source, weak owner, weak runtime] target in
                        guard let current, let source, let owner, let runtime,
                            let active = current.current, active.sharesDocumentLocation(with: current),
                            active.permitsUndoReplay, active.current === active,
                            active.undoRuntime === runtime, source.belongs(to: runtime), source.owner === owner
                        else { return false }
                        return target === owner
                    }
                    if isUndo {
                        manager.undo(allowingTarget: permitsTarget)
                    } else {
                        manager.redo(allowingTarget: permitsTarget)
                    }
                    return
                }
                guard let manager = current.undoSession?.manager else { return }
                let permitsTarget: @MainActor (AnyObject) -> Bool = { target in
                    (target as? TextInputUndoSession)?.belongs(to: runtime) == true
                }
                if isUndo {
                    manager.undo(allowingTarget: permitsTarget)
                } else {
                    manager.redo(allowingTarget: permitsTarget)
                }
                return
            }

            // Escape discards an in-progress IME composition without
            // committing. Real IMEs normally consume Escape themselves and
            // cancel via WM_IME_COMPOSITION; this covers IMEs that pass the
            // key through.
            if event.key == .escape, node.textInputMarkedText != nil {
                controller.isComposing = false
                node.textInputMarkedText = nil
                refreshChrome()
                return
            }

            if event.key == .enter, !allowsNewlines {
                if let onCommit {
                    onCommit()
                    invalidate()
                }
                return
            }

            if allowsNewlines,
                event.key == .upArrow || event.key == .downArrow || event.key == .home || event.key == .end,
                event.modifiers == [] || event.modifiers == [.shift]
                    || event.modifiers == [.control] || event.modifiers == [.control, .shift]
            {
                // Composition owns its candidate-navigation keys. Never turn
                // an Up/Down passed through by an IME into a document edit.
                guard !controller.isComposing, node.textInputMarkedText == nil else { return }
                let vertical = event.key == .upArrow || event.key == .downArrow
                // Paragraph navigation is outside this bounded editor path.
                // Reserve Ctrl+Up/Down rather than moving an enclosing scroller.
                if vertical, event.modifiers.contains(.control) { return }
                refreshChrome()
                guard controller.current === controller else { return }
                if controller.isAttached {
                    guard textInputContentOrigin(controller: controller, runtime: controller.undoRuntime) != nil,
                        controller.current === controller
                    else { return }
                }
                guard controller.current === controller,
                    !controller.isComposing, node.textInputMarkedText == nil,
                    let layout = controller.editorLayoutState?.layout,
                    let sourceText = controller.editorLayoutState?.key?.text,
                    let preparation = controller.editorLayoutState?.selectionPreparation,
                    layout.hasCompleteCaretGeometry
                else { return }
                // The final snapshot and selection are read after all layout
                // callbacks. No application getter sits between choosing the
                // visual line and computing its destination.
                let state = currentSelectionState(in: sourceText)
                guard controller.current === controller,
                    let caret = layout.caret(
                        at: RetainedTextCaretPosition(
                            characterOffset: state.caret, affinity: controller.visualCaretAffinity))
                else { return }
                let destination: RetainedTextCaretPosition
                var preferredVisualX: Double?
                if vertical {
                    let preferredX = controller.preferredVisualX ?? caret.rect.minX
                    preferredVisualX = preferredX
                    let line = caret.lineIndex + (event.key == .upArrow ? -1 : 1)
                    guard layout.lines.indices.contains(line),
                        let target = layout.caret(onLine: line, nearestX: preferredX)
                    else {
                        controller.requestEditorCaretReveal()
                        return
                    }
                    destination = target.position
                } else {
                    if event.modifiers.contains(.control) {
                        destination = RetainedTextCaretPosition(
                            characterOffset: event.key == .home ? 0 : layout.characterCount,
                            affinity: event.key == .home ? .downstream : .upstream)
                    } else {
                        let line = layout.lines[caret.lineIndex]
                        destination = RetainedTextCaretPosition(
                            characterOffset: event.key == .home
                                ? line.sourceRange.lowerBound : line.sourceRange.upperBound,
                            affinity: event.key == .home ? .downstream : .upstream)
                    }
                }
                guard
                    controller.applySelection?(
                        .init(
                            anchor: event.modifiers.contains(.shift) ? state.anchor : destination.characterOffset,
                            extent: destination.characterOffset,
                            preparation: preparation,
                            affinity: destination.affinity,
                            preferredVisualX: preferredVisualX,
                            resetsPreferredVisualX: !vertical)) == true
                else { return }
                controller.current?.requestEditorCaretReveal()
                invalidate()
                return
            }

            // Word navigation has to run before the Ctrl+clipboard dispatch:
            // arrows are not clipboard shortcuts, and the old switch's
            // default swallowed Ctrl+Left/Right altogether. Character-based
            // boundaries keep emoji and combining sequences indivisible.
            if event.modifiers.contains(.control),
                event.key == .leftArrow || event.key == .rightArrow
            {
                controller.preferredVisualX = nil
                controller.visualCaretAffinity = event.key == .leftArrow ? .upstream : .downstream
                let state = currentSelectionState()
                let destination = textInputWordBoundary(
                    in: binding.wrappedValue,
                    from: state.caret,
                    movingForward: event.key == .rightArrow
                )
                if event.modifiers.contains(.shift) {
                    applySelection(anchor: state.anchor, extent: destination)
                } else {
                    setCaretOffset(destination)
                    invalidate()
                }
                return
            }

            if event.modifiers.contains(.control) {
                let clipboard = context.textInputClipboard ?? TextInputClipboardProvider.current
                switch event.keyCode {
                case 0x41:  // Ctrl+A — select all
                    controller.preferredVisualX = nil
                    controller.visualCaretAffinity = .upstream
                    let count = binding.wrappedValue.count
                    guard count > 0 else {
                        return
                    }
                    applySelection(anchor: 0, extent: count)
                case 0x43:  // Ctrl+C — copy (disabled for secure fields)
                    guard !isSecure, let range = currentSelectionState().range else {
                        return
                    }
                    clipboard.copyString(binding.wrappedValue.textSubstring(in: range))
                case 0x58:  // Ctrl+X — cut (disabled for secure fields)
                    guard !isSecure, let range = currentSelectionState().range else {
                        return
                    }
                    clipboard.copyString(binding.wrappedValue.textSubstring(in: range))
                    guard controller.current === controller else { return }
                    deleteSelection(range)
                case 0x56:  // Ctrl+V — paste over the selection or at the caret
                    guard let pasted = clipboard.pasteString() else {
                        return
                    }
                    guard controller.current === controller else { return }
                    let pastedText =
                        allowsNewlines
                        ? pasted
                            .replacingOccurrences(of: "\r\n", with: "\n")
                            .replacingOccurrences(of: "\r", with: "\n")
                        : String(pasted.prefix(while: { $0 != "\r" && $0 != "\n" }))
                    guard !pastedText.isEmpty else {
                        return
                    }
                    let state = currentSelectionState()
                    let replacementRange = state.range ?? (state.caret..<state.caret)
                    replaceText(in: replacementRange, with: pastedText)
                default:
                    return
                }
                return
            }

            if event.key == .backspace {
                if let selectedRange = currentSelectionState().range {
                    deleteSelection(selectedRange)
                    return
                }

                let clampedCaret = currentSelectionState().caret
                guard clampedCaret > 0 else {
                    return
                }

                replaceText(in: (clampedCaret - 1)..<clampedCaret, with: "")
                return
            }

            if event.key == .deleteForward {
                if let selectedRange = currentSelectionState().range {
                    deleteSelection(selectedRange)
                    return
                }

                let clampedCaret = currentSelectionState().caret
                guard clampedCaret < binding.wrappedValue.count else {
                    return
                }

                replaceText(in: clampedCaret..<(clampedCaret + 1), with: "")
                return
            }

            switch event.key {
            case .leftArrow:
                controller.preferredVisualX = nil
                controller.visualCaretAffinity = .upstream
                let state = currentSelectionState()
                if event.modifiers.contains(.shift) {
                    applySelection(anchor: state.anchor, extent: state.caret - 1)
                } else if let range = state.range {
                    setCaretOffset(range.lowerBound)
                    invalidate()
                } else {
                    setCaretOffset(state.caret - 1)
                    invalidate()
                }
                return
            case .rightArrow:
                controller.preferredVisualX = nil
                controller.visualCaretAffinity = .downstream
                let state = currentSelectionState()
                if event.modifiers.contains(.shift) {
                    applySelection(anchor: state.anchor, extent: state.caret + 1)
                } else if let range = state.range {
                    setCaretOffset(range.upperBound)
                    invalidate()
                } else {
                    setCaretOffset(state.caret + 1)
                    invalidate()
                }
                return
            case .home:
                if event.modifiers.contains(.shift) {
                    let state = currentSelectionState()
                    applySelection(anchor: state.anchor, extent: 0)
                } else {
                    setCaretOffset(0)
                    invalidate()
                }
                return
            case .end:
                if event.modifiers.contains(.shift) {
                    let state = currentSelectionState()
                    applySelection(anchor: state.anchor, extent: binding.wrappedValue.count)
                } else {
                    setCaretOffset(binding.wrappedValue.count)
                    invalidate()
                }
                return
            case .backspace, .deleteForward:
                return
            case nil, .tab, .enter, .shift, .control, .alt, .escape, .pageUp, .pageDown, .upArrow, .downArrow, .space,
                .mediaPlayPause:
                break
            }

            let state = currentSelectionState()
            let replacementRange = state.range ?? (state.caret..<state.caret)
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

            replaceText(in: replacementRange, with: character)
        }

        // IME composition flow: updates track the marked (underlined)
        // composition text at the caret without touching the binding; a
        // commit inserts the result string as normal text, replacing the
        // current selection exactly like typed input; ending the session
        // discards any uncommitted marked text.
        node.onIMEComposition = { event in
            guard controller.current === controller, let node = controller.node else { return }
            switch event.phase {
            case .started:
                controller.isComposing = true
            case .updated(let composition):
                controller.isComposing = true
                let marked =
                    allowsNewlines
                    ? composition
                    : String(composition.prefix(while: { $0 != "\r" && $0 != "\n" }))
                node.textInputMarkedText = marked.isEmpty ? nil : marked
                refreshChrome()
            case .committed(let result):
                // A native result can arrive before WM_IME_ENDCOMPOSITION.
                // Keep an existing composition session protected until end.
                node.textInputMarkedText = nil
                let committed =
                    allowsNewlines
                    ? result
                    : String(result.prefix(while: { $0 != "\r" && $0 != "\n" }))
                guard !committed.isEmpty else {
                    refreshChrome()
                    return
                }
                let state = currentSelectionState()
                let replacementRange = state.range ?? (state.caret..<state.caret)
                let inserted =
                    event.source == .keyboard
                    ? autocapitalizedInsertedCharacter(
                        committed,
                        currentText: binding.wrappedValue.textPrefix(upTo: replacementRange.lowerBound),
                        textInputAutocapitalization: context.textInputAutocapitalization
                    )
                    : committed
                replaceText(in: replacementRange, with: inserted)
            case .ended:
                controller.isComposing = false
                node.textInputMarkedText = nil
                refreshChrome()
            }
        }

        // Pointer-down places the caret at the hit offset; dragging extends
        // the selection from the down anchor. Request focus here as well as
        // in runtime routing so direct callback callers use the same path.
        controller.textPosition = { [weak controller, weak runtime] point in
            guard let controller, let node = controller.node,
                node.textInputController === controller
            else { return nil }
            if allowsNewlines {
                // A composition has its own candidate selection; clicking
                // through it must not remap a display offset into the model.
                guard !controller.isComposing, node.textInputMarkedText == nil else { return nil }
                controller.refreshChrome?()
                guard controller.current === controller,
                    let contentOrigin = textInputContentOrigin(controller: controller, runtime: runtime),
                    controller.current === controller,
                    let state = controller.editorLayoutState,
                    let hit = state.layout?.hitTest(
                        Point(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y - state.contentTranslationY))
                else { return nil }
                return hit.position
            }
            guard let contentOrigin = textInputContentOrigin(controller: controller, runtime: runtime),
                let labelNode = node.children.first
            else { return nil }
            let offset = textInputOffset(
                atRootPoint: point,
                contentOrigin: contentOrigin,
                labelNode: labelNode,
                text: binding.wrappedValue,
                isSecure: isSecure,
                allowsNewlines: allowsNewlines,
                displayScale: runtime?.displayScale ?? 1
            )
            return RetainedTextCaretPosition(characterOffset: offset)
        }
        node.onDragStart = { [weak runtime] point in
            guard controller.current === controller, let node = controller.node, let runtime else { return }
            controller.isSelectingWithPointer = false
            runtime.requestFocus(node)
            guard let current = controller.current, current.node === node, node.isFocused,
                let position = current.textPosition?(point)
            else { return }
            _ = current.applySelection?(
                .init(
                    anchor: position.characterOffset, extent: position.characterOffset,
                    preparation: current.editorLayoutState?.selectionPreparation,
                    affinity: position.affinity, pointerAnchor: position.characterOffset,
                    resetsPreferredVisualX: true))
        }
        node.onDragChange = { point, _ in
            guard let current = controller.current, current.isSelectingWithPointer,
                current.node?.isFocused == true, let position = current.textPosition?(point)
            else { return }
            _ = current.applySelection?(
                .init(
                    anchor: current.pointerDragAnchor, extent: position.characterOffset,
                    preparation: current.editorLayoutState?.selectionPreparation,
                    affinity: position.affinity,
                    resetsPreferredVisualX: true))
        }
        node.onDragEnd = { _, _ in controller.current?.isSelectingWithPointer = false }

        return node
    }
}
/// Geometry belongs to the displayed text and accepted viewport width. This
/// cache contains no bindings, runtime, or authored child-node ownership.
private struct TextEditorSelectionPreparation {
    var text: String
    var geometryGeneration: UInt64
}

@MainActor
private final class TextEditorLayoutState {
    struct Key: Equatable {
        var text: String
        var style: PixelTextStyle
        var width: Double
        var displayScale: Double

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.text.utf8.elementsEqual(rhs.text.utf8) && lhs.style == rhs.style
                && lhs.width == rhs.width && lhs.displayScale == rhs.displayScale
        }
    }

    struct Signature: Equatable {
        var key: Key
        var caret: RetainedTextCaretPosition
        var selection: Range<Int>?
        var markedRange: Range<Int>?
        var isFocused: Bool
        var caretColor: Color
        var selectionColor: Color
        var contentTranslationY: Double
        var viewportHeight: Double
    }

    var key: Key?
    var layout: RetainedTextEditingLayout?
    var viewportWidth: Double = 0
    var viewportHeight: Double = 0
    var displayCaret = RetainedTextCaretPosition(characterOffset: 0)
    var contentTranslationY: Double = 0
    var renderSignature: Signature?
    var revealSignature: Signature?
    weak var renderedContent: ViewNode?
    var needsCaretReveal = false
    var revealDeferrals = 0
    var geometryGeneration: UInt64 = 0

    var selectionPreparation: TextEditorSelectionPreparation? {
        guard let key, layout?.hasCompleteCaretGeometry == true else { return nil }
        return TextEditorSelectionPreparation(text: key.text, geometryGeneration: geometryGeneration)
    }

    var caretRect: Rect? {
        guard let caret = layout?.caret(at: displayCaret) else { return nil }
        return translated(caret.rect)
    }

    func translated(_ rect: Rect) -> Rect { rect.offsetBy(dx: 0, dy: contentTranslationY) }
}

@MainActor
private func textEditorViewport(in node: ViewNode) -> ViewNode? {
    guard (node.textInputController as? TextInputInteractionController)?.allowsNewlines == true else { return nil }
    return node.children.first(where: { $0.scrollAxis == .vertical })
}

private func textEditorSelectionAffinity(_ affinity: RetainedTextSelectionAffinity) -> TextSelectionAffinity {
    switch affinity {
    case .automatic: .automatic
    case .upstream: .upstream
    case .downstream: .downstream
    }
}

@MainActor
private func updateTextEditorChrome(
    controller: TextInputInteractionController,
    style: PixelTextStyle,
    text: String,
    markedText: String?,
    caretColor: Color,
    selectionColor: Color,
    displayScale: Double,
    baselineOffset: Double
) {
    guard controller.current === controller, let node = controller.node,
        let state = controller.editorLayoutState, let viewport = textEditorViewport(in: node),
        let content = viewport.children.first
    else { return }
    let baseCaret = clampedTextOffset(node.textInputCaretOffset, in: text)
    let display = textInputCompositionDisplayState(
        contentText: text,
        caret: baseCaret,
        selection: node.textInputSelection?.editableCharacterRange(in: text),
        markedText: markedText
    )
    let viewportWidth =
        !controller.isAttached && viewport.frame.size.width > 0
        ? viewport.frame.size.width : state.viewportWidth
    // Leave room for the insertion indicator at an exactly filled line end.
    // It is an overlay and must not alter the shaped fragment's advances.
    let width = max(0, viewportWidth - 1.5)
    let key = TextEditorLayoutState.Key(text: display.text, style: style, width: width, displayScale: displayScale)
    var geometryChanged = false
    if state.key != key {
        // A new width, font, scale, or source invalidates a preferred X taken
        // from the old shaping. Paint-only style changes do not.
        let oldLayout = state.layout
        let sourceChanged = state.key.map { !$0.text.utf8.elementsEqual(key.text.utf8) } ?? true
        state.key = key
        state.layout = RetainedTextMetrics.editingLayout(
            of: display.text, style: style, contentWidth: width, displayScale: displayScale)
        geometryChanged = oldLayout != state.layout || sourceChanged
        if geometryChanged { controller.preferredVisualX = nil }
    }
    state.displayCaret = RetainedTextCaretPosition(
        characterOffset: display.caret,
        affinity: display.markedRange == nil ? controller.visualCaretAffinity : .downstream
    )
    let signature = TextEditorLayoutState.Signature(
        key: key,
        caret: state.displayCaret,
        selection: display.selection,
        markedRange: display.markedRange,
        isFocused: node.isFocused,
        caretColor: caretColor,
        selectionColor: selectionColor,
        contentTranslationY: baselineOffset.isFinite ? -baselineOffset : 0,
        viewportHeight: !controller.isAttached && viewport.frame.size.height > 0
            ? viewport.frame.size.height : state.viewportHeight
    )
    state.contentTranslationY = signature.contentTranslationY
    let previousReveal = state.revealSignature
    if geometryChanged || previousReveal?.viewportHeight != signature.viewportHeight
        || previousReveal?.contentTranslationY != signature.contentTranslationY
    {
        state.geometryGeneration &+= 1
    }
    let needsReveal =
        geometryChanged || previousReveal?.caret != signature.caret
        || previousReveal?.selection != signature.selection || previousReveal?.markedRange != signature.markedRange
        || previousReveal?.isFocused != signature.isFocused
        || previousReveal?.contentTranslationY != signature.contentTranslationY
        || previousReveal?.viewportHeight != signature.viewportHeight
    state.revealSignature = signature
    if needsReveal {
        if node.isFocused, state.layout?.hasCompleteCaretGeometry == true {
            controller.requestEditorCaretReveal()
        } else {
            state.needsCaretReveal = false
            state.revealDeferrals = 0
        }
    } else if state.needsCaretReveal {
        controller.queueEditorCaretReveal()
    }
    guard state.renderSignature != signature || state.renderedContent !== content else { return }
    state.renderSignature = signature
    state.renderedContent = content
    guard let layout = state.layout else {
        if !content.children.isEmpty { content.removeAllChildren() }
        if content.preferredSize != .zero { content.preferredSize = .zero }
        return
    }

    var children: [ViewNode] = []
    if let selection = display.selection {
        for rect in layout.selectionRects(for: selection) {
            children.append(
                ViewNode(frame: state.translated(rect), backgroundColor: selectionColor, isHitTestVisible: false))
        }
    }
    for line in layout.lines where !line.text.isEmpty {
        var lineStyle = style
        lineStyle.alignment = .leading
        lineStyle.verticalAlignment = .top
        lineStyle.insets = .zero
        lineStyle.lineBreakMode = .clip
        lineStyle.maximumNumberOfLines = 1
        lineStyle.minimumNumberOfLines = nil
        lineStyle.reservesLineLimitSpace = false
        // The entire visual fragment shapes once. Caret, highlights, and
        // composition decorations never divide it into separate text runs.
        children.append(
            ViewNode(frame: state.translated(line.rect), text: line.text, textStyle: lineStyle, isHitTestVisible: false)
        )
    }
    if let markedRange = display.markedRange {
        let thickness = 1 / max(1, displayScale)
        for rect in layout.selectionRects(for: markedRange) where rect.size.width > 0 {
            children.append(
                ViewNode(
                    frame: state.translated(
                        Rect(x: rect.minX, y: rect.maxY - thickness, width: rect.size.width, height: thickness)),
                    backgroundColor: caretColor,
                    isHitTestVisible: false
                ))
        }
    }
    if node.isFocused, display.selection == nil,
        let caret = layout.caret(at: state.displayCaret)
    {
        let caretNode = ViewNode(
            frame: state.translated(
                Rect(x: caret.rect.minX, y: caret.rect.minY, width: 1.5, height: caret.rect.size.height)),
            backgroundColor: caretColor,
            isHitTestVisible: false
        )
        caretNode.isTextInputCaret = true
        children.append(caretNode)
    }
    let contentSize = Size(
        width: max(0, viewportWidth), height: max(0, layout.contentSize.height + max(0, state.contentTranslationY)))
    if content.preferredSize != contentSize { content.preferredSize = contentSize }
    content.absoluteChildFrame = { child, _ in child.frame }
    content.removeAllChildren()
    for child in children { content.addChild(child) }
}

/// Mutable bookkeeping for `updateTextInputEditingChrome` so repeated layout
/// passes only rebuild caret/selection overlay children when the editing
/// state actually changed (guards against layout/invalidate feedback loops).
private final class TextInputEditingChromeState {
    struct EditingState {
        var caret: Int
        var selection: RetainedTextSelection?
        var isFocused: Bool
        var markedText: String?
    }

    struct Signature: Equatable {
        var contentText: String
        var isShowingPlaceholder: Bool
        var isFocused: Bool
        var caret: Int
        var selectionLower: Int
        var selectionUpper: Int
        var isActive: Bool
        var markedText: String
    }

    var signature: Signature?
}
/// Display-space text state while an IME composition is active: the marked
/// (composition) text visually replaces the selection — or inserts at the
/// caret — and the caret moves to the end of the marked range. With no
/// marked text the inputs pass through unchanged, so the non-IME path is
/// byte-identical.
private func textInputCompositionDisplayState(
    contentText: String,
    caret: Int,
    selection: Range<Int>?,
    markedText: String?
) -> (text: String, caret: Int, selection: Range<Int>?, markedRange: Range<Int>?) {
    guard let markedText, !markedText.isEmpty else {
        return (contentText, caret, selection, nil)
    }

    let insertion = selection ?? caret..<caret
    let text = contentText.replacingText(in: insertion, with: markedText)
    let markedRange = insertion.lowerBound..<(insertion.lowerBound + markedText.count)
    return (text, markedRange.upperBound, nil, markedRange)
}
@MainActor
private func textFieldContentBelongsToRuntime(_ node: ViewNode, runtime: RetainedViewRuntime) -> Bool {
    guard runtime.root.parent == nil else { return false }
    var visited = Set<ObjectIdentifier>()
    var candidate: ViewNode? = node
    while let current = candidate, visited.insert(ObjectIdentifier(current)).inserted {
        if current === runtime.root { return true }
        guard let parent = current.parent, parent.children.contains(where: { $0 === current }) else { return false }
        candidate = parent
    }
    return false
}

@MainActor
private func queueTextFieldContentLayout(controller: TextInputInteractionController, content: ViewNode) {
    guard !controller.allowsNewlines, controller.current === controller, controller.isAttached,
        let node = controller.node, let runtime = controller.undoRuntime,
        runtime.isLayoutInProgress, runtime.permitsRetainedActionInvocation,
        content.parent === node, node.children.contains(where: { $0 === content }),
        textFieldContentBelongsToRuntime(node, runtime: runtime)
    else { return }
    // A live field can refresh without a body rebuild. Settle its changed
    // chrome through the existing bounded pass, without revealing a caret.
    runtime.scheduleAfterLayout(key: "text-field-content-layout-\(ObjectIdentifier(node))") {
        [weak controller, weak runtime, weak node, weak content] in
        guard let controller, let runtime, let node, let content,
            !controller.allowsNewlines, controller.current === controller, controller.node === node,
            controller.isAttached, controller.undoRuntime === runtime, runtime.permitsRetainedActionInvocation,
            content.parent === node, node.children.contains(where: { $0 === content }),
            textFieldContentBelongsToRuntime(node, runtime: runtime)
        else { return }
        runtime.invalidateTextInputLayout(for: node, controller: controller)
    }
}

/// Reconciles the children of a retained text input node so the visible
/// caret and selection highlight track the node's editing state. In the
/// inactive state the node keeps exactly its plain label child; in the
/// active state the label is hidden and replaced by per-line horizontal
/// segment rows (plain label segments, a tinted highlight segment, an
/// underlined IME marked segment, and a 1.5pt caret) so painting flows
/// through the regular scene/frame paths.
@MainActor
@discardableResult
private func updateTextInputEditingChrome(
    node: ViewNode,
    labelNode: ViewNode,
    contentText: String,
    isShowingPlaceholder: Bool,
    caretColor: Color,
    selectionColor: Color,
    caretSize: Size,
    markedText: String? = nil,
    state: TextInputEditingChromeState,
    editingState: TextInputEditingChromeState.EditingState? = nil,
    preparingDetachedCandidate: Bool = false,
    makeSegmentLabel: @MainActor (String) -> ViewNode,
    makeMarkedSegmentLabel: (@MainActor (String) -> ViewNode)? = nil
) -> ViewNode? {
    if preparingDetachedCandidate {
        guard node.children.count == 1, node.children.first === labelNode,
            labelNode.parent === node, labelNode.children.isEmpty
        else { return nil }
    }
    let editing =
        editingState
        ?? TextInputEditingChromeState.EditingState(
            caret: node.textInputCaretOffset, selection: node.textInputSelection,
            isFocused: node.isFocused, markedText: markedText)
    let baseSelection =
        isShowingPlaceholder ? nil : editing.selection?.editableCharacterRange(in: contentText)
    let baseCaret = clampedTextOffset(editing.caret, in: contentText)
    let display = textInputCompositionDisplayState(
        contentText: contentText,
        caret: baseCaret,
        selection: baseSelection,
        markedText: editing.markedText
    )
    let displayText = display.text
    let selection = display.selection
    let caret = display.caret
    let markedRange = display.markedRange
    let showsHighlight = selection != nil
    let showsCaret = editing.isFocused && selection == nil
    let isActive = showsCaret || showsHighlight || markedRange != nil
    let signature = TextInputEditingChromeState.Signature(
        contentText: contentText,
        isShowingPlaceholder: isShowingPlaceholder,
        isFocused: editing.isFocused,
        caret: caret,
        selectionLower: selection?.lowerBound ?? caret,
        selectionUpper: selection?.upperBound ?? caret,
        isActive: isActive,
        markedText: editing.markedText ?? ""
    )
    guard signature != state.signature else {
        return nil
    }
    state.signature = signature

    if !isActive {
        let visibilityChanged = labelNode.isHidden
        if visibilityChanged { labelNode.isHidden = false }
        guard node.children.count != 1 || node.children.first !== labelNode else {
            return visibilityChanged ? labelNode : nil
        }
        node.removeAllChildren()
        node.addChild(labelNode)
        return labelNode
    }

    @MainActor func makeCaretNode() -> ViewNode {
        let caretNode = ViewNode()
        caretNode.backgroundColor = caretColor
        caretNode.preferredSize = caretSize
        caretNode.isHitTestVisible = false
        // The runtime blinks it: NSTextInsertionIndicator is on ~0.5s, off
        // ~0.5s, and a steady caret is one of the fastest tells that a text
        // field is not a real system control.
        caretNode.isTextInputCaret = true
        return caretNode
    }
    // Short tinted tail visualizing a selected trailing newline.
    @MainActor func makeHighlightTail() -> ViewNode {
        let tail = ViewNode()
        tail.backgroundColor = selectionColor
        tail.preferredSize = Size(width: caretSize.width * 3, height: caretSize.height)
        tail.isHitTestVisible = false
        return tail
    }

    @MainActor func makeRow(line: String, lineLowerBound: Int, isCaretLine: Bool) -> ViewNode {
        let lineUpperBound = lineLowerBound + line.count
        var children: [ViewNode] = []

        let selectionInLine: Range<Int>? = selection.flatMap { range in
            let lower = max(range.lowerBound, lineLowerBound)
            let upper = min(range.upperBound, lineUpperBound)
            return lower < upper ? (lower - lineLowerBound)..<(upper - lineLowerBound) : nil
        }
        let selectionIncludesLineBreak =
            selection.map { $0.lowerBound <= lineUpperBound && $0.upperBound > lineUpperBound } ?? false
        let markedInLine: Range<Int>? = markedRange.flatMap { range in
            let lower = max(range.lowerBound, lineLowerBound)
            let upper = min(range.upperBound, lineUpperBound)
            return lower < upper ? (lower - lineLowerBound)..<(upper - lineLowerBound) : nil
        }

        if let markedInLine {
            // IME marked text: underlined segment, caret at its end.
            let pre = line.textSubstring(in: 0..<markedInLine.lowerBound)
            let marked = line.textSubstring(in: markedInLine)
            let post = line.textSubstring(in: markedInLine.upperBound..<line.count)
            if !pre.isEmpty {
                children.append(makeSegmentLabel(pre))
            }
            if let makeMarkedSegmentLabel {
                children.append(makeMarkedSegmentLabel(marked))
            } else {
                children.append(makeSegmentLabel(marked))
            }
            if isCaretLine {
                children.append(makeCaretNode())
            }
            if !post.isEmpty {
                children.append(makeSegmentLabel(post))
            }
        } else if let selectionInLine {
            let pre = line.textSubstring(in: 0..<selectionInLine.lowerBound)
            let highlighted = line.textSubstring(in: selectionInLine)
            let post = line.textSubstring(in: selectionInLine.upperBound..<line.count)
            if !pre.isEmpty {
                children.append(makeSegmentLabel(pre))
            }
            let highlightLabel = makeSegmentLabel(highlighted)
            highlightLabel.backgroundColor = selectionColor
            children.append(highlightLabel)
            if !post.isEmpty {
                children.append(makeSegmentLabel(post))
            }
        } else if isCaretLine {
            let caretColumn = caret - lineLowerBound
            let pre = line.textSubstring(in: 0..<caretColumn)
            let post = line.textSubstring(in: caretColumn..<line.count)
            if !pre.isEmpty {
                children.append(makeSegmentLabel(pre))
            }
            children.append(makeCaretNode())
            if !post.isEmpty {
                children.append(makeSegmentLabel(post))
            }
        } else {
            children.append(makeSegmentLabel(line))
        }
        if selectionIncludesLineBreak {
            children.append(makeHighlightTail())
        }

        return Controls.stackPanel(
            stackLayout: .horizontal(spacing: 0, padding: .zero, alignment: .center),
            isHitTestVisible: false,
            children: children
        )
    }

    var lineRanges: [Range<Int>] = []
    var lineStart = 0
    var offset = 0
    for character in displayText {
        if character == "\n" {
            lineRanges.append(lineStart..<offset)
            lineStart = offset + 1
        }
        offset += 1
    }
    lineRanges.append(lineStart..<offset)

    let caretLineIndex = lineRanges.lastIndex(where: { $0.lowerBound <= caret }) ?? 0
    let rows = lineRanges.enumerated().map { index, lineRange in
        makeRow(
            line: displayText.textSubstring(in: lineRange),
            lineLowerBound: lineRange.lowerBound,
            isCaretLine: showsCaret && index == caretLineIndex
        )
    }
    let contentNode: ViewNode
    if rows.count == 1, let row = rows.first {
        contentNode = row
    } else {
        contentNode = Controls.stackPanel(
            stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .leading),
            isHitTestVisible: false,
            children: rows
        )
    }

    labelNode.isHidden = true
    if !preparingDetachedCandidate {
        node.removeAllChildren()
        node.addChild(labelNode)
    }
    node.addChild(contentNode)
    return contentNode
}
/// Maps a root-space pointer point to a character offset in a retained text
/// input. Offsets stay in real-character space; secure fields measure their
/// masked display text, single-line inputs clamp to the first hard line, and
/// multi-line editors map y to hard line rows the same way
/// `updateTextInputEditingChrome` stacks them.
@MainActor
private func textInputOffset(
    atRootPoint point: Point,
    contentOrigin: Point,
    labelNode: ViewNode,
    text: String,
    isSecure: Bool,
    allowsNewlines: Bool,
    displayScale: Double
) -> Int {
    guard !text.isEmpty else {
        return 0
    }

    let displayText = isSecure ? String(repeating: secureFieldMaskCharacter, count: text.count) : text
    let localPoint = Point(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
    let lineRanges = textInputHardLineRanges(in: displayText)

    let row: Int
    if allowsNewlines, lineRanges.count > 1 {
        row = textInputLineRow(
            atY: localPoint.y,
            lineRanges: lineRanges,
            text: displayText,
            style: labelNode.textStyle,
            displayScale: displayScale
        )
    } else {
        row = 0
    }

    let lineRange = lineRanges[row]
    let line = displayText.textSubstring(in: lineRange)
    let column = RetainedTextMetrics.characterOffset(
        atX: localPoint.x,
        in: line,
        style: labelNode.textStyle,
        displayScale: displayScale
    )
    return lineRange.lowerBound + column
}
/// Pointer offsets and IME caret rectangles share the visible content's
/// placement. The source label is hidden while caret/selection chrome is
/// active, so its resolved frame is then zero and cannot locate the text.
/// Ancestor transforms are not accounted for.
@MainActor
private func textInputContentOrigin(
    controller: TextInputInteractionController,
    runtime: RetainedViewRuntime?
) -> Point? {
    guard controller.current === controller, let node = controller.node else { return nil }
    if controller.isAttached {
        guard let runtime else { return nil }
        // Resolving pending layout can replace an unfocused source label
        // with editing chrome. Reselect once, without recursively asking
        // layout to chase changes made by application callbacks.
        for _ in 0..<2 {
            guard controller.current === controller,
                let container = controller.allowsNewlines ? textEditorViewport(in: node) : node,
                let contentNode = container.children.first(where: { !$0.isHidden })
            else { return nil }
            if let frame = runtime.resolvedLayoutFrame(of: contentNode),
                controller.current === controller, contentNode.parent === container, !contentNode.isHidden,
                container === node || container.parent === node
            {
                return frame.origin
            }
        }
        return nil
    }

    // Component.makeNode does not attach the returned node. Callers using
    // those callbacks before attachment supply authored geometry and own
    // the runtime for the duration of the interaction.
    guard
        let contentNode = controller.allowsNewlines
            ? textEditorViewport(in: node)?.children.first : node.children.first
    else { return nil }
    var chain: [ViewNode] = []
    var current: ViewNode? = contentNode
    while let ancestor = current {
        chain.append(ancestor)
        current = ancestor.parent
    }

    var origin = Point(x: 0, y: 0)
    for (index, ancestor) in chain.reversed().enumerated() {
        origin = Point(x: origin.x + ancestor.frame.origin.x, y: origin.y + ancestor.frame.origin.y)
        guard index < chain.count - 1 else {
            continue
        }
        switch ancestor.scrollAxis {
        case .horizontal:
            origin.x -= ancestor.scrollOffset
        case .vertical:
            origin.y -= ancestor.scrollOffset
        case nil:
            break
        }
    }
    return origin
}
/// Hard line ranges (split on "\n") exactly as `updateTextInputEditingChrome`
/// computes them.
private func textInputHardLineRanges(in text: String) -> [Range<Int>] {
    var lineRanges: [Range<Int>] = []
    var lineStart = 0
    var offset = 0
    for character in text {
        if character == "\n" {
            lineRanges.append(lineStart..<offset)
            lineStart = offset + 1
        }
        offset += 1
    }
    lineRanges.append(lineStart..<offset)
    return lineRanges
}
/// Hard-line row whose vertical extent contains `y`, clamped to the
/// outermost rows. Row heights use the measured line-label heights the
/// editing chrome stacks from the content top; empty lines still occupy a
/// full line-height row there once the caret or selection reaches them.
@MainActor
private func textInputLineRow(
    atY y: Double,
    lineRanges: [Range<Int>],
    text: String,
    style: PixelTextStyle,
    displayScale: Double
) -> Int {
    var rowTop = 0.0
    var lastRow = 0
    for (index, lineRange) in lineRanges.enumerated() {
        let line = text.textSubstring(in: lineRange)
        let height = max(
            1,
            RetainedTextMetrics.size(
                of: line.isEmpty ? " " : line,
                style: style,
                displayScale: displayScale
            ).height
        )
        if y < rowTop + height {
            return index
        }
        rowTop += height
        lastRow = index
    }
    return lastRow
}
extension RetainedTextSelection {
    /// Non-empty character-offset range for single-range selections, clamped
    /// to `text`. Insertion points and multi-selections return nil.
    fileprivate func editableCharacterRange(in text: String) -> Range<Int>? {
        guard case .range(let range) = indices else {
            return nil
        }
        let lower = clampedTextOffset(range.lowerBound, in: text)
        let upper = clampedTextOffset(range.upperBound, in: text)
        guard lower < upper else {
            return nil
        }
        return lower..<upper
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
            let formattedValue = Self.formattedValue(
                selection.wrappedValue,
                components: displayedComponents,
                calendar: environmentValues.calendar,
                timeZone: environmentValues.timeZone,
                locale: environmentValues.locale
            )
            let valueNode = Text(formattedValue)
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
            if case .stepperField = datePickerStyle.kind {
                Self.configureStepperButtons(
                    on: controlNode,
                    selection: selection,
                    range: range,
                    components: displayedComponents,
                    calendar: interactionCalendar,
                    isEnabled: context.isEnabled,
                    invalidate: context.invalidate
                )
            }

            guard !context.labelsHidden, !labelViews.isEmpty else {
                let accessibilityLabel =
                    labelViews.isEmpty ? nil : firstRetainedText(in: labelComponent.makeNode(runtime: runtime))
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    range: range,
                    components: displayedComponents,
                    calendar: interactionCalendar,
                    isEnabled: context.isEnabled,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: formattedValue,
                    invalidate: context.invalidate
                )
                return controlNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            guard !context.isInsideGroupedForm else {
                // In a form row the stepper field is the control; the empty
                // rest of the value column is not a click target for it.
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    range: range,
                    components: displayedComponents,
                    calendar: interactionCalendar,
                    isEnabled: context.isEnabled,
                    accessibilityLabel: firstRetainedText(in: labelNode),
                    accessibilityValue: formattedValue,
                    invalidate: context.invalidate
                )
                return groupedFormRowNode(
                    label: labelNode,
                    content: controlNode,
                    isHitTestVisible: context.isEnabled
                )
            }
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
                accessibilityLabel: firstRetainedText(in: labelNode),
                accessibilityValue: formattedValue,
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
        let palette = context.controlPalette
        let fieldSurface = context.isEnabled ? palette.fieldSurface : palette.controlBackground
        let fieldBorder = context.isEnabled ? palette.controlBorder : palette.separator
        let secondaryLabel = context.isEnabled ? palette.secondaryLabel : palette.disabledLabel

        switch style.kind {
        case .automatic:
            return valueNode
        case .compact:
            let disclosureNode = Controls.icon(
                .chevronDown,
                preferredSize: Size(width: 14, height: 14),
                color: secondaryLabel,
                scale: 1.1,
                displayScale: context.iconRasterDisplayScale
            )
            return Controls.stackPanel(
                preferredSize: context.controlSize.singleLineTextInputSize,
                backgroundColor: fieldSurface,
                borderColor: fieldBorder,
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
                backgroundColor: fieldSurface,
                borderColor: fieldBorder,
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
                backgroundColor: context.isEnabled ? palette.controlSurface : palette.controlBackground,
                borderColor: fieldBorder,
                borderWidth: 1,
                cornerRadius: 4,
                stackLayout: .vertical(
                    spacing: 0,
                    padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0),
                    alignment: .center
                ),
                isHitTestVisible: false,
                children: [
                    Controls.label("+", color: secondaryLabel, scale: 1.0),
                    Controls.label("-", color: secondaryLabel, scale: 1.0),
                ]
            )
            return Controls.stackPanel(
                preferredSize: Size(
                    width: context.controlSize.singleLineTextInputSize.width + 30,
                    height: context.controlSize.singleLineTextInputSize.height
                ),
                backgroundColor: fieldSurface,
                borderColor: fieldBorder,
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
            let guideColor = context.isEnabled ? palette.separator : palette.quaternaryFill
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
                backgroundColor: fieldSurface,
                borderColor: fieldBorder,
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
                backgroundColor: context.isEnabled ? palette.tertiaryFill : palette.quinaryFill,
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
                            : context.isEnabled ? palette.systemFill : palette.quaternaryFill,
                        cornerRadius: 3,
                        isHitTestVisible: false
                    )
                }
            )
            return Controls.stackPanel(
                preferredSize: Size(width: context.controlSize.singleLineTextInputSize.width, height: 78),
                backgroundColor: context.isEnabled ? palette.raisedSurface : palette.controlBackground,
                borderColor: fieldBorder,
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
        accessibilityLabel: String?,
        accessibilityValue: String,
        invalidate: @escaping () -> Void
    ) {
        node.accessibilityLabel = accessibilityLabel
        node.accessibilityValue = accessibilityValue
        node.accessibilityRespondsToUserInteraction = isEnabled

        guard isEnabled else {
            return
        }

        node.isFocusable = true
        node.isHitTestVisible = true
        node.interceptsVerticalArrowKeys = true
        node.accessibilityActions.append(
            RetainedAccessibilityAction(name: "Increment", kind: .increment) {
                Self.adjustSelection(
                    selection,
                    direction: 1,
                    range: range,
                    components: components,
                    calendar: calendar,
                    invalidate: invalidate
                )
            }
        )
        node.accessibilityActions.append(
            RetainedAccessibilityAction(name: "Decrement", kind: .decrement) {
                Self.adjustSelection(
                    selection,
                    direction: -1,
                    range: range,
                    components: components,
                    calendar: calendar,
                    invalidate: invalidate
                )
            }
        )
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

            Self.adjustSelection(
                selection,
                direction: direction,
                range: range,
                components: components,
                calendar: calendar,
                invalidate: invalidate
            )
        }
    }

    private static func configureStepperButtons(
        on control: ViewNode,
        selection: Binding<Date>,
        range: DatePickerRange,
        components: DatePickerComponents,
        calendar: Calendar,
        isEnabled: Bool,
        invalidate: @escaping () -> Void
    ) {
        guard let buttons = control.children.last?.children, buttons.count == 2 else {
            return
        }

        for (index, button) in buttons.enumerated() {
            let direction = index == 0 ? 1 : -1
            let canAdjust =
                isEnabled
                && steppedDate(
                    from: selection.wrappedValue,
                    direction: direction,
                    components: components,
                    calendar: calendar
                ).map(range.contains) == true
            button.accessibilityLabel = direction > 0 ? "Increment" : "Decrement"
            button.accessibilityTraits.formUnion(.isButton)
            button.accessibilityRespondsToUserInteraction = canAdjust
            button.isFocusable = canAdjust
            button.isHitTestVisible = canAdjust

            guard canAdjust else {
                continue
            }

            button.onActivate = {
                Self.adjustSelection(
                    selection,
                    direction: direction,
                    range: range,
                    components: components,
                    calendar: calendar,
                    invalidate: invalidate
                )
            }
            button.onRepeatActivate = button.onActivate
            button.buttonRepeatBehavior = .enabled
        }
    }

    private static func adjustSelection(
        _ selection: Binding<Date>,
        direction: Int,
        range: DatePickerRange,
        components: DatePickerComponents,
        calendar: Calendar,
        invalidate: @escaping () -> Void
    ) {
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
        // A colour picker's label is a row label like any other. Forcing it
        // to `.secondary` made "Accent Color" render dimmer than every
        // sibling row in an otherwise uniform Form.
        let labelComponent = composeComponent(
            from: labelViews,
            context:
                context
                .withTextAlignment(.leading)
                .withLineLimit(1),
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)),
            isHitTestVisible: false
        )

        return Component { runtime in
            let color = selection.wrappedValue
            let palette = context.controlPalette
            // NSColorWell: a *bordered control* that happens to be filled
            // with the selection — a bezel in the control-surface tone with
            // the swatch inset inside it, and *no* hex readout (the 8-digit
            // RGBA string this used to print beside it is developer-facing
            // text macOS never shows).
            //
            // The bezel is built as a button because that is what a colour
            // well is: it carries the pointer ramp (hover lightens the bezel
            // and strengthens its ring, pressing it darkens) that a bare
            // panel had no way to express, which is why the well used to read
            // as an inert rectangle of accent colour.
            let inset = MacOSControlMetrics.ColorWell.swatchInset
            // One activation for the whole control. The bezel is the node a
            // click actually lands on — activation does not bubble in the
            // retained runtime, `pointerUp` fires the *pressed* node's own
            // `onActivate` — and the row around it is the focus stop and the
            // label's target. Two constructions of "what a colour well does"
            // is two things that can drift.
            let usesNativeDialog = context.environmentValues.colorPickerUsesNativeDialog
            let invalidate = context.invalidate
            let activate: () -> Void = {
                if usesNativeDialog {
                    if let chosen = ColorDialogManager.chooseColor(initial: selection.wrappedValue) {
                        selection.wrappedValue = chosen
                        invalidate()
                    }
                } else {
                    Self.applyPaletteStep(
                        to: selection,
                        direction: 1,
                        supportsOpacity: supportsOpacity,
                        invalidate: invalidate
                    )
                }
            }
            let wellFill = Controls.panel(
                backgroundColor: color,
                cornerRadius: MacOSControlMetrics.ColorWell.swatchCornerRadius,
                isHitTestVisible: false
            )
            // The well fills the gutter the bezel leaves it.
            wellFill.layoutFillAxes = .both
            let swatchNode = Controls.button(
                runtime: runtime,
                preferredSize: context.controlSize.colorSwatchPreferredSize,
                cornerRadius: MacOSControlMetrics.ColorWell.cornerRadius,
                palette: palette.borderedButtonPalette,
                chrome: palette.buttonChrome(focusTint: context.tint, casts: false),
                clipsToBounds: true,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset),
                        alignment: .stretch,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled,
                appliesSurfaceSheen: true,
                action: context.isEnabled ? activate : nil,
                children: [wellFill]
            )
            // The focus stop and the key handling stay on the control row
            // (`configureInteraction`): a colour well is one tab stop, not a
            // row and a bezel inside it.
            swatchNode.isFocusable = false
            let controlNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: context.isEnabled,
                children: [swatchNode]
            )
            // The hex string is still the well's accessible value — it just
            // is not painted next to it.
            controlNode.accessibilityValue = Self.hexValue(color, includesOpacity: supportsOpacity)

            guard !context.labelsHidden, !labelViews.isEmpty else {
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    supportsOpacity: supportsOpacity,
                    isEnabled: context.isEnabled,
                    activate: activate,
                    invalidate: invalidate
                )
                return controlNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            labelNode.layoutPriority = max(labelNode.layoutPriority, 1)
            guard !context.isInsideGroupedForm else {
                // In a form row the well is the control; the empty rest of
                // the value column is not a click target for it.
                Self.configureInteraction(
                    on: controlNode,
                    selection: selection,
                    supportsOpacity: supportsOpacity,
                    isEnabled: context.isEnabled,
                    activate: activate,
                    invalidate: invalidate
                )
                return groupedFormRowNode(
                    label: labelNode,
                    content: controlNode,
                    isHitTestVisible: context.isEnabled
                )
            }
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
                activate: activate,
                invalidate: invalidate
            )
            return node
        }
    }

    private static func configureInteraction(
        on node: ViewNode,
        selection: Binding<Color>,
        supportsOpacity: Bool,
        isEnabled: Bool,
        activate: @escaping () -> Void,
        invalidate: @escaping () -> Void
    ) {
        guard isEnabled else {
            return
        }

        node.isFocusable = true
        node.isHitTestVisible = true
        node.onActivate = activate
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
        let palette = context.controlPalette
        let trackSize = context.controlSize.togglePreferredSize
        let toggleNode = Controls.toggle(
            runtime: runtime,
            isOn: binding.wrappedValue,
            isEnabled: context.isEnabled,
            // The node is the pointer target; the track floats inside it with
            // a gutter, so the switch the user sees is `trackSize`, not this.
            preferredSize: Size(width: trackSize.width + 8, height: trackSize.height + 8),
            trackSize: trackSize,
            knobDiameter: MacOSControlMetrics.Toggle.knobDiameter,
            knobInset: MacOSControlMetrics.Toggle.knobInset,
            // On is the accent as an opaque *fill* — the same hex in both
            // appearances, because a filled track has no appearance behind
            // it to vary with.
            onColor: ControlPalette.opaque(context.tint),
            offColor: palette.controlTrack,
            knobShadowColor: Elevation.e1.color(for: palette.colorScheme),
            offTrackBorderColor: palette.controlBorder,
            // The plate behind the switch. `Controls.toggle`'s retained
            // default paints an opaque pale blue (#B8D1EB) on pointer-down
            // and a slate one on hover — hand-tuned literals from before
            // there was an appearance to resolve against, and the same two
            // colours in light mode as in dark. With the geometric press
            // scale gone (E6-PRESS) this plate *is* the switch's press
            // affordance, so it comes off the appearance's own fill ramp: a
            // rung softer than a bezel takes, because this is a halo around
            // the switch and not the switch's own surface.
            palette: SurfacePalette(
                idle: .clear,
                hovered: palette.quaternaryFill,
                focused: palette.quaternaryFill,
                pressed: palette.secondaryFill
            ),
            onToggle: { newValue in
                binding.wrappedValue = newValue
                context.invalidate()
            }
        )

        guard !context.labelsHidden else {
            return toggleNode
        }

        let labelNode = labelComponent.makeNode(runtime: runtime)
        // Default accessibility name from the label content; an explicit
        // accessibilityLabel modifier applies after this and wins. The
        // retained toggle builder already applied isButton (+ isSelected
        // when on).
        toggleNode.accessibilityLabel = firstRetainedText(in: labelNode)
        guard !context.isInsideGroupedForm else {
            return groupedFormRowNode(label: labelNode, content: toggleNode)
        }
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
        // 18×18 at `Radius.sm`. Off is *transparent* closed by the strong
        // hairline — an unchecked box is an outline, not a filled plate —
        // and on is the accent as an opaque fill under a white check.
        let palette = context.controlPalette
        let boxSize: Double = 18
        let glyphSize: Double = 12
        let surfaceStyle = ButtonSurfaceStyle.default
        let checkIcon =
            binding.wrappedValue
            ? Controls.icon(
                .checkmark,
                preferredSize: Size(width: glyphSize, height: glyphSize),
                color: context.isEnabled ? palette.selectedContentLabel : surfaceStyle.palette.disabledForeground,
                scale: 1.2,
                displayScale: context.iconRasterDisplayScale
            )
            : Controls.panel(
                preferredSize: Size(width: glyphSize, height: glyphSize),
                isHitTestVisible: false
            )
        let box = Controls.panel(
            preferredSize: Size(width: boxSize, height: boxSize),
            backgroundColor: context.isEnabled
                ? (binding.wrappedValue ? ControlPalette.opaque(context.tint) : .clear)
                : surfaceStyle.palette.disabledBackground,
            borderColor: context.isEnabled
                ? (binding.wrappedValue ? ControlPalette.opaque(context.tint) : palette.controlBorderStrong)
                : surfaceStyle.palette.disabledBorder,
            borderWidth: 1,
            cornerRadius: MacOSControlMetrics.Radius.sm,
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

        let node = Controls.button(
            runtime: runtime,
            preferredSize: context.labelsHidden ? hiddenPreferredSize : nil,
            cornerRadius: MacOSControlMetrics.Radius.sm,
            // The plate behind the box carries the pointer ramp off the
            // appearance's own fill ladder. The four literals it used to
            // hold (`0.24, 0.32, 0.42` and friends) were blue-cast washes
            // from before there was an appearance to resolve against.
            palette: SurfacePalette(
                idle: .clear,
                hovered: palette.quaternaryFill,
                focused: palette.quaternaryFill,
                pressed: palette.secondaryFill
            ),
            chrome: SurfaceChrome(
                borderColor: .clear,
                borderHoveredColor: .clear,
                borderFocusedColor: .clear,
                borderPressedColor: .clear,
                borderWidth: 0,
                focusRingColor: palette.accentRing,
                focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth
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
        // Checkbox-style toggles carry the isToggle trait (maps to the UIA
        // checkBox control type) and project their on state as isSelected.
        node.accessibilityTraits.formUnion(.isToggle)
        if binding.wrappedValue {
            node.accessibilityTraits.formUnion(.isSelected)
        }
        return node
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
                pressed: context.tint
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
                    scale: 1.25,
                    displayScale: context.iconRasterDisplayScale
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

        let node = Controls.button(
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
            appliesSurfaceSheen: true,
            action: {
                binding.wrappedValue.toggle()
                context.invalidate()
            },
            children: children
        )
        // Button-style toggles carry the isToggle trait (maps to the UIA
        // checkBox control type) and project their on state as isSelected.
        node.accessibilityTraits.formUnion(.isToggle)
        if binding.wrappedValue {
            node.accessibilityTraits.formUnion(.isSelected)
        }
        return node
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
                guard !context.isInsideGroupedForm else {
                    return groupedFormRowNode(label: labelNode, content: pickerNode)
                }
                let node = Controls.stackPanel(
                    stackLayout: .vertical(spacing: 8, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [labelNode, pickerNode]
                )
                node.explicitFrameFillAxes = pickerNode.explicitFrameFillAxes
                return node
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
            let node = Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [headerNode, pickerNode]
            )
            node.explicitFrameFillAxes = pickerNode.explicitFrameFillAxes
            return node
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
        // A segment label is single-line and never wraps — that much is
        // NSSegmentedControl. It is *not* a different size from the rest of
        // the app: the size ceiling that used to live here (scale <= 1.3,
        // native size <= 13) was a workaround for an ambient body of 17px
        // starving the 22pt track, and it meant a picker could never
        // participate in the type ramp. With body at 13pt the segment
        // inherits like every other control label.
        //
        // Label colour comes from the appearance palette. The selected
        // label used to be near-black on a near-white pill in *both*
        // appearances - that is the light-mode NSSegmentedControl dropped
        // into a dark app; dark mode raises a grey pill under a white
        // label instead.
        let palette = context.controlPalette
        for option in options {
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let isEnabled = context.isEnabled && option.value != nil
            guard option.node.text != nil else {
                continue
            }
            var style = option.node.textStyle
            style.maximumNumberOfLines = 1
            style.lineBreakMode = .truncateTail
            // An NSSegmentedControl centres its title *in the segment cell*.
            // The title used to be centred by the segment's stack instead,
            // which left the text box exactly as wide as the string.
            //
            // That is the right cell either way, but it arrived as a
            // workaround: a pressed segment used to be drawn at 0.97 and the
            // painter re-fitted its label to the scaled box, so "Three" in a
            // 33pt box became "Thr…" for as long as the pointer was down, and
            // the headroom this bought was the only thing holding it back.
            // Two later changes each removed that independently — E6-TEXT
            // lays a run out in the node's own space and scales the finished
            // cells, and E6-PRESS took the shrink off macOS-parity controls
            // altogether, since an NSSegmentedControl answers a press by
            // darkening the segment and not by moving it. The centring stays
            // because it is what the control does.
            style.alignment = .center
            style.color =
                isEnabled
                ? (isSelected ? palette.segmentedSelectedLabel : palette.label)
                : palette.disabledLabel
            option.node.textStyle = style
            option.node.layoutFillAxes = .horizontalOnly
        }

        // NSSegmentedControl, regular size: the track is
        // `MacOSControlMetrics.PopUpButton.regularHeight` tall. The segment
        // padding is what is left over around the tallest label rather than
        // a hard-coded 2pt, so the control keeps its macOS height at any
        // label metric — and still compresses when a parent squeezes it,
        // because the pill clips its own bounds.
        let segmentLabelHeight = options.map { Self.segmentLabelHeight(of: $0.node) }.max() ?? 0
        // The pill is inset from the track by whatever is left over around
        // the tallest label — down to 1pt, which is NSSegmentedControl's own
        // inset. A 2pt floor here forced the track to 24 the moment the
        // label stopped being clamped to 13px, which is the wrong end to
        // absorb it: the *control* height is the pinned value.
        let segmentVerticalPadding = max(
            1,
            (MacOSControlMetrics.PopUpButton.regularHeight - 2 * Self.segmentedTrackVerticalPadding
                - segmentLabelHeight) / 2
        )
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let isEnabled = context.isEnabled && option.value != nil

            // Selected segment: raised light pill with a soft shadow (the
            // standard button sheen supplies the top-lighter gradient).
            // Unselected: transparent over the recessed track, brightening
            // on hover/press.
            let segmentPalette =
                isSelected
                ? SurfacePalette(
                    idle: palette.segmentedSelectedFill,
                    hovered: ControlPalette.lightened(palette.segmentedSelectedFill, by: 0.08),
                    focused: ControlPalette.lightened(palette.segmentedSelectedFill, by: 0.08),
                    pressed: ControlPalette.darkened(palette.segmentedSelectedFill, by: 0.10),
                    disabledForeground: palette.disabledLabel
                )
                : SurfacePalette(
                    idle: .clear,
                    hovered: palette.quaternaryFill,
                    focused: palette.quaternaryFill,
                    // An unselected segment used to press to `tertiaryFill`,
                    // one rung above its own hover: a 10/255 step on the
                    // track, where a third of what the eye actually read was
                    // the whole segment shrinking to 0.97. With the shrink
                    // gone (E6-PRESS) the fill is the entire affordance, and
                    // `systemFill` is the rung macOS presses a segment to.
                    pressed: palette.systemFill,
                    disabledForeground: palette.disabledLabel
                )

            return Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: MacOSControlMetrics.Button.smallCornerRadius,
                palette: segmentPalette,
                chrome: SurfaceChrome(
                    // The selected pill is one quiet tonal step above its own
                    // track plus a contact shadow — but a contact shadow on a
                    // near-black page is invisible, so on the dark side the
                    // *hairline* is what carries the lift. Structure is
                    // carried by the hairline; that is the rule the rest of
                    // the system follows and there is no reason a segmented
                    // pill should be the exception. The `controlBorder` it
                    // used to take (white @ 0.09) was not enough edge to tell
                    // a selected segment from an unselected one at a glance.
                    borderColor: isSelected ? palette.controlBorderStrong : .clear,
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: palette.accentRing,
                    focusRingWidth: MacOSControlMetrics.FocusRing.strokeWidth,
                    shadowColor: isSelected ? Elevation.e1.color(for: palette.colorScheme) : .clear,
                    shadowPressedColor: .clear,
                    shadowOffset: Point(x: 0, y: Elevation.e1.light.offsetY),
                    shadowSpread: Elevation.e1.light.radius
                ),
                clipsToBounds: true,
                layoutMode: .stack(
                    .vertical(
                        padding: EdgeInsets(
                            top: segmentVerticalPadding,
                            leading: 10,
                            bottom: segmentVerticalPadding,
                            trailing: 10
                        ),
                        alignment: .center,
                        mainAlignment: .center
                    )),
                isEnabled: isEnabled,
                appliesSurfaceSheen: true,
                action: option.value.map { value in
                    {
                        selection.wrappedValue = value
                        context.invalidate()
                    }
                },
                children: [option.node]
            )
        }

        // macOS segmented controls give every segment the same width: the
        // widest intrinsic label sets the common base width, then the
        // track's slack is shared equally on top. Without the common base,
        // segments got equal slack over unequal text widths (wave-2
        // geometry audit) and the pills rendered unequal.
        if let commonSegmentWidth = optionNodes.map({ $0.intrinsicContentSize().width }).max(),
            commonSegmentWidth > 0
        {
            for optionNode in optionNodes {
                optionNode.preferredSize = Size(width: commonSegmentWidth, height: 0)
            }
        }

        // Recessed track: top-darker gradient reads as an inset groove the
        // raised selected pill sits in. Track padding/spacing stay at the
        // pinned 4pt geometry.
        let trackColor = palette.segmentedTrackFill
        let track = Controls.stackPanel(
            backgroundColor: trackColor,
            backgroundGradient: .linear(
                SwiftWindowsGraphics.LinearGradient(
                    startColor: Controls.shaded(trackColor, by: Controls.grooveSheenFactor),
                    endColor: trackColor)),
            borderColor: palette.separator,
            borderWidth: 1,
            cornerRadius: MacOSControlMetrics.Button.regularCornerRadius,
            clipsToBounds: true,
            stackLayout: .horizontal(
                spacing: 4,
                padding: EdgeInsets(
                    top: Self.segmentedTrackVerticalPadding,
                    leading: 4,
                    bottom: Self.segmentedTrackVerticalPadding,
                    trailing: 4
                ),
                alignment: .stretch,
                distribution: .fillEqually
            ),
            isHitTestVisible: false,
            children: optionNodes
        )
        // An NSSegmentedControl is *intrinsically* sized: equal segments,
        // each as wide as the widest label, and it only stretches when
        // something explicitly asks it to (a `.frame(width:)`, a stretching
        // container). Declaring the track greedy made it take whatever it
        // was offered, which is how a three-segment "System / Light / Dark"
        // picker came to be 1215pt wide in a settings pane. The equal-width
        // pass above is what keeps the segments equal at intrinsic size;
        // `.fillEqually` keeps them equal when a container does stretch it.
        track.explicitFrameFillAxes = .horizontalOnly
        return track
    }

    /// Interior padding above and below the segment pills.
    private static var segmentedTrackVerticalPadding: Double { 2 }

    /// Line box of a segment's label, used to derive the segment padding
    /// that lands the track on the macOS control height.
    @MainActor
    private static func segmentLabelHeight(of node: ViewNode) -> Double {
        node.intrinsicContentSize().height
    }

    private static func inlinePickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let appearance = context.controlPalette
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let indicatorNode =
                isSelected
                ? Controls.icon(
                    .checkmark,
                    preferredSize: Size(width: 18, height: 18),
                    color: context.isEnabled ? appearance.accentInk(for: context.tint) : appearance.disabledLabel,
                    scale: 1.2,
                    displayScale: context.iconRasterDisplayScale
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
                        ? appearance.listSelectionBackground(tint: context.tint)
                        : .clear,
                    hovered: isSelected
                        ? context.tint.opacity(appearance.isDark ? 0.24 : 0.18)
                        : appearance.tertiaryFill,
                    focused: isSelected
                        ? context.tint.opacity(appearance.isDark ? 0.28 : 0.20)
                        : appearance.secondaryFill,
                    pressed: isSelected
                        ? context.tint.opacity(appearance.isDark ? 0.34 : 0.24)
                        : appearance.systemFill,
                    disabledBackground: appearance.quinaryFill,
                    disabledForeground: appearance.disabledLabel,
                    disabledBorder: appearance.separator
                ),
                chrome: SurfaceChrome(
                    borderColor: isSelected ? appearance.controlBorderStrong : .clear,
                    borderHoveredColor: isSelected
                        ? appearance.controlBorderStrong : appearance.controlBorder,
                    borderFocusedColor: appearance.controlBorderStrong,
                    borderPressedColor: appearance.controlBorderStrong,
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: appearance.accentInk(for: context.tint).opacity(0.45),
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
            backgroundColor: appearance.controlBackground,
            borderColor: appearance.controlBorder,
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

        let dropdown = Controls.dropdown(
            runtime: runtime,
            options: titles,
            selectedIndex: selectedIndex,
            isEnabled: context.isEnabled && hasSelectableOption,
            preferredSize: Size(
                width: context.controlSize.pickerMenuPreferredSize.width + 24,
                height: context.controlSize.pickerMenuPreferredSize.height + 4
            ),
            palette: context.controlPalette.borderedButtonPalette,
            chrome: context.controlPalette.buttonChrome(focusTint: context.tint),
            onSelect: { index in
                guard options.indices.contains(index), let value = options[index].value else {
                    return
                }

                selection.wrappedValue = value
                context.invalidate()
            }
        )
        Self.applyDropdownAppearance(to: dropdown, selectedIndex: selectedIndex, context: context)
        return dropdown
    }

    private static func palettePickerNode(
        runtime: RetainedViewRuntime,
        context: ViewBuildContext,
        selection: Binding<SelectionValue>,
        selectedAnyValue: AnyHashable,
        options: [Option]
    ) -> ViewNode {
        let appearance = context.controlPalette
        let itemHeight = context.controlSize.pickerMenuPreferredSize.height
        let itemSize = Size(width: max(44, itemHeight * 1.45), height: itemHeight)
        let optionNodes: [ViewNode] = options.map { option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let palette =
                isSelected
                ? selectedPalette(tint: context.tint, appearance: appearance)
                : unselectedPalette(appearance: appearance)
            if option.node.text != nil {
                option.node.textStyle.color =
                    context.isEnabled
                    ? (isSelected ? appearance.selectedContentLabel : appearance.label)
                    : appearance.disabledLabel
            }
            return Controls.button(
                runtime: runtime,
                preferredSize: itemSize,
                layoutPriority: 1,
                cornerRadius: 10,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected
                        ? appearance.controlBorderStrong : appearance.controlBorder,
                    borderHoveredColor: appearance.controlBorderStrong,
                    borderFocusedColor: appearance.controlBorderStrong,
                    borderPressedColor: appearance.controlBorderStrong,
                    borderWidth: isSelected ? 2 : 1,
                    focusRingColor: appearance.accentInk(for: context.tint).opacity(0.45),
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
            backgroundColor: appearance.controlBackground,
            borderColor: appearance.controlBorder,
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
        let appearance = context.controlPalette
        let itemHeight = max(1, Double(context.environmentValues.defaultWheelPickerItemHeight))
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let title = firstText(in: option.node) ?? "OPTION \(index + 1)"
            let palette =
                isSelected
                ? selectedPalette(tint: context.tint, appearance: appearance)
                : unselectedPalette(appearance: appearance)
            let optionNode = Controls.button(
                runtime: runtime,
                layoutPriority: 1,
                cornerRadius: 8,
                palette: palette,
                chrome: SurfaceChrome(
                    borderColor: isSelected ? appearance.controlBorderStrong : .clear,
                    borderHoveredColor: isSelected
                        ? appearance.controlBorderStrong : appearance.controlBorder,
                    borderFocusedColor: appearance.controlBorderStrong,
                    borderPressedColor: appearance.controlBorderStrong,
                    borderWidth: isSelected ? 1 : 0,
                    focusRingColor: appearance.accentInk(for: context.tint).opacity(0.45),
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
                        color: context.isEnabled
                            ? (isSelected ? appearance.selectedContentLabel : appearance.secondaryLabel)
                            : appearance.disabledLabel,
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
            backgroundColor: appearance.controlBackground,
            borderColor: appearance.controlBorder,
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
        let appearance = context.controlPalette
        let optionNodes: [ViewNode] = options.enumerated().map { index, option in
            let isSelected = option.value.map { AnyHashable($0) == selectedAnyValue } ?? false
            let title = firstText(in: option.node) ?? "OPTION \(index + 1)"
            let radioButton = Controls.radioButton(
                runtime: runtime,
                label: title,
                isSelected: isSelected,
                isEnabled: context.isEnabled && option.value != nil,
                layoutPriority: 1,
                palette: appearance.borderedButtonPalette,
                chrome: SurfaceChrome(
                    borderColor: isSelected
                        ? appearance.controlBorderStrong : appearance.controlBorder,
                    borderHoveredColor: appearance.controlBorderStrong,
                    borderFocusedColor: appearance.controlBorderStrong,
                    borderPressedColor: appearance.controlBorderStrong,
                    borderWidth: 1,
                    focusRingColor: appearance.accentInk(for: context.tint).opacity(0.45),
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
            radioButton.children.last?.textStyle.color =
                context.isEnabled && option.value != nil ? appearance.label : appearance.disabledLabel
            return radioButton
        }

        return Controls.stackPanel(
            backgroundColor: appearance.controlBackground,
            borderColor: appearance.controlBorder,
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

        let dropdown = Controls.dropdown(
            runtime: runtime,
            options: titles,
            selectedIndex: selectedIndex,
            isEnabled: context.isEnabled && hasSelectableOption,
            preferredSize: context.controlSize.pickerMenuPreferredSize,
            palette: context.controlPalette.borderedButtonPalette,
            chrome: context.controlPalette.buttonChrome(focusTint: context.tint),
            onSelect: { index in
                guard options.indices.contains(index), let value = options[index].value else {
                    return
                }

                selection.wrappedValue = value
                context.invalidate()
            }
        )
        Self.applyDropdownAppearance(to: dropdown, selectedIndex: selectedIndex, context: context)
        return dropdown
    }

    private static func applyDropdownAppearance(
        to dropdown: ViewNode,
        selectedIndex: Int,
        context: ViewBuildContext
    ) {
        let appearance = context.controlPalette
        let labelColor = context.isEnabled ? appearance.label : appearance.disabledLabel

        if let header = dropdown.children.first {
            header.children.first?.textStyle.color = labelColor
            if header.children.count > 1 {
                header.replaceChild(
                    at: 1,
                    with: Controls.icon(
                        .chevronDown,
                        preferredSize: Size(width: 16, height: 16),
                        color: context.isEnabled ? appearance.secondaryLabel : appearance.disabledLabel,
                        scale: 1.2,
                        displayScale: context.iconRasterDisplayScale
                    )
                )
            }
        }

        guard dropdown.children.count > 1 else {
            return
        }

        let optionsList = dropdown.children[1]
        optionsList.backgroundColor = appearance.elevatedSurface
        optionsList.borderColor = appearance.elevatedSurfaceBorder

        for (index, option) in optionsList.children.enumerated() {
            let isSelected = index == selectedIndex
            let idleColor =
                isSelected && context.isEnabled
                ? appearance.selectedContentBackground(tint: context.tint)
                : .clear
            option.backgroundColor = idleColor
            option.backgroundGradient = nil
            option.borderGradient = nil
            option.children.first?.textStyle.color =
                context.isEnabled
                ? (isSelected ? appearance.selectedContentLabel : appearance.label)
                : appearance.disabledLabel

            if var surface = option.interactionSurface {
                surface.idleBackground = idleColor
                surface.hoveredBackground =
                    isSelected ? appearance.accentHovered(context.tint) : appearance.tertiaryFill
                surface.focusedBackground =
                    isSelected ? appearance.accentHovered(context.tint) : appearance.secondaryFill
                surface.pressedBackground =
                    isSelected ? appearance.accentPressed(context.tint) : appearance.systemFill
                surface.appliesSurfaceSheen = false
                option.interactionSurface = surface
            }
        }
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

    private static func selectedPalette(tint: Color, appearance: ControlPalette) -> SurfacePalette {
        appearance.prominentPalette(tint: tint)
    }

    private static func unselectedPalette(appearance: ControlPalette) -> SurfacePalette {
        appearance.borderedButtonPalette
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
            // NSStepper is a *vertical* joined pair inside ONE bezel: an up
            // arrow above a down arrow, split by a hairline, beside the
            // field. The side-by-side "-"/"+" pair this used to draw is the
            // iOS UIStepper form factor; two separately-ringed buttons stacked
            // flush is the other failure — the seam then carries two adjacent
            // 1pt rings that cancel into a flat box with no divider at all.
            //
            // So the ring lives on the bezel (the painter re-draws a parent's
            // ring after its children, so the halves may fill it edge to edge)
            // and the seam is a real filled hairline node.
            let palette = context.controlPalette
            let halfSize = context.controlSize.stepperButtonPreferredSize
            let outerRadius = MacOSControlMetrics.Stepper.cornerRadius
            let hairline = retainedHairlineThickness(for: context)
            let incrementNode = Self.controlButton(
                runtime: runtime,
                icon: .chevronUp,
                accessibilityName: "Increment",
                isEnabled: context.isEnabled && canIncrement(),
                preferredSize: halfSize,
                palette: palette,
                iconDisplayScale: context.iconRasterDisplayScale,
                bitmapFontAttribution: context.bitmapFontAttribution,
                cornerRadii: RetainedCornerRadii(topLeft: outerRadius, topRight: outerRadius),
                action: {
                    increment()
                    context.invalidate()
                }
            )
            let decrementNode = Self.controlButton(
                runtime: runtime,
                icon: .chevronDown,
                accessibilityName: "Decrement",
                isEnabled: context.isEnabled && canDecrement(),
                preferredSize: halfSize,
                palette: palette,
                iconDisplayScale: context.iconRasterDisplayScale,
                bitmapFontAttribution: context.bitmapFontAttribution,
                cornerRadii: RetainedCornerRadii(bottomRight: outerRadius, bottomLeft: outerRadius),
                action: {
                    decrement()
                    context.invalidate()
                }
            )
            let dividerNode = Controls.panel(
                preferredSize: Size(width: 0, height: hairline),
                backgroundColor: palette.controlBorder,
                isHitTestVisible: false
            )
            dividerNode.layoutFillAxes = .horizontalOnly
            dividerNode.isSeparatorRule = true
            let stepperNode = Controls.panel(
                preferredSize: Size(
                    width: halfSize.width,
                    height: halfSize.height * 2 + hairline
                ),
                borderColor: palette.controlBorder,
                borderWidth: 1,
                cornerRadius: outerRadius,
                layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
                isHitTestVisible: false,
                children: [incrementNode, dividerNode, decrementNode]
            )

            guard !context.labelsHidden else {
                return stepperNode
            }

            let labelNode = labelComponent.makeNode(runtime: runtime)
            guard !context.isInsideGroupedForm else {
                return groupedFormRowNode(label: labelNode, content: stepperNode)
            }
            // The bezel sits flush as a joined pair; the label keeps the
            // 8pt gap the separate pills used to provide.
            let labelSlot = Controls.panel(
                layoutMode: .stack(
                    .horizontal(
                        padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 8),
                        alignment: .center
                    )),
                isHitTestVisible: false,
                children: [labelNode]
            )
            return Controls.stackPanel(
                stackLayout: .horizontal(spacing: 0, alignment: .center),
                isHitTestVisible: false,
                children: [labelSlot, stepperNode]
            )
        }
    }

    private static func controlButton(
        runtime: RetainedViewRuntime,
        icon: SymbolIcon,
        accessibilityName: String,
        isEnabled: Bool,
        preferredSize: Size,
        palette: ControlPalette,
        iconDisplayScale: Double,
        bitmapFontAttribution: NativeBitmapFontAttributionSession?,
        cornerRadii: RetainedCornerRadii,
        action: @escaping @MainActor () -> Void
    ) -> ViewNode {
        let surfaceStyle = ButtonSurfaceStyle.bordered(palette: palette)
        // Joined-pair chrome: the bezel around the pair owns the hairline
        // ring, so a half draws none of its own — two stacked rings is what
        // turned the seam into a flat 2pt smear instead of a divider. The
        // focus ring stays (a half is still a focus stop) and the
        // elevated-button shadow goes, so a hovering or pressed segment
        // cannot cast onto its sibling.
        var joinedChrome = surfaceStyle.chrome
        joinedChrome.borderWidth = 0
        joinedChrome.shadowColor = .clear
        joinedChrome.shadowHoveredColor = .clear
        joinedChrome.shadowFocusedColor = .clear
        joinedChrome.shadowPressedColor = .clear
        // A macOS stepper arrow is a small wedge with air around it, not a
        // glyph sized to the half it sits in. The icon bitmap is stretched
        // into the node's own rect, so this box *is* the arrow's size.
        let chevronBox = MacOSControlMetrics.Stepper.chevronSize
        let titleNode = Controls.icon(
            icon,
            preferredSize: Size(
                width: min(chevronBox.width, preferredSize.width),
                height: min(chevronBox.height, preferredSize.height)
            ),
            color: isEnabled ? palette.label : palette.disabledLabel,
            scale: Stepper.chevronGlyphScale,
            displayScale: iconDisplayScale,
            bitmapFontAttribution: bitmapFontAttribution
        )
        let node = Controls.button(
            runtime: runtime,
            preferredSize: preferredSize,
            cornerRadius: MacOSControlMetrics.Stepper.cornerRadius,
            palette: surfaceStyle.palette,
            chrome: joinedChrome,
            // No self-clip: the painter falls back to `maxRadius` for
            // per-corner clip rounding, which would re-round the square
            // joined edge. The only child is a centered glyph that never
            // reaches the edge, so clipping buys nothing here.
            clipsToBounds: false,
            layoutMode: .stack(.vertical(alignment: .center, mainAlignment: .center)),
            isEnabled: isEnabled,
            animation: surfaceStyle.animation,
            appliesSurfaceSheen: true,
            action: action,
            children: [titleNode]
        )
        node.cornerRadii = cornerRadii
        // Chevron glyphs are poor accessible names; default to the action
        // name (an explicit accessibilityLabel modifier still wins).
        node.accessibilityLabel = accessibilityName
        return node
    }

    /// Glyph scale of the stepper chevrons. Each half is only
    /// `MacOSControlMetrics.Stepper.buttonSize.height` tall, so the glyph
    /// has to stay small enough to sit inside the bezel.
    fileprivate static var chevronGlyphScale: Double { 0.9 }

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
                trackColor: context.controlPalette.controlTrack,
                filledColor: context.tint,
                palette: context.controlPalette.borderedButtonPalette,
                chrome: context.controlPalette.buttonChrome(focusTint: context.tint, casts: false),
                onValueChanged: { newValue in
                    binding.wrappedValue = Self.snappedValue(newValue, in: range, step: step)
                    context.invalidate()
                },
                onEditingChanged: { isEditing in
                    onEditingChanged(isEditing)
                }
            )
            // macOS parity: a slider fills the width it is offered and only
            // falls back to `sliderPreferredSize` as its ideal width when
            // nothing proposes one (an intrinsic measure).
            sliderNode.layoutFillAxes = .horizontalOnly
            let span = range.upperBound - range.lowerBound
            if context.isEnabled, span.isFinite, span > 0 {
                let increment =
                    step.flatMap { value in
                        value.isFinite && value > 0 ? value : nil
                    } ?? span / 100
                let horizontalDirection = context.layoutDirection == .rightToLeft ? -1.0 : 1.0
                let applyValue: (Double) -> Void = { [weak sliderNode] proposedValue in
                    let nextValue = Self.snappedValue(proposedValue, in: range, step: step)
                    guard nextValue != binding.wrappedValue else {
                        return
                    }

                    onEditingChanged(true)
                    binding.wrappedValue = nextValue
                    sliderNode?.accessibilityValue = String(nextValue)
                    context.invalidate()
                    onEditingChanged(false)
                }

                sliderNode.interceptsVerticalArrowKeys = true
                sliderNode.onKeyDown = { event in
                    let proposedValue: Double
                    switch event.key {
                    case .rightArrow:
                        proposedValue = binding.wrappedValue + horizontalDirection * increment
                    case .leftArrow:
                        proposedValue = binding.wrappedValue - horizontalDirection * increment
                    case .upArrow:
                        proposedValue = binding.wrappedValue + increment
                    case .downArrow:
                        proposedValue = binding.wrappedValue - increment
                    case .pageUp:
                        proposedValue = binding.wrappedValue + max(increment, span / 10)
                    case .pageDown:
                        proposedValue = binding.wrappedValue - max(increment, span / 10)
                    case .home:
                        proposedValue = range.lowerBound
                    case .end:
                        proposedValue = range.upperBound
                    default:
                        return
                    }

                    applyValue(proposedValue)
                }
                sliderNode.accessibilityActions.append(
                    RetainedAccessibilityAction(name: "Increment", kind: .increment) {
                        applyValue(binding.wrappedValue + increment)
                    }
                )
                sliderNode.accessibilityActions.append(
                    RetainedAccessibilityAction(name: "Decrement", kind: .decrement) {
                        applyValue(binding.wrappedValue - increment)
                    }
                )
            }

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
            // Default accessibility name from the label content; an explicit
            // accessibilityLabel modifier applies after this and wins. The
            // retained slider builder already applied slider behavior + value.
            sliderNode.accessibilityLabel = firstRetainedText(in: labelNode)
            guard !context.isInsideGroupedForm else {
                // An NSSlider spans a form's control column; 200pt of track
                // floating in a 400pt column is not a settings pane.
                rowNode.layoutFillAxes = .horizontalOnly
                return groupedFormRowNode(label: labelNode, content: rowNode)
            }
            // In the labeled form the track row gives up vertical space before
            // the label does: a constrained parent squeezes the track (which
            // re-resolves its geometry in onLayout) instead of shrinking the
            // label's frame until its text overflows onto the track.
            rowNode.layoutPriority = -1
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
                    trackColor: context.controlPalette.controlTrack,
                    filledColor: context.tint
                )
                progressNode.explicitFrameFillAxes = .horizontalOnly
            }
            guard !context.labelsHidden else {
                return progressNode
            }

            guard !label.isEmpty || !currentValueLabel.isEmpty else {
                return progressNode
            }

            // Labeled form: the bar absorbs vertical compression before the
            // label/header does so the label text never overflows onto it.
            progressNode.layoutPriority = -1

            guard !currentValueLabel.isEmpty else {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                // Default accessibility name from the label content; an
                // explicit accessibilityLabel modifier wins. The retained
                // progress builder already applied the value.
                progressNode.accessibilityLabel = firstRetainedText(in: labelNode)
                guard !context.isInsideGroupedForm else {
                    // A determinate bar spans the value column, the way an
                    // NSProgressIndicator spans a form's control column.
                    if case .automatic = context.progressViewStyle.kind {
                        progressNode.layoutFillAxes = .horizontalOnly
                    } else if case .linear = context.progressViewStyle.kind {
                        progressNode.layoutFillAxes = .horizontalOnly
                    }
                    return groupedFormRowNode(label: labelNode, content: progressNode)
                }
                let node = Controls.stackPanel(
                    stackLayout: .vertical(spacing: 8, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [labelNode, progressNode]
                )
                node.explicitFrameFillAxes = progressNode.explicitFrameFillAxes
                return node
            }

            var headerChildren: [ViewNode] = []
            if !label.isEmpty {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                progressNode.accessibilityLabel = firstRetainedText(in: labelNode)
                headerChildren.append(labelNode)
            }
            headerChildren.append(currentValueLabelComponent.makeNode(runtime: runtime))

            let headerNode = Controls.stackPanel(
                stackLayout: .horizontal(spacing: 8, alignment: .center),
                isHitTestVisible: false,
                children: headerChildren
            )

            let node = Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: [headerNode, progressNode]
            )
            node.explicitFrameFillAxes = progressNode.explicitFrameFillAxes
            return node
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
                    trackColor: context.controlPalette.controlTrack,
                    filledColor: context.tint
                )
                gaugeNode.explicitFrameFillAxes = .horizontalOnly
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

            // Labeled form: the bar absorbs vertical compression before the
            // header/bounds labels do so label text never overflows onto it.
            gaugeNode.layoutPriority = -1

            // A gauge whose only accessory is its label is a grouped-form
            // row like any other: label in the shared column, bar spanning
            // the value column beside it.
            if context.isInsideGroupedForm, !label.isEmpty, currentValueLabel.isEmpty, !hasBounds,
                !hasMarkedLabels
            {
                let labelNode = labelComponent.makeNode(runtime: runtime)
                gaugeNode.accessibilityLabel = firstRetainedText(in: labelNode)
                switch context.gaugeStyle.kind {
                case .circular, .accessoryCircular, .accessoryCircularCapacity:
                    break
                case .automatic, .linear, .linearCapacity, .accessoryLinear, .accessoryLinearCapacity:
                    gaugeNode.layoutFillAxes = .horizontalOnly
                }
                return groupedFormRowNode(label: labelNode, content: gaugeNode)
            }

            var children: [ViewNode] = []
            if hasHeader {
                var headerChildren: [ViewNode] = []
                if !label.isEmpty {
                    let labelNode = labelComponent.makeNode(runtime: runtime)
                    // Default accessibility name from the label content; an
                    // explicit accessibilityLabel modifier wins. The retained
                    // progress builder already applied the value.
                    gaugeNode.accessibilityLabel = firstRetainedText(in: labelNode)
                    headerChildren.append(labelNode)
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

            let node = Controls.stackPanel(
                stackLayout: .vertical(spacing: 8, alignment: .stretch),
                isHitTestVisible: false,
                children: children
            )
            node.explicitFrameFillAxes = gaugeNode.explicitFrameFillAxes
            return node
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
            let node = Controls.button(
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
            // A link is announced as a hyperlink, not a plain button: the
            // projection's first-match table checks isButton before isLink,
            // so replace the retained button default. The name defaults to
            // the label content; an explicit accessibilityLabel wins.
            node.accessibilityTraits.subtract(.isButton)
            node.accessibilityTraits.formUnion(.isLink)
            node.accessibilityLabel = firstRetainedText(in: labelNode)
            return node
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
        let supportedContentTypes = supportedContentTypes
        let onImport = onImport
        return Button {
            let urls = FileDialogManager.showOpenFileDialog(
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: supportedContentTypes),
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
        // A button centers its own label: the pill may be wider than the
        // text (a bezel, a stretch stack, a segmented track), and macOS
        // centers the title in it. The app-wide default alignment is
        // leading, so the button states its own.
        let effectiveButtonStyle =
            resolvedButtonStyle == .automatic && !hasCustomSurfaceStyle ? context.buttonStyle : resolvedButtonStyle
        // A destructive button that is not accent-filled carries its role in
        // the *label*, as macOS does: standard bezel, red title.
        var labelContext = context.withEnvironmentValue(\.multilineTextAlignment, .center)
            .withEnvironmentValue(\.retainedAlertActionScope, nil)
        if appliesDestructiveLabelTint, effectiveButtonStyle != .borderedProminent, !hasCustomSurfaceStyle {
            labelContext = labelContext.withForegroundColor(.red)
        }
        let labelComponent = composeComponent(
            from: label,
            context: labelContext,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )

        return Component { runtime in
            let labelNode = labelComponent.makeNode(runtime: runtime)
            // AppKit dims the whole disabled cell, label included — before
            // this the only difference between an enabled and a disabled
            // button was its fill, with pure-white glyphs on both.
            if !context.isEnabled {
                labelNode.opacity = ControlPalette.disabledContentOpacity
            }
            let buttonStyle = effectiveButtonStyle
            let surfaceStyle = resolvedSurfaceStyle(for: buttonStyle, context: context)
            let buttonBorderShape = context.environmentValues.buttonBorderShape
            // macOS push-bezel content metrics (MacOSControlMetrics.Button):
            // the chrome is a bezel around the label, not the label's own
            // advance box.
            let contentMetrics = retainedButtonContentMetrics(
                style: buttonStyle,
                controlSize: context.controlSize
            )
            let alertReceipt: RetainedAlertActionReceipt?
            let activate: @MainActor () -> Void
            if let scope = context.environmentValues.retainedAlertActionScope, scope.contains(context) {
                let invocationContext = context.retainedAlertInvocationContext()
                let receipt = scope.declaration.registerButton(role: role) {
                    ViewBuildContextScope.withCurrent(invocationContext) { action() }
                }
                alertReceipt = receipt
                activate = { receipt.activate() }
            } else {
                alertReceipt = nil
                activate = {
                    ViewBuildContextScope.withCurrent(context) { action() }
                    context.invalidate()
                }
            }
            let node = Controls.button(
                runtime: runtime,
                layoutPriority: context.environmentValues.buttonSizing.retainedLayoutPriority,
                cornerRadius: buttonBorderShape.retainedCornerRadius(default: surfaceStyle.cornerRadius),
                palette: surfaceStyle.palette,
                chrome: surfaceStyle.chrome,
                clipsToBounds: surfaceStyle.clipsToBounds,
                layoutMode: .stack(
                    .vertical(
                        padding: contentMetrics.padding,
                        alignment: .stretch,
                        mainAlignment: .center
                    )),
                isEnabled: context.isEnabled,
                repeatBehavior: context.environmentValues.buttonRepeatBehavior.retainedBehavior,
                animation: surfaceStyle.animation,
                appliesSurfaceSheen: true,
                action: activate,
                children: [labelNode]
            )
            alertReceipt?.install(on: node)
            if contentMetrics.minimumHeight > 0 {
                node.applyDefaultMinimumHeight(contentMetrics.minimumHeight)
            }
            buttonBorderShape.applyRetainedDynamicCornerRadius(to: node)
            // Default accessibility name from the label content; an explicit
            // `accessibilityLabel` modifier applies after this and wins. The
            // retained button builder already applied the isButton trait and
            // combine behavior.
            node.accessibilityLabel = _storedTitle ?? firstRetainedText(in: labelNode)
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
        let palette = context.controlPalette
        // macOS only *fills* a destructive button when the app has also
        // asked for prominence; an `.automatic` / `.bordered` destructive
        // button keeps the standard bezel and tints its label red (that
        // tint is applied in `makeComponent`, not here).
        if buttonStyle == .borderedProminent {
            if role == .destructive {
                return ButtonSurfaceStyle.destructiveFilled(palette: palette)
            }

            let accent = ControlPalette.opaque(context.tint)
            return ButtonSurfaceStyle(
                cornerRadius: MacOSControlMetrics.Button.regularCornerRadius,
                palette: palette.prominentPalette(tint: accent),
                chrome: palette.buttonChrome(focusTint: accent),
                clipsToBounds: true,
                animation: .default
            )
        }

        guard buttonStyle == .automatic else {
            if hasCustomSurfaceStyle {
                return style
            }

            return buttonStyle.surfaceStyle
        }

        if hasCustomSurfaceStyle {
            return style
        }

        // `ButtonSurfaceStyle.default` is the appearance-free fallback; a
        // button that can see its context resolves the bordered ramp for
        // the live appearance instead.
        return .bordered(palette: palette)
    }

    /// macOS renders a destructive-role button that is *not* prominent as a
    /// standard bezel with a red label.
    fileprivate var appliesDestructiveLabelTint: Bool {
        role == .destructive
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
func resolvedSymbolIcon(for systemName: String, variants: SymbolVariants = .none) -> SymbolIcon {
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
        "chart.line.uptrend.xyaxis.fill", "waveform", "chart.bar", "chart.bar.fill":
        return .activity
    case "doc", "doc.fill", "doc.text", "doc.text.fill", "textformat", "textformat.fill",
        "text.alignleft", "text.alignright", "text.aligncenter", "doc.on.doc", "doc.on.clipboard":
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
    case "arrowtriangle.down.fill", "triangle.down.fill":
        return .caretDownFill
    case "arrowtriangle.up.fill", "triangle.up.fill":
        return .caretUpFill
    case "chevron.down", "chevron.down.circle", "chevron.down.circle.fill", "arrowtriangle.down":
        return .chevronDown
    case "chevron.up", "chevron.up.circle", "chevron.up.circle.fill", "arrowtriangle.up":
        return .chevronUp
    case "chevron.left", "chevron.left.circle", "chevron.left.circle.fill", "arrowtriangle.left",
        "arrowtriangle.left.fill":
        return .chevronLeft
    case "chevron.right", "chevron.right.circle", "chevron.right.circle.fill", "arrowtriangle.right",
        "arrowtriangle.right.fill":
        return .chevronRight
    case "plus", "plus.circle", "plus.circle.fill":
        return .plus
    case "minus", "minus.circle", "minus.circle.fill":
        return .minus
    case "xmark", "xmark.circle", "xmark.circle.fill":
        return .xmark
    case "play", "play.fill", "play.circle", "play.circle.fill", "play.rectangle",
        "play.rectangle.fill":
        return .play
    case "pause", "pause.fill", "pause.circle", "pause.circle.fill":
        return .pause
    case "arrow.left":
        return .arrowLeft
    case "arrow.right":
        return .arrowRight
    case "arrow.up", "square.and.arrow.up":
        return .arrowUp
    case "arrow.down", "square.and.arrow.down":
        return .arrowDown
    case "ellipsis", "ellipsis.circle", "ellipsis.circle.fill":
        return .ellipsis
    case "trash", "trash.fill":
        return .trash
    case "pencil", "pencil.circle", "pencil.circle.fill":
        return .pencil
    case "person", "person.fill", "person.circle", "person.circle.fill":
        return .person
    case "house", "house.fill":
        return .house
    case "star", "star.circle", "star.circle.fill":
        return .star
    case "star.fill":
        return .starFill
    case "heart":
        return .heart
    case "heart.fill":
        return .heartFill
    case "bell", "bell.fill":
        return .bell
    case "camera", "camera.fill":
        return .camera
    case "globe":
        return .globe
    case "map", "map.fill", "mappin", "mappin.circle", "mappin.circle.fill":
        return .mapPin
    default:
        return .sparkle
    }
}
private struct ResolvedTextInputStyle {
    var backgroundColor: Color
    var backgroundGradient: GradientType?
    var borderColor: Color
    var borderWidth: Double
    var cornerRadius: Double
    var padding: EdgeInsets
}
extension TextFieldStyle {
    /// The well every bordered text input shares, resolved for the live
    /// appearance: `fieldSurface` inside a hairline.
    ///
    /// The two appearances are genuine inverses here and both are right: on
    /// the near-black page a field is `surface2`, one step *lighter* than the
    /// card it sits in, because a darker recess on a near-black page is a
    /// hole; on the near-white page it is white, one step lighter than the
    /// `#F1F2F5` chips beside it. In both, the ring is what says "you can
    /// type here" — the engine has no inner shadow and does not need one.
    fileprivate func resolvedTextInputWell(
        isEnabled: Bool,
        palette: ControlPalette,
        cornerRadius: Double
    ) -> ResolvedTextInputStyle {
        let backgroundColor =
            isEnabled
            ? palette.fieldSurface
            : palette.quaternaryFill
        // The painter takes the top stop from the node's own background and
        // the bottom stop from this gradient's end colour, so a recessed
        // well is expressed as "end lighter than the fill".
        let insetGradient: GradientType? =
            isEnabled
            ? .linear(
                SwiftWindowsGraphics.LinearGradient(
                    startColor: backgroundColor,
                    endColor: ControlPalette.lightened(backgroundColor, by: 1 - Controls.grooveSheenFactor)))
            : nil
        return ResolvedTextInputStyle(
            backgroundColor: backgroundColor,
            backgroundGradient: insetGradient,
            borderColor: isEnabled ? palette.controlBorder : palette.quaternaryLabel,
            borderWidth: 1,
            cornerRadius: cornerRadius,
            padding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        )
    }

    fileprivate func resolvedTextInputStyle(isEnabled: Bool, palette: ControlPalette) -> ResolvedTextInputStyle {
        switch kind {
        case .automatic, .roundedBorder:
            return resolvedTextInputWell(
                isEnabled: isEnabled,
                palette: palette,
                cornerRadius: MacOSControlMetrics.Button.regularCornerRadius
            )
        case .squareBorder:
            return resolvedTextInputWell(isEnabled: isEnabled, palette: palette, cornerRadius: 0)
        case .plain:
            return ResolvedTextInputStyle(
                backgroundColor: .clear,
                backgroundGradient: nil,
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
    // Real Win32 key-down events are followed by a layout-aware `WM_CHAR`.
    // Printable insertion belongs exclusively to that stream; retaining the
    // virtual-key inference here would duplicate every typed character and
    // would still get international keyboards wrong.
    guard event.textInputDelivery == .inferredFromVirtualKey else {
        return nil
    }

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
private enum TextInputWordBoundaryClass: Equatable {
    case whitespace
    case word
    case punctuation

    init(_ character: Character) {
        if character.isWhitespace || character.isNewline {
            self = .whitespace
        } else if character.isLetter || character.isNumber || character == "_" {
            self = .word
        } else {
            self = .punctuation
        }
    }
}

/// Returns a Character offset, never a UTF-8/UTF-16 offset: the retained
/// editor's selection model counts extended grapheme clusters, so a family
/// emoji or combining-accent sequence must be crossed in one movement.
private func textInputWordBoundary(
    in text: String,
    from offset: Int,
    movingForward: Bool
) -> Int {
    var characterOffset = clampedTextOffset(offset, in: text)
    var index = text.index(text.startIndex, offsetBy: characterOffset)

    if movingForward {
        guard index < text.endIndex else { return characterOffset }

        let initialClass = TextInputWordBoundaryClass(text[index])
        if initialClass != .whitespace {
            while index < text.endIndex,
                TextInputWordBoundaryClass(text[index]) == initialClass
            {
                text.formIndex(after: &index)
                characterOffset += 1
            }
        }

        while index < text.endIndex,
            TextInputWordBoundaryClass(text[index]) == .whitespace
        {
            text.formIndex(after: &index)
            characterOffset += 1
        }
        return characterOffset
    }

    while index > text.startIndex {
        let previous = text.index(before: index)
        guard TextInputWordBoundaryClass(text[previous]) == .whitespace else { break }
        index = previous
        characterOffset -= 1
    }

    guard index > text.startIndex else { return characterOffset }
    let initialClass = TextInputWordBoundaryClass(text[text.index(before: index)])
    while index > text.startIndex {
        let previous = text.index(before: index)
        guard TextInputWordBoundaryClass(text[previous]) == initialClass else { break }
        index = previous
        characterOffset -= 1
    }
    return characterOffset
}

private func clampedTextOffset(_ offset: Int, in text: String) -> Int {
    min(max(0, offset), text.count)
}
extension String {
    fileprivate func textPrefix(upTo offset: Int) -> String {
        let clampedOffset = clampedTextOffset(offset, in: self)
        return String(prefix(clampedOffset))
    }

    fileprivate func textSubstring(in offsets: Range<Int>) -> String {
        let lowerBound = clampedTextOffset(offsets.lowerBound, in: self)
        let upperBound = clampedTextOffset(offsets.upperBound, in: self)
        guard lowerBound < upperBound else {
            return ""
        }

        let lowerIndex = index(startIndex, offsetBy: lowerBound)
        let upperIndex = index(startIndex, offsetBy: upperBound)
        return String(self[lowerIndex..<upperIndex])
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
    private let symbols: (@MainActor () -> [AnyView])?

    public init(renderer: @escaping @MainActor (inout GraphicsContext, CGSize) -> Void) {
        self.renderer = renderer
        self.symbols = nil
    }

    public init<F: View>(
        renderer: @escaping @MainActor (inout GraphicsContext, CGSize) -> Void,
        symbols: @escaping () -> F
    ) {
        self.renderer = renderer
        self.symbols = { [AnyView(symbols())] }
    }

    public init(
        renderer: @escaping @MainActor (inout GraphicsContext, CGSize) -> Void,
        @ViewBuilder symbols: @escaping @MainActor () -> [AnyView]
    ) {
        self.renderer = renderer
        self.symbols = symbols
    }

    public var body: Never {
        fatalError("Canvas has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        return Component { runtime in
            let canvas = SwiftWindowsUI.UI.canvas { [weak runtime] runtimeContext, size in
                var graphicsContext = GraphicsContext()
                graphicsContext.underlying = runtimeContext
                if let symbols = self.symbols {
                    var environment = context.environmentValues
                    environment.displayScale = runtime?.displayScale ?? context.displayScale
                    let resolver = CanvasSymbolResolver(
                        symbols: symbols,
                        context: context.withCanvasSize(size).withEnvironmentValues(environment))
                    graphicsContext.symbolResolver = { resolver.resolve($0) }
                }
                ViewBuildContextScope.withCurrent(context) {
                    self.renderer(&graphicsContext, size)
                }
                runtimeContext = graphicsContext.underlying
            }
            let node = canvas.makeNode(runtime: runtime)
            node.layoutFillAxes = .both
            return node
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
        return makeViewComponent(content(proxy), context: context)
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
        makeViewComponent(content, context: context)
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
            let urls = FileDialogManager.showOpenFileDialog(
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: [.image]),
                allowsMultipleSelection: multiple != nil
            )
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
            let urls = FileDialogManager.showOpenFileDialog(
                allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: [.image]),
                allowsMultipleSelection: false
            )
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
        return makeViewComponent(content, context: context)
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
            makeViewComponent(chart, context: context)
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
            backgroundColor: Color(red: 0.146, green: 0.146, blue: 0.146, alpha: 0.98),
            text: text,
            textStyle: PixelTextStyle(
                color: Color(red: 0.597, green: 0.597, blue: 0.597, alpha: 0.80),
                scale: 1.4,
                alignment: .center,
                verticalAlignment: .center,
                weight: .semibold
            ),
            borderColor: Color(red: 0.977, green: 0.977, blue: 0.977, alpha: 0.14),
            borderWidth: 1,
            cornerRadius: 12,
            isHitTestVisible: false
        )
    }
}
