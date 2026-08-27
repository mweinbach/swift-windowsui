import Foundation
import SwiftWindowsCore

/// Renderer-neutral geometry sampled from the scroll position that is painted,
/// including the presentation lag of a keyboard scroll and edge overshoot.
public struct RetainedScrollGeometry: Sendable, Equatable {
    public var contentOffset: Point
    public var contentSize: Size
    public var contentInsets: EdgeInsets
    public var containerSize: Size

    public init(contentOffset: Point, contentSize: Size, contentInsets: EdgeInsets, containerSize: Size) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }
}

public enum RetainedScrollPhase: Sendable, Equatable {
    case idle
    case tracking
    case interacting
    case decelerating
    case animating
}

public struct RetainedScrollPhaseChangeContext: Sendable, Equatable {
    public var geometry: RetainedScrollGeometry
    /// Points per second, in content-offset coordinates, when known.
    public var velocity: Point?

    public init(geometry: RetainedScrollGeometry, velocity: Point? = nil) {
        self.geometry = geometry
        self.velocity = velocity
    }
}

/// Scroll layout needs an unfloored content extent for observation even when
/// its clamping/painting extent is at least as large as the viewport. The
/// declared axis survives disabling input; a disabled ScrollView is still a
/// scroll container whose geometry can be observed.
@MainActor
final class RetainedScrollContainerState {
    var axis: ScrollAxis
    var contentSize: Size?
    var attachmentGeneration: UInt64 = 0
    var isInputEnabled = true

    init(axis: ScrollAxis) {
        self.axis = axis
    }
}

struct RetainedScrollSourceEpoch: Equatable {
    // Keep the tiny container state alive while comparing epochs. A bare
    // ObjectIdentifier could be reused after an axis is removed and restored
    // in the same callback. This state does not retain a node or runtime.
    var container: RetainedScrollContainerState
    var attachmentGeneration: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.container === rhs.container && lhs.attachmentGeneration == rhs.attachmentGeneration
    }
}

@MainActor
final class RetainedScrollGeometryObserver {
    let valueType: ObjectIdentifier
    let transform: (RetainedScrollGeometry) -> Any
    let valuesEqual: (Any, Any) -> Bool
    let action: (Any, Any) -> Void
    var previousValue: Any?

    init<Value: Equatable>(
        transform: @escaping (RetainedScrollGeometry) -> Value,
        action: @escaping (Value, Value) -> Void
    ) {
        valueType = ObjectIdentifier(Value.self)
        self.transform = { transform($0) as Any }
        // The type identity above is checked before transferring history.
        // Boxing as Any also preserves an Optional.none derived value.
        valuesEqual = { ($0 as! Value) == ($1 as! Value) }
        self.action = { action($0 as! Value, $1 as! Value) }
    }

    func sample(_ geometry: RetainedScrollGeometry) -> (() -> Void)? {
        let value = transform(geometry)
        let oldValue = previousValue ?? value
        let changed = previousValue == nil || !valuesEqual(oldValue, value)
        guard changed else { return nil }
        let action = action
        return { [self] in
            // A prepared callback can be invalidated by an earlier callback's
            // rebuild. Commit only delivered values, before app code can copy
            // that history into the rebuilt registration.
            previousValue = value
            action(oldValue, value)
        }
    }
}

@MainActor
final class RetainedScrollVisibilityObserver {
    let threshold: Double
    let action: (Bool) -> Void
    var previousValue: Bool?

    init(threshold: Double, action: @escaping (Bool) -> Void) {
        self.threshold = threshold.isFinite ? min(1, max(0, threshold)) : 0.5
        self.action = action
    }

    func sample(_ fraction: Double) -> (() -> Void)? {
        // At zero, touching a viewport edge is not visibility. At one, small
        // transform roundoff must not make a fully contained view invisible.
        let visible = fraction > 0 && fraction + 1e-10 >= threshold
        guard previousValue != visible else { return nil }
        let action = action
        return { [self] in
            previousValue = visible
            action(visible)
        }
    }
}

@MainActor
final class RetainedScrollPhaseObserver {
    typealias Action = (RetainedScrollPhase, RetainedScrollPhase, RetainedScrollPhaseChangeContext) -> Void

    struct Change {
        var id: UInt64
        var oldPhase: RetainedScrollPhase
        var newPhase: RetainedScrollPhase
        var context: RetainedScrollPhaseChangeContext
    }

    let action: Action
    var changes: [Change] = []
    private var nextChangeID: UInt64 = 0

    init(action: @escaping Action) {
        self.action = action
    }

    func reconcile(from previous: RetainedScrollPhaseObserver) {
        changes = previous.changes
        nextChangeID = previous.nextChangeID
    }

