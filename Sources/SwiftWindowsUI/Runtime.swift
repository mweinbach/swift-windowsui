import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform

// Gap/Fix: Granular dirty tracking — OptionSet replaces single isDirty boolean.
public struct DirtyFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Property changes that affect size or position (frame, preferredSize, layoutMode, etc.).
    public static let layout  = DirtyFlags(rawValue: 1 << 0)
    /// Property changes that only affect visual appearance (color, opacity, borderColor, etc.).
    public static let paint   = DirtyFlags(rawValue: 1 << 1)
    /// Child list changed (add/remove).
    public static let children = DirtyFlags(rawValue: 1 << 2)

    public static let all: DirtyFlags = [.layout, .paint, .children]
}

struct ViewPaintCacheKey: Equatable, Sendable {
    var bounds: Rect
    var contentMask: Rect?
    var opacity: Float
    var displayScale: Double
    var isHovered: Bool
    var hoverEffect: RetainedHoverEffect?
    var isFocused: Bool
    var isFocusEffectDisabled: Bool
}

struct ViewMeasureCacheKey: Equatable, Sendable {
    var constraints: LayoutConstraints
    var displayScale: Double
}

public struct KeyboardShortcutBinding: Sendable, Equatable {
    public var keyCode: UInt32
    public var modifiers: KeyboardModifiers

    public init(keyCode: UInt32, modifiers: KeyboardModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    func matches(_ event: KeyboardEvent) -> Bool {
        event.keyCode == keyCode && event.modifiers == modifiers
    }
}

public enum RetainedHoverEffect: Sendable, Equatable {
    case automatic
    case highlight
    case lift
}

public enum RetainedImageResizingMode: Sendable, Equatable {
    case stretch
    case tile
}

public enum RetainedImageRenderingMode: Sendable, Equatable {
    case original
    case template
}

public enum RetainedImageInterpolation: Sendable, Equatable {
    case none
    case low
    case medium
    case high
}

public enum RetainedSymbolRenderingMode: Sendable, Equatable {
    case monochrome
    case hierarchical
    case palette
    case multicolor
}

public struct RetainedSymbolVariants: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let none: RetainedSymbolVariants = []
    public static let circle = RetainedSymbolVariants(rawValue: 1 << 0)
    public static let square = RetainedSymbolVariants(rawValue: 1 << 1)
    public static let rectangle = RetainedSymbolVariants(rawValue: 1 << 2)
    public static let fill = RetainedSymbolVariants(rawValue: 1 << 3)
    public static let slash = RetainedSymbolVariants(rawValue: 1 << 4)
}

public struct RetainedMatchedGeometryEffect: Sendable, Equatable {
    public var namespaceID: String
    public var elementID: String
    public var properties: UInt8
    public var anchor: Point
    public var isSource: Bool

    public init(
        namespaceID: String,
        elementID: String,
        properties: UInt8,
        anchor: Point,
        isSource: Bool
    ) {
        self.namespaceID = namespaceID
        self.elementID = elementID
        self.properties = properties
        self.anchor = anchor
        self.isSource = isSource
    }
}

public struct RetainedClipFillStyle: Sendable, Equatable {
    public var eoFill: Bool
    public var antialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        self.eoFill = eoFill
        self.antialiased = antialiased
    }
}

public struct RetainedContentShapeKinds: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let interaction = RetainedContentShapeKinds(rawValue: 1 << 0)
    public static let dragPreview = RetainedContentShapeKinds(rawValue: 1 << 1)
    public static let contextMenuPreview = RetainedContentShapeKinds(rawValue: 1 << 2)
    public static let focusEffect = RetainedContentShapeKinds(rawValue: 1 << 3)
    public static let hoverEffect = RetainedContentShapeKinds(rawValue: 1 << 4)
    public static let accessibility = RetainedContentShapeKinds(rawValue: 1 << 5)
}

public enum RetainedContentShapeStyle: Sendable, Equatable {
    case rectangle
    case roundedRectangle(Double)
    case capsule
    case ellipse

    public func contains(_ point: Point, in rect: Rect) -> Bool {
        guard rect.contains(point) else {
            return false
        }

        switch self {
        case .rectangle:
            return true
        case .roundedRectangle(let radius):
            return roundedRectContains(point, in: rect, radius: max(0, radius))
        case .capsule:
            return roundedRectContains(
                point,
                in: rect,
                radius: max(0, min(rect.size.width, rect.size.height) * 0.5)
            )
        case .ellipse:
            return ellipseContains(point, in: rect)
        }
    }

    public func visualCornerRadius(in rect: Rect) -> Double {
        switch self {
        case .rectangle:
            return 0
        case .roundedRectangle(let radius):
            return max(0, radius)
        case .capsule, .ellipse:
            return max(0, min(rect.size.width, rect.size.height) * 0.5)
        }
    }
}

public struct RetainedContentShape: Sendable, Equatable {
    public var kinds: RetainedContentShapeKinds
    public var style: RetainedContentShapeStyle
    public var eoFill: Bool

    public init(
        kinds: RetainedContentShapeKinds,
        style: RetainedContentShapeStyle,
        eoFill: Bool = false
    ) {
        self.kinds = kinds
        self.style = style
        self.eoFill = eoFill
    }
}

public struct ViewLifecycleTaskLaunch {
    public var key: String
    public var priority: TaskPriority
    public var action: @Sendable () async -> Void

    public init(
        key: String,
        priority: TaskPriority,
        action: @escaping @Sendable () async -> Void
    ) {
        self.key = key
        self.priority = priority
        self.action = action
    }
}

private func roundedRectContains(_ point: Point, in rect: Rect, radius: Double) -> Bool {
    let radius = min(radius, rect.size.width * 0.5, rect.size.height * 0.5)
    guard radius > 0 else {
        return rect.contains(point)
    }

    let left = rect.origin.x
    let right = rect.origin.x + rect.size.width
    let top = rect.origin.y
    let bottom = rect.origin.y + rect.size.height

    if point.x >= left + radius && point.x <= right - radius {
        return true
    }

    if point.y >= top + radius && point.y <= bottom - radius {
        return true
    }

    let centerX = point.x < left + radius ? left + radius : right - radius
    let centerY = point.y < top + radius ? top + radius : bottom - radius
    let dx = point.x - centerX
    let dy = point.y - centerY
    return dx * dx + dy * dy <= radius * radius
}

private func ellipseContains(_ point: Point, in rect: Rect) -> Bool {
    let radiusX = rect.size.width * 0.5
    let radiusY = rect.size.height * 0.5
    guard radiusX > 0, radiusY > 0 else {
        return false
    }

    let centerX = rect.origin.x + radiusX
    let centerY = rect.origin.y + radiusY
    let normalizedX = (point.x - centerX) / radiusX
    let normalizedY = (point.y - centerY) / radiusY
    return normalizedX * normalizedX + normalizedY * normalizedY <= 1
}

public enum RetainedButtonRepeatBehavior: Sendable, Equatable {
    case automatic
    case enabled
    case disabled
}

public enum RetainedSubmitLabel: Sendable, Equatable {
    case `return`
    case done
    case go
    case send
    case join
    case route
    case search
    case next
    case `continue`
}

public struct RetainedRedactionReasons: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let placeholder = RetainedRedactionReasons(rawValue: 1 << 0)
}

let retainedRedactionPlaceholderBaseColor = Color(red: 0.70, green: 0.74, blue: 0.78, alpha: 0.32)

func retainedRedactionPlaceholderCornerRadius(for rect: Rect) -> Double {
    min(6, max(0, rect.size.height / 2))
}

struct ViewLayoutCacheKey: Equatable, Sendable {
    var frame: Rect
    var displayScale: Double
}

@MainActor
struct ScrollIndicatorDeferredDrawPayload {
    var dispatchIndex: Int
    var track: ScrollIndicatorTrack
    var color: Color
    var cornerRadius: Double

    func fillRectCommand(contentMask: Rect?) -> FillRectCommand {
        FillRectCommand(
            rect: track.indicatorRect,
            color: color,
            cornerRadius: cornerRadius,
            clipRect: contentMask
        )
    }
}

@MainActor
struct DeferredSubtreePayload {
    weak var node: ViewNode?
    var parentOrigin: Point
    var inheritedClip: Rect?
    var inheritedOpacity: Float
    var inheritedInverseTransform: Transform2D?
}

@MainActor
private struct ButtonRepeatState {
    weak var node: ViewNode?
    var startTime: Double?
    var nextActivationTime: Double?
    var didRepeat: Bool
}

@MainActor
struct DeferredSubtreeState {
    var priority: Int
    var parentDispatchIndex: Int
    var payload: DeferredSubtreePayload
}

@MainActor
enum DeferredDrawPayload {
    case scrollIndicator(ScrollIndicatorDeferredDrawPayload)
    case subtree(DeferredSubtreePayload)

    var rect: Rect {
        switch self {
        case .scrollIndicator(let payload):
            return payload.track.indicatorRect
        case .subtree(let payload):
            guard let node = payload.node else {
                return .zero
            }
            return Rect(
                x: payload.parentOrigin.x + node.resolvedFrame.origin.x,
                y: payload.parentOrigin.y + node.resolvedFrame.origin.y,
                width: node.resolvedFrame.size.width,
                height: node.resolvedFrame.size.height
            )
        }
    }

    var interaction: DeferredOverlayInteraction? {
        switch self {
        case .scrollIndicator(let payload):
            return .scrollIndicator(dispatchIndex: payload.dispatchIndex, track: payload.track)
        case .subtree:
            return nil
        }
    }

    func fillRectCommand(contentMask: Rect?) -> FillRectCommand {
        switch self {
        case .scrollIndicator(let payload):
            return payload.fillRectCommand(contentMask: contentMask)
        case .subtree:
            return FillRectCommand(rect: .zero, color: .clear)
        }
    }

    func remappedDispatchIndices(by delta: Int) -> DeferredDrawPayload {
        switch self {
        case .scrollIndicator(var payload):
            payload.dispatchIndex += delta
            return .scrollIndicator(payload)
        case .subtree(let payload):
            return .subtree(payload)
        }
    }
}

@MainActor
struct DeferredDrawState {
    var priority: Int
    var parentDispatchIndex: Int
    var contentMask: Rect?
    var payload: DeferredDrawPayload
    var cachedFrameCommandRange: Range<Int>?
    var cachedScenePaintRange: Range<Int>?

    var rect: Rect {
        payload.rect
    }

    var interaction: DeferredOverlayInteraction? {
        payload.interaction
    }
}

@MainActor
enum DeferredOverlayInteraction {
    case scrollIndicator(dispatchIndex: Int, track: ScrollIndicatorTrack)
}

struct PrepaintStateIndex: Equatable, Sendable {
    var dispatchIndex: Int
    var interactionIndex: Int
    var focusOrderIndex: Int
    var deferredSubtreeIndex: Int
    var deferredDrawIndex: Int
    var deferredPriority: Int
}

struct PrepaintStateRange: Equatable, Sendable {
    var start: PrepaintStateIndex
    var end: PrepaintStateIndex
}

@MainActor
struct PrepaintDispatchState {
    var node: ViewNode
    var parentIndex: Int?
}

@MainActor
struct PrepaintInteractionState {
    var dispatchIndex: Int
    var node: ViewNode
    var frame: Rect
    var clipRect: Rect?
    var clipInverseTransform: Transform2D?
    var hitTestInverseTransform: Transform2D?

    func containsForHitTesting(_ point: Point) -> Bool {
        let clippedPoint: Point
        if let clipInverseTransform {
            clippedPoint = clipInverseTransform.applying(to: point)
        } else {
            clippedPoint = point
        }

        if let clipRect, !clipRect.contains(clippedPoint) {
            return false
        }

        let hitTestPoint: Point
        if let hitTestInverseTransform {
            hitTestPoint = hitTestInverseTransform.applying(to: point)
        } else {
            hitTestPoint = clippedPoint
        }

        return node.containsInteractionPoint(hitTestPoint, in: frame)
    }

    func containsForScrollTarget(_ point: Point) -> Bool {
        let transformedPoint: Point
        if let clipInverseTransform {
            transformedPoint = clipInverseTransform.applying(to: point)
        } else {
            transformedPoint = point
        }

        if let clipRect, !clipRect.contains(transformedPoint) {
            return false
        }

        return frame.contains(transformedPoint)
    }
}

@MainActor
struct RuntimePrepaintState {
    var dispatchNodes: [PrepaintDispatchState] = []
    var interactions: [PrepaintInteractionState] = []
    var focusOrder: [Int] = []
    var deferredSubtrees: [DeferredSubtreeState] = []
    var deferredDraws: [DeferredDrawState] = []
    var nextDeferredPriority: Int = 0
}

public enum ViewLayoutMode: Sendable {
    case absolute
    case stack(StackLayout)
    case flex(FlexStyle)
}

public enum ScrollAxis: Sendable {
    case horizontal
    case vertical
}

public struct FixedSizeAxes: Equatable, Sendable {
    public var horizontal: Bool
    public var vertical: Bool

    public init(horizontal: Bool = true, vertical: Bool = true) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

@MainActor
public final class ViewNode {
    public var frame: Rect {
        didSet { invalidateRuntime(.layout) }
    }

    public var backgroundColor: Color? {
        didSet { invalidateRuntime(.paint) }
    }

    public var backgroundGradient: LinearGradient? {
        didSet { invalidateRuntime(.paint) }
    }

    public var bitmapSurface: BitmapSurface? {
        didSet { invalidateRuntime(.layout) }
    }

    public var text: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var textStyle: PixelTextStyle {
        didSet { invalidateRuntime(.layout) }
    }

    public var borderColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var borderWidth: Double {
        didSet { invalidateRuntime(.layout) }
    }

    public var borderStrokeStyle: StrokeStyle? {
        didSet { invalidateRuntime(.paint) }
    }

    public var outlineColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var outlineWidth: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var shadowColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var shadowOffset: Point {
        didSet { invalidateRuntime(.paint) }
    }

    public var shadowSpread: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var cornerRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var clipsToBounds: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var clipFillStyle: RetainedClipFillStyle? {
        didSet { invalidateRuntime(.paint) }
    }

    public var layoutMode: ViewLayoutMode {
        didSet { invalidateRuntime(.layout) }
    }

    public var preferredSize: Size? {
        didSet { invalidateRuntime(.layout) }
    }

    public var layoutConstraints: LayoutConstraints? {
        didSet { invalidateRuntime(.layout) }
    }

    public var fixedSizeAxes: FixedSizeAxes? {
        didSet { invalidateRuntime(.layout) }
    }

    public var layoutPriority: Double {
        didSet { invalidateRuntime(.layout) }
    }

