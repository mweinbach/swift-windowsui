import Foundation
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
    var contentMask: Rect?
    var opacity: Float
    var blurRadius: Double
    var blurOpaque: Bool
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

private extension RenderCommand {
    mutating func applyBlendMode(_ blendMode: BlendMode) {
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
    case URL
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
    public var importance: Int // 0 = default, 1 = high

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
    var inheritedClipCornerRadius: Double = 0
    var inheritedOpacity: Float
    var inheritedInverseTransform: Transform2D?
    var inheritedTransform: Transform2D = .identity
    var inheritedColorEffects: [RetainedColorEffect]
    var inheritedBlurRadius: Double
    var inheritedBlurOpaque: Bool
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

    // Gap/Fix: Blur radius — property for requesting a Gaussian blur over the view's content.
    public var blurRadius: Double {
        didSet { invalidateRuntime(.paint) }
    }

    public var blurOpaque: Bool {
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

    public var scrollIndicatorsFlashTrigger: String? {
        didSet { invalidateRuntime(.layout) }
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

    public var scrollIndicatorInsets: EdgeInsets {
        didSet { invalidateRuntime(.paint) }
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
        didSet { invalidateRuntime(.paint) }
    }

    public var isHitTestVisible: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var allowsAutomaticWindowDecorations: Bool {
        didSet { invalidateRuntime(.paint) }
    }

    public var isHidden: Bool {
        didSet { invalidateRuntime(.layout) }
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
    public var animationStates: [AnimatableProperty: AnimationState] = [:]

    /// Persistent phase-animation state for PhaseAnimator. Survives rebuilds
    /// because it is stored on the retained ViewNode rather than in @State.
    public var phaseAnimatorState: PhaseAnimatorState?

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
    internal private(set) var hasAppeared = false
    public internal(set) var isRemovalOverlay: Bool = false
    private var previousFrame: Rect?
    private var lifecycleTasks: [String: Task<Void, Never>] = [:]

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
        scrollStep: Double = 64,
        showsScrollIndicator: Bool = false,
        scrollIndicatorColor: Color = Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.26),
        scrollIndicatorIdleColor: Color? = nil,
        scrollIndicatorHoverColor: Color = Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.45),
        scrollIndicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.72),
        scrollIndicatorThickness: Double = 6,
        scrollIndicatorInsets: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
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
        self.scrollIndicatorColor = scrollIndicatorColor
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
        old.onDismantlePlatformView?(old)
        if old.transition.removal.kind != .identity {
            old.isRemovalOverlay = true
            old.applyRemovalTransition()
            old.cachedFrameKey = nil
            old.cachedFrameCommandRange = nil
            old.cachedSceneKey = nil
            old.cachedScenePaintRange = nil
            runtime?.transitionOverlays.append(old)
            runtime?.invalidate()
            old.parent = nil
            old.setRuntime(nil)
        } else {
            old.markSubtreeDisappeared()
            old.parent = nil
            old.setRuntime(nil)
        }

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
        invalidateRuntime()
    }