    func record(
        from oldPhase: RetainedScrollPhase, to newPhase: RetainedScrollPhase,
        context: RetainedScrollPhaseChangeContext
    ) {
        nextChangeID &+= 1
        var change = Change(id: nextChangeID, oldPhase: oldPhase, newPhase: newPhase, context: context)
        // A burst can revisit a phase repeatedly before painting. Coalesce
        // each registration's unpresented path independently; a callback that
        // rebuilds the owner must not consume another registration's events.
        if let repeated = changes.firstIndex(where: { $0.newPhase == newPhase }) {
            change.oldPhase = changes[repeated].oldPhase
            changes.removeSubrange(repeated..<changes.count)
        }
        changes.append(change)
    }

    func pendingActions() -> [() -> Void] {
        changes.map { change in
            { [self] in
                guard let index = changes.firstIndex(where: { $0.id == change.id }) else { return }
                changes.remove(at: index)
                action(change.oldPhase, change.newPhase, change.context)
            }
        }
    }
}

@MainActor
final class RetainedScrollObserverStorage {
    var geometry: [RetainedScrollGeometryObserver] = []
    var phase: [RetainedScrollPhaseObserver] = []
    var visibility: [RetainedScrollVisibilityObserver] = []
    weak var source: ViewNode?
    private var selectedSourceIdentifier: ObjectIdentifier?
    private var selectedSourceEpoch: RetainedScrollSourceEpoch?
    private(set) var generation: UInt64 = 0
    var currentPhase: RetainedScrollPhase = .idle
    var phaseChanges: [RetainedScrollPhaseObserver.Change] { phase.flatMap(\.changes) }
    var reportedMultipleSources = false

    func reconcile(from incoming: RetainedScrollObserverStorage) {
        // Fresh closures may remove registrations or change their transforms.
        // Pending actions from the old declaration must not run afterward.
        generation &+= 1
        for index in incoming.geometry.indices where geometry.indices.contains(index) {
            if incoming.geometry[index].valueType == geometry[index].valueType {
                incoming.geometry[index].previousValue = geometry[index].previousValue
            }
        }
        for index in incoming.visibility.indices where visibility.indices.contains(index) {
            incoming.visibility[index].previousValue = visibility[index].previousValue
        }
        for index in incoming.phase.indices where phase.indices.contains(index) {
            incoming.phase[index].reconcile(from: phase[index])
        }
        geometry = incoming.geometry
        visibility = incoming.visibility
        if phase.isEmpty || incoming.phase.isEmpty {
            currentPhase = .idle
        }
        phase = incoming.phase
    }

    func reset() {
        generation &+= 1
        source = nil
        selectedSourceIdentifier = nil
        selectedSourceEpoch = nil
        currentPhase = .idle
        for observer in phase { observer.changes.removeAll(keepingCapacity: false) }
        for observer in geometry { observer.previousValue = nil }
        for observer in visibility { observer.previousValue = nil }
    }

    func selectSource(_ node: ViewNode?) {
        // A weak source may already have become nil after removal. Its last
        // identity still tells us to release derived values and pending phases.
        guard
            source !== node || selectedSourceIdentifier != node.map(ObjectIdentifier.init)
                || selectedSourceEpoch != node?.scrollSourceEpoch
        else { return }
        generation &+= 1
        source = node
        selectedSourceIdentifier = node.map(ObjectIdentifier.init)
        selectedSourceEpoch = node?.scrollSourceEpoch
        currentPhase = .idle
        for observer in phase { observer.changes.removeAll(keepingCapacity: true) }
        for observer in geometry { observer.previousValue = nil }
    }

    func recordPhase(_ nextPhase: RetainedScrollPhase, context: RetainedScrollPhaseChangeContext) {
        guard !phase.isEmpty, currentPhase != nextPhase else { return }
        for observer in phase {
            observer.record(from: currentPhase, to: nextPhase, context: context)
        }
        currentPhase = nextPhase
    }
}

@MainActor
final class RetainedScrollObserverRegistry {
    struct NodeRef {
        weak var node: ViewNode?
        let sourceEpoch: RetainedScrollSourceEpoch?

        @MainActor
        init(node: ViewNode) {
            self.node = node
            sourceEpoch = node.scrollSourceEpoch
        }
    }

    var nodes: [NodeRef] = []
    private var indices: [ObjectIdentifier: Int] = [:]
    private var emptySlots = 0
    var isDelivering = false
    var renderedDuringDelivery = false

    var isEmpty: Bool { indices.isEmpty }

    func register(_ node: ViewNode) {
        let identifier = ObjectIdentifier(node)
        guard indices[identifier] == nil else { return }
        indices[identifier] = nodes.count
        nodes.append(NodeRef(node: node))
    }

    func unregister(_ node: ViewNode) {
        guard let index = indices.removeValue(forKey: ObjectIdentifier(node)) else { return }
        nodes[index].node = nil
        emptySlots += 1
        if emptySlots > 64, emptySlots > indices.count { compact() }
    }