    // Gap/Fix: Blur radius — property for requesting a Gaussian blur over the view's content.
    public var blurRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Opacity — per-node opacity multiplier (0..1).
    public var opacity: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Z-index for sibling sort order.
    // NOTE: zIndex only sorts among siblings within the same parent.
    // For cross-subtree ordering (e.g. modals, overlays), add the view
    // at the root level or to a dedicated overlay container instead.
    public var zIndex: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Per-node 2D affine transform (applied around the view's center).
    public var transform: Transform2D {
        didSet { invalidateRuntime(.paint) }
    }

    public var flexItem: FlexProperties {
        didSet { invalidateRuntime() }
    }

    public var flexItemStyle: FlexItemStyle {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollAxis: ScrollAxis? {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollOffset: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollStep: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var showsScrollIndicator: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorIdleColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorHoverColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorActiveColor: Color {
        didSet { invalidateRuntime(.paint) }
    }

    public var scrollIndicatorThickness: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFocusable: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isHitTestVisible: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isHidden: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var accessibilityLabel: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityValue: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityHint: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityIdentifier: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityHidden: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var symbolVariableValue: Double? {
        didSet { invalidateRuntime(.paint) }
    }

    public var symbolRenderingMode: RetainedSymbolRenderingMode? {
        didSet { invalidateRuntime(.paint) }
    }

    public var symbolVariants: RetainedSymbolVariants {
        didSet { invalidateRuntime(.paint) }
    }

    public var imageResizingMode: RetainedImageResizingMode? {
        didSet { invalidateRuntime(.paint) }
    }

    public var imageCapInsets: EdgeInsets? {
        didSet { invalidateRuntime(.paint) }
    }

    public var imageRenderingMode: RetainedImageRenderingMode? {
        didSet { invalidateRuntime(.paint) }
    }

    public var imageInterpolation: RetainedImageInterpolation {
        didSet { invalidateRuntime(.paint) }
    }

    public var imageAntialiased: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var keyboardShortcuts: [KeyboardShortcutBinding] {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputSubmitLabel: RetainedSubmitLabel {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputCaretOffset: Int {
        didSet { invalidateRuntime(.paint) }
    }

    public var isSubmitScopeBoundary: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var hoverEffect: RetainedHoverEffect? {
        didSet { invalidateRuntime(.paint) }
    }

    public internal(set) var isHovered: Bool = false {
        didSet {
            if oldValue != isHovered, hoverEffect != nil, !isHoverEffectDisabled {
                invalidateRuntime(.paint)
            }
        }
    }

    public var isHoverEffectDisabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFocusEffectDisabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public internal(set) var isFocused: Bool = false {
        didSet {
            if oldValue != isFocused, isFocusable, !isFocusEffectDisabled {
                invalidateRuntime(.paint)
            }
        }
    }

    public var contentShapes: [RetainedContentShape] {
        didSet { invalidateRuntime(.paint) }
    }

    public var buttonRepeatBehavior: RetainedButtonRepeatBehavior

    public var redactionReasons: RetainedRedactionReasons {
        didSet { invalidateRuntime(.paint) }
    }

    public var isPrivacySensitive: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var paintsInDeferredPhase: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var matchedGeometryEffect: RetainedMatchedGeometryEffect? {
        didSet { invalidateRuntime(.paint) }
    }

    /// Optional stable identity tag used by the diffing algorithm to match
    /// nodes across rebuilds.  When present, two nodes with the same tag are
    /// considered equivalent and will have their properties updated in-place
    /// rather than being torn down and recreated.
    public var nodeTag: String?

    /// Snapshot of previous property values for animation interpolation.
    /// When an animation context is active and a property changes, the old
    /// value is recorded here so that the runtime can interpolate between old
    /// and new over time.
    public var previousPropertyValues: PropertySnapshot?

    /// Active per-property animation states driven by the `animation()` modifier.
    public var animationStates: [AnimatableProperty: AnimationState] = [:]

    public var onPointerEnter: (() -> Void)?
    public var onPointerExit: (() -> Void)?
    public var onPointerDown: (() -> Void)?
    public var onPointerUpInside: (() -> Void)?
    public var onPointerUpOutside: (() -> Void)?
    public var onContextMenu: ((Point) -> Void)?
    public var onFocusEnter: (() -> Void)?
    public var onFocusExit: (() -> Void)?
    public var onKeyDown: ((KeyboardEvent) -> Void)?
    public var onActivate: (() -> Void)?
    public var onRepeatActivate: (() -> Void)?
    public var onDragStart: ((Point) -> Void)?
    public var onDragChange: ((Point, Point) -> Void)?
    public var onDragEnd: ((Point, Point) -> Void)?
    public var onLayout: ((Rect) -> Void)?
    public var onAppearWithNode: ((ViewNode) -> Void)?
    public var onDisappearWithNode: ((ViewNode) -> Void)?
    public var pendingLifecycleTaskLaunches: [ViewLifecycleTaskLaunch] = []

    // Gap/Fix: Lifecycle hooks — called during appendCommands when node
    // first appears, disappears (removeFromParent), or changes frame size.
    public var onAppear: (() -> Void)?
    public var onDisappear: (() -> Void)?
    public var onSizeChange: ((Rect) -> Void)?
    internal private(set) var hasAppeared = false
    private var previousFrame: Rect?
    private var lifecycleTasks: [String: Swift.Task<Void, Never>] = [:]

    public private(set) weak var parent: ViewNode?
    public private(set) var children: [ViewNode]

    fileprivate weak var runtime: RetainedViewRuntime?
    internal var resolvedFrame: Rect
    internal var resolvedContentSize: Size
    internal var resolvedScrollOffset: Double
    internal private(set) var subtreeDirtyFlags: DirtyFlags = .all
    internal var cachedMeasureKey: ViewMeasureCacheKey?
    internal var cachedMeasuredSize: Size?
    internal var cachedLayoutKey: ViewLayoutCacheKey?
    internal var cachedPrepaintKey: ViewPaintCacheKey?
    internal var cachedPrepaintRange: PrepaintStateRange?
    internal var cachedFrameKey: ViewPaintCacheKey?
    internal var cachedFrameCommandRange: Range<Int>?
    internal var cachedSceneKey: ViewPaintCacheKey?
    internal var cachedScenePaintRange: Range<Int>?

    public init(
        frame: Rect = .zero,
        backgroundColor: Color? = nil,
        backgroundGradient: LinearGradient? = nil,
        bitmapSurface: BitmapSurface? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        borderStrokeStyle: StrokeStyle? = nil,
        outlineColor: Color = .clear,
        outlineWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        clipsToBounds: Bool = false,
        clipFillStyle: RetainedClipFillStyle? = nil,
        layoutMode: ViewLayoutMode = .absolute,
        preferredSize: Size? = nil,
        layoutConstraints: LayoutConstraints? = nil,
        fixedSizeAxes: FixedSizeAxes? = nil,
        layoutPriority: Double = 0,
        flexItem: FlexProperties = .default,
        flexItemStyle: FlexItemStyle = FlexItemStyle(),
        blurRadius: Double = 0,
        opacity: Double = 1.0,
        zIndex: Double = 0,
        transform: Transform2D = .identity,
        scrollAxis: ScrollAxis? = nil,
        scrollOffset: Double = 0,
        scrollStep: Double = 64,
        showsScrollIndicator: Bool = false,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorIdleColor: Color? = nil,
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        isFocusable: Bool = false,
        isHitTestVisible: Bool = true,
        isHidden: Bool = false,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        isAccessibilityHidden: Bool = false,
        symbolVariableValue: Double? = nil,
        symbolRenderingMode: RetainedSymbolRenderingMode? = nil,
        symbolVariants: RetainedSymbolVariants = .none,
        imageResizingMode: RetainedImageResizingMode? = nil,
        imageCapInsets: EdgeInsets? = nil,
        imageRenderingMode: RetainedImageRenderingMode? = nil,
        imageInterpolation: RetainedImageInterpolation = .medium,
        imageAntialiased: Bool? = nil,
        keyboardShortcuts: [KeyboardShortcutBinding] = [],
        textInputSubmitLabel: RetainedSubmitLabel = .return,
        textInputCaretOffset: Int = 0,
        isSubmitScopeBoundary: Bool = false,
        hoverEffect: RetainedHoverEffect? = nil,
        isHoverEffectDisabled: Bool = false,
        isFocusEffectDisabled: Bool = false,
        contentShapes: [RetainedContentShape] = [],
        buttonRepeatBehavior: RetainedButtonRepeatBehavior = .automatic,
        redactionReasons: RetainedRedactionReasons = [],
        isPrivacySensitive: Bool = false,
        paintsInDeferredPhase: Bool = false,
        matchedGeometryEffect: RetainedMatchedGeometryEffect? = nil,
        children: [ViewNode] = []
    ) {
        self.frame = frame
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
        self.bitmapSurface = bitmapSurface
        self.text = text
        self.textStyle = textStyle
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.borderStrokeStyle = borderStrokeStyle
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
        self.cornerRadius = cornerRadius
        self.clipsToBounds = clipsToBounds
        self.clipFillStyle = clipFillStyle
        self.layoutMode = layoutMode
        self.preferredSize = preferredSize
        self.layoutConstraints = layoutConstraints
        self.fixedSizeAxes = fixedSizeAxes
        self.layoutPriority = layoutPriority
        self.flexItem = flexItem
        self.flexItemStyle = flexItemStyle
        self.blurRadius = blurRadius
        self.opacity = opacity
        self.zIndex = zIndex
        self.transform = transform
        self.scrollAxis = scrollAxis
        self.scrollOffset = scrollOffset
        self.scrollStep = scrollStep
        self.showsScrollIndicator = showsScrollIndicator
        self.scrollIndicatorColor = scrollIndicatorColor
        self.scrollIndicatorIdleColor = scrollIndicatorIdleColor ?? scrollIndicatorColor
        self.scrollIndicatorHoverColor = scrollIndicatorHoverColor
        self.scrollIndicatorActiveColor = scrollIndicatorActiveColor
        self.scrollIndicatorThickness = scrollIndicatorThickness
        self.isFocusable = isFocusable
        self.isHitTestVisible = isHitTestVisible
        self.isHidden = isHidden
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.isAccessibilityHidden = isAccessibilityHidden
        self.symbolVariableValue = symbolVariableValue
        self.symbolRenderingMode = symbolRenderingMode
        self.symbolVariants = symbolVariants
        self.imageResizingMode = imageResizingMode
        self.imageCapInsets = imageCapInsets
        self.imageRenderingMode = imageRenderingMode
        self.imageInterpolation = imageInterpolation
        self.imageAntialiased = imageAntialiased
        self.keyboardShortcuts = keyboardShortcuts
        self.textInputSubmitLabel = textInputSubmitLabel
        self.textInputCaretOffset = max(0, textInputCaretOffset)
        self.isSubmitScopeBoundary = isSubmitScopeBoundary
        self.hoverEffect = hoverEffect
        self.isHoverEffectDisabled = isHoverEffectDisabled
        self.isFocusEffectDisabled = isFocusEffectDisabled
        self.contentShapes = contentShapes
        self.buttonRepeatBehavior = buttonRepeatBehavior
        self.redactionReasons = redactionReasons
        self.isPrivacySensitive = isPrivacySensitive
        self.paintsInDeferredPhase = paintsInDeferredPhase
        self.matchedGeometryEffect = matchedGeometryEffect
        self.onPointerEnter = nil
        self.onPointerExit = nil
        self.onPointerDown = nil
        self.onPointerUpInside = nil
        self.onPointerUpOutside = nil
        self.onContextMenu = nil
        self.onFocusEnter = nil
        self.onFocusExit = nil
        self.onKeyDown = nil
        self.onActivate = nil
        self.onRepeatActivate = nil
        self.onDragStart = nil
        self.onDragChange = nil
        self.onDragEnd = nil
        self.onLayout = nil
        self.onAppearWithNode = nil
        self.onDisappearWithNode = nil
        self.children = []
        self.resolvedFrame = frame
        self.resolvedContentSize = frame.size
        self.resolvedScrollOffset = 0

        for child in children {
            addChild(child)
        }
    }

    public func addChild(_ child: ViewNode) {
        child.removeFromParent()
        child.parent = self
        child.setRuntime(runtime)
        children.append(child)
        invalidateRuntime(.children)
    }

    public func removeChild(_ child: ViewNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else {
            return
        }

        let removed = children.remove(at: index)
        removed.markSubtreeDisappeared()
        removed.parent = nil
        removed.setRuntime(nil)
        invalidateRuntime(.children)
    }

    public func removeFromParent() {
        parent?.removeChild(self)
    }

    public func removeAllChildren() {
        for child in children {
            child.markSubtreeDisappeared()
            child.parent = nil
            child.setRuntime(nil)
        }

        children.removeAll(keepingCapacity: false)
        invalidateRuntime(.children)
    }

    /// Replace the child at the given index with a new node.
    public func replaceChild(at index: Int, with newChild: ViewNode) {
        guard index >= 0, index < children.count else {
            return
        }

        let old = children[index]
        old.markSubtreeDisappeared()
        old.parent = nil
        old.setRuntime(nil)

        newChild.removeFromParent()
        newChild.parent = self
        newChild.setRuntime(runtime)
        children[index] = newChild
        invalidateRuntime()
    }

    /// Remove the child at the given index.
    public func removeChild(at index: Int) {
        guard index >= 0, index < children.count else {
            return
        }

        let removed = children.remove(at: index)
        removed.markSubtreeDisappeared()
        removed.parent = nil
        removed.setRuntime(nil)
        invalidateRuntime()
    }

    fileprivate func setRuntime(_ runtime: RetainedViewRuntime?) {
        self.runtime = runtime
        for child in children {
            child.setRuntime(runtime)
        }
    }

    private func markSubtreeDisappeared() {
        if hasAppeared {
            onDisappear?()
            onDisappearWithNode?(self)
            cancelLifecycleTasks()
            hasAppeared = false
        }

        for child in children {
            child.markSubtreeDisappeared()
        }
    }

    public func launchLifecycleTask(_ launch: ViewLifecycleTaskLaunch) {
        lifecycleTasks[launch.key]?.cancel()
        lifecycleTasks[launch.key] = Swift.Task(priority: launch.priority) {
            await launch.action()
        }
    }

    public func cancelLifecycleTask(key: String) {
        lifecycleTasks[key]?.cancel()
        lifecycleTasks[key] = nil
    }

    private func cancelLifecycleTasks() {
        for task in lifecycleTasks.values {
            task.cancel()
        }
        lifecycleTasks.removeAll()
    }

    fileprivate func layoutSubtree(displayScale: Double) {
        let layoutKey = ViewLayoutCacheKey(frame: resolvedFrame, displayScale: displayScale)
        let layoutDirtyFlags = subtreeDirtyFlags.intersection([.layout, .children])
        if layoutDirtyFlags.isEmpty, cachedLayoutKey == layoutKey {
            runtime?.recordLayoutReuse()
            resolvedScrollOffset = clampedScrollOffset(for: scrollOffset)

            if hasDirtySubtree {
                for child in children where child.hasDirtySubtree {
                    child.layoutSubtree(displayScale: displayScale)
                }
            }
            return
        }

        onLayout?(resolvedFrame)

        switch layoutMode {
        case .absolute:
            var maxChildX: Double = 0
            var maxChildY: Double = 0

            for child in children {
                let childConstraints = LayoutConstraints(
                    maxWidth: remainingConstraintExtent(resolvedFrame.size.width, offset: child.frame.origin.x),
                    maxHeight: remainingConstraintExtent(resolvedFrame.size.height, offset: child.frame.origin.y)
                )
                let size = child.sizeThatFits(in: childConstraints)
                let resolvedSize = Size(
                    width: child.explicitWidth ?? size.width,
                    height: child.explicitHeight ?? size.height
                )
                child.resolvedFrame = Rect(origin: child.frame.origin, size: resolvedSize)
                child.layoutSubtree(displayScale: displayScale)
                maxChildX = max(maxChildX, child.resolvedFrame.maxX)
                maxChildY = max(maxChildY, child.resolvedFrame.maxY)
            }

            resolvedContentSize = Size(
                width: max(resolvedFrame.size.width, maxChildX),
                height: max(resolvedFrame.size.height, maxChildY)
            )

        case .stack(let stackLayout):
            let contentRect = Rect(origin: .zero, size: resolvedFrame.size).inset(by: stackLayout.padding)
            let visibleChildren = children.filter { !$0.isHidden }
            let childConstraints = stackChildConstraints(for: contentRect.size, axis: stackLayout.axis)
            let desiredSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
            let desiredMainSizes = desiredSizes.map { size in
                stackLayout.axis == .vertical ? size.height : size.width
            }
            let spacingTotal = stackLayoutSpacingTotal(count: visibleChildren.count, spacing: stackLayout.spacing)
            let availableMainExtent = stackLayout.axis == .vertical ? max(0, contentRect.size.height) : max(0, contentRect.size.width)
            let availableChildMainExtent = max(0, availableMainExtent - spacingTotal)
            let allowsOverflowAlongMainAxis = scrollAxis == stackScrollAxis(for: stackLayout.axis)

            // Allocate main sizes with flex support
            var allocatedMainSizes: [Double]
            if allowsOverflowAlongMainAxis {
                allocatedMainSizes = desiredMainSizes
            } else {
                allocatedMainSizes = allocateMainSizes(
                    desiredSizes: desiredMainSizes,
                    children: visibleChildren,
                    availableExtent: availableChildMainExtent
                )
            }

            // Apply flex grow/shrink
            if !allowsOverflowAlongMainAxis, !visibleChildren.isEmpty {
                let allocatedTotal = allocatedMainSizes.reduce(0, +)
                let remaining = availableChildMainExtent - allocatedTotal

                if remaining > 0 {
                    // Distribute remaining space to items with flexGrow > 0
                    let totalGrow = visibleChildren.reduce(0.0) { $0 + $1.flexItem.grow }
                    if totalGrow > 0 {
                        var leftover = remaining
                        for (i, child) in visibleChildren.enumerated() {
                            guard child.flexItem.grow > 0 else { continue }
                            let share: Double
                            if i == visibleChildren.count - 1 {
                                share = leftover
                            } else {
                                share = remaining * (child.flexItem.grow / totalGrow)
                                leftover -= share
                            }
                            allocatedMainSizes[i] += share
                        }
                    }
                } else if remaining < 0 {
                    // Shrink items with flexShrink > 0
                    let deficit = -remaining
                    let totalShrink = visibleChildren.reduce(0.0) { $0 + $1.flexItem.shrink }
                    if totalShrink > 0 {
                        var leftover = deficit
                        for (i, child) in visibleChildren.enumerated() {
                            guard child.flexItem.shrink > 0 else { continue }
                            let share: Double
                            if i == visibleChildren.count - 1 {
                                share = leftover
                            } else {
                                share = deficit * (child.flexItem.shrink / totalShrink)
                                leftover -= share
                            }
                            allocatedMainSizes[i] = max(0, allocatedMainSizes[i] - share)
                        }
                    }
                }
            }

            let occupiedMainExtent = allocatedMainSizes.reduce(0, +) + spacingTotal

            // Calculate spacing and start position based on distribution
            let mainOrigin = stackLayout.axis == .vertical ? contentRect.origin.y : contentRect.origin.x
            let mainCursorStart: Double
            let effectiveSpacing: Double

            switch stackLayout.distribution {
            case .fill:
                effectiveSpacing = stackLayout.spacing
                switch stackLayout.mainAlignment {
                case .start:
                    mainCursorStart = mainOrigin
                case .center:
                    mainCursorStart = mainOrigin + max(0, (availableMainExtent - occupiedMainExtent) * 0.5)
                case .end:
                    mainCursorStart = mainOrigin + max(0, availableMainExtent - occupiedMainExtent)
                }

            case .spaceBetween:
                let itemsTotal = allocatedMainSizes.reduce(0, +)
                let freeSpace = max(0, availableMainExtent - itemsTotal)
                effectiveSpacing = visibleChildren.count > 1 ? freeSpace / Double(visibleChildren.count - 1) : 0
                mainCursorStart = mainOrigin

            case .spaceAround:
                let itemsTotal = allocatedMainSizes.reduce(0, +)
                let freeSpace = max(0, availableMainExtent - itemsTotal)
                let slotSpace = visibleChildren.count > 0 ? freeSpace / Double(visibleChildren.count) : 0
                effectiveSpacing = slotSpace
                mainCursorStart = mainOrigin + slotSpace * 0.5

            case .spaceEvenly:
                let itemsTotal = allocatedMainSizes.reduce(0, +)
                let freeSpace = max(0, availableMainExtent - itemsTotal)
                let slotSpace = visibleChildren.count > 0 ? freeSpace / Double(visibleChildren.count + 1) : 0
                effectiveSpacing = slotSpace
                mainCursorStart = mainOrigin + slotSpace
            }

            var mainCursor = mainCursorStart
            var visibleIndex = 0
            var maxCrossExtent: Double = 0

            for child in children {
                if child.isHidden {
                    child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
                    continue
                }

                let desiredSize = desiredSizes[visibleIndex]
                let allocatedMainSize = allocatedMainSizes[visibleIndex]
                let childFrame: Rect

                switch stackLayout.axis {
                case .vertical:
                    let width = stackLayout.alignment == .stretch ? max(0, contentRect.size.width) : min(desiredSize.width, max(0, contentRect.size.width))
                    let height = max(0, allocatedMainSize)

                    let x: Double
                    switch stackLayout.alignment {
                    case .leading, .stretch:
                        x = contentRect.origin.x
                    case .center:
                        x = contentRect.origin.x + max(0, (contentRect.size.width - width) * 0.5)
                    case .trailing:
                        x = contentRect.maxX - width
                    }

                    childFrame = Rect(x: x, y: mainCursor, width: max(0, width), height: max(0, height))
                    mainCursor += height + effectiveSpacing
                    maxCrossExtent = max(maxCrossExtent, width)

                case .horizontal:
                    let width = max(0, allocatedMainSize)
                    let height = stackLayout.alignment == .stretch ? max(0, contentRect.size.height) : min(desiredSize.height, max(0, contentRect.size.height))

                    let y: Double
                    switch stackLayout.alignment {
                    case .leading, .stretch:
                        y = contentRect.origin.y
                    case .center:
                        y = contentRect.origin.y + max(0, (contentRect.size.height - height) * 0.5)
                    case .trailing:
                        y = contentRect.maxY - height
                    }

                    childFrame = Rect(x: mainCursor, y: y, width: max(0, width), height: max(0, height))
                    mainCursor += width + effectiveSpacing
                    maxCrossExtent = max(maxCrossExtent, height)
                }

                child.resolvedFrame = childFrame
                child.layoutSubtree(displayScale: displayScale)
                visibleIndex += 1
            }

            let contentMainExtent = (
                (allowsOverflowAlongMainAxis ? desiredMainSizes : allocatedMainSizes).reduce(0, +) +
                spacingTotal +
                stackMainPadding(for: stackLayout)
            )
            let contentCrossExtent = maxCrossExtent + stackCrossPadding(for: stackLayout)

            switch stackLayout.axis {
            case .vertical:
                resolvedContentSize = Size(
                    width: max(resolvedFrame.size.width, contentCrossExtent),
                    height: max(resolvedFrame.size.height, contentMainExtent)
                )
            case .horizontal:
                resolvedContentSize = Size(
                    width: max(resolvedFrame.size.width, contentMainExtent),
                    height: max(resolvedFrame.size.height, contentCrossExtent)
                )
            }

        case .flex(let flexStyle):
            let visibleChildren = children.filter { !$0.isHidden }

            let childInputs = visibleChildren.map { child -> FlexboxEngine.LayoutInput.ChildInput in
                let intrinsicSize = child.intrinsicContentSize()
                return FlexboxEngine.LayoutInput.ChildInput(
                    itemStyle: child.flexItemStyle,
                    intrinsicWidth: child.preferredSize?.width ?? intrinsicSize.width,
                    intrinsicHeight: child.preferredSize?.height ?? intrinsicSize.height
                )
            }

            let input = FlexboxEngine.LayoutInput(
                containerWidth: resolvedFrame.size.width,
                containerHeight: resolvedFrame.size.height,
                style: flexStyle,
                children: childInputs
            )

            let layouts = FlexboxEngine.layout(input)

            var visibleIndex = 0
            for child in children {
                if child.isHidden {
                    child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
                    continue
                }

                let childLayout = layouts[visibleIndex]
                child.resolvedFrame = Rect(x: childLayout.x, y: childLayout.y, width: childLayout.width, height: childLayout.height)
                child.layoutSubtree(displayScale: displayScale)
                visibleIndex += 1
            }

            resolvedContentSize = resolvedFrame.size
        }

        cachedLayoutKey = layoutKey
        resolvedScrollOffset = clampedScrollOffset(for: scrollOffset)
    }

    fileprivate func orderedChildrenForPaint() -> [ViewNode] {
        if children.contains(where: { $0.zIndex != 0 }) {
            return children.enumerated()
                .sorted { a, b in
                    if a.element.zIndex != b.element.zIndex {
                        return a.element.zIndex < b.element.zIndex
                    }
                    return a.offset < b.offset
                }
                .map(\.element)
        }

        return children
    }

    fileprivate func appendPrepaintState(
        into state: inout RuntimePrepaintState,
        parentOrigin: Point,
        inheritedClip: Rect?,
        inheritedOpacity: Float = 1,
        parentDispatchIndex: Int? = nil,
        inheritedInverseTransform: Transform2D? = nil,
        previousState: RuntimePrepaintState? = nil,
        displayScale: Double = 1,
        replayCount: inout Int
    ) {
        let startIndex = PrepaintStateIndex(
            dispatchIndex: state.dispatchNodes.count,
            interactionIndex: state.interactions.count,
            focusOrderIndex: state.focusOrder.count,
            deferredSubtreeIndex: state.deferredSubtrees.count,
            deferredDrawIndex: state.deferredDraws.count,
            deferredPriority: state.nextDeferredPriority
        )

        if isHidden {
            cachedPrepaintKey = nil
            cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
            return
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        if !baseClipAllowsDrawing(baseClip: inheritedClip, rect: absoluteFrame) {
            cachedPrepaintKey = nil
            cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
            return
        }

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    cachedPrepaintKey = nil
                    cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
                    return
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        let effectiveOpacity = inheritedOpacity * Float(opacity)
        let resolvedHoverEffect = resolvedActiveHoverEffect
        let cacheKey = ViewPaintCacheKey(
            bounds: absoluteFrame,
            contentMask: effectiveClip,
            opacity: effectiveOpacity,
            displayScale: displayScale,
            isHovered: isHovered,
            hoverEffect: resolvedHoverEffect,
            isFocused: isFocused,
            isFocusEffectDisabled: isFocusEffectDisabled
        )

        if
            let previousState,
            !hasDirtySubtree,
            cachedPrepaintKey == cacheKey,
            let previousRange = cachedPrepaintRange
        {
            let dispatchDelta = startIndex.dispatchIndex - previousRange.start.dispatchIndex
            let interactionDelta = startIndex.interactionIndex - previousRange.start.interactionIndex
            let focusOrderDelta = startIndex.focusOrderIndex - previousRange.start.focusOrderIndex
            let deferredSubtreeDelta = startIndex.deferredSubtreeIndex - previousRange.start.deferredSubtreeIndex
            let deferredDrawDelta = startIndex.deferredDrawIndex - previousRange.start.deferredDrawIndex
            let deferredPriorityDelta = startIndex.deferredPriority - previousRange.start.deferredPriority

            let copiedDispatchNodes = previousState.dispatchNodes[previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex]
                .enumerated()
                .map { offset, dispatchState in
                    var nextDispatchState = dispatchState
                    if let parentIndex = dispatchState.parentIndex {
                        if previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex ~= parentIndex {
                            nextDispatchState.parentIndex = parentIndex + dispatchDelta
                        } else {
                            nextDispatchState.parentIndex = parentDispatchIndex
                        }
                    } else {
                        nextDispatchState.parentIndex = parentDispatchIndex
                    }
                    return nextDispatchState
                }
            state.dispatchNodes.append(contentsOf: copiedDispatchNodes)

            let copiedInteractions = previousState.interactions[previousRange.start.interactionIndex..<previousRange.end.interactionIndex]
                .map { interaction in
                    var nextInteraction = interaction
                    nextInteraction.dispatchIndex += dispatchDelta
                    return nextInteraction
                }
            state.interactions.append(contentsOf: copiedInteractions)

            let copiedFocusOrder = previousState.focusOrder[previousRange.start.focusOrderIndex..<previousRange.end.focusOrderIndex]
                .map { $0 + dispatchDelta }
            state.focusOrder.append(contentsOf: copiedFocusOrder)

            let copiedDeferredSubtrees = previousState.deferredSubtrees[previousRange.start.deferredSubtreeIndex..<previousRange.end.deferredSubtreeIndex]
                .map { deferredSubtree in
                    var nextDeferredSubtree = deferredSubtree
                    nextDeferredSubtree.priority += deferredPriorityDelta
                    if previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex ~= deferredSubtree.parentDispatchIndex {
                        nextDeferredSubtree.parentDispatchIndex += dispatchDelta
                    } else if let parentDispatchIndex {
                        nextDeferredSubtree.parentDispatchIndex = parentDispatchIndex
                    }
                    return nextDeferredSubtree
                }
            state.deferredSubtrees.append(contentsOf: copiedDeferredSubtrees)

            let copiedDeferredDraws = previousState.deferredDraws[previousRange.start.deferredDrawIndex..<previousRange.end.deferredDrawIndex]
                .map { deferredDraw in
                    var nextDeferredDraw = deferredDraw
                    nextDeferredDraw.priority += deferredPriorityDelta
                    if previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex ~= deferredDraw.parentDispatchIndex {
                        nextDeferredDraw.parentDispatchIndex += dispatchDelta
                    } else if let parentDispatchIndex {
                        nextDeferredDraw.parentDispatchIndex = parentDispatchIndex
                    }
                    nextDeferredDraw.payload = deferredDraw.payload.remappedDispatchIndices(by: dispatchDelta)
                    return nextDeferredDraw
                }
            state.deferredDraws.append(contentsOf: copiedDeferredDraws)
            state.nextDeferredPriority = max(
                state.nextDeferredPriority,
                startIndex.deferredPriority + (previousRange.end.deferredPriority - previousRange.start.deferredPriority)
            )

            shiftCachedPrepaintRangesRecursively(
                dispatchDelta: dispatchDelta,
                interactionDelta: interactionDelta,
                focusOrderDelta: focusOrderDelta,
                deferredSubtreeDelta: deferredSubtreeDelta,
                deferredDrawDelta: deferredDrawDelta,
                deferredPriorityDelta: deferredPriorityDelta
            )
            cachedPrepaintKey = cacheKey
            cachedPrepaintRange = PrepaintStateRange(
                start: startIndex,
                end: PrepaintStateIndex(
                    dispatchIndex: state.dispatchNodes.count,
                    interactionIndex: state.interactions.count,
                    focusOrderIndex: state.focusOrder.count,
                    deferredSubtreeIndex: state.deferredSubtrees.count,
                    deferredDrawIndex: state.deferredDraws.count,
                    deferredPriority: state.nextDeferredPriority
                )
            )
            replayCount += 1
            return
        }

        let nodeInverseTransform: Transform2D?
        if transform.isIdentity {
            nodeInverseTransform = inheritedInverseTransform
        } else {
            let center = Point(
                x: absoluteFrame.origin.x + absoluteFrame.size.width * 0.5,
                y: absoluteFrame.origin.y + absoluteFrame.size.height * 0.5
            )
            let centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
                .concatenating(transform)
                .concatenating(.translation(x: center.x, y: center.y))
            if let inverseTransform = centeredTransform.inverseOrNil() {
                if let inheritedInverseTransform {
                    nodeInverseTransform = inheritedInverseTransform.concatenating(inverseTransform)
                } else {
                    nodeInverseTransform = inverseTransform
                }
            } else {
                nodeInverseTransform = inheritedInverseTransform
            }
        }

        let dispatchIndex = state.dispatchNodes.count
        state.dispatchNodes.append(
            PrepaintDispatchState(
                node: self,
                parentIndex: parentDispatchIndex
            )
        )

        if isHitTestVisible || isScrollable {
            state.interactions.append(
                PrepaintInteractionState(
                    dispatchIndex: dispatchIndex,
                    node: self,
                    frame: absoluteFrame,
                    clipRect: effectiveClip,
                    clipInverseTransform: inheritedInverseTransform,
                    hitTestInverseTransform: nodeInverseTransform
                )
            )
        }

        if isFocusable {
            state.focusOrder.append(dispatchIndex)
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in orderedChildrenForPaint() {
            if child.paintsInDeferredPhase {
                state.deferredSubtrees.append(
                    DeferredSubtreeState(
                        priority: state.nextDeferredPriority,
                        parentDispatchIndex: dispatchIndex,
                        payload: DeferredSubtreePayload(
                            node: child,
                            parentOrigin: childOrigin,
                            inheritedClip: effectiveClip,
                            inheritedOpacity: effectiveOpacity,
                            inheritedInverseTransform: nodeInverseTransform
                        )
                    )
                )
                state.nextDeferredPriority += 1
                continue
            }

            child.appendPrepaintState(
                into: &state,
                parentOrigin: childOrigin,
                inheritedClip: effectiveClip,
                inheritedOpacity: effectiveOpacity,
                parentDispatchIndex: dispatchIndex,
                inheritedInverseTransform: nodeInverseTransform,
                previousState: previousState,
                displayScale: displayScale,
                replayCount: &replayCount
            )
        }

        if effectiveOpacity > 0, let track = scrollIndicatorTrack(in: absoluteFrame) {
            let effectiveScrollIndicatorColor = scrollIndicatorColor.multipliedAlpha(by: effectiveOpacity)
            state.deferredDraws.append(
                DeferredDrawState(
                    priority: state.nextDeferredPriority,
                    parentDispatchIndex: dispatchIndex,
                    contentMask: effectiveClip,
                    payload: .scrollIndicator(
                        ScrollIndicatorDeferredDrawPayload(
                            dispatchIndex: dispatchIndex,
                            track: track,
                            color: effectiveScrollIndicatorColor,
                            cornerRadius: min(track.indicatorRect.size.width, track.indicatorRect.size.height) * 0.5
                        )
                    ),
                )
            )
            state.nextDeferredPriority += 1
        }

        cachedPrepaintKey = cacheKey
        cachedPrepaintRange = PrepaintStateRange(
            start: startIndex,
            end: PrepaintStateIndex(
                dispatchIndex: state.dispatchNodes.count,
                interactionIndex: state.interactions.count,
                focusOrderIndex: state.focusOrder.count,
                deferredSubtreeIndex: state.deferredSubtrees.count,
                deferredDrawIndex: state.deferredDraws.count,
                deferredPriority: state.nextDeferredPriority
            )
        )
    }

    fileprivate func appendCommands(
        into commands: inout [RenderCommand],
        parentOrigin: Point,
        inheritedClip: Rect?,
        inheritedOpacity: Float = 1,
        previousRenderedFrame: RenderFrame? = nil,
        displayScale: Double = 1,
        replayCount: inout Int
    ) {
        let startIndex = commands.count
        if isHidden {
            cachedFrameKey = nil
            cachedFrameCommandRange = startIndex..<startIndex
            markSubtreeRendered()
            return
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        // Gap/Fix: Occlusion culling — skip the entire node early if it is
        // fully outside the inherited clip bounds (before allocating any
        // command structs).
        if !baseClipAllowsDrawing(baseClip: inheritedClip, rect: absoluteFrame) {
            cachedFrameKey = nil
            cachedFrameCommandRange = startIndex..<startIndex
            markSubtreeRendered()
            return
        }

        // Gap/Fix: Lifecycle — fire onAppear the first time a node is rendered.
        if !hasAppeared {
            hasAppeared = true
            onAppear?()
            onAppearWithNode?(self)
            previousFrame = absoluteFrame
        }

        // Gap/Fix: Lifecycle — fire onSizeChange when the resolved frame differs
        // from the previously recorded frame.
        if let prev = previousFrame, prev != absoluteFrame {
            onSizeChange?(absoluteFrame)
        }
        previousFrame = absoluteFrame

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    cachedFrameKey = nil
                    cachedFrameCommandRange = startIndex..<startIndex
                    markSubtreeRendered()
                    return
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        // Gap/Fix: Opacity group compositing — when a view has opacity < 1 AND
        // has children, the correct result requires compositing into an offscreen
        // texture first. Without that, each child is blended individually, which
        // causes overlapping children to double-blend.
        // TODO: Opacity < 1 with overlapping children double-blends. Requires render-to-texture for correct compositing.
        // GPUI/Zed instead carries opacity as an inherited paint scalar.
        let effectiveOpacity = inheritedOpacity * Float(opacity)
        let resolvedHoverEffect = resolvedActiveHoverEffect
        let cacheKey = ViewPaintCacheKey(
            bounds: absoluteFrame,
            contentMask: effectiveClip,
            opacity: effectiveOpacity,
            displayScale: displayScale,
            isHovered: isHovered,
            hoverEffect: resolvedHoverEffect,
            isFocused: isFocused,
            isFocusEffectDisabled: isFocusEffectDisabled
        )
        guard effectiveOpacity > 0 else {
            cachedFrameKey = cacheKey
            cachedFrameCommandRange = startIndex..<startIndex
            markSubtreeRendered()
            return
        }

        if
            let previousRenderedFrame,
            !hasDirtySubtree,
            cachedFrameKey == cacheKey,
            let previousRange = cachedFrameCommandRange
        {
            commands.append(contentsOf: previousRenderedFrame.commands[previousRange])
            let delta = startIndex - previousRange.lowerBound
            shiftCachedFrameRangesRecursively(by: delta)
            cachedFrameKey = cacheKey
            cachedFrameCommandRange = startIndex..<commands.count
            markSubtreeRendered()
            replayCount += 1
            return
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        if let hoverShadow = hoverEffectShadowCommand(
            for: absoluteFrame,
            inheritedClip: inheritedClip,
            opacity: effectiveOpacity
        ) {
            commands.append(.fillRect(hoverShadow))
        }

        let effectiveShadowColor = shadowColor.multipliedAlpha(by: effectiveOpacity)
        if effectiveShadowColor.alpha > 0 {
            let shadowRect = absoluteFrame
                .outset(by: max(0, shadowSpread))
                .offsetBy(dx: shadowOffset.x, dy: shadowOffset.y)

            if baseClipAllowsDrawing(baseClip: inheritedClip, rect: shadowRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: shadowRect,
                            color: effectiveShadowColor,
                            cornerRadius: cornerRadius + max(0, shadowSpread),
                            clipRect: inheritedClip
                        )
                    )
                )
            }
        }

        if let focusEffect = focusEffectCommand(
            for: absoluteFrame,
            inheritedClip: inheritedClip,
            opacity: effectiveOpacity
        ) {
            commands.append(.fillRect(focusEffect))
        }

        let effectiveOutlineColor = outlineColor.multipliedAlpha(by: effectiveOpacity)
        if effectiveOutlineColor.alpha > 0, outlineWidth > 0 {
            let outlineRect = absoluteFrame.outset(by: outlineWidth)
            if baseClipAllowsDrawing(baseClip: inheritedClip, rect: outlineRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: outlineRect,
                            color: effectiveOutlineColor,
                            cornerRadius: cornerRadius + outlineWidth,
                            clipRect: inheritedClip
                        )
                    )
                )
            }
        }

        let effectiveBorderColor = borderColor.multipliedAlpha(by: effectiveOpacity)
        if effectiveBorderColor.alpha > 0, borderWidth > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: absoluteFrame) {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: absoluteFrame,
                        color: effectiveBorderColor,
                        cornerRadius: cornerRadius,
                        clipRect: effectiveClip
                    )
                )
            )
        }

