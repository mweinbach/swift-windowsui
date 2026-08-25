import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

// Gap/Fix: Granular dirty tracking — OptionSet replaces single isDirty boolean.
import SwiftWindowsPlatform

// MARK: - Animation interpolation support

/// Properties that can be animated via the `animation()` view modifier.

/// Tracks the interpolation state for a single animated property change.

/// Color-based animation state for interpolating between two colors over time.

/// Snapshot of property values used by the animation system to track previous
/// state so it can interpolate between old and new values.
public struct DirtyFlags: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// Property changes that affect size or position (frame, preferredSize, layoutMode, etc.).
    public static let layout = DirtyFlags(rawValue: 1 << 0)
    /// Property changes that only affect visual appearance (color, opacity, borderColor, etc.).
    public static let paint = DirtyFlags(rawValue: 1 << 1)
    /// Child list changed (add/remove).
    public static let children = DirtyFlags(rawValue: 1 << 2)

    public static let all: DirtyFlags = [.layout, .paint, .children]
}
public enum RetainedColorRenderingMode: Sendable, Equatable, Hashable {
    case nonLinear
    case linear
    case extendedLinear
}
public struct RetainedDrawingGroup: Sendable, Equatable, Hashable {
    public var opaque: Bool
    public var colorMode: RetainedColorRenderingMode

    public init(opaque: Bool = false, colorMode: RetainedColorRenderingMode = .nonLinear) {
        self.opaque = opaque
        self.colorMode = colorMode
    }
}
public enum RetainedColorEffect: Sendable, Equatable {
    case brightness(Double)
    case contrast(Double)
    case colorInvert
    case colorMultiply(Color)
    case saturation(Double)
    case grayscale(Double)
    case hueRotation(Double)
    case luminanceToAlpha
}
public enum RetainedHorizontalAlignment: Sendable, Equatable, Hashable {
    case leading
    case center
    case trailing
}
public enum RetainedVerticalAlignment: Sendable, Equatable, Hashable {
    case top
    case center
    case bottom
}
public struct RetainedViewMask: Sendable, Equatable, Hashable {
    public var horizontal: RetainedHorizontalAlignment
    public var vertical: RetainedVerticalAlignment
    public var isInverse: Bool

    public init(
        horizontal: RetainedHorizontalAlignment = .center,
        vertical: RetainedVerticalAlignment = .center,
        isInverse: Bool = false
    ) {
        self.horizontal = horizontal
        self.vertical = vertical
        self.isInverse = isInverse
    }
}
public enum RetainedListSeparatorVisibility: Sendable, Equatable, Hashable {
    case automatic
    case visible
    case hidden
}
public enum RetainedListRowHoverStyle: Sendable, Equatable, Hashable {
    case automatic
    case disabled
}
public struct RetainedListSeparatorEdges: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let top = RetainedListSeparatorEdges(rawValue: 1 << 0)
    public static let bottom = RetainedListSeparatorEdges(rawValue: 1 << 1)
    public static let all: RetainedListSeparatorEdges = [.top, .bottom]
}
public struct RetainedListRowSeparator: Sendable, Equatable, Hashable {
    public var visibility: RetainedListSeparatorVisibility
    public var edges: RetainedListSeparatorEdges

    public init(
        visibility: RetainedListSeparatorVisibility = .automatic,
        edges: RetainedListSeparatorEdges = .all
    ) {
        self.visibility = visibility
        self.edges = edges
    }
}
public struct RetainedListSectionSeparator: Sendable, Equatable, Hashable {
    public var visibility: RetainedListSeparatorVisibility
    public var edges: RetainedListSeparatorEdges

    public init(
        visibility: RetainedListSeparatorVisibility = .automatic,
        edges: RetainedListSeparatorEdges = .all
    ) {
        self.visibility = visibility
        self.edges = edges
    }
}
public struct RetainedAlternatingRowBackgrounds: Sendable, Equatable, Hashable {
    public var visibility: RetainedListSeparatorVisibility

    public init(visibility: RetainedListSeparatorVisibility = .automatic) {
        self.visibility = visibility
    }
}
public struct RetainedNavigationSplitViewColumnWidth: Sendable, Equatable {
    public var min: Double?
    public var ideal: Double
    public var max: Double?

    public init(min: Double? = nil, ideal: Double, max: Double? = nil) {
        self.min = min
        self.ideal = ideal
        self.max = max
    }
}
public struct RetainedListSeparatorTint: Sendable, Equatable {
    public var color: Color?
    public var edges: RetainedListSeparatorEdges

    public init(
        color: Color? = nil,
        edges: RetainedListSeparatorEdges = .all
    ) {
        self.color = color
        self.edges = edges
    }
}
@MainActor
public struct RetainedSwipeAction: @unchecked Sendable {
    public var title: String
    public var isDestructive: Bool
    public var action: (@MainActor () -> Void)?

    public init(
        title: String,
        isDestructive: Bool = false,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.action = action
    }
}
public struct RetainedEditActions: Sendable, Equatable {
    public var containsDelete: Bool
    public var containsMove: Bool

    public init(_ actions: EditActions) {
        self.containsDelete = actions.contains(.delete)
        self.containsMove = actions.contains(.move)
    }
}
public enum RetainedListItemTintKind: Sendable, Equatable, Hashable {
    case fixed
    case preferred
    case monochrome
}
public struct RetainedListItemTint: Sendable, Equatable {
    public var color: Color?
    public var kind: RetainedListItemTintKind

    public init(
        color: Color? = nil,
        kind: RetainedListItemTintKind = .fixed
    ) {
        self.color = color
        self.kind = kind
    }
}
public struct RetainedFileExporterConfiguration {
    public var isPresented: Binding<Bool>
    public var document: Any?
    public var documents: [Any]?
    public var contentType: UTType
    public var defaultFilename: String?
    public var onCompletion: (Result<URL, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        document: Any? = nil,
        documents: [Any]? = nil,
        contentType: UTType,
        defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.document = document
        self.documents = documents
        self.contentType = contentType
        self.defaultFilename = defaultFilename
        self.onCompletion = onCompletion
    }
}
public struct RetainedFileImporterConfiguration {
    public var isPresented: Binding<Bool>
    public var allowedContentTypes: [UTType]
    public var onCompletion: (Result<URL, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.allowedContentTypes = allowedContentTypes
        self.onCompletion = onCompletion
    }
}
public struct RetainedFileImporterMultiConfiguration {
    public var isPresented: Binding<Bool>
    public var allowedContentTypes: [UTType]
    public var allowsMultipleSelection: Bool
    public var onCompletion: (Result<[URL], Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.allowedContentTypes = allowedContentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onCompletion = onCompletion
    }
}
public struct RetainedFileMoverConfiguration {
    public var isPresented: Binding<Bool>
    public var file: URL
    public var onCompletion: (Result<URL, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        file: URL,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.file = file
        self.onCompletion = onCompletion
    }
}
public struct RetainedGridCellUnsizedAxes: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let horizontal = RetainedGridCellUnsizedAxes(rawValue: 1 << 0)
    public static let vertical = RetainedGridCellUnsizedAxes(rawValue: 1 << 1)
    public static let all: RetainedGridCellUnsizedAxes = [.horizontal, .vertical]
}
public enum RetainedAlignmentGuideAxis: Sendable, Equatable, Hashable {
    case horizontal
    case vertical
}
public struct RetainedAlignmentGuide: Sendable, Equatable, Hashable {
    public var axis: RetainedAlignmentGuideAxis
    public var guide: String
    public var value: Double

    public init(axis: RetainedAlignmentGuideAxis, guide: String, value: Double) {
        self.axis = axis
        self.guide = guide
        self.value = value
    }
}
struct ViewPaintCacheKey: Equatable, Sendable {
    var bounds: Rect
    /// WS-19. The accumulated screen-space transform, as its matrix — the
    /// canonical form, so two decompositions of the same geometry compare
    /// equal. `bounds` is an axis-aligned bounding box and a whole class of
    /// transforms leaves it unchanged: a mirror, a 180° rotation, ±90° of a
    /// square. Keying on bounds alone replayed the previous frame's
    /// primitives for all of them.
    var transform: AffineMatrix
    /// The full clip shape, not just its rejection rect: a clip that keeps its
    /// rect but changes its rounding (a rounded card scrolling until an
    /// ancestor cuts a corner away) has to invalidate the replay cache too.
    var contentMask: RuntimeClipShape?
    var opacity: Float
    var blurRadius: Double
    var blurOpaque: Bool
    /// Separate from `blurRadius`: a change to the subtree-wide content
    /// blur has to invalidate the replay cache even when the node's own
    /// backdrop blur is unchanged (and vice versa).
    var contentBlurRadius: Double
    var contentBlurOpaque: Bool
    var blendMode: BlendMode
    var isCompositingGroup: Bool
    var drawingGroup: RetainedDrawingGroup?
    var colorEffects: [RetainedColorEffect]
    var visualEffects: [String]
    var viewMask: RetainedViewMask?
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
extension RenderCommand {
    fileprivate mutating func applyBlendMode(_ blendMode: BlendMode) {
        guard blendMode != .normal else {
            return
        }

        switch self {
        case .fillRect(var command):
            command.blendMode = blendMode
            self = .fillRect(command)
        case .drawBitmap(var command):
            command.blendMode = blendMode
            self = .drawBitmap(command)
        case .fillPath(var command):
            command.blendMode = blendMode
            self = .fillPath(command)
        case .strokePath(var command):
            command.blendMode = blendMode
            self = .strokePath(command)
        case .drawText(var command):
            command.blendMode = blendMode
            self = .drawText(command)
        case .pushClip, .popClip, .applyBlur:
            break
        }
    }
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
public enum RetainedPointerStyle: Sendable, Equatable {
    case automatic
    case arrow
    case pointingHand
    case iBeam
    case openHand
    case closedHand
    case resizeLeftRight
    case resizeUpDown
    case resizeAllDirections
    case crosshair
    case disappearingItem
    case operationNotAllowed
    case dragLink
    case dragCopy
    case contextMenu
}
public enum RetainedWindowDragInteraction: Sendable, Equatable {
    case automatic
    case disabled
    case enabled
}
public enum RetainedWindowResizeInteraction: Sendable, Equatable {
    case automatic
    case disabled
    case enabled
}
public enum RetainedWindowInteractionBehavior: Sendable, Equatable {
    case automatic
    case enabled
    case disabled
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
public struct RetainedMatchedTransitionSource: Sendable, Equatable {
    public var namespaceID: String
    public var elementID: String

    public init(namespaceID: String, elementID: String) {
        self.namespaceID = namespaceID
        self.elementID = elementID
    }
}
public enum RetainedNavigationTransitionKind: Sendable, Equatable {
    case zoom(namespaceID: String, elementID: String)
    case slide
    case fade
    case automatic
}
public struct RetainedNavigationTransition: Sendable, Equatable {
    public var kind: RetainedNavigationTransitionKind

    public init(kind: RetainedNavigationTransitionKind) {
        self.kind = kind
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
    public static let container = RetainedContentShapeKinds(rawValue: 1 << 6)
}
public struct RetainedAccessibilityTraits: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isButton = RetainedAccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = RetainedAccessibilityTraits(rawValue: 1 << 1)
    public static let isSelected = RetainedAccessibilityTraits(rawValue: 1 << 2)
    public static let isLink = RetainedAccessibilityTraits(rawValue: 1 << 3)
    public static let isImage = RetainedAccessibilityTraits(rawValue: 1 << 4)
    public static let isSearchField = RetainedAccessibilityTraits(rawValue: 1 << 5)
    public static let isKeyboardKey = RetainedAccessibilityTraits(rawValue: 1 << 6)
    public static let isStaticText = RetainedAccessibilityTraits(rawValue: 1 << 7)
    public static let isSummaryElement = RetainedAccessibilityTraits(rawValue: 1 << 8)
    public static let updatesFrequently = RetainedAccessibilityTraits(rawValue: 1 << 9)
    public static let startsMediaSession = RetainedAccessibilityTraits(rawValue: 1 << 10)
    public static let playsSound = RetainedAccessibilityTraits(rawValue: 1 << 11)
    public static let allowsDirectInteraction = RetainedAccessibilityTraits(rawValue: 1 << 12)
    public static let causesPageTurn = RetainedAccessibilityTraits(rawValue: 1 << 13)
    public static let isModal = RetainedAccessibilityTraits(rawValue: 1 << 14)
    // WinSwiftUI control defaults (Phase 2): toggle/checkbox, progress
    // indicator, and text input markers so the projection can resolve the
    // UIA checkBox, progressBar, and edit control types.
    public static let isToggle = RetainedAccessibilityTraits(rawValue: 1 << 15)
    public static let isProgressIndicator = RetainedAccessibilityTraits(rawValue: 1 << 16)
    public static let isTextInput = RetainedAccessibilityTraits(rawValue: 1 << 17)
}
public enum RetainedAccessibilityChildBehavior: Sendable, Equatable {
    case ignore
    case combine
    case contain
}
public enum RetainedAccessibilityActionKind: Sendable, Equatable {
    case `default`
    case escape
    case magicTap
    case increment
    case decrement
    case adjustable
    case zoomIn
    case zoomOut
}
public enum RetainedAccessibilityHeadingLevel: Sendable, Equatable, Hashable {
    case unspecified
    case h1
    case h2
    case h3
    case h4
    case h5
    case h6
}
public enum RetainedAccessibilityTextualContext: Sendable, Equatable, Hashable {
    case sourceCode
    case console
    case narrative
    case message
    case spreadsheet
    case wordProcessing
}
public enum RetainedAccessibilityDirectTouchOptions: Sendable, Equatable {
    case disabled
    case enabled
    case custom(identifier: String)
}
public enum RetainedTextSelectability: Sendable, Equatable {
    case enabled
    case disabled
}
public enum RetainedTextSelectionAffinity: Sendable, Equatable, Hashable {
    case automatic
    case upstream
    case downstream
}
public struct RetainedTextSelection: Sendable, Equatable, Hashable {
    public enum Indices: Sendable, Equatable, Hashable {
        case insertionPoint(Int)
        case range(Range<Int>)
        case ranges([Range<Int>])
    }

    public var indices: Indices
    public var affinity: RetainedTextSelectionAffinity

    public init(indices: Indices, affinity: RetainedTextSelectionAffinity = .automatic) {
        self.indices = indices
        self.affinity = affinity
    }
}
public struct RetainedTextContentType: Sendable, Equatable, Hashable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
public enum RetainedKeyboardType: Sendable, Equatable, Hashable {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    // swift-format-ignore: AlwaysUseLowerCamelCase
    case URL  // matches UIKeyboardType.URL
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
    case asciiCapableNumberPad
}
public struct RetainedTextInputSuggestion: Sendable, Equatable, Hashable {
    public var displayText: String
    public var completion: String?

    public init(displayText: String, completion: String? = nil) {
        self.displayText = displayText
        self.completion = completion
    }
}
public enum RetainedWritingToolsBehavior: Sendable, Equatable, Hashable {
    case automatic
    case complete
    case limited
    case disabled
}
public enum RetainedWritingToolsAffordanceVisibility: Sendable, Equatable, Hashable {
    case automatic
    case visible
    case hidden
}
public enum RetainedTextInputDictationActivation: Sendable, Equatable, Hashable {
    case onLook
    case onSelect
}
public enum RetainedTextInputDictationBehavior: Sendable, Equatable, Hashable {
    case automatic
    case preventDictation
    case inline(activation: RetainedTextInputDictationActivation)
}
public struct RetainedAccessibilityAction {
    public var name: String?
    public var kind: RetainedAccessibilityActionKind?
    public var handler: () -> Void

    public init(
        name: String? = nil,
        kind: RetainedAccessibilityActionKind? = nil,
        handler: @escaping () -> Void
    ) {
        self.name = name
        self.kind = kind
        self.handler = handler
    }
}
public struct RetainedAccessibilityRotor: Sendable, Equatable {
    public var label: String
    public var entries: [String]

    public init(label: String, entries: [String] = []) {
        self.label = label
        self.entries = entries
    }
}
public struct RetainedAccessibilityCustomContent: Sendable, Equatable {
    public var label: String
    public var value: String
    public var importance: Int  // 0 = default, 1 = high

    public init(label: String, value: String, importance: Int = 0) {
        self.label = label
        self.value = value
        self.importance = importance
    }
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
    public var mask: Bool

    public init(
        kinds: RetainedContentShapeKinds,
        style: RetainedContentShapeStyle,
        eoFill: Bool = false,
        mask: Bool = false
    ) {
        self.kinds = kinds
        self.style = style
        self.eoFill = eoFill
        self.mask = mask
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
public struct PhaseAnimatorState: Sendable {
    public var phasesSignature: String
    public var triggerDescription: String?
    public var currentPhaseIndex: Int
    public var previousTrigger: String?
    public var phaseStartTime: Double

    public init(
        phasesSignature: String,
        triggerDescription: String? = nil,
        currentPhaseIndex: Int = 0,
        previousTrigger: String? = nil,
        phaseStartTime: Double = 0
    ) {
        self.phasesSignature = phasesSignature
        self.triggerDescription = triggerDescription
        self.currentPhaseIndex = currentPhaseIndex
        self.previousTrigger = previousTrigger
        self.phaseStartTime = phaseStartTime
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
public enum RetainedPresentationDetent: Sendable, Equatable, Hashable {
    case medium
    case large
    case height(Double)
    case fraction(Double)
}
public enum RetainedPresentationContentInteraction: Sendable, Equatable {
    case automatic
    case resizes
    case scrolls
}
public enum RetainedPresentationAdaptation: Sendable, Equatable {
    case automatic
    case none
    case popover
    case sheet
    case fullScreenCover
}
public enum RetainedPresentationSizing: Sendable, Equatable {
    case automatic
    case fitted
    case page
    case form
    case fittedHorizontal
    case fittedVertical
}
public enum RetainedDialogSeverity: Sendable, Equatable {
    case standard
    case critical
}
public struct RetainedPresentationChrome: Sendable, Equatable {
    public var hasBackgroundOverride: Bool
    public var backgroundColor: Color?
    public var backgroundGradient: GradientType?
    public var hasCornerRadiusOverride: Bool
    public var cornerRadius: Double?
    public var hasDragCornerRadiusOverride: Bool
    public var dragCornerRadius: Double?
    public var hasDragIndicatorOverride: Bool
    public var showsDragIndicator: Bool
    public var hasDetentsOverride: Bool
    public var detents: [RetainedPresentationDetent]
    public var selectedDetent: RetainedPresentationDetent?
    public var hasInteractiveDismissDisabledOverride: Bool
    public var interactiveDismissDisabled: Bool
    public var hasBackgroundInteractionOverride: Bool
    public var allowsBackgroundInteraction: Bool
    public var hasContentInteractionOverride: Bool
    public var contentInteraction: RetainedPresentationContentInteraction
    public var hasCompactAdaptationOverride: Bool
    public var horizontalCompactAdaptation: RetainedPresentationAdaptation
    public var verticalCompactAdaptation: RetainedPresentationAdaptation
    public var hasSizingOverride: Bool
    public var sizing: RetainedPresentationSizing
    public var hasEdgeAttachedOverride: Bool
    public var isEdgeAttached: Bool
    public var hasIsModalOverride: Bool
    public var isModal: Bool
    public var hasDialogSeverityOverride: Bool
    public var dialogSeverity: RetainedDialogSeverity

    public init(
        hasBackgroundOverride: Bool = false,
        backgroundColor: Color? = nil,
        backgroundGradient: GradientType? = nil,
        hasCornerRadiusOverride: Bool = false,
        cornerRadius: Double? = nil,
        hasDragCornerRadiusOverride: Bool = false,
        dragCornerRadius: Double? = nil,
        hasDragIndicatorOverride: Bool = false,
        showsDragIndicator: Bool = false,
        hasDetentsOverride: Bool = false,
        detents: [RetainedPresentationDetent] = [],
        selectedDetent: RetainedPresentationDetent? = nil,
        hasInteractiveDismissDisabledOverride: Bool = false,
        interactiveDismissDisabled: Bool = false,
        hasBackgroundInteractionOverride: Bool = false,
        allowsBackgroundInteraction: Bool = false,
        hasContentInteractionOverride: Bool = false,
        contentInteraction: RetainedPresentationContentInteraction = .automatic,
        hasCompactAdaptationOverride: Bool = false,
        horizontalCompactAdaptation: RetainedPresentationAdaptation = .automatic,
        verticalCompactAdaptation: RetainedPresentationAdaptation = .automatic,
        hasSizingOverride: Bool = false,
        sizing: RetainedPresentationSizing = .automatic,
        hasEdgeAttachedOverride: Bool = false,
        isEdgeAttached: Bool = false,
        hasIsModalOverride: Bool = false,
        isModal: Bool = false,
        hasDialogSeverityOverride: Bool = false,
        dialogSeverity: RetainedDialogSeverity = .standard
    ) {
        self.hasBackgroundOverride = hasBackgroundOverride
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
        self.hasCornerRadiusOverride = hasCornerRadiusOverride
        self.cornerRadius = cornerRadius
        self.hasDragCornerRadiusOverride = hasDragCornerRadiusOverride
        self.dragCornerRadius = dragCornerRadius
        self.hasDragIndicatorOverride = hasDragIndicatorOverride
        self.showsDragIndicator = showsDragIndicator
        self.hasDetentsOverride = hasDetentsOverride
        self.detents = detents
        self.selectedDetent = selectedDetent
        self.hasInteractiveDismissDisabledOverride = hasInteractiveDismissDisabledOverride
        self.interactiveDismissDisabled = interactiveDismissDisabled
        self.hasBackgroundInteractionOverride = hasBackgroundInteractionOverride
        self.allowsBackgroundInteraction = allowsBackgroundInteraction
        self.hasContentInteractionOverride = hasContentInteractionOverride
        self.contentInteraction = contentInteraction
        self.hasCompactAdaptationOverride = hasCompactAdaptationOverride
        self.horizontalCompactAdaptation = horizontalCompactAdaptation
        self.verticalCompactAdaptation = verticalCompactAdaptation
        self.hasSizingOverride = hasSizingOverride
        self.sizing = sizing
        self.hasEdgeAttachedOverride = hasEdgeAttachedOverride
        self.isEdgeAttached = isEdgeAttached
        self.hasIsModalOverride = hasIsModalOverride
        self.isModal = isModal
        self.hasDialogSeverityOverride = hasDialogSeverityOverride
        self.dialogSeverity = dialogSeverity
    }

    public static let empty = RetainedPresentationChrome()
}
public struct RetainedContentTransition: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Equatable, Hashable {
        case identity
        case interpolate
        case numericTextCountsDown
        case numericTextValue
        case opacity
        case symbolEffect
    }

    public var kind: Kind
    public var numericTextCountsDown: Bool
    public var numericTextValue: Double?

    public init(
        kind: Kind,
        numericTextCountsDown: Bool = false,
        numericTextValue: Double? = nil
    ) {
        self.kind = kind
        self.numericTextCountsDown = numericTextCountsDown
        self.numericTextValue = numericTextValue
    }

    public static let identity = RetainedContentTransition(kind: .identity)
    public static let interpolate = RetainedContentTransition(kind: .interpolate)
    public static let opacity = RetainedContentTransition(kind: .opacity)
}
public struct RetainedSensoryFeedback: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Equatable, Hashable {
        case alignment
        case decrease
        case error
        case impact
        case impactFlexibility
        case impactWeight
        case increase
        case levelChange
        case pathComplete
        case press
        case release
        case selection
        case selectionFeedback
        case start
        case stop
        case success
        case warning
    }

    public enum FlexibilityKind: String, Sendable, Equatable, Hashable {
        case rigid
        case solid
        case soft
    }

    public enum WeightKind: String, Sendable, Equatable, Hashable {
        case light
        case medium
        case heavy
    }

    public enum PressKind: String, Sendable, Equatable, Hashable {
        case `default`
        case depth
        case start
    }

    public enum ReleaseKind: String, Sendable, Equatable, Hashable {
        case `default`
        case stop
    }

    public enum SelectionKind: String, Sendable, Equatable, Hashable {
        case `default`
        case maximum
        case minimum
        case off
        case on
    }

    public var kind: Kind
    public var flexibility: FlexibilityKind?
    public var weight: WeightKind?
    public var intensity: Double
    public var pressKind: PressKind?
    public var releaseKind: ReleaseKind?
    public var selectionKind: SelectionKind?

    public init(
        kind: Kind,
        flexibility: FlexibilityKind? = nil,
        weight: WeightKind? = nil,
        intensity: Double = 1.0,
        pressKind: PressKind? = nil,
        releaseKind: ReleaseKind? = nil,
        selectionKind: SelectionKind? = nil
    ) {
        self.kind = kind
        self.flexibility = flexibility
        self.weight = weight
        self.intensity = intensity
        self.pressKind = pressKind
        self.releaseKind = releaseKind
        self.selectionKind = selectionKind
    }
}
public struct RetainedTransition: Sendable, Equatable {
    public var kind: Kind

    public indirect enum Kind: Sendable, Equatable {
        case identity
        case opacity
        case scale(scaleX: Double, scaleY: Double, anchorX: Double, anchorY: Double)
        case offset(x: Double, y: Double)
        case move(edge: RetainedEdge)
        case slide
        case push(from: RetainedEdge)
        case asymmetric(insertion: RetainedTransition, removal: RetainedTransition)
        case combined(RetainedTransition, RetainedTransition)
        case modifier(activeType: ObjectIdentifier, identityType: ObjectIdentifier)
    }

    public init(kind: Kind) {
        self.kind = kind
    }

    public static let identity = RetainedTransition(kind: .identity)

    public var insertion: RetainedTransition {
        switch kind {
        case .asymmetric(let insertion, _):
            return insertion
        default:
            return self
        }
    }

    public var removal: RetainedTransition {
        switch kind {
        case .asymmetric(_, let removal):
            return removal
        default:
            return self
        }
    }
}
public enum RetainedEdge: Sendable, Equatable {
    case top
    case leading
    case bottom
    case trailing
}
public struct RetainedScrollAnchor: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
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
    /// The scroll view the indicator belongs to. The dispatch index below
    /// is what interaction resolves; the node is what the isolation pass a
    /// `.blur(radius:)` runs tests descent with — an indicator whose owner
    /// is inside the blurred subtree is claimed and drawn into the bitmap
    /// rather than painted sharp on top of it.
    weak var node: ViewNode? = nil
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
    /// The full inherited clip — rejection rect, rounding anchor and radii —
    /// so deferred content (overlays, deferred caches) resolves clip rounding
    /// exactly as inline content does. It used to be a rect plus two loose
    /// radius scalars, which is how the two paths drifted apart.
    var inheritedClip: RuntimeClipShape?
    var inheritedOpacity: Float
    var inheritedInverseTransform: Transform2D?
    var inheritedTransform: Transform2D = .identity
    var inheritedColorEffects: [RetainedColorEffect]
    // No inherited blur: `blurRadius` is the node's own backdrop effect and
    // `contentBlurRadius` is resolved as a single pass over the subtree's
    // painted bounds, so neither crosses a deferred-subtree boundary.
    var inheritedBlendMode: BlendMode = .normal
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
    var contentMask: RuntimeClipShape?
    var payload: DeferredDrawPayload
    var cachedFrameCommandRange: Range<Int>?
    var cachedScenePaintRange: Range<Int>?
    /// Set when a pass earlier in the frame already drew this entry, so the
    /// deferred phase must not draw it again.
    ///
    /// One thing sets it: the isolation pass a `.blur(radius:)` subtree runs.
    /// A pinned header is a deferred subtree of the scroll view it is pinned
    /// in, so a blurred `LazyVStack(pinnedViews:)` used to render its rows
    /// blurred and its headers perfectly sharp on top of them — the deferred
    /// phase drains after every node has finished painting, which is after
    /// the blur. The isolation pass pulls its own descendants in instead, so
    /// they are inside the bitmap that gets blurred.
    ///
    /// Reset at the top of every paint attempt: the array outlives the frame
    /// (it carries the replay ranges), the decision does not.
    var isDrawnInline: Bool = false

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
/// One node's interaction footprint, flattened by prepaint. Two spaces meet
/// here and each field says which one it is in:
///
/// - `clip` is `.painted` — the region the painter actually draws this node's
///   content into. A pointer is tested against it in screen space, with no
///   inverse mapping, which is what makes the interactive region *be* the
///   visible region under a transform.
/// - `frame` is untransformed layout space, so the pointer is inverse-mapped
///   into it by `inverseTransform` (the accumulated inverse of this node's own
///   transform and every ancestor's). That is the exact rotated footprint, not
///   its axis-aligned approximation.
@MainActor
struct PrepaintInteractionState {
    var dispatchIndex: Int
    var node: ViewNode
    var frame: Rect
    var clip: RuntimeClipShape?
    var inverseTransform: Transform2D?

    private func localPoint(_ point: Point) -> Point {
        guard let inverseTransform else { return point }
        return inverseTransform.applying(to: point)
    }

    func containsForHitTesting(_ point: Point) -> Bool {
        guard clip.contains(point) else {
            return false
        }

        return node.containsInteractionPoint(localPoint(point), in: frame)
    }

    func containsForScrollTarget(_ point: Point) -> Bool {
        guard clip.contains(point) else {
            return false
        }

        return frame.contains(localPoint(point))
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

    /// Where every one of this state's streams currently ends — the cursor a
    /// node's cached range is opened and closed against. Written as one value
    /// so the recursion that brackets a subtree spells the six counts once
    /// rather than at every level.
    var currentIndex: PrepaintStateIndex {
        PrepaintStateIndex(
            dispatchIndex: dispatchNodes.count,
            interactionIndex: interactions.count,
            focusOrderIndex: focusOrder.count,
            deferredSubtreeIndex: deferredSubtrees.count,
            deferredDrawIndex: deferredDraws.count,
            deferredPriority: nextDeferredPriority
        )
    }
}

/// What a stack has decided before it places its first child: the sizes its
/// children asked for, the sizes they were granted, and where the run starts.
@MainActor
struct StackAllocation {
    var contentRect: Rect
    var desiredSizes: [Size]
    var desiredMainSizes: [Double]
    var allocatedMainSizes: [Double]
    var spacingTotal: Double
    var effectiveSpacing: Double
    var mainCursorStart: Double
    var allowsOverflowAlongMainAxis: Bool
}

/// One child's place in a stack: its frame, how far the cursor advances past
/// it, and how much of the cross axis it claimed.
struct StackChildPlacement {
    var frame: Rect
    var mainAdvance: Double
    var crossExtent: Double
}

/// What a node decided about its own measurement before it measured a single
/// child: the constraints it resolved, the key it will cache under, the size
/// its own content wants, and the proposal its children get.
///
/// It exists so the measure recursion — the last recursive traversal in the
/// runtime — carries one small value per level instead of a mode's worth of
/// locals.
struct MeasurementPlan {
    var effectiveConstraints = LayoutConstraints()
    var cacheKey = ViewMeasureCacheKey(constraints: LayoutConstraints(), displayScale: 1)
    var contentSize = Size.zero
    var childConstraints = LayoutConstraints.unconstrained
    /// `.absolute` proposes to each child from that child's own origin, so its
    /// children cannot share one constraint.
    var measuresChildrenIndividually = false
}

/// How far along the track a stack has placed, and the widest child so far.
/// Carried as one value because the placement loop is the frame the layout
/// recursion descends from, and it is kept deliberately narrow.
struct StackPlacementCursor {
    var mainCursor: Double
    var visibleIndex: Int = 0
    var maxCrossExtent: Double = 0
}

/// `appendPrepaintState`'s share of `ScenePainter.paintNode`'s transform
/// algebra, computed once per node and out of line.
struct PrepaintGeometry {
    var centeredTransform: Transform2D
    var effectiveTransform: Transform2D
    var paintFrame: Rect
    var inverseTransform: Transform2D?
}
public enum ViewLayoutMode: Sendable {
    case absolute
    case stack(StackLayout)
    /// A stack that only lays its children's *subtrees* out when the scroll
    /// viewport can reach them.
    ///
    /// Placement is identical to `.stack` — every child is still measured
    /// (through the per-node measurement cache) and given a frame, because a
    /// stack cannot know where row 900 goes without knowing how tall rows
    /// 0…899 are. What virtualization removes is the recursive
    /// `layoutSubtree` walk into each child, which is where the depth is: a
    /// 5,000-row list is 5,000 shallow placements plus a deep layout of the
    /// handful of rows the viewport plus its overscan margin covers.
    ///
    /// A skipped child keeps its dirty flags and gets no new
    /// `cachedLayoutKey`, so the first pass that finds it in range lays it
    /// out in full. Nothing observes a half-laid-out subtree, because a
    /// child outside the viewport is also outside the clip the painter culls
    /// against.
    case lazyStack(StackLayout)
    case flex(FlexStyle)

    /// The stack layout children are placed with, for both stack variants.
    public var stackLayout: StackLayout? {
        switch self {
        case .stack(let layout), .lazyStack(let layout): return layout
        case .absolute, .flex: return nil
        }
    }

    /// True when out-of-viewport children may skip their recursive layout.
    public var virtualizesChildren: Bool {
        if case .lazyStack = self { return true }
        return false
    }
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
/// Axes on which a node takes the whole extent its parent proposes
/// instead of its intrinsic measurement.
///
/// This is the runtime's model of SwiftUI's *greedy* views — `Color`,
/// `ScrollView`, `List`, `Form`, `Spacer` along its stack's axis,
/// `Divider` across its cross axis, and anything given
/// `.frame(maxWidth: .infinity)`. A greedy axis is
/// meaningful only against a finite proposal: measured with an
/// unconstrained axis (an intrinsic query, or the main axis of the
/// enclosing stack) the node still reports its content size, so a
/// greedy child never inflates an intrinsic measurement to infinity.
/// Along a stack's main axis the fill is applied as growth out of the
/// stack's leftover extent (`growMainSizes`), which is what keeps
/// `VStack { Text; ScrollView }` from over-subscribing the track.
///
/// Greed also travels: a stack holding a greedy child along its *own*
/// axis is greedy along that axis, so `HStack { Text; Spacer }` is as
/// wide as its proposal rather than as wide as its text. That inherited
/// half lives in `ViewNode.inheritedStackFillAxes`, is derived once per
/// measurement, and stops at any ancestor that pins its own extent along
/// the same axis — `ViewNode.effectiveFillAxes` is the sum the layout
/// actually reads.
public struct LayoutFillAxes: Equatable, Sendable {
    public var horizontal: Bool
    public var vertical: Bool

    public init(horizontal: Bool = false, vertical: Bool = false) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let both = LayoutFillAxes(horizontal: true, vertical: true)
    public static let horizontalOnly = LayoutFillAxes(horizontal: true, vertical: false)
    public static let verticalOnly = LayoutFillAxes(horizontal: false, vertical: true)

    public var isEmpty: Bool { !horizontal && !vertical }
}
/// Per-corner rounding for a node's background/border, in points and
/// absolute screen corners (the retained runtime has no layout-direction
/// concept, so these are left/right rather than leading/trailing).
/// A `nil` `ViewNode.cornerRadii` keeps the historic uniform
/// `cornerRadius` behaviour. Rendered end-to-end by ScenePainter →
/// QuadPrimitive → both render backends; consumers that only understand
/// uniform rounding (shadow, outline, clip, dashed borders) fall back
/// to `maxRadius`.
public struct RetainedCornerRadii: Equatable, Sendable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double = 0, topRight: Double = 0, bottomRight: Double = 0, bottomLeft: Double = 0) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init(uniform radius: Double) {
        self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }

    /// Largest single corner radius. Used by uniform-radius consumers
    /// (shadow, outline, clip rect) when a node has per-corner radii.
    public var maxRadius: Double {
        max(topLeft, max(topRight, max(bottomRight, bottomLeft)))
    }

    public var hasPositiveRadius: Bool {
        maxRadius > 0
    }

    /// Shrinks every corner by `amount`, clamped at 0 — the per-corner
    /// equivalent of `max(0, cornerRadius - borderWidth)` used when
    /// deriving a fill shape inside a border ring.
    public func inset(by amount: Double) -> RetainedCornerRadii {
        RetainedCornerRadii(
            topLeft: max(0, topLeft - amount),
            topRight: max(0, topRight - amount),
            bottomRight: max(0, bottomRight - amount),
            bottomLeft: max(0, bottomLeft - amount)
        )
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

    public var backgroundGradient: GradientType? {
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

    public var borderGradient: GradientType? {
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

    /// Optional per-corner rounding for the node's border/background
    /// quads. When set with any radius > 0 it overrides the uniform
    /// `cornerRadius` for the border and fill quads; uniform-only
    /// consumers (shadow, outline, dashed borders) use
    /// `cornerRadii.maxRadius`. Clip rounding resolves per corner for each
    /// emitted quad (see
    /// `RuntimeClipShape.resolvedCornerRadius(forQuadRect:)`), falling
    /// back to `maxRadius` only for quads that span differently-rounded
    /// corners.
    public var cornerRadii: RetainedCornerRadii? {
        didSet { invalidateRuntime(.paint) }
    }

    public var backgroundPath: RenderPath? {
        didSet { invalidateRuntime(.paint) }
    }

    public var canvasDraw: ((inout CanvasGraphicsContext, Size) -> Void)? {
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

    /// Axes on which this node accepts its parent's proposal instead of
    /// its intrinsic size (SwiftUI's greedy views). See `LayoutFillAxes`.
    public var layoutFillAxes: LayoutFillAxes = LayoutFillAxes() {
        didSet { invalidateRuntime(.layout) }
    }

    public var ignoresSafeAreaInsets: EdgeInsets {
        didSet { invalidateRuntime(.layout) }
    }

    public var layoutPriority: Double {
        didSet { invalidateRuntime(.layout) }
    }

    public var spatialCompressionResistance: Double {
        didSet { invalidateRuntime(.layout) }
    }

    public var spatialExpansionResistance: Double {
        didSet { invalidateRuntime(.layout) }
    }

    public var alignmentGuides: [RetainedAlignmentGuide] {
        didSet { invalidateRuntime(.layout) }
    }

    public var gridCellAnchor: Point? {
        didSet { invalidateRuntime(.layout) }
    }

    public var gridCellUnsizedAxes: RetainedGridCellUnsizedAxes {
        didSet { invalidateRuntime(.layout) }
    }

    public var gridCellColumns: Int {
        didSet { invalidateRuntime(.layout) }
    }

    public var gridColumnAlignment: RetainedHorizontalAlignment? {
        didSet { invalidateRuntime(.layout) }
    }

    /// **Backdrop** blur radius, in points: the node's background quad
    /// blurs what is already painted underneath it and composites its tint
    /// over the result. This is what `.background(.regularMaterial)` sets,
    /// and it is a property of *this node's background*, not of its
    /// subtree — a card inside a frosted panel is not itself frosted.
    ///
    /// The distinction from `contentBlurRadius` used to not exist: one
    /// field carried both meanings, so `.blur(radius:)` on a container
    /// pushed a backdrop blur onto every descendant's background quad. That
    /// produced one backbuffer copy plus two blur passes *per descendant*
    /// (200 rows → 400 blur draws a frame) and still left the subtree's
    /// text, images and borders perfectly sharp, because only background
    /// quads carry the field.
    public var blurRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var blurOpaque: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    /// **Content** blur radius, in points: SwiftUI's `.blur(radius:)`. The
    /// subtree paints normally and one blur pass over its painted bounds
    /// blurs the result — text and images included — instead of the blur
    /// being smeared across every descendant background.
    ///
    /// Residual (documented in `docs/GPURenderingPipeline.md`): the pass is
    /// expressed with the existing backdrop primitive, so it blurs
    /// everything already painted inside the subtree's bounds rather than
    /// the subtree in isolation over an unblurred background. For the
    /// overwhelmingly common case — blurred content over a flat backdrop —
    /// the two are the same picture.
    public var contentBlurRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var contentBlurOpaque: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var geometryEffect: String? {
        didSet { invalidateRuntime(.paint) }
    }

    // Gap/Fix: Opacity — per-node opacity multiplier (0..1).
    public var opacity: Double {
        didSet { invalidateRuntime(.paint) }
    }

    // Renderer-neutral blend mode metadata. The RenderFrame fallback forwards
    // supported modes to per-command blend fields; the GPUI scene path keeps
    // normal compositing until typed primitives grow blend fields.
    public var blendMode: BlendMode {
        didSet { invalidateRuntime(.paint) }
    }

    public var isCompositingGroup: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var drawingGroup: RetainedDrawingGroup? {
        didSet { invalidateRuntime(.paint) }
    }

    public var colorEffects: [RetainedColorEffect] {
        didSet { invalidateRuntime(.paint) }
    }

    public var visualEffects: [String] {
        didSet { invalidateRuntime(.paint) }
    }

    public var viewMask: RetainedViewMask? {
        didSet { invalidateRuntime(.paint) }
    }

    public var listRowSeparator: RetainedListRowSeparator? {
        didSet { invalidateRuntime(.layout) }
    }

    public var listRowSeparatorTint: RetainedListSeparatorTint? {
        didSet { invalidateRuntime(.paint) }
    }

    public var listSectionSeparator: RetainedListSectionSeparator? {
        didSet { invalidateRuntime(.layout) }
    }

    public var listSectionSeparatorTint: RetainedListSeparatorTint? {
        didSet { invalidateRuntime(.paint) }
    }

    public var alternatingRowBackgrounds: RetainedAlternatingRowBackgrounds? {
        didSet { invalidateRuntime(.paint) }
    }

    public var listItemTint: RetainedListItemTint? {
        didSet { invalidateRuntime(.paint) }
    }

    public var listRowHoverStyle: RetainedListRowHoverStyle? {
        didSet { invalidateRuntime(.paint) }
    }

    public var listRowPlatterColor: Color? {
        didSet { invalidateRuntime(.paint) }
    }

    public var navigationSplitViewColumnWidth: RetainedNavigationSplitViewColumnWidth? {
        didSet { invalidateRuntime(.layout) }
    }

    public var preferredCompactColumn: NavigationSplitViewColumn? {
        didSet { invalidateRuntime(.layout) }
    }

    public var selectionDisabled: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var selectionDisabledOverride: Bool? {
        didSet { invalidateRuntime(.layout) }
    }

    public var deleteDisabled: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var deleteDisabledOverride: Bool? {
        didSet { invalidateRuntime(.layout) }
    }

    public var moveDisabled: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var moveDisabledOverride: Bool? {
        didSet { invalidateRuntime(.layout) }
    }

    public var onDeleteAction: ((IndexSet) -> Void)? {
        didSet { invalidateRuntime(.layout) }
    }

    public var onMoveAction: ((IndexSet, Int) -> Void)? {
        didSet { invalidateRuntime(.layout) }
    }

    public var editActions: RetainedEditActions? {
        didSet { invalidateRuntime(.layout) }
    }

    public var swipeActionsLeading: [RetainedSwipeAction]? {
        didSet { invalidateRuntime(.layout) }
    }

    public var swipeActionsTrailing: [RetainedSwipeAction]? {
        didSet { invalidateRuntime(.layout) }
    }

    public var swipeActionsAllowsFullSwipe: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var dynamicContentIndex: Int? {
        didSet { invalidateRuntime(.layout) }
    }

    public var dynamicInsertContentTypes: [String] {
        didSet { invalidateRuntime(.layout) }
    }

    public var dynamicDropPayloadType: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var dropAcceptedContentTypes: [String] {
        didSet { invalidateRuntime(.layout) }
    }

    public var dropPayloadType: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var isDropDestinationEnabled: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var hasDropConfiguration: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var dragDropPreviewsFormation: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var springLoadingBehavior: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var dragPayloadType: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var dragItemProviderTypeIdentifiers: [String] {
        didSet { invalidateRuntime(.layout) }
    }

    public var dragContainerItemID: AnyHashable? {
        didSet { invalidateRuntime(.layout) }
    }

    public var dragContainerNamespaceID: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var hasDragPreview: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var horizontalScrollBounceBehavior: String {
        didSet { invalidateRuntime(.layout) }
    }

    public var verticalScrollBounceBehavior: String {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollTargetBehavior: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var isScrollTargetLayout: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollInputBehaviors: [String: String] {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollIndicatorsFlashOnAppear: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    /// `.scrollIndicatorsFlash(trigger:)`. Every distinct value the app hands
    /// down flashes the scroller once — the property used to be stored and
    /// read by nobody, so the modifier compiled and did nothing.
    public var scrollIndicatorsFlashTrigger: String? {
        didSet {
            invalidateRuntime(.layout)
            if scrollIndicatorsFlashTrigger != oldValue, oldValue != nil {
                runtime?.flashScrollIndicator(for: self)
            }
        }
    }

    public var scrollTransition: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollPosition: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollObservations: [String] {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollReaderID: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var scrollProxyRequests: [String] {
        didSet { invalidateRuntime(.layout) }
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

    public var position: Point? {
        didSet { invalidateRuntime(.layout) }
    }

    public var transition: RetainedTransition {
        didSet { invalidateRuntime(.paint) }
    }

    public var contentTransition: RetainedContentTransition? {
        didSet { invalidateRuntime(.paint) }
    }

    public var sensoryFeedback: RetainedSensoryFeedback? {
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
        // Scrolling is a paint change — except over virtualized content,
        // where it is also the only signal that a row has come into range
        // and needs its subtree laid out. `hasVirtualizedDescendants` is set
        // by the first `.lazyStack` below this node that actually defers a
        // child, so an ordinary scroll view keeps its paint-only
        // invalidation and pays nothing for the concept.
        //
        // This is also the one funnel every scroll reaches — wheel, keyboard,
        // thumb drag, momentum, scroll-into-view, `scrollPosition` — so it is
        // where an overlay scroller learns it should be on screen.
        didSet {
            invalidateRuntime(hasVirtualizedDescendants ? [.paint, .layout] : .paint)
            if scrollIndicatorAutoHides, scrollOffset != oldValue {
                runtime?.revealScrollIndicator(for: self)
            }
        }
    }

    /// One *line* of scroll, because that is what a wheel delta counts: the
    /// Win32 host converts a notch into `SPI_GETWHEELSCROLLLINES` lines
    /// (default 3) before the runtime sees it.
    ///
    /// It used to default to 64 — a notch-sized value sitting in a line-sized
    /// slot, so one physical notch moved ~192px of step plus ~160px of glide,
    /// more than half a 600pt viewport. 16 is the body line box this stack
    /// pins (`MacOSControlMetrics.Typography`: 13pt at the 0.22 standard
    /// leading ratio), which puts a default three-line notch at 48pt, in the
    /// band `NSScrollView` lands in.
    public var scrollStep: Double {
        didSet { invalidateRuntime(.paint) }
    }

    /// The per-line scroll distance a scrollable node uses when nothing sets
    /// one. See `scrollStep`.
    public nonisolated static let defaultScrollLineHeight: Double = 16

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

    public var scrollIndicatorInsets: EdgeInsets {
        didSet { invalidateRuntime(.paint) }
    }

    /// Overlay-scroller behaviour: the thumb is *invisible* at rest and is
    /// revealed by scrolling, a flash, or a pointer on the track, then fades
    /// back out a beat after the scrolling stops. This is what a macOS
    /// scroller does, and it is why a screenshot of a real macOS app shows no
    /// scrollbar at all.
    ///
    /// The runtime only supplies the mechanism. `false` keeps the legacy
    /// always-visible bar, which is what `.scrollIndicators(.visible)` asks
    /// for and what every hand-built `ViewNode` fixture still gets.
    public var scrollIndicatorAutoHides: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    /// What the thumb settles to when nothing is happening: nothing at all for
    /// an overlay scroller, its own tone for a legacy one.
    ///
    /// `scrollIndicatorIdleColor` stays the *revealed* tone in both modes, so
    /// reveal and hide are the same tween run in opposite directions.
    public var restingScrollIndicatorColor: Color {
        scrollIndicatorAutoHides ? .clear : scrollIndicatorIdleColor
    }

    public var initialScrollAnchor: RetainedScrollAnchor? {
        didSet {
            hasAppliedInitialScrollAnchor = false
            invalidateRuntime(.layout)
        }
    }

    public var scrollSizeChangeAnchor: RetainedScrollAnchor? {
        didSet { invalidateRuntime(.layout) }
    }

    public var isFocusable: Bool {
        didSet {
            if !isFocusable, runtime?.focusedNode === self {
                runtime?.requestFocus(nil)
            }
            invalidateRuntime(.paint)
        }
    }

    public var isHitTestVisible: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var allowsAutomaticWindowDecorations: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isHidden: Bool {
        didSet {
            if isHidden {
                runtime?.releaseInteractionTargets(in: self)
            }
            invalidateRuntime(.layout)
        }
    }

    public var accessibilityLabel: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityDescription: String? {
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

    public var accessibilityLanguage: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var tooltip: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityTraits: RetainedAccessibilityTraits {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityChildBehavior: RetainedAccessibilityChildBehavior? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilitySortPriority: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityActions: [RetainedAccessibilityAction] {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityRotors: [RetainedAccessibilityRotor] {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityCustomContent: [RetainedAccessibilityCustomContent] {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityInputLabels: [String] {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityHeadingLevel: RetainedAccessibilityHeadingLevel? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityTextualContext: RetainedAccessibilityTextualContext? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityHidden: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityIgnoresInvertColors: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityRespondsToUserInteraction: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityPrefersSliderBehavior: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityRequiresActivationPoint: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityDirectTouchOptions: RetainedAccessibilityDirectTouchOptions? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityMagicTapAction: (() -> Void)?

    public var platformView: Any?
    public var platformViewCoordinator: Any?
    public var platformViewTypeName: String?
    public var onUpdatePlatformView: ((ViewNode) -> Void)?
    public var onDismantlePlatformView: ((ViewNode) -> Void)?

    public var accessibilityPrefersCrossFadeTransitions: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityShowLargeContentViewer: Bool? {
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

    public var textSelectability: RetainedTextSelectability? {
        didSet { invalidateRuntime(.paint) }
    }

    public var textSelectionAffinity: RetainedTextSelectionAffinity {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputSelection: RetainedTextSelection? {
        didSet { invalidateRuntime(.paint) }
    }

    public var textContentType: RetainedTextContentType? {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputKeyboardType: RetainedKeyboardType {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputCompletion: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputSuggestions: [RetainedTextInputSuggestion] {
        didSet { invalidateRuntime(.paint) }
    }

    public var writingToolsBehavior: RetainedWritingToolsBehavior? {
        didSet { invalidateRuntime(.paint) }
    }

    public var writingToolsAffordanceVisibility: RetainedWritingToolsAffordanceVisibility {
        didSet { invalidateRuntime(.paint) }
    }

    public var textInputDictationBehavior: RetainedTextInputDictationBehavior? {
        didSet { invalidateRuntime(.paint) }
    }

    /// In-progress IME composition (marked) text displayed at the caret and
    /// painted underlined by the editing chrome until the composition
    /// commits or cancels. Transient display state only; never part of the
    /// bound text. Secure fields mask it like their committed text.
    public var textInputMarkedText: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFindDisabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isReplaceDisabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFindNavigatorPresented: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isSubmitScopeBoundary: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var submitScopeTriggersRawValue: Int? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFocusSection: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var prefersDefaultFocus: Bool {
        didSet { invalidateRuntime(.layout) }
    }

    public var focusNamespace: NamespaceID? {
        didSet { invalidateRuntime(.layout) }
    }

    public var isGeometryGroup: Bool {
        didSet { invalidateRuntime(.layout) }
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

    public var isFocusDestination: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFocusActive: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isFocusEnabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var pointerStyle: RetainedPointerStyle? {
        didSet { invalidateRuntime(.paint) }
    }

    public var pointerVisibility: PointerVisibility? {
        didSet { invalidateRuntime(.paint) }
    }

    public var digitalCrownRotation: RetainedDigitalCrownRotation? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowDragInteraction: RetainedWindowDragInteraction? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowResizeInteraction: RetainedWindowResizeInteraction? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowDismissBehavior: RetainedWindowInteractionBehavior? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowFullScreenBehavior: RetainedWindowInteractionBehavior? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowMinimizeBehavior: RetainedWindowInteractionBehavior? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowResizeBehavior: RetainedWindowInteractionBehavior? {
        didSet { invalidateRuntime(.layout) }
    }

    public var windowCornerRadius: Double {
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

    public var isAccessibilityShowsLargeContentViewer: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityQuickActionEnabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityQuickActionStyle: AccessibilityQuickActionStyle? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityZoomActionEnabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityScrollActionEnabled: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityFocusSection: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isAccessibilityImage: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityLinkDestination: URL? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityLinkedGroup: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityPage: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var contextMenuForSelectionType: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var widgetURL: URL? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isWidgetAccentable: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var widgetAccentedRenderingMode: WidgetAccentedRenderingMode? {
        didSet { invalidateRuntime(.paint) }
    }

    public var widgetBackgroundStyle: AnyShapeStyle? {
        didSet { invalidateRuntime(.paint) }
    }

    public var widgetBackgroundPlacement: ContainerBackgroundPlacement? {
        didSet { invalidateRuntime(.paint) }
    }

    public var widgetRelevancy: WidgetRelevancy? {
        didSet { invalidateRuntime(.paint) }
    }

    public var paletteSelectionEffect: PaletteSelectionEffect? {
        didSet { invalidateRuntime(.paint) }
    }

    public var paintsInDeferredPhase: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var matchedGeometryEffect: RetainedMatchedGeometryEffect? {
        didSet { invalidateRuntime(.paint) }
    }

    public var matchedTransitionSource: RetainedMatchedTransitionSource? {
        didSet { invalidateRuntime(.paint) }
    }

    public var navigationTransition: RetainedNavigationTransition? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartXAxis: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartXScale: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartYScale: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var meshGradient: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartYAxis: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartLegend: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartBackground: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartPlotStyle: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartOverlay: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartSelection: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartScrollableAxes: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartForegroundStyleScale: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartSymbolSize: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartSymbol: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartAngleScale: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartBackgroundStyleScale: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartSymbolScale: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartXVisibleDomain: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartYVisibleDomain: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartXSelection: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartYSelection: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartAngleSelection: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartScrollPositionX: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var chartScrollPositionY: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var tableColumnHeadersVisible: Bool? {
        didSet { invalidateRuntime(.layout) }
    }

    public var isContentInvalidatable: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var isLineSelectable: Bool? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityActivationPoint: UnitPoint? {
        didSet { invalidateRuntime(.layout) }
    }

    public var accessibilityTextContentType: AccessibilityTextContentType? {
        didSet { invalidateRuntime(.paint) }
    }

    public var scenePaddingEdges: Edge.Set? {
        didSet { invalidateRuntime(.paint) }
    }

    public var coordinateSpaceName: String? {
        didSet { invalidateRuntime(.layout) }
    }

    public var gestureName: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var textRenderer: Any?

    public var presentationChrome: RetainedPresentationChrome {
        didSet { invalidateRuntime(.layout) }
    }

    public var isToolbarContainer: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var toolbarPlacementTags: Set<String> {
        didSet { invalidateRuntime(.paint) }
    }

    public var menuOrder: String? {
        didSet { invalidateRuntime(.paint) }
    }

    public var toolbarTitleMenuChildren: [ViewNode]? {
        didSet { invalidateRuntime(.paint) }
    }

    public var toolbarTitleActionsChildren: [ViewNode]? {
        didSet { invalidateRuntime(.paint) }
    }

    public var accessibilityRepresentationChildren: [ViewNode]? {
        didSet { invalidateRuntime(.paint) }
    }

    public var sectionHeaderChildCount: Int {
        didSet { invalidateRuntime(.paint) }
    }

    public var sectionFooterChildCount: Int {
        didSet { invalidateRuntime(.paint) }
    }

    /// When this node is a grouped-form row, the index of the child that is
    /// its label column; `nil` on every other node.
    ///
    /// A macOS grouped form is a two-column grid, and the leading column's
    /// width is shared by every row in the group — it is the widest label,
    /// not each row's own. The container resolves that width after building
    /// its rows, and this is how it finds the columns to pin without
    /// guessing at child positions.
    public var formRowLabelChildIndex: Int? {
        didSet { invalidateRuntime(.layout) }
    }

    /// Marks this node as a hairline rule rather than content.
    ///
    /// The retained model has no per-side border, so every separator in the
    /// stack — a `Divider`, a list row rule, a stepper's seam, a grouped
    /// form's row rule — is a sibling node one physical pixel thick.
    /// Containers that rule *between* their own children need to know which
    /// of those children is already a rule, or an app that wrote its own
    /// `Divider` into a section gets three lines where it asked for one.
    public var isSeparatorRule: Bool = false

    /// Type-erased preference values emitted by SwiftUI-shaped compatibility modifiers.
    /// The retained runtime keeps them as metadata so ancestor modifiers can
    /// inspect rebuilt subtrees without coupling the renderer to WinSwiftUI.
    public var retainedPreferenceValues: [ObjectIdentifier: Any] = [:]
    public var retainedPreferenceTransformBoundaries: Set<ObjectIdentifier> = []

    /// Type-erased layout values emitted by SwiftUI-shaped compatibility modifiers.
    /// Custom layout engines can consume these later without changing retained nodes.
    public var retainedLayoutValues: [ObjectIdentifier: Any] = [:] {
        didSet { invalidateRuntime(.layout) }
    }

    /// Type-erased container values emitted by SwiftUI-shaped compatibility modifiers.
    /// These values are local to future direct-subview container APIs.
    public var retainedContainerValues: [ObjectIdentifier: Any] = [:] {
        didSet { invalidateRuntime(.layout) }
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
    /// The `didSet` keeps the runtime's animating-node registry in step: the
    /// host gates its animation timer on `hasActiveAnimations`, so a node that
    /// starts animating without the runtime knowing about it never gets ticked
    /// and freezes mid-transition.
    public var animationStates: [AnimatableProperty: AnimationState] = [:] {
        didSet {
            guard oldValue.isEmpty != animationStates.isEmpty else { return }
            if animationStates.isEmpty {
                runtime?.unregisterAnimatingNode(self)
            } else {
                runtime?.registerAnimatingNode(self)
            }
        }
    }

    /// Persistent phase-animation state for PhaseAnimator. Survives rebuilds
    /// because it is stored on the retained ViewNode rather than in @State.
    public var phaseAnimatorState: PhaseAnimatorState?

    /// The colour ramp this node answers pointer, focus and press state with.
    ///
    /// It is *data*, resolved by the runtime, precisely because the build
    /// cannot know where the pointer is. A control that installed its state
    /// colours from build-scope closures had two unfixable problems: every
    /// rebuild overwrote `backgroundColor` (and border, outline, shadow) with
    /// the freshly built *idle* value while the pointer was still on the
    /// control, and the copied closures went on addressing the discarded
    /// build's node, so hover never worked again for the rest of the session.
    /// Both are gone when the runtime — which is the only thing that knows
    /// `hoveredNode` / `focusedNode` / `pressedNode` — owns the resolution and
    /// re-applies it after every reconciliation.
    public var interactionSurface: RetainedInteractionSurface?

    /// An animation this node applies to its own frame and fill changes at
    /// reconciliation time, with or without an ambient `withAnimation`.
    ///
    /// For the handful of controls that animate on macOS *regardless* of what
    /// the app asked for — `NSSwitch` is the one this exists for; its knob
    /// springs across and its track cross-fades whether or not the state
    /// change was wrapped in an animation. A rebuilt control's state change
    /// carries no `currentAnimationTransaction`, so without this the knob
    /// reached its end position in a single frame and the 20px of travel was
    /// never drawn.
    public var implicitReconcileAnimation: AnimationTransaction?

    /// Marks this node as a text input's insertion indicator, so the runtime
    /// can blink it. Set by the text-input chrome builder; nothing else in the
    /// tree carries it.
    public var isTextInputCaret = false

    public var onPointerEnter: (() -> Void)?
    public var onPointerExit: (() -> Void)?
    public var onPointerMove: ((Point) -> Void)?
    public var onPointerDown: (() -> Void)?
    public var onPointerUpInside: (() -> Void)?
    public var onPointerUpInsideAt: ((Point) -> Void)?
    public var onPointerUpOutside: (() -> Void)?
    public var onContextMenu: ((Point) -> Void)?
    public var onFocusEnter: (() -> Void)?
    public var onFocusExit: (() -> Void)?
    public var onKeyDown: ((KeyboardEvent) -> Void)?
    /// IME composition events routed by the runtime to the focused node;
    /// installed by text inputs, `nil` elsewhere.
    public var onIMEComposition: ((IMECompositionEvent) -> Void)?
    /// Reports the caret rectangle in root (logical) coordinates so the
    /// window host can position the OS IME candidate/composition window.
    /// Installed by text inputs; `nil` elsewhere.
    public var textInputCaretRectProvider: (() -> Rect?)?
    /// When true, unmodified up/down arrow keys are delivered to this node's
    /// `onKeyDown` before the runtime's scroll-key handling, so a focused node
    /// (e.g. a selectable list row) can claim vertical arrows for navigation.
    public var interceptsVerticalArrowKeys = false
    public var onKeyUp: ((KeyboardEvent) -> Void)?
    public var onActivate: (() -> Void)?
    public var onRepeatActivate: (() -> Void)?
    public var onDeleteRows: ((IndexSet) -> Void)?
    public var onMoveRows: ((IndexSet, Int) -> Void)?
    public var onInsertRows: ((Int, [Any]) -> Void)?
    public var onDropRows: (([Any], Int) -> Void)?
    public var onValidateDrop: (([Any], Point) -> Bool)?
    public var onDropEntered: (([Any], Point) -> Void)?
    public var onDropUpdated: (([Any], Point) -> Any?)?
    public var onDropExited: (() -> Void)?
    public var onDropProviders: (([Any], Point) -> Bool)?
    public var onDropPayloads: (([Any], Point) -> Bool)?
    public var onMakeDropConfiguration: (([Any], Point) -> Any?)?
    public var onMakeDragPayload: (() -> Any?)?
    public var commandHandlers: [String: () -> Void] = [:]
    public var fileExporterConfiguration: RetainedFileExporterConfiguration?
    public var fileImporterConfiguration: RetainedFileImporterConfiguration?
    public var fileImporterMultiConfiguration: RetainedFileImporterMultiConfiguration?
    public var fileMoverConfiguration: RetainedFileMoverConfiguration?
    public var inspectorColumnWidth: Double?
    public var inspectorColumnWidthFraction: Double?
    public var inspectorColumnWidthMin: Double?
    public var inspectorPresentationStyle: InspectorPresentationStyle?
    public var fileDialogCustomizationID: String?
    public var fileDialogConfirmationLabel: String?
    public var fileDialogDefaultDirectory: URL?
    public var fileDialogMessage: String?
    public var onMakeDragItemProvider: (() -> Any?)?
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

    /// A `GeometryReader`'s body, kept so the runtime can re-invoke it once
    /// layout has resolved the slot the reader actually occupies. Build order
    /// cannot know that slot — the reader's siblings have not been measured
    /// yet — so the reader seeds its body with the canvas and this closure
    /// converges it (see `RetainedViewRuntime.resolveGeometryReaderSlots`).
    ///
    /// Renderer-neutral by construction: it hands back nodes, and it takes
    /// the runtime it should build them against rather than capturing one —
    /// a captured runtime would close a retain cycle back through the root.
    /// The returned node is a fresh build of the *same* reader, so the
    /// runtime adopts it onto this node instead of nesting it underneath.
    public var geometryReaderBuild: ((RetainedViewRuntime, Size) -> [ViewNode])?

    /// The slot size `children` were last built against. `nil` on a node that
    /// is not a reader. Compared against `resolvedFrame.size` to decide
    /// whether a convergence rebuild is owed, so it is also the loop's own
    /// termination condition.
    public var geometryReaderBuiltSize: Size?

    internal private(set) var hasAppeared = false

    /// Marks a node that arrived in its host's *first* build.
    ///
    /// SwiftUI does not play a transition for a view that is present in the
    /// first render of its container: the initial tree is a state, not an
    /// insertion. The runtime used to play one for every transition-bearing
    /// node in the window at launch, because `applyNewNodeTransitionsRecursively`
    /// fires on `!hasAppeared` and on the first build nothing has appeared yet.
    /// `hasAppeared` cannot carry this on its own — it is set at *render*, and a
    /// state change between `setContent` and the first frame would otherwise
    /// find the whole tree still un-appeared and animate it in.
    ///
    /// Cleared the moment the node actually appears, so a later removal and
    /// re-insertion transitions normally.
    internal var isInitialBuildNode = false

    /// Whether this node has already played the transition it arrived with.
    ///
    /// `applyNewNodeTransitionsRecursively` fires on `!hasAppeared`, and
    /// `hasAppeared` is set by the paint traversal — which does not reach
    /// every node it retains, so the two are not the same question. A node
    /// the traversal never marked would play its insertion transition again
    /// on every subsequent rebuild: a `TabView` page faded in correctly on the
    /// switch, and then faded in *again* every time a button on it was
    /// pressed, because pressing the button rebuilds the tree and the page
    /// still looked un-appeared. Caught in a motion capture, where a button
    /// press blanked the whole window for a quarter of a second.
    ///
    /// An insertion transition is a statement about arriving, and a node
    /// arrives once. Cleared with `hasAppeared` when the node really leaves,
    /// so a removal and a genuine re-insertion transition normally.
    internal var didPlayInsertionTransition = false
    public internal(set) var isRemovalOverlay: Bool = false
    private var previousFrame: Rect?
    private var lifecycleTasks: [String: Task<Void, Never>] = [:]

    public private(set) weak var parent: ViewNode?
    public private(set) var children: [ViewNode]

    fileprivate weak var runtime: RetainedViewRuntime?

    /// "Now" on the animation clock of the runtime this node belongs to.
    ///
    /// `runtime` is fileprivate, so every seeding site outside this file —
    /// `ComponentHost`'s reconcile in particular — goes through here rather
    /// than reaching for the wall clock. A detached node (built but not yet
    /// reconciled into a tree) has no runtime and falls back to the wall clock,
    /// which is the same value in production and unreachable by a tween in a
    /// test, since a detached node has no tweens.
    internal var animationClockNow: Double {
        runtime?.clock() ?? Win32Window.currentTimestampSeconds()
    }

    internal var resolvedFrame: Rect
    internal var resolvedContentSize: Size
    internal var resolvedScrollOffset: Double
    // Signed pixel offset applied on top of the clamped scrollOffset during
    // rubber-band animations. Zero outside of edge-overshoot states. Painter
    // and child positioning consume this via `effectiveScrollOffset`; the
    // logical `scrollOffset` itself stays clamped so tests and external
    // callers see the unsurprising value.
    internal var scrollOvershoot: Double = 0
    // Signed pixel offset that visually lags the logical scrollOffset during
    // animated keyboard scrolls. Starts at (oldOffset - newOffset) when the
    // user triggers an instantaneous offset change, then tweens to 0 over a
    // short duration so the viewport glides instead of snapping. Painter
    // adds this to resolvedScrollOffset before applying child positioning.
    internal var scrollPresentedDelta: Double = 0
    internal private(set) var subtreeDirtyFlags: DirtyFlags = .all
    internal var cachedMeasureKey: ViewMeasureCacheKey?
    internal var cachedMeasuredSize: Size?
    /// Main-axis greed this stack picked up from its own children, folded in
    /// at the end of every measurement (see `updateInheritedStackFillAxes`).
    /// Never set by a caller — `layoutFillAxes` is the declared half of the
    /// same idea, and `effectiveFillAxes` is what the layout consults.
    internal private(set) var inheritedStackFillAxes = LayoutFillAxes()
    internal var cachedLayoutKey: ViewLayoutCacheKey?
    /// The key this node's *in-flight* layout pass will cache once its subtree
    /// has settled. Layout is a worklist, so the key is minted when the node is
    /// entered and committed when it finishes — a stack frame used to hold it.
    internal var pendingLayoutKey: ViewLayoutCacheKey?

    /// Set on a scrollable node when a `.lazyStack` beneath it defers a
    /// child's layout. It is what turns a scroll — normally a paint-only
    /// change — into a layout invalidation for virtualized content only.
    ///
    /// Recomputed per pass, not latched: cleared when the scrollable node is
    /// visited by `layoutSubtree` and re-set only by deferrals observed
    /// after that, so a lazy stack reconciled into an eager one stops
    /// charging every subsequent scroll frame a layout invalidation.
    internal var hasVirtualizedDescendants = false

    /// The scrollable ancestor `layoutVirtualizationWindow()` last resolved
    /// against, so deferring a child can mark it without a second walk.
    internal weak var virtualizationScrollAncestor: ViewNode?

    /// The layout pass in which a `.lazyStack` beneath this node resolved
    /// its virtualization window *through* this node, stamped by
    /// `layoutVirtualizationWindow()`'s existing upward walk.
    internal var virtualizationDescentPassID: UInt64 = 0

    /// The layout pass in which `layoutSubtree` last descended into this
    /// node, stamped as that visit finishes.
    internal var lastLayoutVisitPassID: UInt64 = 0

    /// True when a `.lazyStack` below this node resolved its window through
    /// it no earlier than this node's own last visit — that is, when the
    /// last pass that reached here also reached a lazy stack.
    ///
    /// This is what keeps a lazy stack reachable through *clean* ancestors.
    /// A scroll dirties only the scrollable node and its ancestors, so an
    /// intermediate node between the scroll view and the lazy stack takes
    /// `layoutSubtree`'s early return and, without this, would never descend
    /// — leaving rows that scrolled into view laid out at whatever geometry
    /// they last had. Comparing the two stamps rather than trusting a latch
    /// also makes the path self-limiting: once a pass reaches here and finds
    /// no lazy stack below, the next pass stops descending.
    fileprivate var isOnVirtualizationDescentPath: Bool {
        virtualizationDescentPassID != 0 && virtualizationDescentPassID >= lastLayoutVisitPassID
    }

    /// True while a `.lazyStack` ancestor has skipped this node's recursive
    /// layout because the scroll viewport could not reach it.
    ///
    /// Needed because dirty flags are not a reliable record of "still needs
    /// laying out": the painter culls an out-of-viewport subtree and calls
    /// `markSubtreeRendered()` on it, which clears the aggregate flag. A row
    /// skipped at layout and then culled at paint would therefore look clean
    /// the moment it scrolled back into view, and would paint at whatever
    /// geometry it last had — the exact failure a virtualization scheme must
    /// not have.
    internal var isLayoutDeferredByVirtualization = false
    internal var cachedPrepaintKey: ViewPaintCacheKey?
    internal var cachedPrepaintRange: PrepaintStateRange?
    internal var cachedFrameKey: ViewPaintCacheKey?
    internal var cachedFrameCommandRange: Range<Int>?
    internal var cachedSceneKey: ViewPaintCacheKey?
    internal var cachedScenePaintRange: Range<Int>?
    /// Offscreen bitmap this node's compositing group (`.drawingGroup()`,
    /// `.compositingGroup()`) rasterized into, and the paint key it was
    /// rasterized for. A group CPU-rasterizes its whole subtree on the main
    /// actor, so repeating that for an unchanged subtree is the most expensive
    /// thing the painter can do per frame; the pair is reused while the key
    /// matches and the subtree is clean, exactly like the paint-record replay
    /// range above.
    internal var cachedCompositingGroupKey: ViewPaintCacheKey?
    internal var cachedCompositingGroupBitmap: BitmapSurface?
    /// Native glyph-atlas generation the cached bitmap was rasterized against,
    /// when its sub-scene drew native glyphs. An atlas recycle invalidates every
    /// UV captured before it, so a bitmap baked across one must be re-rasterized
    /// on the repaint that recycle triggers rather than reused with someone
    /// else's glyphs in it.
    internal var cachedCompositingGroupAtlasGeneration: UInt64?
    /// True when the last paint that *visited* this node resolved its
    /// `.blur(radius:)` as an isolated offscreen pass — so the pixels the
    /// scene carries for this subtree are a bitmap that already contains its
    /// deferred descendants.
    ///
    /// "Last visited", not "this frame", is the whole point. A clean
    /// **ancestor** of a blurred node replays its own cached paint range,
    /// which carries the composited bitmap forward without the traversal ever
    /// reaching the blur — so `claimDeferredDescendants` does not run, and
    /// without this flag the deferred phase drew a second, sharp copy of every
    /// pinned header on top of the bitmap that already had them. The node-local
    /// replay refusal cannot see that: it is not the blurred node replaying.
    /// `ScenePainter.appendDeferredDraws` consults the flag on the drain side
    /// instead, up the entry's parent chain.
    ///
    /// Cleared on entry to every visit and set only when the pass composites,
    /// so the degraded inline fallback — an isolation buffer that could not be
    /// sized — still draws its headers in the deferred phase.
    internal var lastPaintedViaContentBlurIsolation = false
    private var hasAppliedInitialScrollAnchor: Bool
    private var lastAnchoredScrollContentSize: Size
    private var lastAnchoredScrollFrameSize: Size

    public init(
        frame: Rect = .zero,
        backgroundColor: Color? = nil,
        backgroundGradient: GradientType? = nil,
        bitmapSurface: BitmapSurface? = nil,
        text: String? = nil,
        textStyle: PixelTextStyle = PixelTextStyle(color: .white),
        borderColor: Color = .clear,
        borderGradient: GradientType? = nil,
        borderWidth: Double = 0,
        borderStrokeStyle: StrokeStyle? = nil,
        outlineColor: Color = .clear,
        outlineWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        cornerRadii: RetainedCornerRadii? = nil,
        backgroundPath: RenderPath? = nil,
        canvasDraw: ((inout CanvasGraphicsContext, Size) -> Void)? = nil,
        clipsToBounds: Bool = false,
        clipFillStyle: RetainedClipFillStyle? = nil,
        layoutMode: ViewLayoutMode = .absolute,
        preferredSize: Size? = nil,
        layoutConstraints: LayoutConstraints? = nil,
        fixedSizeAxes: FixedSizeAxes? = nil,
        ignoresSafeAreaInsets: EdgeInsets = .zero,
        layoutPriority: Double = 0,
        spatialCompressionResistance: Double = 0,
        spatialExpansionResistance: Double = 0,
        alignmentGuides: [RetainedAlignmentGuide] = [],
        gridCellAnchor: Point? = nil,
        gridCellUnsizedAxes: RetainedGridCellUnsizedAxes = [],
        gridCellColumns: Int = 1,
        gridColumnAlignment: RetainedHorizontalAlignment? = nil,
        flexItem: FlexProperties = .default,
        flexItemStyle: FlexItemStyle = FlexItemStyle(),
        blurRadius: Double = 0,
        blurOpaque: Bool = false,
        contentBlurRadius: Double = 0,
        contentBlurOpaque: Bool = false,
        geometryEffect: String? = nil,
        opacity: Double = 1.0,
        blendMode: BlendMode = .normal,
        isCompositingGroup: Bool = false,
        drawingGroup: RetainedDrawingGroup? = nil,
        colorEffects: [RetainedColorEffect] = [],
        visualEffects: [String] = [],
        viewMask: RetainedViewMask? = nil,
        listRowSeparator: RetainedListRowSeparator? = nil,
        listRowSeparatorTint: RetainedListSeparatorTint? = nil,
        listSectionSeparator: RetainedListSectionSeparator? = nil,
        listSectionSeparatorTint: RetainedListSeparatorTint? = nil,
        alternatingRowBackgrounds: RetainedAlternatingRowBackgrounds? = nil,
        listItemTint: RetainedListItemTint? = nil,
        listRowHoverStyle: RetainedListRowHoverStyle? = nil,
        listRowPlatterColor: Color? = nil,
        navigationSplitViewColumnWidth: RetainedNavigationSplitViewColumnWidth? = nil,
        preferredCompactColumn: NavigationSplitViewColumn? = nil,
        selectionDisabled: Bool = false,
        selectionDisabledOverride: Bool? = nil,
        deleteDisabled: Bool = false,
        deleteDisabledOverride: Bool? = nil,
        moveDisabled: Bool = false,
        moveDisabledOverride: Bool? = nil,
        onDeleteAction: ((IndexSet) -> Void)? = nil,
        onMoveAction: ((IndexSet, Int) -> Void)? = nil,
        editActions: RetainedEditActions? = nil,
        swipeActionsLeading: [RetainedSwipeAction]? = nil,
        swipeActionsTrailing: [RetainedSwipeAction]? = nil,
        swipeActionsAllowsFullSwipe: Bool = true,
        dynamicContentIndex: Int? = nil,
        dynamicInsertContentTypes: [String] = [],
        dynamicDropPayloadType: String? = nil,
        dropAcceptedContentTypes: [String] = [],
        dropPayloadType: String? = nil,
        isDropDestinationEnabled: Bool = false,
        hasDropConfiguration: Bool = false,
        dragDropPreviewsFormation: String? = nil,
        springLoadingBehavior: String? = nil,
        dragPayloadType: String? = nil,
        dragItemProviderTypeIdentifiers: [String] = [],
        dragContainerItemID: AnyHashable? = nil,
        dragContainerNamespaceID: String? = nil,
        hasDragPreview: Bool = false,
        horizontalScrollBounceBehavior: String = "automatic",
        verticalScrollBounceBehavior: String = "automatic",
        scrollTargetBehavior: String? = nil,
        isScrollTargetLayout: Bool = false,
        scrollInputBehaviors: [String: String] = [:],
        scrollIndicatorsFlashOnAppear: Bool = false,
        scrollIndicatorsFlashTrigger: String? = nil,
        scrollTransition: String? = nil,
        scrollPosition: String? = nil,
        scrollObservations: [String] = [],
        scrollReaderID: String? = nil,
        scrollProxyRequests: [String] = [],
        zIndex: Double = 0,
        transform: Transform2D = .identity,
        transition: RetainedTransition = .identity,
        contentTransition: RetainedContentTransition? = nil,
        sensoryFeedback: RetainedSensoryFeedback? = nil,
        scrollAxis: ScrollAxis? = nil,
        scrollOffset: Double = 0,
        scrollStep: Double = ViewNode.defaultScrollLineHeight,
        showsScrollIndicator: Bool = false,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorIdleColor: Color? = nil,
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        scrollIndicatorInsets: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
        scrollIndicatorAutoHides: Bool = false,
        initialScrollAnchor: RetainedScrollAnchor? = nil,
        scrollSizeChangeAnchor: RetainedScrollAnchor? = nil,
        isFocusable: Bool = false,
        isHitTestVisible: Bool = true,
        allowsAutomaticWindowDecorations: Bool = true,
        isHidden: Bool = false,
        accessibilityLabel: String? = nil,
        accessibilityDescription: String? = nil,
        accessibilityValue: String? = nil,
        accessibilityHint: String? = nil,
        accessibilityIdentifier: String? = nil,
        accessibilityLanguage: String? = nil,
        accessibilityTraits: RetainedAccessibilityTraits = [],
        accessibilityChildBehavior: RetainedAccessibilityChildBehavior? = nil,
        accessibilitySortPriority: Double = 0,
        accessibilityActions: [RetainedAccessibilityAction] = [],
        accessibilityRotors: [RetainedAccessibilityRotor] = [],
        accessibilityCustomContent: [RetainedAccessibilityCustomContent] = [],
        accessibilityInputLabels: [String] = [],
        accessibilityHeadingLevel: RetainedAccessibilityHeadingLevel? = nil,
        accessibilityTextualContext: RetainedAccessibilityTextualContext? = nil,
        isAccessibilityHidden: Bool = false,
        accessibilityIgnoresInvertColors: Bool = false,
        accessibilityRespondsToUserInteraction: Bool? = nil,
        accessibilityPrefersSliderBehavior: Bool? = nil,
        accessibilityRequiresActivationPoint: Bool? = nil,
        accessibilityDirectTouchOptions: RetainedAccessibilityDirectTouchOptions? = nil,
        accessibilityMagicTapAction: (() -> Void)? = nil,
        accessibilityPrefersCrossFadeTransitions: Bool? = nil,
        accessibilityShowLargeContentViewer: Bool? = nil,
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
        textSelectability: RetainedTextSelectability? = nil,
        textSelectionAffinity: RetainedTextSelectionAffinity = .automatic,
        textInputSelection: RetainedTextSelection? = nil,
        textContentType: RetainedTextContentType? = nil,
        textInputKeyboardType: RetainedKeyboardType = .default,
        textInputCompletion: String? = nil,
        textInputSuggestions: [RetainedTextInputSuggestion] = [],
        writingToolsBehavior: RetainedWritingToolsBehavior? = nil,
        writingToolsAffordanceVisibility: RetainedWritingToolsAffordanceVisibility = .automatic,
        textInputDictationBehavior: RetainedTextInputDictationBehavior? = nil,
        isFindDisabled: Bool = false,
        isReplaceDisabled: Bool = false,
        isFindNavigatorPresented: Bool = false,
        isSubmitScopeBoundary: Bool = false,
        submitScopeTriggersRawValue: Int? = nil,
        isGeometryGroup: Bool = false,
        hoverEffect: RetainedHoverEffect? = nil,
        isHoverEffectDisabled: Bool = false,
        isFocusEffectDisabled: Bool = false,
        isFocusDestination: Bool = false,
        isFocusActive: Bool = false,
        isFocusEnabled: Bool = true,
        pointerStyle: RetainedPointerStyle? = nil,
        pointerVisibility: PointerVisibility? = nil,
        digitalCrownRotation: RetainedDigitalCrownRotation? = nil,
        windowDragInteraction: RetainedWindowDragInteraction? = nil,
        windowResizeInteraction: RetainedWindowResizeInteraction? = nil,
        windowDismissBehavior: RetainedWindowInteractionBehavior? = nil,
        windowFullScreenBehavior: RetainedWindowInteractionBehavior? = nil,
        windowMinimizeBehavior: RetainedWindowInteractionBehavior? = nil,
        windowResizeBehavior: RetainedWindowInteractionBehavior? = nil,
        windowCornerRadius: Double = 0,
        contentShapes: [RetainedContentShape] = [],
        buttonRepeatBehavior: RetainedButtonRepeatBehavior = .automatic,
        redactionReasons: RetainedRedactionReasons = [],
        isPrivacySensitive: Bool = false,
        isAccessibilityShowsLargeContentViewer: Bool = false,
        isAccessibilityQuickActionEnabled: Bool = false,
        accessibilityQuickActionStyle: AccessibilityQuickActionStyle? = nil,
        isAccessibilityZoomActionEnabled: Bool = false,
        isAccessibilityScrollActionEnabled: Bool = false,
        isAccessibilityFocusSection: Bool = false,
        isAccessibilityImage: Bool = false,
        accessibilityLinkDestination: URL? = nil,
        accessibilityLinkedGroup: String? = nil,
        accessibilityPage: String? = nil,
        contextMenuForSelectionType: String? = nil,
        widgetURL: URL? = nil,
        isWidgetAccentable: Bool = false,
        widgetAccentedRenderingMode: WidgetAccentedRenderingMode? = nil,
        widgetBackgroundStyle: AnyShapeStyle? = nil,
        widgetBackgroundPlacement: ContainerBackgroundPlacement? = nil,
        widgetRelevancy: WidgetRelevancy? = nil,
        paletteSelectionEffect: PaletteSelectionEffect? = nil,
        paintsInDeferredPhase: Bool = false,
        matchedGeometryEffect: RetainedMatchedGeometryEffect? = nil,
        matchedTransitionSource: RetainedMatchedTransitionSource? = nil,
        navigationTransition: RetainedNavigationTransition? = nil,
        chartXAxis: String? = nil,
        chartXScale: String? = nil,
        chartYScale: String? = nil,
        meshGradient: String? = nil,
        chartYAxis: String? = nil,
        chartLegend: String? = nil,
        chartBackground: String? = nil,
        chartPlotStyle: String? = nil,
        chartOverlay: String? = nil,
        chartSelection: String? = nil,
        chartScrollableAxes: String? = nil,
        chartForegroundStyleScale: String? = nil,
        chartSymbolSize: String? = nil,
        chartSymbol: String? = nil,
        chartAngleScale: String? = nil,
        chartBackgroundStyleScale: String? = nil,
        chartSymbolScale: String? = nil,
        chartXVisibleDomain: String? = nil,
        chartYVisibleDomain: String? = nil,
        chartXSelection: String? = nil,
        chartYSelection: String? = nil,
        chartAngleSelection: String? = nil,
        chartScrollPositionX: String? = nil,
        chartScrollPositionY: String? = nil,
        tableColumnHeadersVisible: Bool? = nil,
        isContentInvalidatable: Bool? = nil,
        isLineSelectable: Bool? = nil,
        accessibilityActivationPoint: UnitPoint? = nil,
        accessibilityTextContentType: AccessibilityTextContentType? = nil,
        presentationChrome: RetainedPresentationChrome = .empty,
        isToolbarContainer: Bool = false,
        toolbarPlacementTags: Set<String> = [],
        menuOrder: String? = nil,
        toolbarTitleMenuChildren: [ViewNode]? = nil,
        toolbarTitleActionsChildren: [ViewNode]? = nil,
        accessibilityRepresentationChildren: [ViewNode]? = nil,
        gestureName: String? = nil,
        textRenderer: Any? = nil,
        coordinateSpaceName: String? = nil,
        sectionHeaderChildCount: Int = 0,
        sectionFooterChildCount: Int = 0,
        phaseAnimatorState: PhaseAnimatorState? = nil,
        children: [ViewNode] = []
    ) {
        self.frame = frame
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
        self.bitmapSurface = bitmapSurface
        self.text = text
        self.textStyle = textStyle
        self.borderColor = borderColor
        self.borderGradient = borderGradient
        self.borderWidth = borderWidth
        self.borderStrokeStyle = borderStrokeStyle
        self.outlineColor = outlineColor
        self.outlineWidth = outlineWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
        self.cornerRadius = cornerRadius
        self.cornerRadii = cornerRadii
        self.backgroundPath = backgroundPath
        self.canvasDraw = canvasDraw
        self.clipsToBounds = clipsToBounds
        self.clipFillStyle = clipFillStyle
        self.layoutMode = layoutMode
        self.preferredSize = preferredSize
        self.layoutConstraints = layoutConstraints
        self.fixedSizeAxes = fixedSizeAxes
        self.ignoresSafeAreaInsets = ignoresSafeAreaInsets
        self.layoutPriority = layoutPriority
        self.spatialCompressionResistance = spatialCompressionResistance
        self.spatialExpansionResistance = spatialExpansionResistance
        self.alignmentGuides = alignmentGuides
        self.gridCellAnchor = gridCellAnchor
        self.gridCellUnsizedAxes = gridCellUnsizedAxes
        self.gridCellColumns = gridCellColumns
        self.gridColumnAlignment = gridColumnAlignment
        self.flexItem = flexItem
        self.flexItemStyle = flexItemStyle
        self.blurRadius = blurRadius
        self.blurOpaque = blurOpaque
        self.contentBlurRadius = contentBlurRadius
        self.contentBlurOpaque = contentBlurOpaque
        self.geometryEffect = geometryEffect
        self.opacity = opacity
        self.blendMode = blendMode
        self.isCompositingGroup = isCompositingGroup
        self.drawingGroup = drawingGroup
        self.colorEffects = colorEffects
        self.visualEffects = visualEffects
        self.viewMask = viewMask
        self.listRowSeparator = listRowSeparator
        self.listRowSeparatorTint = listRowSeparatorTint
        self.listSectionSeparator = listSectionSeparator
        self.listSectionSeparatorTint = listSectionSeparatorTint
        self.alternatingRowBackgrounds = alternatingRowBackgrounds
        self.listItemTint = listItemTint
        self.listRowHoverStyle = listRowHoverStyle
        self.listRowPlatterColor = listRowPlatterColor
        self.navigationSplitViewColumnWidth = navigationSplitViewColumnWidth
        self.preferredCompactColumn = preferredCompactColumn
        self.selectionDisabled = selectionDisabled
        self.selectionDisabledOverride = selectionDisabledOverride
        self.deleteDisabled = deleteDisabled
        self.deleteDisabledOverride = deleteDisabledOverride
        self.moveDisabled = moveDisabled
        self.moveDisabledOverride = moveDisabledOverride
        self.onDeleteAction = onDeleteAction
        self.onMoveAction = onMoveAction
        self.editActions = editActions
        self.swipeActionsLeading = swipeActionsLeading
        self.swipeActionsTrailing = swipeActionsTrailing
        self.swipeActionsAllowsFullSwipe = swipeActionsAllowsFullSwipe
        self.dynamicContentIndex = dynamicContentIndex
        self.dynamicInsertContentTypes = dynamicInsertContentTypes
        self.dynamicDropPayloadType = dynamicDropPayloadType
        self.dropAcceptedContentTypes = dropAcceptedContentTypes
        self.dropPayloadType = dropPayloadType
        self.isDropDestinationEnabled = isDropDestinationEnabled
        self.hasDropConfiguration = hasDropConfiguration
        self.dragDropPreviewsFormation = dragDropPreviewsFormation
        self.springLoadingBehavior = springLoadingBehavior
        self.dragPayloadType = dragPayloadType
        self.dragItemProviderTypeIdentifiers = dragItemProviderTypeIdentifiers
        self.dragContainerItemID = dragContainerItemID
        self.dragContainerNamespaceID = dragContainerNamespaceID
        self.hasDragPreview = hasDragPreview
        self.horizontalScrollBounceBehavior = horizontalScrollBounceBehavior
        self.verticalScrollBounceBehavior = verticalScrollBounceBehavior
        self.scrollTargetBehavior = scrollTargetBehavior
        self.isScrollTargetLayout = isScrollTargetLayout
        self.scrollInputBehaviors = scrollInputBehaviors
        self.scrollIndicatorsFlashOnAppear = scrollIndicatorsFlashOnAppear
        self.scrollIndicatorsFlashTrigger = scrollIndicatorsFlashTrigger
        self.scrollTransition = scrollTransition
        self.scrollPosition = scrollPosition
        self.scrollObservations = scrollObservations
        self.scrollReaderID = scrollReaderID
        self.scrollProxyRequests = scrollProxyRequests
        self.zIndex = zIndex
        self.transform = transform
        self.transition = transition
        self.contentTransition = contentTransition
        self.sensoryFeedback = sensoryFeedback
        self.scrollAxis = scrollAxis
        self.scrollOffset = scrollOffset
        self.scrollStep = scrollStep
        self.showsScrollIndicator = showsScrollIndicator
        self.scrollIndicatorAutoHides = scrollIndicatorAutoHides
        // An overlay scroller starts where it spends most of its life:
        // invisible. `scrollIndicatorIdleColor` stays the *revealed* tone, so
        // the same node can fade in to it and back out to nothing.
        self.scrollIndicatorColor = scrollIndicatorAutoHides ? .clear : scrollIndicatorColor
        self.scrollIndicatorIdleColor = scrollIndicatorIdleColor ?? scrollIndicatorColor
        self.scrollIndicatorHoverColor = scrollIndicatorHoverColor
        self.scrollIndicatorActiveColor = scrollIndicatorActiveColor
        self.scrollIndicatorThickness = scrollIndicatorThickness
        self.scrollIndicatorInsets = scrollIndicatorInsets
        self.initialScrollAnchor = initialScrollAnchor
        self.scrollSizeChangeAnchor = scrollSizeChangeAnchor
        self.isFocusable = isFocusable
        self.isHitTestVisible = isHitTestVisible
        self.allowsAutomaticWindowDecorations = allowsAutomaticWindowDecorations
        self.isHidden = isHidden
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityDescription = accessibilityDescription
        self.accessibilityValue = accessibilityValue
        self.accessibilityHint = accessibilityHint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLanguage = accessibilityLanguage
        self.tooltip = nil
        self.accessibilityTraits = accessibilityTraits
        self.accessibilityChildBehavior = accessibilityChildBehavior
        self.accessibilitySortPriority = accessibilitySortPriority
        self.accessibilityActions = accessibilityActions
        self.accessibilityRotors = accessibilityRotors
        self.accessibilityCustomContent = accessibilityCustomContent
        self.accessibilityInputLabels = accessibilityInputLabels
        self.accessibilityHeadingLevel = accessibilityHeadingLevel
        self.accessibilityTextualContext = accessibilityTextualContext
        self.isAccessibilityHidden = isAccessibilityHidden
        self.accessibilityIgnoresInvertColors = accessibilityIgnoresInvertColors
        self.accessibilityRespondsToUserInteraction = accessibilityRespondsToUserInteraction
        self.accessibilityPrefersSliderBehavior = accessibilityPrefersSliderBehavior
        self.accessibilityRequiresActivationPoint = accessibilityRequiresActivationPoint
        self.accessibilityDirectTouchOptions = accessibilityDirectTouchOptions
        self.accessibilityMagicTapAction = accessibilityMagicTapAction
        self.accessibilityPrefersCrossFadeTransitions = accessibilityPrefersCrossFadeTransitions
        self.accessibilityShowLargeContentViewer = accessibilityShowLargeContentViewer
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
        self.textSelectability = textSelectability
        self.textSelectionAffinity = textSelectionAffinity
        self.textInputSelection = textInputSelection
        self.textContentType = textContentType
        self.textInputKeyboardType = textInputKeyboardType
        self.textInputCompletion = textInputCompletion
        self.textInputSuggestions = textInputSuggestions
        self.writingToolsBehavior = writingToolsBehavior
        self.writingToolsAffordanceVisibility = writingToolsAffordanceVisibility
        self.textInputDictationBehavior = textInputDictationBehavior
        self.textInputMarkedText = nil
        self.isFindDisabled = isFindDisabled
        self.isReplaceDisabled = isReplaceDisabled
        self.isFindNavigatorPresented = isFindNavigatorPresented
        self.isSubmitScopeBoundary = isSubmitScopeBoundary
        self.submitScopeTriggersRawValue = submitScopeTriggersRawValue
        self.isFocusSection = false
        self.prefersDefaultFocus = false
        self.focusNamespace = nil
        self.isGeometryGroup = isGeometryGroup
        self.hoverEffect = hoverEffect
        self.isHoverEffectDisabled = isHoverEffectDisabled
        self.isFocusEffectDisabled = isFocusEffectDisabled
        self.isFocusDestination = isFocusDestination
        self.isFocusActive = isFocusActive
        self.isFocusEnabled = isFocusEnabled
        self.pointerStyle = pointerStyle
        self.pointerVisibility = pointerVisibility
        self.digitalCrownRotation = digitalCrownRotation
        self.windowDragInteraction = windowDragInteraction
        self.windowResizeInteraction = windowResizeInteraction
        self.windowDismissBehavior = windowDismissBehavior
        self.windowFullScreenBehavior = windowFullScreenBehavior
        self.windowMinimizeBehavior = windowMinimizeBehavior
        self.windowResizeBehavior = windowResizeBehavior
        self.windowCornerRadius = windowCornerRadius
        self.contentShapes = contentShapes
        self.buttonRepeatBehavior = buttonRepeatBehavior
        self.redactionReasons = redactionReasons
        self.isPrivacySensitive = isPrivacySensitive
        self.isAccessibilityShowsLargeContentViewer = isAccessibilityShowsLargeContentViewer
        self.isAccessibilityQuickActionEnabled = isAccessibilityQuickActionEnabled
        self.accessibilityQuickActionStyle = accessibilityQuickActionStyle
        self.isAccessibilityZoomActionEnabled = isAccessibilityZoomActionEnabled
        self.isAccessibilityScrollActionEnabled = isAccessibilityScrollActionEnabled
        self.isAccessibilityFocusSection = isAccessibilityFocusSection
        self.isAccessibilityImage = isAccessibilityImage
        self.accessibilityLinkDestination = accessibilityLinkDestination
        self.accessibilityLinkedGroup = accessibilityLinkedGroup
        self.accessibilityPage = accessibilityPage
        self.contextMenuForSelectionType = contextMenuForSelectionType
        self.widgetURL = widgetURL
        self.isWidgetAccentable = isWidgetAccentable
        self.widgetAccentedRenderingMode = widgetAccentedRenderingMode
        self.widgetBackgroundStyle = widgetBackgroundStyle
        self.widgetBackgroundPlacement = widgetBackgroundPlacement
        self.widgetRelevancy = widgetRelevancy
        self.paletteSelectionEffect = paletteSelectionEffect
        self.paintsInDeferredPhase = paintsInDeferredPhase
        self.matchedGeometryEffect = matchedGeometryEffect
        self.matchedTransitionSource = matchedTransitionSource
        self.navigationTransition = navigationTransition
        self.chartXAxis = chartXAxis
        self.chartXScale = chartXScale
        self.chartYScale = chartYScale
        self.meshGradient = meshGradient
        self.chartYAxis = chartYAxis
        self.chartLegend = chartLegend
        self.chartBackground = chartBackground
        self.chartPlotStyle = chartPlotStyle
        self.chartOverlay = chartOverlay
        self.chartSelection = chartSelection
        self.chartScrollableAxes = chartScrollableAxes
        self.chartForegroundStyleScale = chartForegroundStyleScale
        self.chartSymbolSize = chartSymbolSize
        self.chartSymbol = chartSymbol
        self.chartAngleScale = chartAngleScale
        self.chartBackgroundStyleScale = chartBackgroundStyleScale
        self.chartSymbolScale = chartSymbolScale
        self.chartXVisibleDomain = chartXVisibleDomain
        self.chartYVisibleDomain = chartYVisibleDomain
        self.chartXSelection = chartXSelection
        self.chartYSelection = chartYSelection
        self.chartAngleSelection = chartAngleSelection
        self.chartScrollPositionX = chartScrollPositionX
        self.chartScrollPositionY = chartScrollPositionY
        self.tableColumnHeadersVisible = tableColumnHeadersVisible
        self.isContentInvalidatable = isContentInvalidatable
        self.isLineSelectable = isLineSelectable
        self.accessibilityActivationPoint = accessibilityActivationPoint
        self.accessibilityTextContentType = accessibilityTextContentType
        self.presentationChrome = presentationChrome
        self.isToolbarContainer = isToolbarContainer
        self.toolbarPlacementTags = toolbarPlacementTags
        self.menuOrder = menuOrder
        self.toolbarTitleMenuChildren = toolbarTitleMenuChildren
        self.toolbarTitleActionsChildren = toolbarTitleActionsChildren
        self.accessibilityRepresentationChildren = accessibilityRepresentationChildren
        self.gestureName = gestureName
        self.textRenderer = textRenderer
        self.coordinateSpaceName = coordinateSpaceName
        self.sectionHeaderChildCount = max(0, sectionHeaderChildCount)
        self.sectionFooterChildCount = max(0, sectionFooterChildCount)
        self.phaseAnimatorState = phaseAnimatorState
        self.position = nil
        self.onPointerEnter = nil
        self.onPointerExit = nil
        self.onPointerMove = nil
        self.onPointerDown = nil
        self.onPointerUpInside = nil
        self.onPointerUpInsideAt = nil
        self.onPointerUpOutside = nil
        self.onContextMenu = nil
        self.onFocusEnter = nil
        self.onFocusExit = nil
        self.onKeyDown = nil
        self.onIMEComposition = nil
        self.textInputCaretRectProvider = nil
        self.onKeyUp = nil
        self.onActivate = nil
        self.onRepeatActivate = nil
        self.onDeleteRows = nil
        self.onMoveRows = nil
        self.onInsertRows = nil
        self.onDropRows = nil
        self.onValidateDrop = nil
        self.onDropEntered = nil
        self.onDropUpdated = nil
        self.onDropExited = nil
        self.onDropProviders = nil
        self.onDropPayloads = nil
        self.onMakeDropConfiguration = nil
        self.onMakeDragPayload = nil
        self.onMakeDragItemProvider = nil
        self.onDragStart = nil
        self.onDragChange = nil
        self.onDragEnd = nil
        self.onLayout = nil
        self.onAppearWithNode = nil
        self.onDisappearWithNode = nil
        self.commandHandlers = [:]
        self.fileExporterConfiguration = nil
        self.fileImporterConfiguration = nil
        self.fileImporterMultiConfiguration = nil
        self.fileMoverConfiguration = nil
        self.inspectorColumnWidth = nil
        self.inspectorColumnWidthFraction = nil
        self.inspectorColumnWidthMin = nil
        self.inspectorPresentationStyle = nil
        self.fileDialogCustomizationID = nil
        self.fileDialogConfirmationLabel = nil
        self.fileDialogDefaultDirectory = nil
        self.fileDialogMessage = nil
        self.toolbarTitleMenuChildren = nil
        self.toolbarTitleActionsChildren = nil
        self.accessibilityRepresentationChildren = nil
        self.isLineSelectable = nil
        self.accessibilityActivationPoint = nil
        self.accessibilityTextContentType = nil
        self.accessibilityMagicTapAction = nil
        self.gestureName = nil
        self.textRenderer = nil
        self.coordinateSpaceName = nil
        self.children = []
        self.resolvedFrame = frame
        self.resolvedContentSize = frame.size
        self.resolvedScrollOffset = 0
        self.hasAppliedInitialScrollAnchor = false
        self.lastAnchoredScrollContentSize = frame.size
        self.lastAnchoredScrollFrameSize = frame.size

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
        removeChild(at: index)
    }

    public func removeFromParent() {
        parent?.removeChild(self)
    }

    public func removeAllChildren() {
        for child in children {
            if child.transition.removal.kind != .identity {
                child.isRemovalOverlay = true
                child.applyRemovalTransition()
                child.cachedFrameKey = nil
                child.cachedFrameCommandRange = nil
                child.cachedSceneKey = nil
                child.cachedScenePaintRange = nil
                runtime?.transitionOverlays.append(child)
                child.parent = nil
                child.setRuntime(nil)
            } else {
                child.markSubtreeDisappeared()
                child.parent = nil
                child.setRuntime(nil)
            }
        }
        if !children.isEmpty {
            runtime?.invalidate()
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
        detachRemovedChild(old)

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
        detachRemovedChild(removed)
        invalidateRuntime()
    }

    /// Runs a child that has just left `children` through its removal
    /// transition (or straight to disappearance) and unparents it. The single
    /// place that decides what leaving looks like — shared by `removeChild`,
    /// `replaceChild` and `setChildren`.
    private func detachRemovedChild(_ removed: ViewNode) {
        removed.onDismantlePlatformView?(removed)
        if removed.transition.removal.kind != .identity {
            removed.isRemovalOverlay = true
            removed.applyRemovalTransition()
            removed.cachedFrameKey = nil
            removed.cachedFrameCommandRange = nil
            removed.cachedSceneKey = nil
            removed.cachedScenePaintRange = nil
            runtime?.transitionOverlays.append(removed)
            runtime?.invalidate()
            removed.parent = nil
            removed.setRuntime(nil)
        } else {
            removed.markSubtreeDisappeared()
            removed.parent = nil
            removed.setRuntime(nil)
        }
    }

    /// Replaces the child list wholesale with `nextChildren`, in that order.
    ///
    /// Children that survive keep their identity and everything hung on it;
    /// children that are gone from the new list leave through
    /// `detachRemovedChild`, exactly as `removeChild` would have taken them.
    /// This is what lets reconciliation *move* a node instead of destroying
    /// and rebuilding it: the index-walking API could only ever replace in
    /// place, so a keyed match that changed position had no way to be
    /// expressed.
    func setChildren(_ nextChildren: [ViewNode]) {
        // A rebuild reconciles every node in the window, and for the
        // overwhelming majority of them it hands back the same child objects
        // in the same order — the reconcile already matched them and updated
        // them in place. Doing the full replacement anyway costs an
        // `ObjectIdentifier` set, a filtered array, a `setRuntime` walk of the
        // whole subtree (which is quadratic in tree depth once every node
        // does it), and a `.children` invalidation that says the child list
        // changed when it did not — which is a lie the layout pass believes,
        // and the reason a rebuild used to re-descend subtrees nothing had
        // touched.
        if isChildListUnchanged(nextChildren) {
            return
        }

        let surviving = Set(nextChildren.map(ObjectIdentifier.init))
        let departing = children.filter { !surviving.contains(ObjectIdentifier($0)) }
        children = []
        for child in departing {
            detachRemovedChild(child)
        }
        for child in nextChildren {
            if child.parent !== self {
                child.removeFromParent()
                child.parent = self
            }
            child.setRuntime(runtime)
        }
        children = nextChildren
        invalidateRuntime(.children)
    }

    /// Whether `nextChildren` is the list this node already has: same objects,
    /// same order, each already parented here and already carrying this
    /// node's runtime. All three have to hold, because the replacement path
    /// establishes all three and skipping it must not leave any of them
    /// half-done.
    private func isChildListUnchanged(_ nextChildren: [ViewNode]) -> Bool {
        guard children.count == nextChildren.count else {
            return false
        }
        for index in nextChildren.indices {
            let child = nextChildren[index]
            guard children[index] === child, child.parent === self, child.runtime === runtime else {
                return false
            }
        }
        return true
    }

    fileprivate func setRuntime(_ runtime: RetainedViewRuntime?) {
        if self.runtime !== runtime {
            self.runtime?.releaseInteractionTargets(in: self)
        }

        // Animation registration follows the node across runtimes: a node
        // detached mid-animation (a removal overlay) must not keep the old
        // runtime's driver awake, and a node attached mid-animation must be
        // ticked by the new one.
        if !animationStates.isEmpty {
            self.runtime?.unregisterAnimatingNode(self)
            runtime?.registerAnimatingNode(self)
        }
        self.runtime = runtime
        for child in children {
            child.setRuntime(runtime)
        }
    }

    internal func markSubtreeDisappeared() {
        if hasAppeared {
            onDisappear?()
            onDisappearWithNode?(self)
            cancelLifecycleTasks()
            hasAppeared = false
        }
        // A node that leaves and comes back is a real insertion the second
        // time, whatever it was on the host's first build — and whatever it
        // played on the way in the first time.
        isInitialBuildNode = false
        didPlayInsertionTransition = false

        for child in children {
            child.markSubtreeDisappeared()
        }
    }

    public func launchLifecycleTask(_ launch: ViewLifecycleTaskLaunch) {
        lifecycleTasks[launch.key]?.cancel()
        lifecycleTasks[launch.key] = Task(priority: launch.priority) {
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

    // MARK: - Traversal depth

    /// Hard cap on nested layout / measure / prepaint / command traversal.
    /// Deep trees are legal here — every `WinSwiftUI` modifier adds a wrapper
    /// node, so depth grows with modifier-chain length and not only with
    /// nesting — but a pathological chain has to degrade to a diagnostic
    /// instead of overflowing the main thread's stack. A stack overflow on
    /// Windows is an access violation: no Swift error, no renderer fallback,
    /// no log line.
    ///
    /// 256 is a *stack guarantee*, not just a backstop, and that took work.
    /// Layout, prepaint and the frame-path command walk were recursions whose
    /// unoptimized frames ran 12 KB, 15 KB and 24 KB; against a 1 MB stack the
    /// real ceiling was about 43 levels — an eighth of this number, and one
    /// level above the deepest demo screen. All three are now explicit
    /// worklists (`ScenePainter.paintNode` was the first, for the same
    /// reason), so their depth costs an array element and no stack at all.
    /// Measurement is still a recursion, because it returns a value up the
    /// tree, and is held to roughly a kilobyte a level: 256 of those is about
    /// a quarter of the stack, in debug, which is the worst case that ships.
    /// `TraversalStackHeadroomTests` renders a tree at this exact depth and is
    /// what keeps that true.
    ///
    /// The counter is shared across all four walks — measurement nests inside
    /// layout, and the worklists publish their depth on it (see
    /// `enterTraversal(atDepth:)`) — so it bounds the real nesting rather than
    /// any one function's.
    ///
    /// The demo's deepest screen reaches 42 (`maxObservedTraversalDepth`), so
    /// the cap leaves ~6× headroom for real trees.
    internal static var maximumTraversalDepth = 256
    private static var traversalDepth = 0
    private static var hasReportedTraversalDepthOverflow = false
    /// Number of subtrees dropped by the depth cap since process start.
    internal private(set) static var traversalDepthOverflowCount = 0
    /// Deepest nesting any traversal has reached. Diagnostic only — it is what
    /// the cap has to stay comfortably above for real view trees.
    internal private(set) static var maxObservedTraversalDepth = 0

    /// Returns false when the cap is reached; the caller must then return
    /// without recursing (and without a matching `leaveTraversal`).
    fileprivate static func enterTraversal() -> Bool {
        guard traversalDepth < maximumTraversalDepth else {
            reportTraversalDepthOverflow()
            return false
        }
        traversalDepth += 1
        if traversalDepth > maxObservedTraversalDepth {
            maxObservedTraversalDepth = traversalDepth
        }
        return true
    }

    /// The same cap, the same counter, addressed by absolute depth instead of
    /// by nesting — what an explicit-worklist traversal needs, since its
    /// "depth" is a field in a heap record rather than a stack frame.
    ///
    /// It also *publishes* that depth on the shared counter, so the recursive
    /// helpers a de-recursed traversal still calls (`markSubtreeRendered`,
    /// `shiftCachedFrameRangesRecursively`) are bounded from where they were
    /// really entered rather than from zero.
    fileprivate static func enterTraversal(atDepth depth: Int) -> Bool {
        guard depth < maximumTraversalDepth else {
            reportTraversalDepthOverflow()
            return false
        }
        traversalDepth = depth + 1
        if traversalDepth > maxObservedTraversalDepth {
            maxObservedTraversalDepth = traversalDepth
        }
        return true
    }

    private static func reportTraversalDepthOverflow() {
        traversalDepthOverflowCount += 1
        guard !hasReportedTraversalDepthOverflow else { return }
        hasReportedTraversalDepthOverflow = true
        FileHandle.standardError.write(
            Data(
                """
                [SwiftWindowsUI] view tree deeper than \
                \(maximumTraversalDepth) levels; the subtree below \
                that depth is not laid out or painted.

                """.utf8
            )
        )
    }

    fileprivate static func leaveTraversal() {
        traversalDepth -= 1
    }

    /// One node's entry in the layout traversal — the whole state a level
    /// needs, which is why layout can afford to be a worklist.
    private struct LayoutTraversalContext {
        let node: ViewNode
        let depth: Int
    }

    private enum LayoutTraversalStep {
        case enter(LayoutTraversalContext)
        /// Runs once the subtree below the node has been laid out: an
        /// `.absolute` container's content size is the union of frames its
        /// children only settle on down there, and the scroll anchor and the
        /// clamped offset both read that size.
        case finish(LayoutTraversalContext)
    }

    /// Layout, as an explicit worklist rather than a recursion.
    ///
    /// Every level of this walk also runs the *measure* recursion beneath it,
    /// so the two share the main thread's 1 MB; at `-Onone` a level of layout
    /// cost some five kilobytes of frame, which put `maximumTraversalDepth`
    /// (256) four times over the stack it was supposed to be a backstop for.
    /// De-recursed, a level costs an array element and the measure walk gets
    /// the stack to itself.
    fileprivate func layoutSubtree(displayScale: Double) {
        let baseDepth = ViewNode.traversalDepth
        defer { ViewNode.traversalDepth = baseDepth }

        var traversal: [LayoutTraversalStep] = [
            .enter(LayoutTraversalContext(node: self, depth: 0))
        ]

        while let traversalStep = traversal.popLast() {
            let context: LayoutTraversalContext
            switch traversalStep {
            case .finish(let finishContext):
                ViewNode.traversalDepth = baseDepth + finishContext.depth + 1
                finishContext.node.finishLayoutPass()
                continue

            case .enter(let entryContext):
                context = entryContext
            }

            let node = context.node
            guard ViewNode.enterTraversal(atDepth: baseDepth + context.depth) else { continue }
            node.runtime?.recordLayoutVisit()

            // Recomputed, never latched: a scrollable node's virtualization
            // flag is only as true as the deferrals this pass is about to
            // observe below it. Cleared here — before any descendant can defer
            // — so the pass that reconciles a lazy stack into an eager one is
            // also the pass that stops charging every later scroll a layout
            // invalidation.
            if node.scrollAxis != nil { node.hasVirtualizedDescendants = false }

            // Sanitize before the cache key is minted so the key, the geometry
            // the painter reads, and the geometry the next pass compares
            // against are all the same finite values.
            node.resolvedFrame = sanitizedLayoutRect(node.resolvedFrame)

            // Collected here rather than at build time because this is the
            // first point at which the reader's frame is both resolved and
            // known to belong to the live tree: a build-time registry would
            // hold the throwaway nodes reconciliation discards. Above the
            // clean-path skip, so a reader whose slot moved under an
            // otherwise-cached ancestor is still offered to the loop.
            if node.geometryReaderBuild != nil {
                node.runtime?.recordGeometryReaderCandidate(node)
            }

            let layoutKey = ViewLayoutCacheKey(frame: node.resolvedFrame, displayScale: displayScale)
            let layoutDirtyFlags = node.subtreeDirtyFlags.intersection([.layout, .children])
            if layoutDirtyFlags.isEmpty, node.cachedLayoutKey == layoutKey {
                node.enqueueCleanPathChildren(into: &traversal, depth: context.depth)
                node.lastLayoutVisitPassID = node.runtime?.layoutPassID ?? 0
                continue
            }

            node.beginLayoutPass()

            // The node's own frame is settled and its children's frames are
            // computed here; `finish` closes the pass once they have been laid
            // out. Pushed before the children so it pops after all of them.
            traversal.append(.finish(context))
            node.placeChildren(into: &traversal, depth: context.depth, layoutKey: layoutKey)
        }
    }

    /// Everything that happens to a node before its children are placed:
    /// the layout callback, `.position()`'s re-centring, and the scroll offset
    /// a descendant `.lazyStack` will resolve its viewport against.
    @inline(never)
    private func beginLayoutPass() {
        onLayout?(resolvedFrame)

        if let position = position {
            let size = resolvedFrame.size
            resolvedFrame = Rect(
                x: position.x - size.width / 2,
                y: position.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        // Published before the children lay out, not only after: a
        // descendant `.lazyStack` resolves its viewport against this value,
        // and reading last pass's offset means it virtualizes against the
        // rows the user was looking at a frame ago. Clamping needs
        // `resolvedContentSize`, which this pass is about to recompute, so
        // the assignment at the end of the pass stands as the authoritative
        // one and this is the best estimate available before it.
        resolvedScrollOffset = effectiveScrollOffset
    }

    /// Places the children and enqueues the ones that still have to be laid
    /// out, deepest-last so the worklist pops them in order.
    @inline(never)
    private func placeChildren(
        into traversal: inout [LayoutTraversalStep],
        depth: Int,
        layoutKey: ViewLayoutCacheKey
    ) {
        pendingLayoutKey = layoutKey
        var descendants: [ViewNode] = []
        switch layoutMode {
        case .absolute:
            layoutAbsoluteChildren(descendants: &descendants)

        case .stack(let stackLayout), .lazyStack(let stackLayout):
            layoutStackChildren(stackLayout: stackLayout, descendants: &descendants)

        case .flex(let flexStyle):
            layoutFlexChildren(flexStyle: flexStyle, descendants: &descendants)
        }

        for child in descendants.reversed() {
            traversal.append(.enter(LayoutTraversalContext(node: child, depth: depth + 1)))
        }
    }

    /// Closes a node's layout pass, once its subtree has been laid out.
    @inline(never)
    private func finishLayoutPass() {
        if case .absolute = layoutMode {
            // Read back rather than accumulated during placement: a child with
            // `.position()` rewrites its own frame while *it* lays out, so the
            // union is only correct once the subtree below has settled.
            var maxChildX: Double = 0
            var maxChildY: Double = 0
            for child in children {
                maxChildX = max(maxChildX, child.resolvedFrame.maxX)
                maxChildY = max(maxChildY, child.resolvedFrame.maxY)
            }
            resolvedContentSize = Size(
                width: max(resolvedFrame.size.width, maxChildX),
                height: max(resolvedFrame.size.height, maxChildY)
            )
        }

        resolvedContentSize = sanitizedLayoutSize(resolvedContentSize)
        applyDefaultScrollAnchorAfterLayout()
        if let pendingLayoutKey {
            cachedLayoutKey = pendingLayoutKey
        }
        pendingLayoutKey = nil
        resolvedScrollOffset = effectiveScrollOffset
        lastLayoutVisitPassID = runtime?.layoutPassID ?? 0
    }

    /// A clean node still has to let its dirty or newly-visible descendants
    /// through: a scroll frame dirties `.paint`, not `.layout`, so this — not
    /// the placement loop — is the path a scrolling list actually takes, and
    /// it is where rows that have just come into range are laid out. The
    /// window is recomputed here rather than carried, and every child is
    /// tested rather than only the dirty ones, because a deferred row's dirty
    /// flags were cleared by the painter's cull while it was off-screen.
    @inline(never)
    private func enqueueCleanPathChildren(
        into traversal: inout [LayoutTraversalStep],
        depth: Int
    ) {
        runtime?.recordLayoutReuse()
        resolvedScrollOffset = effectiveScrollOffset

        var descendants: [ViewNode] = []
        if layoutMode.virtualizesChildren, let mainAxis = layoutMode.stackLayout?.axis {
            let window = layoutVirtualizationWindow()
            for child in children {
                if Self.isOutsideLayoutViewport(child.resolvedFrame, viewport: window, axis: mainAxis) {
                    child.isLayoutDeferredByVirtualization = true
                    virtualizationScrollAncestor?.hasVirtualizedDescendants = true
                    runtime?.recordVirtualizedLayoutSkip()
                    continue
                }
                let resumed = child.resumeVirtualizedLayout()
                if resumed || child.hasDirtySubtree {
                    descendants.append(child)
                }
            }
        } else if hasDirtySubtree || isOnVirtualizationDescentPath {
            // The descent-path term is what keeps a lazy stack reachable
            // through a clean ancestor: a scroll dirties the scrollable node,
            // not the panel between it and the stack, and a stack never
            // reached is a stack that never resumes its rows.
            for child in children where child.hasDirtySubtree || child.isOnVirtualizationDescentPath {
                descendants.append(child)
            }
        }

        for child in descendants.reversed() {
            traversal.append(.enter(LayoutTraversalContext(node: child, depth: depth + 1)))
        }
    }

    /// `.absolute`: every child keeps its own origin and is measured against
    /// what is left of the container from there.
    @inline(never)
    private func layoutAbsoluteChildren(descendants: inout [ViewNode]) {
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
            descendants.append(child)
        }
    }

    /// `.flex`: the engine solves the whole row or column, then each child is
    /// placed at the frame it was given.
    @inline(never)
    private func layoutFlexChildren(flexStyle: FlexStyle, descendants: inout [ViewNode]) {
        let layouts = flexChildLayouts(for: flexStyle)

        var visibleIndex = 0
        for child in children {
            if child.isHidden {
                child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
                continue
            }

            let childLayout = layouts[visibleIndex]
            child.resolvedFrame = Rect(
                x: childLayout.x, y: childLayout.y, width: childLayout.width, height: childLayout.height)
            descendants.append(child)
            visibleIndex += 1
        }

        resolvedContentSize = resolvedFrame.size
    }

    /// `.stack` / `.lazyStack`: allocate the track, then walk it placing —
    /// and, unless virtualization defers them, laying out — each child.
    @inline(never)
    private func layoutStackChildren(stackLayout: StackLayout, descendants: inout [ViewNode]) {
        let allocation = stackAllocation(for: stackLayout)
        // nil for a plain `.stack` and for a `.lazyStack` with nothing
        // scrollable above it, which is what makes virtualization opt-in
        // and bounded rather than a guess.
        let virtualizationWindow = layoutVirtualizationWindow()
        var cursor = StackPlacementCursor(mainCursor: allocation.mainCursorStart)

        for child in children {
            if placeStackChild(
                child,
                stackLayout: stackLayout,
                allocation: allocation,
                virtualizationWindow: virtualizationWindow,
                cursor: &cursor
            ) {
                descendants.append(child)
            }
        }

        resolvedContentSize = stackContentSize(
            stackLayout: stackLayout, allocation: allocation, maxCrossExtent: cursor.maxCrossExtent)
    }

    /// Places one child of a stack and answers whether it should now be laid
    /// out — false when it is hidden, or when virtualization defers it.
    @inline(never)
    private func placeStackChild(
        _ child: ViewNode,
        stackLayout: StackLayout,
        allocation: StackAllocation,
        virtualizationWindow: Rect?,
        cursor: inout StackPlacementCursor
    ) -> Bool {
        if child.isHidden {
            child.resolvedFrame = Rect(x: 0, y: 0, width: 0, height: 0)
            return false
        }

        let placement = stackChildPlacement(
            of: child,
            stackLayout: stackLayout,
            contentRect: allocation.contentRect,
            desiredSize: allocation.desiredSizes[cursor.visibleIndex],
            allocatedMainSize: allocation.allocatedMainSizes[cursor.visibleIndex],
            mainCursor: cursor.mainCursor
        )

        child.resolvedFrame = placement.frame
        cursor.mainCursor += placement.mainAdvance + allocation.effectiveSpacing
        cursor.maxCrossExtent = max(cursor.maxCrossExtent, placement.crossExtent)
        cursor.visibleIndex += 1

        if Self.isOutsideLayoutViewport(
            placement.frame, viewport: virtualizationWindow, axis: stackLayout.axis)
        {
            child.isLayoutDeferredByVirtualization = true
            virtualizationScrollAncestor?.hasVirtualizedDescendants = true
            runtime?.recordVirtualizedLayoutSkip()
            return false
        }

        _ = child.resumeVirtualizedLayout()
        return true
    }

    /// What a placed stack reports as its content size — the scrollable extent
    /// its children occupied. Out of line for the recursion's sake.
    @inline(never)
    private func stackContentSize(
        stackLayout: StackLayout,
        allocation: StackAllocation,
        maxCrossExtent: Double
    ) -> Size {
        let mainSizes =
            allocation.allowsOverflowAlongMainAxis
            ? allocation.desiredMainSizes : allocation.allocatedMainSizes
        let contentMainExtent =
            mainSizes.reduce(0, +) + allocation.spacingTotal + stackMainPadding(for: stackLayout)
        let contentCrossExtent = maxCrossExtent + stackCrossPadding(for: stackLayout)

        switch stackLayout.axis {
        case .vertical:
            return Size(
                width: max(resolvedFrame.size.width, contentCrossExtent),
                height: max(resolvedFrame.size.height, contentMainExtent)
            )
        case .horizontal:
            return Size(
                width: max(resolvedFrame.size.width, contentMainExtent),
                height: max(resolvedFrame.size.height, contentCrossExtent)
            )
        }
    }

    /// Everything a stack decides *before* it starts placing children: how big
    /// each one wants to be, how much of the track each one gets, and where
    /// the first one starts.
    ///
    /// Out of line, and never inlined back. In an unoptimized build this
    /// block's flex/shrink/distribution arithmetic is kilobytes of
    /// temporaries, and it runs with the measure recursion live beneath it —
    /// `sizeThatFits` on every visible child. Out of line those temporaries
    /// are charged to a frame that is gone before the walk goes any deeper.
    @inline(never)
    private func stackAllocation(for stackLayout: StackLayout) -> StackAllocation {
        let contentRect = Rect(origin: .zero, size: resolvedFrame.size).inset(by: stackLayout.padding)
        let visibleChildren = children.filter { !$0.isHidden }
        let childConstraints = stackChildConstraints(for: contentRect.size, axis: stackLayout.axis)
        let desiredSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
        let desiredMainSizes = desiredSizes.map { size in
            stackLayout.axis == .vertical ? size.height : size.width
        }
        let spacingTotal = stackLayoutSpacingTotal(count: visibleChildren.count, spacing: stackLayout.spacing)
        let availableMainExtent =
            stackLayout.axis == .vertical ? max(0, contentRect.size.height) : max(0, contentRect.size.width)
        let availableChildMainExtent = max(0, availableMainExtent - spacingTotal)
        let allowsOverflowAlongMainAxis = scrollAxis == stackScrollAxis(for: stackLayout.axis)

        // Shrink floors keep text-bearing content readable under
        // pressure: a squeezed stack compresses padding, spacers, and
        // flexible siblings before it crushes a label below its
        // measured main-axis size (see stackShrinkFloorMainExtent).
        // Computed only when a squeeze actually occurs. A floor
        // protects a child from sibling pressure, never from a
        // container that is smaller than the child alone, so each
        // floor is capped at this node's full main extent (full, not
        // the content box: floors may extend into padding — that is
        // how padding compresses before text).
        var shrinkFloors: [Double] = []
        if !allowsOverflowAlongMainAxis,
            stackLayout.distribution != .fillEqually,
            desiredMainSizes.reduce(0, +) > availableChildMainExtent
        {
            let floorCap =
                stackLayout.axis == .vertical
                ? resolvedFrame.size.height : resolvedFrame.size.width
            shrinkFloors = visibleChildren.map {
                min(
                    $0.stackShrinkFloorMainExtent(along: stackLayout.axis, constraints: childConstraints),
                    floorCap
                )
            }
        }

        // Allocate main sizes with flex support
        var allocatedMainSizes: [Double]
        if allowsOverflowAlongMainAxis {
            allocatedMainSizes = desiredMainSizes
        } else if stackLayout.distribution == .fillEqually, !visibleChildren.isEmpty {
            // Equality wins over content pressure: every child gets the
            // same share of the track, shrink floors and flex do not
            // apply. An unconstrained track falls back to the widest
            // desired extent so intrinsic measurement stays equal too.
            let share =
                availableChildMainExtent.isFinite
                ? max(0, availableChildMainExtent / Double(visibleChildren.count))
                : (desiredMainSizes.max() ?? 0)
            allocatedMainSizes = [Double](repeating: share, count: visibleChildren.count)
        } else {
            allocatedMainSizes = allocateMainSizes(
                desiredSizes: desiredMainSizes,
                children: visibleChildren,
                axis: stackLayout.axis,
                availableExtent: availableChildMainExtent,
                shrinkFloors: shrinkFloors
            )
        }

        // Apply flex grow/shrink
        if !allowsOverflowAlongMainAxis, stackLayout.distribution != .fillEqually,
            !visibleChildren.isEmpty
        {
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
                // Shrink items with flexShrink > 0, still honoring the
                // shrink floors so text is never crushed below its
                // measured main-axis size.
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
                        allocatedMainSizes[i] = max(
                            shrinkFloors.isEmpty ? 0 : shrinkFloors[i], allocatedMainSizes[i] - share)
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
        case .fill, .fillEqually:
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

        // Padding compresses in placement as it does in allocation:
        // when the occupied extent cannot fit the content box, the
        // leading padding yields (down to the node's own edge) before
        // children overflow the trailing edge. When content fits, the
        // clamp is a no-op; scrollable axes keep natural placement.
        var mainCursor = mainCursorStart
        if !allowsOverflowAlongMainAxis {
            let fullMainExtent =
                stackLayout.axis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width
            mainCursor = max(0, min(mainCursorStart, fullMainExtent - occupiedMainExtent))
        }

        return StackAllocation(
            contentRect: contentRect,
            desiredSizes: desiredSizes,
            desiredMainSizes: desiredMainSizes,
            allocatedMainSizes: allocatedMainSizes,
            spacingTotal: spacingTotal,
            effectiveSpacing: effectiveSpacing,
            mainCursorStart: mainCursor,
            allowsOverflowAlongMainAxis: allowsOverflowAlongMainAxis
        )
    }

    /// Where one child of a stack goes, and how much of the cross axis it
    /// claims.
    ///
    /// Out of line for the same reason `stackAllocation` is: this switch is
    /// the widest block in the placement loop, and that loop runs with the
    /// measure recursion live beneath it — the one walk that still spends
    /// stack per level, and so the one whose callers stay narrow.
    @inline(never)
    private func stackChildPlacement(
        of child: ViewNode,
        stackLayout: StackLayout,
        contentRect: Rect,
        desiredSize: Size,
        allocatedMainSize: Double,
        mainCursor: Double
    ) -> StackChildPlacement {
        switch stackLayout.axis {
        case .vertical:
            let proposedWidth = max(0, contentRect.size.width)
            let measuredWidth = min(desiredSize.width, proposedWidth)
            let width: Double
            if stackLayout.alignment == .stretch {
                width = proposedWidth
            } else if measuredWidth == 0, child.expandsAlongStackCrossAxis, proposedWidth > 0 {
                // macOS parity: a flexible-width child (a Color /
                // background-painted panel with no intrinsic or explicit
                // width) takes the stack's cross-axis width instead of
                // collapsing to zero.
                width = proposedWidth
            } else {
                width = measuredWidth
            }
            let height = max(0, allocatedMainSize)

            let x: Double
            let usesCustomAlignmentGuide: Bool
            if let guidedX = stackCrossOriginUsingAlignmentGuide(
                for: child,
                stackAxis: .vertical,
                stackAlignment: stackLayout.alignment,
                contentOrigin: contentRect.origin.x,
                contentExtent: contentRect.size.width,
                childExtent: width
            ) {
                x = guidedX
                usesCustomAlignmentGuide = true
            } else {
                usesCustomAlignmentGuide = false
                switch stackLayout.alignment {
                case .leading, .stretch, .firstTextBaseline, .customVertical:
                    x = contentRect.origin.x
                case .center:
                    x = contentRect.origin.x + max(0, (contentRect.size.width - width) * 0.5)
                case .trailing, .lastTextBaseline:
                    x = contentRect.maxX - width
                case .customHorizontal:
                    x = contentRect.origin.x
                }
            }

            return StackChildPlacement(
                frame: Rect(x: x, y: mainCursor, width: max(0, width), height: max(0, height)),
                mainAdvance: height,
                crossExtent: usesCustomAlignmentGuide
                    ? max(0, x - contentRect.origin.x + width) : width
            )

        case .horizontal:
            let width = max(0, allocatedMainSize)
            let proposedHeight = max(0, contentRect.size.height)
            let measuredHeight = min(desiredSize.height, proposedHeight)
            let height: Double
            if stackLayout.alignment == .stretch {
                height = proposedHeight
            } else if measuredHeight == 0, child.expandsAlongStackCrossAxis, proposedHeight > 0 {
                // macOS parity: flexible-height children take the stack's
                // cross-axis height (mirrors the vertical case above).
                height = proposedHeight
            } else {
                height = measuredHeight
            }

            let y: Double
            let usesCustomAlignmentGuide: Bool
            if let guidedY = stackCrossOriginUsingAlignmentGuide(
                for: child,
                stackAxis: .horizontal,
                stackAlignment: stackLayout.alignment,
                contentOrigin: contentRect.origin.y,
                contentExtent: contentRect.size.height,
                childExtent: height
            ) {
                y = guidedY
                usesCustomAlignmentGuide = true
            } else {
                usesCustomAlignmentGuide = false
                switch stackLayout.alignment {
                case .leading, .stretch:
                    y = contentRect.origin.y
                case .center:
                    y = contentRect.origin.y + max(0, (contentRect.size.height - height) * 0.5)
                case .trailing:
                    y = contentRect.maxY - height
                case .firstTextBaseline:
                    y = contentRect.origin.y + max(0, contentRect.size.height * 0.8 - height * 0.8)
                case .lastTextBaseline:
                    y = contentRect.origin.y + max(0, contentRect.size.height * 0.8 - height * 0.8)
                case .customHorizontal:
                    y = contentRect.origin.y
                case .customVertical:
                    y = contentRect.origin.y
                }
            }

            return StackChildPlacement(
                frame: Rect(x: mainCursor, y: y, width: max(0, width), height: max(0, height)),
                mainAdvance: width,
                crossExtent: usesCustomAlignmentGuide
                    ? max(0, y - contentRect.origin.y + height) : height
            )
        }
    }

    /// The flex engine's answer for this node's visible children — the whole
    /// measure-and-solve step, out of line so `layoutSubtree` carries the
    /// resulting array and not the inputs that produced it.
    @inline(never)
    private func flexChildLayouts(for flexStyle: FlexStyle) -> [FlexboxEngine.ChildLayout] {
        let visibleChildren = children.filter { !$0.isHidden }

        let childInputs = visibleChildren.map { child -> FlexboxEngine.LayoutInput.ChildInput in
            let intrinsicSize = child.intrinsicContentSize()
            return FlexboxEngine.LayoutInput.ChildInput(
                itemStyle: child.flexItemStyle,
                intrinsicWidth: child.preferredSize?.width ?? intrinsicSize.width,
                intrinsicHeight: child.preferredSize?.height ?? intrinsicSize.height
            )
        }

        return FlexboxEngine.layout(
            FlexboxEngine.LayoutInput(
                containerWidth: resolvedFrame.size.width,
                containerHeight: resolvedFrame.size.height,
                style: flexStyle,
                children: childInputs
            )
        )
    }

    /// The region of this node's own coordinate space — the space its
    /// children's frames live in — that a scrollable ancestor can show,
    /// or `nil` when this node does not virtualize or nothing above it
    /// scrolls.
    ///
    /// Computed by walking *up* to the nearest scrollable ancestor rather
    /// than pushed down during layout, for one reason: a scroll frame
    /// dirties `.paint`, not `.layout`, so most layout passes over a
    /// scrolling list never reach the code that would refresh a pushed-down
    /// value. A stale window is not a slow list, it is rows that scrolled
    /// into view and were never laid out. The walk is O(depth), once per
    /// lazy stack per pass.
    ///
    /// Kept out of line so the placement loop it is called from gains a call
    /// and not a rectangle.
    internal func layoutVirtualizationWindow() -> Rect? {
        guard layoutMode.virtualizesChildren else { return nil }
        var offsetX: Double = 0
        var offsetY: Double = 0
        var node: ViewNode? = self
        var depth = 0
        while let current = node, depth < ViewNode.maximumTraversalDepth {
            if let axis = current.scrollAxis {
                // Remember which node's offset governs this window, so a
                // scroll can invalidate layout for virtualized content and
                // only for virtualized content.
                virtualizationScrollAncestor = current
                // And record the path itself, so a later pass that would
                // early-return at a clean node between here and there
                // descends far enough to reach this stack instead.
                stampVirtualizationDescentPath(upTo: current)
                // The ancestor's visible window lives in ITS content space;
                // subtracting the accumulated offset restates it in ours.
                let window = Rect(
                    x: (axis == .horizontal ? current.resolvedScrollOffset : 0) - offsetX,
                    y: (axis == .vertical ? current.resolvedScrollOffset : 0) - offsetY,
                    width: current.resolvedFrame.size.width,
                    height: current.resolvedFrame.size.height)
                return window.origin.x.isFinite && window.origin.y.isFinite ? window : nil
            }
            offsetX += current.resolvedFrame.origin.x
            offsetY += current.resolvedFrame.origin.y
            node = current.parent
            depth += 1
        }
        return nil
    }

    /// Stamps this pass onto every node from this stack up to and including
    /// `ancestor`, the scrollable node its virtualization window came from.
    ///
    /// Only that span is marked. A lazy stack with nothing scrollable above
    /// it virtualizes nothing, so nothing above it needs to be kept
    /// reachable on its account.
    private func stampVirtualizationDescentPath(upTo ancestor: ViewNode) {
        let passID = runtime?.layoutPassID ?? 0
        var node: ViewNode? = self
        var depth = 0
        while let current = node, depth < ViewNode.maximumTraversalDepth {
            current.virtualizationDescentPassID = passID
            if current === ancestor { return }
            node = current.parent
            depth += 1
        }
    }

    /// True when `frame` sits entirely outside `viewport` along `axis`, with
    /// a full viewport extent of overscan on each side.
    ///
    /// The overscan is what makes the skip safe rather than merely fast. A
    /// row's subtree may draw outside the row (a shadow, an overlay, a
    /// negative offset), and layout is not the place that knows how far;
    /// putting a whole viewport of slack on each side means anything that
    /// could plausibly reach the visible area was laid out anyway, while the
    /// work still stays proportional to the viewport rather than to the list.
    /// A nil viewport (no scrollable ancestor) virtualizes nothing.
    private static func isOutsideLayoutViewport(
        _ frame: Rect, viewport: Rect?, axis: StackAxis
    ) -> Bool {
        guard let viewport else { return false }
        let overscan: Double
        let start: Double
        let end: Double
        let frameStart: Double
        let frameEnd: Double
        switch axis {
        case .vertical:
            overscan = max(viewport.size.height, 0)
            start = viewport.origin.y - overscan
            end = viewport.origin.y + viewport.size.height + overscan
            frameStart = frame.origin.y
            frameEnd = frame.maxY
        case .horizontal:
            overscan = max(viewport.size.width, 0)
            start = viewport.origin.x - overscan
            end = viewport.origin.x + viewport.size.width + overscan
            frameStart = frame.origin.x
            frameEnd = frame.maxX
        }
        guard start.isFinite, end.isFinite, frameStart.isFinite, frameEnd.isFinite else { return false }
        return frameEnd < start || frameStart > end
    }

    private func applyDefaultScrollAnchorAfterLayout() {
        let contentSizeChanged = resolvedContentSize != lastAnchoredScrollContentSize
        let frameSizeChanged = resolvedFrame.size != lastAnchoredScrollFrameSize

        defer {
            lastAnchoredScrollContentSize = resolvedContentSize
            lastAnchoredScrollFrameSize = resolvedFrame.size
        }

        guard isScrollable else {
            return
        }

        if !hasAppliedInitialScrollAnchor {
            if let initialScrollAnchor {
                scrollOffset = anchoredScrollOffset(for: initialScrollAnchor)
            }
            hasAppliedInitialScrollAnchor = true
            return
        }

        if contentSizeChanged || frameSizeChanged, let scrollSizeChangeAnchor {
            scrollOffset = anchoredScrollOffset(for: scrollSizeChangeAnchor)
        }
    }

    private func anchoredScrollOffset(for anchor: RetainedScrollAnchor) -> Double {
        switch scrollAxis {
        case .horizontal:
            return clampedScrollOffset(for: maxScrollOffset * anchor.x)
        case .vertical:
            return clampedScrollOffset(for: maxScrollOffset * anchor.y)
        case nil:
            return 0
        }
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

    /// One node's entry in prepaint's explicit traversal.
    private struct PrepaintTraversalContext {
        let node: ViewNode
        let parentOrigin: Point
        let inheritedClip: RuntimeClipShape?
        let inheritedOpacity: Float
        let parentDispatchIndex: Int?
        let inheritedInverseTransform: Transform2D?
        let inheritedTransform: Transform2D
        let inheritedColorEffects: [RetainedColorEffect]
        let inheritedBlendMode: BlendMode
        let depth: Int
        /// A child is a candidate for deferral; the node a traversal is
        /// *entered* at never is — it is either the root or a subtree being
        /// resumed precisely because it was already deferred once.
        let isDeferralCandidate: Bool
    }

    /// The half of a node's prepaint visit that can only run once its
    /// descendants have contributed: its scroll indicator draws over them, and
    /// the range it caches is not closed until they have all been recorded.
    private struct PrepaintFinishState {
        let node: ViewNode
        let startIndex: PrepaintStateIndex
        let cacheKey: ViewPaintCacheKey
        let dispatchIndex: Int
        let absoluteFrame: Rect
        let inheritedTransform: Transform2D
        let centeredTransform: Transform2D
        let effectiveClip: RuntimeClipShape?
        let effectiveOpacity: Float
        let depth: Int
    }

    private enum PrepaintTraversalStep {
        case enter(PrepaintTraversalContext)
        case finish(PrepaintFinishState)
    }

    /// Prepaint's walk over the tree, as an explicit worklist.
    ///
    /// De-recursed for the same reason `appendCommands` was: an unoptimized
    /// build gave this a 15 KB frame, and `maximumTraversalDepth` is 256 — a
    /// cap the stack could not actually honour. Depth is now an integer in a
    /// heap record, so the cap bounds the *tree*, which is what it was always
    /// meant to mean.
    fileprivate func appendPrepaintState(
        into state: inout RuntimePrepaintState,
        parentOrigin: Point,
        inheritedClip: RuntimeClipShape?,
        inheritedOpacity: Float = 1,
        parentDispatchIndex: Int? = nil,
        inheritedInverseTransform: Transform2D? = nil,
        inheritedTransform: Transform2D = .identity,
        inheritedColorEffects: [RetainedColorEffect] = [],
        inheritedBlendMode: BlendMode = .normal,
        previousState: RuntimePrepaintState? = nil,
        displayScale: Double = 1,
        replayCount: inout Int
    ) {
        let baseDepth = ViewNode.traversalDepth
        defer { ViewNode.traversalDepth = baseDepth }

        var traversal: [PrepaintTraversalStep] = [
            .enter(
                PrepaintTraversalContext(
                    node: self,
                    parentOrigin: parentOrigin,
                    inheritedClip: inheritedClip,
                    inheritedOpacity: inheritedOpacity,
                    parentDispatchIndex: parentDispatchIndex,
                    inheritedInverseTransform: inheritedInverseTransform,
                    inheritedTransform: inheritedTransform,
                    inheritedColorEffects: inheritedColorEffects,
                    inheritedBlendMode: inheritedBlendMode,
                    depth: 0,
                    isDeferralCandidate: false
                )
            )
        ]

        while let traversalStep = traversal.popLast() {
            let context: PrepaintTraversalContext
            switch traversalStep {
            case .finish(let finish):
                ViewNode.traversalDepth = baseDepth + finish.depth + 1
                finish.node.appendScrollIndicatorDeferredDraw(
                    into: &state,
                    dispatchIndex: finish.dispatchIndex,
                    absoluteFrame: finish.absoluteFrame,
                    inheritedTransform: finish.inheritedTransform,
                    centeredTransform: finish.centeredTransform,
                    effectiveClip: finish.effectiveClip,
                    effectiveOpacity: finish.effectiveOpacity
                )
                finish.node.cachedPrepaintKey = finish.cacheKey
                finish.node.cachedPrepaintRange = PrepaintStateRange(
                    start: finish.startIndex, end: state.currentIndex)
                continue

            case .enter(let entryContext):
                context = entryContext
            }

            let node = context.node
            let parentOrigin = context.parentOrigin
            let inheritedClip = context.inheritedClip
            let inheritedTransform = context.inheritedTransform

            // Recorded, not descended into — and recorded before the depth cap
            // is consulted, because in the recursion this was the *parent's*
            // work, done without entering the child at all.
            if context.isDeferralCandidate, node.paintsInDeferredPhase {
                Self.appendDeferredSubtree(
                    into: &state,
                    child: node,
                    parentDispatchIndex: context.parentDispatchIndex ?? 0,
                    childOrigin: parentOrigin,
                    effectiveClip: inheritedClip,
                    effectiveOpacity: context.inheritedOpacity,
                    nodeInverseTransform: context.inheritedInverseTransform,
                    effectiveTransform: inheritedTransform,
                    effectiveColorEffects: context.inheritedColorEffects,
                    effectiveBlendMode: context.inheritedBlendMode
                )
                continue
            }

            let startIndex = state.currentIndex

            guard ViewNode.enterTraversal(atDepth: baseDepth + context.depth) else {
                node.cachedPrepaintKey = nil
                node.cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
                continue
            }

            if node.isHidden {
                node.cachedPrepaintKey = nil
                node.cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
                continue
            }

            let absoluteFrame = Rect(
                x: parentOrigin.x + node.resolvedFrame.origin.x,
                y: parentOrigin.y + node.resolvedFrame.origin.y,
                width: node.resolvedFrame.size.width,
                height: node.resolvedFrame.size.height
            )

            let geometry = Self.prepaintGeometry(
                of: absoluteFrame,
                transform: node.transform,
                inheritedTransform: inheritedTransform,
                inheritedInverseTransform: context.inheritedInverseTransform
            )
            let effectiveTransform = geometry.effectiveTransform
            let nodeInverseTransform = geometry.inverseTransform

            if !inheritedClip.allowsDrawing(geometry.paintFrame) {
                node.cachedPrepaintKey = nil
                node.cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
                continue
            }

            // One narrowing rule and one space, shared with the painter and
            // the frame path (`RuntimeClipShape.intersecting`). Prepaint
            // narrowed the *untransformed* frame while both paint paths
            // narrowed the transformed one, so a rotated `.clipped()`
            // container painted one region, accepted pointers in a second, and
            // handed its deferred overlays a third.
            var effectiveClip = inheritedClip
            if node.clipsToBounds {
                // R-ROT. Prepaint lowers the same placement the painter does,
                // so a rotated `.clipped()` container narrows to the *turned*
                // shape on both. Passing only `paintFrame` left interaction
                // testing the bounding box while the painter composited the
                // rotated one — a pointer accepted in a corner nothing was
                // drawn in.
                guard
                    let clipped = Self.narrowedClip(
                        inheritedClip, to: geometry.paintFrame, localFrame: absoluteFrame,
                        transform: effectiveTransform, radii: node.cornerRadii,
                        uniformRadius: node.cornerRadius)
                else {
                    node.cachedPrepaintKey = nil
                    node.cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: startIndex)
                    continue
                }
                effectiveClip = clipped
            }

            let effectiveOpacity = context.inheritedOpacity * Float(node.opacity)
            let effectiveColorEffects = context.inheritedColorEffects + node.colorEffects
            let effectiveBlendMode =
                node.blendMode == .normal ? context.inheritedBlendMode : node.blendMode
            // Keyed on the transformed frame, like the painter's: a replayed
            // subtree carries the inverse transform it was recorded with, and
            // an ancestor transform that moves an unclipped node leaves its
            // untransformed frame — and so the old key — unchanged.
            let cacheKey = node.paintCacheKey(
                paintFrame: geometry.paintFrame,
                effectiveTransform: effectiveTransform,
                effectiveClip: effectiveClip,
                effectiveOpacity: effectiveOpacity,
                effectiveBlendMode: effectiveBlendMode,
                colorEffects: effectiveColorEffects,
                displayScale: displayScale
            )

            if let previousState,
                !node.hasDirtySubtree,
                node.cachedPrepaintKey == cacheKey,
                let previousRange = node.cachedPrepaintRange
            {
                node.replayPrepaintState(
                    into: &state,
                    previousState: previousState,
                    startIndex: startIndex,
                    previousRange: previousRange,
                    parentDispatchIndex: context.parentDispatchIndex,
                    cacheKey: cacheKey
                )
                replayCount += 1
                continue
            }

            let dispatchIndex = state.dispatchNodes.count
            node.appendOwnPrepaintState(
                into: &state,
                dispatchIndex: dispatchIndex,
                parentDispatchIndex: context.parentDispatchIndex,
                absoluteFrame: absoluteFrame,
                effectiveClip: effectiveClip,
                nodeInverseTransform: nodeInverseTransform
            )

            let absoluteOrigin = Point(
                x: parentOrigin.x + node.resolvedFrame.origin.x,
                y: parentOrigin.y + node.resolvedFrame.origin.y
            )

            let childOrigin = Point(
                x: absoluteOrigin.x - (node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0),
                y: absoluteOrigin.y - (node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0)
            )

            traversal.append(
                .finish(
                    PrepaintFinishState(
                        node: node,
                        startIndex: startIndex,
                        cacheKey: cacheKey,
                        dispatchIndex: dispatchIndex,
                        absoluteFrame: absoluteFrame,
                        inheritedTransform: inheritedTransform,
                        centeredTransform: geometry.centeredTransform,
                        effectiveClip: effectiveClip,
                        effectiveOpacity: effectiveOpacity,
                        depth: context.depth
                    )
                )
            )

            // Reversed so the worklist pops them in paint order: deferral
            // priorities and dispatch indices are assigned in visit order, and
            // the painter reads both as given.
            for child in node.orderedChildrenForPaint().reversed() {
                traversal.append(
                    .enter(
                        PrepaintTraversalContext(
                            node: child,
                            parentOrigin: childOrigin,
                            inheritedClip: effectiveClip,
                            inheritedOpacity: effectiveOpacity,
                            parentDispatchIndex: dispatchIndex,
                            inheritedInverseTransform: nodeInverseTransform,
                            inheritedTransform: effectiveTransform,
                            inheritedColorEffects: effectiveColorEffects,
                            inheritedBlendMode: effectiveBlendMode,
                            depth: context.depth + 1,
                            isDeferralCandidate: true
                        )
                    )
                )
            }
        }
    }

    /// The transform algebra `ScenePainter.paintNode` derives inline, kept out
    /// of line here for the same reason `accumulatedPaintGeometry` is: three
    /// `concatenating` calls and an inversion are several hundred bytes of
    /// unoptimized temporaries, and prepaint is a recursion that pays for them
    /// at every level.
    @inline(never)
    fileprivate static func prepaintGeometry(
        of absoluteFrame: Rect,
        transform: Transform2D,
        inheritedTransform: Transform2D,
        inheritedInverseTransform: Transform2D?
    ) -> PrepaintGeometry {
        guard !transform.isIdentity else {
            return PrepaintGeometry(
                centeredTransform: .identity,
                effectiveTransform: inheritedTransform,
                paintFrame: absoluteFrame.applying(transform: inheritedTransform),
                inverseTransform: inheritedInverseTransform
            )
        }

        let screenFrame = absoluteFrame.applying(transform: inheritedTransform)
        let center = Point(x: screenFrame.midX, y: screenFrame.midY)
        let centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
            .concatenating(transform)
            .concatenating(.translation(x: center.x, y: center.y))
        // WS-19: ancestors first, then this node. See the note in
        // `ScenePainter.paintNode` — the centred transform is a screen-space
        // operator, so it composes after the map that produced the screen
        // space it is centred in.
        let effectiveTransform =
            inheritedTransform.isIdentity
            ? centeredTransform : inheritedTransform.concatenating(centeredTransform)

        let inverseTransform: Transform2D?
        if let inverse = centeredTransform.inverseOrNil() {
            // `(A·B)⁻¹ = B⁻¹·A⁻¹`: the inverse composes in the opposite order
            // to `effectiveTransform`, so a pointer is un-rotated by this node
            // before it is un-mapped by its ancestors.
            if let inheritedInverseTransform {
                inverseTransform = inverse.concatenating(inheritedInverseTransform)
            } else {
                inverseTransform = inverse
            }
        } else {
            inverseTransform = inheritedInverseTransform
        }

        return PrepaintGeometry(
            centeredTransform: centeredTransform,
            effectiveTransform: effectiveTransform,
            paintFrame: absoluteFrame.applying(transform: effectiveTransform),
            inverseTransform: inverseTransform
        )
    }

    /// The dispatch, interaction and focus records a node contributes for
    /// itself. Out of line: three record constructions the recursion would
    /// otherwise carry at every level.
    @inline(never)
    private func appendOwnPrepaintState(
        into state: inout RuntimePrepaintState,
        dispatchIndex: Int,
        parentDispatchIndex: Int?,
        absoluteFrame: Rect,
        effectiveClip: RuntimeClipShape?,
        nodeInverseTransform: Transform2D?
    ) {
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
                    clip: effectiveClip,
                    inverseTransform: nodeInverseTransform
                )
            )
        }

        if isFocusable {
            state.focusOrder.append(dispatchIndex)
        }
    }

    /// A child that paints in the deferred phase is recorded, not descended
    /// into. Out of line: the payload is nine inherited values, and building it
    /// inline charged the recursion for all of them.
    @inline(never)
    private static func appendDeferredSubtree(
        into state: inout RuntimePrepaintState,
        child: ViewNode,
        parentDispatchIndex: Int,
        childOrigin: Point,
        effectiveClip: RuntimeClipShape?,
        effectiveOpacity: Float,
        nodeInverseTransform: Transform2D?,
        effectiveTransform: Transform2D,
        effectiveColorEffects: [RetainedColorEffect],
        effectiveBlendMode: BlendMode
    ) {
        state.deferredSubtrees.append(
            DeferredSubtreeState(
                priority: state.nextDeferredPriority,
                parentDispatchIndex: parentDispatchIndex,
                payload: DeferredSubtreePayload(
                    node: child,
                    parentOrigin: childOrigin,
                    inheritedClip: effectiveClip,
                    inheritedOpacity: effectiveOpacity,
                    inheritedInverseTransform: nodeInverseTransform,
                    inheritedTransform: effectiveTransform,
                    inheritedColorEffects: effectiveColorEffects,
                    inheritedBlendMode: effectiveBlendMode
                )
            )
        )
        state.nextDeferredPriority += 1
    }

    /// Returned in painted space, in the same space as the `contentMask`: the
    /// painter draws this rect verbatim and `deferredDrawContains` tests a
    /// screen point against both, so a track in layout space under a transform
    /// would be drawn where the viewport is not and clipped by a clip it no
    /// longer overlaps. It is *measured* in layout space, because the fraction
    /// of the content that is visible is a layout-space ratio — see
    /// `scrollIndicatorTrack`.
    ///
    /// Out of line for the recursion's sake, like its neighbours.
    @inline(never)
    private func appendScrollIndicatorDeferredDraw(
        into state: inout RuntimePrepaintState,
        dispatchIndex: Int,
        absoluteFrame: Rect,
        inheritedTransform: Transform2D,
        centeredTransform: Transform2D,
        effectiveClip: RuntimeClipShape?,
        effectiveOpacity: Float
    ) {
        guard effectiveOpacity > 0,
            let track = scrollIndicatorTrack(
                in: absoluteFrame, inheritedTransform: inheritedTransform,
                centeredTransform: centeredTransform)
        else {
            return
        }

        let effectiveScrollIndicatorColor = scrollIndicatorColor.multipliedAlpha(by: effectiveOpacity)
        state.deferredDraws.append(
            DeferredDrawState(
                priority: state.nextDeferredPriority,
                parentDispatchIndex: dispatchIndex,
                contentMask: effectiveClip,
                payload: .scrollIndicator(
                    ScrollIndicatorDeferredDrawPayload(
                        node: self,
                        dispatchIndex: dispatchIndex,
                        track: track,
                        color: effectiveScrollIndicatorColor,
                        cornerRadius: min(track.indicatorRect.size.width, track.indicatorRect.size.height)
                            * 0.5
                    )
                ),
            )
        )
        state.nextDeferredPriority += 1
    }

    /// Copying a clean subtree's records forward instead of rebuilding them.
    /// Six array remaps with a closure each — the fattest block in the
    /// recursion, and out of line so it is charged to one leaf frame.
    @inline(never)
    private func replayPrepaintState(
        into state: inout RuntimePrepaintState,
        previousState: RuntimePrepaintState,
        startIndex: PrepaintStateIndex,
        previousRange: PrepaintStateRange,
        parentDispatchIndex: Int?,
        cacheKey: ViewPaintCacheKey
    ) {
        let dispatchDelta = startIndex.dispatchIndex - previousRange.start.dispatchIndex
        let interactionDelta = startIndex.interactionIndex - previousRange.start.interactionIndex
        let focusOrderDelta = startIndex.focusOrderIndex - previousRange.start.focusOrderIndex
        let deferredSubtreeDelta = startIndex.deferredSubtreeIndex - previousRange.start.deferredSubtreeIndex
        let deferredDrawDelta = startIndex.deferredDrawIndex - previousRange.start.deferredDrawIndex
        let deferredPriorityDelta = startIndex.deferredPriority - previousRange.start.deferredPriority

        let copiedDispatchNodes = previousState.dispatchNodes[
            previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex
        ]
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

        let copiedInteractions = previousState.interactions[
            previousRange.start.interactionIndex..<previousRange.end.interactionIndex
        ]
        .map { interaction in
            var nextInteraction = interaction
            nextInteraction.dispatchIndex += dispatchDelta
            return nextInteraction
        }
        state.interactions.append(contentsOf: copiedInteractions)

        let copiedFocusOrder = previousState.focusOrder[
            previousRange.start.focusOrderIndex..<previousRange.end.focusOrderIndex
        ]
        .map { $0 + dispatchDelta }
        state.focusOrder.append(contentsOf: copiedFocusOrder)

        let copiedDeferredSubtrees = previousState.deferredSubtrees[
            previousRange.start.deferredSubtreeIndex..<previousRange.end.deferredSubtreeIndex
        ]
        .map { deferredSubtree in
            var nextDeferredSubtree = deferredSubtree
            nextDeferredSubtree.priority += deferredPriorityDelta
            if previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex
                ~= deferredSubtree.parentDispatchIndex
            {
                nextDeferredSubtree.parentDispatchIndex += dispatchDelta
            } else if let parentDispatchIndex {
                nextDeferredSubtree.parentDispatchIndex = parentDispatchIndex
            }
            return nextDeferredSubtree
        }
        state.deferredSubtrees.append(contentsOf: copiedDeferredSubtrees)

        let copiedDeferredDraws = previousState.deferredDraws[
            previousRange.start.deferredDrawIndex..<previousRange.end.deferredDrawIndex
        ]
        .map { deferredDraw in
            var nextDeferredDraw = deferredDraw
            nextDeferredDraw.priority += deferredPriorityDelta
            if previousRange.start.dispatchIndex..<previousRange.end.dispatchIndex
                ~= deferredDraw.parentDispatchIndex
            {
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
            startIndex.deferredPriority
                + (previousRange.end.deferredPriority - previousRange.start.deferredPriority)
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
        cachedPrepaintRange = PrepaintStateRange(start: startIndex, end: state.currentIndex)
    }

    /// The clip a `clipsToBounds` node narrows to, with its rotation lowered.
    ///
    /// Out of line for the same reason `accumulatedPaintGeometry` is: a
    /// `PaintPlacement` is three geometry values plus the temporaries
    /// `lowering` builds to produce them, and a walk that visits every node
    /// should pay for that once, in a leaf frame, rather than at every level.
    fileprivate static func narrowedClip(
        _ inheritedClip: RuntimeClipShape?,
        to paintFrame: Rect,
        localFrame: Rect,
        transform: Transform2D,
        radii: RetainedCornerRadii?,
        uniformRadius: Double
    ) -> RuntimeClipShape? {
        let placement = PaintPlacement.lowering(localFrame, through: transform)
        return inheritedClip.narrowed(
            to: paintFrame, shape: placement.frame, radii: radii, uniformRadius: uniformRadius,
            rotation: placement.rotation, space: .painted)
    }

    /// A node's painted frame and the transform its children inherit — the
    /// same algebra `ScenePainter.paintNode` and `appendPrepaintState` derive
    /// (they also need the centred transform itself, for the pointer inverse
    /// and the scroll-indicator mapping; the agreement between all three is
    /// what `ClipAbstractionTests` pins).
    ///
    /// Out of line on purpose: in an unoptimized build the temporaries of
    /// three `concatenating` calls are several hundred bytes, and the frame
    /// path's walk should carry only the two values it actually uses.
    fileprivate static func accumulatedPaintGeometry(
        of frame: Rect,
        transform: Transform2D,
        inheritedTransform: Transform2D
    ) -> (paintFrame: Rect, effectiveTransform: Transform2D) {
        let screenFrame = inheritedTransform.isIdentity ? frame : frame.applying(transform: inheritedTransform)
        guard !transform.isIdentity else {
            return (screenFrame, inheritedTransform)
        }

        let center = Point(x: screenFrame.midX, y: screenFrame.midY)
        let centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
            .concatenating(transform)
            .concatenating(.translation(x: center.x, y: center.y))
        // WS-19: ancestors first, then this node — the same order the painter
        // and prepaint compose in, for the same reason (the centred transform
        // is built around a screen-space centre, so it applies to screen
        // space). `paintFrame` is then the single application of the result
        // rather than a bounding box of a bounding box.
        let effectiveTransform =
            inheritedTransform.isIdentity
            ? centeredTransform : inheritedTransform.concatenating(centeredTransform)
        return (frame.applying(transform: effectiveTransform), effectiveTransform)
    }

    /// One node's entry in the frame path's explicit traversal.
    private struct FrameTraversalContext {
        let node: ViewNode
        let parentOrigin: Point
        let inheritedClip: RuntimeClipShape?
        let inheritedOpacity: Float
        let inheritedBlendMode: BlendMode
        let inheritedTransform: Transform2D
        /// Nesting below the node the traversal was entered at. The cap is
        /// applied to `baseDepth + depth`, so a subtree resumed from a deferred
        /// draw is bounded from where it really sits in the tree.
        let depth: Int
    }

    /// The post-children half of a node's visit: the command range it owns is
    /// only known once its descendants have appended theirs.
    private struct FrameNodeFinishState {
        let node: ViewNode
        let startIndex: Int
        let cacheKey: ViewPaintCacheKey
        let depth: Int
    }

    private enum FrameTraversalStep {
        case enter(FrameTraversalContext)
        case finish(FrameNodeFinishState)
    }

    /// The frame path's command walk, as an explicit worklist rather than a
    /// recursion.
    ///
    /// This was the deepest and fattest recursion in the runtime: an
    /// unoptimized build gave it a 23 KB frame, so a tree 43 levels deep — the
    /// demo's deepest screen reaches 42 — exhausted the main thread's 1 MB
    /// stack and took the process out with an access violation, no assertion,
    /// no log. `ScenePainter.paintNode` was de-recursed for exactly this
    /// reason and this is the same shape: `.enter` does everything a node can
    /// do before its children, `.finish` does the one thing it can only do
    /// after them, and both live on the heap. Depth now costs an array element,
    /// not a stack frame, so `maximumTraversalDepth` is a policy about how deep
    /// a tree may be rather than a bet on how big a frame is.
    fileprivate func appendCommands(
        into commands: inout [RenderCommand],
        parentOrigin: Point,
        inheritedClip: RuntimeClipShape?,
        inheritedOpacity: Float = 1,
        inheritedBlendMode: BlendMode = .normal,
        inheritedTransform: Transform2D = .identity,
        previousRenderedFrame: RenderFrame? = nil,
        displayScale: Double = 1,
        replayCount: inout Int
    ) {
        // The shared depth counter is a stack-depth proxy for the recursions
        // that are still recursions; this traversal borrows it so that nesting
        // is accounted across the boundary in both directions.
        let baseDepth = ViewNode.traversalDepth
        defer { ViewNode.traversalDepth = baseDepth }

        var traversal: [FrameTraversalStep] = [
            .enter(
                FrameTraversalContext(
                    node: self,
                    parentOrigin: parentOrigin,
                    inheritedClip: inheritedClip,
                    inheritedOpacity: inheritedOpacity,
                    inheritedBlendMode: inheritedBlendMode,
                    inheritedTransform: inheritedTransform,
                    depth: 0
                )
            )
        ]

        while let traversalStep = traversal.popLast() {
            let context: FrameTraversalContext
            switch traversalStep {
            case .finish(let state):
                ViewNode.traversalDepth = baseDepth + state.depth + 1
                state.node.cachedFrameKey = state.cacheKey
                state.node.cachedFrameCommandRange = state.startIndex..<commands.count
                state.node.markSubtreeRendered()
                continue

            case .enter(let entryContext):
                context = entryContext
            }

            let node = context.node
            let parentOrigin = context.parentOrigin
            let inheritedClip = context.inheritedClip
            let inheritedTransform = context.inheritedTransform
            let startIndex = commands.count

            guard ViewNode.enterTraversal(atDepth: baseDepth + context.depth) else {
                node.cachedFrameKey = nil
                node.cachedFrameCommandRange = startIndex..<startIndex
                node.markSubtreeRendered()
                continue
            }

            if node.isHidden {
                node.cachedFrameKey = nil
                node.cachedFrameCommandRange = startIndex..<startIndex
                node.markSubtreeRendered()
                continue
            }

            let absoluteFrame = Rect(
                x: parentOrigin.x + node.resolvedFrame.origin.x,
                y: parentOrigin.y + node.resolvedFrame.origin.y,
                width: node.resolvedFrame.size.width,
                height: node.resolvedFrame.size.height
            )

            // `paintFrame` is what this path draws *and* what it narrows the
            // clip by, so it has to be the accumulated screen frame at every
            // depth. Applying only the node's own transform left a child of a
            // rotated container drawing at its transformed frame while being
            // gated against a clip its untransformed frame was compared to —
            // the mixed-space comparison one level down, and one the
            // `RuntimeClipShape.Space` assertion cannot see because both sides
            // say `.painted`.
            let (paintFrame, effectiveTransform) = Self.accumulatedPaintGeometry(
                of: absoluteFrame, transform: node.transform, inheritedTransform: inheritedTransform)

            // Gap/Fix: Occlusion culling — skip the entire node early if it is
            // fully outside the inherited clip bounds (before allocating any
            // command structs). Uses the same subtree test as the scene path,
            // so a zero-extent container inside the clip keeps painting its
            // overflowing children on both paths instead of only on one.
            if !inheritedClip.allowsSubtreeTraversal(bounds: paintFrame) {
                node.cachedFrameKey = nil
                node.cachedFrameCommandRange = startIndex..<startIndex
                node.markSubtreeRendered()
                continue
            }

            node.fireFrameLifecycleCallbacks(absoluteFrame: absoluteFrame)

            // The frame path emits its geometry at `paintFrame` — the node's
            // own transform applied — so it has to clip there too. Clipping the
            // untransformed `absoluteFrame` while drawing the transformed one
            // made a rotated `.clipped()` container chop its content diagonally
            // here and bleed past the visible edge on the scene path: two
            // different regions for the same tree, swapped silently by
            // `fallbackToFrameRenderer`.
            var effectiveClip = inheritedClip
            if node.clipsToBounds {
                guard
                    let clipped = inheritedClip.narrowed(
                        to: paintFrame, radii: node.cornerRadii, uniformRadius: node.cornerRadius,
                        space: .painted)
                else {
                    node.cachedFrameKey = nil
                    node.cachedFrameCommandRange = startIndex..<startIndex
                    node.markSubtreeRendered()
                    continue
                }
                effectiveClip = clipped
            }
            let effectiveClipRect = effectiveClip?.rect

            // Gap/Fix: Opacity group compositing — when a view has opacity < 1
            // AND has children, the correct result requires compositing into an
            // offscreen texture first. Without that, each child is blended
            // individually, which causes overlapping children to double-blend.
            // TODO: Opacity < 1 with overlapping children double-blends. Requires render-to-texture for correct compositing.
            // GPUI/Zed instead carries opacity as an inherited paint scalar.
            let effectiveOpacity = context.inheritedOpacity * Float(node.opacity)
            let effectiveBlendMode =
                node.blendMode == .normal ? context.inheritedBlendMode : node.blendMode
            let cacheKey = node.paintCacheKey(
                paintFrame: paintFrame,
                effectiveTransform: effectiveTransform,
                effectiveClip: effectiveClip,
                effectiveOpacity: effectiveOpacity,
                effectiveBlendMode: effectiveBlendMode,
                colorEffects: node.colorEffects,
                displayScale: displayScale
            )
            guard effectiveOpacity > 0 else {
                node.cachedFrameKey = cacheKey
                node.cachedFrameCommandRange = startIndex..<startIndex
                node.markSubtreeRendered()
                continue
            }

            if let previousRenderedFrame,
                !node.hasDirtySubtree,
                node.cachedFrameKey == cacheKey,
                let previousRange = node.cachedFrameCommandRange
            {
                commands.append(contentsOf: previousRenderedFrame.commands[previousRange])
                let delta = startIndex - previousRange.lowerBound
                node.shiftCachedFrameRangesRecursively(by: delta)
                node.cachedFrameKey = cacheKey
                node.cachedFrameCommandRange = startIndex..<commands.count
                node.markSubtreeRendered()
                replayCount += 1
                continue
            }

            let absoluteOrigin = Point(
                x: parentOrigin.x + node.resolvedFrame.origin.x,
                y: parentOrigin.y + node.resolvedFrame.origin.y
            )

            let childOrigin = Point(
                x: absoluteOrigin.x - (node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0),
                y: absoluteOrigin.y - (node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0)
            )

            node.appendOwnCommands(
                into: &commands,
                paintFrame: paintFrame,
                inheritedClip: inheritedClip,
                effectiveClip: effectiveClip,
                effectiveClipRect: effectiveClipRect,
                effectiveOpacity: effectiveOpacity,
                effectiveBlendMode: effectiveBlendMode,
                displayScale: displayScale
            )

            traversal.append(
                .finish(
                    FrameNodeFinishState(
                        node: node,
                        startIndex: startIndex,
                        cacheKey: cacheKey,
                        depth: context.depth
                    )
                )
            )

            // Pushed in reverse so the worklist pops them in paint order: the
            // command stream's order is the presentation order, exactly as it
            // was when this walk recursed.
            for child in node.orderedChildrenForPaint().reversed() {
                guard !child.paintsInDeferredPhase else {
                    continue
                }
                traversal.append(
                    .enter(
                        FrameTraversalContext(
                            node: child,
                            parentOrigin: childOrigin,
                            inheritedClip: effectiveClip,
                            inheritedOpacity: effectiveOpacity,
                            inheritedBlendMode: effectiveBlendMode,
                            inheritedTransform: effectiveTransform,
                            depth: context.depth + 1
                        )
                    )
                )
            }
        }
    }

    /// Gap/Fix: Lifecycle — fire onAppear the first time a node is rendered,
    /// and onSizeChange when its resolved frame moved. Removal overlays are
    /// skipped: they have already appeared, and onDisappear waits for the
    /// transition to finish.
    private func fireFrameLifecycleCallbacks(absoluteFrame: Rect) {
        guard !isRemovalOverlay else { return }
        if !hasAppeared {
            hasAppeared = true
            isInitialBuildNode = false
            onAppear?()
            onAppearWithNode?(self)
            if scrollIndicatorsFlashOnAppear {
                runtime?.flashScrollIndicator(for: self)
            }
            previousFrame = absoluteFrame
        }
        if let prev = previousFrame, prev != absoluteFrame {
            onSizeChange?(absoluteFrame)
        }
        previousFrame = absoluteFrame
    }

    /// The replay key both walks mint, out of line so each pays for one key
    /// rather than for the twenty temporaries an unoptimized build
    /// materializes to build it.
    ///
    /// The frame path keys on the node's own colour effects and prepaint on
    /// the accumulated ones, because that is what each of them applies; the
    /// rest of the key is identical by construction.
    @inline(never)
    private func paintCacheKey(
        paintFrame: Rect,
        effectiveTransform: Transform2D,
        effectiveClip: RuntimeClipShape?,
        effectiveOpacity: Float,
        effectiveBlendMode: BlendMode,
        colorEffects: [RetainedColorEffect],
        displayScale: Double
    ) -> ViewPaintCacheKey {
        ViewPaintCacheKey(
            bounds: paintFrame,
            transform: effectiveTransform.matrix,
            contentMask: effectiveClip,
            opacity: effectiveOpacity,
            blurRadius: blurRadius,
            blurOpaque: blurOpaque,
            contentBlurRadius: contentBlurRadius,
            contentBlurOpaque: contentBlurOpaque,
            blendMode: effectiveBlendMode,
            isCompositingGroup: isCompositingGroup,
            drawingGroup: drawingGroup,
            colorEffects: colorEffects,
            visualEffects: visualEffects,
            viewMask: viewMask,
            displayScale: displayScale,
            isHovered: isHovered,
            hoverEffect: resolvedActiveHoverEffect,
            isFocused: isFocused,
            isFocusEffectDisabled: isFocusEffectDisabled
        )
    }

    /// Everything a node draws for *itself* on the frame path: decoration,
    /// background, bitmap, text, canvas, and the blend-mode lowering over the
    /// commands all of that produced.
    ///
    /// Out of line, and deliberately never inlined back. In an unoptimized
    /// build every `FillRectCommand` / `RenderCommand` temporary in this block
    /// claims its own stack slot — some thirty of them, tens of kilobytes in
    /// total — and this was half of why `appendCommands` had a 24 KB frame
    /// while it was still a recursion, enough to put a 43-level tree over the
    /// main thread's 1 MB stack. The walk is a worklist now and this stays out
    /// of line anyway: one leaf frame per node visited, popped before the next
    /// one is. `TraversalStackHeadroomTests` pins the result.
    @inline(never)
    private func appendOwnCommands(
        into commands: inout [RenderCommand],
        paintFrame: Rect,
        inheritedClip: RuntimeClipShape?,
        effectiveClip: RuntimeClipShape?,
        effectiveClipRect: Rect?,
        effectiveOpacity: Float,
        effectiveBlendMode: BlendMode,
        displayScale: Double
    ) {
        let directCommandStartIndex = commands.count

        // `FillRectCommand` only carries a uniform radius, so the frame path
        // degrades per-corner radii the same way ScenePainter degrades them for
        // its uniform-radius consumers: to `maxRadius`. Reading `cornerRadius`
        // alone (typically 0 on a per-corner node) turned a rounded segmented
        // control square the moment the host fell back to this renderer.
        let uniformCornerRadius = cornerRadii?.maxRadius ?? cornerRadius

        // Same rule as ScenePainter: a zero-extent node paints none of its own
        // decoration (the outset shadow and outline would otherwise draw a small
        // square around a collapsed node) while its children still paint.
        let hasPaintableExtent = paintFrame.size.width > 0 && paintFrame.size.height > 0

        if hasPaintableExtent,
            let hoverShadow = hoverEffectShadowCommand(
                for: paintFrame,
                inheritedClip: inheritedClip?.rect,
                opacity: effectiveOpacity
            )
        {
            commands.append(.fillRect(hoverShadow))
        }

        let effectiveShadowColor = shadowColor.multipliedAlpha(by: effectiveOpacity)
        if hasPaintableExtent, effectiveShadowColor.alpha > 0 {
            let shadowRect =
                paintFrame
                .outset(by: max(0, shadowSpread))
                .offsetBy(dx: shadowOffset.x, dy: shadowOffset.y)

            if baseClipAllowsDrawing(baseClip: inheritedClip?.rect, rect: shadowRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: shadowRect,
                            color: effectiveShadowColor,
                            cornerRadius: uniformCornerRadius + max(0, shadowSpread),
                            clipRect: inheritedClip?.rect
                        )
                    )
                )
            }
        }

        if hasPaintableExtent {
            for focusEffect in focusEffectCommands(
                for: paintFrame,
                inheritedClip: inheritedClip?.rect,
                opacity: effectiveOpacity
            ) {
                commands.append(.fillRect(focusEffect))
            }
        }

        let effectiveOutlineColor = outlineColor.multipliedAlpha(by: effectiveOpacity)
        if hasPaintableExtent, effectiveOutlineColor.alpha > 0, outlineWidth > 0 {
            let outlineRect = paintFrame.outset(by: outlineWidth)
            if baseClipAllowsDrawing(baseClip: inheritedClip?.rect, rect: outlineRect) {
                // A ring, matching `ScenePainter.appendFocusRing`. Filling the
                // whole outset rect only reads as a ring while the border and
                // background painted over it are opaque; the macOS palettes
                // are translucent, so the accent used to show through the body
                // and repaint a focused bordered control accent-blue.
                appendFocusRingCommands(
                    into: &commands,
                    paintFrame: paintFrame,
                    outlineWidth: outlineWidth,
                    color: effectiveOutlineColor,
                    uniformCornerRadius: uniformCornerRadius,
                    clipRect: inheritedClip?.rect
                )
            }
        }

        let effectiveBorderGradient = borderGradient?.withMultipliedOpacity(Double(effectiveOpacity))
        let effectiveBorderColor =
            borderGradient?.startColor
            ?? borderColor.multipliedAlpha(by: effectiveOpacity)
        // Gated on `paintFrame`, not `absoluteFrame`: the border below is drawn
        // at `paintFrame` and the clip was narrowed there, so testing the
        // untransformed frame dropped the border of a translated view whose
        // painted frame is inside the clip — on this path only, while
        // `ScenePainter` drew it.
        if hasPaintableExtent,
            effectiveBorderColor.alpha > 0 || Self.hasVisibleGradient(effectiveBorderGradient),
            borderWidth > 0, backgroundPath == nil,
            baseClipAllowsDrawing(baseClip: effectiveClip, rect: paintFrame)
        {
            if let borderSegments = BorderSegments.dashedSegments(
                frame: paintFrame,
                width: borderWidth,
                cornerRadius: uniformCornerRadius,
                strokeStyle: borderStrokeStyle
            ) {
                for segment in borderSegments where baseClipAllowsDrawing(baseClip: effectiveClip, rect: segment.rect) {
                    // Each dash is its own quad, so the ring's gradient has to
                    // be re-sampled onto the dash rather than replayed inside
                    // it — same reason, and same helper, as the scene path's
                    // ring segments.
                    let stops = BorderSegments.segmentStops(
                        gradient: effectiveBorderGradient,
                        start: effectiveBorderColor,
                        segment: segment.rect,
                        in: paintFrame
                    )
                    commands.append(
                        .fillRect(
                            FillRectCommand(
                                rect: segment.rect,
                                color: stops.color,
                                cornerRadius: segment.cornerRadius,
                                clipRect: effectiveClipRect,
                                gradient: stops.gradient
                            )
                        )
                    )
                }
            } else {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: paintFrame,
                            color: effectiveBorderColor,
                            cornerRadius: uniformCornerRadius,
                            clipRect: effectiveClipRect,
                            gradient: effectiveBorderGradient
                        )
                    )
                )
            }
        }

        let fillRect = borderWidth > 0 ? paintFrame.inset(by: borderWidth) : paintFrame
        let fillCornerRadius = max(0, uniformCornerRadius - borderWidth)

        let resolvedBackgroundGradient = backgroundGradient?.withMultipliedOpacity(Double(effectiveOpacity))
        let resolvedBackgroundColor =
            backgroundColor?.multipliedAlpha(by: effectiveOpacity)
            ?? backgroundGradient?.startColor
        if let resolvedBackgroundColor,
            resolvedBackgroundColor.alpha > 0 || Self.hasVisibleGradient(resolvedBackgroundGradient),
            fillRect.size.width > 0,
            fillRect.size.height > 0, backgroundPath == nil
        {
            if baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
                commands.append(
                    .fillRect(
                        FillRectCommand(
                            rect: fillRect,
                            color: resolvedBackgroundColor,
                            cornerRadius: fillCornerRadius,
                            clipRect: effectiveClipRect,
                            gradient: resolvedBackgroundGradient
                        )
                    )
                )
            }
        }

        if let path = backgroundPath, fillRect.size.width > 0, fillRect.size.height > 0,
            baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect)
        {
            let scaledPath = path.scaled(to: fillRect)
            if let resolvedBackgroundColor, resolvedBackgroundColor.alpha > 0 {
                commands.append(
                    .fillPath(
                        FillPathCommand(
                            path: scaledPath,
                            color: resolvedBackgroundColor,
                            clipRect: effectiveClipRect
                        )
                    )
                )
            }
            let effectiveStrokeColor = borderColor.multipliedAlpha(by: effectiveOpacity)
            if effectiveStrokeColor.alpha > 0, borderWidth > 0 {
                commands.append(
                    .strokePath(
                        StrokePathCommand(
                            path: scaledPath,
                            color: effectiveStrokeColor,
                            // The node's own stroke style, not a fresh one:
                            // rebuilding it from `borderWidth` dropped the
                            // cap and join the shape asked for, so the frame
                            // path and the scene path drew different shapes.
                            style: StrokeStyle(
                                lineWidth: borderWidth,
                                lineCap: borderStrokeStyle?.lineCap ?? .butt,
                                lineJoin: borderStrokeStyle?.lineJoin ?? .miter,
                                miterLimit: borderStrokeStyle?.miterLimit ?? 10),
                            clipRect: effectiveClipRect
                        )
                    )
                )
            }
        }

        if let hoverOverlay = hoverEffectOverlayCommand(
            for: fillRect,
            cornerRadius: fillCornerRadius,
            clipRect: effectiveClipRect,
            opacity: effectiveOpacity
        ) {
            commands.append(.fillRect(hoverOverlay))
        }

        let drawsRedactionPlaceholder =
            redactionReasons.contains(.placeholder)
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
                        clipRect: effectiveClipRect
                    )
                )
            )
        } else if let bitmapSurface, fillRect.size.width > 0, fillRect.size.height > 0,
            baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect)
        {
            commands.append(
                .drawBitmap(
                    DrawBitmapCommand(
                        rect: fillRect,
                        bitmap: bitmapSurface,
                        opacity: effectiveOpacity,
                        clipRect: effectiveClipRect
                    )
                )
            )
        }

        if !drawsRedactionPlaceholder, let text, !text.isEmpty,
            baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect)
        {
            let effectiveTextStyle = textStyle.multipliedOpacity(by: effectiveOpacity)
            if !NativeTextRenderer.appendCommands(
                for: text, in: fillRect, style: effectiveTextStyle, scaleFactor: displayScale,
                clipRect: effectiveClipRect, into: &commands)
            {
                PixelFont.appendCommands(
                    for: text,
                    in: fillRect,
                    style: effectiveTextStyle,
                    clipRect: effectiveClipRect,
                    into: &commands
                )
            }
        }

        // Canvas custom drawing — evaluate the renderer closure and emit commands.
        if let canvasDraw, fillRect.size.width > 0, fillRect.size.height > 0,
            baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect)
        {
            var context = CanvasGraphicsContext()
            canvasDraw(&context, fillRect.size)
            context.appendCommands(
                into: &commands,
                // The canvas closure draws in a space `fillRect.size` wide, so
                // its origin is `fillRect`'s — the painted origin, inset by
                // the border. `absoluteOrigin` is the *layout* origin and
                // carries neither the accumulated transform nor the border
                // inset, so a bordered or transformed canvas drew offset from
                // where the scene path put it.
                origin: fillRect.origin,
                clipRect: effectiveClipRect,
                opacity: effectiveOpacity,
                displayScale: displayScale
            )
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
        // Blend modes are carried on the frame commands, never interpreted —
        // the same decision the painter makes for `QuadPrimitive.blendMode`.
        // Every presenter composites source-over (the fallback renderer owns
        // exactly one `ID3D11BlendState`, `GPUISceneBridge` forwards the field
        // onto the quad without reading it, and the CPU rasterizer matches),
        // so a presenter swap cannot change how `.blendMode(.multiply)` looks.
        // Dropping the lowering instead would make the decision irreversible.
        // See `CPUGPUBlendModeContractTests`.
        if effectiveBlendMode != .normal {
            for index in directCommandStartIndex..<commands.count {
                commands[index].applyBlendMode(effectiveBlendMode)
            }
        }
    }

    /// A transparent first stop does not make the rest of a gradient
    /// invisible. Frame-path culling must inspect the same authored ramp the
    /// scene painter lowers, including visible middle stops.
    private static func hasVisibleGradient(_ gradient: GradientType?) -> Bool {
        guard let gradient else {
            return false
        }

        let stops: [GradientStop]
        switch gradient {
        case .linear(let linear):
            stops = linear.stops
        case .radial(let radial):
            stops = radial.stops
        case .conic(let conic):
            stops = conic.stops
        }

        return stops.contains { stop in
            stop.color.alpha.isFinite && stop.color.alpha > 0
        }
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
        let shadowRect =
            absoluteFrame
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

    /// The 2pt focus halo, as a RING.
    ///
    /// It used to be one `fillRect` covering `frame.outset(by: 2)` — a slab
    /// under the control, relying on the control's own border and background
    /// to cover everything but the 2pt margin. Those are translucent in the
    /// macOS palettes (`white(0.15)`-class fills), so the halo showed through
    /// the body and repainted a focused bordered control accent-blue, which
    /// on macOS means a *different* control: the prominent/default button.
    /// Emitted as an annulus, it can only ever occupy the margin.
    func focusEffectCommands(
        for absoluteFrame: Rect,
        inheritedClip: Rect?,
        opacity: Float
    ) -> [FillRectCommand] {
        guard isFocused, isFocusable, !isFocusEffectDisabled else {
            return []
        }
        // One ring, one owner. A node that carries its own focus ring — every
        // `Controls.button`, every text field — was getting two: this 2pt
        // hardcoded `Color(0.25, 0.55, 1, 0.75)` halo, which knows nothing
        // about the appearance palette and nothing about the animation clock,
        // painted at full strength on the frame focus arrived, and *behind* it
        // the control's own 4pt palette ring fading in over 0.18s. A scanline
        // through a focused bordered button read two 2px bands of different
        // blue (light: 106,173,246 beside 47,140,252), and mid-fade the outer
        // band was still grey while the inner one was already solid.
        //
        // The survivor is the control's own ring: it is appearance-resolved,
        // it is animated on the injected clock, and its width is the pinned
        // `MacOSControlMetrics.FocusRing.strokeWidth`. This one stays only as
        // the fallback for a focusable node that paints no ring of its own.
        guard interactionSurface?.focusRingColor == nil, outlineWidth <= 0 else {
            return []
        }

        let width = 2.0
        let ringRect = absoluteFrame.outset(by: width)
        guard ringRect.size.width > 0, ringRect.size.height > 0 else {
            return []
        }
        guard baseClipAllowsDrawing(baseClip: inheritedClip, rect: ringRect) else {
            return []
        }

        let color = Color(red: 0.25, green: 0.55, blue: 1, alpha: 0.75).multipliedAlpha(by: opacity)
        guard color.alpha > 0 else {
            return []
        }

        return focusRingFillCommands(
            ringFrame: ringRect,
            width: width,
            color: color,
            outerCornerRadius: effectCornerRadius(
                for: absoluteFrame, kinds: .focusEffect, fallback: cornerRadius) + width,
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

    private func invalidateRuntime(_ flags: DirtyFlags = .all) {
        markDirty(flags)
        runtime?.invalidate(flags, from: self)
    }

    var hasDirtySubtree: Bool {
        !subtreeDirtyFlags.isEmpty
    }

    /// Drops the cached compositing-group bitmap. Called when the node paints
    /// without a group buffer (the modifier was removed, the group fell back to
    /// inline painting, or it lost its children), so a buffer that can be as
    /// large as `maxCompositingGroupPixels` does not outlive its use.
    func releaseCompositingGroupCache() {
        guard cachedCompositingGroupBitmap != nil || cachedCompositingGroupKey != nil else { return }
        cachedCompositingGroupBitmap = nil
        cachedCompositingGroupKey = nil
        cachedCompositingGroupAtlasGeneration = nil
    }

    func markSubtreeRendered() {
        subtreeDirtyFlags = []
    }

    /// Clears the deferred-layout mark and, if it was set, the cached layout
    /// key with it, so the caller's `layoutSubtree` cannot take its
    /// early-return path over a subtree that was never laid out. Returns
    /// whether the node had been deferred.
    fileprivate func resumeVirtualizedLayout() -> Bool {
        guard isLayoutDeferredByVirtualization else { return false }
        isLayoutDeferredByVirtualization = false
        cachedLayoutKey = nil
        return true
    }

    fileprivate func markDirty(_ flags: DirtyFlags) {
        var currentNode: ViewNode? = self
        while let node = currentNode {
            node.subtreeDirtyFlags.insert(flags)
            currentNode = node.parent
        }
    }

    func shiftCachedFrameRangesRecursively(by delta: Int) {
        guard ViewNode.enterTraversal() else { return }
        defer { ViewNode.leaveTraversal() }

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
        guard ViewNode.enterTraversal() else { return }
        defer { ViewNode.leaveTraversal() }

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
        guard ViewNode.enterTraversal() else { return }
        defer { ViewNode.leaveTraversal() }

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

    /// Intrinsic measurement — the one traversal in the runtime that is still
    /// a recursion, and so the one that has to stay narrow.
    ///
    /// Layout and both paint walks are worklists; this one returns a value up
    /// the tree, which a worklist can only express by threading results
    /// through the node cache. Instead it is kept to a single small frame per
    /// level: deciding *what* to measure and folding the children's sizes back
    /// both happen out of line, so all that is live while the walk descends is
    /// the plan, the sizes gathered so far, and the loop. `-Onone` frames are
    /// what matter here — `TraversalStackHeadroomTests` measures the result at
    /// `maximumTraversalDepth`.
    fileprivate func sizeThatFits(in constraints: LayoutConstraints) -> Size {
        guard ViewNode.enterTraversal() else { return .zero }
        defer { ViewNode.leaveTraversal() }

        var plan = MeasurementPlan()
        if let cached = beginMeasurement(constraints, into: &plan) {
            return cached
        }

        var childSizes: [Size] = []
        childSizes.reserveCapacity(children.count)
        for child in children where !child.isHidden {
            childSizes.append(
                child.sizeThatFits(
                    in: plan.measuresChildrenIndividually
                        ? absoluteChildConstraints(for: child, in: plan.effectiveConstraints)
                        : plan.childConstraints))
        }

        return finishMeasurement(plan: plan, childSizes: childSizes)
    }

    /// The cache probe and everything a node can decide before it measures a
    /// single child. Returns the cached size when this measurement is already
    /// known, in which case `plan` is not used.
    @inline(never)
    private func beginMeasurement(
        _ constraints: LayoutConstraints,
        into plan: inout MeasurementPlan
    ) -> Size? {
        let displayScale = runtime?.displayScale ?? 1.0
        let effectiveConstraints = applyingLayoutConstraints(to: constraints)
        let cacheKey = ViewMeasureCacheKey(constraints: effectiveConstraints, displayScale: displayScale)
        let layoutDirtyFlags = subtreeDirtyFlags.intersection([.layout, .children])
        if layoutDirtyFlags.isEmpty, cachedMeasureKey == cacheKey, let cachedMeasuredSize {
            runtime?.recordMeasureReuse()
            return cachedMeasuredSize
        }

        plan.effectiveConstraints = effectiveConstraints
        plan.cacheKey = cacheKey
        plan.contentSize = bitmapContentSize() ?? textContentSize(in: effectiveConstraints) ?? .zero

        switch layoutMode {
        case .absolute:
            // Every child gets what is left of the container from its own
            // origin, so this is the one mode whose proposal is per child.
            plan.measuresChildrenIndividually = true
        case .stack(let stackLayout), .lazyStack(let stackLayout):
            plan.childConstraints = stackChildConstraints(
                for: insetConstraints(effectiveConstraints, by: stackLayout.padding),
                axis: stackLayout.axis)
        case .flex:
            plan.childConstraints = .unconstrained
        }
        return nil
    }

    @inline(never)
    private func absoluteChildConstraints(
        for child: ViewNode,
        in effectiveConstraints: LayoutConstraints
    ) -> LayoutConstraints {
        LayoutConstraints(
            maxWidth: remainingConstraintExtent(effectiveConstraints.maxWidth, offset: child.frame.origin.x),
            maxHeight: remainingConstraintExtent(effectiveConstraints.maxHeight, offset: child.frame.origin.y)
        )
    }

    /// Folds the children's measured sizes into this node's own size, applies
    /// its explicit dimensions, and caches the answer.
    @inline(never)
    private func finishMeasurement(plan: MeasurementPlan, childSizes: [Size]) -> Size {
        // Before this node answers for itself: the children have measured, so
        // their own inherited greed is this pass's, and folding it in here is
        // what carries a `Spacer` up out of the row it sits in.
        updateInheritedStackFillAxes()

        let measuredSize: Size
        switch layoutMode {
        case .absolute:
            measuredSize = absoluteMeasuredSize(contentSize: plan.contentSize, childSizes: childSizes)
        case .stack(let stackLayout), .lazyStack(let stackLayout):
            measuredSize = Self.stackMeasuredSize(of: childSizes, stackLayout: stackLayout)
        case .flex(let flexStyle):
            measuredSize = Self.flexMeasuredSize(of: childSizes, flexStyle: flexStyle)
        }

        let resolvedSize = applyingExplicitDimensions(
            to: measuredSize, constraints: plan.effectiveConstraints)
        cachedMeasureKey = plan.cacheKey
        cachedMeasuredSize = resolvedSize
        return resolvedSize
    }

    @inline(never)
    private func absoluteMeasuredSize(contentSize: Size, childSizes: [Size]) -> Size {
        var maxChildX = contentSize.width
        var maxChildY = contentSize.height

        var index = 0
        for child in children where !child.isHidden {
            let childSize = childSizes[index]
            index += 1
            let resolvedWidth = child.explicitWidth ?? childSize.width
            let resolvedHeight = child.explicitHeight ?? childSize.height
            maxChildX = max(maxChildX, child.frame.origin.x + resolvedWidth)
            maxChildY = max(maxChildY, child.frame.origin.y + resolvedHeight)
        }

        return Size(width: maxChildX, height: maxChildY)
    }

    /// The arithmetic a measured stack does over its children's sizes. Out of
    /// line so the recursion above carries the array and not the six reduce /
    /// map temporaries that fold it.
    @inline(never)
    private static func stackMeasuredSize(
        of childSizes: [Size],
        stackLayout: StackLayout
    ) -> Size {
        let spacingTotal = stackLayoutSpacingTotal(
            count: childSizes.count, spacing: stackLayout.spacing)
        let mainExtent =
            childSizes.reduce(0.0) { partialResult, size in
                partialResult + (stackLayout.axis == .vertical ? size.height : size.width)
            } + spacingTotal + stackMainPadding(for: stackLayout)
        let crossExtent =
            (childSizes.map { size in
                stackLayout.axis == .vertical ? size.width : size.height
            }.max() ?? 0) + stackCrossPadding(for: stackLayout)

        return Size(
            width: stackLayout.axis == .vertical ? crossExtent : mainExtent,
            height: stackLayout.axis == .vertical ? mainExtent : crossExtent
        )
    }

    /// The flex equivalent of `stackMeasuredSize`, and out of line for the
    /// same reason.
    @inline(never)
    private static func flexMeasuredSize(of childSizes: [Size], flexStyle: FlexStyle) -> Size {
        let isRow = flexStyle.direction == .row || flexStyle.direction == .rowReverse
        let gapTotal = childSizes.count > 1 ? flexStyle.gap * Double(childSizes.count - 1) : 0

        let mainExtent =
            childSizes.reduce(0.0) { partialResult, size in
                partialResult + (isRow ? size.width : size.height)
            } + gapTotal
            + (isRow
                ? flexStyle.padding.leading + flexStyle.padding.trailing
                : flexStyle.padding.top + flexStyle.padding.bottom)

        let crossExtent =
            (childSizes.map { size in
                isRow ? size.height : size.width
            }.max() ?? 0)
            + (isRow
                ? flexStyle.padding.top + flexStyle.padding.bottom
                : flexStyle.padding.leading + flexStyle.padding.trailing)

        return Size(
            width: isRow ? mainExtent : crossExtent,
            height: isRow ? crossExtent : mainExtent
        )
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
        var measuredWidth = explicitWidth ?? size.width
        var measuredHeight = explicitHeight ?? size.height

        // Greedy axes take the proposal. A frame the author set is their
        // own answer and always wins; a `preferredSize` is only an ideal,
        // so a greedy node with one (a slider, a scroll panel) keeps it as
        // the size it reports when nothing proposes an extent. An infinite
        // proposal leaves the measurement alone, which is what keeps an
        // unconstrained measure of a greedy subtree finite.
        let fillAxes = effectiveFillAxes
        if frame.size.width <= 0, fillAxes.horizontal, constraints.maxWidth.isFinite {
            measuredWidth = max(measuredWidth, constraints.maxWidth)
        }
        if frame.size.height <= 0, fillAxes.vertical, constraints.maxHeight.isFinite {
            measuredHeight = max(measuredHeight, constraints.maxHeight)
        }

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

    /// True when the node paints flexible content (a background color,
    /// gradient, or path) — the runtime stand-in for SwiftUI's
    /// flexible-size views such as `Color`. Stack layout uses this to
    /// expand zero-measuring painted children across the stack's cross
    /// axis (macOS parity); spacers and empty containers stay false so
    /// invisible nodes don't inflate.
    fileprivate var expandsAlongStackCrossAxis: Bool {
        backgroundColor != nil || backgroundGradient != nil || backgroundPath != nil
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
        axis: StackAxis,
        availableExtent: Double,
        shrinkFloors: [Double]
    ) -> [Double] {
        var allocatedSizes = desiredSizes
        let desiredExtent = desiredSizes.reduce(0, +)

        if desiredExtent > availableExtent {
            // The caller computes shrink floors under its own squeeze test, so
            // the array is empty whenever that test disagrees with this one.
            // `shrinkMainSizes` indexes it per child; size it here rather than
            // rely on two float comparisons staying identical forever.
            let floors =
                shrinkFloors.count == desiredSizes.count
                ? shrinkFloors
                : [Double](repeating: 0, count: desiredSizes.count)
            shrinkMainSizes(
                &allocatedSizes,
                children: children,
                axis: axis,
                floors: floors,
                deficit: desiredExtent - availableExtent
            )
        } else if desiredExtent < availableExtent {
            growMainSizes(
                &allocatedSizes,
                children: children,
                axis: axis,
                extraExtent: availableExtent - desiredExtent
            )
        }

        return allocatedSizes
    }

    /// Weight this child carries when a stack shares out leftover main-axis
    /// extent.
    ///
    /// Leftover space belongs to the children that asked for it. When any
    /// child is greedy along this axis — a `Spacer`, a `ScrollView`, a
    /// `.frame(maxWidth: .infinity)` — those children take the whole
    /// remainder and everyone else keeps the size it measured, which is
    /// SwiftUI's rule and the reason a fixed-width search field beside a
    /// `Spacer` stays the width its author gave it.
    ///
    /// `layoutPriority` is not a flex weight in SwiftUI, but a good deal of
    /// this stack's control chrome was built on it behaving like one. That
    /// reading survives only where it can still be the intended one: a row
    /// with no greedy child at all.
    private static func mainAxisGrowthWeight(
        of child: ViewNode,
        axis: StackAxis,
        preferringGreedyChildren: Bool
    ) -> Double {
        guard preferringGreedyChildren else {
            return max(0, child.layoutPriority)
        }
        return fillsMainAxis(child, axis: axis) ? max(1, child.layoutPriority) : 0
    }

    private func growMainSizes(
        _ sizes: inout [Double],
        children: [ViewNode],
        axis: StackAxis,
        extraExtent: Double
    ) {
        guard sizes.count == children.count else {
            return
        }

        let preferringGreedyChildren = children.contains { ViewNode.fillsMainAxis($0, axis: axis) }
        let participantIndices = children.indices.filter {
            ViewNode.mainAxisGrowthWeight(
                of: children[$0], axis: axis, preferringGreedyChildren: preferringGreedyChildren) > 0
        }
        guard !participantIndices.isEmpty else {
            return
        }

        let totalPriority = participantIndices.reduce(0.0) { partialResult, index in
            partialResult
                + ViewNode.mainAxisGrowthWeight(
                    of: children[index], axis: axis, preferringGreedyChildren: preferringGreedyChildren)
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
                share =
                    extraExtent
                    * (ViewNode.mainAxisGrowthWeight(
                        of: children[index], axis: axis, preferringGreedyChildren: preferringGreedyChildren)
                        / totalPriority)
                remainingExtent -= share
            }

            sizes[index] += share
        }
    }

    private func shrinkMainSizes(
        _ sizes: inout [Double],
        children: [ViewNode],
        axis: StackAxis,
        floors: [Double],
        deficit: Double
    ) {
        // Three parallel arrays indexed by `children.indices`; a mismatch is an
        // index-out-of-range trap, so refuse to shrink instead.
        guard sizes.count == children.count, floors.count == children.count else {
            return
        }

        var remainingDeficit = deficit

        // A greedy child (a ScrollView, a List, `.frame(maxHeight: .infinity)`)
        // asked for the whole track it was offered, so when the track is
        // over-subscribed it gives the excess back before any sibling that
        // asked only for the size of its content. Without this, a scroll
        // view whose content is taller than the window squeezes the tab bar
        // and toolbar it sits next to, and the chrome's metrics start
        // depending on which page is selected.
        let greedyIndices = children.indices.filter {
            ViewNode.fillsMainAxis(children[$0], axis: axis) && sizes[$0] > floors[$0]
        }
        if !greedyIndices.isEmpty, remainingDeficit > 0 {
            remainingDeficit -= reduce(
                &sizes,
                at: Array(greedyIndices),
                floors: floors,
                by: remainingDeficit
            )
        }

        let priorities = Array(Set(children.map(\.layoutPriority))).sorted()

        for priority in priorities where remainingDeficit > 0 {
            let indices = children.indices.filter {
                children[$0].layoutPriority == priority && sizes[$0] > floors[$0]
            }
            guard !indices.isEmpty else {
                continue
            }

            remainingDeficit -= reduce(&sizes, at: Array(indices), floors: floors, by: remainingDeficit)
        }
    }

    /// Shares `deficit` across `indices` in proportion to each entry's slack
    /// above its floor, and answers how much was actually absorbed.
    private func reduce(
        _ sizes: inout [Double],
        at indices: [Int],
        floors: [Double],
        by deficit: Double
    ) -> Double {
        let shrinkCapacity = indices.reduce(0.0) { partialResult, index in
            partialResult + sizes[index] - floors[index]
        }
        guard shrinkCapacity > 0 else {
            return 0
        }

        let targetReduction = min(deficit, shrinkCapacity)
        var remainingReduction = targetReduction

        for (offset, index) in indices.enumerated() {
            let capacity = sizes[index] - floors[index]
            let reduction: Double
            if offset == indices.count - 1 {
                reduction = remainingReduction
            } else {
                reduction = targetReduction * (capacity / shrinkCapacity)
                remainingReduction -= reduction
            }

            let appliedReduction = min(capacity, reduction)
            sizes[index] -= appliedReduction
        }

        return targetReduction
    }

    /// True when this node accepts its parent's proposal along `axis`.
    fileprivate static func fillsMainAxis(_ node: ViewNode, axis: StackAxis) -> Bool {
        axis == .vertical ? node.effectiveFillAxes.vertical : node.effectiveFillAxes.horizontal
    }

    /// The axes this node is actually greedy on: the ones it declares, plus
    /// the ones it inherited from a greedy child along its own stack axis.
    internal var effectiveFillAxes: LayoutFillAxes {
        LayoutFillAxes(
            horizontal: layoutFillAxes.horizontal || inheritedStackFillAxes.horizontal,
            vertical: layoutFillAxes.vertical || inheritedStackFillAxes.vertical
        )
    }

    /// A stack that holds a greedy child *along its own axis* is itself
    /// greedy along that axis — SwiftUI's `HStack { Text; Spacer }`, which
    /// takes the width it is proposed rather than the width of its text.
    ///
    /// Only the main axis is derived. Across a stack's cross axis a greedy
    /// child already reports the proposal from its own measurement and the
    /// stack folds that in as its cross extent, so deriving there would
    /// double-apply — and would let a `.frame(width:)` wrapper (a
    /// single-child vertical stack) inherit width greed it must not have.
    /// A node that pins its own extent along the axis ends the chain for the
    /// same reason: `.frame(height: 44)` is the author's answer, not a
    /// proposal to pass on.
    ///
    /// Called once per measurement, after the children have measured, so the
    /// values it reads are this pass's. Deriving it here rather than walking
    /// down from `effectiveFillAxes` keeps the one remaining recursion —
    /// `sizeThatFits` — free of a second one.
    @inline(never)
    fileprivate func updateInheritedStackFillAxes() {
        guard let axis = layoutMode.stackLayout?.axis else {
            inheritedStackFillAxes = LayoutFillAxes()
            return
        }

        let pinsMainExtent = axis == .vertical ? explicitHeight != nil : explicitWidth != nil
        guard !pinsMainExtent else {
            inheritedStackFillAxes = LayoutFillAxes()
            return
        }

        let inherits = children.contains { !$0.isHidden && ViewNode.fillsMainAxis($0, axis: axis) }
        inheritedStackFillAxes =
            axis == .vertical
            ? LayoutFillAxes(horizontal: false, vertical: inherits)
            : LayoutFillAxes(horizontal: inherits, vertical: false)
    }

    /// Minimum main-axis extent a stack shrink pass may leave this node
    /// with. Leaf content that measures as text (or an icon/glyph bitmap)
    /// pins the floor at its measured extent, and a stack carrying such
    /// content pins at the combination of its children's floors — sum
    /// plus spacing along its own axis, max across it — so squeezing a
    /// labeled container compresses its padding and flexible siblings
    /// (and ultimately overflows) instead of crushing text below its
    /// measured size. Nodes without text content keep a zero floor, which
    /// preserves the previous shrink behavior for them. Two escape
    /// hatches keep pinned control chrome contained: a `clipsToBounds`
    /// container absorbs squeeze instead of propagating a floor, and
    /// explicit single-line text takes no width floor because truncation
    /// is its degrade path.
    fileprivate func stackShrinkFloorMainExtent(
        along axis: StackAxis,
        constraints: LayoutConstraints
    ) -> Double {
        guard ViewNode.enterTraversal() else { return 0 }
        defer { ViewNode.leaveTraversal() }

        // A declared minimum is a hard floor, whatever the content is: a
        // control that states its macOS height (a 22pt segmented track, a
        // 24pt list row) keeps it under pressure and the container
        // overflows or scrolls instead, exactly as `.frame(minHeight:)`
        // behaves in SwiftUI.
        let declaredMinimum = max(
            0,
            axis == .vertical ? (layoutConstraints?.minHeight ?? 0) : (layoutConstraints?.minWidth ?? 0)
        )

        // A clipping container is the declared "content may be cut here"
        // boundary: it absorbs squeeze (its interior clips or truncates)
        // instead of resisting it, so it contributes no floor upward — not
        // even its own declared minimum. Control chrome (buttons, segmented
        // tracks) relies on this to keep pinned frames contained.
        if clipsToBounds {
            return 0
        }

        if let text, !text.isEmpty {
            // Explicit single-line text opted into truncation as its
            // degrade path: an over-long label shows an ellipsis instead
            // of resisting the squeeze, so it takes no width floor. The
            // vertical floor (line height) still applies.
            if axis == .horizontal, textStyle.maximumNumberOfLines == 1 {
                return declaredMinimum
            }
            let measured = sizeThatFits(in: constraints)
            return max(declaredMinimum, axis == .vertical ? measured.height : measured.width)
        }

        if bitmapSurface != nil {
            let measured = sizeThatFits(in: constraints)
            return max(declaredMinimum, axis == .vertical ? measured.height : measured.width)
        }

        guard let stackLayout = layoutMode.stackLayout else {
            return declaredMinimum
        }

        let contentConstraints = insetConstraints(
            applyingLayoutConstraints(to: constraints), by: stackLayout.padding)
        let childConstraints = stackChildConstraints(for: contentConstraints, axis: stackLayout.axis)
        let visibleChildren = children.filter { !$0.isHidden }
        let childFloors = visibleChildren.map {
            $0.stackShrinkFloorMainExtent(along: axis, constraints: childConstraints)
        }

        let combinedFloor: Double
        if stackLayout.axis == axis {
            combinedFloor =
                childFloors.reduce(0, +)
                + stackLayoutSpacingTotal(count: visibleChildren.count, spacing: stackLayout.spacing)
        } else {
            combinedFloor = childFloors.max() ?? 0
        }

        // An explicit main-axis dimension caps the floor: the author asked
        // for a fixed size, so shrink resistance never exceeds it.
        let explicitMainExtent = axis == .vertical ? explicitHeight : explicitWidth
        if let explicitMainExtent {
            return max(declaredMinimum, min(combinedFloor, explicitMainExtent))
        }

        return max(declaredMinimum, combinedFloor)
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

    /// Applies a wheel impulse to scrollOffset and returns the signed offset
    /// change that was actually applied (0 when no movement happened).
    fileprivate func applyMouseWheelDelta(_ delta: Double) -> Double {
        guard isScrollable else {
            return 0
        }

        let previousOffset = scrollOffset
        let nextOffset = clampedScrollOffset(for: scrollOffset - delta * scrollStep)
        guard nextOffset != previousOffset else {
            return 0
        }

        scrollOffset = nextOffset
        return nextOffset - previousOffset
    }

    /// The part of a wheel push the bounds refuse, in offset units.
    ///
    /// Positive means the push wanted to go past `maxScrollOffset`, negative
    /// past 0. Zero when the push lands inside the range, when the node cannot
    /// scroll at all, or when its content fits — a view with nothing to scroll
    /// should sit still, not bounce.
    ///
    /// Must be read *before* `applyMouseWheelDelta`, which moves the offset out
    /// from under it.
    fileprivate func refusedMouseWheelDelta(_ delta: Double) -> Double {
        guard isScrollable, maxScrollOffset > 0 else {
            return 0
        }

        let proposedOffset = scrollOffset - delta * scrollStep
        return proposedOffset - clampedScrollOffset(for: proposedOffset)
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
            return applyScrollDelta(
                (scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width) * 0.85)
        case (_, .pageUp):
            return applyScrollDelta(
                -(scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width) * 0.85)
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

    private var effectiveScrollIndicatorInsets: EdgeInsets {
        EdgeInsets(
            top: max(0, scrollIndicatorInsets.top),
            leading: max(0, scrollIndicatorInsets.leading),
            bottom: max(0, scrollIndicatorInsets.bottom),
            trailing: max(0, scrollIndicatorInsets.trailing)
        )
    }

    /// Where the thumb *is*, whether or not it can currently be seen.
    ///
    /// Geometry deliberately does not consult `scrollIndicatorColor`: an
    /// overlay scroller is transparent for most of its life, and gating the
    /// rect on alpha would mean a faded-out thumb has no track, so the pointer
    /// could never land on it and hovering the edge could never bring it back.
    func scrollIndicatorRect(in absoluteFrame: Rect) -> Rect? {
        guard showsScrollIndicator, isScrollable, maxScrollOffset > 0 else {
            return nil
        }

        let indicatorInsets = effectiveScrollIndicatorInsets
        let indicatorThickness = max(4, scrollIndicatorThickness)

        switch scrollAxis {
        case .vertical:
            let trackHeight = max(0, absoluteFrame.size.height - indicatorInsets.top - indicatorInsets.bottom)
            guard trackHeight > 0 else { return nil }
            let visibleRatio = max(
                0.08, absoluteFrame.size.height / max(resolvedContentSize.height, absoluteFrame.size.height))
            let indicatorHeight = max(24, trackHeight * visibleRatio)
            let travel = max(0, trackHeight - indicatorHeight)
            // Rubber-band overshoot may push resolvedScrollOffset outside
            // [0, maxScrollOffset]; the indicator stays pinned at its bound
            // while content overscrolls, matching macOS behaviour.
            let progress = maxScrollOffset > 0 ? min(1, max(0, resolvedScrollOffset / maxScrollOffset)) : 0
            return Rect(
                x: absoluteFrame.maxX - indicatorInsets.trailing - indicatorThickness,
                y: absoluteFrame.origin.y + indicatorInsets.top + travel * progress,
                width: indicatorThickness,
                height: indicatorHeight
            )

        case .horizontal:
            let trackWidth = max(0, absoluteFrame.size.width - indicatorInsets.leading - indicatorInsets.trailing)
            guard trackWidth > 0 else { return nil }
            let visibleRatio = max(
                0.08, absoluteFrame.size.width / max(resolvedContentSize.width, absoluteFrame.size.width))
            let indicatorWidth = max(24, trackWidth * visibleRatio)
            let travel = max(0, trackWidth - indicatorWidth)
            let progress = maxScrollOffset > 0 ? min(1, max(0, resolvedScrollOffset / maxScrollOffset)) : 0
            return Rect(
                x: absoluteFrame.origin.x + indicatorInsets.leading + travel * progress,
                y: absoluteFrame.maxY - indicatorInsets.bottom - indicatorThickness,
                width: indicatorWidth,
                height: indicatorThickness
            )

        case nil:
            return nil
        }
    }

    /// The indicator track, measured in layout space and returned in painted
    /// space.
    ///
    /// Both spaces are load-bearing and they are not interchangeable. The
    /// thumb's *length* is the visible fraction of the content —
    /// `resolvedFrame` against `resolvedContentSize`, both layout-space — and
    /// its *position* is what the painter draws and what the pointer is tested
    /// against, which is painted space. Measuring the fraction on the painted
    /// frame while the content size stayed in layout space made a
    /// `.scaleEffect(2)` ScrollView report a viewport as tall as its content:
    /// a full-length thumb that could not move, and a drag whose
    /// `maxScrollOffset / travel` rate was scaled by the same factor.
    ///
    /// `inheritedTransform` then `centeredTransform` is exactly the mapping the
    /// caller used to derive its own `paintFrame`, so the track lands inside
    /// the viewport it belongs to rather than beside it.
    fileprivate func scrollIndicatorTrack(
        in layoutFrame: Rect,
        inheritedTransform: Transform2D,
        centeredTransform: Transform2D
    ) -> ScrollIndicatorTrack? {
        guard let layoutIndicatorRect = scrollIndicatorRect(in: layoutFrame), let scrollAxis else {
            return nil
        }

        let indicatorInsets = effectiveScrollIndicatorInsets
        func painted(_ rect: Rect) -> Rect {
            var mapped = rect
            if !inheritedTransform.isIdentity {
                mapped = mapped.applying(transform: inheritedTransform)
            }
            if !centeredTransform.isIdentity {
                mapped = mapped.applying(transform: centeredTransform)
            }
            return mapped
        }

        let indicatorRect = painted(layoutIndicatorRect)

        switch scrollAxis {
        case .vertical:
            let trackLength = max(0, layoutFrame.size.height - indicatorInsets.top - indicatorInsets.bottom)
            let trackRect = painted(
                Rect(
                    x: layoutIndicatorRect.origin.x,
                    y: layoutFrame.origin.y + indicatorInsets.top,
                    width: layoutIndicatorRect.size.width,
                    height: trackLength
                )
            )
            return ScrollIndicatorTrack(
                axis: .vertical,
                origin: trackRect.origin.y,
                travel: max(0, trackRect.size.height - indicatorRect.size.height),
                indicatorRect: indicatorRect
            )

        case .horizontal:
            let trackLength = max(0, layoutFrame.size.width - indicatorInsets.leading - indicatorInsets.trailing)
            let trackRect = painted(
                Rect(
                    x: layoutFrame.origin.x + indicatorInsets.leading,
                    y: layoutIndicatorRect.origin.y,
                    width: trackLength,
                    height: layoutIndicatorRect.size.height
                )
            )
            return ScrollIndicatorTrack(
                axis: .horizontal,
                origin: trackRect.origin.x,
                travel: max(0, trackRect.size.width - indicatorRect.size.width),
                indicatorRect: indicatorRect
            )
        }
    }

    fileprivate func clampedScrollOffset(for value: Double) -> Double {
        // `max(NaN, 0)` is NaN in Swift, and a NaN scroll offset poisons every
        // descendant origin — every clip intersection then comes back empty and
        // the window paints blank with nothing logged.
        guard value.isFinite else { return 0 }
        let limit = maxScrollOffset
        return min(max(value, 0), limit.isFinite ? limit : 0)
    }

    /// The scroll offset actually presented this frame: the clamped logical
    /// offset plus the rubber-band and keyboard-tween deltas. Both
    /// `layoutSubtree` exits assign `resolvedScrollOffset` from this — the
    /// full-relayout exit used to drop both deltas, so a `.layout`
    /// invalidation arriving mid rubber-band snapped the content back to the
    /// clamped offset for a frame and then jumped out again on the next tick.
    fileprivate var effectiveScrollOffset: Double {
        let composed = clampedScrollOffset(for: scrollOffset) + scrollOvershoot + scrollPresentedDelta
        return composed.isFinite ? composed : 0
    }

    private func applyScrollDelta(_ delta: Double) -> Bool {
        setScrollOffset(scrollOffset + delta)
    }

    fileprivate func setScrollOffset(_ value: Double) -> Bool {
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
        case .backgroundGradientStart:
            return backgroundGradient?.startColor ?? backgroundColor ?? .clear
        case .backgroundGradientEnd:
            return backgroundGradient?.endColor ?? backgroundColor ?? .clear
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
        case .backgroundGradientStart:
            backgroundGradient = backgroundGradient?.replacingStartColor(with: color)
        case .backgroundGradientEnd:
            backgroundGradient = backgroundGradient?.replacingEndColor(with: color)
        }
    }

    /// Cross-fades this node's fill from where it was to what the build just
    /// wrote, for a node that animates its own changes
    /// (`implicitReconcileAnimation`).
    ///
    /// The gradient ends are animated too, and that is not a nicety: a
    /// gradient wins over `backgroundColor` at paint time, so a tween that
    /// moved only the colour under a snapped gradient would not be visible at
    /// all.
    func applyImplicitFillTween(fromBackgroundColor: Color?, fromBackgroundGradient: GradientType?) {
        guard let animation = implicitReconcileAnimation, animation.duration > 0, let runtime else {
            return
        }

        let timestamp = animationClockNow
        if let fromBackgroundColor, let target = backgroundColor, fromBackgroundColor != target {
            backgroundColor = fromBackgroundColor
            runtime.animateColor(.background, of: self, to: target, duration: animation.duration, at: timestamp)
        }
        if let fromBackgroundGradient, let target = backgroundGradient, fromBackgroundGradient != target {
            let startColor = target.startColor
            let endColor = target.endColor
            backgroundGradient = fromBackgroundGradient
            runtime.animateColor(
                .backgroundGradientStart, of: self, to: startColor, duration: animation.duration, at: timestamp)
            runtime.animateColor(
                .backgroundGradientEnd, of: self, to: endColor, duration: animation.duration, at: timestamp)
        }
    }

    func applyInsertionTransition() {
        let insertion = transition.insertion
        guard insertion.kind != .identity else { return }
        didPlayInsertionTransition = true

        // Ambient `withAnimation` first, then the node's own transaction (a
        // control whose state change is its own — a disclosure, a switch —
        // never has an ambient one), then the SwiftUI default.
        let tx = currentAnimationTransaction ?? implicitReconcileAnimation.map { ($0.duration, $0.easing) }
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut
        let now = animationClockNow

        applySingleTransition(insertion, duration: duration, easing: easing, now: now)
    }

    private func applySingleTransition(
        _ transition: RetainedTransition, duration: Double, easing: AnimationEasing, now: Double
    ) {
        switch transition.kind {
        case .identity:
            break
        case .opacity:
            let targetOpacity = opacity
            opacity = 0
            animationStates[.opacity] = AnimationState(
                startValue: 0, endValue: targetOpacity,
                startTime: now, duration: duration, easing: easing
            )
        case .scale(let scaleX, let scaleY, _, _):
            let targetScaleX = transform.scaleX
            let targetScaleY = transform.scaleY
            transform.scaleX = scaleX
            transform.scaleY = scaleY
            animationStates[.transformScaleX] = AnimationState(
                startValue: scaleX, endValue: targetScaleX,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformScaleY] = AnimationState(
                startValue: scaleY, endValue: targetScaleY,
                startTime: now, duration: duration, easing: easing
            )
        case .offset(let x, let y):
            let targetTX = transform.translationX
            let targetTY = transform.translationY
            transform.translationX = x
            transform.translationY = y
            animationStates[.transformTranslationX] = AnimationState(
                startValue: x, endValue: targetTX,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformTranslationY] = AnimationState(
                startValue: y, endValue: targetTY,
                startTime: now, duration: duration, easing: easing
            )
        case .move(let edge):
            let offsetX: Double
            let offsetY: Double
            switch edge {
            case .leading:
                offsetX = -resolvedFrame.size.width
                offsetY = 0
            case .trailing:
                offsetX = resolvedFrame.size.width
                offsetY = 0
            case .top:
                offsetX = 0
                offsetY = -resolvedFrame.size.height
            case .bottom:
                offsetX = 0
                offsetY = resolvedFrame.size.height
            }
            let targetTX = transform.translationX
            let targetTY = transform.translationY
            transform.translationX = offsetX
            transform.translationY = offsetY
            animationStates[.transformTranslationX] = AnimationState(
                startValue: offsetX, endValue: targetTX,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformTranslationY] = AnimationState(
                startValue: offsetY, endValue: targetTY,
                startTime: now, duration: duration, easing: easing
            )
        case .slide:
            let targetTX = transform.translationX
            transform.translationX = resolvedFrame.size.width
            animationStates[.transformTranslationX] = AnimationState(
                startValue: resolvedFrame.size.width, endValue: targetTX,
                startTime: now, duration: duration, easing: easing
            )
        case .push:
            let targetTX = transform.translationX
            let targetScaleX = transform.scaleX
            transform.translationX = resolvedFrame.size.width * 0.5
            transform.scaleX = 0.85
            animationStates[.transformTranslationX] = AnimationState(
                startValue: resolvedFrame.size.width * 0.5, endValue: targetTX,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformScaleX] = AnimationState(
                startValue: 0.85, endValue: targetScaleX,
                startTime: now, duration: duration, easing: easing
            )
        case .combined(let first, let second):
            applySingleTransition(first, duration: duration, easing: easing, now: now)
            applySingleTransition(second, duration: duration, easing: easing, now: now)
        case .asymmetric:
            // Defensive: insertion property already flattens asymmetric.
            break
        case .modifier:
            break
        }
    }

    func applyRemovalTransition() {
        let removal = transition.removal
        guard removal.kind != .identity else { return }

        let tx = currentAnimationTransaction ?? implicitReconcileAnimation.map { ($0.duration, $0.easing) }
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut
        let now = animationClockNow

        applySingleRemovalTransition(removal, duration: duration, easing: easing, now: now)
    }

    private func applySingleRemovalTransition(
        _ transition: RetainedTransition, duration: Double, easing: AnimationEasing, now: Double
    ) {
        switch transition.kind {
        case .identity:
            break
        case .opacity:
            let startOpacity = opacity
            animationStates[.opacity] = AnimationState(
                startValue: startOpacity, endValue: 0,
                startTime: now, duration: duration, easing: easing
            )
        case .scale(let scaleX, let scaleY, _, _):
            let startScaleX = transform.scaleX
            let startScaleY = transform.scaleY
            animationStates[.transformScaleX] = AnimationState(
                startValue: startScaleX, endValue: scaleX,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformScaleY] = AnimationState(
                startValue: startScaleY, endValue: scaleY,
                startTime: now, duration: duration, easing: easing
            )
        case .offset(let x, let y):
            let startTX = transform.translationX
            let startTY = transform.translationY
            animationStates[.transformTranslationX] = AnimationState(
                startValue: startTX, endValue: x,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformTranslationY] = AnimationState(
                startValue: startTY, endValue: y,
                startTime: now, duration: duration, easing: easing
            )
        case .move(let edge):
            let offsetX: Double
            let offsetY: Double
            switch edge {
            case .leading:
                offsetX = -resolvedFrame.size.width
                offsetY = 0
            case .trailing:
                offsetX = resolvedFrame.size.width
                offsetY = 0
            case .top:
                offsetX = 0
                offsetY = -resolvedFrame.size.height
            case .bottom:
                offsetX = 0
                offsetY = resolvedFrame.size.height
            }
            let startTX = transform.translationX
            let startTY = transform.translationY
            animationStates[.transformTranslationX] = AnimationState(
                startValue: startTX, endValue: offsetX,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformTranslationY] = AnimationState(
                startValue: startTY, endValue: offsetY,
                startTime: now, duration: duration, easing: easing
            )
        case .slide:
            let startTX = transform.translationX
            animationStates[.transformTranslationX] = AnimationState(
                startValue: startTX, endValue: resolvedFrame.size.width,
                startTime: now, duration: duration, easing: easing
            )
        case .push:
            let startTX = transform.translationX
            let startScaleX = transform.scaleX
            animationStates[.transformTranslationX] = AnimationState(
                startValue: startTX, endValue: resolvedFrame.size.width * 0.5,
                startTime: now, duration: duration, easing: easing
            )
            animationStates[.transformScaleX] = AnimationState(
                startValue: startScaleX, endValue: 0.85,
                startTime: now, duration: duration, easing: easing
            )
        case .combined(let first, let second):
            applySingleRemovalTransition(first, duration: duration, easing: easing, now: now)
            applySingleRemovalTransition(second, duration: duration, easing: easing, now: now)
        case .asymmetric:
            // Defensive: removal property already flattens asymmetric.
            break
        case .modifier:
            break
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
@MainActor
private func stackCrossOriginUsingAlignmentGuide(
    for child: ViewNode,
    stackAxis: StackAxis,
    stackAlignment: StackCrossAlignment,
    contentOrigin: Double,
    contentExtent: Double,
    childExtent: Double
) -> Double? {
    guard let guide = stackCrossAlignmentGuide(for: stackAxis, alignment: stackAlignment) else {
        return nil
    }

    let guideValue: Double
    if let alignmentGuide = child.alignmentGuides.last(where: { $0.axis == guide.axis && $0.guide == guide.name }) {
        guideValue = alignmentGuide.value
    } else if stackAlignment == .firstTextBaseline || stackAlignment == .lastTextBaseline {
        guideValue = defaultStackCrossBaselineGuideValue(for: childExtent)
    } else {
        return nil
    }

    return contentOrigin + stackCrossReference(for: stackAlignment, contentExtent: contentExtent) - guideValue
}
private func stackCrossAlignmentGuide(
    for stackAxis: StackAxis,
    alignment: StackCrossAlignment
) -> (axis: RetainedAlignmentGuideAxis, name: String)? {
    switch stackAxis {
    case .vertical:
        switch alignment {
        case .leading:
            return (.horizontal, "leading")
        case .center:
            return (.horizontal, "center")
        case .trailing:
            return (.horizontal, "trailing")
        case .firstTextBaseline:
            return nil
        case .lastTextBaseline:
            return nil
        case .customHorizontal(let name):
            return (.horizontal, name)
        case .customVertical:
            return nil
        case .stretch:
            return nil
        }
    case .horizontal:
        switch alignment {
        case .leading:
            return (.vertical, "top")
        case .center:
            return (.vertical, "center")
        case .trailing:
            return (.vertical, "bottom")
        case .firstTextBaseline:
            return (.vertical, "firstTextBaseline")
        case .lastTextBaseline:
            return (.vertical, "lastTextBaseline")
        case .customHorizontal:
            return nil
        case .customVertical(let name):
            return (.vertical, name)
        case .stretch:
            return nil
        }
    }
}
private func stackCrossReference(for alignment: StackCrossAlignment, contentExtent: Double) -> Double {
    switch alignment {
    case .leading, .stretch:
        return 0
    case .center:
        return contentExtent * 0.5
    case .trailing:
        return contentExtent
    case .firstTextBaseline, .lastTextBaseline:
        return defaultStackCrossBaselineGuideValue(for: contentExtent)
    case .customHorizontal, .customVertical:
        return 0
    }
}
private func defaultStackCrossBaselineGuideValue(for extent: Double) -> Double {
    max(0, extent) * 0.8
}
private func stackScrollAxis(for axis: StackAxis) -> ScrollAxis {
    switch axis {
    case .vertical:
        return .vertical
    case .horizontal:
        return .horizontal
    }
}
/// Clamps a resolved layout coordinate to the finite range the scene contract
/// accepts. Layout arithmetic reaches non-finite values from ordinary app code
/// — `.frame(maxWidth: .infinity)` landing in `preferredSize`, or a division by
/// an extent that collapsed to zero during first layout — and every downstream
/// `Int(_: Float)` conversion traps on those. A Swift trap is the one failure
/// class the host's renderer fallback cannot degrade, so the clamp happens
/// here, at the layer boundary. Finite in-range values pass through unchanged.
private func sanitizedLayoutCoordinate(_ value: Double) -> Double {
    GPUISceneValue.clamped(value, to: Double(GPUISceneLimits.maxCoordinate))
}
/// Extents additionally floor at zero: a negative or NaN extent describes no
/// area, and `Rect.intersected` treats it as an empty region either way.
private func sanitizedLayoutExtent(_ value: Double) -> Double {
    max(0, sanitizedLayoutCoordinate(value))
}
private func sanitizedLayoutSize(_ size: Size) -> Size {
    Size(width: sanitizedLayoutExtent(size.width), height: sanitizedLayoutExtent(size.height))
}
private func sanitizedLayoutRect(_ rect: Rect) -> Rect {
    Rect(
        x: sanitizedLayoutCoordinate(rect.origin.x),
        y: sanitizedLayoutCoordinate(rect.origin.y),
        width: sanitizedLayoutExtent(rect.size.width),
        height: sanitizedLayoutExtent(rect.size.height)
    )
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
/// Weak box so the runtime can hold a set of nodes without keeping them
/// alive. Used by the animating-node registry, where a strong reference
/// would turn a dropped mid-animation node into a permanently spinning
/// animation timer.
@MainActor
private struct WeakViewNodeRef {
    weak var node: ViewNode?
}
/// One invalidation raised while a render pass was open, replayed onto the
/// node's subtree flags once the pass has finished clearing them.
@MainActor
private struct PendingNodeInvalidation {
    var node: WeakViewNodeRef
    var flags: DirtyFlags
}
@MainActor
public final class RetainedViewRuntime {
    private static let buttonRepeatInitialDelay = 0.45
    private static let buttonRepeatInterval = 0.08

    public let root: ViewNode

    public var displayScale: Double {
        didSet {
            // No text-cache invalidation here: `TextRasterCache`'s key carries
            // the scale the raster was produced at, so a scale change asks a
            // different question rather than invalidating an answer. This used
            // to clear a `textRasterCache` property that nothing ever
            // assigned — the hook was live, the cache was `nil`.
            invalidate()
        }
    }

    public var clearColor: Color {
        didSet { invalidate() }
    }

    /// The single source of "now" for every animation this runtime owns.
    ///
    /// `tickAnimations(at:)` takes an injected timestamp, but a tween's *start*
    /// time is stamped wherever the tween is seeded — a pointer event, a
    /// reconcile, a wheel notch — none of which are handed a timestamp. Those
    /// sites used to read `Win32Window.currentTimestampSeconds()` directly,
    /// which in production is the same QPC source the host ticks with, but in a
    /// test is a clock the test cannot address. The consequence was structural:
    /// no test could assert a value while a tween was in flight, because it
    /// could not place the tween's start on the timeline it was ticking. The
    /// gallery's interaction tier renders at `t = 1e12` for exactly this
    /// reason, and by construction only ever captured settled end states.
    ///
    /// Every start-time stamp in the runtime, in `Controls`, and in
    /// `ComponentHost`'s reconcile now reads this. Override it and the whole
    /// interaction layer runs on the timeline you choose.
    public var clock: @MainActor () -> Double = { Win32Window.currentTimestampSeconds() }

    /// True while anything in this runtime still needs a frame tick. The host
    /// gates its animation timer on exactly this value, so every animation
    /// mechanism has to be represented: the runtime-level ones (colour tweens,
    /// button repeat, scroll momentum and presented tweens), the per-node
    /// `animationStates` driven by `.animation()` and insertion transitions,
    /// and the removal-transition overlays. Omitting either of the last two
    /// froze a removal transition permanently — the overlay was painted once
    /// at its start value and then never ticked again.
    /// `scrollIndicatorReveals` is in the list for the interval where nothing
    /// is moving at all: a revealed overlay scroller waiting out its hold has
    /// no tween in flight, and if the host switched its timer off there the
    /// deadline would never arrive and the thumb would stay up forever.
    /// `deferredRebuilds` is there for the same reason one step up: a
    /// `PhaseAnimator` between two phases has nothing tweening, and if the
    /// timer stopped there the next phase would never start.
    public var hasActiveAnimations: Bool {
        !colorAnimations.isEmpty || buttonRepeatState != nil || !scrollMomenta.isEmpty
            || !scrollPresentedTweens.isEmpty || !transitionOverlays.isEmpty
            || !scrollIndicatorReveals.isEmpty
            || !deferredRebuilds.isEmpty
            || hasBlinkingCaret
            || hasNodeAnimationsInFlight
    }

    // MARK: - Deferred rebuilds

    private struct DeferredRebuild {
        var deadline: Double
        var action: @MainActor () -> Void
    }

    private var deferredRebuilds: [String: DeferredRebuild] = [:]

    /// Runs `action` once, from `tickAnimations(at:)`, after `delay` on this
    /// runtime's animation clock — and reports the pending wait through
    /// `hasActiveAnimations` so the host keeps ticking until it fires.
    ///
    /// `PhaseAnimator` used to advance on a detached `Task` awaiting
    /// `Task.sleep(nanoseconds:)`. That sleep is wall-clock and unsynchronised
    /// with the frame clock, so a phase boundary landed wherever the scheduler
    /// happened to put it rather than on a frame; and nothing in
    /// `hasActiveAnimations` represented a phase animator waiting out a phase,
    /// so a phase with a nil or zero-duration animation left the runtime with
    /// nothing registered and the host free to switch its timer off between
    /// phases. Both are properties of the timer, not of the animator, which is
    /// why the fix belongs here: this is the same shape as
    /// `tickScrollIndicatorReveals`, and it makes phase timing reproducible
    /// under a controlled clock, which a sleep can never be.
    public func scheduleDeferredRebuild(
        key: String, delay: Double, perform action: @escaping @MainActor () -> Void
    ) {
        deferredRebuilds[key] = DeferredRebuild(deadline: clock() + max(0, delay), action: action)
        invalidate()
    }

    public func hasDeferredRebuild(key: String) -> Bool {
        deferredRebuilds[key] != nil
    }

    public func cancelDeferredRebuild(key: String) {
        deferredRebuilds.removeValue(forKey: key)
    }

    /// Fires every deadline that has come due, in key order so a frame that
    /// carries several is deterministic. Entries are removed before their
    /// actions run: an action rebuilds, and a rebuild is entitled to schedule
    /// the next phase.
    private func tickDeferredRebuilds(at timestamp: Double) -> Bool {
        guard !deferredRebuilds.isEmpty else { return false }

        let dueKeys = deferredRebuilds.filter { $0.value.deadline <= timestamp }.keys.sorted()
        guard !dueKeys.isEmpty else { return false }

        var due: [@MainActor () -> Void] = []
        for key in dueKeys {
            if let entry = deferredRebuilds.removeValue(forKey: key) {
                due.append(entry.action)
            }
        }
        for action in due {
            action()
        }
        return true
    }

    /// A focused text input's caret needs a tick forever, not until something
    /// settles — the blink has no end state. Without it in the gate the host
    /// switches its timer off and the caret freezes wherever the last frame
    /// left it, which is the failure mode the comment above documents.
    private var hasBlinkingCaret: Bool {
        focusedCaretNode() != nil
    }

    /// Nodes with at least one in-flight per-property animation, maintained
    /// from `ViewNode.animationStates`' `didSet`. References are weak so a
    /// node dropped mid-animation cannot pin the animation driver on for the
    /// rest of the session; stale slots are swept in `tickAnimations`.
    private var animatingNodes: [ObjectIdentifier: WeakViewNodeRef] = [:]

    private var hasNodeAnimationsInFlight: Bool {
        for entry in animatingNodes.values where entry.node != nil {
            return true
        }
        return false
    }

    fileprivate func registerAnimatingNode(_ node: ViewNode) {
        animatingNodes[ObjectIdentifier(node)] = WeakViewNodeRef(node: node)
    }

    fileprivate func unregisterAnimatingNode(_ node: ViewNode) {
        animatingNodes.removeValue(forKey: ObjectIdentifier(node))
    }

    private func sweepAnimatingNodes() {
        guard !animatingNodes.isEmpty else { return }
        animatingNodes = animatingNodes.filter { $0.value.node != nil }
    }

    // Gap/Fix: Granular dirty tracking — DirtyFlags replaces single boolean.
    public private(set) var dirtyFlags: DirtyFlags = .all
    public var isDirty: Bool { !dirtyFlags.isEmpty }

    /// Invalidation staging for the duration of a render pass — see
    /// `beginRenderPass()` / `endRenderPass()`.
    private var isRendering = false
    private var pendingDirtyFlags: DirtyFlags = []
    private var pendingDirtyNodes: [PendingNodeInvalidation] = []
    private var pendingAfterLayoutActions: [String: @MainActor () -> Void] = [:]
    private var pendingAfterLayoutActionKeys: [String] = []
    private var isDrainingAfterLayoutActions = false
    private struct PendingPreciseScrollAlignment {
        weak var target: ViewNode?
        weak var container: ViewNode?
        var anchorX: Double?
        var anchorY: Double?
        var expectedOffset: Double
    }
    private var pendingPreciseScrollAlignments: [PendingPreciseScrollAlignment] = []
    private var cachedFrame: RenderFrame?
    private var cachedScene: GPUIScene?
    /// The glyph-atlas generation `cachedScene`'s glyph quads were addressed
    /// against, or `nil` when it draws no native glyph. `nil` for a scene
    /// without glyphs rather than "unknown": there is nothing to go stale.
    private var cachedSceneAtlasGeneration: UInt64?
    private var prepaintState = RuntimePrepaintState()

    /// Access to current prepaint state for testing deferred scene-path behavior.
    @MainActor
    internal var currentPrepaintState: RuntimePrepaintState { prepaintState }
    internal private(set) var lastFrameReplayCount = 0
    internal private(set) var lastSceneReplayCount = 0
    /// How many `renderScene` calls actually repainted the tree, and how many
    /// returned the retained copy untouched.
    ///
    /// The replay counters above are per-node and per-pass; these two are the
    /// per-frame question a live measurement has to answer — whether the
    /// window's steady state is "repaint everything at refresh rate" or
    /// "hand back the cached scene". Nothing outside this module could tell
    /// those apart, so the replay machinery's effect on a running window was
    /// unfalsifiable from the host that drives it.
    public private(set) var sceneRebuildCount: UInt64 = 0
    public private(set) var sceneCacheHitCount: UInt64 = 0
    /// Monotonic revision of the built output, bumped exactly when
    /// `renderFrame` or `renderScene` actually rebuilds — never on a cache
    /// hit or a pacing-floor replay. Two calls that return the same revision
    /// returned byte-identical content, which is what lets the host skip a
    /// present that would replace the screen's pixels with themselves.
    /// Backend-neutral on purpose: one counter covers both output shapes, so
    /// a backend switch (which drops the other path's cache and rebuilds)
    /// always moves it.
    public private(set) var contentRevision: UInt64 = 0
    /// Whether `renderScene` splits its own wall clock into layout and paint.
    ///
    /// Off by default and paid for by nobody who has not asked: the split
    /// costs two QPC round-trips on a path that runs at frame rate. A live
    /// diagnostics session turns it on, because "the scene build cost 10 ms"
    /// is not an actionable statement — laying the tree out and painting it
    /// are different work with different fixes, and the combined figure
    /// cannot say which one moved.
    public var collectsPhaseTimings = false
    /// Seconds the last scene repaint spent in `updateResolvedLayout` (every
    /// layout pass, including `GeometryReader` convergence rounds) and in
    /// `ScenePainter.paint` respectively. Both are zero on a frame that hit
    /// the scene cache, and stale — from the last repaint — if read after one.
    public private(set) var lastLayoutSeconds: Double = 0
    public private(set) var lastPaintSeconds: Double = 0
    /// Nodes the most recent scene repaint replayed from the previous scene
    /// instead of repainting. Meaningful only for a frame that rebuilt.
    public var lastSceneNodeReplayCount: Int { lastSceneReplayCount }
    /// Public read-only paint metrics for the most recently rendered scene.
    /// Captures GPU-vs-CPU path routing decisions so callers can observe
    /// the GPU promotion rate (see `ScenePaintMetrics.gpuPromotionRate`).
    public private(set) var lastScenePaintMetrics: ScenePaintMetrics = ScenePaintMetrics()
    internal private(set) var lastLayoutReuseCount = 0
    internal private(set) var lastMeasureReuseCount = 0
    /// How many child subtrees a `.lazyStack` has skipped laying out because
    /// the scroll viewport (plus overscan) could not reach them.
    ///
    /// Monotonic, not per-pass: one `renderScene` + `renderFrame` pair runs
    /// two layout passes and the second correctly does nothing, so a
    /// per-pass counter reads zero exactly when the work was avoided. This
    /// is the structural measure of virtualization — the difference between
    /// O(rows) and O(visible rows) of recursive layout work.
    internal private(set) var virtualizedLayoutSkipCount = 0
    /// How many nodes `layoutSubtree` actually descended into, across every
    /// pass this runtime has run.
    ///
    /// The companion to `virtualizedLayoutSkipCount`, and the one that can
    /// tell the two failure modes apart: a skip counter alone cannot
    /// distinguish "skipped the descent but still walked every row" from
    /// "visited only the window". Visits are the direct measure of recursive
    /// layout work, so a list whose visit count grows with the row count has
    /// lost virtualization even while the skip count looks healthy.
    ///
    /// Lifetime-cumulative, so it measures passes-times-visits: an absolute
    /// budget belongs on `maxLayoutVisitsInAnyPass` below, not on this.
    internal private(set) var layoutVisitCount = 0
    /// The largest number of nodes any single layout pass has descended
    /// into. The cumulative count above doubles under an extra settle pass
    /// with no regression behind it — and a one-pass regression can hide in
    /// the same slack — so a budget on descent cost reads this instead: per
    /// pass, and immune to how many passes a render happened to run.
    internal private(set) var maxLayoutVisitsInAnyPass = 0
    /// Visits recorded by the pass currently running (or the last one that
    /// ran). Reset in `updateResolvedLayout` beside `layoutPassID`.
    private var currentPassLayoutVisitCount = 0
    /// Monotonic identity of the layout pass currently running (or the last
    /// one that ran). Bumped once per `updateResolvedLayout`, and used to
    /// tell state a pass produced from state a previous pass left behind —
    /// see `ViewNode.isOnVirtualizationDescentPath`.
    internal private(set) var layoutPassID: UInt64 = 0
    /// True only while a retained layout traversal is actively placing its
    /// nodes. Post-layout callbacks run with this false, after geometry has
    /// settled and programmatic scroll requests can safely be resolved.
    public private(set) var isLayoutInProgress = false

    /// Whether this runtime has begun at least one retained layout pass.
    /// Clients combine this with `isLayoutInProgress` to distinguish a
    /// genuinely premature request from a missing or disabled scroll target.
    public var hasCompletedLayout: Bool { layoutPassID != 0 }

    /// The `GeometryReader` nodes the pass that just ran walked past, in
    /// traversal order. Refilled by every pass and drained by
    /// `resolveGeometryReaderSlots`; empty for the overwhelming majority of
    /// trees, which is what keeps the convergence loop free when no reader
    /// is on screen.
    private var pendingGeometryReaderNodes: [WeakViewNodeRef] = []

    /// How many reader bodies have been rebuilt against a resolved slot over
    /// this runtime's lifetime. A test-visible convergence witness: it must
    /// stop climbing once the layout is stable.
    internal private(set) var geometryReaderResolveCount = 0

    /// How many extra layout passes a single `updateResolvedLayout` may spend
    /// converging readers onto their slots. Each round resolves every reader
    /// the previous pass saw, so nesting costs rounds, not passes per reader.
    /// Four is deep enough for the nested readers real screens build and
    /// small enough that a body whose own size feeds its slot — a reader in
    /// an unbounded scroll proposal — gives up rather than oscillating.
    private static let geometryReaderConvergenceLimit = 4

    internal private(set) var lastPrepaintReplayCount = 0
    internal private(set) var lastDeferredOverlayReplayCount = 0
    internal private(set) var lastDeferredDrawFrameReplayCount = 0
    internal private(set) var lastDeferredDrawSceneReplayCount = 0
    let textSystem: WindowTextSystem
    private weak var hoveredNode: ViewNode?
    private weak var pressedNode: ViewNode?
    /// The node currently holding keyboard focus, if any. Read-only so
    /// presentation builders can capture and later restore focus; mutate
    /// only through `requestFocus` / focus traversal.
    public private(set) weak var focusedNode: ViewNode?
    /// Accessibility integration hook (UI Automation, Phase 2): called on the
    /// main actor after the focused node changes. Additive only — no effect
    /// on focus behavior itself.
    public var onAccessibilityFocusChanged: ((ViewNode?) -> Void)?
    private weak var hoveredScrollIndicatorNode: ViewNode?
    private weak var activeScrollIndicatorNode: ViewNode?
    private var colorAnimations: [ColorAnimationKey: ViewColorAnimation] = [:]
    private var buttonRepeatState: ButtonRepeatState?
    private var scrollDragState: ScrollDragState?
    private var nodeDragState: NodeDragState?

    // Wheel-driven scroll momentum: each entry tracks a node whose scroll
    // offset is gliding to a stop after recent wheel impulses. Velocity is in
    // logical pixels per second along the node's scroll axis (sign matches
    // scrollOffset's direction of change).
    fileprivate struct ScrollMomentumState {
        weak var node: ViewNode?
        var velocity: Double
        var lastTime: Double
    }
    private var scrollMomenta: [ObjectIdentifier: ScrollMomentumState] = [:]

    // Decay rate (per second) for wheel momentum. exp(-decay * dt) per frame;
    // 6.0 gives a ~0.115s half-life so a flick fades in under half a second.
    private static let scrollMomentumDecay: Double = 6.0
    // Translate a wheel notch into peak velocity. delta * scrollStep is the
    // immediate offset jump; multiplying by this factor adds a brief glide
    // proportional to how hard the user spun the wheel.
    private static let scrollMomentumImpulseFactor: Double = 5.0
    // Below this speed, momentum is considered finished.
    private static let scrollMomentumEpsilon: Double = 6.0
    // Spring constants for the rubber-band return when scroll over-shoots an
    // edge. Tuned to feel like a snappy macOS bounce (~150ms to settle).
    private static let scrollRubberBandStiffness: Double = 180
    private static let scrollRubberBandDamping: Double = 27
    // Cap on rubber-band excursion so a fast flick doesn't yank the content
    // far beyond the viewport.
    private static let scrollRubberBandMax: Double = 80
    // Resistance coefficient for a push against a bound the scroll is already
    // resting on. This is WebKit's `ScrollElasticityController` constant, the
    // same value AppKit's overscroll resists with: the stretch approaches
    // `dimension / c` asymptotically, tracks the push 1:1 for the first few
    // pixels, and gives back progressively less the harder the user leans on
    // it. Without a resistance term a single three-line notch would jump
    // straight to the 80pt cap and the bounce would read as a lurch.
    nonisolated static let scrollRubberBandStretchCoefficient: Double = 0.55

    /// WebKit/AppKit overscroll stretch: how far a refused push of `distance`
    /// actually moves the content, against a viewport of `dimension`.
    ///
    /// `(1 - 1/(d·c/D + 1)) · D/c` — unit slope at d = 0, asymptotic to D/c.
    nonisolated static func rubberBandStretch(
        forRefusedDistance distance: Double,
        viewportDimension dimension: Double
    ) -> Double {
        guard dimension > 0 else { return 0 }
        let coefficient = scrollRubberBandStretchCoefficient
        let magnitude = abs(distance)
        let stretch = (1.0 - (1.0 / (magnitude * coefficient / dimension + 1.0))) * dimension / coefficient
        return distance < 0 ? -stretch : stretch
    }

    /// Answers a wheel push against a bound the scroll is already sitting on:
    /// the refused travel becomes visible overshoot, and a zero-velocity
    /// momentum entry hands it to the spring branch of `tickScrollMomenta`,
    /// which is what springs it back. Nothing else in the runtime could reach
    /// that branch from rest.
    fileprivate func beginEdgeRubberBand(for node: ViewNode, refusedOffsetDelta: Double) {
        guard node.isScrollable, refusedOffsetDelta != 0 else {
            return
        }

        let dimension = node.scrollAxis == .vertical ? node.resolvedFrame.size.height : node.resolvedFrame.size.width
        let stretch = Self.rubberBandStretch(forRefusedDistance: refusedOffsetDelta, viewportDimension: dimension)
        guard stretch != 0 else {
            return
        }

        let key = ObjectIdentifier(node)
        // A second push while the band is still out adds to the excursion
        // rather than restarting it, so holding the wheel down leans further
        // in instead of stuttering.
        let combined = node.scrollOvershoot + stretch
        node.scrollOvershoot = max(min(combined, Self.scrollRubberBandMax), -Self.scrollRubberBandMax)
        var state = scrollMomenta[key] ?? ScrollMomentumState(node: node, velocity: 0, lastTime: clock())
        state.node = node
        state.lastTime = clock()
        scrollMomenta[key] = state
        invalidate()
    }

    // Keyboard scroll (PageUp/Down, Home, End, arrow keys) jumps `scrollOffset`
    // to its new target synchronously so external observers see the value
    // immediately, but visually we keep a lag delta that tweens to 0 over
    // ~220ms with ease-out so the viewport feels animated.
    fileprivate struct ScrollPresentedTween {
        weak var node: ViewNode?
        var startDelta: Double
        var startTime: Double
        var duration: Double
    }
    private var scrollPresentedTweens: [ObjectIdentifier: ScrollPresentedTween] = [:]
    private static let scrollKeyboardTweenDuration: Double = 0.22

    // MARK: - Overlay scroller reveal / auto-hide

    /// A scroller that has been asked to show itself and is waiting to be told
    /// to go away again.
    ///
    /// Both fields are resolved against the *animation clock* rather than the
    /// wall clock: `tickAnimations(at:)` is handed the same timestamp the
    /// colour tweens run on, and a test that drives the runtime with synthetic
    /// timestamps has to be able to run a reveal to completion. Arming the
    /// deadline on the first tick after the reveal — instead of at the call
    /// site — is what keeps the two clocks from being mixed.
    private struct ScrollIndicatorRevealState {
        weak var node: ViewNode?
        var needsReveal: Bool
        var hideDeadline: Double?
    }
    private var scrollIndicatorReveals: [ObjectIdentifier: ScrollIndicatorRevealState] = [:]
    /// How long a revealed overlay scroller stays up after the last scroll.
    /// macOS holds its scroller for about a beat before starting the fade.
    static let scrollIndicatorVisibleHold: Double = 1.0
    /// Fade in is quick; fade out is slow, the asymmetry macOS uses so a
    /// scroller answers instantly and leaves quietly.
    static let scrollIndicatorRevealDuration: Double = 0.12
    static let scrollIndicatorFadeOutDuration: Double = 0.45

    /// Brings an overlay scroller on screen and restarts its hold. Every scroll
    /// on an auto-hiding node routes here through `ViewNode.scrollOffset`.
    func revealScrollIndicator(for node: ViewNode) {
        guard node.scrollIndicatorAutoHides, node.showsScrollIndicator, node.isScrollable else {
            return
        }
        let key = ObjectIdentifier(node)
        if var state = scrollIndicatorReveals[key] {
            state.needsReveal = true
            state.hideDeadline = nil
            scrollIndicatorReveals[key] = state
        } else {
            scrollIndicatorReveals[key] = ScrollIndicatorRevealState(
                node: node, needsReveal: true, hideDeadline: nil)
        }
        invalidate()
    }

    /// `.scrollIndicatorsFlash(...)`: the same reveal, asked for by the app
    /// rather than by a scroll.
    public func flashScrollIndicator(for node: ViewNode) {
        revealScrollIndicator(for: node)
    }

    /// Runs the reveal state machine on the animation clock. Returns true only
    /// when a tween was actually started, so a scroller sitting in its hold
    /// does not bill the host for a redraw every frame.
    // MARK: - Caret blink

    /// macOS blinks `NSTextInsertionIndicator` on for about half a second and
    /// off for about half a second, fading rather than hard-toggling on
    /// recent releases. A steady caret is one of the fastest tells that a text
    /// field is not a real system control, and before this there was no blink
    /// machinery anywhere in the stack: `tickAnimations` returned false on
    /// every tick for two seconds with the field focused and the caret's alpha
    /// pinned at its build value.
    static let caretBlinkOnDuration: Double = 0.5
    static let caretBlinkOffDuration: Double = 0.5
    /// The edges are ramps, not steps.
    static let caretBlinkFadeDuration: Double = 0.1

    /// When the current blink cycle started. `nil` means no focused caret, or
    /// a caret that has just been reset and will start its cycle on the next
    /// tick. Reset — to fully on — happens on focus change, on any key the
    /// focused input handles, and whenever the caret moves, all of which macOS
    /// does too: a caret that blinked out mid-typing would be unreadable.
    private var caretBlinkCycleStart: Double?

    /// The caret under the focused node, if the focused node is a text input
    /// currently showing one.
    private func focusedCaretNode() -> ViewNode? {
        guard let focusedNode else { return nil }
        return Self.firstCaretNode(in: focusedNode)
    }

    private static func firstCaretNode(in node: ViewNode) -> ViewNode? {
        if node.isTextInputCaret { return node }
        for child in node.children {
            if let found = firstCaretNode(in: child) { return found }
        }
        return nil
    }

    /// Restarts the blink at fully on. Called from every event that moves the
    /// caret or changes what it is pointing at.
    func resetCaretBlink() {
        caretBlinkCycleStart = nil
        if let caret = focusedCaretNode(), caret.opacity != 1 {
            caret.opacity = 1
            invalidate()
        }
    }

    /// The blink phase's opacity at `elapsed` seconds into a cycle.
    static func caretBlinkOpacity(atElapsed elapsed: Double) -> Double {
        let period = caretBlinkOnDuration + caretBlinkOffDuration
        let fade = min(caretBlinkFadeDuration, min(caretBlinkOnDuration, caretBlinkOffDuration))
        let phase = elapsed.truncatingRemainder(dividingBy: period)
        if phase < caretBlinkOnDuration - fade {
            return 1
        }
        if phase < caretBlinkOnDuration {
            return 1 - (phase - (caretBlinkOnDuration - fade)) / fade
        }
        if phase < period - fade {
            return 0
        }
        return (phase - (period - fade)) / fade
    }

    private func tickCaretBlink(at timestamp: Double) -> Bool {
        guard let caret = focusedCaretNode() else {
            caretBlinkCycleStart = nil
            return false
        }
        guard let cycleStart = caretBlinkCycleStart else {
            caretBlinkCycleStart = timestamp
            if caret.opacity != 1 {
                caret.opacity = 1
                return true
            }
            return false
        }
        let opacity = Self.caretBlinkOpacity(atElapsed: max(0, timestamp - cycleStart))
        guard caret.opacity != opacity else { return false }
        caret.opacity = opacity
        return true
    }

    private func tickScrollIndicatorReveals(at timestamp: Double) -> Bool {
        guard !scrollIndicatorReveals.isEmpty else { return false }

        var didStartTween = false
        for key in Array(scrollIndicatorReveals.keys) {
            guard var state = scrollIndicatorReveals[key], let node = state.node else {
                scrollIndicatorReveals.removeValue(forKey: key)
                continue
            }

            // A thumb the pointer is on, or is dragging, is already shown at a
            // stronger tone by the hover/active path; the reveal must not pull
            // it back down to the resting one.
            let isPointerOwned = node === hoveredScrollIndicatorNode || node === activeScrollIndicatorNode

            if state.needsReveal {
                state.needsReveal = false
                // A momentum glide re-arms the reveal on every tick it moves
                // the offset. Restarting the tween each time would keep
                // resetting its start colour to wherever the fade had got to,
                // so the thumb would creep up asymptotically and never arrive.
                // Only the *deadline* is re-armed by a repeat scroll.
                let alreadyRising =
                    colorAnimations[ColorAnimationKey(node: node, property: .scrollIndicator)]?.endColor
                    == node.scrollIndicatorIdleColor
                if !isPointerOwned, !alreadyRising {
                    animateColor(
                        .scrollIndicator, of: node, to: node.scrollIndicatorIdleColor,
                        duration: Self.scrollIndicatorRevealDuration, at: timestamp)
                    didStartTween = true
                }
            }

            guard let deadline = state.hideDeadline else {
                state.hideDeadline = timestamp + Self.scrollIndicatorVisibleHold
                scrollIndicatorReveals[key] = state
                continue
            }

            guard timestamp >= deadline else {
                scrollIndicatorReveals[key] = state
                continue
            }

            scrollIndicatorReveals.removeValue(forKey: key)
            if !isPointerOwned {
                animateColor(
                    .scrollIndicator, of: node, to: node.restingScrollIndicatorColor,
                    duration: Self.scrollIndicatorFadeOutDuration, at: timestamp)
                didStartTween = true
            }
        }
        return didStartTween
    }

    /// Nodes that have been removed from the view tree but are still animating
    /// out via their removal transition. Rendered after the main tree each frame.
    public internal(set) var transitionOverlays: [ViewNode] = []

    /// Captured frame and node references for matched geometry effect processing.
    struct MatchedGeometryOldNode {
        let node: ViewNode
        let frame: Rect
    }

    internal var pendingMatchedGeometryOldNodes: [String: [String: MatchedGeometryOldNode]] = [:]
    internal var pendingMatchedGeometryCheck = false

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

        let ownsRenderPass = beginRenderPass()
        defer { endRenderPass(ownsPass: ownsRenderPass) }
        updateResolvedLayout()
        applyMatchedGeometryAnimations()

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

        // Render removal-transition overlays on top of the main tree.
        for overlay in transitionOverlays {
            var overlayReplayCount = 0
            overlay.appendCommands(
                into: &commands,
                parentOrigin: .zero,
                inheritedClip: nil,
                previousRenderedFrame: previousFrame,
                displayScale: displayScale,
                replayCount: &overlayReplayCount
            )
            replayCount += overlayReplayCount
        }

        let frame = RenderFrame(clearColor: clearColor, commands: commands)
        lastFrameReplayCount = replayCount
        lastDeferredDrawFrameReplayCount = deferredDrawReplayCount
        lastDeferredDrawSceneReplayCount = 0
        cachedFrame = frame
        cachedScene = nil
        cachedSceneAtlasGeneration = nil
        contentRevision &+= 1
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return frame
    }

    /// Render the current view tree as a GPUIScene for batch rendering.
    public func renderScene(at timestamp: Double = 0) -> GPUIScene {
        // WS-14's stale-UV rule, applied to the one holder that had escaped it.
        // `shippable` staples the *current* shared atlas onto a scene whose
        // glyph quads were addressed against an earlier one, and the atlas is
        // process-wide: a clean, unchanged window that never repaints would
        // have shipped pre-recovery UVs against a post-recovery atlas forever,
        // because a clear triggered by some *other* window leaves nothing in
        // this runtime dirty. Dropping the cache forces a real paint — which
        // also drops the replay source, since replayed primitives carry the
        // same dead UVs.
        if let generation = cachedSceneAtlasGeneration, generation != NativeGlyphAtlas.shared.atlasGeneration {
            cachedScene = nil
            cachedSceneAtlasGeneration = nil
        }

        if let cachedScene, !isDirty {
            sceneCacheHitCount &+= 1
            lastSceneReplayCount = 0
            lastLayoutReuseCount = 0
            lastMeasureReuseCount = 0
            lastPrepaintReplayCount = 0
            lastDeferredOverlayReplayCount = 0
            lastDeferredDrawFrameReplayCount = 0
            lastDeferredDrawSceneReplayCount = 0
            return shippable(cachedScene)
        }

        if let interval = minimumFrameInterval, timestamp > 0, lastRenderTime > 0 {
            let elapsed = timestamp - lastRenderTime
            if elapsed < interval, let cachedScene {
                sceneCacheHitCount &+= 1
                lastSceneReplayCount = 0
                lastLayoutReuseCount = 0
                lastMeasureReuseCount = 0
                lastPrepaintReplayCount = 0
                lastDeferredOverlayReplayCount = 0
                lastDeferredDrawFrameReplayCount = 0
                lastDeferredDrawSceneReplayCount = 0
                return shippable(cachedScene)
            }
        }

        let ownsRenderPass = beginRenderPass()
        defer { endRenderPass(ownsPass: ownsRenderPass) }
        let phaseStartedAt = collectsPhaseTimings ? Win32Window.currentTimestampSeconds() : 0
        updateResolvedLayout()
        applyMatchedGeometryAnimations()
        let layoutEndedAt = collectsPhaseTimings ? Win32Window.currentTimestampSeconds() : 0

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
            deferredReplayCount: &deferredDrawReplayCount,
            overlays: transitionOverlays
        )
        prepaintState.deferredDraws = deferredDraws
        if collectsPhaseTimings {
            let paintEndedAt = Win32Window.currentTimestampSeconds()
            lastLayoutSeconds = layoutEndedAt - phaseStartedAt
            lastPaintSeconds = paintEndedAt - layoutEndedAt
        }

        // The retained copy drops the atlases on purpose: it outlives the
        // frame, and a snapshot holding the atlas `Data` across frames turns
        // the next glyph write into a copy of the whole 2048² buffer. It is a
        // replay source, and replay reads primitives, never atlases.
        var cachedSceneCopy = scene
        cachedSceneCopy.glyphAtlas = nil
        cachedSceneCopy.pixelGlyphAtlas = nil
        sceneRebuildCount &+= 1
        contentRevision &+= 1
        lastSceneReplayCount = replayCount
        lastDeferredDrawSceneReplayCount = deferredDrawReplayCount
        lastDeferredDrawFrameReplayCount = 0
        lastScenePaintMetrics = scene.paintMetrics
        cachedScene = cachedSceneCopy
        cachedSceneAtlasGeneration = cachedSceneCopy.usesGlyphs ? NativeGlyphAtlas.shared.atlasGeneration : nil
        cachedFrame = nil
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return scene
    }

    /// A cached scene made shippable again.
    ///
    /// `cachedScene` is stored without its atlases (see above), and both
    /// early returns above hand it straight to the host as this frame's
    /// scene. A frame that ships has to carry the atlas its glyph quads
    /// address, or every consumer without an atlas texture of its own draws
    /// blank text where the user sees text.
    private func shippable(_ scene: GPUIScene) -> GPUIScene {
        var shipped = scene
        ScenePainter.attachCachedGlyphAtlases(to: &shipped)
        return shipped
    }

    public func pointerMoved(to point: Point) {
        if let dragState = scrollDragState {
            guard let node = dragState.node else {
                scrollDragState = nil
                updateScrollIndicatorHover(to: nil)
                return
            }

            let delta =
                dragState.axis == .vertical ? point.y - dragState.startPoint.y : point.x - dragState.startPoint.x
            _ = node.applyScrollIndicatorDrag(
                startOffset: dragState.startOffset, delta: delta, travel: dragState.track.travel)
            updateScrollIndicatorHover(to: ScrollIndicatorHit(node: node, track: dragState.track))
            return
        }

        if var dragState = nodeDragState {
            guard let node = dragState.node else {
                nodeDragState = nil
                return
            }

            dragState.lastPoint = point
            nodeDragState = dragState
            let delta = Point(x: point.x - dragState.startPoint.x, y: point.y - dragState.startPoint.y)
            node.onDragChange?(point, delta)
            return
        }

        let hitNode = hitTest(at: point)
        let interactionNode = pointerInteractionTarget(from: hitNode, at: point)
        updateHoverTarget(to: interactionNode)
        interactionNode?.onPointerMove?(point)
        updateScrollIndicatorHover(to: scrollIndicatorHit(at: point))
    }

    public func pointerExitedWindow() {
        updateHoverTarget(to: nil)
        if scrollDragState == nil {
            updateScrollIndicatorHover(to: nil)
        }
    }

    /// Cancels an interaction whose native pointer capture was stolen or
    /// explicitly cancelled. Losing capture is never a successful release:
    /// controls leave their pressed state, repeat stops, and a dragged slider
    /// receives its editing-ended callback without activating any control.
    public func pointerCancelled() {
        let cancelledPressedNode = pressedNode
        let cancelledNodeDrag = nodeDragState
        let cancelledDragNode = cancelledNodeDrag?.node
        let cancelledScrollIndicatorNode = activeScrollIndicatorNode

        pressedNode = nil
        buttonRepeatState = nil
        nodeDragState = nil
        scrollDragState = nil
        activeScrollIndicatorNode = nil

        if let cancelledNodeDrag, let cancelledDragNode {
            let delta = Point(
                x: cancelledNodeDrag.lastPoint.x - cancelledNodeDrag.startPoint.x,
                y: cancelledNodeDrag.lastPoint.y - cancelledNodeDrag.startPoint.y
            )
            cancelledDragNode.onDragEnd?(cancelledNodeDrag.lastPoint, delta)
        }

        updateHoverTarget(to: nil)
        updateScrollIndicatorHover(to: nil)

        if let cancelledScrollIndicatorNode {
            animateColor(
                .scrollIndicator,
                of: cancelledScrollIndicatorNode,
                to: cancelledScrollIndicatorNode.restingScrollIndicatorColor,
                duration: 0.12,
                at: clock()
            )
        }

        cancelledPressedNode?.onPointerUpOutside?()
        applyInteractionChrome(to: cancelledPressedNode)
    }

    /// `delta` is in *lines* (the host has already multiplied the notch by
    /// `SPI_GETWHEELSCROLLLINES`), so `scrollStep` is a per-line distance.
    ///
    /// `source` decides whether the scroll glides. Momentum is a gesture-device
    /// behaviour — AppKit populates `NSEvent.momentumPhase` for a trackpad or
    /// Magic Mouse and never for a click wheel — and this stack was giving the
    /// trackpad calibration to every wheel event: one line of wheel input
    /// travelled 117.7px, a 64px step plus 53.7px of glide over two thirds of
    /// a second. The decay constants are right where they apply; what was
    /// wrong was applying them to a detent.
    public func mouseWheel(
        at point: Point,
        delta: Double,
        axis: ScrollAxis? = nil,
        source: ScrollInputSource = .wheelNotch
    ) {
        let scrollTarget = scrollTarget(at: point, axis: axis) ?? nearestScrollableNode(from: hoveredNode, axis: axis)
        guard let scrollableNode = scrollTarget else {
            return
        }

        cancelScrollPresentedTween(for: scrollableNode)
        let refusedDelta = scrollableNode.refusedMouseWheelDelta(delta)
        let appliedDelta = scrollableNode.applyMouseWheelDelta(delta)
        if appliedDelta != 0 {
            updateHoverTarget(to: pointerInteractionTarget(from: hitTest(at: point), at: point))
            if source == .precise {
                seedScrollMomentum(for: scrollableNode, wheelDelta: delta, appliedOffsetDelta: appliedDelta)
            }
            return
        }

        // Nothing moved. Either the node has nothing to scroll — in which case
        // `refusedMouseWheelDelta` is 0 and there is genuinely nothing to say —
        // or the user is pushing against a bound they are already sitting on.
        // The rubber band used to be unreachable from there: the spring branch
        // in `tickScrollMomenta` only ran when an *already gliding* scroll ran
        // into an edge, so a push against a stationary top produced no bounce,
        // no overshoot and not even an indicator flash. AppKit bounces on a
        // direct edge push, and shows the scroller for an input it cannot act
        // on so the user can see where they are.
        guard refusedDelta != 0 else {
            return
        }

        updateHoverTarget(to: pointerInteractionTarget(from: hitTest(at: point), at: point))
        beginEdgeRubberBand(for: scrollableNode, refusedOffsetDelta: refusedDelta)
        revealScrollIndicator(for: scrollableNode)
    }

    public func pointerDown(at point: Point) {
        if let scrollIndicatorHit = scrollIndicatorHit(at: point) {
            cancelScrollMomentum(for: scrollIndicatorHit.node)
            cancelScrollPresentedTween(for: scrollIndicatorHit.node)
            scrollDragState = ScrollDragState(
                node: scrollIndicatorHit.node, axis: scrollIndicatorHit.track.axis, startPoint: point,
                startOffset: scrollIndicatorHit.node.scrollOffset, track: scrollIndicatorHit.track)
            activeScrollIndicatorNode = scrollIndicatorHit.node
            animateColor(
                .scrollIndicator, of: scrollIndicatorHit.node, to: scrollIndicatorHit.node.scrollIndicatorActiveColor,
                duration: 0.10, at: clock())
            return
        }

        let hitNode = hitTest(at: point)
        if let draggableNode = nearestDraggableNode(from: hitNode) {
            nodeDragState = NodeDragState(node: draggableNode, startPoint: point, lastPoint: point)
            // Dragging is still a pointer press: focus belongs to the same
            // nearest focusable control as an ordinary click. Otherwise
            // sliders keep the previous field's caret/focus ring active while
            // their own focused chrome and accessibility focus never appear.
            updateFocusTarget(to: nearestFocusableNode(from: hitNode))
            draggableNode.onDragStart?(point)
            updateHoverTarget(to: pointerInteractionTarget(from: hitNode, at: point))
            return
        }

        let hoverNode = pointerInteractionTarget(from: hitNode, at: point)
        let interactionNode = pointerInteractionTarget(from: hitNode, at: point, routing: .activation)
        updateFocusTarget(to: nearestFocusableNode(from: hitNode))
        updateHoverTarget(to: hoverNode)
        pressedNode = interactionNode
        interactionNode?.onPointerDown?()
        applyInteractionChrome(to: interactionNode)
        beginButtonRepeatIfNeeded(for: interactionNode)
    }

    public func pointerUp(at point: Point) {
        if let dragState = scrollDragState {
            scrollDragState = nil
            activeScrollIndicatorNode = nil
            let nextIndicatorHit = scrollIndicatorHit(at: point)
            updateScrollIndicatorHover(to: nextIndicatorHit)

            if let node = dragState.node {
                let targetColor =
                    nextIndicatorHit?.node === node
                    ? node.scrollIndicatorHoverColor : node.restingScrollIndicatorColor
                animateColor(
                    .scrollIndicator, of: node, to: targetColor, duration: 0.12,
                    at: clock())
            }
            return
        }

        if let dragState = nodeDragState {
            nodeDragState = nil
            if let node = dragState.node {
                let delta = Point(x: point.x - dragState.startPoint.x, y: point.y - dragState.startPoint.y)
                node.onDragEnd?(point, delta)
            }
            let hitNode = hitTest(at: point)
            updateHoverTarget(to: pointerInteractionTarget(from: hitNode, at: point))
            updateScrollIndicatorHover(to: scrollIndicatorHit(at: point))
            return
        }

        let hitNode = hitTest(at: point)
        let hoverNode = pointerInteractionTarget(from: hitNode, at: point)
        let interactionNode = pointerInteractionTarget(from: hitNode, at: point, routing: .activation)

        if let pressedNode {
            let didRepeat = endButtonRepeat(for: pressedNode)
            // The press ends *before* the action runs. AppKit releases the
            // cell highlight on mouseUp and only then sends the action, and
            // the ordering matters here for a second reason: the action is
            // what changes `@State`, which rebuilds the tree — and the rebuild
            // ends in `restoreInteractionChrome`, which has to find the press
            // already lifted or it restores the control to its held-down fill.
            self.pressedNode = nil
            applyInteractionChrome(to: pressedNode)
            if pressedNode === interactionNode {
                pressedNode.onPointerUpInside?()
                pressedNode.onPointerUpInsideAt?(point)
                if !didRepeat {
                    pressedNode.onActivate?()
                }
            } else {
                pressedNode.onPointerUpOutside?()
            }
        }

        self.pressedNode = nil
        updateHoverTarget(to: hoverNode)
    }

    public func contextClick(at point: Point) {
        let hitNode = hitTest(at: point)
        updateHoverTarget(to: pointerInteractionTarget(from: hitNode, at: point))
        guard let contextNode = nearestContextMenuNode(from: hitNode) else {
            return
        }

        contextNode.onContextMenu?(point)
    }

    /// Delivers an OS file drop (Explorer files via `WM_DROPFILES`, forwarded
    /// by the window host) to the topmost drop-accepting node under `point`.
    ///
    /// Payload mapping: the dropped file URLs are delivered as the raw `[Any]`
    /// items (`URL` values). A node with `onValidateDrop` gates the drop; the
    /// payload is then performed through `onDropPayloads` (preferred) or
    /// `onDropProviders`. The WinSwiftUI `onDrop(of:perform:)` modifier wraps
    /// `URL` items in `NSItemProvider(contentsOf:)`, so OS file drops reach
    /// the standard SwiftUI-shaped handler. `onDropRows` is deliberately not
    /// used: its row index is list-relative and meaningless for a
    /// window-level drop. Returns true when a node accepted the drop.
    @discardableResult
    public func performFileDrop(_ fileURLs: [URL], at point: Point) -> Bool {
        guard !fileURLs.isEmpty else {
            return false
        }

        let items: [Any] = fileURLs.map { $0 as Any }
        let hitNode = hitTest(at: point)
        guard
            let target = node(
                for: nearestDispatchIndex(
                    from: dispatchIndex(for: hitNode),
                    where: { candidate in
                        candidate.isDropDestinationEnabled
                            && Self.acceptsFileDrop(candidate)
                            && (candidate.onValidateDrop != nil || candidate.onDropPayloads != nil
                                || candidate.onDropProviders != nil)
                    }
                )
            )
        else {
            return false
        }

        if let validate = target.onValidateDrop, !validate(items, point) {
            return false
        }

        var handled = false
        if let payloads = target.onDropPayloads {
            handled = payloads(items, point)
        }
        if !handled, let providers = target.onDropProviders {
            handled = providers(items, point)
        }
        return handled
    }

    /// Window-level drops always carry file URLs, so a destination whose
    /// accepted-content-type list is non-empty must opt into file URLs
    /// (`public.file-url` or the broader `public.url`).
    private static func acceptsFileDrop(_ node: ViewNode) -> Bool {
        let accepted = node.dropAcceptedContentTypes
        guard !accepted.isEmpty else {
            return true
        }
        return accepted.contains(UTType.fileURL.identifier) || accepted.contains(UTType.url.identifier)
    }

    public func keyDown(_ event: KeyboardEvent) {
        // Typing restarts the blink at fully on. macOS does the same, and for
        // the same reason: a caret that blinked out on the keystroke that
        // moved it would be unreadable exactly when it matters.
        resetCaretBlink()
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
            let focusedBeforeEscape = focusedNode
            focusedNode?.onKeyDown?(event)
            // A presentation's Escape-dismiss may restore focus to another
            // node; only clear focus when nothing reclaimed it.
            if focusedNode === focusedBeforeEscape {
                updateFocusTarget(to: nil)
            }
            return

        default:
            break
        }

        if let key = event.key,
            key == .upArrow || key == .downArrow,
            event.modifiers.isEmpty,
            focusedNode?.interceptsVerticalArrowKeys == true
        {
            focusedNode?.onKeyDown?(event)
            return
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

    /// Routes an IME composition event to the focused text input. Nodes
    /// without an `onIMEComposition` handler ignore it; when no IME is
    /// active this is never called and keyboard input flows through
    /// `keyDown` exactly as before.
    public func imeComposition(_ event: IMECompositionEvent) {
        focusedNode?.onIMEComposition?(event)
    }

    /// Caret rectangle of the focused text input in root (logical)
    /// coordinates, used to position the OS IME candidate/composition
    /// window. `nil` when the focused node is not a text input or cannot
    /// report a caret.
    public var focusedTextInputCaretRect: Rect? {
        focusedNode?.textInputCaretRectProvider?()
    }

    public func requestFocus(_ node: ViewNode?) {
        guard let node else {
            updateFocusTarget(to: nil)
            return
        }

        guard node.isFocusable, !Self.hasHiddenAncestor(node) else {
            return
        }

        updateFocusTarget(to: node)
    }

    /// Schedules one callback after the next complete retained layout, shared
    /// by scene and frame rendering. Reusing a key replaces the pending
    /// callback without changing its position in the original request order.
    ///
    /// Callbacks run once, after geometry-reader convergence and before
    /// prepaint. A callback scheduled from inside another callback belongs to
    /// the next pass; this keeps re-entrant application code from turning one
    /// frame into an unbounded callback loop.
    public func scheduleAfterLayout(
        key: String,
        perform action: @escaping @MainActor () -> Void
    ) {
        if pendingAfterLayoutActions.updateValue(action, forKey: key) == nil {
            pendingAfterLayoutActionKeys.append(key)
        }
        invalidate(.layout)
    }

    /// Moves the nearest retained scroll container until `descendant` is
    /// visible. Explicit anchor coordinates align the same fractional point
    /// on the target and viewport; without one, only the smallest movement
    /// needed to reveal the target is applied.
    ///
    /// Lazy stacks assign every immediate row its real frame even when the
    /// row's own subtree has never been laid out. If an ID lives below such a
    /// deferred row, the row is the authoritative target until scrolling
    /// brings its descendants into the active virtualization window.
    ///
    /// Returns false before the enclosing scroll container has completed a
    /// layout pass so callers can keep pre-layout requests queued. A valid
    /// request whose target is already visible returns true without inventing
    /// an offset change.
    @discardableResult
    public func scrollToDescendant(
        _ descendant: ViewNode,
        anchorX: Double? = nil,
        anchorY: Double? = nil
    ) -> Bool {
        guard descendant.runtime === self, layoutPassID != 0, !Self.hasHiddenAncestor(descendant) else {
            return false
        }

        var target = descendant
        var candidate: ViewNode? = descendant
        var scrollContainer: ViewNode?
        var depth = 0
        while let node = candidate, depth < ViewNode.maximumTraversalDepth {
            if node.isLayoutDeferredByVirtualization {
                target = node
            }
            if node.scrollAxis != nil {
                scrollContainer = node
                break
            }
            candidate = node.parent
            depth += 1
        }

        guard let scrollContainer, let axis = scrollContainer.scrollAxis,
            !isLayoutInProgress,
            scrollContainer.cachedLayoutKey != nil,
            scrollContainer.pendingLayoutKey == nil
        else {
            return false
        }

        let anchor = axis == .horizontal ? anchorX : anchorY
        guard anchor?.isFinite ?? true else {
            return false
        }

        var targetFrame = target.resolvedFrame
        var ancestor = target.parent
        depth = 0
        while let node = ancestor, node !== scrollContainer,
            depth < ViewNode.maximumTraversalDepth
        {
            targetFrame = targetFrame.offsetBy(
                dx: node.resolvedFrame.origin.x,
                dy: node.resolvedFrame.origin.y
            )
            ancestor = node.parent
            depth += 1
        }
        guard ancestor === scrollContainer else {
            return false
        }

        let viewportExtent: Double
        let targetStart: Double
        let targetExtent: Double
        switch axis {
        case .horizontal:
            viewportExtent = scrollContainer.resolvedFrame.size.width
            targetStart = targetFrame.minX
            targetExtent = targetFrame.size.width
        case .vertical:
            viewportExtent = scrollContainer.resolvedFrame.size.height
            targetStart = targetFrame.minY
            targetExtent = targetFrame.size.height
        }
        guard viewportExtent > 0, viewportExtent.isFinite,
            targetStart.isFinite, targetExtent > 0, targetExtent.isFinite
        else {
            return false
        }

        let requestedOffset: Double
        if let anchor {
            let boundedAnchor = min(max(anchor, 0), 1)
            requestedOffset = targetStart + targetExtent * boundedAnchor - viewportExtent * boundedAnchor
        } else if targetStart < scrollContainer.scrollOffset {
            requestedOffset = targetStart
        } else if targetStart + targetExtent > scrollContainer.scrollOffset + viewportExtent {
            requestedOffset = targetStart + targetExtent - viewportExtent
        } else {
            requestedOffset = scrollContainer.scrollOffset
        }

        cancelScrollMomentum(for: scrollContainer)
        cancelScrollPresentedTween(for: scrollContainer)
        _ = scrollContainer.setScrollOffset(requestedOffset)

        // The next explicit request for a container supersedes any older
        // deferred correction. Once its oversized lazy row is realized, an
        // ID living deeper in that row needs one bounded second alignment to
        // its own now-real frame rather than the row's coarse fallback.
        pendingPreciseScrollAlignments.removeAll {
            $0.container == nil || $0.target == nil || $0.container === scrollContainer
        }
        if target !== descendant {
            pendingPreciseScrollAlignments.append(
                PendingPreciseScrollAlignment(
                    target: descendant,
                    container: scrollContainer,
                    anchorX: anchorX,
                    anchorY: anchorY,
                    expectedOffset: scrollContainer.scrollOffset
                )
            )
        }
        return true
    }

    /// A retained subtree that disappears cannot keep receiving keyboard,
    /// hover, repeat, or drag events merely because application code still
    /// holds one of its nodes alive. This also emits the matching focus/UIA
    /// exit while the removed node is still available to its callbacks.
    fileprivate func releaseInteractionTargets(in subtree: ViewNode) {
        let ownsPointerInteraction =
            Self.isInteractionTarget(pressedNode, within: subtree)
            || Self.isInteractionTarget(nodeDragState?.node, within: subtree)
            || Self.isInteractionTarget(scrollDragState?.node, within: subtree)
            || Self.isInteractionTarget(activeScrollIndicatorNode, within: subtree)

        if ownsPointerInteraction {
            pointerCancelled()
        } else {
            if Self.isInteractionTarget(hoveredNode, within: subtree) {
                updateHoverTarget(to: nil)
            }
            if Self.isInteractionTarget(hoveredScrollIndicatorNode, within: subtree) {
                updateScrollIndicatorHover(to: nil)
            }
        }

        if Self.isInteractionTarget(focusedNode, within: subtree) {
            updateFocusTarget(to: nil)
        }
    }

    private static func isInteractionTarget(_ candidate: ViewNode?, within subtree: ViewNode) -> Bool {
        var current = candidate
        while let node = current {
            if node === subtree {
                return true
            }
            current = node.parent
        }
        return false
    }

    private static func hasHiddenAncestor(_ node: ViewNode) -> Bool {
        var current: ViewNode? = node
        while let candidate = current {
            if candidate.isHidden {
                return true
            }
            current = candidate.parent
        }
        return false
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

        guard hoveredNodeActivates(node) else {
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

    /// Hover-only descendants keep their own callbacks while their enclosing
    /// button owns the press, so repeat must accept the same passive
    /// activation-owner chain rather than requiring identical hovered nodes.
    private func hoveredNodeActivates(_ owner: ViewNode) -> Bool {
        var candidate = hoveredNode
        while let current = candidate {
            if current === owner {
                return true
            }
            guard Self.isPassivePointerContent(current, routing: .activation) else {
                return false
            }
            candidate = current.parent
        }
        return false
    }

    /// The curve every colour cross-fade runs on unless a caller names another.
    ///
    /// AppKit's implicit property changes run on `kCAMediaTimingFunctionEase
    /// InEaseOut` and `NSAnimationContext` inherits it, so a hover, focus or
    /// press cross-fade on macOS is eased at both ends. This stack's colour
    /// tweens used to be a straight ramp — measurably so: a hover-in sampled
    /// every 10ms stepped by exactly 0.00278 alpha from the first frame to the
    /// last. The per-property path (`AnimationState`) already eased, so the
    /// runtime's two animation mechanisms disagreed about curve.
    ///
    /// `.easeInOut` here is the quadratic form `AnimationState` uses rather
    /// than the cubic bezier `(0.42, 0, 0.58, 1)` CoreAnimation evaluates; the
    /// two differ by at most 0.012 of progress (at t ≈ 0.60), which on the
    /// widest colour tween in the stack is under half a step of 8-bit alpha.
    /// Matching the other mechanism exactly is worth more than matching the
    /// bezier to the third decimal.
    public static let defaultColorAnimationEasing: AnimationEasing = .easeInOut

    public func animateBackgroundColor(
        of node: ViewNode, to targetColor: Color, duration: Double = 0.18, at timestamp: Double,
        easing: AnimationEasing = RetainedViewRuntime.defaultColorAnimationEasing
    ) {
        animateColor(.background, of: node, to: targetColor, duration: duration, at: timestamp, easing: easing)
    }

    public func animateColor(
        _ property: AnimatedColorProperty, of node: ViewNode, to targetColor: Color, duration: Double = 0.18,
        at timestamp: Double, easing: AnimationEasing = RetainedViewRuntime.defaultColorAnimationEasing
    ) {
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
            duration: duration,
            easing: easing
        )
        invalidate()
    }

    @discardableResult
    public func tickAnimations(at timestamp: Double) -> Bool {
        // First, because a due rebuild produces the tree the rest of this tick
        // advances — a phase boundary that landed this frame should be animated
        // from this frame, not from the next one.
        let didRunDeferredRebuild = tickDeferredRebuilds(at: timestamp)
        sweepAnimatingNodes()
        let didAdvanceButtonRepeat = advanceButtonRepeat(at: timestamp)
        let didAdvanceScrollMomenta = tickScrollMomenta(at: timestamp)
        let didAdvanceScrollPresentedTweens = tickScrollPresentedTweens(at: timestamp)
        // Before the colour tweens are advanced below, so a reveal or a fade
        // started this tick makes progress on this tick rather than the next.
        let didStartScrollIndicatorTween = tickScrollIndicatorReveals(at: timestamp)
        let didBlinkCaret = tickCaretBlink(at: timestamp)
        let didAdvancePropertyAnimations = tickPropertyAnimations(node: root, at: timestamp)

        var didAdvanceOverlayAnimations = false
        var completedOverlays: [ViewNode] = []
        for overlay in transitionOverlays {
            if tickPropertyAnimations(node: overlay, at: timestamp) {
                didAdvanceOverlayAnimations = true
            }
            if overlay.animationStates.isEmpty {
                completedOverlays.append(overlay)
            }
        }
        for overlay in completedOverlays {
            overlay.isRemovalOverlay = false
            overlay.markSubtreeDisappeared()
            if let index = transitionOverlays.firstIndex(where: { $0 === overlay }) {
                transitionOverlays.remove(at: index)
            }
        }
        if !completedOverlays.isEmpty {
            invalidate()
        }

        guard !colorAnimations.isEmpty else {
            return didRunDeferredRebuild || didAdvanceButtonRepeat || didAdvanceScrollMomenta
                || didAdvanceScrollPresentedTweens || didStartScrollIndicatorTween || didBlinkCaret
                || didAdvancePropertyAnimations || didAdvanceOverlayAnimations || !completedOverlays.isEmpty
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

            // Retire on elapsed time, paint on the curve: an eased value can
            // reach 1 before the tween is over (and, for a spring, pass it).
            let fraction = animation.elapsedFraction(at: timestamp)
            let progress = animation.easing.apply(fraction)
            let nextColor = animation.startColor.interpolated(to: animation.endColor, progress: progress)
            if node.color(for: animation.property) != nextColor {
                node.setColor(nextColor, for: animation.property)
                didUpdateAnyAnimation = true
            }

            if fraction >= 1 {
                node.setColor(animation.endColor, for: animation.property)
                colorAnimations.removeValue(forKey: animationKey)
            }
        }

        return didUpdateAnyAnimation || didRunDeferredRebuild || didAdvanceButtonRepeat
            || didAdvanceScrollMomenta || didAdvanceScrollPresentedTweens || didStartScrollIndicatorTween
            || didBlinkCaret || didAdvancePropertyAnimations || didAdvanceOverlayAnimations
            || !completedOverlays.isEmpty
    }

    // MARK: - Scroll Momentum

    /// Seeds (or boosts) wheel-driven scroll momentum on `node` after an
    /// immediate offset jump of `appliedOffsetDelta`. `wheelDelta` is the raw
    /// notch count from the platform; we map that to a velocity in offset
    /// units per second so subsequent ticks can glide the scroll to a stop.
    fileprivate func seedScrollMomentum(for node: ViewNode, wheelDelta: Double, appliedOffsetDelta: Double) {
        guard node.isScrollable, appliedOffsetDelta != 0 else {
            return
        }

        // Sign: applyMouseWheelDelta moves offset by `-wheelDelta * scrollStep`,
        // so positive wheelDelta produces a negative velocity (offset shrinks).
        // Use the actual applied delta so we don't accumulate velocity against
        // a clamped edge.
        let impulse = appliedOffsetDelta * Self.scrollMomentumImpulseFactor
        let key = ObjectIdentifier(node)
        var state = scrollMomenta[key] ?? ScrollMomentumState(node: node, velocity: 0, lastTime: 0)

        // If the new impulse opposes existing velocity, replace rather than
        // sum — feels more natural when the user reverses direction.
        if state.velocity != 0, (state.velocity > 0) != (impulse > 0) {
            state.velocity = impulse
        } else {
            state.velocity += impulse
        }
        state.node = node
        state.lastTime = clock()
        scrollMomenta[key] = state
        invalidate()
    }

    /// Cancels any pending wheel momentum on `node`. Called when the user
    /// takes manual control (keyboard scroll, indicator drag) so momentum
    /// doesn't fight the user input. Also zeros any rubber-band overshoot so
    /// content snaps back to the clamped offset instead of staying overscrolled.
    fileprivate func cancelScrollMomentum(for node: ViewNode) {
        scrollMomenta.removeValue(forKey: ObjectIdentifier(node))
        if node.scrollOvershoot != 0 {
            node.scrollOvershoot = 0
            invalidate()
        }
    }

    /// Drops any in-flight keyboard-scroll tween for `node` so the next
    /// imperative offset change isn't double-counted with stale lag.
    fileprivate func cancelScrollPresentedTween(for node: ViewNode) {
        if scrollPresentedTweens.removeValue(forKey: ObjectIdentifier(node)) != nil {
            node.scrollPresentedDelta = 0
            invalidate()
        }
    }

    private func tickScrollMomenta(at timestamp: Double) -> Bool {
        guard !scrollMomenta.isEmpty else { return false }

        var didUpdate = false
        for key in Array(scrollMomenta.keys) {
            guard var state = scrollMomenta[key] else { continue }
            guard let node = state.node, node.isScrollable else {
                scrollMomenta.removeValue(forKey: key)
                continue
            }

            let dt = max(0, timestamp - state.lastTime)
            // Clamp very long gaps (window inactive, etc.) so momentum doesn't
            // jump forward by a huge amount on the next active frame.
            let effectiveDt = min(dt, 0.05)
            guard effectiveDt > 0 else {
                state.lastTime = timestamp
                scrollMomenta[key] = state
                continue
            }

            if node.scrollOvershoot != 0 {
                // Rubber-band phase: critically-damped spring pulls overshoot
                // back to 0. F = -k*x - c*v with k ≈ 180, c ≈ 27 (just below
                // critical damping so the return feels lively but doesn't
                // visibly oscillate).
                let stiffness = Self.scrollRubberBandStiffness
                let damping = Self.scrollRubberBandDamping
                let force = -stiffness * node.scrollOvershoot - damping * state.velocity
                state.velocity += force * effectiveDt
                let nextOvershoot = node.scrollOvershoot + state.velocity * effectiveDt
                // Snap to zero once the spring has settled and would otherwise
                // oscillate across the bound.
                let crossedZero = (nextOvershoot > 0) != (node.scrollOvershoot > 0)
                if crossedZero
                    || (abs(nextOvershoot) < Self.scrollMomentumEpsilon * 0.1
                        && abs(state.velocity) < Self.scrollMomentumEpsilon)
                {
                    node.scrollOvershoot = 0
                    scrollMomenta.removeValue(forKey: key)
                    didUpdate = true
                    continue
                }
                node.scrollOvershoot = nextOvershoot
                state.lastTime = timestamp
                scrollMomenta[key] = state
                didUpdate = true
                continue
            }

            let previousOffset = node.scrollOffset
            let proposedOffset = previousOffset + state.velocity * effectiveDt
            let nextOffset = node.clampedScrollOffset(for: proposedOffset)
            if nextOffset != previousOffset {
                node.scrollOffset = nextOffset
                didUpdate = true
            }

            // If clamping ate the proposed movement (hit an edge), convert
            // the leftover travel into overshoot and let the rubber-band
            // branch above spring it back next tick.
            if proposedOffset != nextOffset {
                let excess = proposedOffset - nextOffset
                let cappedExcess = max(min(excess, Self.scrollRubberBandMax), -Self.scrollRubberBandMax)
                node.scrollOvershoot = cappedExcess
                state.lastTime = timestamp
                scrollMomenta[key] = state
                didUpdate = true
                continue
            }

            state.velocity *= exp(-Self.scrollMomentumDecay * effectiveDt)
            state.lastTime = timestamp
            if abs(state.velocity) < Self.scrollMomentumEpsilon {
                scrollMomenta.removeValue(forKey: key)
            } else {
                scrollMomenta[key] = state
            }
        }

        if didUpdate {
            invalidate()
        }
        return didUpdate
    }

    // MARK: - Matched Geometry Effect

    func recordMatchedGeometryFrames() {
        pendingMatchedGeometryOldNodes.removeAll()
        collectMatchedGeometryFrames(from: root)
    }

    private func collectMatchedGeometryFrames(from node: ViewNode) {
        if let effect = node.matchedGeometryEffect {
            pendingMatchedGeometryOldNodes[effect.namespaceID, default: [:]][effect.elementID] = MatchedGeometryOldNode(
                node: node,
                frame: node.resolvedFrame
            )
        }
        for child in node.children {
            collectMatchedGeometryFrames(from: child)
        }
    }

    func applyMatchedGeometryAnimations() {
        guard pendingMatchedGeometryCheck, !pendingMatchedGeometryOldNodes.isEmpty else {
            pendingMatchedGeometryCheck = false
            return
        }

        var currentNodes: [String: [String: (node: ViewNode, frame: Rect)]] = [:]
        collectCurrentMatchedGeometryNodes(from: root, into: &currentNodes)

        let now = clock()
        let tx = currentAnimationTransaction
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut

        for (namespaceID, oldElements) in pendingMatchedGeometryOldNodes {
            for (elementID, oldRecord) in oldElements {
                guard let currentRecord = currentNodes[namespaceID]?[elementID] else { continue }

                let oldNode = oldRecord.node
                let oldFrame = oldRecord.frame
                let newFrame = currentRecord.frame

                // Skip if the old node is still in the tree.
                guard oldNode.parent == nil else { continue }

                // Skip if the old node is already in transitionOverlays.
                guard !transitionOverlays.contains(where: { $0 === oldNode }) else { continue }

                // Skip if frames are identical.
                guard oldFrame != newFrame else { continue }

                oldNode.isRemovalOverlay = true
                oldNode.cachedFrameKey = nil
                oldNode.cachedFrameCommandRange = nil
                oldNode.cachedSceneKey = nil
                oldNode.cachedScenePaintRange = nil

                // Animate frame from old to new.
                if oldFrame.origin.x != newFrame.origin.x {
                    oldNode.animationStates[.frameOriginX] = AnimationState(
                        startValue: oldFrame.origin.x, endValue: newFrame.origin.x,
                        startTime: now, duration: duration, easing: easing
                    )
                }
                if oldFrame.origin.y != newFrame.origin.y {
                    oldNode.animationStates[.frameOriginY] = AnimationState(
                        startValue: oldFrame.origin.y, endValue: newFrame.origin.y,
                        startTime: now, duration: duration, easing: easing
                    )
                }
                if oldFrame.size.width != newFrame.size.width {
                    oldNode.animationStates[.frameWidth] = AnimationState(
                        startValue: oldFrame.size.width, endValue: newFrame.size.width,
                        startTime: now, duration: duration, easing: easing
                    )
                }
                if oldFrame.size.height != newFrame.size.height {
                    oldNode.animationStates[.frameHeight] = AnimationState(
                        startValue: oldFrame.size.height, endValue: newFrame.size.height,
                        startTime: now, duration: duration, easing: easing
                    )
                }

                // Lock the overlay's frame and resolvedFrame to the old position
                // so the animation starts from there.
                oldNode.frame = oldFrame
                oldNode.resolvedFrame = oldFrame

                transitionOverlays.append(oldNode)
                invalidate()
            }
        }

        pendingMatchedGeometryCheck = false
        pendingMatchedGeometryOldNodes.removeAll()
    }

    private func collectCurrentMatchedGeometryNodes(
        from node: ViewNode,
        into result: inout [String: [String: (node: ViewNode, frame: Rect)]]
    ) {
        if let effect = node.matchedGeometryEffect {
            result[effect.namespaceID, default: [:]][effect.elementID] = (
                node: node,
                frame: node.resolvedFrame
            )
        }
        for child in node.children {
            collectCurrentMatchedGeometryNodes(from: child, into: &result)
        }
    }

    private func tickPropertyAnimations(node: ViewNode, at timestamp: Double) -> Bool {
        guard ViewNode.enterTraversal() else { return false }
        defer { ViewNode.leaveTraversal() }

        var didUpdate = false
        for (property, state) in node.animationStates {
            let elapsed = timestamp - state.startTime
            guard elapsed >= 0 else { continue }
            let progress = min(1.0, max(0.0, elapsed / max(state.duration, 0.001)))
            let eased = state.easing.apply(progress)
            let value = state.startValue + (state.endValue - state.startValue) * eased

            switch property {
            case .opacity:
                if node.opacity != value {
                    node.opacity = value
                    didUpdate = true
                }
            case .outlineWidth:
                if node.outlineWidth != value {
                    node.outlineWidth = value
                    didUpdate = true
                }
            case .frameOriginX:
                let newOrigin = Point(x: value, y: node.frame.origin.y)
                let newFrame = Rect(origin: newOrigin, size: node.frame.size)
                if node.frame != newFrame {
                    node.frame = newFrame
                    node.resolvedFrame.origin.x = value
                    didUpdate = true
                }
            case .frameOriginY:
                let newOrigin = Point(x: node.frame.origin.x, y: value)
                let newFrame = Rect(origin: newOrigin, size: node.frame.size)
                if node.frame != newFrame {
                    node.frame = newFrame
                    node.resolvedFrame.origin.y = value
                    didUpdate = true
                }
            case .frameWidth:
                let newSize = Size(width: value, height: node.frame.size.height)
                let newFrame = Rect(origin: node.frame.origin, size: newSize)
                if node.frame != newFrame {
                    node.frame = newFrame
                    node.resolvedFrame.size.width = value
                    didUpdate = true
                }
            case .frameHeight:
                let newSize = Size(width: node.frame.size.width, height: value)
                let newFrame = Rect(origin: node.frame.origin, size: newSize)
                if node.frame != newFrame {
                    node.frame = newFrame
                    node.resolvedFrame.size.height = value
                    didUpdate = true
                }
            case .transformScaleX:
                if node.transform.scaleX != value {
                    node.transform.scaleX = value
                    didUpdate = true
                }
            case .transformScaleY:
                if node.transform.scaleY != value {
                    node.transform.scaleY = value
                    didUpdate = true
                }
            case .transformTranslationX:
                if node.transform.translationX != value {
                    node.transform.translationX = value
                    didUpdate = true
                }
            case .transformTranslationY:
                if node.transform.translationY != value {
                    node.transform.translationY = value
                    didUpdate = true
                }
            case .transformRotation:
                if node.transform.rotation != value {
                    node.transform.rotation = value
                    didUpdate = true
                }
            case .backgroundColor:
                break
            }

            if progress >= 1.0 {
                node.animationStates.removeValue(forKey: property)
            }
        }

        for child in node.children {
            if tickPropertyAnimations(node: child, at: timestamp) {
                didUpdate = true
            }
        }

        return didUpdate
    }

    fileprivate func invalidate(_ flags: DirtyFlags = .all) {
        guard isRendering else {
            dirtyFlags.insert(flags)
            return
        }
        pendingDirtyFlags.insert(flags)
    }

    fileprivate func invalidate(_ flags: DirtyFlags, from node: ViewNode) {
        guard isRendering else {
            dirtyFlags.insert(flags)
            return
        }
        pendingDirtyFlags.insert(flags)
        pendingDirtyNodes.append(PendingNodeInvalidation(node: WeakViewNodeRef(node: node), flags: flags))
    }

    /// Opens a render pass. While one is open, invalidations are staged rather
    /// than applied, because the pass ends by clearing `dirtyFlags` — anything
    /// raised by a user closure running *inside* the traversal (`onAppear`,
    /// `onLayout`, `onSizeChange`, `canvasDraw`) would otherwise be wiped and
    /// the change would never reach the screen.
    ///
    /// Returns whether *this* call opened the pass. A render pass runs arbitrary
    /// app closures, and one of them re-entering `renderFrame`/`renderScene`
    /// must not reset the staging sets or close the pass on the way out: the
    /// outer pass would then run with `isRendering == false`, route its
    /// invalidations straight into `dirtyFlags`, and wipe them at its own
    /// `endRenderPass` — a permanently frozen runtime with no diagnostic. The
    /// nested call is a no-op on both ends and the outer pass stays the owner.
    private func beginRenderPass() -> Bool {
        guard !isRendering else {
            RetainedViewRuntime.reportReentrantRenderPass()
            return false
        }
        isRendering = true
        pendingDirtyFlags = []
        pendingDirtyNodes.removeAll(keepingCapacity: true)
        return true
    }

    /// Closes a render pass opened by `beginRenderPass()`: the flags the pass
    /// consumed are cleared and the staged ones take their place. Per-node
    /// subtree flags are re-applied too — a node invalidated mid-traversal has
    /// its ancestors' flags erased again as `markSubtreeRendered` unwinds, which
    /// would let the next pass replay its stale range.
    ///
    /// `ownsPass` is what `beginRenderPass()` returned; a nested pass closes
    /// nothing. Always call it from a `defer`, so a throw or an early return
    /// added inside the pass cannot leave `isRendering` stuck true.
    private func endRenderPass(ownsPass: Bool) {
        guard ownsPass else { return }
        isRendering = false
        for pending in pendingDirtyNodes {
            pending.node.node?.markDirty(pending.flags)
        }
        pendingDirtyNodes.removeAll(keepingCapacity: true)
        dirtyFlags = pendingDirtyFlags
        pendingDirtyFlags = []
    }

    /// Number of nested render passes observed since process start. Diagnostic
    /// only: a nested pass means an app closure rendered from inside a render,
    /// which is always a bug in the app, but never a reason to lose an
    /// invalidation.
    internal private(set) static var reentrantRenderPassCount = 0
    private static var hasReportedReentrantRenderPass = false

    private static func reportReentrantRenderPass() {
        reentrantRenderPassCount += 1
        guard !hasReportedReentrantRenderPass else { return }
        hasReportedReentrantRenderPass = true
        FileHandle.standardError.write(
            Data(
                """
                [SwiftWindowsUI] render pass re-entered from inside a render \
                (an onAppear/onLayout/canvasDraw closure rendering again); the \
                nested pass is ignored.

                """.utf8
            )
        )
    }

    fileprivate func recordLayoutReuse() {
        lastLayoutReuseCount += 1
    }

    fileprivate func recordVirtualizedLayoutSkip() {
        virtualizedLayoutSkipCount += 1
    }

    fileprivate func recordLayoutVisit() {
        layoutVisitCount += 1
        currentPassLayoutVisitCount += 1
        maxLayoutVisitsInAnyPass = max(maxLayoutVisitsInAnyPass, currentPassLayoutVisitCount)
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
            if let previousFrame,
                let cachedFrameCommandRange = prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange
            {
                commands.append(contentsOf: previousFrame.commands[cachedFrameCommandRange])
                prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange =
                    startCommandIndex..<commands.count
                replayCount += 1
                continue
            }

            switch prepaintState.deferredDraws[deferredDrawIndex].payload {
            case .scrollIndicator:
                let fillRect = prepaintState.deferredDraws[deferredDrawIndex].payload.fillRectCommand(
                    contentMask: prepaintState.deferredDraws[deferredDrawIndex].contentMask?.rect
                )
                commands.append(.fillRect(fillRect))
            case .subtree(let payload):
                guard let node = payload.node else {
                    prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange =
                        startCommandIndex..<startCommandIndex
                    continue
                }
                node.appendCommands(
                    into: &commands,
                    parentOrigin: payload.parentOrigin,
                    inheritedClip: payload.inheritedClip,
                    inheritedOpacity: payload.inheritedOpacity,
                    // Resuming a deferred subtree restores the state it was
                    // deferred from — all of it. The blend mode was dropped
                    // here while `ScenePainter.appendDeferredDraws` passed it,
                    // so an overlay inside a `.blendMode()` subtree composited
                    // normally on the frame path and multiplied on the scene
                    // path.
                    inheritedBlendMode: payload.inheritedBlendMode,
                    // The payload's clip is already `.painted`, so its subtree
                    // has to be too — the same argument `ScenePainter` passes
                    // when it resumes a deferred subtree.
                    inheritedTransform: payload.inheritedTransform,
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

    private func deferredDrawContentMask(_ deferredDraw: DeferredDrawState) -> RuntimeClipShape? {
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
            prepaintState.dispatchNodes.indices.contains(candidateDispatchIndex)
        {
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

    private enum PointerInteractionRouting {
        case hover
        case activation
    }

    /// The control that owns a pointer hit on otherwise passive content.
    ///
    /// Stack/panel wrappers are hit-test-visible by default. When one sits
    /// inside a Button or selectable List row, the deepest hit is therefore
    /// often its decorative content rather than the control carrying the
    /// action and interaction chrome. Promote only genuinely passive hits to
    /// an enabled, hit-test-visible activatable ancestor. Explicit gestures,
    /// pointer callbacks, focusable controls, scroll views, and draggable
    /// content remain independent interaction boundaries. Hover-only
    /// callbacks/effects own hover without swallowing the enclosing control's
    /// activation, so hover routing and press routing are intentionally split.
    private func pointerInteractionTarget(
        from hitNode: ViewNode?,
        at point: Point,
        routing: PointerInteractionRouting = .hover
    ) -> ViewNode? {
        guard let hitNode, Self.isPassivePointerContent(hitNode, routing: routing),
            let hitDispatchIndex = dispatchIndex(for: hitNode)
        else {
            return hitNode
        }

        var ancestorDispatchIndex = prepaintState.dispatchNodes[hitDispatchIndex].parentIndex
        while let currentIndex = ancestorDispatchIndex,
            prepaintState.dispatchNodes.indices.contains(currentIndex)
        {
            let dispatchState = prepaintState.dispatchNodes[currentIndex]
            let ancestor = dispatchState.node

            if ancestor.onActivate != nil {
                guard ancestor.isHitTestVisible,
                    let interaction = prepaintState.interactions.last(where: {
                        $0.dispatchIndex == currentIndex
                    }),
                    interaction.containsForHitTesting(point)
                else {
                    return hitNode
                }
                return ancestor
            }

            guard Self.isPassivePointerContent(ancestor, routing: routing) else {
                return hitNode
            }
            ancestorDispatchIndex = dispatchState.parentIndex
        }

        return hitNode
    }

    private static func isPassivePointerContent(_ node: ViewNode, routing: PointerInteractionRouting) -> Bool {
        guard node.onActivate == nil,
            node.onPointerDown == nil,
            node.onPointerUpInside == nil,
            node.onPointerUpInsideAt == nil,
            node.onPointerUpOutside == nil,
            !node.isFocusable,
            !node.isScrollable,
            !node.isDraggable,
            node.interactionSurface == nil
        else {
            return false
        }

        switch routing {
        case .activation:
            return true
        case .hover:
            return node.onPointerEnter == nil
                && node.onPointerExit == nil
                && node.onPointerMove == nil
                && node.hoverEffect == nil
        }
    }

    /// Window-space centres of the controls that respond to a press, in the
    /// order the paint traversal registered them.
    ///
    /// A scripted diagnostics run has to press a real control, and the two
    /// alternatives are both worse. Hard-coded fractions of the window miss
    /// the moment the layout re-flows — six scripted "screen switches" in the
    /// existing run land on two, and the session cannot tell. Calling the
    /// runtime's activation directly skips the hit test the press exists to
    /// exercise. These are the frames the hit test itself uses, so a point
    /// taken from here is a point the hit test will resolve to that control.
    public func activatableControlCenters() -> [Point] {
        updateResolvedLayout()
        var centers: [Point] = []
        centers.reserveCapacity(prepaintState.interactions.count)
        for interaction in prepaintState.interactions {
            let node = interaction.node
            guard node.isHitTestVisible, node.onActivate != nil else {
                continue
            }
            let frame = interaction.frame
            guard frame.size.width > 0, frame.size.height > 0 else {
                continue
            }
            let center = Point(x: frame.midX, y: frame.midY)
            guard interaction.containsForHitTesting(center) else {
                continue
            }
            centers.append(center)
        }
        return centers
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

        let previousOffset = scrollableNode.scrollOffset
        let didScroll = scrollableNode.applyKeyboardScroll(key)
        if didScroll {
            cancelScrollMomentum(for: scrollableNode)
            seedKeyboardScrollTween(for: scrollableNode, previousOffset: previousOffset)
        }
        return didScroll
    }

    /// After an instantaneous keyboard scroll, capture the offset jump as a
    /// negative presented delta so the viewport visually starts where it was
    /// and tweens forward to the new offset over ~220ms.
    fileprivate func seedKeyboardScrollTween(for node: ViewNode, previousOffset: Double) {
        let delta = previousOffset - node.scrollOffset
        guard abs(delta) >= 0.5 else {
            return
        }

        let key = ObjectIdentifier(node)
        // Combine with any in-flight presented delta so rapid key presses
        // accumulate without snapping.
        let combinedStart = node.scrollPresentedDelta + delta
        node.scrollPresentedDelta = combinedStart
        scrollPresentedTweens[key] = ScrollPresentedTween(
            node: node,
            startDelta: combinedStart,
            startTime: clock(),
            duration: Self.scrollKeyboardTweenDuration
        )
        invalidate()
    }

    private func tickScrollPresentedTweens(at timestamp: Double) -> Bool {
        guard !scrollPresentedTweens.isEmpty else { return false }

        var didUpdate = false
        for key in Array(scrollPresentedTweens.keys) {
            guard let tween = scrollPresentedTweens[key] else { continue }
            guard let node = tween.node else {
                scrollPresentedTweens.removeValue(forKey: key)
                continue
            }

            let elapsed = max(0, timestamp - tween.startTime)
            let progress = tween.duration > 0 ? min(1, elapsed / tween.duration) : 1
            // Ease-out (1 - (1 - t)^3) so the viewport decelerates into the
            // target like macOS keyboard scrolling.
            let eased = 1 - pow(1 - progress, 3)
            let nextDelta = tween.startDelta * (1 - eased)
            if node.scrollPresentedDelta != nextDelta {
                node.scrollPresentedDelta = nextDelta
                didUpdate = true
            }
            if progress >= 1 {
                node.scrollPresentedDelta = 0
                scrollPresentedTweens.removeValue(forKey: key)
            }
        }

        if didUpdate {
            invalidate()
        }
        return didUpdate
    }

    private func updateResolvedLayout() {
        lastLayoutReuseCount = 0
        lastMeasureReuseCount = 0
        lastPrepaintReplayCount = 0
        lastDeferredOverlayReplayCount = 0
        lastDeferredDrawFrameReplayCount = 0
        lastDeferredDrawSceneReplayCount = 0
        runLayoutPass()

        // A `GeometryReader` is greedy, so its slot is decided by its parent
        // and is not knowable at build time. The pass above resolved it; this
        // loop hands it back to the body that asked for it and re-lays out.
        // A tree with no reader in it never enters the loop and pays for one
        // nil-check per pass.
        var convergenceRounds = 0
        while convergenceRounds < Self.geometryReaderConvergenceLimit,
            resolveGeometryReaderSlots()
        {
            convergenceRounds += 1
            runLayoutPass()
        }

        if drainAfterLayoutActions() {
            // Programmatic scrolling changes a scrollable node's presented
            // offset after the first pass resolved it. Lazy content also
            // needs its newly visible rows laid out before this same frame
            // paints; one bounded settle pass handles both without allowing
            // callback-created callbacks to recurse indefinitely.
            settleLayoutAfterProgrammaticScroll()
        }

        if resolvePendingPreciseScrollAlignments() {
            // A target inside an oversized, previously deferred lazy row
            // acquires its own frame only after the row's first settle. One
            // additional bounded pass aligns that precise frame and still
            // paints the correct target in the same scene/frame.
            settleLayoutAfterProgrammaticScroll()
        }

        updatePrepaintState()
    }

    private func drainAfterLayoutActions() -> Bool {
        guard !isDrainingAfterLayoutActions, !pendingAfterLayoutActionKeys.isEmpty else {
            return false
        }

        isDrainingAfterLayoutActions = true
        let keys = pendingAfterLayoutActionKeys
        let actions = pendingAfterLayoutActions
        pendingAfterLayoutActionKeys.removeAll(keepingCapacity: true)
        pendingAfterLayoutActions.removeAll(keepingCapacity: true)
        defer { isDrainingAfterLayoutActions = false }

        for key in keys {
            guard let action = actions[key] else {
                continue
            }
            action()
        }
        return true
    }

    private func resolvePendingPreciseScrollAlignments() -> Bool {
        guard !pendingPreciseScrollAlignments.isEmpty else {
            return false
        }

        let alignments = pendingPreciseScrollAlignments
        pendingPreciseScrollAlignments.removeAll(keepingCapacity: true)
        var didResolve = false
        for alignment in alignments {
            guard let target = alignment.target, let container = alignment.container,
                target.runtime === self, container.runtime === self,
                container.scrollOffset == alignment.expectedOffset,
                nearestRetainedScrollContainer(of: target) === container
            else {
                continue
            }
            if scrollToDescendant(target, anchorX: alignment.anchorX, anchorY: alignment.anchorY) {
                didResolve = true
            }
        }
        return didResolve
    }

    private func nearestRetainedScrollContainer(of target: ViewNode) -> ViewNode? {
        var current: ViewNode? = target
        var depth = 0
        while let node = current, depth < ViewNode.maximumTraversalDepth {
            if node.scrollAxis != nil {
                return node
            }
            current = node.parent
            depth += 1
        }
        return nil
    }

    private func settleLayoutAfterProgrammaticScroll() {
        runLayoutPass()
        var convergenceRounds = 0
        while convergenceRounds < Self.geometryReaderConvergenceLimit,
            resolveGeometryReaderSlots()
        {
            convergenceRounds += 1
            runLayoutPass()
        }
    }

    private func runLayoutPass() {
        let wasLayoutInProgress = isLayoutInProgress
        isLayoutInProgress = true
        defer { isLayoutInProgress = wasLayoutInProgress }

        layoutPassID &+= 1
        currentPassLayoutVisitCount = 0
        pendingGeometryReaderNodes.removeAll(keepingCapacity: true)
        root.resolvedFrame = root.frame
        root.layoutSubtree(displayScale: displayScale)
    }

    /// Records a reader the running layout pass walked past. Called from the
    /// traversal, so the list is in traversal order — outer readers before
    /// the ones nested in their bodies, which is the order that converges in
    /// the fewest rounds.
    fileprivate func recordGeometryReaderCandidate(_ node: ViewNode) {
        pendingGeometryReaderNodes.append(WeakViewNodeRef(node: node))
    }

    /// Re-invokes every reader body whose resolved slot no longer matches the
    /// size it was built from, and answers whether anything changed — which
    /// is the loop's signal to lay out again.
    ///
    /// The rebuild produces a fresh node for the *same* reader, so it is
    /// adopted onto the existing one: the reader keeps its place in its
    /// parent, its resolved frame, and everything the runtime hung on it,
    /// and only its body is re-seated. Insertion transitions are deliberately
    /// not re-applied — this is a re-measurement of content that is already
    /// on screen, not an insertion.
    private func resolveGeometryReaderSlots() -> Bool {
        guard !pendingGeometryReaderNodes.isEmpty else {
            return false
        }

        var didRebuild = false
        for reference in pendingGeometryReaderNodes {
            guard let node = reference.node, let build = node.geometryReaderBuild else {
                continue
            }

            let slot = node.resolvedFrame.size
            // A zero-extent slot is a node the layout has not placed yet (or
            // a hidden one); reporting it would hand the body a degenerate
            // proxy and throw away the seed for nothing.
            guard slot.width > 0, slot.height > 0 else {
                continue
            }

            if let built = node.geometryReaderBuiltSize,
                abs(built.width - slot.width) < 0.5,
                abs(built.height - slot.height) < 0.5
            {
                continue
            }

            guard let rebuilt = build(self, slot).first else {
                continue
            }

            ComponentHost.adopt(source: rebuilt, into: node)
            // Belt and braces: `adopt` copies the rebuilt node's own record
            // of what it was built from, and this is the same value. Setting
            // it explicitly means a reader whose rebuild path ever stops
            // carrying that record still terminates.
            node.geometryReaderBuiltSize = slot
            geometryReaderResolveCount &+= 1
            didRebuild = true
        }

        return didRebuild
    }

    private func updatePrepaintState() {
        let previousState = prepaintState
        var nextState = RuntimePrepaintState()
        var replayCount = 0
        root.appendPrepaintState(
            into: &nextState,
            parentOrigin: .zero,
            inheritedClip: nil,
            inheritedTransform: .identity,
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

    /// The coordinate space of every clip the last prepaint recorded. All of
    /// them are `.painted`: the same clip is read by interaction and by the
    /// painter, which inherits it for deferred subtrees and scroll indicators.
    internal var prepaintClipSpacesForTesting: [RuntimeClipShape.Space] {
        prepaintState.interactions.compactMap { $0.clip?.space }
            + prepaintState.deferredDraws.compactMap { $0.contentMask?.space }
            + prepaintState.deferredSubtrees.compactMap { $0.payload.inheritedClip?.space }
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
                    inheritedTransform: payload.inheritedTransform,
                    inheritedColorEffects: payload.inheritedColorEffects,
                    inheritedBlendMode: payload.inheritedBlendMode,
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
        applyInteractionChrome(to: previousNode)
        applyInteractionChrome(to: nextHoveredNode)
    }

    // MARK: - Interaction chrome

    /// Which ramp entry `node` should currently be painted at.
    ///
    /// The runtime is the only authority for this: `hoveredNode`,
    /// `focusedNode` and `pressedNode` live here, and a view build has no way
    /// to know any of them. Precedence matches what the control builders
    /// resolved by hand — a press outranks focus outranks hover.
    public func interactionPhase(for node: ViewNode) -> RetainedInteractionSurface.Phase {
        if node === pressedNode {
            return .pressed
        }
        if node.isFocused {
            return .focused
        }
        if node.isHovered {
            return .hovered
        }
        return .idle
    }

    /// Paints `node` at the ramp entry its current phase resolves to.
    ///
    /// `animated: false` is for a restore rather than an interaction: the
    /// chrome being re-applied was already on screen a frame ago, so it snaps
    /// back instead of replaying the ramp the pointer earned when it arrived.
    func applyInteractionChrome(to node: ViewNode?, animated: Bool = true) {
        guard let node, let surface = node.interactionSurface else {
            return
        }

        let phase = interactionPhase(for: node)
        let duration = animated ? surface.duration(intoPhase: phase) : 0
        let timestamp = clock()

        if let background = surface.background(for: phase) {
            animateColor(.background, of: node, to: background, duration: duration, at: timestamp)
            if surface.appliesSurfaceSheen {
                node.backgroundGradient = Controls.backgroundSheen(for: background)
            }
        }
        if let border = surface.border(for: phase) {
            animateColor(.border, of: node, to: border, duration: duration, at: timestamp)
            if surface.appliesSurfaceSheen {
                node.borderGradient = Controls.borderSheen(for: border)
            }
        }
        if let shadow = surface.shadow(for: phase) {
            animateColor(.shadow, of: node, to: shadow, duration: duration, at: timestamp)
        }

        if let focusRingColor = surface.focusRingColor {
            // Keyed off focus itself, not the resolved phase: a press outranks
            // focus for the *fill*, but AppKit keeps the ring on a focused
            // control the whole time the mouse is held down on it.
            let isFocused = node.isFocused
            animateColor(
                .outline, of: node, to: isFocused ? focusRingColor : .clear,
                duration: duration, at: timestamp)
            // macOS does not cross-fade the ring's alpha in place: it grows
            // out of the control's edge. Animating the width alongside the
            // colour is what makes it read as a ring arriving rather than a
            // blue haze resolving. See `docs/AnimationParity.md`.
            animateOutlineWidth(
                of: node, to: isFocused ? surface.focusRingWidth : 0,
                duration: duration, at: timestamp)
        }

        let isPressed = phase == .pressed
        if surface.pressedScale != 1 {
            animateScale(of: node, to: isPressed ? surface.pressedScale : 1, duration: duration, at: timestamp)
        }
        if surface.pressedContentOpacity != 1 {
            animateOpacity(
                of: node, to: isPressed ? surface.pressedContentOpacity : 1,
                duration: duration, at: timestamp)
        }
    }

    /// Re-applies interaction chrome to every node the runtime currently
    /// considers hovered, focused or pressed.
    ///
    /// Called at the end of every reconciliation. A rebuild rewrites
    /// `backgroundColor`, `borderColor`, `outlineColor` and `shadowColor` from
    /// a build that does not know where the pointer is, so without this the
    /// control under the pointer drops to its idle fill on the next `@State`
    /// change anywhere in the window and stays there — the pointer is already
    /// inside it, so `updateHoverTarget` short-circuits and never re-enters.
    public func restoreInteractionChrome() {
        applyInteractionChrome(to: hoveredNode, animated: false)
        if focusedNode !== hoveredNode {
            applyInteractionChrome(to: focusedNode, animated: false)
        }
        if pressedNode !== hoveredNode, pressedNode !== focusedNode {
            applyInteractionChrome(to: pressedNode, animated: false)
        }
    }

    private func animateOutlineWidth(of node: ViewNode, to target: Double, duration: Double, at timestamp: Double) {
        guard duration > 0, node.outlineWidth != target else {
            node.animationStates[.outlineWidth] = nil
            node.outlineWidth = target
            return
        }
        // The stored width stays where it is and the tween drives it, unlike
        // `animateScale`'s steady-state-target convention: a ring that jumped
        // to its end width on the frame the animation *started* would vanish
        // outright on focus loss instead of retracting into the edge.
        node.animationStates[.outlineWidth] = AnimationState(
            startValue: node.outlineWidth, endValue: target, startTime: timestamp, duration: duration,
            easing: .easeOut)
    }

    private func animateScale(of node: ViewNode, to target: Double, duration: Double, at timestamp: Double) {
        guard duration > 0 else {
            node.animationStates[.transformScaleX] = nil
            node.animationStates[.transformScaleY] = nil
            node.transform.scaleX = target
            node.transform.scaleY = target
            return
        }
        let startX = node.transform.scaleX
        let startY = node.transform.scaleY
        node.transform.scaleX = target
        node.transform.scaleY = target
        node.animationStates[.transformScaleX] = AnimationState(
            startValue: startX, endValue: target, startTime: timestamp, duration: duration, easing: .easeOut)
        node.animationStates[.transformScaleY] = AnimationState(
            startValue: startY, endValue: target, startTime: timestamp, duration: duration, easing: .easeOut)
    }

    private func animateOpacity(of node: ViewNode, to target: Double, duration: Double, at timestamp: Double) {
        guard duration > 0 else {
            node.animationStates[.opacity] = nil
            node.opacity = target
            return
        }
        let start = node.opacity
        node.opacity = target
        node.animationStates[.opacity] = AnimationState(
            startValue: start, endValue: target, startTime: timestamp, duration: duration, easing: .easeOut)
    }

    private func updateScrollIndicatorHover(to nextIndicatorHit: ScrollIndicatorHit?) {
        let nextNode = nextIndicatorHit?.node
        guard hoveredScrollIndicatorNode !== nextNode else {
            return
        }

        if let previousNode = hoveredScrollIndicatorNode, previousNode !== activeScrollIndicatorNode {
            // An overlay scroller the pointer has left goes all the way out,
            // not back to a visible "idle" bar it never had.
            animateColor(
                .scrollIndicator,
                of: previousNode,
                to: previousNode.restingScrollIndicatorColor,
                duration: 0.12,
                at: clock()
            )
        }

        hoveredScrollIndicatorNode = nextNode

        if let nextNode, nextNode !== activeScrollIndicatorNode {
            animateColor(
                .scrollIndicator,
                of: nextNode,
                to: nextNode.scrollIndicatorHoverColor,
                duration: 0.12,
                at: clock()
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
        resetCaretBlink()
        applyInteractionChrome(to: previousNode)
        applyInteractionChrome(to: nextFocusedNode)
        invalidate()
        onAccessibilityFocusChanged?(nextFocusedNode)
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
    var lastPoint: Point
}
public enum AnimatedColorProperty: Hashable, Sendable {
    case background
    case border
    case outline
    case shadow
    case scrollIndicator
    /// The two ends of a node's background gradient, animated as ordinary
    /// colours so a fill that is *painted* as a gradient — which is every
    /// control surface with a sheen, and the gradient wins over
    /// `backgroundColor` at paint time — can cross-fade at all. Multi-stop
    /// gradients move only at their ends.
    case backgroundGradientStart
    case backgroundGradientEnd
}

/// The state-dependent chrome of one control, as a value the runtime resolves.
///
/// Every colour is optional so a control can opt into only the part it owns: a
/// push button carries the whole fill/border/shadow ramp, a text field and a
/// slider carry a focus ring and nothing else. `nil` means "leave that
/// property alone", which is what keeps a field's bezel from being repainted
/// by a hover the platform does not give it.
///
/// Phase precedence is pressed > focused > hovered > idle, matching the order
/// the control builders resolved by hand before the runtime took it over.
public struct RetainedInteractionSurface: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case hovered
        case focused
        case pressed
    }

    public var idleBackground: Color?
    public var hoveredBackground: Color?
    public var focusedBackground: Color?
    public var pressedBackground: Color?

    public var idleBorder: Color?
    public var hoveredBorder: Color?
    public var focusedBorder: Color?
    public var pressedBorder: Color?

    public var idleShadow: Color?
    public var hoveredShadow: Color?
    public var focusedShadow: Color?
    public var pressedShadow: Color?

    /// The keyboard focus ring: `outlineColor` while focused, `.clear`
    /// otherwise, with `outlineWidth` expanding from 0 to `focusRingWidth`.
    public var focusRingColor: Color?
    public var focusRingWidth: Double

    /// Press affordances beyond the fill. Both are `1` — no change — for a
    /// macOS-parity control; see `ControlAnimationStyle.pressedScale` and
    /// `SurfacePalette.pressedContentOpacity`.
    public var pressedScale: Double
    public var pressedContentOpacity: Double

    /// Whether the resolved background/border colours also drive the node's
    /// sheen gradients.
    public var appliesSurfaceSheen: Bool

    public var hoverDuration: Double
    public var pressDuration: Double
    public var focusDuration: Double

    public init(
        idleBackground: Color? = nil,
        hoveredBackground: Color? = nil,
        focusedBackground: Color? = nil,
        pressedBackground: Color? = nil,
        idleBorder: Color? = nil,
        hoveredBorder: Color? = nil,
        focusedBorder: Color? = nil,
        pressedBorder: Color? = nil,
        idleShadow: Color? = nil,
        hoveredShadow: Color? = nil,
        focusedShadow: Color? = nil,
        pressedShadow: Color? = nil,
        focusRingColor: Color? = nil,
        focusRingWidth: Double = 0,
        pressedScale: Double = 1,
        pressedContentOpacity: Double = 1,
        appliesSurfaceSheen: Bool = false,
        hoverDuration: Double = 0.18,
        pressDuration: Double = 0.14,
        focusDuration: Double = 0.18
    ) {
        self.idleBackground = idleBackground
        self.hoveredBackground = hoveredBackground
        self.focusedBackground = focusedBackground
        self.pressedBackground = pressedBackground
        self.idleBorder = idleBorder
        self.hoveredBorder = hoveredBorder
        self.focusedBorder = focusedBorder
        self.pressedBorder = pressedBorder
        self.idleShadow = idleShadow
        self.hoveredShadow = hoveredShadow
        self.focusedShadow = focusedShadow
        self.pressedShadow = pressedShadow
        self.focusRingColor = focusRingColor
        self.focusRingWidth = focusRingWidth
        self.pressedScale = pressedScale
        self.pressedContentOpacity = pressedContentOpacity
        self.appliesSurfaceSheen = appliesSurfaceSheen
        self.hoverDuration = hoverDuration
        self.pressDuration = pressDuration
        self.focusDuration = focusDuration
    }

    public func background(for phase: Phase) -> Color? {
        switch phase {
        case .pressed: return pressedBackground ?? focusedBackground ?? hoveredBackground ?? idleBackground
        case .focused: return focusedBackground ?? hoveredBackground ?? idleBackground
        case .hovered: return hoveredBackground ?? idleBackground
        case .idle: return idleBackground
        }
    }

    public func border(for phase: Phase) -> Color? {
        switch phase {
        case .pressed: return pressedBorder ?? focusedBorder ?? hoveredBorder ?? idleBorder
        case .focused: return focusedBorder ?? hoveredBorder ?? idleBorder
        case .hovered: return hoveredBorder ?? idleBorder
        case .idle: return idleBorder
        }
    }

    public func shadow(for phase: Phase) -> Color? {
        switch phase {
        case .pressed: return pressedShadow ?? focusedShadow ?? hoveredShadow ?? idleShadow
        case .focused: return focusedShadow ?? hoveredShadow ?? idleShadow
        case .hovered: return hoveredShadow ?? idleShadow
        case .idle: return idleShadow
        }
    }

    /// The duration the transition *into* `phase` runs for. A press lands
    /// quicker than the hover it replaces, which is the ordering AppKit uses.
    public func duration(intoPhase phase: Phase) -> Double {
        switch phase {
        case .pressed: return pressDuration
        case .focused: return focusDuration
        case .hovered, .idle: return hoverDuration
        }
    }
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
    let easing: AnimationEasing

    init(
        node: ViewNode, property: AnimatedColorProperty, startColor: Color, endColor: Color, startTime: Double,
        duration: Double, easing: AnimationEasing
    ) {
        self.node = node
        self.property = property
        self.startColor = startColor
        self.endColor = endColor
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
    }

    /// Fraction of `duration` elapsed, with no curve applied.
    ///
    /// Completion is decided on this and never on the eased value: a spring
    /// curve passes through 1 well before it settles, and retiring the tween
    /// there would leave the colour parked at an overshoot.
    func elapsedFraction(at timestamp: Double) -> Double {
        let elapsed = timestamp - startTime
        guard duration > 0 else {
            return 1
        }

        return min(max(elapsed / duration, 0), 1)
    }

    /// The curved fraction the colour is interpolated at.
    func progress(at timestamp: Double) -> Double {
        easing.apply(elapsedFraction(at: timestamp))
    }
}
/// The frame path's keyboard focus ring: an annulus around `paintFrame`,
/// drawn as the same `BorderSegments` walk the scene path uses.
///
/// Out of line because `appendCommands` is the deepest frame in the paint
/// traversal and this needs a segment array; inlined, every level of a deep
/// tree would carry it whether or not the node has a focus ring.
@inline(never)
func appendFocusRingCommands(
    into commands: inout [RenderCommand],
    paintFrame: Rect,
    outlineWidth: Double,
    color: Color,
    uniformCornerRadius: Double,
    clipRect: Rect?
) {
    for command in focusRingFillCommands(
        ringFrame: paintFrame.outset(by: outlineWidth),
        width: outlineWidth,
        color: color,
        outerCornerRadius: uniformCornerRadius + outlineWidth,
        clipRect: clipRect
    ) {
        commands.append(.fillRect(command))
    }
}

/// The one place a focus ring's geometry is decided, shared by the 2pt focus
/// effect and the wider chrome outline, and by both the frame and scene paths.
///
/// A ring is an annulus, and `BorderSegments.solidSegments` is the walk the
/// container border already uses when it must paint after its children — edges
/// plus per-corner arcs, covering the band and nothing inside it.
func focusRingFillCommands(
    ringFrame: Rect,
    width: Double,
    color: Color,
    outerCornerRadius: Double,
    clipRect: Rect?
) -> [FillRectCommand] {
    let segments = BorderSegments.solidSegments(
        frame: ringFrame,
        width: width,
        cornerRadius: outerCornerRadius
    )
    // A degenerate walk (zero perimeter, or a ring wider than the control it
    // surrounds) must not drop the ring entirely — fall back to the slab,
    // which is what a ring that thick would look like anyway.
    guard !segments.isEmpty else {
        return [
            FillRectCommand(
                rect: ringFrame,
                color: color,
                cornerRadius: outerCornerRadius,
                clipRect: clipRect
            )
        ]
    }

    return segments.compactMap { segment in
        guard baseClipAllowsDrawing(baseClip: clipRect, rect: segment.rect) else { return nil }
        return FillRectCommand(
            rect: segment.rect,
            color: color,
            cornerRadius: segment.cornerRadius,
            clipRect: clipRect
        )
    }
}

func baseClipAllowsDrawing(baseClip: Rect?, rect: Rect) -> Bool {
    baseClip?.intersected(with: rect) != nil || baseClip == nil
}

func baseClipAllowsDrawing(baseClip: RuntimeClipShape?, rect: Rect) -> Bool {
    baseClip.allowsDrawing(rect)
}

/// Culling test for a whole *subtree*, as opposed to a single primitive.
///
/// Degenerate footprints are the difference. `Rect.intersected` reports "no
/// overlap" for every zero-width or zero-height rect wherever it sits, but a
/// zero-extent node is a legal parent: macOS SwiftUI does not clip at a frame
/// boundary, so `.frame(height: 0)` without `.clipped()` overflows and its
/// children still paint (see `docs/GPURenderingPipeline.md` §2b). Culling such
/// a node on `intersected` alone erases the subtree; not culling it at all —
/// which is what gating the cull on a paintable extent did — leaves a
/// collapsed row parked far outside the clip traversing its whole subtree
/// every frame.
///
/// So: a degenerate footprint is culled only when it is strictly outside the
/// clip, a non-degenerate one keeps the exact overlap test primitives use
/// (`baseClipAllowsDrawing`), and an empty clip culls everything beneath it —
/// no pixel under it can survive.
func clipAllowsSubtreeTraversal(clip: Rect?, bounds: Rect) -> Bool {
    guard let clip else { return true }
    guard !clip.isEmpty else { return false }
    guard bounds.isEmpty else { return clip.intersected(with: bounds) != nil }
    return bounds.maxX >= clip.minX && bounds.minX <= clip.maxX
        && bounds.maxY >= clip.minY && bounds.minY <= clip.maxY
}
public enum AnimatableProperty: Hashable, Sendable {
    case opacity
    case backgroundColor
    /// The keyboard focus ring's stroke width. macOS grows the ring out of the
    /// control's edge rather than fading a full-width ring up from nothing.
    case outlineWidth
    case frameOriginX
    case frameOriginY
    case frameWidth
    case frameHeight
    case transformScaleX
    case transformScaleY
    case transformTranslationX
    case transformTranslationY
    case transformRotation
}
public struct AnimationState {
    public var startValue: Double
    public var endValue: Double
    public var startTime: Double
    public var duration: Double
    public var easing: AnimationEasing

    public init(
        startValue: Double, endValue: Double, startTime: Double, duration: Double, easing: AnimationEasing = .easeInOut
    ) {
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
public struct ColorAnimationState {
    public var startColor: Color
    public var endColor: Color
    public var startTime: Double
    public var duration: Double
    public var easing: AnimationEasing

    public init(
        startColor: Color, endColor: Color, startTime: Double, duration: Double, easing: AnimationEasing = .easeInOut
    ) {
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
public struct PropertySnapshot {
    public var opacity: Double?
    public var backgroundColor: Color?

    public init(opacity: Double? = nil, backgroundColor: Color? = nil) {
        self.opacity = opacity
        self.backgroundColor = backgroundColor
    }
}