    func compact() {
        nodes.removeAll { $0.node == nil }
        indices.removeAll(keepingCapacity: true)
        for (index, reference) in nodes.enumerated() {
            if let node = reference.node { indices[ObjectIdentifier(node)] = index }
        }
        emptySlots = 0
    }
}

extension ViewNode {
    var scrollSourceEpoch: RetainedScrollSourceEpoch? {
        scrollContainerState.map {
            RetainedScrollSourceEpoch(container: $0, attachmentGeneration: $0.attachmentGeneration)
        }
    }
    /// Observes the first enclosed scroll container. The first complete render
    /// establishes the value with an old == new callback; later renders invoke
    /// the action only when the transformed Equatable value changes.
    public func observeScrollGeometry<Value: Equatable>(
        of transform: @escaping (RetainedScrollGeometry) -> Value,
        action: @escaping (Value, Value) -> Void
    ) {
        let storage = scrollObserverStorage ?? RetainedScrollObserverStorage()
        storage.geometry.append(RetainedScrollGeometryObserver(transform: transform, action: action))
        scrollObserverStorage = storage
    }

    public func observeScrollPhase(
        _ action:
            @escaping (
                RetainedScrollPhase, RetainedScrollPhase, RetainedScrollPhaseChangeContext
            ) -> Void
    ) {
        let storage = scrollObserverStorage ?? RetainedScrollObserverStorage()
        storage.phase.append(RetainedScrollPhaseObserver(action: action))
        scrollObserverStorage = storage
    }

    /// Observes this view's area within its ancestor viewports. This is a
    /// geometry observation, not an opacity or sibling-occlusion query.
    public func observeScrollVisibility(threshold: Double = 0.5, _ action: @escaping (Bool) -> Void) {
        let storage = scrollObserverStorage ?? RetainedScrollObserverStorage()
        storage.visibility.append(RetainedScrollVisibilityObserver(threshold: threshold, action: action))
        scrollObserverStorage = storage
    }

    func reconcileScrollObservers(from source: ViewNode) {
        guard let incoming = source.scrollObserverStorage else {
            if scrollObserverStorage != nil { scrollObserverStorage = nil }
            return
        }
        if let storage = scrollObserverStorage {
            storage.reconcile(from: incoming)
            // A transform may capture changed application state even while
            // the scroll geometry itself is unchanged.
            scrollObserverStorage = storage
        } else {
            scrollObserverStorage = incoming
        }
    }

    func reconcileScrollContainer(from source: ViewNode) {
        guard let incoming = source.scrollContainerState else {
            scrollContainerState = nil
            return
        }
        if let state = scrollContainerState {
            state.axis = incoming.axis
        } else {
            scrollContainerState = RetainedScrollContainerState(axis: incoming.axis)
        }
        isScrollInputEnabled = incoming.isInputEnabled
    }
}

/// Convex polygon intersection keeps visibility correct under rotation and
/// scale, where intersecting axis-aligned bounding boxes overcounts area.
enum RetainedScrollVisibilityGeometry {
    static func corners(of rect: Rect, transform: Transform2D) -> [Point] {
        [
            Point(x: rect.minX, y: rect.minY),
            Point(x: rect.maxX, y: rect.minY),
            Point(x: rect.maxX, y: rect.maxY),
            Point(x: rect.minX, y: rect.maxY),
        ].map { transform.applying(to: $0) }
    }

    static func area(of points: [Point]) -> Double {
        abs(signedArea(of: points))
    }

    private static func signedArea(of points: [Point]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }
        return sum * 0.5
    }

    static func intersect(_ subject: [Point], with clip: [Point]) -> [Point] {
        guard subject.count >= 3, clip.count >= 3 else { return [] }
        let orientation = signedArea(of: clip) >= 0 ? 1.0 : -1.0
        var output = subject
        for index in clip.indices {
            guard !output.isEmpty else { return [] }
            let edgeStart = clip[index]
            let edgeEnd = clip[(index + 1) % clip.count]
            func distance(_ point: Point) -> Double {
                orientation
                    * ((edgeEnd.x - edgeStart.x) * (point.y - edgeStart.y)
                        - (edgeEnd.y - edgeStart.y) * (point.x - edgeStart.x))
            }
            let input = output
            output = []
            var previous = input[input.count - 1]
            var previousDistance = distance(previous)
            for current in input {
                let currentDistance = distance(current)
                if (currentDistance >= 0) != (previousDistance >= 0) {
                    let progress = previousDistance / (previousDistance - currentDistance)
                    output.append(
                        Point(
                            x: previous.x + (current.x - previous.x) * progress,
                            y: previous.y + (current.y - previous.y) * progress))
                }
                if currentDistance >= 0 { output.append(current) }
                previous = current
                previousDistance = currentDistance
            }
        }
        return output
    }
}