        let fillRect = borderWidth > 0 ? absoluteFrame.inset(by: borderWidth) : absoluteFrame
        let fillCornerRadius = max(0, cornerRadius - borderWidth)

        var resolvedBackgroundGradient = backgroundGradient
        if var gradient = resolvedBackgroundGradient {
            gradient.stops = gradient.stops.map { stop in
                GradientStop(color: stop.color.multipliedAlpha(by: effectiveOpacity), position: stop.position)
            }
            resolvedBackgroundGradient = gradient
        }
        let resolvedBackgroundColor = backgroundColor?.multipliedAlpha(by: effectiveOpacity)
            ?? resolvedBackgroundGradient?.startColor
        if let resolvedBackgroundColor, resolvedBackgroundColor.alpha > 0, fillRect.size.width > 0, fillRect.size.height > 0 {
            if baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: fillRect,
                            color: resolvedBackgroundColor,
                            cornerRadius: fillCornerRadius,
                            clipRect: effectiveClip,
                            gradient: resolvedBackgroundGradient
                        )
                    )
                )
            }
        }

        if let hoverOverlay = hoverEffectOverlayCommand(
            for: fillRect,
            cornerRadius: fillCornerRadius,
            clipRect: effectiveClip,
            opacity: effectiveOpacity
        ) {
            commands.append(.fillRect(hoverOverlay))
        }

        let drawsRedactionPlaceholder = redactionReasons.contains(.placeholder)
            && (bitmapSurface != nil || (text?.isEmpty == false))
            && fillRect.size.width > 0
            && fillRect.size.height > 0
            && baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect)

        if drawsRedactionPlaceholder {
            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: fillRect,
                        color: retainedRedactionPlaceholderBaseColor.multipliedAlpha(by: effectiveOpacity),
                        cornerRadius: retainedRedactionPlaceholderCornerRadius(for: fillRect),
                        clipRect: effectiveClip
                    )
                )
            )
        } else if let bitmapSurface, fillRect.size.width > 0, fillRect.size.height > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
            commands.append(
                .drawBitmap(
                    DrawBitmapCommand(
                        rect: fillRect,
                        bitmap: bitmapSurface,
                        opacity: effectiveOpacity,
                        clipRect: effectiveClip
                    )
                )
            )
        }

        if !drawsRedactionPlaceholder, let text, !text.isEmpty, baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
            let effectiveTextStyle = textStyle.multipliedOpacity(by: effectiveOpacity)
            if !NativeTextRenderer.appendCommands(for: text, in: fillRect, style: effectiveTextStyle, scaleFactor: displayScale, clipRect: effectiveClip, into: &commands) {
                PixelFont.appendCommands(
                    for: text,
                    in: fillRect,
                    style: effectiveTextStyle,
                    clipRect: effectiveClip,
                    into: &commands
                )
            }
        }

        // Gap/Fix: Emit blur render command — apply Gaussian blur over
        // the view's content region when blurRadius is set.
        // The active demo renderer does not implement post-process blur yet.
        // Keep the property on ViewNode so the API surface can evolve, but do
        // not emit a command that the current backend would silently drop.

        // Gap/Fix: Z-index sibling sort — children are drawn in zIndex
        // order (stable sort preserves original order for equal zIndex).
        // NOTE: zIndex only sorts among siblings within the same parent.
        // For cross-subtree ordering (e.g. modals, overlays, popups),
        // views should be added at the root level or to a dedicated
        // overlay container rather than relying on zIndex across
        // different subtrees.
        for child in orderedChildrenForPaint() {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.appendCommands(
                into: &commands,
                parentOrigin: childOrigin,
                inheritedClip: effectiveClip,
                inheritedOpacity: effectiveOpacity,
                previousRenderedFrame: previousRenderedFrame,
                displayScale: displayScale,
                replayCount: &replayCount
            )
        }

        cachedFrameKey = cacheKey
        cachedFrameCommandRange = startIndex..<commands.count
        markSubtreeRendered()
    }

    fileprivate func hitTest(at point: Point, parentOrigin: Point, inheritedClip: Rect?) -> ViewNode? {
        if isHidden {
            return nil
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    return nil
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        if let effectiveClip, !effectiveClip.contains(point) {
            return nil
        }

        // Gap/Fix: Hit testing with transforms — apply the inverse of the view's
        // transform (centered on the view's center) to the test point before
        // checking containment. This ensures rotated/scaled views are hit-tested
        // in their local coordinate space.
        let testPoint: Point
        if !transform.isIdentity {
            let cx = absoluteFrame.origin.x + absoluteFrame.size.width * 0.5
            let cy = absoluteFrame.origin.y + absoluteFrame.size.height * 0.5
            let centeredTransform = Transform2D.translation(x: -cx, y: -cy)
                .concatenating(transform)
                .concatenating(.translation(x: cx, y: cy))
            if let inverseTransform = centeredTransform.inverseOrNil() {
                testPoint = inverseTransform.applying(to: point)
            } else {
                testPoint = point
            }
        } else {
            testPoint = point
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in children.reversed() {
            if let hitNode = child.hitTest(at: testPoint, parentOrigin: childOrigin, inheritedClip: effectiveClip) {
                return hitNode
            }
        }

        if isHitTestVisible, absoluteFrame.contains(testPoint) {
            guard containsInteractionPoint(testPoint, in: absoluteFrame) else {
                return nil
            }
            return self
        }

        return nil
    }

    var resolvedActiveHoverEffect: RetainedHoverEffect? {
        guard isHovered, !isHoverEffectDisabled, let hoverEffect else {
            return nil
        }

        switch hoverEffect {
        case .automatic:
            return .highlight
        case .highlight, .lift:
            return hoverEffect
        }
    }

    func hoverEffectShadowCommand(
        for absoluteFrame: Rect,
        inheritedClip: Rect?,
        opacity: Float
    ) -> FillRectCommand? {
        guard resolvedActiveHoverEffect == .lift else {
            return nil
        }

        let shadowColor = Color(red: 0, green: 0, blue: 0, alpha: 0.18).multipliedAlpha(by: opacity)
        guard shadowColor.alpha > 0 else {
            return nil
        }

        let spread = max(3, min(12, min(absoluteFrame.size.width, absoluteFrame.size.height) * 0.08))
        let shadowRect = absoluteFrame
            .outset(by: spread)
            .offsetBy(dx: 0, dy: max(1, spread * 0.35))
        guard baseClipAllowsDrawing(baseClip: inheritedClip, rect: shadowRect) else {
            return nil
        }

        return FillRectCommand(
            rect: shadowRect,
            color: shadowColor,
            cornerRadius: effectCornerRadius(for: absoluteFrame, kinds: .hoverEffect, fallback: cornerRadius) + spread,
            clipRect: inheritedClip
        )
    }

    func hoverEffectOverlayCommand(
        for fillRect: Rect,
        cornerRadius: Double,
        clipRect: Rect?,
        opacity: Float
    ) -> FillRectCommand? {
        guard let effect = resolvedActiveHoverEffect else {
            return nil
        }

        let alpha: Float
        switch effect {
        case .automatic, .highlight:
            alpha = 0.10
        case .lift:
            alpha = 0.07
        }

        let color = Color(red: 1, green: 1, blue: 1, alpha: alpha).multipliedAlpha(by: opacity)
        guard color.alpha > 0, fillRect.size.width > 0, fillRect.size.height > 0 else {
            return nil
        }
        guard baseClipAllowsDrawing(baseClip: clipRect, rect: fillRect) else {
            return nil
        }

        return FillRectCommand(
            rect: fillRect,
            color: color,
            cornerRadius: effectCornerRadius(for: fillRect, kinds: .hoverEffect, fallback: cornerRadius),
            clipRect: clipRect
        )
    }

    func focusEffectCommand(
        for absoluteFrame: Rect,
        inheritedClip: Rect?,
        opacity: Float
    ) -> FillRectCommand? {
        guard isFocused, isFocusable, !isFocusEffectDisabled else {
            return nil
        }

        let width = 2.0
        let ringRect = absoluteFrame.outset(by: width)
        guard ringRect.size.width > 0, ringRect.size.height > 0 else {
            return nil
        }
        guard baseClipAllowsDrawing(baseClip: inheritedClip, rect: ringRect) else {
            return nil
        }

        let color = Color(red: 0.25, green: 0.55, blue: 1, alpha: 0.75).multipliedAlpha(by: opacity)
        guard color.alpha > 0 else {
            return nil
        }

        return FillRectCommand(
            rect: ringRect,
            color: color,
            cornerRadius: effectCornerRadius(for: absoluteFrame, kinds: .focusEffect, fallback: cornerRadius) + width,
            clipRect: inheritedClip
        )
    }

    private func effectCornerRadius(
        for rect: Rect,
        kinds: RetainedContentShapeKinds,
        fallback: Double
    ) -> Double {
        guard let shape = contentShapes.last(where: { $0.kinds.intersection(kinds).isEmpty == false }) else {
            return fallback
        }

        return shape.style.visualCornerRadius(in: rect)
    }

    fileprivate func containsInteractionPoint(_ point: Point, in frame: Rect) -> Bool {
        guard frame.contains(point) else {
            return false
        }

        guard let contentShape = contentShapes.last(where: { $0.kinds.contains(.interaction) }) else {
            return true
        }

        return contentShape.style.contains(point, in: frame)
    }

    fileprivate func scrollTarget(at point: Point, axis: ScrollAxis? = nil, parentOrigin: Point, inheritedClip: Rect?) -> ViewNode? {
        if isHidden {
            return nil
        }

        let absoluteFrame = Rect(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y,
            width: resolvedFrame.size.width,
            height: resolvedFrame.size.height
        )

        var effectiveClip = inheritedClip
        if clipsToBounds {
            if let inheritedClip {
                guard let clippedRect = inheritedClip.intersected(with: absoluteFrame) else {
                    return nil
                }

                effectiveClip = clippedRect
            } else {
                effectiveClip = absoluteFrame
            }
        }

        if let effectiveClip, !effectiveClip.contains(point) {
            return nil
        }

        let absoluteOrigin = Point(
            x: parentOrigin.x + resolvedFrame.origin.x,
            y: parentOrigin.y + resolvedFrame.origin.y
        )

        let childOrigin = Point(
            x: absoluteOrigin.x - (scrollAxis == .horizontal ? resolvedScrollOffset : 0),
            y: absoluteOrigin.y - (scrollAxis == .vertical ? resolvedScrollOffset : 0)
        )

        for child in children.reversed() {
            if let target = child.scrollTarget(at: point, axis: axis, parentOrigin: childOrigin, inheritedClip: effectiveClip) {
                return target
            }
        }

        if isScrollable,
           absoluteFrame.contains(point),
           axis == nil || scrollAxis == axis
        {
            return self
        }

        return nil
    }

    private func invalidateRuntime(_ flags: DirtyFlags = .all) {
        markDirty(flags)
        runtime?.invalidate(flags)
    }

    var hasDirtySubtree: Bool {
        !subtreeDirtyFlags.isEmpty
    }

    func markSubtreeRendered() {
        subtreeDirtyFlags = []
    }

    private func markDirty(_ flags: DirtyFlags) {
        var currentNode: ViewNode? = self
        while let node = currentNode {
            node.subtreeDirtyFlags.insert(flags)
            currentNode = node.parent
        }
    }

    func shiftCachedFrameRangesRecursively(by delta: Int) {
        if let existingRange = cachedFrameCommandRange {
            cachedFrameCommandRange = (existingRange.lowerBound + delta)..<(existingRange.upperBound + delta)
        }

        for child in children {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.shiftCachedFrameRangesRecursively(by: delta)
        }
    }

    func shiftCachedPrepaintRangesRecursively(
        dispatchDelta: Int,
        interactionDelta: Int,
        focusOrderDelta: Int,
        deferredSubtreeDelta: Int,
        deferredDrawDelta: Int,
        deferredPriorityDelta: Int
    ) {
        if let existingRange = cachedPrepaintRange {
            cachedPrepaintRange = PrepaintStateRange(
                start: PrepaintStateIndex(
                    dispatchIndex: existingRange.start.dispatchIndex + dispatchDelta,
                    interactionIndex: existingRange.start.interactionIndex + interactionDelta,
                    focusOrderIndex: existingRange.start.focusOrderIndex + focusOrderDelta,
                    deferredSubtreeIndex: existingRange.start.deferredSubtreeIndex + deferredSubtreeDelta,
                    deferredDrawIndex: existingRange.start.deferredDrawIndex + deferredDrawDelta,
                    deferredPriority: existingRange.start.deferredPriority + deferredPriorityDelta
                ),
                end: PrepaintStateIndex(
                    dispatchIndex: existingRange.end.dispatchIndex + dispatchDelta,
                    interactionIndex: existingRange.end.interactionIndex + interactionDelta,
                    focusOrderIndex: existingRange.end.focusOrderIndex + focusOrderDelta,
                    deferredSubtreeIndex: existingRange.end.deferredSubtreeIndex + deferredSubtreeDelta,
                    deferredDrawIndex: existingRange.end.deferredDrawIndex + deferredDrawDelta,
                    deferredPriority: existingRange.end.deferredPriority + deferredPriorityDelta
                )
            )
        }

        for child in children {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.shiftCachedPrepaintRangesRecursively(
                dispatchDelta: dispatchDelta,
                interactionDelta: interactionDelta,
                focusOrderDelta: focusOrderDelta,
                deferredSubtreeDelta: deferredSubtreeDelta,
                deferredDrawDelta: deferredDrawDelta,
                deferredPriorityDelta: deferredPriorityDelta
            )
        }
    }

    func shiftCachedSceneRangesRecursively(by delta: Int) {
        if let existingRange = cachedScenePaintRange {
            cachedScenePaintRange = (existingRange.lowerBound + delta)..<(existingRange.upperBound + delta)
        }

        for child in children {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.shiftCachedSceneRangesRecursively(by: delta)
        }
    }

    fileprivate func sizeThatFits(in constraints: LayoutConstraints) -> Size {
        let displayScale = runtime?.displayScale ?? 1.0
        let effectiveConstraints = applyingLayoutConstraints(to: constraints)
        let cacheKey = ViewMeasureCacheKey(constraints: effectiveConstraints, displayScale: displayScale)
        let layoutDirtyFlags = subtreeDirtyFlags.intersection([.layout, .children])
        if layoutDirtyFlags.isEmpty, cachedMeasureKey == cacheKey, let cachedMeasuredSize {
            runtime?.recordMeasureReuse()
            return cachedMeasuredSize
        }

        var measuredSize = bitmapContentSize() ?? textContentSize(in: effectiveConstraints) ?? .zero

        switch layoutMode {
        case .absolute:
            var maxChildX = measuredSize.width
            var maxChildY = measuredSize.height

            for child in children where !child.isHidden {
                let childConstraints = LayoutConstraints(
                    maxWidth: remainingConstraintExtent(effectiveConstraints.maxWidth, offset: child.frame.origin.x),
                    maxHeight: remainingConstraintExtent(effectiveConstraints.maxHeight, offset: child.frame.origin.y)
                )
                let childSize = child.sizeThatFits(in: childConstraints)
                let resolvedWidth = child.explicitWidth ?? childSize.width
                let resolvedHeight = child.explicitHeight ?? childSize.height
                maxChildX = max(maxChildX, child.frame.origin.x + resolvedWidth)
                maxChildY = max(maxChildY, child.frame.origin.y + resolvedHeight)
            }

            measuredSize = Size(width: maxChildX, height: maxChildY)

        case .stack(let stackLayout):
            let contentConstraints = insetConstraints(effectiveConstraints, by: stackLayout.padding)
            let childConstraints = stackChildConstraints(for: contentConstraints, axis: stackLayout.axis)
            let visibleChildren = children.filter { !$0.isHidden }
            let childSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
            let spacingTotal = stackLayoutSpacingTotal(count: childSizes.count, spacing: stackLayout.spacing)
            let mainExtent = childSizes.reduce(0.0) { partialResult, size in
                partialResult + (stackLayout.axis == .vertical ? size.height : size.width)
            } + spacingTotal + stackMainPadding(for: stackLayout)
            let crossExtent = (childSizes.map { size in
                stackLayout.axis == .vertical ? size.width : size.height
            }.max() ?? 0) + stackCrossPadding(for: stackLayout)

            measuredSize = Size(
                width: stackLayout.axis == .vertical ? crossExtent : mainExtent,
                height: stackLayout.axis == .vertical ? mainExtent : crossExtent
            )

        case .flex(let flexStyle):
            let visibleChildren = children.filter { !$0.isHidden }
            let childSizes = visibleChildren.map { $0.sizeThatFits(in: .unconstrained) }
            let isRow = flexStyle.direction == .row || flexStyle.direction == .rowReverse
            let gapTotal = visibleChildren.count > 1 ? flexStyle.gap * Double(visibleChildren.count - 1) : 0

            let mainExtent = childSizes.reduce(0.0) { partialResult, size in
                partialResult + (isRow ? size.width : size.height)
            } + gapTotal + (isRow
                ? flexStyle.padding.leading + flexStyle.padding.trailing
                : flexStyle.padding.top + flexStyle.padding.bottom)

            let crossExtent = (childSizes.map { size in
                isRow ? size.height : size.width
            }.max() ?? 0) + (isRow
                ? flexStyle.padding.top + flexStyle.padding.bottom
                : flexStyle.padding.leading + flexStyle.padding.trailing)

            measuredSize = Size(
                width: isRow ? mainExtent : crossExtent,
                height: isRow ? crossExtent : mainExtent
            )
        }

        let resolvedSize = applyingExplicitDimensions(to: measuredSize, constraints: effectiveConstraints)
        cachedMeasureKey = cacheKey
        cachedMeasuredSize = resolvedSize
        return resolvedSize
    }

    public func intrinsicContentSize() -> Size {
        sizeThatFits(in: .unconstrained)
    }

    private func textContentSize(in constraints: LayoutConstraints) -> Size? {
        guard let text, !text.isEmpty else {
            return nil
        }

        let displayScale = runtime?.displayScale ?? 1.0
        let maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : nil
        return runtime?.textSystem.measure(text, style: textStyle, maxWidth: maxWidth, scaleFactor: displayScale)
            ?? NativeTextRenderer.measure(text, style: textStyle, scaleFactor: displayScale, maxWidth: maxWidth)
            ?? PixelFont.measure(text, style: textStyle, maxWidth: maxWidth)
    }

    private func bitmapContentSize() -> Size? {
        guard let bitmapSurface, bitmapSurface.width > 0, bitmapSurface.height > 0 else {
            return nil
        }

        return Size(width: Double(bitmapSurface.width), height: Double(bitmapSurface.height))
    }

    private func applyingExplicitDimensions(to size: Size, constraints: LayoutConstraints) -> Size {
        let measuredWidth = explicitWidth ?? size.width
        let measuredHeight = explicitHeight ?? size.height

        return Size(
            width: clampedExtent(measuredWidth, min: constraints.minWidth, max: constraints.maxWidth),
            height: clampedExtent(measuredHeight, min: constraints.minHeight, max: constraints.maxHeight)
        )
    }

    private func applyingLayoutConstraints(to constraints: LayoutConstraints) -> LayoutConstraints {
        let fixedConstraints = applyingFixedSizeAxes(to: constraints)
        guard let layoutConstraints else {
            return fixedConstraints
        }

        let minWidth = max(fixedConstraints.minWidth, layoutConstraints.minWidth)
        let minHeight = max(fixedConstraints.minHeight, layoutConstraints.minHeight)

        return LayoutConstraints(
            minWidth: minWidth,
            maxWidth: max(minWidth, minimumFiniteExtent(fixedConstraints.maxWidth, layoutConstraints.maxWidth)),
            minHeight: minHeight,
            maxHeight: max(minHeight, minimumFiniteExtent(fixedConstraints.maxHeight, layoutConstraints.maxHeight))
        )
    }

    private func applyingFixedSizeAxes(to constraints: LayoutConstraints) -> LayoutConstraints {
        guard let fixedSizeAxes else {
            return constraints
        }

        return LayoutConstraints(
            minWidth: constraints.minWidth,
            maxWidth: fixedSizeAxes.horizontal ? .infinity : constraints.maxWidth,
            minHeight: constraints.minHeight,
            maxHeight: fixedSizeAxes.vertical ? .infinity : constraints.maxHeight
        )
    }

    private var explicitWidth: Double? {
        if let preferredSize, preferredSize.width > 0 {
            return preferredSize.width
        }

        if frame.size.width > 0 {
            return frame.size.width
        }

        return nil
    }

    private var explicitHeight: Double? {
        if let preferredSize, preferredSize.height > 0 {
            return preferredSize.height
        }

        if frame.size.height > 0 {
            return frame.size.height
        }

        return nil
    }

    private func allocateMainSizes(
        desiredSizes: [Double],
        children: [ViewNode],
        availableExtent: Double
    ) -> [Double] {
        var allocatedSizes = desiredSizes
        let desiredExtent = desiredSizes.reduce(0, +)

        if desiredExtent > availableExtent {
            shrinkMainSizes(&allocatedSizes, children: children, deficit: desiredExtent - availableExtent)
        } else if desiredExtent < availableExtent {
            growMainSizes(&allocatedSizes, children: children, extraExtent: availableExtent - desiredExtent)
        }

        return allocatedSizes
    }

    private func growMainSizes(_ sizes: inout [Double], children: [ViewNode], extraExtent: Double) {
        let participantIndices = children.indices.filter { children[$0].layoutPriority > 0 }
        guard !participantIndices.isEmpty else {
            return
        }

        let totalPriority = participantIndices.reduce(0.0) { partialResult, index in
            partialResult + children[index].layoutPriority
        }
        guard totalPriority > 0 else {
            return
        }

        var remainingExtent = extraExtent
        for (offset, index) in participantIndices.enumerated() {
            let share: Double
            if offset == participantIndices.count - 1 {
                share = remainingExtent
            } else {
                share = extraExtent * (children[index].layoutPriority / totalPriority)
                remainingExtent -= share
            }

            sizes[index] += share
        }
    }

    private func shrinkMainSizes(_ sizes: inout [Double], children: [ViewNode], deficit: Double) {
        var remainingDeficit = deficit
        let priorities = Array(Set(children.map(\.layoutPriority))).sorted()

        for priority in priorities where remainingDeficit > 0 {
            let indices = children.indices.filter { children[$0].layoutPriority == priority && sizes[$0] > 0 }
            guard !indices.isEmpty else {
                continue
            }

            let shrinkCapacity = indices.reduce(0.0) { partialResult, index in
                partialResult + sizes[index]
            }
            guard shrinkCapacity > 0 else {
                continue
            }

            let targetReduction = min(remainingDeficit, shrinkCapacity)
            var remainingReduction = targetReduction

            for (offset, index) in indices.enumerated() {
                let reduction: Double
                if offset == indices.count - 1 {
                    reduction = remainingReduction
                } else {
                    reduction = targetReduction * (sizes[index] / shrinkCapacity)
                    remainingReduction -= reduction
                }

                let appliedReduction = min(sizes[index], reduction)
                sizes[index] -= appliedReduction
            }

            remainingDeficit -= targetReduction
        }
    }

    fileprivate var isScrollable: Bool {
        scrollAxis != nil
    }

    fileprivate var isDraggable: Bool {
        onDragStart != nil || onDragChange != nil || onDragEnd != nil
    }

    fileprivate var maxScrollOffset: Double {
        switch scrollAxis {
        case .horizontal:
            return max(0, resolvedContentSize.width - resolvedFrame.size.width)
        case .vertical:
            return max(0, resolvedContentSize.height - resolvedFrame.size.height)
        case nil:
            return 0
        }
    }

    fileprivate func applyMouseWheelDelta(_ delta: Double) -> Bool {
        guard isScrollable else {
            return false
        }

        let nextOffset = clampedScrollOffset(for: scrollOffset - delta * scrollStep)
        guard nextOffset != scrollOffset else {
            return false
        }

        scrollOffset = nextOffset
        return true
    }

    fileprivate func applyKeyboardScroll(_ key: KeyboardKey) -> Bool {
        guard isScrollable else {
            return false
        }

        switch (scrollAxis, key) {
        case (.vertical, .downArrow), (.horizontal, .rightArrow):
            return applyScrollDelta(scrollStep)
        case (.vertical, .upArrow), (.horizontal, .leftArrow):
            return applyScrollDelta(-scrollStep)
        case (_, .pageDown):
            return applyScrollDelta((scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width) * 0.85)
        case (_, .pageUp):
            return applyScrollDelta(-(scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width) * 0.85)
        case (_, .home):
            return setScrollOffset(0)
        case (_, .end):
            return setScrollOffset(maxScrollOffset)
        default:
            return false
        }
    }

    fileprivate func applyScrollIndicatorDrag(startOffset: Double, delta: Double, travel: Double) -> Bool {
        guard maxScrollOffset > 0, travel > 0 else {
            return false
        }

        let translatedOffset = startOffset + delta * (maxScrollOffset / travel)
        return setScrollOffset(translatedOffset)
    }

    func scrollIndicatorRect(in absoluteFrame: Rect) -> Rect? {
        guard showsScrollIndicator, isScrollable, maxScrollOffset > 0, scrollIndicatorColor.alpha > 0 else {
            return nil
        }

        let indicatorInset = 6.0
        let indicatorThickness = max(4, scrollIndicatorThickness)

        switch scrollAxis {
        case .vertical:
            let trackHeight = max(0, absoluteFrame.size.height - indicatorInset * 2)
            guard trackHeight > 0 else { return nil }
            let visibleRatio = max(0.08, absoluteFrame.size.height / max(resolvedContentSize.height, absoluteFrame.size.height))
            let indicatorHeight = max(24, trackHeight * visibleRatio)
            let travel = max(0, trackHeight - indicatorHeight)
            let progress = maxScrollOffset > 0 ? resolvedScrollOffset / maxScrollOffset : 0
            return Rect(
                x: absoluteFrame.maxX - indicatorInset - indicatorThickness,
                y: absoluteFrame.origin.y + indicatorInset + travel * progress,
                width: indicatorThickness,
                height: indicatorHeight
            )

        case .horizontal:
            let trackWidth = max(0, absoluteFrame.size.width - indicatorInset * 2)
            guard trackWidth > 0 else { return nil }
            let visibleRatio = max(0.08, absoluteFrame.size.width / max(resolvedContentSize.width, absoluteFrame.size.width))
            let indicatorWidth = max(24, trackWidth * visibleRatio)
            let travel = max(0, trackWidth - indicatorWidth)
            let progress = maxScrollOffset > 0 ? resolvedScrollOffset / maxScrollOffset : 0
            return Rect(
                x: absoluteFrame.origin.x + indicatorInset + travel * progress,
                y: absoluteFrame.maxY - indicatorInset - indicatorThickness,
                width: indicatorWidth,
                height: indicatorThickness
            )

        case nil:
            return nil
        }
    }

    fileprivate func scrollIndicatorTrack(in absoluteFrame: Rect) -> ScrollIndicatorTrack? {
        guard let indicatorRect = scrollIndicatorRect(in: absoluteFrame), let scrollAxis else {
            return nil
        }

        let inset = 6.0

        switch scrollAxis {
        case .vertical:
            let trackLength = max(0, absoluteFrame.size.height - inset * 2)
            return ScrollIndicatorTrack(
                axis: .vertical,
                origin: absoluteFrame.origin.y + inset,
                travel: max(0, trackLength - indicatorRect.size.height),
                indicatorRect: indicatorRect
            )

        case .horizontal:
            let trackLength = max(0, absoluteFrame.size.width - inset * 2)
            return ScrollIndicatorTrack(
                axis: .horizontal,
                origin: absoluteFrame.origin.x + inset,
                travel: max(0, trackLength - indicatorRect.size.width),
                indicatorRect: indicatorRect
            )
        }
    }

    private func clampedScrollOffset(for value: Double) -> Double {
        min(max(value, 0), maxScrollOffset)
    }

    private func applyScrollDelta(_ delta: Double) -> Bool {
        setScrollOffset(scrollOffset + delta)
    }

    private func setScrollOffset(_ value: Double) -> Bool {
        let nextOffset = clampedScrollOffset(for: value)
        guard nextOffset != scrollOffset else {
            return false
        }

        scrollOffset = nextOffset
        return true
    }

    fileprivate func color(for property: AnimatedColorProperty) -> Color {
        switch property {
        case .background:
            return backgroundColor ?? .clear
        case .border:
            return borderColor
        case .outline:
            return outlineColor
        case .shadow:
            return shadowColor
        case .scrollIndicator:
            return scrollIndicatorColor
        }
    }

    fileprivate func setColor(_ color: Color, for property: AnimatedColorProperty) {
        switch property {
        case .background:
            backgroundColor = color
        case .border:
            borderColor = color
        case .outline:
            outlineColor = color
        case .shadow:
            shadowColor = color
        case .scrollIndicator:
            scrollIndicatorColor = color
        }
    }
}

private func insetConstraints(_ constraints: LayoutConstraints, by padding: EdgeInsets) -> LayoutConstraints {
    LayoutConstraints(
        minWidth: max(0, constraints.minWidth - padding.leading - padding.trailing),
        maxWidth: remainingConstraintExtent(constraints.maxWidth, offset: padding.leading + padding.trailing),
        minHeight: max(0, constraints.minHeight - padding.top - padding.bottom),
        maxHeight: remainingConstraintExtent(constraints.maxHeight, offset: padding.top + padding.bottom)
    )
}

private func stackChildConstraints(for size: Size, axis: StackAxis) -> LayoutConstraints {
    switch axis {
    case .vertical:
        return LayoutConstraints(maxWidth: max(0, size.width))
    case .horizontal:
        return LayoutConstraints(maxHeight: max(0, size.height))
    }
}

private func stackChildConstraints(for constraints: LayoutConstraints, axis: StackAxis) -> LayoutConstraints {
    switch axis {
    case .vertical:
        return LayoutConstraints(maxWidth: constraints.maxWidth)
    case .horizontal:
        return LayoutConstraints(maxHeight: constraints.maxHeight)
    }
}

private func stackLayoutSpacingTotal(count: Int, spacing: Double) -> Double {
    guard count > 1 else {
        return 0
    }

    return Double(count - 1) * spacing
}

private func stackMainPadding(for layout: StackLayout) -> Double {
    switch layout.axis {
    case .vertical:
        return layout.padding.top + layout.padding.bottom
    case .horizontal:
        return layout.padding.leading + layout.padding.trailing
    }
}

private func stackCrossPadding(for layout: StackLayout) -> Double {
    switch layout.axis {
    case .vertical:
        return layout.padding.leading + layout.padding.trailing
    case .horizontal:
        return layout.padding.top + layout.padding.bottom
    }
}

private func stackScrollAxis(for axis: StackAxis) -> ScrollAxis {
    switch axis {
    case .vertical:
        return .vertical
    case .horizontal:
        return .horizontal
    }
}

private func remainingConstraintExtent(_ maxExtent: Double, offset: Double) -> Double {
    guard maxExtent.isFinite else {
        return .infinity
    }

    return max(0, maxExtent - offset)
}

private func minimumFiniteExtent(_ lhs: Double, _ rhs: Double) -> Double {
    if lhs.isFinite && rhs.isFinite {
        return min(lhs, rhs)
    }

    if lhs.isFinite {
        return lhs
    }

    return rhs
}

private func clampedExtent(_ extent: Double, min minimum: Double, max maximum: Double) -> Double {
    var value = max(extent, minimum)
    if maximum.isFinite {
        value = min(value, maximum)
    }
    return value
}

@MainActor
public final class RetainedViewRuntime {
    private static let buttonRepeatInitialDelay = 0.45
    private static let buttonRepeatInterval = 0.08

    public let root: ViewNode

    public var displayScale: Double {
        didSet {
            // Gap/Fix: Text cache granular invalidation — only invalidate the
            // text raster cache when the scale factor actually changed, rather
            // than clearing it on every dirty pass.
            if oldValue != displayScale {
                textRasterCache?.clear()
            }
            invalidate()
        }
    }

    public var clearColor: Color {
        didSet { invalidate() }
    }

    public var hasActiveAnimations: Bool {
        !colorAnimations.isEmpty || buttonRepeatState != nil
    }

    // Gap/Fix: Granular dirty tracking — DirtyFlags replaces single boolean.
    public private(set) var dirtyFlags: DirtyFlags = .all
    public var isDirty: Bool { !dirtyFlags.isEmpty }
    private var cachedFrame: RenderFrame?
    private var cachedScene: GPUIScene?
    private var prepaintState = RuntimePrepaintState()

    /// Access to current prepaint state for testing deferred scene-path behavior.
    @MainActor
    internal var currentPrepaintState: RuntimePrepaintState { prepaintState }
    internal private(set) var lastFrameReplayCount = 0
    internal private(set) var lastSceneReplayCount = 0
    internal private(set) var lastLayoutReuseCount = 0
    internal private(set) var lastMeasureReuseCount = 0
    internal private(set) var lastPrepaintReplayCount = 0
    internal private(set) var lastDeferredOverlayReplayCount = 0
    internal private(set) var lastDeferredDrawFrameReplayCount = 0
    internal private(set) var lastDeferredDrawSceneReplayCount = 0
    let textSystem: WindowTextSystem
    private weak var hoveredNode: ViewNode?
    private weak var pressedNode: ViewNode?
    private weak var focusedNode: ViewNode?
    private weak var hoveredScrollIndicatorNode: ViewNode?
    private weak var activeScrollIndicatorNode: ViewNode?
    private var colorAnimations: [ColorAnimationKey: ViewColorAnimation] = [:]
    private var buttonRepeatState: ButtonRepeatState?
    private var scrollDragState: ScrollDragState?
    private var nodeDragState: NodeDragState?

    /// Optional text raster cache for scale-aware invalidation.
    public var textRasterCache: TextRasterCache?

    // Gap/Fix: Frame pacing enforcement — minimum interval between renders.
    public var minimumFrameInterval: Double?
    private var lastRenderTime: Double = 0

    public init(clearColor: Color = .black, root: ViewNode = ViewNode(), displayScale: Double = 1.0) {
        self.clearColor = clearColor
        self.root = root
        self.displayScale = displayScale
        self.textSystem = WindowTextSystem()
        self.root.setRuntime(self)
    }

    public func setRootSize(_ size: IntSize) {
        let nextSize = Size(width: Double(size.width), height: Double(size.height))
        if root.frame.size != nextSize {
            root.frame.size = nextSize
        }
    }

    public func renderFrame(at timestamp: Double = 0) -> RenderFrame {
        if let cachedFrame, !isDirty {
            lastFrameReplayCount = 0
            lastLayoutReuseCount = 0
            lastMeasureReuseCount = 0
            lastPrepaintReplayCount = 0
            lastDeferredOverlayReplayCount = 0
            lastDeferredDrawFrameReplayCount = 0
            lastDeferredDrawSceneReplayCount = 0
            return cachedFrame
        }

        // Gap/Fix: Frame pacing enforcement — if minimumFrameInterval is set,
        // skip re-rendering when called too soon after the previous render.
        if let interval = minimumFrameInterval, timestamp > 0, lastRenderTime > 0 {
            let elapsed = timestamp - lastRenderTime
            if elapsed < interval, let cachedFrame {
                lastFrameReplayCount = 0
                lastLayoutReuseCount = 0
                lastMeasureReuseCount = 0
                lastPrepaintReplayCount = 0
                lastDeferredOverlayReplayCount = 0
                lastDeferredDrawFrameReplayCount = 0
                lastDeferredDrawSceneReplayCount = 0
                return cachedFrame
            }
        }

        updateResolvedLayout()

        let previousFrame = cachedFrame
        var commands: [RenderCommand] = []
        var replayCount = 0
        var deferredDrawReplayCount = 0
        root.appendCommands(
            into: &commands,
            parentOrigin: .zero,
            inheritedClip: nil,
            previousRenderedFrame: previousFrame,
            displayScale: displayScale,
            replayCount: &replayCount
        )
        appendDeferredDraws(
            into: &commands,
            previousFrame: previousFrame,
            displayScale: displayScale,
            replayCount: &deferredDrawReplayCount
        )

        let frame = RenderFrame(clearColor: clearColor, commands: commands)
        lastFrameReplayCount = replayCount
        lastDeferredDrawFrameReplayCount = deferredDrawReplayCount
        lastDeferredDrawSceneReplayCount = 0
        cachedFrame = frame
        cachedScene = nil
        dirtyFlags = []
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return frame
    }

    /// Render the current view tree as a GPUIScene for batch rendering.
    public func renderScene(at timestamp: Double = 0) -> GPUIScene {
        if let cachedScene, !isDirty {
            lastSceneReplayCount = 0
            lastLayoutReuseCount = 0
            lastMeasureReuseCount = 0
            lastPrepaintReplayCount = 0
            lastDeferredOverlayReplayCount = 0
            lastDeferredDrawFrameReplayCount = 0
            lastDeferredDrawSceneReplayCount = 0
            return cachedScene
        }

        if let interval = minimumFrameInterval, timestamp > 0, lastRenderTime > 0 {
            let elapsed = timestamp - lastRenderTime
            if elapsed < interval, let cachedScene {
                lastSceneReplayCount = 0
                lastLayoutReuseCount = 0
                lastMeasureReuseCount = 0
                lastPrepaintReplayCount = 0
                lastDeferredOverlayReplayCount = 0
                lastDeferredDrawFrameReplayCount = 0
                lastDeferredDrawSceneReplayCount = 0
                return cachedScene
            }
        }

        updateResolvedLayout()
        let previousScene = cachedScene
        var replayCount = 0
        var deferredDrawReplayCount = 0
        var deferredDraws = prepaintState.deferredDraws
        let scene = ScenePainter.paint(
            root: root,
            clearColor: clearColor,
            surfaceSize: root.frame.size,
            displayScale: displayScale,
            textSystem: textSystem,
            previousScene: previousScene,
            deferredDraws: &deferredDraws,
            replayCount: &replayCount,
            deferredReplayCount: &deferredDrawReplayCount
        )
        prepaintState.deferredDraws = deferredDraws

        var cachedSceneCopy = scene
        cachedSceneCopy.glyphAtlas = nil
        cachedSceneCopy.pixelGlyphAtlas = nil
        lastSceneReplayCount = replayCount
        lastDeferredDrawSceneReplayCount = deferredDrawReplayCount
        lastDeferredDrawFrameReplayCount = 0
        cachedScene = cachedSceneCopy
        cachedFrame = nil
        dirtyFlags = []
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return scene
    }

    public func pointerMoved(to point: Point) {
        if let dragState = scrollDragState {
            guard let node = dragState.node else {
                scrollDragState = nil
                updateScrollIndicatorHover(to: nil)
                return
            }

            let delta = dragState.axis == .vertical ? point.y - dragState.startPoint.y : point.x - dragState.startPoint.x
            _ = node.applyScrollIndicatorDrag(startOffset: dragState.startOffset, delta: delta, travel: dragState.track.travel)
            updateScrollIndicatorHover(to: ScrollIndicatorHit(node: node, track: dragState.track))
            return
        }

        if let dragState = nodeDragState {
            guard let node = dragState.node else {
                nodeDragState = nil
                return
            }

            let delta = Point(x: point.x - dragState.startPoint.x, y: point.y - dragState.startPoint.y)
            node.onDragChange?(point, delta)
            return
        }

        updateHoverTarget(to: hitTest(at: point))
        updateScrollIndicatorHover(to: scrollIndicatorHit(at: point))
    }

    public func pointerExitedWindow() {
        updateHoverTarget(to: nil)
        if scrollDragState == nil {
            updateScrollIndicatorHover(to: nil)
        }
    }

    public func mouseWheel(at point: Point, delta: Double, axis: ScrollAxis? = nil) {
        let scrollTarget = scrollTarget(at: point, axis: axis) ?? nearestScrollableNode(from: hoveredNode, axis: axis)
        guard let scrollableNode = scrollTarget else {
            return
        }

        if scrollableNode.applyMouseWheelDelta(delta) {
            updateHoverTarget(to: hitTest(at: point))
        }
    }

    public func pointerDown(at point: Point) {
        if let scrollIndicatorHit = scrollIndicatorHit(at: point) {
            scrollDragState = ScrollDragState(node: scrollIndicatorHit.node, axis: scrollIndicatorHit.track.axis, startPoint: point, startOffset: scrollIndicatorHit.node.scrollOffset, track: scrollIndicatorHit.track)
            activeScrollIndicatorNode = scrollIndicatorHit.node
            animateColor(.scrollIndicator, of: scrollIndicatorHit.node, to: scrollIndicatorHit.node.scrollIndicatorActiveColor, duration: 0.10, at: Win32Window.currentTimestampSeconds())
            return
        }

        let hitNode = hitTest(at: point)
        if let draggableNode = nearestDraggableNode(from: hitNode) {
            nodeDragState = NodeDragState(node: draggableNode, startPoint: point)
            draggableNode.onDragStart?(point)
            updateHoverTarget(to: hitNode)
            return
        }

        updateFocusTarget(to: nearestFocusableNode(from: hitNode))
        updateHoverTarget(to: hitNode)
        pressedNode = hitNode
        hitNode?.onPointerDown?()
        beginButtonRepeatIfNeeded(for: hitNode)
    }

    public func pointerUp(at point: Point) {
        if let dragState = scrollDragState {
            scrollDragState = nil
            activeScrollIndicatorNode = nil
            let nextIndicatorHit = scrollIndicatorHit(at: point)
            updateScrollIndicatorHover(to: nextIndicatorHit)

            if let node = dragState.node {
                let targetColor = nextIndicatorHit?.node === node ? node.scrollIndicatorHoverColor : node.scrollIndicatorIdleColor
                animateColor(.scrollIndicator, of: node, to: targetColor, duration: 0.12, at: Win32Window.currentTimestampSeconds())
            }
            return
        }

        if let dragState = nodeDragState {
            nodeDragState = nil
            if let node = dragState.node {
                let delta = Point(x: point.x - dragState.startPoint.x, y: point.y - dragState.startPoint.y)
                node.onDragEnd?(point, delta)
            }
            updateHoverTarget(to: hitTest(at: point))
            updateScrollIndicatorHover(to: scrollIndicatorHit(at: point))
            return
        }

        let hitNode = hitTest(at: point)

        if let pressedNode {
            let didRepeat = endButtonRepeat(for: pressedNode)
            if pressedNode === hitNode {
                pressedNode.onPointerUpInside?()
                if !didRepeat {
                    pressedNode.onActivate?()
                }
            } else {
                pressedNode.onPointerUpOutside?()
            }
        }

        self.pressedNode = nil
        updateHoverTarget(to: hitNode)
    }

    public func contextClick(at point: Point) {
        let hitNode = hitTest(at: point)
        updateHoverTarget(to: hitNode)
        guard let contextNode = nearestContextMenuNode(from: hitNode) else {
            return
        }

        contextNode.onContextMenu?(point)
    }

    public func keyDown(_ event: KeyboardEvent) {
        switch event.key {
        case .tab:
            moveFocus(reverse: event.modifiers.contains(.shift))
            return

        default:
            break
        }

        if activateKeyboardShortcut(for: event) {
            return
        }

        switch event.key {

        case .enter, .space:
            focusedNode?.onActivate?()

        case .escape:
            updateFocusTarget(to: nil)
            return

        default:
            break
        }

        if let key = event.key, handleScrollKey(key) {
            return
        }

        focusedNode?.onKeyDown?(event)
    }

    public func keyboardFocusDidLeaveWindow() {
        buttonRepeatState = nil
        updateFocusTarget(to: nil)
    }

    public func requestFocus(_ node: ViewNode?) {
        guard let node else {
            updateFocusTarget(to: nil)
            return
        }

        guard node.isFocusable else {
            return
        }

        updateFocusTarget(to: node)
    }

    private func beginButtonRepeatIfNeeded(for node: ViewNode?) {
        guard let node, node.buttonRepeatBehavior == .enabled else {
            buttonRepeatState = nil
            return
        }

        buttonRepeatState = ButtonRepeatState(
            node: node,
            startTime: nil,
            nextActivationTime: nil,
            didRepeat: false
        )
        invalidate(.paint)
    }

    private func endButtonRepeat(for node: ViewNode?) -> Bool {
        guard let state = buttonRepeatState else {
            return false
        }

        guard state.node === node else {
            if state.node == nil {
                buttonRepeatState = nil
            }
            return false
        }

        buttonRepeatState = nil
        return state.didRepeat
    }

    @discardableResult
    private func advanceButtonRepeat(at timestamp: Double) -> Bool {
        guard var state = buttonRepeatState else {
            return false
        }

        guard let node = state.node, pressedNode === node else {
            buttonRepeatState = nil
            return false
        }

        guard hoveredNode === node else {
            buttonRepeatState = state
            return false
        }

        if state.startTime == nil {
            state.startTime = timestamp
            state.nextActivationTime = timestamp + Self.buttonRepeatInitialDelay
            buttonRepeatState = state
            return false
        }

        guard let nextActivationTime = state.nextActivationTime, timestamp >= nextActivationTime else {
            buttonRepeatState = state
            return false
        }

        state.didRepeat = true
        state.nextActivationTime = timestamp + Self.buttonRepeatInterval
        buttonRepeatState = state
        if let onRepeatActivate = node.onRepeatActivate {
            onRepeatActivate()
        } else {
            node.onActivate?()
        }
        return true
    }

    public func animateBackgroundColor(of node: ViewNode, to targetColor: Color, duration: Double = 0.18, at timestamp: Double) {
        animateColor(.background, of: node, to: targetColor, duration: duration, at: timestamp)
    }

    public func animateColor(_ property: AnimatedColorProperty, of node: ViewNode, to targetColor: Color, duration: Double = 0.18, at timestamp: Double) {
        let animationKey = ColorAnimationKey(node: node, property: property)
        let startingColor = node.color(for: property)

        guard duration > 0, startingColor != targetColor else {
            colorAnimations.removeValue(forKey: animationKey)
            node.setColor(targetColor, for: property)
            return
        }

        colorAnimations[animationKey] = ViewColorAnimation(
            node: node,
            property: property,
            startColor: startingColor,
            endColor: targetColor,
            startTime: timestamp,
            duration: duration
        )
        invalidate()
    }

    @discardableResult
    public func tickAnimations(at timestamp: Double) -> Bool {
        let didAdvanceButtonRepeat = advanceButtonRepeat(at: timestamp)

        guard !colorAnimations.isEmpty else {
            return didAdvanceButtonRepeat
        }

        var didUpdateAnyAnimation = false

        for animationKey in Array(colorAnimations.keys) {
            guard let animation = colorAnimations[animationKey] else {
                continue
            }

            guard let node = animation.node else {
                colorAnimations.removeValue(forKey: animationKey)
                continue
            }

            let progress = animation.progress(at: timestamp)
            let nextColor = animation.startColor.interpolated(to: animation.endColor, progress: progress)
            if node.color(for: animation.property) != nextColor {
                node.setColor(nextColor, for: animation.property)
                didUpdateAnyAnimation = true
            }

            if progress >= 1 {
                colorAnimations.removeValue(forKey: animationKey)
            }
        }

        return didUpdateAnyAnimation || didAdvanceButtonRepeat
    }

    fileprivate func invalidate(_ flags: DirtyFlags = .all) {
        dirtyFlags.insert(flags)
    }

    fileprivate func recordLayoutReuse() {
        lastLayoutReuseCount += 1
    }

    fileprivate func recordMeasureReuse() {
        lastMeasureReuseCount += 1
    }

    private func appendDeferredDraws(
        into commands: inout [RenderCommand],
        previousFrame: RenderFrame?,
        displayScale: Double,
        replayCount: inout Int
    ) {
        for deferredDrawIndex in orderedDeferredDrawIndices(prepaintState.deferredDraws) {
            let startCommandIndex = commands.count
            if let previousFrame, let cachedFrameCommandRange = prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange {
                commands.append(contentsOf: previousFrame.commands[cachedFrameCommandRange])
                prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange = startCommandIndex..<commands.count
                replayCount += 1
                continue
            }

            switch prepaintState.deferredDraws[deferredDrawIndex].payload {
            case .scrollIndicator:
                let fillRect = prepaintState.deferredDraws[deferredDrawIndex].payload.fillRectCommand(
                    contentMask: prepaintState.deferredDraws[deferredDrawIndex].contentMask
                )
                commands.append(.fillRect(fillRect))
            case .subtree(let payload):
                guard let node = payload.node else {
                    prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange = startCommandIndex..<startCommandIndex
                    continue
                }
                node.appendCommands(
                    into: &commands,
                    parentOrigin: payload.parentOrigin,
                    inheritedClip: payload.inheritedClip,
                    inheritedOpacity: payload.inheritedOpacity,
                    previousRenderedFrame: previousFrame,
                    displayScale: displayScale,
                    replayCount: &replayCount
                )
            }

            prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange = startCommandIndex..<commands.count
        }
    }

    fileprivate func orderedDeferredDrawIndices(_ deferredDraws: [DeferredDrawState]) -> [Int] {
        deferredDraws.indices.sorted { lhs, rhs in
            let left = deferredDraws[lhs]
            let right = deferredDraws[rhs]
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return lhs < rhs
        }
    }

    fileprivate func orderedDeferredSubtreeIndices(
        _ deferredSubtrees: ArraySlice<DeferredSubtreeState>
    ) -> [Int] {
        deferredSubtrees.indices.sorted { lhs, rhs in
            let left = deferredSubtrees[lhs]
            let right = deferredSubtrees[rhs]
            if left.priority != right.priority {
                return left.priority < right.priority
            }
            return lhs < rhs
        }
    }

    private func deferredDrawRect(_ deferredDraw: DeferredDrawState) -> Rect {
        deferredDraw.rect
    }

    private func deferredDrawContentMask(_ deferredDraw: DeferredDrawState) -> Rect? {
        deferredDraw.contentMask
    }

    private func deferredDrawContains(_ point: Point, deferredDraw: DeferredDrawState) -> Bool {
        if let contentMask = deferredDrawContentMask(deferredDraw), !contentMask.contains(point) {
            return false
        }
        return deferredDrawRect(deferredDraw).contains(point)
    }

    private func deferredDrawsInteracting(at point: Point) -> [DeferredDrawState] {
        orderedDeferredDrawIndices(prepaintState.deferredDraws).reversed().compactMap { index in
            let deferredDraw = prepaintState.deferredDraws[index]
            guard deferredDrawContains(point, deferredDraw: deferredDraw) else {
                return nil
            }
            return deferredDraw
        }
    }

    private func dispatchIndex(for node: ViewNode?) -> Int? {
        guard let node else {
            return nil
        }

        return prepaintState.dispatchNodes.firstIndex(where: { $0.node === node })
    }

    private func node(for dispatchIndex: Int?) -> ViewNode? {
        guard let dispatchIndex, prepaintState.dispatchNodes.indices.contains(dispatchIndex) else {
            return nil
        }

        return prepaintState.dispatchNodes[dispatchIndex].node
    }

    private func nearestDispatchIndex(
        from dispatchIndex: Int?,
        where predicate: (ViewNode) -> Bool
    ) -> Int? {
        var currentDispatchIndex = dispatchIndex
        while let candidateDispatchIndex = currentDispatchIndex,
              prepaintState.dispatchNodes.indices.contains(candidateDispatchIndex) {
            let candidate = prepaintState.dispatchNodes[candidateDispatchIndex]
            if predicate(candidate.node) {
                return candidateDispatchIndex
            }

            currentDispatchIndex = candidate.parentIndex
        }

        return nil
    }

    private func hitDispatchIndex(at point: Point) -> Int? {
        updateResolvedLayout()
        for interaction in prepaintState.interactions.reversed() where interaction.node.isHitTestVisible {
            if interaction.containsForHitTesting(point) {
                return interaction.dispatchIndex
            }
        }

        return nil
    }

    private func hitTest(at point: Point) -> ViewNode? {
        node(for: hitDispatchIndex(at: point))
    }

    private func scrollTargetDispatchIndex(at point: Point, axis: ScrollAxis? = nil) -> Int? {
        updateResolvedLayout()
        for interaction in prepaintState.interactions.reversed() {
            guard interaction.node.isScrollable else {
                continue
            }

            if let axis, interaction.node.scrollAxis != axis {
                continue
            }

            if interaction.containsForScrollTarget(point) {
                return interaction.dispatchIndex
            }
        }

        return nil
    }

    private func scrollTarget(at point: Point, axis: ScrollAxis? = nil) -> ViewNode? {
        node(for: scrollTargetDispatchIndex(at: point, axis: axis))
    }

    private func scrollIndicatorHit(at point: Point) -> ScrollIndicatorHit? {
        updateResolvedLayout()
        for deferredDraw in deferredDrawsInteracting(at: point) {
            switch deferredDraw.interaction {
            case .scrollIndicator(let dispatchIndex, let track):
                guard let node = node(for: dispatchIndex) else {
                    continue
                }
                return ScrollIndicatorHit(node: node, track: track)
            case nil:
                continue
            }
        }

        return nil
    }

    private func moveFocus(reverse: Bool) {
        updateResolvedLayout()
        let focusableDispatchIndices = prepaintState.focusOrder
        guard !focusableDispatchIndices.isEmpty else {
            return
        }

        guard
            let focusedDispatchIndex = nearestDispatchIndex(
                from: dispatchIndex(for: focusedNode),
                where: { $0.isFocusable }
            ),
            let index = focusableDispatchIndices.firstIndex(of: focusedDispatchIndex)
        else {
            updateFocusTarget(to: node(for: reverse ? focusableDispatchIndices.last : focusableDispatchIndices.first))
            return
        }

        let nextIndex: Int
        if reverse {
            nextIndex = index == 0 ? focusableDispatchIndices.count - 1 : index - 1
        } else {
            nextIndex = index == focusableDispatchIndices.count - 1 ? 0 : index + 1
        }

        updateFocusTarget(to: node(for: focusableDispatchIndices[nextIndex]))
    }

    private func nearestFocusableNode(from node: ViewNode?) -> ViewNode? {
        self.node(for: nearestDispatchIndex(from: dispatchIndex(for: node), where: { $0.isFocusable }))
    }

    private func nearestScrollableNode(from node: ViewNode?, axis: ScrollAxis? = nil) -> ViewNode? {
        self.node(
            for: nearestDispatchIndex(
                from: dispatchIndex(for: node),
                where: { candidate in
                    candidate.isScrollable && (axis == nil || candidate.scrollAxis == axis)
                }
            )
        )
    }

    private func nearestDraggableNode(from node: ViewNode?) -> ViewNode? {
        self.node(for: nearestDispatchIndex(from: dispatchIndex(for: node), where: { $0.isDraggable }))
    }

    private func nearestContextMenuNode(from node: ViewNode?) -> ViewNode? {
        self.node(for: nearestDispatchIndex(from: dispatchIndex(for: node), where: { $0.onContextMenu != nil }))
    }

    private func activateKeyboardShortcut(for event: KeyboardEvent) -> Bool {
        updateResolvedLayout()
        for dispatchState in prepaintState.dispatchNodes {
            let node = dispatchState.node
            guard
                node.onActivate != nil,
                node.keyboardShortcuts.contains(where: { $0.matches(event) })
            else {
                continue
            }

            updateFocusTarget(to: nearestFocusableNode(from: node))
            node.onActivate?()
            return true
        }

        return false
    }

    private func handleScrollKey(_ key: KeyboardKey) -> Bool {
        updateResolvedLayout()
        let scrollableNode = nearestScrollableNode(from: focusedNode) ?? nearestScrollableNode(from: hoveredNode)
        guard let scrollableNode else {
            return false
        }

        return scrollableNode.applyKeyboardScroll(key)
    }

    private func updateResolvedLayout() {
        lastLayoutReuseCount = 0
        lastMeasureReuseCount = 0
        lastPrepaintReplayCount = 0
        lastDeferredOverlayReplayCount = 0
        lastDeferredDrawFrameReplayCount = 0
        lastDeferredDrawSceneReplayCount = 0
        root.resolvedFrame = root.frame
        root.layoutSubtree(displayScale: displayScale)
        updatePrepaintState()
    }

    private func updatePrepaintState() {
        let previousState = prepaintState
        var nextState = RuntimePrepaintState()
        var replayCount = 0
        root.appendPrepaintState(
            into: &nextState,
            parentOrigin: .zero,
            inheritedClip: nil,
            previousState: previousState,
            displayScale: displayScale,
            replayCount: &replayCount
        )
        processDeferredPrepaintDraws(
            into: &nextState,
            previousState: previousState,
            displayScale: displayScale,
            replayCount: &replayCount
        )
        prepaintState = nextState
        lastPrepaintReplayCount = replayCount
        lastDeferredOverlayReplayCount = replayCount
    }

    private func processDeferredPrepaintDraws(
        into state: inout RuntimePrepaintState,
        previousState: RuntimePrepaintState?,
        displayScale: Double,
        replayCount: inout Int
    ) {
        var cursor = 0
        while cursor < state.deferredSubtrees.count {
            let roundEnd = state.deferredSubtrees.count
            for deferredSubtreeIndex in orderedDeferredSubtreeIndices(state.deferredSubtrees[cursor..<roundEnd]) {
                let deferredSubtree = state.deferredSubtrees[deferredSubtreeIndex]
                let payload = deferredSubtree.payload
                guard let node = payload.node else {
                    continue
                }

                state.deferredDraws.append(
                    DeferredDrawState(
                        priority: deferredSubtree.priority,
                        parentDispatchIndex: deferredSubtree.parentDispatchIndex,
                        contentMask: payload.inheritedClip,
                        payload: .subtree(payload)
                    )
                )

                node.appendPrepaintState(
                    into: &state,
                    parentOrigin: payload.parentOrigin,
                    inheritedClip: payload.inheritedClip,
                    inheritedOpacity: payload.inheritedOpacity,
                    parentDispatchIndex: deferredSubtree.parentDispatchIndex,
                    inheritedInverseTransform: payload.inheritedInverseTransform,
                    previousState: previousState,
                    displayScale: displayScale,
                    replayCount: &replayCount
                )
            }
            cursor = roundEnd
        }
    }

    private func updateHoverTarget(to nextHoveredNode: ViewNode?) {
        guard hoveredNode !== nextHoveredNode else {
            return
        }

        let previousNode = hoveredNode
        previousNode?.isHovered = false
        previousNode?.onPointerExit?()
        hoveredNode = nextHoveredNode
        hoveredNode?.isHovered = true
        hoveredNode?.onPointerEnter?()
    }

    private func updateScrollIndicatorHover(to nextIndicatorHit: ScrollIndicatorHit?) {
        let nextNode = nextIndicatorHit?.node
        guard hoveredScrollIndicatorNode !== nextNode else {
            return
        }

        if let previousNode = hoveredScrollIndicatorNode, previousNode !== activeScrollIndicatorNode {
            animateColor(
                .scrollIndicator,
                of: previousNode,
                to: previousNode.scrollIndicatorIdleColor,
                duration: 0.12,
                at: Win32Window.currentTimestampSeconds()
            )
        }

        hoveredScrollIndicatorNode = nextNode

        if let nextNode, nextNode !== activeScrollIndicatorNode {
            animateColor(
                .scrollIndicator,
                of: nextNode,
                to: nextNode.scrollIndicatorHoverColor,
                duration: 0.12,
                at: Win32Window.currentTimestampSeconds()
            )
        }
    }

    private func updateFocusTarget(to nextFocusedNode: ViewNode?) {
        guard focusedNode !== nextFocusedNode else {
            return
        }

        let previousNode = focusedNode
        previousNode?.isFocused = false
        previousNode?.onFocusExit?()
        focusedNode = nextFocusedNode
        focusedNode?.isFocused = true
        focusedNode?.onFocusEnter?()
        invalidate()
    }
}

struct ScrollIndicatorTrack {
    let axis: ScrollAxis
    let origin: Double
    let travel: Double
    let indicatorRect: Rect
}

private struct ScrollIndicatorHit {
    unowned let node: ViewNode
    let track: ScrollIndicatorTrack
}

private struct ScrollDragState {
    weak var node: ViewNode?
    let axis: ScrollAxis
    let startPoint: Point
    let startOffset: Double
    let track: ScrollIndicatorTrack
}

private struct NodeDragState {
    weak var node: ViewNode?
    let startPoint: Point
}

public enum AnimatedColorProperty: Hashable, Sendable {
    case background
    case border
    case outline
    case shadow
    case scrollIndicator
}

private struct ColorAnimationKey: Hashable {
    let nodeIdentifier: ObjectIdentifier
    let property: AnimatedColorProperty

    init(node: ViewNode, property: AnimatedColorProperty) {
        self.nodeIdentifier = ObjectIdentifier(node)
        self.property = property
    }
}

private final class ViewColorAnimation {
    weak var node: ViewNode?
    let property: AnimatedColorProperty
    let startColor: Color
    let endColor: Color
    let startTime: Double
    let duration: Double

    init(node: ViewNode, property: AnimatedColorProperty, startColor: Color, endColor: Color, startTime: Double, duration: Double) {
        self.node = node
        self.property = property
        self.startColor = startColor
        self.endColor = endColor
        self.startTime = startTime
        self.duration = duration
    }

    func progress(at timestamp: Double) -> Double {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return 1
        }

        return min(max(elapsed / duration, 0), 1)
    }
}