    fileprivate func setRuntime(_ runtime: RetainedViewRuntime?) {
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

        if let position = position {
            let size = resolvedFrame.size
            resolvedFrame = Rect(
                x: position.x - size.width / 2,
                y: position.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

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

                    childFrame = Rect(x: x, y: mainCursor, width: max(0, width), height: max(0, height))
                    mainCursor += height + effectiveSpacing
                    maxCrossExtent = max(
                        maxCrossExtent,
                        usesCustomAlignmentGuide ? max(0, x - contentRect.origin.x + width) : width
                    )

                case .horizontal:
                    let width = max(0, allocatedMainSize)
                    let height = stackLayout.alignment == .stretch ? max(0, contentRect.size.height) : min(desiredSize.height, max(0, contentRect.size.height))

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

                    childFrame = Rect(x: mainCursor, y: y, width: max(0, width), height: max(0, height))
                    mainCursor += width + effectiveSpacing
                    maxCrossExtent = max(
                        maxCrossExtent,
                        usesCustomAlignmentGuide ? max(0, y - contentRect.origin.y + height) : height
                    )
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

        applyDefaultScrollAnchorAfterLayout()
        cachedLayoutKey = layoutKey
        resolvedScrollOffset = clampedScrollOffset(for: scrollOffset)
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

        if (contentSizeChanged || frameSizeChanged), let scrollSizeChangeAnchor {
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

    fileprivate func appendPrepaintState(
        into state: inout RuntimePrepaintState,
        parentOrigin: Point,
        inheritedClip: Rect?,
        inheritedOpacity: Float = 1,
        parentDispatchIndex: Int? = nil,
        inheritedInverseTransform: Transform2D? = nil,
        inheritedTransform: Transform2D = .identity,
        inheritedColorEffects: [RetainedColorEffect] = [],
        inheritedBlurRadius: Double = 0,
        inheritedBlurOpaque: Bool = false,
        inheritedBlendMode: BlendMode = .normal,
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
        let effectiveColorEffects = inheritedColorEffects + colorEffects
        let effectiveBlurRadius = max(inheritedBlurRadius, blurRadius)
        let effectiveBlurOpaque = inheritedBlurOpaque || blurOpaque
        let effectiveBlendMode = blendMode == .normal ? inheritedBlendMode : blendMode
        let resolvedHoverEffect = resolvedActiveHoverEffect
        let cacheKey = ViewPaintCacheKey(
            bounds: absoluteFrame,
            contentMask: effectiveClip,
            opacity: effectiveOpacity,
            blurRadius: effectiveBlurRadius,
            blurOpaque: effectiveBlurOpaque,
            blendMode: effectiveBlendMode,
            isCompositingGroup: isCompositingGroup,
            drawingGroup: drawingGroup,
            colorEffects: effectiveColorEffects,
            visualEffects: visualEffects,
            viewMask: viewMask,
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

        let nodeForwardTransform: Transform2D
        if transform.isIdentity {
            nodeForwardTransform = .identity
        } else {
            let center = Point(
                x: absoluteFrame.origin.x + absoluteFrame.size.width * 0.5,
                y: absoluteFrame.origin.y + absoluteFrame.size.height * 0.5
            )
            nodeForwardTransform = Transform2D.translation(x: -center.x, y: -center.y)
                .concatenating(transform)
                .concatenating(.translation(x: center.x, y: center.y))
        }
        let effectiveTransform = nodeForwardTransform.concatenating(inheritedTransform)

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
                            inheritedInverseTransform: nodeInverseTransform,
                            inheritedTransform: effectiveTransform,
                            inheritedColorEffects: effectiveColorEffects,
                            inheritedBlurRadius: effectiveBlurRadius,
                            inheritedBlurOpaque: effectiveBlurOpaque,
                            inheritedBlendMode: effectiveBlendMode
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
                inheritedTransform: effectiveTransform,
                inheritedColorEffects: effectiveColorEffects,
                inheritedBlurRadius: effectiveBlurRadius,
                inheritedBlurOpaque: effectiveBlurOpaque,
                inheritedBlendMode: effectiveBlendMode,
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
        inheritedBlendMode: BlendMode = .normal,
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

        let paintFrame: Rect
        if transform.isIdentity {
            paintFrame = absoluteFrame
        } else {
            let center = Point(x: absoluteFrame.midX, y: absoluteFrame.midY)
            let centeredTransform = Transform2D.translation(x: -center.x, y: -center.y)
                .concatenating(transform)
                .concatenating(.translation(x: center.x, y: center.y))
            paintFrame = absoluteFrame.applying(transform: centeredTransform)
        }

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
        // Skip lifecycle callbacks for removal overlays; they have already
        // appeared and we defer onDisappear until the transition finishes.
        if !isRemovalOverlay {
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
        }

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
        let effectiveBlendMode = blendMode == .normal ? inheritedBlendMode : blendMode
        let resolvedHoverEffect = resolvedActiveHoverEffect
        let cacheKey = ViewPaintCacheKey(
            bounds: paintFrame,
            contentMask: effectiveClip,
            opacity: effectiveOpacity,
            blurRadius: blurRadius,
            blurOpaque: blurOpaque,
            blendMode: effectiveBlendMode,
            isCompositingGroup: isCompositingGroup,
            drawingGroup: drawingGroup,
            colorEffects: colorEffects,
            visualEffects: visualEffects,
            viewMask: viewMask,
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
        let directCommandStartIndex = commands.count

        if let hoverShadow = hoverEffectShadowCommand(
            for: paintFrame,
            inheritedClip: inheritedClip,
            opacity: effectiveOpacity
        ) {
            commands.append(.fillRect(hoverShadow))
        }

        let effectiveShadowColor = shadowColor.multipliedAlpha(by: effectiveOpacity)
        if effectiveShadowColor.alpha > 0 {
            let shadowRect = paintFrame
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
            for: paintFrame,
            inheritedClip: inheritedClip,
            opacity: effectiveOpacity
        ) {
            commands.append(.fillRect(focusEffect))
        }

        let effectiveOutlineColor = outlineColor.multipliedAlpha(by: effectiveOpacity)
        if effectiveOutlineColor.alpha > 0, outlineWidth > 0 {
            let outlineRect = paintFrame.outset(by: outlineWidth)
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

        let effectiveBorderGradient = borderGradient?.withMultipliedOpacity(Double(effectiveOpacity))
        let effectiveBorderColor = borderGradient?.startColor
            ?? borderColor.multipliedAlpha(by: effectiveOpacity)
        if effectiveBorderColor.alpha > 0, borderWidth > 0, backgroundPath == nil, baseClipAllowsDrawing(baseClip: effectiveClip, rect: absoluteFrame) {
            if let borderSegments = BorderSegments.dashedSegments(
                frame: paintFrame,
                width: borderWidth,
                cornerRadius: cornerRadius,
                strokeStyle: borderStrokeStyle
            ) {
                for segment in borderSegments where baseClipAllowsDrawing(baseClip: effectiveClip, rect: segment.rect) {
                    commands.append(
                        .fillRect(
                            FillRectCommand(
                                rect: segment.rect,
                                color: effectiveBorderColor,
                                cornerRadius: segment.cornerRadius,
                                clipRect: effectiveClip,
                                gradient: effectiveBorderGradient
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
                            cornerRadius: cornerRadius,
                            clipRect: effectiveClip,
                            gradient: effectiveBorderGradient
                        )
                    )
                )
            }
        }

        let fillRect = borderWidth > 0 ? paintFrame.inset(by: borderWidth) : paintFrame
        let fillCornerRadius = max(0, cornerRadius - borderWidth)

        let resolvedBackgroundGradient = backgroundGradient?.withMultipliedOpacity(Double(effectiveOpacity))
        let resolvedBackgroundColor = backgroundColor?.multipliedAlpha(by: effectiveOpacity)
            ?? backgroundGradient?.startColor
        if let resolvedBackgroundColor, resolvedBackgroundColor.alpha > 0, fillRect.size.width > 0, fillRect.size.height > 0, backgroundPath == nil {
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

        if let path = backgroundPath, fillRect.size.width > 0, fillRect.size.height > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
            let scaledPath = path.scaled(to: fillRect)
            if let resolvedBackgroundColor, resolvedBackgroundColor.alpha > 0 {
                commands.append(
                    .fillPath(
                        FillPathCommand(
                            path: scaledPath,
                            color: resolvedBackgroundColor,
                            clipRect: effectiveClip
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
                            style: StrokeStyle(lineWidth: borderWidth),
                            clipRect: effectiveClip
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

        // Canvas custom drawing — evaluate the renderer closure and emit commands.
        if let canvasDraw, fillRect.size.width > 0, fillRect.size.height > 0, baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect) {
            var context = CanvasGraphicsContext()
            canvasDraw(&context, fillRect.size)
            context.appendCommands(
                into: &commands,
                origin: absoluteOrigin,
                clipRect: effectiveClip,
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
        if effectiveBlendMode != .normal {
            for index in directCommandStartIndex..<commands.count {
                commands[index].applyBlendMode(effectiveBlendMode)
            }
        }

        for child in orderedChildrenForPaint() {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.appendCommands(
                into: &commands,
                parentOrigin: childOrigin,
                inheritedClip: effectiveClip,
                inheritedOpacity: effectiveOpacity,
                inheritedBlendMode: effectiveBlendMode,
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

    private var effectiveScrollIndicatorInsets: EdgeInsets {
        EdgeInsets(
            top: max(0, scrollIndicatorInsets.top),
            leading: max(0, scrollIndicatorInsets.leading),
            bottom: max(0, scrollIndicatorInsets.bottom),
            trailing: max(0, scrollIndicatorInsets.trailing)
        )
    }

    func scrollIndicatorRect(in absoluteFrame: Rect) -> Rect? {
        guard showsScrollIndicator, isScrollable, maxScrollOffset > 0, scrollIndicatorColor.alpha > 0 else {
            return nil
        }

        let indicatorInsets = effectiveScrollIndicatorInsets
        let indicatorThickness = max(4, scrollIndicatorThickness)

        switch scrollAxis {
        case .vertical:
            let trackHeight = max(0, absoluteFrame.size.height - indicatorInsets.top - indicatorInsets.bottom)
            guard trackHeight > 0 else { return nil }
            let visibleRatio = max(0.08, absoluteFrame.size.height / max(resolvedContentSize.height, absoluteFrame.size.height))
            let indicatorHeight = max(24, trackHeight * visibleRatio)
            let travel = max(0, trackHeight - indicatorHeight)
            let progress = maxScrollOffset > 0 ? resolvedScrollOffset / maxScrollOffset : 0
            return Rect(
                x: absoluteFrame.maxX - indicatorInsets.trailing - indicatorThickness,
                y: absoluteFrame.origin.y + indicatorInsets.top + travel * progress,
                width: indicatorThickness,
                height: indicatorHeight
            )

        case .horizontal:
            let trackWidth = max(0, absoluteFrame.size.width - indicatorInsets.leading - indicatorInsets.trailing)
            guard trackWidth > 0 else { return nil }
            let visibleRatio = max(0.08, absoluteFrame.size.width / max(resolvedContentSize.width, absoluteFrame.size.width))
            let indicatorWidth = max(24, trackWidth * visibleRatio)
            let travel = max(0, trackWidth - indicatorWidth)
            let progress = maxScrollOffset > 0 ? resolvedScrollOffset / maxScrollOffset : 0
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

    fileprivate func scrollIndicatorTrack(in absoluteFrame: Rect) -> ScrollIndicatorTrack? {
        guard let indicatorRect = scrollIndicatorRect(in: absoluteFrame), let scrollAxis else {
            return nil
        }

        let indicatorInsets = effectiveScrollIndicatorInsets

        switch scrollAxis {
        case .vertical:
            let trackLength = max(0, absoluteFrame.size.height - indicatorInsets.top - indicatorInsets.bottom)
            return ScrollIndicatorTrack(
                axis: .vertical,
                origin: absoluteFrame.origin.y + indicatorInsets.top,
                travel: max(0, trackLength - indicatorRect.size.height),
                indicatorRect: indicatorRect
            )

        case .horizontal:
            let trackLength = max(0, absoluteFrame.size.width - indicatorInsets.leading - indicatorInsets.trailing)
            return ScrollIndicatorTrack(
                axis: .horizontal,
                origin: absoluteFrame.origin.x + indicatorInsets.leading,
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

    func applyInsertionTransition() {
        let insertion = transition.insertion
        guard insertion.kind != .identity else { return }

        let tx = currentAnimationTransaction
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut
        let now = Win32Window.currentTimestampSeconds()

        applySingleTransition(insertion, duration: duration, easing: easing, now: now)
    }

    private func applySingleTransition(_ transition: RetainedTransition, duration: Double, easing: AnimationEasing, now: Double) {
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

        let tx = currentAnimationTransaction
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut
        let now = Win32Window.currentTimestampSeconds()

        applySingleRemovalTransition(removal, duration: duration, easing: easing, now: now)
    }

    private func applySingleRemovalTransition(_ transition: RetainedTransition, duration: Double, easing: AnimationEasing, now: Double) {
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
        case let .customHorizontal(name):
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
        case let .customVertical(name):
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
        applyMatchedGeometryAnimations()

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

        let hitNode = hitTest(at: point)
        updateHoverTarget(to: hitNode)
        hitNode?.onPointerMove?(point)
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
                pressedNode.onPointerUpInsideAt?(point)
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
            focusedNode?.onKeyDown?(event)
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
            return didAdvanceButtonRepeat || didAdvancePropertyAnimations || didAdvanceOverlayAnimations || !completedOverlays.isEmpty
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

        return didUpdateAnyAnimation || didAdvanceButtonRepeat || didAdvancePropertyAnimations || didAdvanceOverlayAnimations || !completedOverlays.isEmpty
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

        let now = Win32Window.currentTimestampSeconds()
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
                    inheritedBlurRadius: payload.inheritedBlurRadius,
                    inheritedBlurOpaque: payload.inheritedBlurOpaque,
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

func baseClipAllowsDrawing(baseClip: Rect?, rect: Rect) -> Bool {
    baseClip?.intersected(with: rect) != nil || baseClip == nil
}

// MARK: - Animation interpolation support

/// Properties that can be animated via the `animation()` view modifier.
public enum AnimatableProperty: Hashable, Sendable {
    case opacity
    case backgroundColor
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