private func baseClipAllowsDrawing(baseClip: Rect?, rect: Rect) -> Bool {
    baseClip?.intersected(with: rect) != nil || baseClip == nil
}

// MARK: - Animation interpolation support

/// Properties that can be animated via the `animation()` view modifier.
public enum AnimatableProperty: Hashable, Sendable {
    case opacity
    case backgroundColor
}

/// Tracks the interpolation state for a single animated property change.
public struct AnimationState {
    public var startValue: Double
    public var endValue: Double
    public var startTime: Double
    public var duration: Double
    public var easing: AnimationEasing

    public init(startValue: Double, endValue: Double, startTime: Double, duration: Double, easing: AnimationEasing = .easeInOut) {
        self.startValue = startValue
        self.endValue = endValue
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
    }

    /// Returns the interpolated value at the given timestamp.
    public func interpolatedValue(at timestamp: Double) -> Double {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return endValue
        }

        let linearProgress = min(max(elapsed / duration, 0), 1)
        let easedProgress = easing.apply(linearProgress)
        return startValue + (endValue - startValue) * easedProgress
    }

    /// Whether the animation has completed at the given timestamp.
    public func isComplete(at timestamp: Double) -> Bool {
        (timestamp - startTime) >= duration
    }
}

/// Easing functions for animation interpolation.
public enum AnimationEasing: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return t * (2 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        }
    }
}

/// Color-based animation state for interpolating between two colors over time.
public struct ColorAnimationState {
    public var startColor: Color
    public var endColor: Color
    public var startTime: Double
    public var duration: Double
    public var easing: AnimationEasing

    public init(startColor: Color, endColor: Color, startTime: Double, duration: Double, easing: AnimationEasing = .easeInOut) {
        self.startColor = startColor
        self.endColor = endColor
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
    }

    public func interpolatedColor(at timestamp: Double) -> Color {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return endColor
        }

        let linearProgress = min(max(elapsed / duration, 0), 1)
        let easedProgress = easing.apply(linearProgress)
        return startColor.interpolated(to: endColor, progress: easedProgress)
    }

    public func isComplete(at timestamp: Double) -> Bool {
        (timestamp - startTime) >= duration
    }
}

/// Snapshot of property values used by the animation system to track previous
/// state so it can interpolate between old and new values.
public struct PropertySnapshot {
    public var opacity: Double?
    public var backgroundColor: Color?

    public init(opacity: Double? = nil, backgroundColor: Color? = nil) {
        self.opacity = opacity
        self.backgroundColor = backgroundColor
    }
}
