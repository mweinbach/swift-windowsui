import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout

// Gap/Fix: Granular dirty tracking — OptionSet replaces single isDirty boolean.

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

/// Exhaustion permanently disables optional selection replay rather than
/// allowing an old scope stamp to match a later runtime state.
func advanceTextInputReplayScopeRevision(_ revision: inout UInt64?) {
    guard let current = revision else { return }
    revision = current == UInt64.max ? nil : current + 1
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
enum RetainedFileDialogKind: UInt8, CaseIterable {
    case exporter = 1
    case importer = 2
    case importerMulti = 4
    case mover = 8
}

/// A selected native dialog cannot regain ownership after its presenter leaves,
/// even when the same raw node is inserted again before the modal call returns.
@MainActor
final class RetainedFileDialogPresenterLease {
    let kind: RetainedFileDialogKind
    private(set) var isValid = true

    init(kind: RetainedFileDialogKind) {
        self.kind = kind
    }

    func invalidate() {
        isValid = false
    }
}

public struct RetainedFileExporterConfiguration {
    package var invocationScope: (any RetainedFileDialogInvocationScope)? = nil
    public var isPresented: Binding<Bool>
    public var document: Any?
    public var documents: [Any]?
    /// Supplies regular-file bytes for the accepted destination without exposing
    /// a facade document or file-wrapper type to the retained runtime.
    public var dataProvider: (@MainActor (URL) throws -> Data)?
    public var contentType: UTType
    public var defaultFilename: String?
    public var onCompletion: (Result<URL, Error>) -> Void

    public init(
        isPresented: Binding<Bool>,
        document: Any? = nil,
        documents: [Any]? = nil,
        dataProvider: (@MainActor (URL) throws -> Data)? = nil,
        contentType: UTType,
        defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.isPresented = isPresented
        self.document = document
        self.documents = documents
        self.dataProvider = dataProvider
        self.contentType = contentType
        self.defaultFilename = defaultFilename
        self.onCompletion = onCompletion
    }
}
public struct RetainedFileImporterConfiguration {
    package var invocationScope: (any RetainedFileDialogInvocationScope)? = nil
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
    package var invocationScope: (any RetainedFileDialogInvocationScope)? = nil
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
    package var invocationScope: (any RetainedFileDialogInvocationScope)? = nil
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
    /// Scene cache eligibility can depend on the enclosing device target even
    /// when a deferred subtree has no clip. Prepaint and the legacy frame walk
    /// do not own a render target and leave this scene-only input unspecified.
    var surfaceSize: Size? = nil
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
    /// Distinguishes password fields from ordinary editable text without
    /// exposing their backing value to platform accessibility providers.
    public static let isSecureTextInput = RetainedAccessibilityTraits(rawValue: 1 << 18)
    /// Identifies retained List/Table rows that support selection even while
    /// they are currently unselected.
    public static let isSelectable = RetainedAccessibilityTraits(rawValue: 1 << 19)
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

/// Configuration for one retained long-press recognizer. Its pending attempt
/// belongs to the runtime, so replacing a view's callbacks does not restart
/// the duration or move the gesture's original logical position.
@MainActor
public struct RetainedLongPressGesture {
    public typealias Cleanup = @MainActor () -> Void
    public typealias IsActive = @MainActor () -> Bool

    public var minimumDuration: Double
    public var maximumDistance: Double
    public var isEnabled: Bool
    public var onBegin: (@MainActor (IsActive) -> Cleanup?)?
    public var onPressingChanged: (@MainActor (Bool) -> Void)?
    public var onRecognized: @MainActor () -> Void

    public init(
        minimumDuration: Double = 0.5,
        maximumDistance: Double = 10,
        isEnabled: Bool = true,
        onBegin: (@MainActor (IsActive) -> Cleanup?)? = nil,
        onPressingChanged: (@MainActor (Bool) -> Void)? = nil,
        onRecognized: @escaping @MainActor () -> Void
    ) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
        self.isEnabled = isEnabled
        self.onBegin = onBegin
        self.onPressingChanged = onPressingChanged
        self.onRecognized = onRecognized
    }

    fileprivate var canRecognize: Bool {
        isEnabled && minimumDuration.isFinite && minimumDuration >= 0
            && maximumDistance.isFinite && maximumDistance >= 0
    }
}

@MainActor
private final class LongPressAttempt {
    weak var node: ViewNode?
    let startPoint: Point
    let deadline: Double
    let maximumDistance: Double
    var configuration: RetainedLongPressGesture
    var cleanup: RetainedLongPressGesture.Cleanup?
    var didNotifyPressing = false
    var didFinish = false
    var isCheckingDeadline = false

    init(node: ViewNode, point: Point, timestamp: Double, configuration: RetainedLongPressGesture) {
        self.node = node
        self.startPoint = point
        self.deadline = timestamp + configuration.minimumDuration
        self.maximumDistance = configuration.maximumDistance
        self.configuration = configuration
    }
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
    var cachedFrameSnapshotIdentity: PaintSnapshotIdentity?
    var cachedSceneSnapshotIdentity: PaintSnapshotIdentity?
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
final class PrepaintSnapshotIdentity: Sendable, Equatable {
    static func == (lhs: PrepaintSnapshotIdentity, rhs: PrepaintSnapshotIdentity) -> Bool {
        lhs === rhs
    }
}
/// Paint can omit a subtree that prepaint still visits, for example under
/// zero opacity. Paint ranges therefore belong to their own output snapshot,
/// independently of the snapshot containing interaction and focus records.
final class PaintSnapshotIdentity: Sendable, Equatable {
    static func == (lhs: PaintSnapshotIdentity, rhs: PaintSnapshotIdentity) -> Bool {
        lhs === rhs
    }
}
struct FramePaintSnapshot: Sendable {
    var frame: RenderFrame
    let identity: PaintSnapshotIdentity
}
struct PrepaintStateRange: Equatable, Sendable {
    var start: PrepaintStateIndex
    var end: PrepaintStateIndex
    /// A culled ancestor leaves descendant ranges untouched. Their offsets
    /// remain meaningful only in the snapshot that actually contains them.
    var generation: PrepaintSnapshotIdentity
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
    // Cached ranges retain their token, so snapshots remain distinct even
    // when a subtree moves between runtimes or an older snapshot is released.
    let generation = PrepaintSnapshotIdentity()
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

/// Placement admission travels with the size under the same measurement key.
/// An ideal probe must not leave a finite-fit flag on a different cached size.
private struct ViewMeasurementResult {
    var size: Size
    var fittedAspect: RetainedAspectFitLayout?
    var inheritedFillAxes: LayoutFillAxes
}

private struct ViewMeasurementCacheEntry {
    var key: ViewMeasureCacheKey
    var result: ViewMeasurementResult
}

/// A single synchronous measurement can propose several widths to a subtree.
/// Dirty nodes cannot use their previous frame's cache yet, so retain these
/// answers only for this walk to avoid repeating an entire nested row for
/// every proposal. The memo owns no nodes and is discarded when the walk ends.
@MainActor
private final class MeasurementMemo {
    struct Key: Hashable {
        var node: ObjectIdentifier
        var measurement: ViewMeasureCacheKey
        var depth: Int

        func hash(into hasher: inout Hasher) {
            hasher.combine(node)
            hasher.combine(measurement.constraints.minWidth)
            hasher.combine(measurement.constraints.maxWidth)
            hasher.combine(measurement.constraints.minHeight)
            hasher.combine(measurement.constraints.maxHeight)
            hasher.combine(measurement.displayScale)
            hasher.combine(depth)
        }
    }

    var results: [Key: ViewMeasurementResult] = [:]
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
/// A two-dimensional retained Grid. Unlike a vertical stack of independent
/// rows, this mode measures one set of column tracks for all of its rows.
public struct RetainedGridLayout: Equatable, Sendable {
    public var horizontalSpacing: Double
    public var verticalSpacing: Double
    public var horizontalAlignment: StackCrossAlignment
    public var verticalAlignment: StackCrossAlignment
    public var isRightToLeft: Bool

    public init(
        horizontalSpacing: Double = 0,
        verticalSpacing: Double = 0,
        horizontalAlignment: StackCrossAlignment = .center,
        verticalAlignment: StackCrossAlignment = .center,
        isRightToLeft: Bool = false
    ) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.isRightToLeft = isRightToLeft
    }
}

/// A physical row boundary whose cells can use a directly containing Grid's
/// tracks. Outside that boundary it retains the legacy horizontal-stack layout.
public struct RetainedGridRowLayout: Equatable, Sendable {
    public var alignment: StackCrossAlignment?
    public var standaloneSpacing: Double

    public init(alignment: StackCrossAlignment? = nil, standaloneSpacing: Double = 0) {
        self.alignment = alignment
        self.standaloneSpacing = standaloneSpacing
    }

    var standaloneStackLayout: StackLayout {
        .horizontal(spacing: standaloneSpacing, alignment: alignment ?? .center)
    }
}

private struct GridCellInput {
    var node: ViewNode
    var firstColumn: Int
    var endColumn: Int
    var isMerged: Bool
}

private struct GridRowInput {
    var node: ViewNode
    var isGridRow: Bool
    var alignment: StackCrossAlignment
    var cells: [GridCellInput]
}

/// One run of identical empty/interior columns. Boundaries come only from actual
/// cells, so a request to span Int.max columns does not allocate Int.max entries.
private struct GridTrackRun {
    var firstColumn: Int
    var endColumn: Int
    var extent: Double = 0
    var minimumExtent: Double = 0
    var isFlexible = false
    var alignment: StackCrossAlignment
    var guideBefore: Double = 0
    var guideAfter: Double = 0
}

private struct GridCellGeometry {
    var identity: ObjectIdentifier
    var frame: Rect
}

private struct GridRowGeometry {
    var identity: ObjectIdentifier
    var frame: Rect
    var cells: [GridCellGeometry]
}

/// Installed-node layout data only. This does not retain construction nodes,
/// application callbacks, or a build context, and is never copied by the host.
private struct GridLayoutGeometry {
    var size: Size
    var fillAxes: LayoutFillAxes
    var rows: [GridRowGeometry]
}

private struct GridRowMetrics {
    var height: Double = 0
    var minimumHeight: Double = 0
    var guideBefore: Double = 0
    var guideAfter: Double = 0
    var isFlexible = false
}

/// A one-child modifier that proposes a coupled size for finite aspect fit.
/// Nil preserves the child's current ideal ratio, not its last placed size.
package struct RetainedAspectFitLayout: Equatable, Sendable {
    package var aspectRatio: Double?

    package init(aspectRatio: Double? = nil) {
        self.aspectRatio = aspectRatio
    }
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
    case grid(RetainedGridLayout)
    case gridRow(RetainedGridRowLayout)

    /// The stack layout children are placed with, for both stack variants.
    public var stackLayout: StackLayout? {
        switch self {
        case .stack(let layout), .lazyStack(let layout): return layout
        case .gridRow(let layout): return layout.standaloneStackLayout
        case .absolute, .flex, .grid: return nil
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

/// Optional interaction callbacks used only by controls that actually handle
/// pointer, keyboard, or focus events. Keeping these out of `ViewNode`'s
/// inline storage means ordinary labels, layout wrappers, and list rows do not
/// carry sixteen empty closure slots each.
@MainActor
private final class ViewNodeInteractionHandlers {
    var pointerEnter: (() -> Void)?
    var pointerExit: (() -> Void)?
    var pointerMove: ((Point) -> Void)?
    var pointerDown: (() -> Void)?
    var pointerUpInside: (() -> Void)?
    var pointerUpInsideAt: ((Point) -> Void)?
    var pointerUpOutside: (() -> Void)?
    var contextMenu: ((Point) -> Void)?
    var focusEnter: (() -> Void)?
    var focusExit: (() -> Void)?
    var keyDown: ((KeyboardEvent) -> Void)?
    var imeComposition: ((IMECompositionEvent) -> Void)?
    var textInputCaretRectProvider: (() -> Rect?)?
    var textInputController: (any RetainedTextInputController)?
    var listNavigationOwner: RetainedListNavigationOwner?
    var keyUp: ((KeyboardEvent) -> Void)?
    var activate: (() -> Void)?
    var repeatActivate: (() -> Void)?
    var longPressGesture: RetainedLongPressGesture?
}

/// Drag, drop, and dynamic-list editing are another independently optional
/// capability: installing a button's activation handler must not also
/// allocate space for sixteen unrelated drag/drop callbacks.
@MainActor
private final class ViewNodeDropHandlers {
    var deleteRows: ((IndexSet) -> Void)?
    var moveRows: ((IndexSet, Int) -> Void)?
    var insertRows: ((Int, [Any]) -> Void)?
    var dropRows: (([Any], Int) -> Void)?
    var validateDrop: (([Any], Point) -> Bool)?
    var dropEntered: (([Any], Point) -> Void)?
    var dropUpdated: (([Any], Point) -> Any?)?
    var dropExited: (() -> Void)?
    var dropProviders: (([Any], Point) -> Bool)?
    var dropPayloads: (([Any], Point) -> Bool)?
    var makeDropConfiguration: (([Any], Point) -> Any?)?
    var makeDragPayload: (() -> Any?)?
    var makeDragItemProvider: (() -> Any?)?
    var dragStart: ((Point) -> Void)?
    var dragChange: ((Point, Point) -> Void)?
    var dragEnd: ((Point, Point) -> Void)?
}

/// Scalar style for the framework's separator gap before one actual List row.
/// A zero thickness means the style has spacing but no separator. The gap
/// contains no row View, callback, provider, or ownership authority.
package struct RetainedLazyListGap: Equatable, Sendable {
    package let spacing: Double
    package let separatorThickness: Double
    package let nextRowIsSelected: Bool
    package let nextRowIsGrouped: Bool

    package init?(
        spacing: Double, separatorThickness: Double,
        nextRowIsSelected: Bool, nextRowIsGrouped: Bool
    ) {
        guard spacing.isFinite, spacing >= 0,
            separatorThickness.isFinite, separatorThickness >= 0
        else { return nil }
        let maximumExtent = separatorThickness == 0 ? spacing : 2 * spacing + separatorThickness
        guard maximumExtent.isFinite else { return nil }
        self.spacing = spacing
        self.separatorThickness = separatorThickness
        self.nextRowIsSelected = nextRowIsSelected
        self.nextRowIsGrouped = nextRowIsGrouped
    }
}

/// Framework chrome for an eligible row whose authored background is empty.
/// The native prefix index supplies alternating parity only after actual row
/// output is accepted; an unvisited prefix remains an explicit estimate.
package struct RetainedLazyListRowChrome: Equatable, Sendable {
    package let alternatingBackground: Color

    package init(alternatingBackground: Color) {
        self.alternatingBackground = alternatingBackground
    }
}

@MainActor
private final class RetainedLazyListRowChromePublication {
    let metadata: RetainedLazyListRowChrome
    let originalCornerRadius: Double
    var expectedBackground: Color?
    var expectedCornerRadius: Double
    var isSuppressed: Bool
    var isPublishing = false
    var usesEstimatedParity: Bool?

    init(metadata: RetainedLazyListRowChrome, initialBackground: Color?, initialCornerRadius: Double) {
        self.metadata = metadata
        originalCornerRadius = initialCornerRadius
        expectedBackground = initialBackground
        expectedCornerRadius = initialCornerRadius
        isSuppressed = initialBackground != nil
    }

    func noteExternalFieldAssignment() {
        if !isPublishing { isSuppressed = true }
    }
}

/// Layout/lifecycle observers and GeometryReader rebuilding are deliberately
/// separate from control input: most retained nodes use none of these, while
/// observable list rows can install one without paying for pointer handlers.
@MainActor
private final class ViewNodeLifecycleHandlers {
    var layout: ((Rect) -> Void)?
    var layoutWithNode: ((ViewNode, Rect) -> Void)?
    var absoluteChildFrame: ((ViewNode, Rect) -> Rect)?
    var appearWithNode: ((ViewNode) -> Void)?
    var disappearWithNode: ((ViewNode) -> Void)?
    var appear: (() -> Void)?
    var disappear: (() -> Void)?
    var sizeChange: ((Rect) -> Void)?
    var geometryReaderBuild: ((RetainedViewRuntime, Size) -> [ViewNode])?
    var retainedSubtreeBuildLease: (any RetainedSubtreeBuildLease)?
    var retainedTasks: RetainedTaskNodeState?
    var retainedLazyListActivity: RetainedLazyListNodeActivityStorage?
    var completedLazyTaskAppearance: RetainedLazyListActualAttachment?
    var retainedLazyListAdapter: RetainedLazyListRuntimeAdapter?
    var retainedLazyListGap: RetainedLazyListGap?
    var retainedLazyListRowChrome: RetainedLazyListRowChromePublication?
    var lazyListContentRevision: UInt64 = 0
    var lazyListEnvironmentRevision: UInt64 = 0
    var lazyListAttachmentIdentity: RetainedLazyListAttachmentIdentity?
    var lazyListLayoutIdentity: RetainedLazyListAttachmentIdentity?
    var lazyListViewIdentity: RetainedLazyListAttachmentIdentity?
    var lazyListScrollIntentIdentity: RetainedLazyListAttachmentIdentity?
    var lazyListRetirementIdentity: RetainedLazyListAttachmentIdentity?
}

/// Native identity only. Old proofs keep this allocation distinct without
/// keeping a node, provider, callback, or runtime alive.
fileprivate final class RetainedLazyListAttachmentIdentity {}

@MainActor
fileprivate struct RetainedLazyListLocalLayoutProof {
    weak var node: ViewNode?
    let identity: RetainedLazyListAttachmentIdentity
    let attachment: RetainedLazyListAttachmentProof

    var isCurrent: Bool {
        node?.lazyListLayoutIdentity === identity && attachment.isCurrent
    }
}

/// A pure witness for the identity field, separate from attachment. Equality
/// of authored keys is checked explicitly; any later assignment, including an
/// equal-value ABA, invalidates this proof before old key payloads can unwind.
@MainActor
final class RetainedLazyListViewIdentityProof {
    private weak var node: ViewNode?
    private let identity: RetainedLazyListAttachmentIdentity

    fileprivate init(node: ViewNode, identity: RetainedLazyListAttachmentIdentity) {
        self.node = node
        self.identity = identity
    }

    var isCurrent: Bool { node?.lazyListViewIdentity === identity }
}

@MainActor
final class RetainedLazyListAttachmentProof {
    private weak var node: ViewNode?
    private weak var parent: ViewNode?
    private weak var runtime: RetainedViewRuntime?
    private let hadParent: Bool
    private let hadRuntime: Bool
    private let identity: RetainedLazyListAttachmentIdentity

    fileprivate init(node: ViewNode, identity: RetainedLazyListAttachmentIdentity) {
        self.node = node
        self.parent = node.parent
        self.runtime = node.runtime
        self.hadParent = node.parent != nil
        self.hadRuntime = node.runtime != nil
        self.identity = identity
    }

    var isCurrent: Bool {
        guard let node, node.lazyListAttachmentIdentity === identity,
            !node.isRetiringLazyListAttachment
        else { return false }
        if hadParent {
            guard let parent, node.parent === parent else { return false }
        } else if node.parent != nil {
            return false
        }
        if hadRuntime {
            guard let runtime, node.runtime === runtime else { return false }
        } else if node.runtime != nil {
            return false
        }
        return true
    }
}

/// A request-owned continuation contains only native proofs and weak actual
/// attachments. It cannot keep a provider, authored key, view or state alive.
@MainActor
package final class RetainedLazyListScrollSearchCursor {
    fileprivate weak var runtime: RetainedViewRuntime?
    fileprivate weak var container: ViewNode?
    fileprivate weak var content: ViewNode?
    fileprivate weak var adapter: RetainedLazyListRuntimeAdapter?
    fileprivate weak var lease: (any RetainedSubtreeBuildLease)?
    fileprivate weak var descriptor: RetainedLazyListManagedLogicalDescriptorBinding?
    fileprivate let hadManagedDescriptor: Bool
    fileprivate let containerAttachment: RetainedLazyListAttachmentProof
    fileprivate let contentAttachment: RetainedLazyListAttachmentProof
    fileprivate let containerIdentity: RetainedLazyListViewIdentityProof
    fileprivate let contentIdentity: RetainedLazyListViewIdentityProof
    fileprivate let adapterProof: RetainedLazyListRuntimeAdapter.LayoutProof
    fileprivate let ancestry: [RetainedLazyListAttachmentProof]
    fileprivate let lastExaminedToken: RetainedLazyListRowToken?

    fileprivate init(
        runtime: RetainedViewRuntime, container: ViewNode, content: ViewNode,
        adapter: RetainedLazyListRuntimeAdapter, lease: any RetainedSubtreeBuildLease,
        descriptor: RetainedLazyListManagedLogicalDescriptorBinding?,
        adapterProof: RetainedLazyListRuntimeAdapter.LayoutProof
    ) {
        self.runtime = runtime
        self.container = container
        self.content = content
        self.adapter = adapter
        self.lease = lease
        self.descriptor = descriptor
        hadManagedDescriptor = descriptor != nil
        containerAttachment = container.captureLazyListAttachmentProof()
        contentAttachment = content.captureLazyListAttachmentProof()
        containerIdentity = container.captureLazyListIdentityProof()
        contentIdentity = content.captureLazyListIdentityProof()
        self.adapterProof = adapterProof
        var proofs: [RetainedLazyListAttachmentProof] = []
        var ancestor: ViewNode? = content
        while let node = ancestor, proofs.count < ViewNode.maximumTraversalDepth {
            proofs.append(node.captureLazyListAttachmentProof())
            if node === runtime.root { break }
            ancestor = node.parent
        }
        ancestry = proofs
        lastExaminedToken = nil
    }

    fileprivate init(advancing previous: RetainedLazyListScrollSearchCursor, through token: RetainedLazyListRowToken) {
        runtime = previous.runtime
        container = previous.container
        content = previous.content
        adapter = previous.adapter
        lease = previous.lease
        descriptor = previous.descriptor
        hadManagedDescriptor = previous.hadManagedDescriptor
        containerAttachment = previous.containerAttachment
        contentAttachment = previous.contentAttachment
        containerIdentity = previous.containerIdentity
        contentIdentity = previous.contentIdentity
        adapterProof = previous.adapterProof
        ancestry = previous.ancestry
        lastExaminedToken = token
    }
}

@MainActor
package enum RetainedLazyListScrollSearchResult {
    case found(RetainedLazyListRowToken)
    case more(RetainedLazyListScrollSearchCursor)
    case notFound
    case obsolete
    case deferred
}

/// One admitted retained operation. This reads only owned identity and scalar
/// state, including the source's native generation proof; it invokes no lease,
/// provider, application getter, focus operation, or accessibility operation.
@MainActor
final class RetainedLazyListAdoptionAdmission {
    private weak var container: ViewNode?
    private weak var runtime: RetainedViewRuntime?
    private weak var adapter: RetainedLazyListRuntimeAdapter?
    private weak var lease: (any RetainedSubtreeBuildLease)?
    private let attachment: RetainedLazyListAttachmentProof
    private var candidate: RetainedLazyListRuntimeAdapter.Candidate?
    private let coordinator: RetainedBuildCoordinator
    private let sequence: UInt64
    private let layoutProofs: [RetainedLazyListLocalLayoutProof]
    private let expectedDisplayScale: Double
    private let expectedLayoutPassID: UInt64
    private var completedSubtrees: [RetainedLazyListAdoptionCompletion] = []
    private var wasRevoked = false
    private var isFinishingCandidate = false
    private(set) var didMutate = false

    init(
        adapter: RetainedLazyListRuntimeAdapter,
        candidate: RetainedLazyListRuntimeAdapter.Candidate? = nil,
        container: ViewNode, runtime: RetainedViewRuntime,
        coordinator: RetainedBuildCoordinator, sequence: UInt64
    ) {
        self.adapter = adapter
        self.candidate = candidate
        self.container = container
        self.runtime = runtime
        self.lease = container.retainedSubtreeBuildLease
        self.attachment = container.captureLazyListAttachmentProof()
        self.coordinator = coordinator
        self.sequence = sequence
        self.expectedDisplayScale = runtime.displayScale
        self.expectedLayoutPassID = runtime.layoutPassID
        var proofs: [RetainedLazyListLocalLayoutProof] = []
        var ancestor: ViewNode? = container
        while let node = ancestor, proofs.count < ViewNode.maximumTraversalDepth {
            proofs.append(node.captureLazyListLocalLayoutProof())
            if node === runtime.root { break }
            ancestor = node.parent
        }
        self.layoutProofs = proofs
    }

    var isCurrent: Bool {
        !isFinishingCandidate && candidate != nil && isBuildCurrent
    }

    internal var admittedRuntime: RetainedViewRuntime? { runtime }
    internal var admittedContainer: ViewNode? { container }

    /// Before installing a row candidate this admits only construction. The
    /// checked reconciler requires isCurrent, which also requires a candidate.
    var isBuildCurrent: Bool {
        let candidateCurrent = isFinishingCandidate ? candidate?.isOperationCurrent : candidate?.isCurrent
        guard !wasRevoked, candidateCurrent != false, attachment.isCurrent,
            let container, let runtime, let adapter, let lease,
            runtime.permitsRetainedActionInvocation,
            runtime.layoutPassID == expectedLayoutPassID,
            runtime.displayScale == expectedDisplayScale, layoutProofs.allSatisfy(\.isCurrent),
            completedSubtrees.allSatisfy(\.isCurrent),
            container.runtime === runtime, container.retainedLazyListAdapter === adapter,
            adapter.ownsAttachment(container),
            container.retainedSubtreeBuildLease === lease,
            coordinator.isBuilding, !coordinator.wasSuperseded(since: sequence)
        else { return false }
        var ancestor: ViewNode? = container
        var depth = 0
        while let node = ancestor, depth < ViewNode.maximumTraversalDepth {
            if node === runtime.root { return true }
            ancestor = node.parent
            depth += 1
        }
        return false
    }

    func markMutationStarted() { didMutate = true }
    func revoke() { wasRevoked = true }

    func installCandidate(_ candidate: RetainedLazyListRuntimeAdapter.Candidate) -> Bool {
        guard !isFinishingCandidate, self.candidate == nil, isBuildCurrent, let adapter,
            adapter.ownsCandidate(candidate), candidate.isCurrent
        else { return false }
        self.candidate = candidate
        return isCurrent
    }

    func isBuildCurrent(for adapter: RetainedLazyListRuntimeAdapter) -> Bool {
        self.adapter === adapter && isBuildCurrent
    }

    func recordCompletion(_ completion: RetainedLazyListAdoptionCompletion) -> Bool {
        guard isCurrent, completion.isCurrent else { return false }
        completedSubtrees.append(completion)
        return isCurrent
    }

    func claimDepartingEmptyRows(journal: RetainedLazyListAdoptionJournal) -> Bool {
        guard isCurrent, let candidate, let adapter else { return false }
        return adapter.claimDepartingEmptyRows(in: candidate, journal: journal)
    }

    func recordCompletedOwnedSource(
        from source: ViewNode, to actual: ViewNode, journal: RetainedLazyListAdoptionJournal
    ) {
        guard isCurrent, let candidate, let container else { return }
        candidate.recordCompletedSource(from: source, to: actual, in: container, journal: journal)
    }

    /// A build token cannot be borrowed to mutate another retained subtree.
    /// Detached construction nodes are prepared separately and are admitted
    /// here only after their actual parent membership has been published.
    func permitsMutation(of node: ViewNode) -> Bool {
        guard isCurrent, let container, let runtime, node.runtime === runtime else { return false }
        var current = node
        var depth = 0
        while depth < ViewNode.maximumTraversalDepth {
            if current === container { return true }
            guard let parent = current.parent, parent.runtime === runtime,
                parent.children.contains(where: { $0 === current })
            else { return false }
            current = parent
            depth += 1
        }
        return false
    }

    func revokeUnfinishedCandidate() {
        // Do not revoke a newer attempt installed by a cleanup callback.
        if candidate?.isOperationCurrent == true { adapter?.revokePendingCandidate() }
    }

    func finishCandidatePayload() {
        guard !isFinishingCandidate else { return }
        // Revoke mutation before any source-node/key/closure destructor runs.
        // Native generation/operation and actual retained-tree witnesses can
        // still be checked once those owned temporary payloads have unwound.
        isFinishingCandidate = true
        candidate?.discardBuiltContent()
    }

    func removalReason(for root: ViewNode) -> RetainedChildRemovalReason {
        candidate?.virtualizedDepartureRoots.contains(ObjectIdentifier(root)) == true ? .virtualization : .structural
    }
}

enum RetainedChildRemovalReason {
    case structural
    case virtualization
}

/// Chart compatibility modifiers are rare on retained nodes, but their
/// twenty-four optional strings used to occupy every single node. One lazy
/// allocation keeps the existing modifier API and reconciliation semantics
/// without making ordinary text/layout nodes pay the Charts storage tax.
@MainActor
private final class ViewNodeChartMetadata {
    var xAxis: String?
    var xScale: String?
    var yScale: String?
    var meshGradient: String?
    var yAxis: String?
    var legend: String?
    var background: String?
    var plotStyle: String?
    var overlay: String?
    var selection: String?
    var scrollableAxes: String?
    var foregroundStyleScale: String?
    var symbolSize: String?
    var symbol: String?
    var angleScale: String?
    var backgroundStyleScale: String?
    var symbolScale: String?
    var xVisibleDomain: String?
    var yVisibleDomain: String?
    var xSelection: String?
    var ySelection: String?
    var angleSelection: String?
    var scrollPositionX: String?
    var scrollPositionY: String?
}

@MainActor
public final class ViewNode {
    private var interactionHandlers: ViewNodeInteractionHandlers?
    fileprivate var storedAccessibilityAttachmentIdentity: RetainedAccessibilityIdentity?
    private var dropHandlers: ViewNodeDropHandlers?
    private var lifecycleHandlers: ViewNodeLifecycleHandlers?
    private var chartMetadata: ViewNodeChartMetadata?

    /// Structural diagnostics for the sparse-storage regression tests. These
    /// are computed flags, so observing them never creates optional storage.
    internal var hasAllocatedInteractionHandlers: Bool { interactionHandlers != nil }
    internal var hasAllocatedDropHandlers: Bool { dropHandlers != nil }
    internal var hasAllocatedLifecycleHandlers: Bool { lifecycleHandlers != nil }
    internal var hasAllocatedChartMetadata: Bool { chartMetadata != nil }

    internal var existingRetainedTaskState: RetainedTaskNodeState? { lifecycleHandlers?.retainedTasks }
    internal var retainedLazyListRuntime: RetainedViewRuntime? { runtime }

    /// Physical membership only. This is deliberately not permission to invoke
    /// an action, render callback, Task, input handler, or accessibility request.
    internal func isRetainedLazyListAttached(in expectedRuntime: RetainedViewRuntime) -> Bool {
        var current: ViewNode? = self
        var depth = 0
        while let node = current, depth < Self.maximumTraversalDepth {
            guard node.runtime === expectedRuntime, !node.isRetiringLazyListAttachment else { return false }
            if node === expectedRuntime.root { return true }
            guard let parent = node.parent, parent.children.contains(where: { $0 === node }) else { return false }
            current = parent
            depth += 1
        }
        return false
    }

    /// Native attribution and receipts remain sparse. Merely inspecting an
    /// ordinary node must not allocate activity or lifecycle storage.
    internal var retainedLazyListActivityStorage: RetainedLazyListNodeActivityStorage? {
        get { lifecycleHandlers?.retainedLazyListActivity }
        set {
            if let lifecycleHandlers {
                lifecycleHandlers.retainedLazyListActivity = newValue
            } else if let newValue {
                let handlers = ViewNodeLifecycleHandlers()
                handlers.retainedLazyListActivity = newValue
                lifecycleHandlers = handlers
            }
        }
    }

    /// Native presence only: reading these stored values executes no authored
    /// getter or equality. Scalar paint/layout defaults do not keep an old
    /// owner writable after its last reference-bearing field is replaced.
    internal var retainedSourcePayloadFields: [PartialKeyPath<ViewNode>] {
        var fields: [PartialKeyPath<ViewNode>] = []
        if canvasDraw != nil { fields.append(\.canvasDraw) }
        if onDeleteAction != nil { fields.append(\.onDeleteAction) }
        if onMoveAction != nil { fields.append(\.onMoveAction) }
        if dragContainerItemID != nil { fields.append(\.dragContainerItemID) }
        if fileExporterConfiguration != nil { fields.append(\.fileExporterConfiguration) }
        if fileImporterConfiguration != nil { fields.append(\.fileImporterConfiguration) }
        if fileImporterMultiConfiguration != nil { fields.append(\.fileImporterMultiConfiguration) }
        if fileMoverConfiguration != nil { fields.append(\.fileMoverConfiguration) }
        if accessibilityMagicTapAction != nil { fields.append(\.accessibilityMagicTapAction) }
        if platformView != nil { fields.append(\.platformView) }
        if platformViewCoordinator != nil { fields.append(\.platformViewCoordinator) }
        if onUpdatePlatformView != nil { fields.append(\.onUpdatePlatformView) }
        if onDismantlePlatformView != nil { fields.append(\.onDismantlePlatformView) }
        if textRenderer != nil { fields.append(\.textRenderer) }
        if widgetBackgroundStyle != nil { fields.append(\.widgetBackgroundStyle) }
        if retainedViewIdentity != nil { fields.append(\.retainedViewIdentity) }
        if retainedSubtreeBuildLease != nil { fields.append(\.retainedSubtreeBuildLease) }
        if retainedLazyListAdapter != nil { fields.append(\.retainedLazyListAdapter) }
        if textInputController != nil { fields.append(\.textInputController) }
        if !retainedScrollGeometryPayloads.isEmpty { fields.append(\.retainedScrollGeometryPayloads) }
        if !retainedScrollPhasePayloads.isEmpty { fields.append(\.retainedScrollPhasePayloads) }
        if !retainedScrollVisibilityPayloads.isEmpty { fields.append(\.retainedScrollVisibilityPayloads) }
        if onPointerEnter != nil { fields.append(\.onPointerEnter) }
        if onPointerExit != nil { fields.append(\.onPointerExit) }
        if onPointerMove != nil { fields.append(\.onPointerMove) }
        if onPointerDown != nil { fields.append(\.onPointerDown) }
        if onPointerUpInside != nil { fields.append(\.onPointerUpInside) }
        if onPointerUpInsideAt != nil { fields.append(\.onPointerUpInsideAt) }
        if onPointerUpOutside != nil { fields.append(\.onPointerUpOutside) }
        if onContextMenu != nil { fields.append(\.onContextMenu) }
        if onFocusEnter != nil { fields.append(\.onFocusEnter) }
        if onFocusExit != nil { fields.append(\.onFocusExit) }
        if onKeyDown != nil { fields.append(\.onKeyDown) }
        if onIMEComposition != nil { fields.append(\.onIMEComposition) }
        if textInputCaretRectProvider != nil { fields.append(\.textInputCaretRectProvider) }
        if onKeyUp != nil { fields.append(\.onKeyUp) }
        if onActivate != nil { fields.append(\.onActivate) }
        if onRepeatActivate != nil { fields.append(\.onRepeatActivate) }
        if longPressGesture != nil { fields.append(\.longPressGesture) }
        if onDeleteRows != nil { fields.append(\.onDeleteRows) }
        if onMoveRows != nil { fields.append(\.onMoveRows) }
        if onInsertRows != nil { fields.append(\.onInsertRows) }
        if onDropRows != nil { fields.append(\.onDropRows) }
        if onValidateDrop != nil { fields.append(\.onValidateDrop) }
        if onDropEntered != nil { fields.append(\.onDropEntered) }
        if onDropUpdated != nil { fields.append(\.onDropUpdated) }
        if onDropExited != nil { fields.append(\.onDropExited) }
        if onDropProviders != nil { fields.append(\.onDropProviders) }
        if onDropPayloads != nil { fields.append(\.onDropPayloads) }
        if onMakeDropConfiguration != nil { fields.append(\.onMakeDropConfiguration) }
        if onMakeDragPayload != nil { fields.append(\.onMakeDragPayload) }
        if onMakeDragItemProvider != nil { fields.append(\.onMakeDragItemProvider) }
        if onDragStart != nil { fields.append(\.onDragStart) }
        if onDragChange != nil { fields.append(\.onDragChange) }
        if onDragEnd != nil { fields.append(\.onDragEnd) }
        if onLayout != nil { fields.append(\.onLayout) }
        if onLayoutWithNode != nil { fields.append(\.onLayoutWithNode) }
        if absoluteChildFrame != nil { fields.append(\.absoluteChildFrame) }
        if onAppearWithNode != nil { fields.append(\.onAppearWithNode) }
        if onDisappearWithNode != nil { fields.append(\.onDisappearWithNode) }
        if onAppear != nil { fields.append(\.onAppear) }
        if onDisappear != nil { fields.append(\.onDisappear) }
        if onSizeChange != nil { fields.append(\.onSizeChange) }
        if geometryReaderBuild != nil { fields.append(\.geometryReaderBuild) }
        if !accessibilityActions.isEmpty { fields.append(\.accessibilityActions) }
        if !commandHandlers.isEmpty { fields.append(\.commandHandlers) }
        if !retainedPreferenceValues.isEmpty { fields.append(\.retainedPreferenceValues) }
        if !retainedLayoutValues.isEmpty { fields.append(\.retainedLayoutValues) }
        if !retainedContainerValues.isEmpty { fields.append(\.retainedContainerValues) }
        if !reconcileAnimationModifiers.isEmpty { fields.append(\.reconcileAnimationModifiers) }
        if !pendingLifecycleTaskLaunches.isEmpty { fields.append(\.pendingLifecycleTaskLaunches) }
        if swipeActionsLeading?.isEmpty == false { fields.append(\.swipeActionsLeading) }
        if swipeActionsTrailing?.isEmpty == false { fields.append(\.swipeActionsTrailing) }
        if toolbarTitleMenuChildren?.isEmpty == false { fields.append(\.toolbarTitleMenuChildren) }
        if toolbarTitleActionsChildren?.isEmpty == false { fields.append(\.toolbarTitleActionsChildren) }
        if accessibilityRepresentationChildren?.isEmpty == false {
            fields.append(\.accessibilityRepresentationChildren)
        }
        return fields
    }

    internal func retainedTaskState() -> RetainedTaskNodeState {
        if let state = lifecycleHandlers?.retainedTasks { return state }
        let handlers: ViewNodeLifecycleHandlers
        if let lifecycleHandlers {
            handlers = lifecycleHandlers
        } else {
            handlers = ViewNodeLifecycleHandlers()
            lifecycleHandlers = handlers
        }
        let state = RetainedTaskNodeState(node: self)
        handlers.retainedTasks = state
        return state
    }

    /// Construction's runtime argument is not proof of attachment. Check the
    /// actual root and every parent edge without authored identity operations.
    internal func isRetainedTaskTarget(in runtime: RetainedViewRuntime) -> Bool {
        guard self.runtime === runtime, runtime.permitsRetainedActionInvocation else { return false }
        var current: ViewNode? = self
        var depth = 0
        while let candidate = current, depth < Self.maximumTraversalDepth {
            guard candidate.acceptsLifecycleTasks, candidate.runtime === runtime, !candidate.isRemovalOverlay
            else { return false }
            if candidate === runtime.root { return true }
            guard let parent = candidate.parent, parent.children.contains(where: { $0 === candidate })
            else { return false }
            current = parent
            depth += 1
        }
        return false
    }

    internal func isRetainedTaskAppearanceCurrent(in runtime: RetainedViewRuntime, revision: UInt64) -> Bool {
        hasAppeared && hasPendingAppearanceCallbacks
            && runtime.isDeliveringRetainedTaskAppearance(revision: revision)
            && runtime.canDeliverRenderLifecycle(to: self)
    }

    internal func isRetainedLazyTaskRenderAdmissionCurrent(in runtime: RetainedViewRuntime, revision: UInt64) -> Bool {
        hasAppeared && !hasPendingAppearanceCallbacks
            && runtime.isDeliveringRetainedTaskAppearance(revision: revision)
            && runtime.canDeliverRenderLifecycle(to: self)
    }

    internal func hasCurrentCompletedRetainedTaskAppearance(
        in runtime: RetainedViewRuntime, attachment: RetainedLazyListActualAttachment
    ) -> Bool {
        guard hasAppeared, !hasPendingAppearanceCallbacks, runtime.canDeliverRenderLifecycle(to: self),
            let completed = lifecycleHandlers?.completedLazyTaskAppearance,
            completed.target === attachment.target, completed.attachment === attachment.attachment
        else { return false }
        return completed.isAttached && attachment.isAttached && isRetainedLazyListAttached(in: runtime)
    }

    @inline(__always)
    private func setInteractionHandler<Value>(
        _ value: Value?,
        at keyPath: ReferenceWritableKeyPath<ViewNodeInteractionHandlers, Value?>
    ) {
        if let interactionHandlers {
            interactionHandlers[keyPath: keyPath] = value
        } else if value != nil {
            let handlers = ViewNodeInteractionHandlers()
            handlers[keyPath: keyPath] = value
            interactionHandlers = handlers
        }
    }

    fileprivate var accessibilityAttachmentIdentity: RetainedAccessibilityIdentity {
        if let identity = storedAccessibilityAttachmentIdentity { return identity }
        let identity = RetainedAccessibilityIdentity()
        storedAccessibilityAttachmentIdentity = identity
        return identity
    }

    @inline(__always)
    private func setDropHandler<Value>(
        _ value: Value?,
        at keyPath: ReferenceWritableKeyPath<ViewNodeDropHandlers, Value?>
    ) {
        if let dropHandlers {
            dropHandlers[keyPath: keyPath] = value
        } else if value != nil {
            let handlers = ViewNodeDropHandlers()
            handlers[keyPath: keyPath] = value
            dropHandlers = handlers
        }
    }

    @inline(__always)
    private func setLifecycleHandler<Value>(
        _ value: Value?,
        at keyPath: ReferenceWritableKeyPath<ViewNodeLifecycleHandlers, Value?>
    ) {
        if let lifecycleHandlers {
            // Captured objects can reenter this slot during cleanup. Publish
            // the replacement and finish its exclusive write before releasing
            // the old handler, without delaying cleanup past this setter.
            let previous = lifecycleHandlers[keyPath: keyPath]
            lifecycleHandlers[keyPath: keyPath] = value
            withExtendedLifetime(previous) {}
        } else if value != nil {
            let handlers = ViewNodeLifecycleHandlers()
            handlers[keyPath: keyPath] = value
            lifecycleHandlers = handlers
        }
    }

    @inline(__always)
    private func setChartMetadata(
        _ value: String?,
        at keyPath: ReferenceWritableKeyPath<ViewNodeChartMetadata, String?>
    ) {
        if let chartMetadata {
            chartMetadata[keyPath: keyPath] = value
        } else if value != nil {
            let metadata = ViewNodeChartMetadata()
            metadata[keyPath: keyPath] = value
            chartMetadata = metadata
        }
        // Preserve the old stored properties' `didSet` semantics even when
        // clearing an already-empty field does not allocate a metadata bag.
        invalidateRuntime(.paint)
    }

    public var frame: Rect {
        didSet {
            // Controls recompute child geometry from onLayout. Reassigning
            // that same frame must not queue another layout forever or keep
            // programmatic scrolling waiting for geometry that is settled.
            guard frame != oldValue else { return }
            invalidateRuntime(.layout)
        }
    }

    public var backgroundColor: Color? {
        didSet {
            lifecycleHandlers?.retainedLazyListRowChrome?.noteExternalFieldAssignment()
            invalidateRuntime(.paint)
        }
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
        didSet {
            guard borderWidth != oldValue else { return }
            invalidateRuntime(.layout)
        }
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
        didSet {
            lifecycleHandlers?.retainedLazyListRowChrome?.noteExternalFieldAssignment()
            invalidateRuntime(.paint)
        }
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

    private var resolvedGridGeometry: GridLayoutGeometry?

    public var preferredSize: Size? {
        didSet { invalidateRuntime(.layout) }
    }

    /// Axes where a positive finite preference declares a fixed dimension.
    /// Ordinary preferences remain ideals. This intent is separate from
    /// `fixedSizeAxes`, which controls the proposal used for measurement.
    private var fixedPreferredSizeMask: UInt8 = 0
    public var fixedPreferredSizeAxes: LayoutFillAxes {
        get {
            LayoutFillAxes(horizontal: fixedPreferredSizeMask & 1 != 0, vertical: fixedPreferredSizeMask & 2 != 0)
        }
        set {
            let mask: UInt8 = (newValue.horizontal ? 1 : 0) | (newValue.vertical ? 2 : 0)
            guard mask != fixedPreferredSizeMask else { return }
            fixedPreferredSizeMask = mask
            invalidateRuntime(.layout)
        }
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

    /// A single-child frame offers both dimensions to its content. Ordinary
    /// stacks leave their main axis unbounded while measuring children.
    /// The forwarded size is a proposal; intrinsic content need not fill it.
    public var forwardsStackMainAxisProposal = false {
        didSet {
            guard forwardsStackMainAxisProposal != oldValue else { return }
            invalidateRuntime(.layout)
        }
    }

    /// The facade installs this on a centered one-child stack. An admitted
    /// finite measurement places its accepted child size without fitting again;
    /// declined proposals keep the original stack measurement and placement.
    package var aspectFitLayout: RetainedAspectFitLayout? {
        didSet {
            guard aspectFitLayout != oldValue else { return }
            invalidateRuntime(.layout)
        }
    }

    /// Intrinsically sized controls may opt into a directly enclosing fixed
    /// frame's proposal without becoming greedy in ordinary stacks or Forms.
    /// Keep this uncommon capability in one byte rather than an allocation.
    private var explicitFrameFillMask: UInt8 = 0
    public var explicitFrameFillAxes: LayoutFillAxes {
        get {
            LayoutFillAxes(horizontal: explicitFrameFillMask & 1 != 0, vertical: explicitFrameFillMask & 2 != 0)
        }
        set {
            let mask: UInt8 = (newValue.horizontal ? 1 : 0) | (newValue.vertical ? 2 : 0)
            guard mask != explicitFrameFillMask else { return }
            explicitFrameFillMask = mask
            invalidateRuntime(.layout)
        }
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

    /// Allocated only on views carrying scroll observation callbacks. Kept
    /// separately from diagnostic metadata so reconciliation can retain values.
    internal var scrollObserverStorage: RetainedScrollObserverStorage? {
        didSet {
            if scrollObserverStorage != nil {
                runtime?.registerScrollObservationNode(self)
            } else {
                runtime?.unregisterScrollObservationNode(self)
            }
            invalidateRuntime(.paint)
        }
    }

    internal var scrollContainerState: RetainedScrollContainerState?

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
        didSet {
            listNavigationOwner?.revokeIfRoleIsUnavailable()
            if scrollAxis != oldValue {
                runtime?.cancelScrollMomentum(for: self)
                runtime?.cancelScrollPresentedTween(for: self)
            }
            if let scrollAxis {
                if let state = scrollContainerState {
                    state.axis = scrollAxis
                } else {
                    scrollContainerState = RetainedScrollContainerState(axis: scrollAxis)
                }
            } else {
                scrollContainerState = nil
            }
            invalidateRuntime(.layout)
        }
    }

    /// Input policy is separate from the axis used for layout and paint. A
    /// disabled scroll view keeps its viewport, content extent and offset.
    /// Programmatic requests can still move it through scrollToDescendant.
    /// This retained bridge configures an existing scroll container: assign
    /// scrollAxis first. Ordinary nodes do not allocate or retain scroll policy.
    public var isScrollInputEnabled: Bool {
        get { scrollContainerState?.isInputEnabled ?? true }
        set {
            _ = reconcileScrollInputEnabled(newValue, admission: nil)
        }
    }

    private var storedScrollOffset: Double

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
        get { storedScrollOffset }
        set { _ = assignScrollOffset(newValue, admission: nil) }
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
            listNavigationOwner?.revokeIfRoleIsUnavailable()
            if !isFocusable, runtime?.focusedNode === self {
                runtime?.requestFocus(nil)
            }
            invalidateRuntime(.paint)
        }
    }

    public var isHitTestVisible: Bool {
        didSet {
            if !isHitTestVisible {
                runtime?.cancelLongPress(in: self)
            }
            invalidateRuntime(.paint)
        }
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
        didSet {
            listNavigationOwner?.revokeIfRoleIsUnavailable()
            invalidateRuntime(.paint)
        }
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

    /// Only a source bitmap leaf opts into cap/tile sampling. Symbol and
    /// already-composited image metadata must not resize their output twice.
    public var imageUsesBitmapResizing = false {
        didSet { invalidateRuntime(.paint) }
    }

    /// The last bitmap sampling resolution. Unsupported inputs skip that
    /// image, keep other paint commands, and remain inspectable by callers.
    public private(set) var imageSamplingFailure: ImageSamplingFailure?

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
        didSet {
            listNavigationOwner?.revokeIfRoleIsUnavailable()
            invalidateRuntime(.paint)
        }
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
        get { chartMetadata?.xAxis }
        set { setChartMetadata(newValue, at: \.xAxis) }
    }

    public var chartXScale: String? {
        get { chartMetadata?.xScale }
        set { setChartMetadata(newValue, at: \.xScale) }
    }

    public var chartYScale: String? {
        get { chartMetadata?.yScale }
        set { setChartMetadata(newValue, at: \.yScale) }
    }

    public var meshGradient: String? {
        get { chartMetadata?.meshGradient }
        set { setChartMetadata(newValue, at: \.meshGradient) }
    }

    public var chartYAxis: String? {
        get { chartMetadata?.yAxis }
        set { setChartMetadata(newValue, at: \.yAxis) }
    }

    public var chartLegend: String? {
        get { chartMetadata?.legend }
        set { setChartMetadata(newValue, at: \.legend) }
    }

    public var chartBackground: String? {
        get { chartMetadata?.background }
        set { setChartMetadata(newValue, at: \.background) }
    }

    public var chartPlotStyle: String? {
        get { chartMetadata?.plotStyle }
        set { setChartMetadata(newValue, at: \.plotStyle) }
    }

    public var chartOverlay: String? {
        get { chartMetadata?.overlay }
        set { setChartMetadata(newValue, at: \.overlay) }
    }

    public var chartSelection: String? {
        get { chartMetadata?.selection }
        set { setChartMetadata(newValue, at: \.selection) }
    }

    public var chartScrollableAxes: String? {
        get { chartMetadata?.scrollableAxes }
        set { setChartMetadata(newValue, at: \.scrollableAxes) }
    }

    public var chartForegroundStyleScale: String? {
        get { chartMetadata?.foregroundStyleScale }
        set { setChartMetadata(newValue, at: \.foregroundStyleScale) }
    }

    public var chartSymbolSize: String? {
        get { chartMetadata?.symbolSize }
        set { setChartMetadata(newValue, at: \.symbolSize) }
    }

    public var chartSymbol: String? {
        get { chartMetadata?.symbol }
        set { setChartMetadata(newValue, at: \.symbol) }
    }

    public var chartAngleScale: String? {
        get { chartMetadata?.angleScale }
        set { setChartMetadata(newValue, at: \.angleScale) }
    }

    public var chartBackgroundStyleScale: String? {
        get { chartMetadata?.backgroundStyleScale }
        set { setChartMetadata(newValue, at: \.backgroundStyleScale) }
    }

    public var chartSymbolScale: String? {
        get { chartMetadata?.symbolScale }
        set { setChartMetadata(newValue, at: \.symbolScale) }
    }

    public var chartXVisibleDomain: String? {
        get { chartMetadata?.xVisibleDomain }
        set { setChartMetadata(newValue, at: \.xVisibleDomain) }
    }

    public var chartYVisibleDomain: String? {
        get { chartMetadata?.yVisibleDomain }
        set { setChartMetadata(newValue, at: \.yVisibleDomain) }
    }

    public var chartXSelection: String? {
        get { chartMetadata?.xSelection }
        set { setChartMetadata(newValue, at: \.xSelection) }
    }

    public var chartYSelection: String? {
        get { chartMetadata?.ySelection }
        set { setChartMetadata(newValue, at: \.ySelection) }
    }

    public var chartAngleSelection: String? {
        get { chartMetadata?.angleSelection }
        set { setChartMetadata(newValue, at: \.angleSelection) }
    }

    public var chartScrollPositionX: String? {
        get { chartMetadata?.scrollPositionX }
        set { setChartMetadata(newValue, at: \.scrollPositionX) }
    }

    public var chartScrollPositionY: String? {
        get { chartMetadata?.scrollPositionY }
        set { setChartMetadata(newValue, at: \.scrollPositionY) }
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

    /// Modal intent can be explicit accessibility metadata or the portable
    /// SwiftUI presentation modifier that disables background interaction.
    /// The latter keeps custom overlays valid on Apple's SwiftUI, where
    /// `AccessibilityTraits.isModal` is not part of the public API.
    public var isModalPresentationScope: Bool {
        if accessibilityTraits.contains(.isModal) {
            return true
        }

        guard presentationChrome.hasBackgroundInteractionOverride,
            !presentationChrome.allowsBackgroundInteraction
        else {
            return false
        }

        // A sheet applies its presentation modifiers to the content node
        // that describes it, while the overlay itself owns the modal scope.
        // Treating that configuration as another nested presentation steals
        // Escape from the actual sheet. A standalone custom overlay still
        // becomes modal when no explicitly marked presentation contains it.
        var ancestor = parent
        while let candidate = ancestor {
            if candidate.accessibilityTraits.contains(.isModal) {
                return false
            }
            ancestor = candidate.parent
        }

        return true
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

    /// Typed declarative identity takes precedence over the legacy node tag
    /// during reconciliation. Raw retained nodes leave this nil and retain
    /// their existing tag or positional matching behavior.
    public var retainedViewIdentity: RetainedViewIdentity? {
        willSet { lifecycleHandlers?.lazyListViewIdentity = nil }
    }

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

    private var animationModifierStorage: RetainedAnimationModifierStorage?

    /// Declarative modifiers, in the order they are attached while building
    /// the view (inner first). The host evaluates them from outer to inner
    /// and retains their triggers across rebuilds.
    public var reconcileAnimationModifiers: [RetainedAnimationModifier] {
        get { animationModifierStorage?.modifiers ?? [] }
        set {
            guard !newValue.isEmpty || animationModifierStorage != nil else { return }
            if animationModifierStorage == nil {
                animationModifierStorage = RetainedAnimationModifierStorage()
            }
            animationModifierStorage?.modifiers = newValue
        }
    }

    /// Insertion runs after reconciliation, when the ambient modifier scope
    /// has unwound. Keep its effective transaction until that first arrival.
    func retainInsertionTransaction(_ transaction: Transaction?) {
        guard transition.kind != .identity, !didPlayInsertionTransition else { return }
        guard transaction != nil || animationModifierStorage != nil else { return }
        if animationModifierStorage == nil {
            animationModifierStorage = RetainedAnimationModifierStorage()
        }
        animationModifierStorage?.insertionTransaction = transaction
    }

    @discardableResult
    func retainInsertionTransaction(
        _ transaction: Transaction?, admission: RetainedLazyListAdoptionAdmission?
    ) -> Bool {
        guard admission?.isCurrent != false else { return false }
        replaceInsertionTransactionPayload(transaction, admission: admission)
        return admission?.isCurrent != false
    }

    private func replaceInsertionTransactionPayload(
        _ transaction: Transaction?, admission: RetainedLazyListAdoptionAdmission?
    ) {
        let previous = animationModifierStorage?.insertionTransaction
        if transition.kind != .identity, !didPlayInsertionTransition,
            transaction != nil || animationModifierStorage != nil
        {
            admission?.markMutationStarted()
            retainInsertionTransaction(transaction)
        }
        withExtendedLifetime(previous) {}
    }

    /// Marks this node as a text input's insertion indicator, so the runtime
    /// can blink it. Set by the text-input chrome builder; nothing else in the
    /// tree carries it.
    public var isTextInputCaret = false

    public var onPointerEnter: (() -> Void)? {
        get { interactionHandlers?.pointerEnter }
        set { setInteractionHandler(newValue, at: \.pointerEnter) }
    }
    public var onPointerExit: (() -> Void)? {
        get { interactionHandlers?.pointerExit }
        set { setInteractionHandler(newValue, at: \.pointerExit) }
    }
    public var onPointerMove: ((Point) -> Void)? {
        get { interactionHandlers?.pointerMove }
        set { setInteractionHandler(newValue, at: \.pointerMove) }
    }
    public var onPointerDown: (() -> Void)? {
        get { interactionHandlers?.pointerDown }
        set { setInteractionHandler(newValue, at: \.pointerDown) }
    }
    public var onPointerUpInside: (() -> Void)? {
        get { interactionHandlers?.pointerUpInside }
        set { setInteractionHandler(newValue, at: \.pointerUpInside) }
    }
    public var onPointerUpInsideAt: ((Point) -> Void)? {
        get { interactionHandlers?.pointerUpInsideAt }
        set { setInteractionHandler(newValue, at: \.pointerUpInsideAt) }
    }
    public var onPointerUpOutside: (() -> Void)? {
        get { interactionHandlers?.pointerUpOutside }
        set { setInteractionHandler(newValue, at: \.pointerUpOutside) }
    }
    public var onContextMenu: ((Point) -> Void)? {
        get { interactionHandlers?.contextMenu }
        set { setInteractionHandler(newValue, at: \.contextMenu) }
    }
    public var onFocusEnter: (() -> Void)? {
        get { interactionHandlers?.focusEnter }
        set { setInteractionHandler(newValue, at: \.focusEnter) }
    }
    public var onFocusExit: (() -> Void)? {
        get { interactionHandlers?.focusExit }
        set { setInteractionHandler(newValue, at: \.focusExit) }
    }
    public var onKeyDown: ((KeyboardEvent) -> Void)? {
        get { interactionHandlers?.keyDown }
        set { setInteractionHandler(newValue, at: \.keyDown) }
    }
    /// IME composition events routed by the runtime to the focused node;
    /// installed by text inputs, `nil` elsewhere.
    public var onIMEComposition: ((IMECompositionEvent) -> Void)? {
        get { interactionHandlers?.imeComposition }
        set { setInteractionHandler(newValue, at: \.imeComposition) }
    }
    /// Reports the caret rectangle in root (logical) coordinates so the
    /// window host can position the OS IME candidate/composition window.
    /// Installed by text inputs; `nil` elsewhere.
    public var textInputCaretRectProvider: (() -> Rect?)? {
        get { interactionHandlers?.textInputCaretRectProvider }
        set { setInteractionHandler(newValue, at: \.textInputCaretRectProvider) }
    }

    /// Optional editor-only state; ordinary nodes do not allocate a controller.
    public var textInputController: (any RetainedTextInputController)? {
        get { interactionHandlers?.textInputController }
        set {
            setInteractionHandler(newValue, at: \.textInputController)
            // Reconciliation can install an editor on an already-attached
            // node without changing child identities or calling setRuntime.
            if runtime != nil, !isRetiringLazyListAttachment { newValue?.attach(to: self) }
        }
    }

    func reconcileTextInputController(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil
    ) -> Bool {
        guard admission?.isCurrent != false else { return false }
        if let lazyJournal {
            let checked = admission != nil || !lazyJournal.isOrdinaryAdoption
            let targetAttachment = checked ? captureLazyListAttachmentProof() : nil
            let targetIdentity = checked ? captureLazyListIdentityProof() : nil
            let sourceAttachment = checked ? source.captureLazyListAttachmentProof() : nil
            let sourceIdentity = checked ? source.captureLazyListIdentityProof() : nil
            let completed = reconcileJournalTextInputController(
                from: source, admission: admission, journal: lazyJournal, taskAdoption: taskAdoption)
            return completed && admission?.isCurrent != false
                && (lazyJournal.isOrdinaryAdoption || lazyJournal.canContinueAdoption)
                && targetAttachment?.isCurrent != false && targetIdentity?.isCurrent != false
                && sourceAttachment?.isCurrent != false && sourceIdentity?.isCurrent != false
        }
        let completed = reconcileTextInputControllerPayload(from: source, admission: admission)
        // Controller payload destruction happens before this final primitive
        // check, outside the stored handler's exclusive write access.
        return completed && admission?.isCurrent != false
    }

    private func reconcileTextInputControllerPayload(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission?
    ) -> Bool {
        let previous = textInputController
        let incoming = source.textInputController
        guard let admission else {
            if let incoming {
                textInputController = incoming
                incoming.reconcile(from: previous, onto: self)
            } else if let previous {
                previous.detach(from: self)
                textInputController = nil
            }
            return true
        }
        let attachment = captureLazyListAttachmentProof()
        guard admission.isCurrent, attachment.isCurrent else { return false }
        if let incoming {
            admission.markMutationStarted()
            textInputController = incoming
            guard admission.isCurrent, attachment.isCurrent, textInputController === incoming else { return false }
            incoming.reconcile(from: previous, onto: self)
            guard admission.isCurrent, attachment.isCurrent, textInputController === incoming else { return false }
        } else if let previous {
            admission.markMutationStarted()
            previous.detach(from: self)
            guard admission.isCurrent, attachment.isCurrent, textInputController === previous else { return false }
            textInputController = nil
        }
        withExtendedLifetime(previous) {}
        return admission.isCurrent && attachment.isCurrent
    }

    /// Publish the actual controller field before attach/reconcile can release
    /// callbacks held by the displaced controller. Ordinary nil calls above
    /// retain their existing setter and lifecycle order.
    private func reconcileJournalTextInputController(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission?,
        journal: RetainedLazyListAdoptionJournal, taskAdoption: RetainedTaskAdoptionContext?
    ) -> Bool {
        let previous = textInputController
        let incoming = source.textInputController
        let checked = admission != nil || !journal.isOrdinaryAdoption
        let targetAttachment = checked ? captureLazyListAttachmentProof() : nil
        let targetIdentity = checked ? captureLazyListIdentityProof() : nil
        let sourceAttachment = checked ? source.captureLazyListAttachmentProof() : nil
        let sourceIdentity = checked ? source.captureLazyListIdentityProof() : nil
        func isCurrent() -> Bool {
            admission?.isCurrent != false
                && (journal.isOrdinaryAdoption || journal.canContinueAdoption)
                && targetAttachment?.isCurrent != false && targetIdentity?.isCurrent != false
                && sourceAttachment?.isCurrent != false && sourceIdentity?.isCurrent != false
                && (!checked || source.textInputController === incoming)
        }
        guard isCurrent() else { return false }
        if incoming == nil, previous == nil { return true }
        let prepared = journal.preparePropertyCopy(from: source, to: self, keyPath: \ViewNode.textInputController)
        guard journal.isOrdinaryAdoption || prepared else { return false }
        let started = journal.markMutationStarted()
        guard journal.isOrdinaryAdoption || started else { return false }
        admission?.markMutationStarted()
        if let incoming {
            // The public setter immediately calls attach. Keep the same native
            // write and callback order, with acceptance between those steps.
            setInteractionHandler(incoming, at: \.textInputController)
            recordAcceptedLazyProperty(
                from: source, keyPath: \ViewNode.textInputController, journal: journal, taskAdoption: taskAdoption)
            guard isCurrent(), textInputController === incoming else { return false }
            if runtime != nil, !isRetiringLazyListAttachment { incoming.attach(to: self) }
            guard isCurrent(), textInputController === incoming else { return false }
            incoming.reconcile(from: previous, onto: self)
            guard isCurrent(), textInputController === incoming else { return false }
        } else if let previous {
            previous.detach(from: self)
            guard isCurrent(), textInputController === previous else { return false }
            setInteractionHandler(nil, at: \.textInputController)
            recordAcceptedLazyProperty(
                from: source, keyPath: \ViewNode.textInputController, journal: journal, taskAdoption: taskAdoption)
        }
        withExtendedLifetime(previous) {}
        return isCurrent()
    }

    private func recordAcceptedLazyProperty(
        from source: ViewNode, keyPath: PartialKeyPath<ViewNode>, journal: RetainedLazyListAdoptionJournal,
        taskAdoption: RetainedTaskAdoptionContext?
    ) {
        for group in journal.recordAcceptedProperty(from: source, to: self, keyPath: keyPath) {
            taskAdoption?.associateLazyAccepted(group, journal: journal)
        }
        for group in journal.takeAcceptedDescriptorTaskGroups() {
            taskAdoption?.associateDescriptorAccepted(group, journal: journal)
        }
    }

    /// List-only ownership stays in optional interaction storage. The facade
    /// captures this declaration; adoption redirects it to the retained node.
    package var listNavigationOwner: RetainedListNavigationOwner? {
        get { interactionHandlers?.listNavigationOwner }
        set { setInteractionHandler(newValue, at: \.listNavigationOwner) }
    }

    func installListNavigationOwner(_ owner: RetainedListNavigationOwner) {
        listNavigationOwner = owner
        if let runtime { owner.didAttach(to: runtime) }
    }

    func hasListNavigationRuntime(_ expected: RetainedViewRuntime?) -> Bool {
        runtime === expected
    }

    @discardableResult
    func adoptListNavigationOwner(from source: ViewNode) -> RetainedListNavigationOwner? {
        guard source !== self else { return nil }
        let incoming = source.listNavigationOwner
        incoming?.adopt(from: listNavigationOwner, onto: self, runtime: runtime)
        listNavigationOwner = incoming
        // Disposing the fresh build must not revoke the retained attachment.
        source.listNavigationOwner = nil
        return incoming
    }
    /// When true, unmodified up/down arrow keys are delivered to this node's
    /// `onKeyDown` before the runtime's scroll-key handling, so a focused node
    /// (e.g. a selectable list row) can claim vertical arrows for navigation.
    /// Text inputs also claim Up/Down/Home/End with Shift and/or Control.
    public var interceptsVerticalArrowKeys = false {
        didSet { listNavigationOwner?.revokeIfRoleIsUnavailable() }
    }
    public var onKeyUp: ((KeyboardEvent) -> Void)? {
        get { interactionHandlers?.keyUp }
        set { setInteractionHandler(newValue, at: \.keyUp) }
    }
    public var onActivate: (() -> Void)? {
        get { interactionHandlers?.activate }
        set { setInteractionHandler(newValue, at: \.activate) }
    }
    public var onRepeatActivate: (() -> Void)? {
        get { interactionHandlers?.repeatActivate }
        set { setInteractionHandler(newValue, at: \.repeatActivate) }
    }
    public var longPressGesture: RetainedLongPressGesture? {
        get { interactionHandlers?.longPressGesture }
        set {
            setInteractionHandler(newValue, at: \.longPressGesture)
            runtime?.longPressConfigurationDidChange(on: self)
        }
    }
    public var onDeleteRows: ((IndexSet) -> Void)? {
        get { dropHandlers?.deleteRows }
        set { setDropHandler(newValue, at: \.deleteRows) }
    }
    public var onMoveRows: ((IndexSet, Int) -> Void)? {
        get { dropHandlers?.moveRows }
        set { setDropHandler(newValue, at: \.moveRows) }
    }
    public var onInsertRows: ((Int, [Any]) -> Void)? {
        get { dropHandlers?.insertRows }
        set { setDropHandler(newValue, at: \.insertRows) }
    }
    public var onDropRows: (([Any], Int) -> Void)? {
        get { dropHandlers?.dropRows }
        set { setDropHandler(newValue, at: \.dropRows) }
    }
    public var onValidateDrop: (([Any], Point) -> Bool)? {
        get { dropHandlers?.validateDrop }
        set { setDropHandler(newValue, at: \.validateDrop) }
    }
    public var onDropEntered: (([Any], Point) -> Void)? {
        get { dropHandlers?.dropEntered }
        set { setDropHandler(newValue, at: \.dropEntered) }
    }
    public var onDropUpdated: (([Any], Point) -> Any?)? {
        get { dropHandlers?.dropUpdated }
        set { setDropHandler(newValue, at: \.dropUpdated) }
    }
    public var onDropExited: (() -> Void)? {
        get { dropHandlers?.dropExited }
        set { setDropHandler(newValue, at: \.dropExited) }
    }
    public var onDropProviders: (([Any], Point) -> Bool)? {
        get { dropHandlers?.dropProviders }
        set { setDropHandler(newValue, at: \.dropProviders) }
    }
    public var onDropPayloads: (([Any], Point) -> Bool)? {
        get { dropHandlers?.dropPayloads }
        set { setDropHandler(newValue, at: \.dropPayloads) }
    }
    public var onMakeDropConfiguration: (([Any], Point) -> Any?)? {
        get { dropHandlers?.makeDropConfiguration }
        set { setDropHandler(newValue, at: \.makeDropConfiguration) }
    }
    public var onMakeDragPayload: (() -> Any?)? {
        get { dropHandlers?.makeDragPayload }
        set { setDropHandler(newValue, at: \.makeDragPayload) }
    }
    public var commandHandlers: [String: () -> Void] = [:]
    private weak var fileDialogPresenterLease: RetainedFileDialogPresenterLease?
    private var fileDialogPresenterIsDeparting = false
    private var fileDialogPreparedRevocations: UInt8 = 0
    public var fileExporterConfiguration: RetainedFileExporterConfiguration? {
        willSet {
            if newValue == nil, fileDialogPresenterLease?.kind == .exporter {
                fileDialogPresenterLease?.invalidate()
            }
        }
    }
    public var fileImporterConfiguration: RetainedFileImporterConfiguration? {
        willSet {
            if newValue == nil, fileDialogPresenterLease?.kind == .importer {
                fileDialogPresenterLease?.invalidate()
            }
        }
    }
    public var fileImporterMultiConfiguration: RetainedFileImporterMultiConfiguration? {
        willSet {
            if newValue == nil, fileDialogPresenterLease?.kind == .importerMulti {
                fileDialogPresenterLease?.invalidate()
            }
        }
    }
    public var fileMoverConfiguration: RetainedFileMoverConfiguration? {
        willSet {
            if newValue == nil, fileDialogPresenterLease?.kind == .mover {
                fileDialogPresenterLease?.invalidate()
            }
        }
    }
    public var inspectorColumnWidth: Double?
    public var inspectorColumnWidthFraction: Double?
    public var inspectorColumnWidthMin: Double?
    public var inspectorPresentationStyle: InspectorPresentationStyle?
    public var fileDialogCustomizationID: String?
    public var fileDialogConfirmationLabel: String?
    public var fileDialogDefaultDirectory: URL?
    public var fileDialogMessage: String?
    public var onMakeDragItemProvider: (() -> Any?)? {
        get { dropHandlers?.makeDragItemProvider }
        set { setDropHandler(newValue, at: \.makeDragItemProvider) }
    }
    public var onDragStart: ((Point) -> Void)? {
        get { dropHandlers?.dragStart }
        set { setDropHandler(newValue, at: \.dragStart) }
    }
    public var onDragChange: ((Point, Point) -> Void)? {
        get { dropHandlers?.dragChange }
        set { setDropHandler(newValue, at: \.dragChange) }
    }
    public var onDragEnd: ((Point, Point) -> Void)? {
        get { dropHandlers?.dragEnd }
        set { setDropHandler(newValue, at: \.dragEnd) }
    }
    public var onLayout: ((Rect) -> Void)? {
        get { lifecycleHandlers?.layout }
        set { setLifecycleHandler(newValue, at: \.layout) }
    }
    /// Updates geometry on the live retained node after the legacy layout callback.
    /// Taking the node as an argument avoids capturing a temporary node produced
    /// while rebuilding components and later discarded during reconciliation.
    package var onLayoutWithNode: ((ViewNode, Rect) -> Void)? {
        get { lifecycleHandlers?.layoutWithNode }
        set {
            guard newValue != nil || lifecycleHandlers?.layoutWithNode != nil else { return }
            setLifecycleHandler(newValue, at: \.layoutWithNode)
            invalidateRuntime(.layout)
        }
    }
    /// Places each live child of an absolute container in the container's
    /// resolved bounds. The returned frame is layout output, not an authored
    /// sizing input: it never replaces the child's intrinsic frame or queues
    /// another layout pass. Kept in sparse storage for custom containers.
    public var absoluteChildFrame: ((ViewNode, Rect) -> Rect)? {
        get { lifecycleHandlers?.absoluteChildFrame }
        set {
            guard newValue != nil || lifecycleHandlers?.absoluteChildFrame != nil else { return }
            setLifecycleHandler(newValue, at: \.absoluteChildFrame)
            invalidateRuntime(.layout)
        }
    }
    public var onAppearWithNode: ((ViewNode) -> Void)? {
        get { lifecycleHandlers?.appearWithNode }
        set { setLifecycleHandler(newValue, at: \.appearWithNode) }
    }
    public var onDisappearWithNode: ((ViewNode) -> Void)? {
        get { lifecycleHandlers?.disappearWithNode }
        set { setLifecycleHandler(newValue, at: \.disappearWithNode) }
    }
    public var pendingLifecycleTaskLaunches: [ViewLifecycleTaskLaunch] = []

    // Lifecycle hooks are delivered by the shared render lifecycle pass, or
    // by removal when a previously appeared node leaves the retained tree.
    public var onAppear: (() -> Void)? {
        get { lifecycleHandlers?.appear }
        set { setLifecycleHandler(newValue, at: \.appear) }
    }
    public var onDisappear: (() -> Void)? {
        get { lifecycleHandlers?.disappear }
        set { setLifecycleHandler(newValue, at: \.disappear) }
    }
    public var onSizeChange: ((Rect) -> Void)? {
        get { lifecycleHandlers?.sizeChange }
        set { setLifecycleHandler(newValue, at: \.sizeChange) }
    }

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
    public var geometryReaderBuild: ((RetainedViewRuntime, Size) -> [ViewNode])? {
        get { lifecycleHandlers?.geometryReaderBuild }
        set { setLifecycleHandler(newValue, at: \.geometryReaderBuild) }
    }

    /// Ownership of this deferred subtree's captured generation. Adoption
    /// copies this metadata without retiring an owner that survives the build.
    public var retainedSubtreeBuildLease: (any RetainedSubtreeBuildLease)? {
        get { lifecycleHandlers?.retainedSubtreeBuildLease }
        set {
            if lifecycleHandlers?.retainedSubtreeBuildLease !== newValue {
                lifecycleHandlers?.retainedLazyListAdapter?.revokePendingCandidate()
            }
            setLifecycleHandler(newValue, at: \.retainedSubtreeBuildLease)
        }
    }

    /// Deferred public List construction shares the ordinary retained build,
    /// state, and input lifetimes. Sparse lifecycle storage keeps nodes that
    /// are not lazy List containers unchanged.
    package var retainedLazyListAdapter: RetainedLazyListRuntimeAdapter? {
        get { lifecycleHandlers?.retainedLazyListAdapter }
        set {
            setRetainedLazyListAdapter(newValue, descriptorCopy: .unmanaged, lazyJournal: nil)
        }
    }

    package var retainedLazyListGap: RetainedLazyListGap? {
        get { lifecycleHandlers?.retainedLazyListGap }
        set {
            guard lifecycleHandlers?.retainedLazyListGap != newValue else { return }
            setLifecycleHandler(newValue, at: \.retainedLazyListGap)
            invalidateRuntime(.layout)
        }
    }

    package var retainedLazyListRowChrome: RetainedLazyListRowChrome? {
        get { lifecycleHandlers?.retainedLazyListRowChrome?.metadata }
        set {
            guard newValue != nil || lifecycleHandlers?.retainedLazyListRowChrome != nil else { return }
            // A fresh accepted row declaration resets this native publication
            // even when the palette is equal. Its background property has
            // already been reconciled before ComponentHost copies this field.
            let publication = newValue.map {
                RetainedLazyListRowChromePublication(
                    metadata: $0, initialBackground: backgroundColor, initialCornerRadius: cornerRadius)
            }
            setLifecycleHandler(publication, at: \.retainedLazyListRowChrome)
            invalidateRuntime(.layout)
        }
    }

    package var retainedLazyListRowChromeUsesEstimatedParity: Bool? {
        lifecycleHandlers?.retainedLazyListRowChrome?.usesEstimatedParity
    }

    fileprivate func publishRetainedLazyListRowChrome(isOdd: Bool, hasUnknownPrefix: Bool) {
        guard let publication = lifecycleHandlers?.retainedLazyListRowChrome else { return }
        publication.usesEstimatedParity = hasUnknownPrefix
        guard !publication.isSuppressed else { return }
        guard backgroundColor == publication.expectedBackground, cornerRadius == publication.expectedCornerRadius else {
            // Raw authored mutation after the declaration wins. A later fresh
            // declaration can opt back in after its own eligibility check.
            publication.isSuppressed = true
            return
        }
        let color = isOdd ? publication.metadata.alternatingBackground : nil
        let radius = isOdd ? max(publication.originalCornerRadius, 8) : publication.originalCornerRadius
        publication.expectedBackground = color
        publication.expectedCornerRadius = radius
        publication.isPublishing = true
        defer { publication.isPublishing = false }
        if backgroundColor != color { backgroundColor = color }
        if cornerRadius != radius { cornerRadius = radius }
    }

    private func setRetainedLazyListAdapter(
        _ incoming: RetainedLazyListRuntimeAdapter?,
        descriptorCopy: RetainedLazyListDescriptorCopyPreparation,
        lazyJournal: RetainedLazyListAdoptionJournal?, source: ViewNode? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil
    ) {
        let previous = lifecycleHandlers?.retainedLazyListAdapter
        guard !isRetiringLazyListAttachment, previous !== incoming else { return }
        let ownedPrevious = previous?.ownsAttachment(self) == true
        let inheritsMountedRecords: Bool
        if source != nil, ownedPrevious, let previous, let incoming {
            inheritsMountedRecords = incoming.canInheritMountedRecords(from: previous, in: self)
        } else {
            inheritsMountedRecords = false
        }
        // A staged successor is a conditional continuation, not permission to
        // replace the List if its original predecessor proof has expired.
        if runtime != nil, incoming?.hasStagedPredecessor == true, !inheritsMountedRecords { return }
        if !inheritsMountedRecords { previous?.revokePendingCandidate() }
        runtime?.unregisterLazyListContainer(self, revokingAdapter: !inheritsMountedRecords)
        setLifecycleHandler(incoming, at: \.retainedLazyListAdapter)
        if case .ready(let publication) = descriptorCopy {
            // Releasing old mounted records can run application destructors
            // even while their adapter remains pinned. Publish here, before
            // that release, rather than after the property's setter returns.
            lazyJournal?.recordAcceptedLogicalDeclaration(publication)
        } else if case .removal(let publication) = descriptorCopy {
            lazyJournal?.recordAcceptedLogicalScopeRemoval(publication)
        }
        if inheritsMountedRecords, let previous, let incoming {
            // Both stages are native publications. Transfer the existing
            // physical records before property/task transport or old payload
            // cleanup can call out. New factories still run under the fresh
            // descriptor and reconcile onto these retained children.
            _ = incoming.inheritMountedRecords(from: previous, in: self)
        }
        if let lazyJournal, let source {
            recordAcceptedLazyProperty(
                from: source, keyPath: \ViewNode.retainedLazyListAdapter,
                journal: lazyJournal, taskAdoption: taskAdoption)
        }
        if ownedPrevious {
            // Keep the weak claim until destructors from old mapped leaves
            // finish; they cannot install this adapter elsewhere and have its
            // new records cleared by this old release.
            previous?.releaseMountedRecords(journal: lazyJournal)
            previous?.releaseAttachment(from: self)
        }
        if lifecycleHandlers?.retainedLazyListAdapter === incoming, incoming != nil {
            runtime?.registerLazyListContainer(self)
        }
        invalidateRuntime(.layout)
        withExtendedLifetime(previous) {}
    }

    /// The facade will supply revisions captured with its inherited build
    /// environment. These are cache tags, never build or input authority.
    /// Width and display scale are supplied by actual retained layout.
    package func setRetainedLazyListMeasurementRevisions(content: UInt64, environment: UInt64) {
        guard lazyListContentRevision != content || lazyListEnvironmentRevision != environment else { return }
        retainedLazyListAdapter?.revokePendingCandidate()
        if lifecycleHandlers == nil { lifecycleHandlers = ViewNodeLifecycleHandlers() }
        lifecycleHandlers?.lazyListContentRevision = content
        lifecycleHandlers?.lazyListEnvironmentRevision = environment
        invalidateRuntime(.layout)
    }

    fileprivate var lazyListContentRevision: UInt64 { lifecycleHandlers?.lazyListContentRevision ?? 0 }
    fileprivate var lazyListEnvironmentRevision: UInt64 { lifecycleHandlers?.lazyListEnvironmentRevision ?? 0 }

    fileprivate var lazyListAttachmentIdentity: RetainedLazyListAttachmentIdentity? {
        lifecycleHandlers?.lazyListAttachmentIdentity
    }

    fileprivate var lazyListLayoutIdentity: RetainedLazyListAttachmentIdentity? {
        lifecycleHandlers?.lazyListLayoutIdentity
    }

    fileprivate var lazyListViewIdentity: RetainedLazyListAttachmentIdentity? {
        lifecycleHandlers?.lazyListViewIdentity
    }

    fileprivate var lazyListScrollIntentIdentity: RetainedLazyListAttachmentIdentity? {
        lifecycleHandlers?.lazyListScrollIntentIdentity
    }

    fileprivate func revokeLazyListScrollIntent() {
        lifecycleHandlers?.lazyListScrollIntentIdentity = nil
    }

    fileprivate func captureLazyListScrollIntentIdentity() -> RetainedLazyListAttachmentIdentity {
        if lifecycleHandlers == nil { lifecycleHandlers = ViewNodeLifecycleHandlers() }
        if lifecycleHandlers?.lazyListScrollIntentIdentity == nil {
            lifecycleHandlers?.lazyListScrollIntentIdentity = RetainedLazyListAttachmentIdentity()
        }
        return lifecycleHandlers!.lazyListScrollIntentIdentity!
    }

    func captureLazyListIdentityProof() -> RetainedLazyListViewIdentityProof {
        if lifecycleHandlers == nil { lifecycleHandlers = ViewNodeLifecycleHandlers() }
        if lifecycleHandlers?.lazyListViewIdentity == nil {
            lifecycleHandlers?.lazyListViewIdentity = RetainedLazyListAttachmentIdentity()
        }
        return RetainedLazyListViewIdentityProof(node: self, identity: lifecycleHandlers!.lazyListViewIdentity!)
    }

    fileprivate func captureLazyListLocalLayoutProof() -> RetainedLazyListLocalLayoutProof {
        let attachment = captureLazyListAttachmentProof()
        if lifecycleHandlers?.lazyListLayoutIdentity == nil {
            lifecycleHandlers?.lazyListLayoutIdentity = RetainedLazyListAttachmentIdentity()
        }
        return RetainedLazyListLocalLayoutProof(
            node: self, identity: lifecycleHandlers!.lazyListLayoutIdentity!, attachment: attachment)
    }

    fileprivate var isRetiringLazyListAttachment: Bool {
        lifecycleHandlers?.lazyListRetirementIdentity != nil
    }

    func captureLazyListAttachmentProof() -> RetainedLazyListAttachmentProof {
        if lifecycleHandlers == nil { lifecycleHandlers = ViewNodeLifecycleHandlers() }
        if lifecycleHandlers?.lazyListAttachmentIdentity == nil {
            lifecycleHandlers?.lazyListAttachmentIdentity = RetainedLazyListAttachmentIdentity()
        }
        return RetainedLazyListAttachmentProof(
            node: self, identity: lifecycleHandlers!.lazyListAttachmentIdentity!)
    }

    /// Revoke before a callback can observe a detach, including a move through
    /// detached construction parents. Returning to the same parent is new.
    fileprivate func revokeLazyListAttachmentProofs() {
        // Detached source transfers have never published physical activity.
        // Their reserved insertion IDs must survive until that first write.
        if runtime != nil { retainedLazyListActivityStorage?.revokeAttachment() }
        lifecycleHandlers?.completedLazyTaskAppearance = nil
        lifecycleHandlers?.lazyListAttachmentIdentity = nil
        lifecycleHandlers?.retainedLazyListAdapter?.revokePendingCandidate()
    }

    func childrenForLazyListReconciliation(from source: ViewNode) -> [ViewNode] {
        if let adapter = retainedLazyListAdapter, let incoming = source.retainedLazyListAdapter {
            if incoming === adapter || incoming.canInheritMountedRecords(from: adapter, in: self) {
                return children
            }
        }
        return source.children
    }

    func canAdoptStagedLazyListAdapter(from source: ViewNode) -> Bool {
        guard let incoming = source.retainedLazyListAdapter, incoming.hasStagedPredecessor else { return true }
        guard let previous = retainedLazyListAdapter else { return false }
        return incoming.canInheritMountedRecords(from: previous, in: self)
    }

    func reconcileLazyListAdapter(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil
    ) -> Bool {
        let metadataOnly = lazyJournal?.isOrdinaryAdoption == true
        guard admission?.isCurrent != false, metadataOnly || lazyJournal?.canContinueAdoption != false else {
            return false
        }
        guard canAdoptStagedLazyListAdapter(from: source) else { return false }
        let descriptorCopy: RetainedLazyListDescriptorCopyPreparation
        if let lazyJournal, !metadataOnly || lazyJournal.canContinueAdoption {
            descriptorCopy = lazyJournal.prepareDescriptorCopy(from: source, to: self)
        } else {
            descriptorCopy = .unmanaged
        }
        if case .rejected = descriptorCopy { return false }
        if retainedLazyListAdapter !== source.retainedLazyListAdapter {
            if let lazyJournal {
                let prepared = lazyJournal.preparePropertyCopy(
                    from: source, to: self, keyPath: \ViewNode.retainedLazyListAdapter)
                guard metadataOnly || prepared else { return false }
            }
            let started = lazyJournal?.markMutationStarted()
            guard metadataOnly || started != false else { return false }
            admission?.markMutationStarted()
            replaceLazyListAdapterPayload(
                with: source.retainedLazyListAdapter, descriptorCopy: descriptorCopy, lazyJournal: lazyJournal,
                source: source, taskAdoption: taskAdoption)
        }
        guard admission?.isCurrent != false, metadataOnly || lazyJournal?.canContinueAdoption != false else {
            return false
        }
        if lazyListContentRevision != source.lazyListContentRevision
            || lazyListEnvironmentRevision != source.lazyListEnvironmentRevision
        {
            let started = lazyJournal?.markMutationStarted()
            guard metadataOnly || started != false else { return false }
            admission?.markMutationStarted()
            setRetainedLazyListMeasurementRevisions(
                content: source.lazyListContentRevision, environment: source.lazyListEnvironmentRevision)
        }
        return admission?.isCurrent != false && (metadataOnly || lazyJournal?.canContinueAdoption != false)
    }

    private func replaceLazyListAdapterPayload(
        with incoming: RetainedLazyListRuntimeAdapter?,
        descriptorCopy: RetainedLazyListDescriptorCopyPreparation,
        lazyJournal: RetainedLazyListAdoptionJournal?, source: ViewNode,
        taskAdoption: RetainedTaskAdoptionContext?
    ) {
        let previous = retainedLazyListAdapter
        setRetainedLazyListAdapter(
            incoming, descriptorCopy: descriptorCopy, lazyJournal: lazyJournal, source: source,
            taskAdoption: taskAdoption)
        withExtendedLifetime(previous) {}
    }

    func reconciliationAnimationTime(admission: RetainedLazyListAdoptionAdmission? = nil) -> Double? {
        guard admission?.isCurrent != false else { return nil }
        let time = animationClockNow
        guard admission?.isCurrent != false else { return nil }
        if let admission, !time.isFinite {
            admission.revoke()
            return nil
        }
        return time
    }

    /// Native preflight for the checked adopter. Copying a nil axis
    /// drops existing scroll state; otherwise its input policy is preserved.
    /// Any subsequently created state starts with input enabled.
    func supportsLazyListScrollInputAdoption(from source: ViewNode) -> Bool {
        guard let incoming = source.scrollContainerState, !incoming.isInputEnabled else { return true }
        let retainedInputEnabled =
            source.scrollAxis == nil && scrollAxis != nil ? true : (scrollContainerState?.isInputEnabled ?? true)
        return !retainedInputEnabled || runtime?.hasActiveScrollInputCapture(for: self) != true
    }

    @discardableResult
    func reconcileScrollInputEnabled(
        _ enabled: Bool, admission: RetainedLazyListAdoptionAdmission?,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        guard let state = scrollContainerState, state.isInputEnabled != enabled else { return true }
        // An earlier admitted callback may have started a capture after the
        // whole-plan preflight. Leave its input policy and capture untouched.
        if admission != nil || nativeCheck != nil, !enabled,
            runtime?.hasActiveScrollInputCapture(for: self) == true
        {
            return false
        }
        let attachment = admission == nil ? nil : captureLazyListAttachmentProof()
        if let nativeCheck, let source = nativeCheck.source {
            guard nativeCheck.preparePropertyCopy(from: source, to: self, keyPath: \ViewNode.isScrollInputEnabled)
            else { return false }
        }
        admission?.markMutationStarted()
        state.isInputEnabled = enabled
        if let nativeCheck, let source = nativeCheck.source, let journal = nativeCheck.lazyJournal {
            recordAcceptedLazyProperty(
                from: source, keyPath: \ViewNode.isScrollInputEnabled, journal: journal,
                taskAdoption: nativeCheck.taskAdoption)
        }
        if !enabled, let runtime,
            !runtime.disableScrollInput(for: self, admission: admission, nativeCheck: nativeCheck)
        {
            return false
        }
        guard admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false,
            (admission == nil && nativeCheck == nil) || scrollContainerState === state
        else { return false }
        invalidateRuntime(.paint)
        return true
    }

    @discardableResult
    func reconcileScrollOffset(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission?,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        // Preserve the existing facade convention: an unconfigured zero does
        // not reset the user's retained position during ordinary adoption.
        guard source.scrollOffset != 0, scrollOffset != source.scrollOffset else { return true }
        return assignScrollOffset(
            source.scrollOffset, admission: admission, nativeCheck: nativeCheck,
            authoredSource: nativeCheck == nil ? nil : source)
    }

    /// The same setter funnel serves ordinary input and checked adoption.
    /// History cleanup during cancellation can reenter; no later observer or
    /// indicator write is admitted after that operation loses its attachment.
    @discardableResult
    fileprivate func assignScrollOffset(
        _ value: Double, admission: RetainedLazyListAdoptionAdmission?,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil, authoredSource: ViewNode? = nil,
        continuingListReveal: RetainedListNavigationRevealContinuation? = nil,
        continuingAccessibilityAnchor: RetainedLazyListAttachmentIdentity? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        if let continuingListReveal {
            guard admission == nil, nativeCheck == nil, authoredSource == nil,
                continuingAccessibilityAnchor == nil,
                continuingListReveal.container === self, continuingListReveal.state == .waiting,
                runtime?.isListNavigationRevealCurrent(continuingListReveal) == true
            else { return false }
        }
        if let continuingAccessibilityAnchor {
            guard admission == nil, nativeCheck == nil, authoredSource == nil, continuingListReveal == nil,
                runtime?.canBeginLazyListAccessibilityAnchorCorrection(
                    in: self, intent: continuingAccessibilityAnchor) == true
            else { return false }
        }
        if let nativeCheck, let authoredSource {
            guard nativeCheck.preparePropertyCopy(from: authoredSource, to: self, keyPath: \ViewNode.scrollOffset)
            else { return false }
        }
        // Even an equal authored assignment supersedes a pending lazy anchor.
        // Ordinary scroll containers allocate no proof storage for this check.
        if let continuingListReveal {
            // This is the one callback-free correction admitted from a fixed
            // settlement. Publish its exact successor intent before the shared
            // offset observer tests cancellation. Authored writes cannot use it.
            let nextIntent = RetainedLazyListAttachmentIdentity()
            lifecycleHandlers?.lazyListScrollIntentIdentity = nextIntent
            continuingListReveal.scrollIntent = nextIntent
            continuingListReveal.expectedOffset = value
        } else if let continuingAccessibilityAnchor {
            // Reserve the exact post-write identity before invalidation can
            // release a queued callback. An authored nested write clears it.
            lifecycleHandlers?.lazyListScrollIntentIdentity = continuingAccessibilityAnchor
        } else {
            lifecycleHandlers?.lazyListScrollIntentIdentity = nil
        }
        let attachment = admission == nil ? nil : captureLazyListAttachmentProof()
        let previous = storedScrollOffset
        admission?.markMutationStarted()
        storedScrollOffset = value
        if let nativeCheck, let authoredSource, let journal = nativeCheck.lazyJournal {
            recordAcceptedLazyProperty(
                from: authoredSource, keyPath: \ViewNode.scrollOffset, journal: journal,
                taskAdoption: nativeCheck.taskAdoption)
        }
        if let runtime,
            !runtime.cancelProgrammaticScrollIfTargetChanged(for: self, admission: admission, nativeCheck: nativeCheck)
        {
            return false
        }
        guard admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
        else { return false }
        if let continuingAccessibilityAnchor,
            runtime?.isLazyListAccessibilityAnchorCorrectionCurrent(
                in: self, intent: continuingAccessibilityAnchor) != true
        {
            return false
        }
        invalidateRuntime(hasVirtualizedDescendants ? [.paint, .layout] : .paint)
        if let continuingAccessibilityAnchor,
            runtime?.isLazyListAccessibilityAnchorCorrectionCurrent(
                in: self, intent: continuingAccessibilityAnchor) != true
        {
            return false
        }
        if scrollIndicatorAutoHides, storedScrollOffset != previous {
            runtime?.revealScrollIndicator(for: self)
        }
        if let continuingAccessibilityAnchor,
            runtime?.isLazyListAccessibilityAnchorCorrectionCurrent(
                in: self, intent: continuingAccessibilityAnchor) != true
        {
            return false
        }
        return admission?.isCurrent != false && attachment?.isCurrent != false && nativeCheck?.isCurrent != false
    }

    func reconcileScrollIndicatorsFlashTrigger(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false else { return false }
        if scrollIndicatorsFlashTrigger != source.scrollIndicatorsFlashTrigger {
            admission?.markMutationStarted()
            // This setter schedules the existing primitive reveal state; it
            // neither reads the animation clock nor invokes an app callback.
            scrollIndicatorsFlashTrigger = source.scrollIndicatorsFlashTrigger
        }
        return admission?.isCurrent != false
    }

    /// The slot size `children` were last built against. `nil` on a node that
    /// is not a reader. Compared against `resolvedFrame.size` to decide
    /// whether a convergence rebuild is owed, so it is also the loop's own
    /// termination condition.
    public var geometryReaderBuiltSize: Size? {
        didSet {
            guard oldValue != nil || geometryReaderBuiltSize != nil else { return }
            // Reconciliation copies the opaque body before this scalar. Even
            // an equal seed completes a new body/size pair that a clean path
            // must visit before it can establish resolved layout evidence.
            invalidateRuntime(.layout)
        }
    }

    internal private(set) var hasAppeared = false
    /// A rebuilding onAppear action must not drop the remaining node/task
    /// callback or invoke its replacement before the new frame is resolved.
    internal private(set) var hasPendingAppearanceCallbacks = false
    private var hasPendingAppearanceNodeCallback = false

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
    /// `hasAppeared` is set by the render lifecycle stage — which does not reach
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
    private var acceptsLifecycleTasks = true

    public private(set) weak var parent: ViewNode? {
        didSet {
            if parent !== oldValue { storedAccessibilityAttachmentIdentity = nil }
        }
    }
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
        runtime?.clock() ?? PlatformClock.now()
    }

    internal var resolvedFrame: Rect
    internal var resolvedContentSize: Size
    internal var resolvedScrollOffset: Double
    // Signed pixel offset applied on top of the clamped scrollOffset during
    // rubber-band animations. Zero outside of edge-overshoot states. Painter
    // and child positioning consume this via `effectiveScrollOffset`; the
    // logical `scrollOffset` itself stays clamped so tests and external
    // callers see the unsurprising value. Presentation changes dirty this
    // node too, so clean ancestors cannot replay the previous viewport.
    internal var scrollOvershoot: Double = 0 {
        didSet {
            if scrollOvershoot != oldValue {
                invalidateRuntime(hasVirtualizedDescendants ? [.paint, .layout] : .paint)
            }
        }
    }
    // Signed pixel offset that visually lags the logical scrollOffset during
    // keyboard and programmatic animations. Layout, hit testing, paint, and
    // observation all consume the same composed presentation offset.
    internal var scrollPresentedDelta: Double = 0 {
        didSet {
            if scrollPresentedDelta != oldValue {
                invalidateRuntime(hasVirtualizedDescendants ? [.paint, .layout] : .paint)
            }
        }
    }
    internal private(set) var subtreeDirtyFlags: DirtyFlags = .all
    private var cachedMeasurement: ViewMeasurementCacheEntry?
    internal var cachedMeasureKey: ViewMeasureCacheKey? { cachedMeasurement?.key }
    internal var cachedMeasuredSize: Size? { cachedMeasurement?.result.size }
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
    internal var cachedFrameSnapshotIdentity: PaintSnapshotIdentity?
    internal var cachedSceneKey: ViewPaintCacheKey?
    internal var cachedScenePaintRange: Range<Int>?
    internal var cachedSceneSnapshotIdentity: PaintSnapshotIdentity?
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
        self.scrollContainerState = scrollAxis.map { RetainedScrollContainerState(axis: $0) }
        self.storedScrollOffset = scrollOffset
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

        if chartXAxis != nil || chartXScale != nil || chartYScale != nil
            || meshGradient != nil || chartYAxis != nil || chartLegend != nil
            || chartBackground != nil || chartPlotStyle != nil || chartOverlay != nil
            || chartSelection != nil || chartScrollableAxes != nil
            || chartForegroundStyleScale != nil || chartSymbolSize != nil || chartSymbol != nil
            || chartAngleScale != nil || chartBackgroundStyleScale != nil || chartSymbolScale != nil
            || chartXVisibleDomain != nil || chartYVisibleDomain != nil || chartXSelection != nil
            || chartYSelection != nil || chartAngleSelection != nil
            || chartScrollPositionX != nil || chartScrollPositionY != nil
        {
            let metadata = ViewNodeChartMetadata()
            metadata.xAxis = chartXAxis
            metadata.xScale = chartXScale
            metadata.yScale = chartYScale
            metadata.meshGradient = meshGradient
            metadata.yAxis = chartYAxis
            metadata.legend = chartLegend
            metadata.background = chartBackground
            metadata.plotStyle = chartPlotStyle
            metadata.overlay = chartOverlay
            metadata.selection = chartSelection
            metadata.scrollableAxes = chartScrollableAxes
            metadata.foregroundStyleScale = chartForegroundStyleScale
            metadata.symbolSize = chartSymbolSize
            metadata.symbol = chartSymbol
            metadata.angleScale = chartAngleScale
            metadata.backgroundStyleScale = chartBackgroundStyleScale
            metadata.symbolScale = chartSymbolScale
            metadata.xVisibleDomain = chartXVisibleDomain
            metadata.yVisibleDomain = chartYVisibleDomain
            metadata.xSelection = chartXSelection
            metadata.ySelection = chartYSelection
            metadata.angleSelection = chartAngleSelection
            metadata.scrollPositionX = chartScrollPositionX
            metadata.scrollPositionY = chartScrollPositionY
            self.chartMetadata = metadata
        }

        for child in children {
            addChild(child)
        }
    }

    public func addChild(_ child: ViewNode) {
        guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment,
            child.parent?.isRetiringLazyListAttachment != true
        else { return }
        let interactionRuntime = runtime
        let sourceRuntime = child.runtime
        interactionRuntime?.beginLongPressReconciliation()
        if sourceRuntime !== interactionRuntime { sourceRuntime?.beginLongPressReconciliation() }
        defer {
            if sourceRuntime !== interactionRuntime { sourceRuntime?.endLongPressReconciliation() }
            interactionRuntime?.endLongPressReconciliation()
        }
        child.removeFromParent()
        guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment, child.parent == nil else { return }
        child.revokeLazyListAttachmentProofs()
        child.parent = self
        child.setRuntime(runtime)
        guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment, child.parent === self else { return }
        children.append(child)
        runtime?.registerLazyListAttachments(in: child)
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
        guard !isRetiringLazyListAttachment, !children.contains(where: \.isRetiringLazyListAttachment) else { return }
        let interactionRuntime = runtime
        let groupTaskCleanup = Self.claimLazyGroupTaskDepartures(in: children)
        interactionRuntime?.beginLongPressReconciliation()
        defer {
            interactionRuntime?.endLongPressReconciliation()
            for cleanup in groupTaskCleanup { cleanup.finish() }
        }
        for child in children { child.revokeTextInputOwnership() }
        for child in children {
            guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment else { return }
            child.revokeLazyListAttachmentProofs()
            if runtime != nil, child.transition.removal.kind != .identity, child.applyRemovalTransition() {
                guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment else { return }
                child.isRemovalOverlay = true
                child.cachedFrameKey = nil
                child.cachedFrameCommandRange = nil
                child.cachedSceneKey = nil
                child.cachedScenePaintRange = nil
                runtime?.transitionOverlays.append(child)
                child.revokeLazyListAttachmentProofs()
                child.parent = nil
                child.setRuntime(nil)
            } else {
                child.markSubtreeDisappeared()
                guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment else { return }
                child.revokeLazyListAttachmentProofs()
                child.parent = nil
                child.setRuntime(nil)
            }
        }
        if !children.isEmpty {
            runtime?.invalidate()
        }
        guard !isRetiringLazyListAttachment else { return }
        children.removeAll(keepingCapacity: false)
        invalidateRuntime(.children)
    }

    /// Replace the child at the given index with a new node.
    public func replaceChild(at index: Int, with newChild: ViewNode) {
        guard !isRetiringLazyListAttachment, !newChild.isRetiringLazyListAttachment,
            newChild.parent?.isRetiringLazyListAttachment != true
        else { return }
        guard index >= 0, index < children.count else {
            return
        }

        let interactionRuntime = runtime
        let sourceRuntime = newChild.runtime
        let groupTaskCleanup = Self.claimLazyGroupTaskDepartures(in: [children[index]])
        interactionRuntime?.beginLongPressReconciliation()
        if sourceRuntime !== interactionRuntime { sourceRuntime?.beginLongPressReconciliation() }
        defer {
            if sourceRuntime !== interactionRuntime { sourceRuntime?.endLongPressReconciliation() }
            interactionRuntime?.endLongPressReconciliation()
            for cleanup in groupTaskCleanup { cleanup.finish() }
        }

        let old = children[index]
        guard !old.isRetiringLazyListAttachment else { return }
        detachRemovedChild(old)

        guard !isRetiringLazyListAttachment, !newChild.isRetiringLazyListAttachment,
            newChild.parent?.isRetiringLazyListAttachment != true
        else { return }
        newChild.removeFromParent()
        guard !isRetiringLazyListAttachment, !newChild.isRetiringLazyListAttachment, newChild.parent == nil else {
            return
        }
        newChild.revokeLazyListAttachmentProofs()
        newChild.parent = self
        newChild.setRuntime(runtime)
        guard !isRetiringLazyListAttachment, !newChild.isRetiringLazyListAttachment, newChild.parent === self else {
            return
        }
        children[index] = newChild
        runtime?.registerLazyListAttachments(in: newChild)
        invalidateRuntime()
    }

    /// Remove the child at the given index.
    public func removeChild(at index: Int) {
        guard !isRetiringLazyListAttachment else { return }
        guard index >= 0, index < children.count else {
            return
        }

        let interactionRuntime = runtime
        let groupTaskCleanup = Self.claimLazyGroupTaskDepartures(in: [children[index]])
        interactionRuntime?.beginLongPressReconciliation()
        defer {
            interactionRuntime?.endLongPressReconciliation()
            for cleanup in groupTaskCleanup { cleanup.finish() }
        }

        guard !children[index].isRetiringLazyListAttachment else { return }
        let removed = children.remove(at: index)
        detachRemovedChild(removed)
        invalidateRuntime()
    }

    /// Runs a child that has just left `children` through its removal
    /// transition (or straight to disappearance) and unparents it. The single
    /// place that decides what leaving looks like — shared by `removeChild`,
    /// `replaceChild` and `setChildren`.
    private func detachRemovedChild(_ removed: ViewNode) {
        guard !isRetiringLazyListAttachment, !removed.isRetiringLazyListAttachment else { return }
        removed.revokeLazyListAttachmentProofs()
        removed.revokeTextInputOwnership()
        removed.onDismantlePlatformView?(removed)
        guard !isRetiringLazyListAttachment, !removed.isRetiringLazyListAttachment else { return }
        // Adoption also removes fresh nodes from temporary construction
        // parents. Only a mounted parent can own and retire a removal overlay.
        if runtime != nil, removed.transition.removal.kind != .identity, removed.applyRemovalTransition() {
            guard !isRetiringLazyListAttachment, !removed.isRetiringLazyListAttachment else { return }
            removed.isRemovalOverlay = true
            removed.cachedFrameKey = nil
            removed.cachedFrameCommandRange = nil
            removed.cachedSceneKey = nil
            removed.cachedScenePaintRange = nil
            runtime?.transitionOverlays.append(removed)
            runtime?.invalidate()
            removed.revokeLazyListAttachmentProofs()
            removed.parent = nil
            removed.setRuntime(nil)
        } else {
            removed.markSubtreeDisappeared()
            guard !isRetiringLazyListAttachment, !removed.isRetiringLazyListAttachment else { return }
            removed.revokeLazyListAttachmentProofs()
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
    private func setChildrenUnchecked(
        _ nextChildren: [ViewNode], lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil, sourceParent: ViewNode? = nil
    ) {
        guard !isRetiringLazyListAttachment else { return }
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
            if let sourceParent, let lazyJournal,
                lazyJournal.prepareOwnedStructuralDeclaration(from: sourceParent, to: self)
            {
                lazyJournal.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
            }
            return
        }
        guard !children.contains(where: \.isRetiringLazyListAttachment),
            !nextChildren.contains(where: {
                $0.isRetiringLazyListAttachment || $0.parent?.isRetiringLazyListAttachment == true
            })
        else { return }

        let interactionRuntime = runtime
        var groupTaskCleanup: [RetainedLazyListAcceptedTaskCleanup] = []
        interactionRuntime?.beginLongPressReconciliation()
        var sourceRuntimes: [RetainedViewRuntime] = []
        for child in nextChildren {
            if let sourceRuntime = child.runtime, sourceRuntime !== interactionRuntime,
                !sourceRuntimes.contains(where: { $0 === sourceRuntime })
            {
                sourceRuntime.beginLongPressReconciliation()
                sourceRuntimes.append(sourceRuntime)
            }
        }
        defer {
            for sourceRuntime in sourceRuntimes { sourceRuntime.endLongPressReconciliation() }
            interactionRuntime?.endLongPressReconciliation()
            for cleanup in groupTaskCleanup { cleanup.finish() }
        }

        let surviving = Set(nextChildren.map(ObjectIdentifier.init))
        let departing = children.filter { !surviving.contains(ObjectIdentifier($0)) }
        groupTaskCleanup = Self.claimLazyGroupTaskDepartures(in: departing)
        if let lazyJournal {
            for cleanup in groupTaskCleanup { lazyJournal.claimTaskCleanup(cleanup) }
            for node in Self.lazyListNodes(in: departing) ?? [] {
                _ = lazyJournal.recordPhysicalDeparture(of: node, cause: .acceptedReplacement)
            }
            for node in Self.lazyListNodes(in: nextChildren.filter { $0.parent !== self }) ?? [] {
                _ = lazyJournal.prepareInsertedNode(from: node)
            }
        }
        for child in departing { child.revokeTextInputOwnership() }
        var recordsEmptyDeclaration = false
        if nextChildren.isEmpty, let sourceParent, let lazyJournal {
            recordsEmptyDeclaration = lazyJournal.prepareOwnedStructuralDeclaration(from: sourceParent, to: self)
        }
        children = []
        if recordsEmptyDeclaration, let sourceParent {
            lazyJournal?.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
        }
        for child in departing {
            detachRemovedChild(child)
        }
        guard !isRetiringLazyListAttachment else { return }
        for child in nextChildren {
            guard !child.isRetiringLazyListAttachment, child.parent?.isRetiringLazyListAttachment != true else {
                return
            }
            if child.parent !== self {
                child.removeFromParent()
                guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment, child.parent == nil else {
                    return
                }
                child.revokeLazyListAttachmentProofs()
                child.parent = self
            }
            child.setRuntime(runtime)
            guard !isRetiringLazyListAttachment, !child.isRetiringLazyListAttachment, child.parent === self else {
                return
            }
        }
        guard !isRetiringLazyListAttachment,
            !nextChildren.contains(where: \.isRetiringLazyListAttachment)
        else { return }
        var recordsDeclaration = false
        if !nextChildren.isEmpty, let sourceParent, let lazyJournal {
            recordsDeclaration = lazyJournal.prepareOwnedStructuralDeclaration(from: sourceParent, to: self)
        }
        children = nextChildren
        if recordsDeclaration, let sourceParent {
            lazyJournal?.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
        }
        for child in nextChildren { runtime?.registerLazyListAttachments(in: child) }
        if let lazyJournal {
            // The legacy setter's publication point stays in its original
            // position. These are metadata facts for the ordinary epoch; the
            // selective descriptor path uses the checked publication engine.
            for node in Self.lazyListNodes(in: nextChildren) ?? [] {
                for group in lazyJournal.recordAcceptedInsertedNode(on: node) {
                    taskAdoption?.associateLazyAccepted(group, journal: lazyJournal)
                }
                for group in lazyJournal.takeAcceptedDescriptorTaskGroups() {
                    taskAdoption?.associateDescriptorAccepted(group, journal: lazyJournal)
                }
                for group in lazyJournal.recordCompletedNode(from: node, to: node) {
                    taskAdoption?.associateLazyAccepted(group, journal: lazyJournal)
                }
                for group in lazyJournal.takeAcceptedDescriptorTaskGroups() {
                    taskAdoption?.associateDescriptorAccepted(group, journal: lazyJournal)
                }
            }
        }
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

    /// Ownership revocation cannot release history or invoke application
    /// callbacks. All members of a departure batch must be marked first.
    func revokeTextInputOwnership() {
        var pending = [self]
        while let node = pending.popLast() {
            pending.append(contentsOf: node.children)
            // File dialogs share the same departure boundary: a callback in an
            // earlier branch must not use a later departing presenter's lease.
            node.fileDialogPresenterIsDeparting = true
            node.fileDialogPresenterLease?.invalidate()
            node.listNavigationOwner?.revokeForDeparture()
            node.textInputController?.revokeOwnership(from: node)
        }
    }

    func beginFileDialogPresentation(kind: RetainedFileDialogKind) -> RetainedFileDialogPresenterLease {
        fileDialogPresenterLease?.invalidate()
        let lease = RetainedFileDialogPresenterLease(kind: kind)
        if fileDialogPresenterIsDeparting || (fileDialogPreparedRevocations & kind.rawValue) != 0 {
            lease.invalidate()
        }
        fileDialogPresenterLease = lease
        return lease
    }

    func isFileDialogPresenter(in expectedRuntime: RetainedViewRuntime) -> Bool {
        guard !fileDialogPresenterIsDeparting, runtime === expectedRuntime else { return false }
        var ancestor: ViewNode? = self
        while let node = ancestor {
            if node === expectedRuntime.root { return true }
            ancestor = node.parent
        }
        return false
    }

    /// Called during adoption preparation, before any departing payload can run
    /// application code. Compatible configuration refreshes keep the operation
    /// snapshot; removing that modifier revokes it immediately.
    func revokeFileDialogPresentation(ifAbsentFrom source: ViewNode) {
        if fileExporterConfiguration != nil, source.fileExporterConfiguration == nil {
            fileDialogPreparedRevocations |= RetainedFileDialogKind.exporter.rawValue
        }
        if fileImporterConfiguration != nil, source.fileImporterConfiguration == nil {
            fileDialogPreparedRevocations |= RetainedFileDialogKind.importer.rawValue
        }
        if fileImporterMultiConfiguration != nil, source.fileImporterMultiConfiguration == nil {
            fileDialogPreparedRevocations |= RetainedFileDialogKind.importerMulti.rawValue
        }
        if fileMoverConfiguration != nil, source.fileMoverConfiguration == nil {
            fileDialogPreparedRevocations |= RetainedFileDialogKind.mover.rawValue
        }
        if let lease = fileDialogPresenterLease, (fileDialogPreparedRevocations & lease.kind.rawValue) != 0 {
            lease.invalidate()
        }
    }

    func finishFileDialogConfigurationAdoption() {
        fileDialogPreparedRevocations = 0
    }

    fileprivate func setRuntime(_ runtime: RetainedViewRuntime?, hasRevokedTextInputOwnership: Bool = false) {
        guard !isRetiringLazyListAttachment else { return }
        if let previousRuntime = self.runtime, previousRuntime !== runtime,
            let adapter = retainedLazyListAdapter, adapter.ownsAttachment(self)
        {
            // An owned deferred container must finish its old mapping/claim
            // before another runtime can acquire it. The supported transfer
            // is detach, complete cleanup, then attach on a fresh operation.
            guard runtime == nil else { return }
            detachLazyListRuntime(
                from: previousRuntime, adapter: adapter,
                hasRevokedTextInputOwnership: hasRevokedTextInputOwnership)
            return
        }
        let didChangeRuntime = self.runtime !== runtime
        if didChangeRuntime { storedAccessibilityAttachmentIdentity = nil }
        let isLeavingRuntime = self.runtime != nil && self.runtime !== runtime
        if isLeavingRuntime { lifecycleHandlers?.retainedTasks?.invalidateAttachment() }
        if didChangeRuntime {
            revokeLazyListAttachmentProofs()
            self.runtime?.unregisterLazyListContainer(self)
        }
        if isLeavingRuntime, !hasRevokedTextInputOwnership {
            revokeTextInputOwnership()
        }
        if didChangeRuntime {
            fileDialogPresenterLease?.invalidate()
            if let state = scrollContainerState { state.attachmentGeneration &+= 1 }
            self.runtime?.unregisterScrollObservationNode(self)
            scrollObserverStorage?.reset()
            guard !isRetiringLazyListAttachment else { return }
            if self.runtime != nil { textInputController?.willDetach(from: self) }
            guard !isRetiringLazyListAttachment else { return }
            self.runtime?.releaseInteractionTargets(in: self)
            guard !isRetiringLazyListAttachment else { return }
            self.runtime?.cancelColorAnimations(of: self)
            if runtime == nil {
                textInputController?.detach(from: self)
                guard !isRetiringLazyListAttachment else { return }
            }
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
        if let runtime { listNavigationOwner?.didAttach(to: runtime) }
        if runtime != nil, didChangeRuntime {
            fileDialogPresenterIsDeparting = false
            fileDialogPreparedRevocations = 0
        }
        if runtime != nil {
            textInputController?.attach(to: self)
            guard !isRetiringLazyListAttachment else { return }
        }
        if scrollObserverStorage != nil {
            runtime?.registerScrollObservationNode(self)
        }
        if retainedLazyListAdapter != nil { runtime?.registerLazyListContainer(self) }
        for child in children {
            child.setRuntime(
                runtime, hasRevokedTextInputOwnership: hasRevokedTextInputOwnership || isLeavingRuntime)
        }
    }

    /// Only protects adapter mapping/claim lifetime in the legacy runtime
    /// bridge. Generic removal may already have delivered dismantle/appearance
    /// callbacks before reaching here; it is not the checked eviction path.
    private func detachLazyListRuntime(
        from previousRuntime: RetainedViewRuntime, adapter: RetainedLazyListRuntimeAdapter,
        hasRevokedTextInputOwnership: Bool
    ) {
        let gate = LazyListRetirementGate(nodes: [self])
        drainLazyListRuntimeDetach(
            from: previousRuntime, adapter: adapter, gateIdentity: gate.identity,
            hasRevokedTextInputOwnership: hasRevokedTextInputOwnership)
        // The helper's old payload captures have unwound while the gate and
        // weak claim still exclude a new owner. Existing queued cleanup also
        // finishes before the gate releases that claim.
        previousRuntime.afterRetainedCallbacks { gate.finish() }
    }

    private func drainLazyListRuntimeDetach(
        from previousRuntime: RetainedViewRuntime, adapter: RetainedLazyListRuntimeAdapter,
        gateIdentity: RetainedLazyListAttachmentIdentity, hasRevokedTextInputOwnership: Bool
    ) {
        storedAccessibilityAttachmentIdentity = nil
        let controller = textInputController
        let storage = scrollObserverStorage
        let detachedChildren = children
        let scopedTaskCleanup = existingRetainedTaskState?.claimLazyPhysicalDeparture()
        revokeLazyListAttachmentProofs()
        previousRuntime.unregisterLazyListContainer(self)
        if !hasRevokedTextInputOwnership { revokeTextInputOwnership() }
        fileDialogPresenterLease?.invalidate()
        if let state = scrollContainerState { state.attachmentGeneration &+= 1 }
        previousRuntime.unregisterScrollObservationNode(self)
        let history = storage?.takeLazyListRetiredHistory() ?? []

        // These are captured cleanup obligations. A callback replacing an
        // editor field does not redirect the old editor's terminal detach.
        controller?.willDetach(from: self)
        previousRuntime.releaseInteractionTargets(in: self)
        previousRuntime.cancelColorAnimations(of: self)
        controller?.detach(from: self)
        if lifecycleHandlers?.lazyListRetirementIdentity === gateIdentity,
            retainedLazyListAdapter === adapter, runtime === previousRuntime
        {
            previousRuntime.unregisterAnimatingNode(self)
            revokeLazyListAttachmentProofs()
            runtime = nil
            for child in detachedChildren where child.parent === self && child.runtime === previousRuntime {
                child.setRuntime(nil, hasRevokedTextInputOwnership: true)
            }
        }
        if lifecycleHandlers?.lazyListRetirementIdentity === gateIdentity,
            retainedLazyListAdapter === adapter, adapter.ownsAttachment(self)
        {
            adapter.releaseMountedRecords()
        }
        scopedTaskCleanup?.finish()
        withExtendedLifetime(history) {}
        withExtendedLifetime(controller) {}
        withExtendedLifetime(storage) {}
        withExtendedLifetime(detachedChildren) {}
        withExtendedLifetime(scopedTaskCleanup) {}
    }

    internal func invalidateRenderLifecycleCandidates() {
        runtime?.invalidateRenderLifecycleCandidates()
    }

    internal func markSubtreeDisappeared() {
        let groupTaskCleanup = Self.claimLazyGroupTaskDepartures(in: [self])
        defer { for cleanup in groupTaskCleanup { cleanup.finish() } }
        lifecycleHandlers?.completedLazyTaskAppearance = nil
        let taskState = lifecycleHandlers?.retainedTasks
        let taskDisappearance = taskState?.beginDisappearance()
        if hasAppeared {
            onDisappear?()
            onDisappearWithNode?(self)
            cancelLifecycleTasks()
            hasAppeared = false
            hasPendingAppearanceCallbacks = false
            hasPendingAppearanceNodeCallback = false
        }
        if let taskDisappearance { taskState?.finishDisappearance(taskDisappearance) }
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
        guard acceptsLifecycleTasks, !isRetiringLazyListAttachment,
            runtime?.permitsRenderLifecycleCallbacks != false
        else { return }
        lifecycleTasks[launch.key]?.cancel()
        // Cancelling the previous task may synchronously close this owner.
        guard acceptsLifecycleTasks, !isRetiringLazyListAttachment,
            runtime?.permitsRenderLifecycleCallbacks != false
        else { return }
        lifecycleTasks[launch.key] = Task(priority: launch.priority) {
            await launch.action()
        }
    }

    @discardableResult
    func launchLifecycleTask(
        _ launch: ViewLifecycleTaskLaunch, admission: RetainedLazyListAdoptionAdmission?,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil, source: ViewNode? = nil
    ) -> Bool {
        guard let lazyJournal, !lazyJournal.isOrdinaryAdoption else {
            guard let admission else {
                launchLifecycleTask(launch)
                return true
            }
            guard admission.isCurrent, acceptsLifecycleTasks,
                runtime?.permitsRenderLifecycleCallbacks != false, !isRetiringLazyListAttachment
            else { return false }
            let attachment = captureLazyListAttachmentProof()
            let completed = replaceLifecycleTask(launch, admission: admission, attachment: attachment)
            return completed && admission.isCurrent && attachment.isCurrent
        }
        guard admission?.isCurrent != false, lazyJournal.canContinueAdoption, acceptsLifecycleTasks,
            runtime?.permitsRenderLifecycleCallbacks != false, !isRetiringLazyListAttachment
        else { return false }
        let attachment = captureLazyListAttachmentProof()
        let identity = captureLazyListIdentityProof()
        let sourceAttachment = source?.captureLazyListAttachmentProof()
        let sourceIdentity = source?.captureLazyListIdentityProof()
        let completed = replaceJournalLifecycleTask(
            launch, admission: admission, attachment: attachment, identity: identity,
            sourceAttachment: sourceAttachment, sourceIdentity: sourceIdentity, lazyJournal: lazyJournal)
        return completed && admission?.isCurrent != false && lazyJournal.canContinueAdoption
            && attachment.isCurrent && identity.isCurrent
            && sourceAttachment?.isCurrent != false && sourceIdentity?.isCurrent != false
    }

    private func replaceLifecycleTask(
        _ launch: ViewLifecycleTaskLaunch, admission: RetainedLazyListAdoptionAdmission,
        attachment: RetainedLazyListAttachmentProof
    ) -> Bool {
        admission.markMutationStarted()
        let previous = lifecycleTasks.removeValue(forKey: launch.key)
        previous?.cancel()
        guard admission.isCurrent, attachment.isCurrent, acceptsLifecycleTasks,
            runtime?.permitsRenderLifecycleCallbacks != false, lifecycleTasks[launch.key] == nil
        else { return false }
        lifecycleTasks[launch.key] = Task(priority: launch.priority) {
            await launch.action()
        }
        withExtendedLifetime(previous) {}
        return true
    }

    private func replaceJournalLifecycleTask(
        _ launch: ViewLifecycleTaskLaunch, admission: RetainedLazyListAdoptionAdmission?,
        attachment: RetainedLazyListAttachmentProof, identity: RetainedLazyListViewIdentityProof,
        sourceAttachment: RetainedLazyListAttachmentProof?, sourceIdentity: RetainedLazyListViewIdentityProof?,
        lazyJournal: RetainedLazyListAdoptionJournal?
    ) -> Bool {
        guard lazyJournal?.markMutationStarted() != false else { return false }
        admission?.markMutationStarted()
        let previous = lifecycleTasks.removeValue(forKey: launch.key)
        previous?.cancel()
        guard admission?.isCurrent != false, lazyJournal?.canContinueAdoption != false,
            attachment.isCurrent, identity.isCurrent,
            sourceAttachment?.isCurrent != false, sourceIdentity?.isCurrent != false, acceptsLifecycleTasks,
            runtime?.permitsRenderLifecycleCallbacks != false, lifecycleTasks[launch.key] == nil
        else { return false }
        lifecycleTasks[launch.key] = Task(priority: launch.priority) {
            await launch.action()
        }
        withExtendedLifetime(previous) {}
        return true
    }

    public func cancelLifecycleTask(key: String) {
        lifecycleTasks[key]?.cancel()
        lifecycleTasks[key] = nil
    }

    private func cancelLifecycleTasks() {
        for task in takeLifecycleTasks() { task.cancel() }
    }

    fileprivate func takeLifecycleTasks(retiring: Bool = false) -> [Task<Void, Never>] {
        if retiring { acceptsLifecycleTasks = false }
        let tasks = Array(lifecycleTasks.values)
        lifecycleTasks.removeAll()
        return tasks
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
    @MainActor
    private struct LayoutTraversalContext {
        let node: ViewNode
        let depth: Int
        let attachment: RetainedLazyListAttachmentProof?
        weak var checkedRuntime: RetainedViewRuntime?

        init(node: ViewNode, depth: Int) {
            self.node = node
            self.depth = depth
            if let runtime = node.runtime, runtime.hasLazyListLayoutScope {
                attachment = node.captureLazyListAttachmentProof()
                checkedRuntime = runtime
            } else {
                attachment = nil
                checkedRuntime = nil
            }
        }

        var isCurrent: Bool {
            attachment == nil
                || (attachment?.isCurrent == true && checkedRuntime?.permitsRetainedActionInvocation == true)
        }
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
                guard finishContext.isCurrent else {
                    finishContext.checkedRuntime?.rejectLazyListLayoutVisit()
                    continue
                }
                ViewNode.traversalDepth = baseDepth + finishContext.depth + 1
                finishContext.node.finishLayoutPass()
                continue

            case .enter(let entryContext):
                context = entryContext
            }

            let node = context.node
            guard context.isCurrent else {
                context.checkedRuntime?.rejectLazyListLayoutVisit()
                continue
            }
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
            if node.retainedLazyListAdapter != nil {
                node.runtime?.recordLazyListLayoutCandidate(node)
            }

            let layoutKey = ViewLayoutCacheKey(frame: node.resolvedFrame, displayScale: displayScale)
            let layoutDirtyFlags = node.subtreeDirtyFlags.intersection([.layout, .children])
            if layoutDirtyFlags.isEmpty, node.cachedLayoutKey == layoutKey {
                node.enqueueCleanPathChildren(into: &traversal, depth: context.depth)
                node.lastLayoutVisitPassID = node.runtime?.layoutPassID ?? 0
                continue
            }

            guard node.beginLayoutPass(context: context) else { continue }

            // The node's own frame is settled and its children's frames are
            // computed here; `finish` closes the pass once they have been laid
            // out. Pushed before the children so it pops after all of them.
            traversal.append(.finish(context))
            node.placeChildren(into: &traversal, depth: context.depth, layoutKey: layoutKey)
        }
    }

    /// Everything that happens to a node before its children are placed:
    /// the layout callbacks, `.position()`'s re-centring, and the scroll offset
    /// a descendant `.lazyStack` will resolve its viewport against.
    @inline(never)
    private func beginLayoutPass(context: LayoutTraversalContext) -> Bool {
        onLayout?(resolvedFrame)
        guard context.isCurrent else {
            context.checkedRuntime?.rejectLazyListLayoutVisit()
            return false
        }

        onLayoutWithNode?(self, resolvedFrame)
        guard context.isCurrent else {
            context.checkedRuntime?.rejectLazyListLayoutVisit()
            return false
        }

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
        return true
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
        if retainedLazyListAdapter != nil {
            layoutRetainedLazyListChildren(descendants: &descendants)
        } else {
            switch layoutMode {
            case .absolute:
                layoutAbsoluteChildren(descendants: &descendants)

            case .stack(let stackLayout), .lazyStack(let stackLayout):
                layoutStackChildren(stackLayout: stackLayout, descendants: &descendants)

            case .flex(let flexStyle):
                layoutFlexChildren(flexStyle: flexStyle, descendants: &descendants)

            case .grid(let gridLayout):
                layoutGridChildren(gridLayout: gridLayout, descendants: &descendants)

            case .gridRow(let rowLayout):
                layoutGridRowChildren(rowLayout: rowLayout, descendants: &descendants)
            }
        }

        for child in descendants.reversed() {
            traversal.append(.enter(LayoutTraversalContext(node: child, depth: depth + 1)))
        }
    }

    /// Closes a node's layout pass, once its subtree has been laid out.
    @inline(never)
    private func finishLayoutPass() {
        if case .absolute = layoutMode, retainedLazyListAdapter == nil {
            // Read back rather than accumulated during placement: a child with
            // `.position()` rewrites its own frame while *it* lays out, so the
            // union is only correct once the subtree below has settled.
            var maxChildX: Double = 0
            var maxChildY: Double = 0
            for child in children {
                guard !child.isHidden else { continue }
                maxChildX = max(maxChildX, child.resolvedFrame.maxX)
                maxChildY = max(maxChildY, child.resolvedFrame.maxY)
            }
            scrollContainerState?.contentSize = Size(width: maxChildX, height: maxChildY)
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
        if retainedLazyListAdapter != nil {
            layoutRetainedLazyListChildren(descendants: &descendants)
        } else if layoutMode.virtualizesChildren, let mainAxis = layoutMode.stackLayout?.axis {
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
            if let absoluteChildFrame {
                child.resolvedFrame = absoluteChildFrame(child, resolvedFrame)
                descendants.append(child)
                continue
            }
            let childConstraints = LayoutConstraints(
                maxWidth: remainingConstraintExtent(resolvedFrame.size.width, offset: child.frame.origin.x),
                maxHeight: remainingConstraintExtent(resolvedFrame.size.height, offset: child.frame.origin.y)
            )
            let size = child.sizeThatFits(in: childConstraints)
            let resolvedSize = child.absoluteLayoutSize(from: size)
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
        scrollContainerState?.contentSize = resolvedFrame.size
    }

    /// `.stack` / `.lazyStack`: allocate the track, then walk it placing —
    /// and, unless virtualization defers them, laying out — each child.
    @inline(never)
    private func layoutStackChildren(stackLayout: StackLayout, descendants: inout [ViewNode]) {
        if aspectFitLayout != nil, layoutAspectFitChild(descendants: &descendants) { return }
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

    /// Do not reinterpret the accepted size as another aspect proposal or
    /// restore a fixed child's preferred dimensions through absolute layout.
    /// If this was a declined probe or its assigned slot changed, the original
    /// stack path remains responsible for allocation, alignment and clamping.
    private func layoutAspectFitChild(descendants: inout [ViewNode]) -> Bool {
        guard let measurement = cachedMeasurement,
            let fittedAspect = measurement.result.fittedAspect,
            fittedAspect == aspectFitLayout,
            measurement.key.displayScale == (runtime?.displayScale ?? 1),
            applyingLayoutConstraints(to: measurement.key.constraints) == measurement.key.constraints,
            measurement.result.size == resolvedFrame.size,
            children.count == 1, let child = children.first, !child.isHidden
        else { return false }

        child.resolvedFrame = Rect(origin: .zero, size: measurement.result.size)
        descendants.append(child)
        resolvedContentSize = resolvedFrame.size
        scrollContainerState?.contentSize = resolvedFrame.size
        return true
    }

    @inline(never)
    private func layoutGridChildren(gridLayout: RetainedGridLayout, descendants: inout [ViewNode]) {
        let geometry = makeGridGeometry(
            layout: gridLayout,
            constraints: LayoutConstraints(
                maxWidth: resolvedFrame.width, maxHeight: resolvedFrame.height),
            memo: MeasurementMemo(), alignInProposal: true)
        resolvedGridGeometry = geometry
        placeGridRows(geometry, descendants: &descendants)
        resolvedContentSize = Size(
            width: max(resolvedFrame.width, geometry.size.width),
            height: max(resolvedFrame.height, geometry.size.height))
        scrollContainerState?.contentSize = geometry.size
    }

    /// The single placement boundary for a Grid's physical row nodes. It is
    /// deliberately separate from measurement so checked child visits can be
    /// composed here without changing the numerical track solver.
    private func placeGridRows(_ geometry: GridLayoutGeometry, descendants: inout [ViewNode]) {
        var rowIndex = 0
        for child in children {
            if child.isHidden {
                child.resolvedFrame = .zero
                continue
            }
            guard rowIndex < geometry.rows.count,
                geometry.rows[rowIndex].identity == ObjectIdentifier(child)
            else { continue }
            child.resolvedFrame = geometry.rows[rowIndex].frame
            descendants.append(child)
            rowIndex += 1
        }
    }

    @inline(never)
    private func layoutGridRowChildren(rowLayout: RetainedGridRowLayout, descendants: inout [ViewNode]) {
        guard let grid = parent, case .grid(let layout) = grid.layoutMode,
            grid.children.contains(where: { $0 === self })
        else {
            layoutStackChildren(stackLayout: rowLayout.standaloneStackLayout, descendants: &descendants)
            return
        }

        // A row callback can change a shared sizing input after the Grid began
        // its pass. Rebuild from installed nodes, never a source-row capture.
        if grid.resolvedGridGeometry == nil {
            var rows: [ViewNode] = []
            grid.layoutGridChildren(gridLayout: layout, descendants: &rows)
        }
        guard let geometry = grid.resolvedGridGeometry,
            let row = geometry.rows.first(where: { $0.identity == ObjectIdentifier(self) })
        else { return }

        var cellIndex = 0
        for child in children {
            if child.isHidden {
                child.resolvedFrame = .zero
                continue
            }
            guard cellIndex < row.cells.count,
                row.cells[cellIndex].identity == ObjectIdentifier(child)
            else { continue }
            child.resolvedFrame = row.cells[cellIndex].frame
            descendants.append(child)
            cellIndex += 1
        }
        resolvedContentSize = row.frame.size
        scrollContainerState?.contentSize = row.frame.size
    }

    @inline(never)
    private func measureGrid(layout: RetainedGridLayout, plan: MeasurementPlan, memo: MeasurementMemo) -> Size {
        let geometry = makeGridGeometry(
            layout: layout, constraints: plan.childConstraints, memo: memo, alignInProposal: false)
        inheritedStackFillAxes = LayoutFillAxes(
            horizontal: explicitWidth == nil && geometry.fillAxes.horizontal,
            vertical: explicitHeight == nil && geometry.fillAxes.vertical)
        return finishMeasurement(plan: plan, childSizes: [], memo: memo, gridSize: geometry.size)
    }

    /// Enumerates only direct rows and explicitly expanded structural children.
    /// A nested Grid, padding, frame, or other real layout container is one cell.
    private func gridInputs(layout: RetainedGridLayout) -> (rows: [GridRowInput], columns: Int) {
        var rows: [GridRowInput] = []
        var columnCount = 0
        for child in children where !child.isHidden {
            if case .gridRow(let rowLayout) = child.layoutMode {
                var cells: [GridCellInput] = []
                var cursor = 0
                for cell in child.children where !cell.isHidden {
                    // Saturation is defensive behavior for uncharacterized
                    // overflowing spans; it keeps every physical child finite.
                    let first = min(cursor, Int.max - 1)
                    let span = max(1, cell.gridCellColumns)
                    let end = span > Int.max - first ? Int.max : first + span
                    cells.append(
                        GridCellInput(node: cell, firstColumn: first, endColumn: end, isMerged: end - first > 1))
                    cursor = end
                }
                columnCount = max(columnCount, cursor)
                rows.append(
                    GridRowInput(
                        node: child, isGridRow: true, alignment: rowLayout.alignment ?? layout.verticalAlignment,
                        cells: cells))
            } else {
                rows.append(
                    GridRowInput(
                        node: child, isGridRow: false, alignment: layout.verticalAlignment,
                        cells: [GridCellInput(node: child, firstColumn: 0, endColumn: 1, isMerged: true)]))
                columnCount = max(1, columnCount)
            }
        }
        for index in rows.indices where !rows[index].isGridRow {
            rows[index].cells[0].endColumn = columnCount
        }
        return (rows, columnCount)
    }

    private func gridTracks(
        rows: [GridRowInput], columns: Int, layout: RetainedGridLayout
    ) -> [GridTrackRun] {
        guard columns > 0 else { return [] }
        var boundaries: Set<Int> = [0, columns]
        var columnAlignments: [Int: StackCrossAlignment] = [:]
        for row in rows {
            for cell in row.cells {
                boundaries.insert(cell.firstColumn)
                boundaries.insert(cell.endColumn)
                if !cell.isMerged, let alignment = cell.node.gridColumnAlignment,
                    columnAlignments[cell.firstColumn] == nil
                {
                    // Different overrides in one column are undefined by
                    // SwiftUI. Do not characterize this choice as native order.
                    columnAlignments[cell.firstColumn] = gridTrackCrossAlignment(alignment)
                }
            }
        }
        let sorted = boundaries.sorted()
        return zip(sorted, sorted.dropFirst()).map { first, end in
            GridTrackRun(
                firstColumn: first, endColumn: end,
                alignment: gridHorizontalAlignment(
                    columnAlignments[first] ?? layout.horizontalAlignment, isRightToLeft: layout.isRightToLeft))
        }
    }

    /// Each physical GridRow still consumes a traversal level. No grid-specific
    /// path may bypass the runtime's recursion/depth guard for its cell subtrees.
    @inline(never)
    private func measureGridCells(
        row: GridRowInput, tracks: [GridTrackRun]?, spacing: Double, height: Double = .infinity,
        memo: MeasurementMemo
    ) -> [Size] {
        if row.isGridRow, !ViewNode.enterTraversal() {
            return [Size](repeating: .zero, count: row.cells.count)
        }
        defer { if row.isGridRow { ViewNode.leaveTraversal() } }
        return row.cells.map { cell in
            let width =
                tracks.map {
                    gridSpanExtent($0, firstColumn: cell.firstColumn, endColumn: cell.endColumn, spacing: spacing)
                } ?? .infinity
            return sanitizedLayoutSize(
                cell.node.sizeThatFits(in: LayoutConstraints(maxWidth: width, maxHeight: height), memo: memo))
        }
    }

    private func gridCellFills(_ node: ViewNode, axis: StackAxis) -> Bool {
        switch axis {
        case .horizontal:
            return node.effectiveFillAxes.horizontal && node.frame.width <= 0
                && node.fixedSizeAxes?.horizontal != true && !node.gridCellUnsizedAxes.contains(.horizontal)
        case .vertical:
            return node.effectiveFillAxes.vertical && node.frame.height <= 0
                && node.fixedSizeAxes?.vertical != true && !node.gridCellUnsizedAxes.contains(.vertical)
        }
    }

    @inline(never)
    private func gridCellFloors(
        row: GridRowInput, axis: StackAxis, tracks: [GridTrackRun], spacing: Double,
        constraints: LayoutConstraints
    ) -> [Double] {
        if row.isGridRow, !ViewNode.enterTraversal() {
            return [Double](repeating: 0, count: row.cells.count)
        }
        defer { if row.isGridRow { ViewNode.leaveTraversal() } }
        return row.cells.map { cell in
            let proposal = LayoutConstraints(
                maxWidth: axis == .vertical
                    ? gridSpanExtent(
                        tracks, firstColumn: cell.firstColumn, endColumn: cell.endColumn, spacing: spacing)
                    : constraints.maxWidth,
                maxHeight: constraints.maxHeight)
            return sanitizedLayoutExtent(cell.node.stackShrinkFloorMainExtent(along: axis, constraints: proposal))
        }
    }

    private func updateGridColumnGuides(
        rows: [GridRowInput], sizes: [[Size]], tracks: inout [GridTrackRun], establishExtent: Bool
    ) {
        for index in tracks.indices {
            tracks[index].guideBefore = 0
            tracks[index].guideAfter = 0
        }
        for (rowIndex, row) in rows.enumerated() {
            for (cellIndex, cell) in row.cells.enumerated() where !cell.isMerged && cell.node.gridCellAnchor == nil {
                guard let index = tracks.firstIndex(where: { $0.firstColumn == cell.firstColumn }) else { continue }
                let width = sizes[rowIndex][cellIndex].width
                let guide = gridGuideValue(
                    for: cell.node, axis: .vertical, alignment: tracks[index].alignment, extent: width)
                tracks[index].guideBefore = max(tracks[index].guideBefore, guide)
                tracks[index].guideAfter = max(tracks[index].guideAfter, width - guide)
            }
        }
        if establishExtent {
            for index in tracks.indices {
                tracks[index].extent = sanitizedLayoutExtent(tracks[index].guideBefore + tracks[index].guideAfter)
            }
        }
    }

    private func gridRowMetrics(row: GridRowInput, sizes: [Size]) -> GridRowMetrics {
        var result = GridRowMetrics()
        for (index, cell) in row.cells.enumerated() {
            let height = sizes[index].height
            result.height = max(result.height, height)
            result.isFlexible = result.isFlexible || gridCellFills(cell.node, axis: .vertical)
            if !cell.isMerged, cell.node.gridCellAnchor == nil {
                let guide = gridGuideValue(
                    for: cell.node, axis: .horizontal, alignment: row.alignment, extent: height)
                result.guideBefore = max(result.guideBefore, guide)
                result.guideAfter = max(result.guideAfter, height - guide)
            }
        }
        result.height = sanitizedLayoutExtent(max(result.height, result.guideBefore + result.guideAfter))
        return result
    }

    /// Produces fresh geometry without storing any of the temporary strong node
    /// references. All passes use the same sparse column boundaries and memo.
    @inline(never)
    private func makeGridGeometry(
        layout: RetainedGridLayout, constraints: LayoutConstraints, memo: MeasurementMemo,
        alignInProposal: Bool
    ) -> GridLayoutGeometry {
        let inputs = gridInputs(layout: layout)
        let rows = inputs.rows
        let horizontalSpacing = gridSpacing(layout.horizontalSpacing)
        let verticalSpacing = gridSpacing(layout.verticalSpacing)
        var tracks = gridTracks(rows: rows, columns: inputs.columns, layout: layout)
        let naturalSizes = rows.map {
            measureGridCells(row: $0, tracks: nil, spacing: horizontalSpacing, memo: memo)
        }
        updateGridColumnGuides(rows: rows, sizes: naturalSizes, tracks: &tracks, establishExtent: true)
        var requirements: [(cell: GridCellInput, width: Double)] = []
        for (rowIndex, row) in rows.enumerated() {
            for (cellIndex, cell) in row.cells.enumerated() {
                requirements.append((cell, naturalSizes[rowIndex][cellIndex].width))
                if gridCellFills(cell.node, axis: .horizontal) {
                    for index in gridRunIndices(
                        tracks, firstColumn: cell.firstColumn, endColumn: cell.endColumn)
                    {
                        tracks[index].isFlexible = true
                    }
                }
            }
        }
        // Singles precede spans. For equal-length underdetermined spans retain
        // authored order; this is the documented interim numerical policy.
        requirements = requirements.enumerated().sorted {
            let left = $0.element.cell.endColumn - $0.element.cell.firstColumn
            let right = $1.element.cell.endColumn - $1.element.cell.firstColumn
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        for requirement in requirements {
            gridRequireSpanExtent(
                requirement.width, firstColumn: requirement.cell.firstColumn,
                endColumn: requirement.cell.endColumn, spacing: horizontalSpacing, tracks: &tracks)
        }
        let horizontalGaps = gridSpacingTotal(count: inputs.columns, spacing: horizontalSpacing)
        let availableWidth = constraints.maxWidth - horizontalGaps
        var minimumRequirements: [(cell: GridCellInput, width: Double)] = []
        if availableWidth.isFinite, tracks.reduce(0, { $0 + $1.extent }) > max(0, availableWidth) {
            for row in rows {
                let floors = gridCellFloors(
                    row: row, axis: .horizontal, tracks: tracks, spacing: horizontalSpacing, constraints: constraints)
                for (index, cell) in row.cells.enumerated() {
                    minimumRequirements.append((cell, floors[index]))
                    gridRequireSpanExtent(
                        floors[index],
                        firstColumn: cell.firstColumn, endColumn: cell.endColumn,
                        spacing: horizontalSpacing, tracks: &tracks, minimum: true)
                }
            }
        }
        let widths = gridAllocateExtents(
            desired: tracks.map(\.extent), minimum: tracks.map { min($0.extent, $0.minimumExtent) },
            flexibleWeights: tracks.map { $0.isFlexible ? Double($0.endColumn - $0.firstColumn) : 0 },
            available: availableWidth)
        for index in tracks.indices { tracks[index].extent = widths[index] }
        // A span is an aggregate constraint. Clipping a provisional per-run
        // minimum to its desired width must not discard part of that hard
        // aggregate floor. Restore each covered minimum after compression;
        // this can overflow the proposal, but cannot violate an earlier floor.
        for requirement in minimumRequirements {
            gridRequireSpanExtent(
                requirement.width, firstColumn: requirement.cell.firstColumn,
                endColumn: requirement.cell.endColumn, spacing: horizontalSpacing, tracks: &tracks)
        }

        let fittedSizes = rows.map {
            measureGridCells(row: $0, tracks: tracks, spacing: horizontalSpacing, memo: memo)
        }
        updateGridColumnGuides(rows: rows, sizes: fittedSizes, tracks: &tracks, establishExtent: false)
        var metrics = rows.enumerated().map { gridRowMetrics(row: $0.element, sizes: fittedSizes[$0.offset]) }
        let verticalGaps = gridSpacingTotal(count: rows.count, spacing: verticalSpacing)
        let availableHeight = constraints.maxHeight - verticalGaps
        if availableHeight.isFinite, metrics.reduce(0, { $0 + $1.height }) > max(0, availableHeight) {
            for index in rows.indices {
                metrics[index].minimumHeight = min(
                    metrics[index].height,
                    gridCellFloors(
                        row: rows[index], axis: .vertical, tracks: tracks,
                        spacing: horizontalSpacing, constraints: constraints
                    ).max() ?? 0)
            }
        }
        let heights = gridAllocateExtents(
            desired: metrics.map(\.height), minimum: metrics.map(\.minimumHeight),
            flexibleWeights: metrics.map { $0.isFlexible ? 1 : 0 }, available: availableHeight)
        let size = sanitizedLayoutSize(
            Size(
                width: tracks.reduce(0, { $0 + $1.extent }) + horizontalGaps,
                height: heights.reduce(0, +) + verticalGaps))
        let origin = Point(
            x: alignInProposal
                ? gridAnchor(
                    for: gridHorizontalAlignment(layout.horizontalAlignment, isRightToLeft: layout.isRightToLeft))
                    * (constraints.maxWidth - size.width) : 0,
            y: alignInProposal ? gridAnchor(for: layout.verticalAlignment) * (constraints.maxHeight - size.height) : 0)
        var geometry: [GridRowGeometry] = []
        var cursor = sanitizedLayoutCoordinate(origin.y)
        for (index, row) in rows.enumerated() {
            let sizes = measureGridCells(
                row: row, tracks: tracks, spacing: horizontalSpacing, height: heights[index], memo: memo)
            let cells = gridCellGeometry(
                row: row, sizes: sizes, metrics: metrics[index], height: heights[index],
                tracks: tracks, totalWidth: size.width, layout: layout)
            let rowFrame = Rect(x: origin.x, y: cursor, width: size.width, height: heights[index])
            if row.isGridRow {
                geometry.append(
                    GridRowGeometry(
                        identity: ObjectIdentifier(row.node), frame: sanitizedLayoutRect(rowFrame), cells: cells))
            } else if let cell = cells.first {
                geometry.append(
                    GridRowGeometry(
                        identity: ObjectIdentifier(row.node),
                        frame: sanitizedLayoutRect(
                            Rect(
                                x: rowFrame.minX + cell.frame.minX, y: rowFrame.minY + cell.frame.minY,
                                width: cell.frame.width, height: cell.frame.height)), cells: []))
            }
            cursor = sanitizedLayoutCoordinate(cursor + heights[index] + verticalSpacing)
        }
        return GridLayoutGeometry(
            size: size,
            fillAxes: LayoutFillAxes(
                horizontal: tracks.contains(where: \.isFlexible), vertical: metrics.contains(where: \.isFlexible)),
            rows: geometry)
    }

    private func gridCellGeometry(
        row: GridRowInput, sizes: [Size], metrics: GridRowMetrics, height: Double,
        tracks: [GridTrackRun], totalWidth: Double, layout: RetainedGridLayout
    ) -> [GridCellGeometry] {
        let spacing = gridSpacing(layout.horizontalSpacing)
        return row.cells.enumerated().map { index, cell in
            let size = sizes[index]
            let span = gridSpanExtent(
                tracks, firstColumn: cell.firstColumn, endColumn: cell.endColumn, spacing: spacing)
            let logicalX = gridTrackOrigin(tracks, firstColumn: cell.firstColumn, spacing: spacing)
            let columnX = layout.isRightToLeft ? totalWidth - logicalX - span : logicalX
            let track = tracks.first(where: { $0.firstColumn == cell.firstColumn })
            let alignment =
                cell.isMerged
                ? gridHorizontalAlignment(layout.horizontalAlignment, isRightToLeft: layout.isRightToLeft)
                : (track?.alignment ?? layout.horizontalAlignment)
            let anchor =
                cell.node.gridCellAnchor
                ?? (cell.isMerged ? Point(x: gridAnchor(for: alignment), y: gridAnchor(for: row.alignment)) : nil)
            let x: Double
            let y: Double
            if let anchor {
                // Explicit unit coordinates are physical. Exact SwiftUI RTL
                // anchor mirroring remains a separate native characterization.
                x = columnX + sanitizedLayoutCoordinate(anchor.x) * (span - size.width)
                y = sanitizedLayoutCoordinate(anchor.y) * (height - size.height)
            } else {
                let guideBefore = track?.guideBefore ?? 0
                let guideAfter = track?.guideAfter ?? 0
                x =
                    columnX + guideBefore + (span - guideBefore - guideAfter) * gridAnchor(for: alignment)
                    - gridGuideValue(for: cell.node, axis: .vertical, alignment: alignment, extent: size.width)
                y =
                    metrics.guideBefore
                    + (height - metrics.guideBefore - metrics.guideAfter) * gridAnchor(for: row.alignment)
                    - gridGuideValue(for: cell.node, axis: .horizontal, alignment: row.alignment, extent: size.height)
            }
            return GridCellGeometry(
                identity: ObjectIdentifier(cell.node),
                frame: sanitizedLayoutRect(Rect(x: x, y: y, width: size.width, height: size.height)))
        }
    }

    /// Deferred data rows use the metadata prefix index; no placeholder node
    /// and no factory participates in measuring or placing an absent record.
    /// The vertical lazy stack uses the adapter's inter-leaf spacing under a
    /// finite viewport. Styled outer padding belongs to its scroll container.
    fileprivate func lazyListViewport(
        displayScale: Double
    ) -> (RetainedLazyListRuntimeAdapter.Viewport, ViewNode, Double)? {
        var contentOrigin: Point?
        guard !isHidden, !isRetiringLazyListAttachment, scrollAxis == nil,
            case .lazyStack(let stack) = layoutMode, stack.axis == .vertical,
            stack.spacing == retainedLazyListAdapter?.interLeafSpacing,
            stack.padding == .zero, stack.mainAlignment == .start,
            stack.distribution == .fill, stack.alignment == .leading || stack.alignment == .stretch,
            let window = layoutVirtualizationWindow(contentOrigin: &contentOrigin),
            let scroll = virtualizationScrollAncestor,
            scroll.scrollAxis == .vertical, !scroll.isHidden,
            resolvedFrame.width.isFinite, resolvedFrame.width > 0,
            window.height.isFinite, window.height > 0,
            let context = RetainedLazyListMeasurementContext(
                width: resolvedFrame.width, displayScale: displayScale,
                contentRevision: lazyListContentRevision, environmentRevision: lazyListEnvironmentRevision),
            let viewport = RetainedLazyListRuntimeAdapter.Viewport(
                context: context, offset: window.minY, extent: window.height)
        else { return nil }
        // Preserve the canonical ancestor sum. Subtracting two offsets back
        // out of the window can change its low bits when clamping scrolls.
        guard let origin = contentOrigin?.y, origin.isFinite else { return nil }
        return (viewport, scroll, origin)
    }

    @inline(never)
    private func layoutRetainedLazyListChildren(descendants: inout [ViewNode]) {
        guard let adapter = retainedLazyListAdapter else { return }
        resolvedContentSize = sanitizedLayoutSize(
            Size(width: resolvedFrame.width, height: adapter.contentExtent))
        guard let runtime, let (visit, plan) = runtime.lazyListLayoutPlan(for: self) else { return }
        if plan.hasLogicalOmissions || plan.requiresResolution {
            virtualizationScrollAncestor?.hasVirtualizedDescendants = true
        }
        var recordToken: RetainedLazyListRowToken?
        var recordOrigin = 0.0
        var localOffset = 0.0
        for placement in plan.placements {
            guard runtime.lazyListVisitIsCurrent(visit), placement.node.parent === self,
                placement.node.runtime === runtime
            else {
                runtime.rejectLazyListLayoutVisit()
                return
            }
            if recordToken != placement.token {
                recordToken = placement.token
                recordOrigin = placement.originY
                localOffset = 0
            }
            let child = placement.node
            let attachment = child.captureLazyListAttachmentProof()
            // The measured prefix places later records. Natural measurement
            // of this bounded mounted leaf also detects local state changes
            // which do not replace the provider's logical generation.
            let measured: Size
            if child.isHidden {
                measured = .zero
            } else if child.retainedLazyListGap != nil {
                // An unknown predecessor gives provisional zero geometry.
                // The adapter withholds measurement publication/settlement
                // until its bounded native boundary query has an answer.
                measured = Size(width: resolvedFrame.width, height: placement.extent ?? 0)
            } else {
                measured = child.sizeThatFits(in: LayoutConstraints(maxWidth: resolvedFrame.width))
            }
            guard runtime.lazyListVisitIsCurrent(visit), attachment.isCurrent,
                measured.width.isFinite, measured.height.isFinite, measured.height >= 0
            else {
                runtime.rejectLazyListLayoutVisit()
                return
            }
            let measuredWidth = min(resolvedFrame.width, max(0, measured.width))
            let expands =
                layoutMode.stackLayout?.alignment == .stretch
                || (measuredWidth == 0 && child.expandsAlongStackCrossAxis)
            let width = child.isHidden ? 0 : expands ? resolvedFrame.width : measuredWidth
            let origin = recordOrigin + localOffset
            localOffset += measured.height + adapter.interLeafSpacing
            guard origin.isFinite, localOffset.isFinite else {
                runtime.rejectLazyListLayoutVisit()
                return
            }
            let crossOrigin =
                stackCrossOriginUsingAlignmentGuide(
                    for: child, stackAxis: .vertical,
                    stackAlignment: layoutMode.stackLayout?.alignment ?? .leading,
                    contentOrigin: 0, contentExtent: resolvedFrame.width, childExtent: width) ?? 0
            guard crossOrigin.isFinite else {
                runtime.rejectLazyListLayoutVisit()
                return
            }
            child.resolvedFrame = Rect(x: crossOrigin, y: origin, width: width, height: measured.height)
            _ = child.resumeVirtualizedLayout()
            runtime.recordLazyListLeafMeasurement(
                placement, attachment: attachment, container: self)
            // Even clean mounted leaves get the actual pass stamp. The
            // traversal's existing cache still skips their unchanged subtrees.
            if !child.isHidden { descendants.append(child) }
        }
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
            scrollContainerState?.contentSize = Size(width: contentCrossExtent, height: contentMainExtent)
            return Size(
                width: max(resolvedFrame.size.width, contentCrossExtent),
                height: max(resolvedFrame.size.height, contentMainExtent)
            )
        case .horizontal:
            scrollContainerState?.contentSize = Size(width: contentMainExtent, height: contentCrossExtent)
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
        var desiredSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
        let desiredMainSizes = desiredSizes.map { size in
            stackLayout.axis == .vertical ? size.height : size.width
        }
        let spacingTotal = stackLayoutSpacingTotal(count: visibleChildren.count, spacing: stackLayout.spacing)
        let availableMainExtent =
            stackLayout.axis == .vertical ? max(0, contentRect.size.height) : max(0, contentRect.size.width)
        let availableChildMainExtent = max(0, availableMainExtent - spacingTotal)
        let allowsOverflowAlongMainAxis = scrollAxis == stackScrollAxis(for: stackLayout.axis)

        let allocatedMainSizes = allocatedStackMainSizes(
            for: stackLayout,
            desiredMainSizes: desiredMainSizes,
            children: visibleChildren,
            childConstraints: childConstraints,
            fullMainExtent: stackLayout.axis == .vertical ? resolvedFrame.height : resolvedFrame.width,
            availableChildMainExtent: availableChildMainExtent,
            allowsOverflowAlongMainAxis: allowsOverflowAlongMainAxis)

        if stackLayout.axis == .horizontal {
            for index in visibleChildren.indices
            where allocatedMainSizes[index] != desiredSizes[index].width
                && visibleChildren[index].needsMeasurement(
                    atStackWidth: allocatedMainSizes[index], originalConstraints: childConstraints)
            {
                desiredSizes[index].height =
                    visibleChildren[index].sizeThatFits(
                        in: LayoutConstraints(
                            maxWidth: allocatedMainSizes[index], maxHeight: childConstraints.maxHeight)
                    ).height
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

    /// Measurement and placement must allocate the same widths before asking
    /// children for their heights. Keep floors, equal shares, and flex rules in
    /// one place so a wrapping row cannot measure one width and paint another.
    @inline(never)
    private func allocatedStackMainSizes(
        for stackLayout: StackLayout,
        desiredMainSizes: [Double],
        children visibleChildren: [ViewNode],
        childConstraints: LayoutConstraints,
        fullMainExtent: Double,
        availableChildMainExtent: Double,
        allowsOverflowAlongMainAxis: Bool
    ) -> [Double] {
        if allowsOverflowAlongMainAxis { return desiredMainSizes }

        if stackLayout.distribution == .fillEqually, !visibleChildren.isEmpty {
            let share =
                availableChildMainExtent.isFinite
                ? max(0, availableChildMainExtent / Double(visibleChildren.count))
                : (desiredMainSizes.max() ?? 0)
            return [Double](repeating: share, count: visibleChildren.count)
        }

        // A floor protects text from siblings, not from a container smaller
        // than the child alone. The full extent includes padding, which can
        // compress before text loses any of its measured height.
        var shrinkFloors: [Double] = []
        if desiredMainSizes.reduce(0, +) > availableChildMainExtent {
            shrinkFloors = visibleChildren.map {
                min(
                    $0.stackShrinkFloorMainExtent(along: stackLayout.axis, constraints: childConstraints),
                    fullMainExtent)
            }
        }

        var allocatedMainSizes = allocateMainSizes(
            desiredSizes: desiredMainSizes,
            children: visibleChildren,
            axis: stackLayout.axis,
            availableExtent: availableChildMainExtent,
            shrinkFloors: shrinkFloors)

        let remaining = availableChildMainExtent - allocatedMainSizes.reduce(0, +)
        if remaining > 0 {
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

        return allocatedMainSizes
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
        var contentOrigin: Point?
        return layoutVirtualizationWindow(contentOrigin: &contentOrigin)
    }

    private func layoutVirtualizationWindow(contentOrigin: inout Point?) -> Rect? {
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
                contentOrigin = Point(x: offsetX, y: offsetY)
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
                    start: finish.startIndex, end: state.currentIndex, generation: state.generation)
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
                node.cachedPrepaintRange = PrepaintStateRange(
                    start: startIndex, end: startIndex, generation: state.generation)
                continue
            }

            if node.isHidden {
                node.cachedPrepaintKey = nil
                node.cachedPrepaintRange = PrepaintStateRange(
                    start: startIndex, end: startIndex, generation: state.generation)
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
                node.cachedPrepaintRange = PrepaintStateRange(
                    start: startIndex, end: startIndex, generation: state.generation)
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
                    node.cachedPrepaintRange = PrepaintStateRange(
                        start: startIndex, end: startIndex, generation: state.generation)
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
                let previousRange = node.cachedPrepaintRange,
                previousRange.generation == previousState.generation
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
            fromGeneration: previousState.generation,
            toGeneration: state.generation,
            dispatchDelta: dispatchDelta,
            interactionDelta: interactionDelta,
            focusOrderDelta: focusOrderDelta,
            deferredSubtreeDelta: deferredSubtreeDelta,
            deferredDrawDelta: deferredDrawDelta,
            deferredPriorityDelta: deferredPriorityDelta
        )
        cachedPrepaintKey = cacheKey
        cachedPrepaintRange = PrepaintStateRange(
            start: startIndex, end: state.currentIndex, generation: state.generation)
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
        previousRenderedFrame: FramePaintSnapshot? = nil,
        snapshotIdentity: PaintSnapshotIdentity,
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
                state.node.cachedFrameSnapshotIdentity = snapshotIdentity
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
                node.cachedFrameSnapshotIdentity = snapshotIdentity
                node.markSubtreeRendered()
                continue
            }

            if node.isHidden {
                node.cachedFrameKey = nil
                node.cachedFrameCommandRange = startIndex..<startIndex
                node.cachedFrameSnapshotIdentity = snapshotIdentity
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
                node.cachedFrameSnapshotIdentity = snapshotIdentity
                node.markSubtreeRendered()
                continue
            }

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
                    node.cachedFrameSnapshotIdentity = snapshotIdentity
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
                node.cachedFrameSnapshotIdentity = snapshotIdentity
                node.markSubtreeRendered()
                continue
            }

            if let previousRenderedFrame,
                !node.hasDirtySubtree,
                node.cachedFrameKey == cacheKey,
                node.cachedFrameSnapshotIdentity == previousRenderedFrame.identity,
                let previousRange = node.cachedFrameCommandRange,
                previousRange.lowerBound >= 0,
                previousRange.upperBound <= previousRenderedFrame.frame.commands.count
            {
                commands.append(contentsOf: previousRenderedFrame.frame.commands[previousRange])
                let delta = startIndex - previousRange.lowerBound
                node.shiftCachedFrameRangesRecursively(
                    by: delta, from: previousRenderedFrame.identity, to: snapshotIdentity)
                node.cachedFrameKey = cacheKey
                node.cachedFrameCommandRange = startIndex..<commands.count
                node.cachedFrameSnapshotIdentity = snapshotIdentity
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
                displayScale: displayScale,
                canvasCoordinateScale: node.canvasDraw == nil
                    ? 1 : PaintPlacement.lowering(absoluteFrame, through: effectiveTransform).scale
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

    @MainActor
    fileprivate struct RenderLifecycleCandidate {
        weak var node: ViewNode?
        let absoluteFrame: Rect
    }

    /// Lifecycle belongs to the mounted tree, not a painter's recording or
    /// replay. Snapshot the same visibility and geometry the frame traversal
    /// used before moving its callbacks to the shared render entry point.
    fileprivate func appendRenderLifecycleCandidates(
        into candidates: inout [RenderLifecycleCandidate],
        parentOrigin: Point,
        inheritedClip: RuntimeClipShape?,
        inheritedOpacity: Float = 1,
        inheritedTransform: Transform2D = .identity
    ) {
        let baseDepth = ViewNode.traversalDepth
        defer { ViewNode.traversalDepth = baseDepth }
        var traversal = [
            FrameTraversalContext(
                node: self, parentOrigin: parentOrigin, inheritedClip: inheritedClip,
                inheritedOpacity: inheritedOpacity, inheritedBlendMode: .normal,
                inheritedTransform: inheritedTransform, depth: 0)
        ]
        while let context = traversal.popLast() {
            let node = context.node
            guard ViewNode.enterTraversal(atDepth: baseDepth + context.depth),
                !node.isHidden, !node.isRemovalOverlay, !node.isLayoutDeferredByVirtualization
            else { continue }
            let absoluteFrame = Rect(
                x: context.parentOrigin.x + node.resolvedFrame.origin.x,
                y: context.parentOrigin.y + node.resolvedFrame.origin.y,
                width: node.resolvedFrame.size.width,
                height: node.resolvedFrame.size.height)
            let (paintFrame, effectiveTransform) = Self.accumulatedPaintGeometry(
                of: absoluteFrame, transform: node.transform, inheritedTransform: context.inheritedTransform)
            guard context.inheritedClip.allowsSubtreeTraversal(bounds: paintFrame) else { continue }
            if !node.hasAppeared || node.hasPendingAppearanceCallbacks || node.previousFrame != absoluteFrame {
                candidates.append(RenderLifecycleCandidate(node: node, absoluteFrame: absoluteFrame))
            }

            // The node itself appears before its own clip or opacity can stop
            // descent. In particular an opacity-zero node does not make its
            // descendants appear, and an unclipped zero-size box can overflow.
            var effectiveClip = context.inheritedClip
            if node.clipsToBounds {
                guard
                    let clipped = context.inheritedClip.narrowed(
                        to: paintFrame, radii: node.cornerRadii, uniformRadius: node.cornerRadius,
                        space: .painted)
                else { continue }
                effectiveClip = clipped
            }
            let effectiveOpacity = context.inheritedOpacity * Float(node.opacity)
            guard effectiveOpacity > 0 else { continue }
            let childOrigin = Point(
                x: absoluteFrame.origin.x - (node.scrollAxis == .horizontal ? node.resolvedScrollOffset : 0),
                y: absoluteFrame.origin.y - (node.scrollAxis == .vertical ? node.resolvedScrollOffset : 0))
            for child in node.orderedChildrenForPaint().reversed() where !child.paintsInDeferredPhase {
                traversal.append(
                    FrameTraversalContext(
                        node: child, parentOrigin: childOrigin, inheritedClip: effectiveClip,
                        inheritedOpacity: effectiveOpacity, inheritedBlendMode: .normal,
                        inheritedTransform: effectiveTransform, depth: context.depth + 1))
            }
        }
    }

    fileprivate func fireRenderLifecycleCallbacks(absoluteFrame: Rect, in runtime: RetainedViewRuntime) {
        guard runtime.canDeliverRenderLifecycle(to: self) else { return }
        let isFirstAppearance = !hasAppeared
        let isCompletingAppearance = isFirstAppearance || hasPendingAppearanceCallbacks
        let didMove = !isCompletingAppearance && previousFrame != nil && previousFrame != absoluteFrame
        let revision = runtime.renderLifecycleRevision
        let taskState = lifecycleHandlers?.retainedTasks
        let taskAppearance = taskState?.beginAppearance(in: runtime, revision: revision)
        defer {
            if let taskAppearance { taskState?.endAppearance(taskAppearance) }
        }
        // Commit this event before invoking application code. Nested renders
        // must not observe an unfinished appearance or repeat a size change.
        hasAppeared = true
        isInitialBuildNode = false
        previousFrame = absoluteFrame
        if isFirstAppearance {
            hasPendingAppearanceCallbacks = true
            hasPendingAppearanceNodeCallback = true
            onAppear?()
            guard hasAppeared, runtime.canDeliverRenderLifecycle(to: self) else { return }
            // The same retained node can now carry a different task or node
            // callback. Finish that phase only after its new geometry settles;
            // do not lose it or repeat the already delivered onAppear action.
            guard runtime.renderLifecycleRevision == revision else { return }
        }
        if hasPendingAppearanceCallbacks {
            if hasPendingAppearanceNodeCallback {
                hasPendingAppearanceNodeCallback = false
                onAppearWithNode?(self)
                guard hasAppeared, runtime.canDeliverRenderLifecycle(to: self) else { return }
                guard runtime.renderLifecycleRevision == revision else { return }
            }
            // Some producers register only pending launches, with no node
            // callback. Keep the newest build's declarations through a
            // deferred appearance, without restarting keys its hook launched.
            let launches = pendingLifecycleTaskLaunches
            pendingLifecycleTaskLaunches.removeAll()
            for launch in launches where lifecycleTasks[launch.key] == nil {
                launchLifecycleTask(launch)
            }
            if let taskState = lifecycleHandlers?.retainedTasks {
                taskState.deliverPendingAppearance(in: runtime, revision: revision)
                guard hasAppeared, runtime.canDeliverRenderLifecycle(to: self),
                    runtime.renderLifecycleRevision == revision
                else { return }
            }
            hasPendingAppearanceCallbacks = false
            if scrollIndicatorsFlashOnAppear {
                runtime.flashScrollIndicator(for: self)
            }
        }
        if didMove { onSizeChange?(absoluteFrame) }
        guard isRetainedLazyTaskRenderAdmissionCurrent(in: runtime, revision: revision) else { return }
        if let activity = retainedLazyListActivityStorage {
            // Record an actual completed render for this physical generation.
            // A later first Task modifier may reuse this native fact; flags
            // alone cannot prove that appearance predates no detach/reattach.
            lifecycleHandlers?.completedLazyTaskAppearance = activity.captureActualAttachment(of: self, in: runtime)
        }
        if let taskState, lifecycleHandlers?.retainedTasks === taskState {
            taskState.noteLazyTaskRenderAdmission(in: runtime, revision: revision)
        }
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
        displayScale: Double,
        canvasCoordinateScale: Double
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
                            clipRect: effectiveClipRect,
                            fillRule: clipFillStyle?.eoFill == true ? .evenOdd : .nonZero
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
            baseClipAllowsDrawing(baseClip: effectiveClip, rect: fillRect),
            let sampling = resolvedBitmapImageSampling(bitmapSurface)
        {
            commands.append(
                .drawBitmap(
                    DrawBitmapCommand(
                        rect: fillRect,
                        bitmap: bitmapSurface,
                        opacity: effectiveOpacity,
                        clipRect: effectiveClipRect,
                        sampling: sampling,
                        placement: .destinationRect
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
            canvasDraw(&context, fillRect.size.scaled(by: 1 / canvasCoordinateScale))
            context.appendCommands(
                into: &commands,
                // Draw in logical Canvas coordinates, then apply the inherited
                // uniform scale before its placed origin and border inset.
                origin: fillRect.origin,
                clipRect: effectiveClipRect,
                opacity: effectiveOpacity,
                displayScale: displayScale,
                coordinateScale: canvasCoordinateScale
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
        // Only the receiver's authored layout changes revoke this stamp.
        // Dirty propagation from a child is not an ancestor configuration
        // change, and an admitted child-list replacement has its own proof.
        if flags.contains(.layout) { lifecycleHandlers?.lazyListLayoutIdentity = nil }
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
            if !flags.intersection([.layout, .children]).isEmpty {
                node.invalidateGridGeometry()
            }
            currentNode = node.parent
        }
    }

    private func invalidateGridGeometry() {
        guard resolvedGridGeometry != nil else { return }
        // Clear before scheduling. Installing resolved frames does not call
        // this hook, and a second mutation before recomputation cannot enqueue
        // another request for the same plan.
        resolvedGridGeometry = nil
        guard case .grid = layoutMode, let runtime, runtime.isLayoutInProgress else { return }
        var current: ViewNode? = self
        var visited: Set<ObjectIdentifier> = []
        while let node = current, visited.count < ViewNode.maximumTraversalDepth {
            guard visited.insert(ObjectIdentifier(node)).inserted, node.runtime === runtime else { return }
            if node === runtime.root {
                // No node, source view, context, or callback is captured. The
                // ordinary bounded after-layout loop performs the next pass.
                runtime.scheduleAfterLayout(key: "grid-shared-tracks-\(ObjectIdentifier(self))") {}
                return
            }
            guard let parent = node.parent, parent.children.contains(where: { $0 === node }) else { return }
            current = parent
        }
    }

    func shiftCachedFrameRangesRecursively(
        by delta: Int, from previousIdentity: PaintSnapshotIdentity, to snapshotIdentity: PaintSnapshotIdentity
    ) {
        guard ViewNode.enterTraversal() else { return }
        defer { ViewNode.leaveTraversal() }

        guard let existingRange = cachedFrameCommandRange, cachedFrameSnapshotIdentity == previousIdentity else {
            return
        }
        cachedFrameCommandRange = (existingRange.lowerBound + delta)..<(existingRange.upperBound + delta)
        cachedFrameSnapshotIdentity = snapshotIdentity

        for child in children {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.shiftCachedFrameRangesRecursively(by: delta, from: previousIdentity, to: snapshotIdentity)
        }
    }

    func shiftCachedPrepaintRangesRecursively(
        fromGeneration: PrepaintSnapshotIdentity,
        toGeneration: PrepaintSnapshotIdentity,
        dispatchDelta: Int,
        interactionDelta: Int,
        focusOrderDelta: Int,
        deferredSubtreeDelta: Int,
        deferredDrawDelta: Int,
        deferredPriorityDelta: Int
    ) {
        guard ViewNode.enterTraversal() else { return }
        defer { ViewNode.leaveTraversal() }

        // Hidden or clipped branches did not contribute their descendants to
        // the copied snapshot. Do not rebase those older ranges or make them
        // appear current merely because a visible ancestor was replayed.
        guard let existingRange = cachedPrepaintRange, existingRange.generation == fromGeneration else { return }
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
            ),
            generation: toGeneration
        )

        for child in children {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.shiftCachedPrepaintRangesRecursively(
                fromGeneration: fromGeneration,
                toGeneration: toGeneration,
                dispatchDelta: dispatchDelta,
                interactionDelta: interactionDelta,
                focusOrderDelta: focusOrderDelta,
                deferredSubtreeDelta: deferredSubtreeDelta,
                deferredDrawDelta: deferredDrawDelta,
                deferredPriorityDelta: deferredPriorityDelta
            )
        }
    }

    func shiftCachedSceneRangesRecursively(
        by delta: Int, from previousIdentity: PaintSnapshotIdentity, to snapshotIdentity: PaintSnapshotIdentity
    ) {
        guard ViewNode.enterTraversal() else { return }
        defer { ViewNode.leaveTraversal() }

        guard let existingRange = cachedScenePaintRange, cachedSceneSnapshotIdentity == previousIdentity else {
            return
        }
        cachedScenePaintRange = (existingRange.lowerBound + delta)..<(existingRange.upperBound + delta)
        cachedSceneSnapshotIdentity = snapshotIdentity

        for child in children {
            guard !child.paintsInDeferredPhase else {
                continue
            }
            child.shiftCachedSceneRangesRecursively(by: delta, from: previousIdentity, to: snapshotIdentity)
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
        sizeThatFits(in: constraints, memo: MeasurementMemo())
    }

    private func sizeThatFits(in constraints: LayoutConstraints, memo: MeasurementMemo) -> Size {
        guard ViewNode.enterTraversal() else { return .zero }
        defer { ViewNode.leaveTraversal() }

        var plan = MeasurementPlan()
        if let cached = beginMeasurement(constraints, into: &plan, memo: memo) {
            return cached
        }

        if aspectFitLayout != nil, let size = measureAspectFit(plan: plan, memo: memo) {
            return size
        }

        if case .grid(let layout) = layoutMode {
            return measureGrid(layout: layout, plan: plan, memo: memo)
        }

        var childSizes: [Size] = []
        childSizes.reserveCapacity(children.count)
        for child in children where !child.isHidden {
            childSizes.append(
                child.sizeThatFits(
                    in: plan.measuresChildrenIndividually
                        ? absoluteChildConstraints(for: child, in: plan.childConstraints)
                        : plan.childConstraints,
                    memo: memo))
        }

        // Children have now resolved inherited greed, so a row containing a
        // Spacer can accept its proposal before widths are allocated.
        updateInheritedStackFillAxes()
        if let widths = horizontalStackMeasurementWidths(
            childSizes: childSizes,
            constraints: plan.effectiveConstraints,
            childConstraints: plan.childConstraints)
        {
            var index = 0
            for child in children where !child.isHidden {
                if widths[index] != childSizes[index].width,
                    child.needsMeasurement(atStackWidth: widths[index], originalConstraints: plan.childConstraints)
                {
                    childSizes[index].height =
                        child.sizeThatFits(
                            in: LayoutConstraints(maxWidth: widths[index], maxHeight: plan.childConstraints.maxHeight),
                            memo: memo
                        ).height
                }
                // Keep the allocated width, not the longest wrapped line's
                // slightly smaller advance: narrowing the row again here can
                // cause another line break when it is finally placed.
                childSizes[index].width = widths[index]
                index += 1
            }
        }

        return finishMeasurement(plan: plan, childSizes: childSizes, memo: memo)
    }

    /// Only the finite positive two-axis proposal is admitted here. Other
    /// proposals keep the existing ideal-size fallback until their semantics
    /// are characterized. In particular, never feed an unbounded proposal to
    /// AspectRatioConstraint's finite sentinel fallback.
    @inline(never)
    private func measureAspectFit(plan: MeasurementPlan, memo: MeasurementMemo) -> Size? {
        let constraints = plan.effectiveConstraints
        guard case .stack = layoutMode,
            let layout = aspectFitLayout, children.count == 1,
            let child = children.first, !child.isHidden,
            constraints.minWidth == 0, constraints.minHeight == 0,
            constraints.maxWidth.isFinite, constraints.maxWidth > 0,
            constraints.maxHeight.isFinite, constraints.maxHeight > 0
        else { return nil }

        let ratio: Double
        if let requestedRatio = layout.aspectRatio {
            ratio = requestedRatio
        } else {
            let ideal = child.sizeThatFits(in: .unconstrained, memo: memo)
            guard ideal.width.isFinite, ideal.width > 0, ideal.height.isFinite, ideal.height > 0 else { return nil }
            ratio = ideal.width / ideal.height
        }
        guard ratio.isFinite, ratio > 0 else { return nil }

        let proposal = AspectRatioConstraint(ratio: ratio, mode: .fit).measure(
            in: LayoutConstraints(maxWidth: constraints.maxWidth, maxHeight: constraints.maxHeight)
        ).size
        guard proposal.width.isFinite, proposal.width > 0, proposal.height.isFinite, proposal.height > 0 else {
            return nil
        }

        let acceptedSize = child.sizeThatFits(
            in: LayoutConstraints(maxWidth: proposal.width, maxHeight: proposal.height), memo: memo)
        inheritedStackFillAxes = LayoutFillAxes()
        // A frame or intrinsic child may decline the proposal. Report its
        // answer, not the proposal or the wrapper's legacy preferred size.
        return cacheMeasuredSize(acceptedSize, plan: plan, memo: memo, fittedAspect: layout)
    }

    @inline(never)
    private func horizontalStackMeasurementWidths(
        childSizes: [Size],
        constraints: LayoutConstraints,
        childConstraints: LayoutConstraints
    ) -> [Double]? {
        guard let stackLayout = layoutMode.stackLayout, stackLayout.axis == .horizontal,
            scrollAxis != .horizontal, contentMeasurementConstraints(in: constraints).maxWidth.isFinite
        else { return nil }

        let measuredSize = Self.stackMeasuredSize(of: childSizes, stackLayout: stackLayout)
        let width = applyingExplicitDimensions(to: measuredSize, constraints: constraints).width
        let availableExtent = max(
            0,
            width - stackMainPadding(for: stackLayout)
                - stackLayoutSpacingTotal(count: childSizes.count, spacing: stackLayout.spacing))
        let desiredWidths = childSizes.map(\.width)
        let widths = allocatedStackMainSizes(
            for: stackLayout,
            desiredMainSizes: desiredWidths,
            children: children.filter { !$0.isHidden },
            childConstraints: childConstraints,
            fullMainExtent: width,
            availableChildMainExtent: availableExtent,
            allowsOverflowAlongMainAxis: false)
        return widths == desiredWidths ? nil : widths
    }

    /// A larger allocated frame does not necessarily change a child's content
    /// proposal: an explicitly sized or fixed-size child can keep its own
    /// width. Avoid recursively measuring that unchanged subtree again at
    /// every enclosing horizontal stack.
    private func needsMeasurement(atStackWidth width: Double, originalConstraints: LayoutConstraints) -> Bool {
        let original = contentMeasurementConstraints(in: applyingLayoutConstraints(to: originalConstraints))
        let proposed = contentMeasurementConstraints(
            in: applyingLayoutConstraints(
                to: LayoutConstraints(maxWidth: width, maxHeight: originalConstraints.maxHeight)))
        return original.maxWidth != proposed.maxWidth
    }

    /// The cache probe and everything a node can decide before it measures a
    /// single child. Returns the cached size when this measurement is already
    /// known, in which case `plan` is not used.
    @inline(never)
    private func beginMeasurement(
        _ constraints: LayoutConstraints,
        into plan: inout MeasurementPlan,
        memo: MeasurementMemo
    ) -> Size? {
        let displayScale = runtime?.displayScale ?? 1.0
        let effectiveConstraints = applyingLayoutConstraints(to: constraints)
        let cacheKey = ViewMeasureCacheKey(constraints: effectiveConstraints, displayScale: displayScale)
        if let adapter = retainedLazyListAdapter {
            // This branch intentionally precedes both cache probes. Prefix
            // updates are scalar metadata, not a reason to measure all rows.
            let width =
                effectiveConstraints.maxWidth.isFinite
                ? max(0, effectiveConstraints.maxWidth) : max(0, explicitWidth ?? frame.width)
            let measured = applyingExplicitDimensions(
                to: Size(width: width, height: adapter.contentExtent), constraints: effectiveConstraints)
            let resolved = sanitizedLayoutSize(measured)
            cachedMeasurement = ViewMeasurementCacheEntry(
                key: cacheKey,
                result: ViewMeasurementResult(
                    size: resolved, fittedAspect: nil, inheritedFillAxes: inheritedStackFillAxes))
            return resolved
        }
        let layoutDirtyFlags = subtreeDirtyFlags.intersection([.layout, .children])
        if layoutDirtyFlags.isEmpty, let cachedMeasurement, cachedMeasurement.key == cacheKey {
            return reuseMeasuredSize(cachedMeasurement.result, cacheKey: cacheKey)
        }
        let memoKey = MeasurementMemo.Key(
            node: ObjectIdentifier(self), measurement: cacheKey, depth: ViewNode.traversalDepth)
        if let result = memo.results[memoKey] {
            return reuseMeasuredSize(result, cacheKey: cacheKey)
        }

        let contentConstraints = contentMeasurementConstraints(in: effectiveConstraints)
        plan.effectiveConstraints = effectiveConstraints
        plan.cacheKey = cacheKey
        plan.contentSize = bitmapContentSize() ?? textContentSize(in: contentConstraints) ?? .zero

        switch layoutMode {
        case .absolute:
            // Every child gets what is left of the container from its own
            // origin, so this is the one mode whose proposal is per child.
            plan.childConstraints = contentConstraints
            plan.measuresChildrenIndividually = true
        case .stack(let stackLayout), .lazyStack(let stackLayout):
            plan.childConstraints = stackChildConstraints(
                for: insetConstraints(contentConstraints, by: stackLayout.padding),
                axis: stackLayout.axis)
        case .gridRow(let rowLayout):
            plan.childConstraints = stackChildConstraints(
                for: contentConstraints, axis: rowLayout.standaloneStackLayout.axis)
        case .grid:
            plan.childConstraints = contentConstraints
        case .flex:
            plan.childConstraints = .unconstrained
        }
        return nil
    }

    private func stackChildConstraints(for size: Size, axis: StackAxis) -> LayoutConstraints {
        stackChildConstraints(
            for: LayoutConstraints(maxWidth: max(0, size.width), maxHeight: max(0, size.height)),
            axis: axis)
    }

    private func stackChildConstraints(for constraints: LayoutConstraints, axis: StackAxis) -> LayoutConstraints {
        if forwardsStackMainAxisProposal, children.count == 1 {
            return LayoutConstraints(maxWidth: constraints.maxWidth, maxHeight: constraints.maxHeight)
        }
        switch axis {
        case .vertical:
            return LayoutConstraints(maxWidth: constraints.maxWidth)
        case .horizontal:
            return LayoutConstraints(maxHeight: constraints.maxHeight)
        }
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
    private func finishMeasurement(
        plan: MeasurementPlan, childSizes: [Size], memo: MeasurementMemo, gridSize: Size? = nil
    ) -> Size {
        let measuredSize: Size
        switch layoutMode {
        case .absolute:
            measuredSize = absoluteMeasuredSize(contentSize: plan.contentSize, childSizes: childSizes)
        case .stack(let stackLayout), .lazyStack(let stackLayout):
            measuredSize = Self.stackMeasuredSize(of: childSizes, stackLayout: stackLayout)
        case .flex(let flexStyle):
            measuredSize = Self.flexMeasuredSize(of: childSizes, flexStyle: flexStyle)
        case .grid:
            measuredSize = gridSize ?? .zero
        case .gridRow(let rowLayout):
            measuredSize = Self.stackMeasuredSize(of: childSizes, stackLayout: rowLayout.standaloneStackLayout)
        }

        let resolvedSize = applyingExplicitDimensions(
            to: measuredSize, constraints: plan.effectiveConstraints)
        return cacheMeasuredSize(resolvedSize, plan: plan, memo: memo)
    }

    private func cacheMeasuredSize(
        _ resolvedSize: Size, plan: MeasurementPlan, memo: MeasurementMemo,
        fittedAspect: RetainedAspectFitLayout? = nil
    ) -> Size {
        let result = ViewMeasurementResult(
            size: resolvedSize, fittedAspect: fittedAspect, inheritedFillAxes: inheritedStackFillAxes)
        cachedMeasurement = ViewMeasurementCacheEntry(key: plan.cacheKey, result: result)
        memo.results[
            MeasurementMemo.Key(
                node: ObjectIdentifier(self), measurement: plan.cacheKey, depth: ViewNode.traversalDepth)
        ] = result
        return resolvedSize
    }

    private func reuseMeasuredSize(_ result: ViewMeasurementResult, cacheKey: ViewMeasureCacheKey) -> Size {
        cachedMeasurement = ViewMeasurementCacheEntry(key: cacheKey, result: result)
        // A fit wrapper can alternate between a legacy ideal probe and an
        // admitted finite proposal within one memo. Restore its greed with
        // that same result, including when the reused result is the fallback.
        if aspectFitLayout != nil { inheritedStackFillAxes = result.inheritedFillAxes }
        runtime?.recordMeasureReuse()
        return result.size
    }

    @inline(never)
    private func absoluteMeasuredSize(contentSize: Size, childSizes: [Size]) -> Size {
        var maxChildX = contentSize.width
        var maxChildY = contentSize.height

        var index = 0
        for child in children where !child.isHidden {
            let childSize = childSizes[index]
            index += 1
            let resolvedSize = child.absoluteLayoutSize(from: childSize)
            maxChildX = max(maxChildX, child.frame.origin.x + resolvedSize.width)
            maxChildY = max(maxChildY, child.frame.origin.y + resolvedSize.height)
        }

        return Size(width: maxChildX, height: maxChildY)
    }

    /// Keep the same size policy when folding an absolute subtree and placing
    /// its children. Accepted measurements already include local minima and
    /// fixedSize overflow, so they must not be clamped a second time here.
    private func absoluteLayoutSize(from measuredSize: Size) -> Size {
        let fixedAxes = fixedPreferredSizeAxes
        return Size(
            width: Self.absoluteLayoutExtent(
                measured: measuredSize.width, raw: frame.size.width, preferred: preferredSize?.width,
                isFixed: fixedAxes.horizontal, legacyExplicit: explicitWidth),
            height: Self.absoluteLayoutExtent(
                measured: measuredSize.height, raw: frame.size.height, preferred: preferredSize?.height,
                isFixed: fixedAxes.vertical, legacyExplicit: explicitHeight)
        )
    }

    private static func absoluteLayoutExtent(
        measured: Double, raw: Double, preferred: Double?, isFixed: Bool, legacyExplicit: Double?
    ) -> Double {
        if raw == 0, !isFixed, let preferred, preferred > 0, preferred.isFinite {
            return measured
        }
        // Fixed intent reads the current animated preference. Raw-frame and
        // zero/nonpositive/nonfinite branches keep their legacy precedence.
        return legacyExplicit ?? measured
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

    /// Both paint paths resolve in layout space before display scale or a
    /// transform moves the image. The descriptor then scales with its quad.
    func resolvedBitmapImageSampling(_ bitmap: BitmapSurface) -> ImageSamplingDescriptor? {
        guard imageUsesBitmapResizing, let imageResizingMode else {
            imageSamplingFailure = nil
            return .legacy
        }
        let localFrame = Rect(origin: .zero, size: resolvedFrame.size)
        let localFillFrame = borderWidth > 0 ? localFrame.inset(by: borderWidth) : localFrame
        let mode: ImageSamplingMode = imageResizingMode == .tile ? .tile : .stretch
        switch ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: bitmap.width, height: bitmap.height),
            destinationSize: localFillFrame.size,
            capInsets: imageCapInsets ?? .zero,
            mode: mode)
        {
        case .success(let sampling):
            imageSamplingFailure = nil
            return sampling
        case .failure(let failure):
            imageSamplingFailure = failure
            return nil
        }
    }

    /// Measure content at the width it will actually receive. Applying a
    /// preferred width only after measurement gives a narrow paragraph the
    /// height of the wider proposal, so its last lines collide with the next
    /// row. Keep these content proposals separate from the node's sizing
    /// constraints: an explicit fill axis may still accept the full proposal.
    private func contentMeasurementConstraints(in constraints: LayoutConstraints) -> LayoutConstraints {
        let width: Double
        if let explicitWidth,
            !(frame.size.width <= 0 && layoutFillAxes.horizontal && constraints.maxWidth.isFinite)
        {
            width = clampedExtent(explicitWidth, min: constraints.minWidth, max: constraints.maxWidth)
        } else {
            width = constraints.maxWidth
        }

        let height: Double
        if let explicitHeight,
            !(frame.size.height <= 0 && layoutFillAxes.vertical && constraints.maxHeight.isFinite)
        {
            height = clampedExtent(explicitHeight, min: constraints.minHeight, max: constraints.maxHeight)
        } else {
            height = constraints.maxHeight
        }

        return LayoutConstraints(
            minWidth: constraints.minWidth, maxWidth: width,
            minHeight: constraints.minHeight, maxHeight: height)
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
    /// paragraphs that can reflow or explicitly truncate take no
    /// width floor. Their measured height still protects every allocated line.
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

        // fixedSize can live on a padding/container wrapper rather than on
        // the text itself. It ends width negotiation for the whole subtree.
        if axis == .horizontal, fixedSizeAxes?.horizontal == true {
            return max(declaredMinimum, sizeThatFits(in: constraints).width)
        }

        if let text, !text.isEmpty {
            // Paragraphs can reflow and ask for more height; explicit
            // single-line text can truncate. Preserve compact ASCII tokens
            // such as Compute or 68% under sibling pressure, but do not
            // infer word boundaries from missing spaces in other scripts.
            // A token's own narrower frame still participates below, so an
            // explicitly narrow word can wrap.
            if axis == .horizontal {
                let preservesSingleASCIIToken =
                    text.utf8.allSatisfy { $0 < 0x80 }
                    && text.split(maxSplits: 1, whereSeparator: \.isWhitespace).count == 1
                let canReflow = textStyle.lineBreakMode == .wrap && !preservesSingleASCIIToken
                if textStyle.maximumNumberOfLines == 1 || canReflow {
                    return declaredMinimum
                }
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

        let effectiveConstraints = applyingLayoutConstraints(to: constraints)
        let contentConstraints = insetConstraints(
            contentMeasurementConstraints(in: effectiveConstraints), by: stackLayout.padding)
        let childConstraints = stackChildConstraints(for: contentConstraints, axis: stackLayout.axis)
        let visibleChildren = children.filter { !$0.isHidden }
        let allocatedWidths: [Double]?
        if axis == .vertical, stackLayout.axis == .horizontal, contentConstraints.maxWidth.isFinite {
            let childSizes = visibleChildren.map { $0.sizeThatFits(in: childConstraints) }
            updateInheritedStackFillAxes()
            allocatedWidths = horizontalStackMeasurementWidths(
                childSizes: childSizes, constraints: effectiveConstraints, childConstraints: childConstraints)
        } else {
            allocatedWidths = nil
        }
        let childFloors = visibleChildren.enumerated().map { index, child in
            child.stackShrinkFloorMainExtent(
                along: axis,
                constraints: allocatedWidths.map {
                    LayoutConstraints(maxWidth: $0[index], maxHeight: childConstraints.maxHeight)
                } ?? childConstraints)
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

    fileprivate var acceptsScrollInput: Bool {
        isScrollable && isScrollInputEnabled
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
        guard acceptsScrollInput, delta.isFinite, scrollStep.isFinite, scrollStep > 0 else {
            return 0
        }

        let previousOffset = clampedScrollOffset(for: scrollOffset)
        let proposedOffset = previousOffset - delta * scrollStep
        guard proposedOffset.isFinite else { return 0 }
        let nextOffset = clampedScrollOffset(for: proposedOffset)
        guard nextOffset != previousOffset else {
            if scrollOffset != nextOffset {
                scrollOffset = nextOffset
            }
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
        guard acceptsScrollInput, maxScrollOffset > 0, delta.isFinite, scrollStep.isFinite, scrollStep > 0 else {
            return 0
        }

        let proposedOffset = clampedScrollOffset(for: scrollOffset) - delta * scrollStep
        guard proposedOffset.isFinite else { return 0 }
        return proposedOffset - clampedScrollOffset(for: proposedOffset)
    }

    fileprivate func applyKeyboardScroll(_ key: KeyboardKey) -> Bool {
        guard let offset = requestedKeyboardScrollOffset(for: key) else { return false }
        return setScrollOffset(offset)
    }

    fileprivate func requestedKeyboardScrollOffset(for key: KeyboardKey) -> Double? {
        guard acceptsScrollInput else {
            return nil
        }

        switch (scrollAxis, key) {
        case (.vertical, .downArrow), (.horizontal, .rightArrow):
            return scrollOffset + scrollStep
        case (.vertical, .upArrow), (.horizontal, .leftArrow):
            return scrollOffset - scrollStep
        case (_, .pageDown):
            return scrollOffset + (scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width)
                * 0.85
        case (_, .pageUp):
            return scrollOffset - (scrollAxis == .vertical ? resolvedFrame.size.height : resolvedFrame.size.width)
                * 0.85
        case (_, .home):
            return 0
        case (_, .end):
            return maxScrollOffset
        default:
            return nil
        }
    }

    fileprivate func applyScrollIndicatorDrag(startOffset: Double, delta: Double, travel: Double) -> Bool {
        guard acceptsScrollInput, maxScrollOffset > 0, travel > 0 else {
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

    /// Reveals this node in its nearest scrollable ancestor. A live runtime
    /// also cancels momentum and resolves deferred lazy-stack descendants;
    /// an already-laid-out standalone tree can still adjust its own offset
    /// without keeping the runtime alive through an interaction closure.
    @discardableResult
    public func scrollIntoView() -> Bool {
        if let runtime {
            return runtime.scrollToDescendant(self)
        }

        guard let (target, scrollContainer) = nearestScrollTarget(),
            scrollContainer.cachedLayoutKey != nil,
            scrollContainer.pendingLayoutKey == nil,
            let requestedOffset = Self.requestedScrollOffset(
                for: target,
                within: scrollContainer,
                anchor: nil
            )
        else {
            return false
        }

        _ = scrollContainer.setScrollOffset(requestedOffset)
        return true
    }

    fileprivate func nearestScrollTarget() -> (target: ViewNode, container: ViewNode)? {
        var target = self
        var candidate: ViewNode? = self
        var depth = 0
        while let node = candidate, depth < Self.maximumTraversalDepth {
            guard !node.isHidden else { return nil }
            if node.isLayoutDeferredByVirtualization {
                target = node
            }
            if node.scrollAxis != nil {
                return (target, node)
            }
            candidate = node.parent
            depth += 1
        }
        return nil
    }

    fileprivate static func requestedScrollOffset(
        for target: ViewNode,
        within scrollContainer: ViewNode,
        anchor: Double?,
        visibleOffset: Double? = nil
    ) -> Double? {
        guard let axis = scrollContainer.scrollAxis, anchor?.isFinite ?? true else {
            return nil
        }

        var targetFrame = target.resolvedFrame
        var ancestor = target.parent
        var depth = 0
        while let node = ancestor, node !== scrollContainer,
            depth < maximumTraversalDepth
        {
            targetFrame = targetFrame.offsetBy(
                dx: node.resolvedFrame.origin.x,
                dy: node.resolvedFrame.origin.y
            )
            ancestor = node.parent
            depth += 1
        }
        guard ancestor === scrollContainer else {
            return nil
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
            return nil
        }

        if let anchor {
            let boundedAnchor = min(max(anchor, 0), 1)
            return targetStart + targetExtent * boundedAnchor - viewportExtent * boundedAnchor
        }
        let currentOffset = visibleOffset ?? scrollContainer.scrollOffset
        if targetStart < currentOffset {
            return targetStart
        }
        if targetStart + targetExtent > currentOffset + viewportExtent {
            return targetStart + targetExtent - viewportExtent
        }
        return currentOffset
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
            if interactionSurface?.appliesSurfaceSheen == true {
                backgroundGradient = Controls.backgroundSheen(for: color)
            }
        case .border:
            borderColor = color
            if interactionSurface?.appliesSurfaceSheen == true {
                borderGradient = Controls.borderSheen(for: color)
            }
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
    /// wrote, using the transaction selected by reconciliation.
    ///
    /// The gradient ends are animated too, and that is not a nicety: a
    /// gradient wins over `backgroundColor` at paint time, so a tween that
    /// moved only the colour under a snapped gradient would not be visible at
    /// all.
    @discardableResult
    func applyReconcileFillTween(
        fromBackgroundColor: Color?, fromBackgroundGradient: GradientType?,
        animation: AnimationTransaction?, animationsDisabled: Bool,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        guard let runtime else { return true }
        let attachment = admission == nil ? nil : captureLazyListAttachmentProof()
        if let target = backgroundColor {
            let fromBackgroundColor = fromBackgroundColor ?? .clear
            if fromBackgroundColor != target {
                admission?.markMutationStarted()
                backgroundColor = fromBackgroundColor
            }
            guard
                runtime.reconcileColor(
                    .background, of: self, to: target, animation: animation,
                    animationsDisabled: animationsDisabled, admission: admission, nativeCheck: nativeCheck),
                admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
            else { return false }
        } else if fromBackgroundColor != nil {
            admission?.markMutationStarted()
            runtime.cancelColorAnimation(.background, of: self)
        }
        if let fromBackgroundGradient, let target = backgroundGradient {
            let startColor = target.startColor
            let endColor = target.endColor
            let startingGradient = target.replacingStartColor(with: fromBackgroundGradient.startColor)
                .replacingEndColor(with: fromBackgroundGradient.endColor)
            if backgroundGradient != startingGradient {
                admission?.markMutationStarted()
                backgroundGradient = startingGradient
            }
            guard
                runtime.reconcileColor(
                    .backgroundGradientStart, of: self, to: startColor,
                    animation: animation, animationsDisabled: animationsDisabled, admission: admission,
                    nativeCheck: nativeCheck),
                admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
            else { return false }
            guard
                runtime.reconcileColor(
                    .backgroundGradientEnd, of: self, to: endColor,
                    animation: animation, animationsDisabled: animationsDisabled, admission: admission,
                    nativeCheck: nativeCheck),
                admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
            else { return false }
        } else if backgroundGradient == nil, fromBackgroundGradient != nil {
            admission?.markMutationStarted()
            runtime.cancelColorAnimation(.backgroundGradientStart, of: self)
            runtime.cancelColorAnimation(.backgroundGradientEnd, of: self)
        }
        return admission?.isCurrent != false && attachment?.isCurrent != false && nativeCheck?.isCurrent != false
    }

    func applyInsertionTransition() {
        let insertion = transition.insertion
        guard insertion.kind != .identity else { return }
        didPlayInsertionTransition = true

        let fullTransaction = animationModifierStorage?.insertionTransaction ?? currentTransaction
        animationModifierStorage?.insertionTransaction = nil
        if let fullTransaction,
            fullTransaction.disablesAnimations || fullTransaction.animation == nil
        {
            return
        }

        // Ambient `withAnimation` first, then the node's own transaction (a
        // control whose state change is its own — a disclosure, a switch —
        // never has an ambient one), then the SwiftUI default.
        let tx: (duration: Double, easing: AnimationEasing)? =
            fullTransaction?.animation.map { ($0.duration, $0.easing) }
            ?? currentAnimationTransaction ?? implicitReconcileAnimation.map { ($0.duration, $0.easing) }
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut
        guard duration > 0 else { return }
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

    @discardableResult
    func applyRemovalTransition() -> Bool {
        let removal = transition.removal
        guard removal.kind != .identity else { return false }

        var fullTransaction =
            currentTransaction
            ?? currentAnimationTransaction.map {
                Transaction(animation: Animation(duration: $0.duration, easing: $0.easing))
            }
        let modifiers = reconcileAnimationModifiers
        for modifier in modifiers.reversed() {
            var transaction = fullTransaction ?? Transaction()
            if modifier.apply(to: &transaction, previous: modifier) {
                fullTransaction = transaction
            }
        }
        if let fullTransaction,
            fullTransaction.disablesAnimations || fullTransaction.animation == nil
        {
            return false
        }

        let tx: (duration: Double, easing: AnimationEasing)? =
            fullTransaction?.animation.map { ($0.duration, $0.easing) }
            ?? currentAnimationTransaction ?? implicitReconcileAnimation.map { ($0.duration, $0.easing) }
        let duration = tx?.duration ?? 0.35
        let easing = tx?.easing ?? .easeInOut
        guard duration > 0 else { return false }
        let now = animationClockNow

        applySingleRemovalTransition(removal, duration: duration, easing: easing, now: now)
        return !animationStates.isEmpty
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
private func gridSpacing(_ spacing: Double) -> Double {
    spacing.isFinite ? sanitizedLayoutCoordinate(spacing) : 0
}

private func gridSpacingTotal(count: Int, spacing: Double) -> Double {
    count > 1 ? sanitizedLayoutCoordinate(Double(count - 1) * spacing) : 0
}

private func gridHorizontalAlignment(
    _ alignment: StackCrossAlignment, isRightToLeft: Bool
) -> StackCrossAlignment {
    guard isRightToLeft else { return alignment }
    switch alignment {
    case .leading: return .trailing
    case .trailing: return .leading
    default: return alignment
    }
}

private func gridAnchor(for alignment: StackCrossAlignment) -> Double {
    switch alignment {
    case .leading, .stretch, .customHorizontal, .customVertical: return 0
    case .center: return 0.5
    case .trailing: return 1
    case .firstTextBaseline, .lastTextBaseline: return 0.8
    }
}

private func gridTrackCrossAlignment(_ alignment: RetainedHorizontalAlignment) -> StackCrossAlignment {
    switch alignment {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
}

@MainActor
private func gridGuideValue(
    for node: ViewNode, axis: StackAxis, alignment: StackCrossAlignment, extent: Double
) -> Double {
    if let guide = stackCrossAlignmentGuide(for: axis, alignment: alignment),
        let value = node.alignmentGuides.last(where: { $0.axis == guide.axis && $0.guide == guide.name })?.value,
        value.isFinite
    {
        return sanitizedLayoutCoordinate(value)
    }
    return stackCrossReference(for: alignment, contentExtent: extent)
}

private func gridRunIndices(
    _ tracks: [GridTrackRun], firstColumn: Int, endColumn: Int
) -> [Int] {
    tracks.indices.filter {
        tracks[$0].firstColumn >= firstColumn && tracks[$0].endColumn <= endColumn
    }
}

private func gridSpanExtent(
    _ tracks: [GridTrackRun], firstColumn: Int, endColumn: Int, spacing: Double
) -> Double {
    let extent = tracks.reduce(0.0) { partial, track in
        guard track.firstColumn >= firstColumn, track.endColumn <= endColumn else { return partial }
        return partial + track.extent
    }
    return sanitizedLayoutExtent(extent + gridSpacingTotal(count: endColumn - firstColumn, spacing: spacing))
}

private func gridTrackOrigin(_ tracks: [GridTrackRun], firstColumn: Int, spacing: Double) -> Double {
    sanitizedLayoutCoordinate(
        tracks.reduce(0.0) { $0 + ($1.endColumn <= firstColumn ? $1.extent : 0) }
            + Double(firstColumn) * spacing)
}

/// Equal increments per logical column are a deterministic interim policy for
/// underdetermined spans, not a claim about SwiftUI's general span solver.
private func gridRequireSpanExtent(
    _ requiredExtent: Double, firstColumn: Int, endColumn: Int, spacing: Double,
    tracks: inout [GridTrackRun], minimum: Bool = false
) {
    let indices = gridRunIndices(tracks, firstColumn: firstColumn, endColumn: endColumn)
    guard !indices.isEmpty, endColumn > firstColumn else { return }
    let current =
        indices.reduce(0.0) {
            $0 + (minimum ? tracks[$1].minimumExtent : tracks[$1].extent)
        } + gridSpacingTotal(count: endColumn - firstColumn, spacing: spacing)
    let deficit = sanitizedLayoutExtent(requiredExtent - current)
    guard deficit > 0 else { return }
    let count = Double(endColumn - firstColumn)
    for index in indices {
        let share = deficit * (Double(tracks[index].endColumn - tracks[index].firstColumn) / count)
        if minimum {
            tracks[index].minimumExtent = sanitizedLayoutExtent(tracks[index].minimumExtent + share)
        } else {
            tracks[index].extent = sanitizedLayoutExtent(tracks[index].extent + share)
        }
    }
}

/// Fits a finite proposal while retaining the same text/declared-minimum floors
/// used by the runtime's stacks. Heterogeneous Grid priority negotiation remains
/// uncharacterized; this proportional-slack policy is intentionally explicit.
private func gridAllocateExtents(
    desired: [Double], minimum: [Double], flexibleWeights: [Double], available: Double
) -> [Double] {
    guard available.isFinite else { return desired }
    let available = sanitizedLayoutExtent(available)
    let desiredTotal = desired.reduce(0, +)
    var result = desired
    if desiredTotal > available {
        let capacity = desired.indices.map { max(0, desired[$0] - minimum[$0]) }
        let totalCapacity = capacity.reduce(0, +)
        if totalCapacity > 0 {
            let reduction = min(desiredTotal - available, totalCapacity)
            for index in result.indices {
                result[index] = max(minimum[index], desired[index] - reduction * (capacity[index] / totalCapacity))
            }
        }
    } else if desiredTotal < available {
        let totalWeight = flexibleWeights.reduce(0, +)
        if totalWeight > 0 {
            let extra = available - desiredTotal
            for index in result.indices {
                result[index] += extra * (flexibleWeights[index] / totalWeight)
            }
        }
    }
    return result.map(sanitizedLayoutExtent)
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

/// Kept alive by receipts, without retaining the runtime or application data.
/// An address alone could identify a different runtime after deallocation.
fileprivate final class RetainedLayoutSettlementIdentity {}

/// Evidence from one completed, bounded retained layout resolution. Only the
/// runtime that produced it can validate it; it is not permission to run layout
/// or a guarantee about callbacks that have not yet executed.
package struct RetainedLayoutSettlementReceipt {
    fileprivate let identity: RetainedLayoutSettlementIdentity
    fileprivate let geometryRevision: UInt64
    fileprivate let resolutionSequence: UInt64
}

/// A host must not turn either failure case into a synchronous retry loop.
/// `unsettled` needs an ordinary layout or active callback/build to finish.
/// `unavailable` means the completed resolution did not establish the proof,
/// or its checked generations are exhausted. Exhaustion is permanent.
package enum RetainedLayoutSettlementStatus {
    case settled(RetainedLayoutSettlementReceipt)
    case unsettled
    case unavailable
}

/// A facade's accepted removal can restore focus only while its private
/// receipt remains current. Nodes stay weak, and the owner is a lightweight
/// registration token rather than the window or runtime.
@MainActor
package final class RetainedPresentationFocusRequest {
    fileprivate let owner: AnyObject
    fileprivate weak var preferred: ViewNode?
    fileprivate weak var underlyingModal: ViewNode?
    fileprivate let expectedFocusRevision: UInt64
    fileprivate var isRevoked = false
    private var isFinished = false
    fileprivate var isCurrent: (@MainActor () -> Bool)?
    fileprivate var resolveBase: (@MainActor () -> ViewNode?)?
    private var didFinish: (@MainActor () -> Void)?

    package init(
        owner: AnyObject,
        preferred: ViewNode?,
        underlyingModal: ViewNode?,
        expectedFocusRevision: UInt64,
        isCurrent: @escaping @MainActor () -> Bool,
        resolveBase: @escaping @MainActor () -> ViewNode?,
        didFinish: (@MainActor () -> Void)? = nil
    ) {
        self.owner = owner
        self.preferred = preferred
        self.underlyingModal = underlyingModal
        self.expectedFocusRevision = expectedFocusRevision
        self.isCurrent = isCurrent
        self.resolveBase = resolveBase
        self.didFinish = didFinish
    }

    /// Closing and adoption first revoke every receipt, before releasing any
    /// application captures that could synchronously reenter the runtime.
    package func revoke() {
        isRevoked = true
    }

    fileprivate func finish() {
        guard !isFinished else { return }
        isFinished = true
        isRevoked = true
        let retired = (isCurrent, resolveBase, didFinish)
        isCurrent = nil
        resolveBase = nil
        didFinish = nil
        withExtendedLifetime(retired) { retired.2?() }
    }
}

/// These identities never retain nodes, callbacks, bindings, or application
/// payloads. An admitted operation keeps the old identity alive until it ends.
@MainActor
package final class RetainedAccessibilityIdentity {}

/// A single synchronous UIA mutation. The runtime owns admission so different
/// adapters for the same runtime cannot reenter one another.
@MainActor
package final class RetainedAccessibilityMutation {
    package private(set) var revision: UInt64 = 0
    package private(set) var isExhausted = false

    fileprivate func recordMutation() {
        guard !isExhausted else { return }
        let next = revision.addingReportingOverflow(1)
        guard !next.overflow else {
            isExhausted = true
            return
        }
        revision = next.partialValue
    }
}

/// The exact physical attachment admitted before a layout query. No retained
/// owner is pinned by the witness; detach/reparent and reattach cannot revive it.
@MainActor
package final class RetainedAccessibilityTarget {
    fileprivate struct Link {
        weak var node: ViewNode?
        let identity: RetainedAccessibilityIdentity
    }

    package private(set) weak var node: ViewNode?
    fileprivate let path: [Link]

    fileprivate init(node: ViewNode, path: [Link]) {
        self.node = node
        self.path = path
    }

    fileprivate func isCurrent(in runtime: RetainedViewRuntime) -> Bool {
        guard node != nil, path.first?.node === node, path.last?.node === runtime.root else { return false }
        for (index, link) in path.enumerated() {
            guard let current = link.node, current.runtime === runtime,
                current.storedAccessibilityAttachmentIdentity === link.identity
            else { return false }
            if index + 1 < path.count {
                guard let parent = path[index + 1].node, current.parent === parent,
                    parent.children.contains(where: { $0 === current })
                else { return false }
            }
        }
        return true
    }
}

/// One already accepted List reveal. The runtime owns this finite native
/// record, not a selection binding, row factory, or public controller. Its
/// endpoints and attachment paths remain weak, and its receipt points back
/// weakly so terminal cancellation has no actor-deinit or reference cycle.
@MainActor
final class RetainedListNavigationRevealContinuation {
    enum State { case unarmed, waiting, consuming, finished }

    private(set) var receipt: RetainedListNavigationReceipt?
    private(set) var state = State.unarmed
    fileprivate weak var target: ViewNode?
    fileprivate weak var container: ViewNode?
    fileprivate let targetAttachment: RetainedAccessibilityTarget
    fileprivate let containerAttachment: RetainedAccessibilityTarget
    fileprivate let containerEpoch: RetainedScrollSourceEpoch?
    fileprivate let axis: ScrollAxis
    fileprivate let pointerSequence: UInt64
    fileprivate var scrollIntent: RetainedLazyListAttachmentIdentity
    fileprivate var expectedOffset: Double
    fileprivate var hasAnimation = false
    fileprivate var animationHasCompleted = false
    fileprivate var focusResolutionSequence: UInt64?
    fileprivate var focusGeometryRevision: UInt64?

    fileprivate init(
        receipt: RetainedListNavigationReceipt, target: ViewNode, container: ViewNode,
        targetAttachment: RetainedAccessibilityTarget, containerAttachment: RetainedAccessibilityTarget,
        axis: ScrollAxis, pointerSequence: UInt64
    ) {
        self.receipt = receipt
        self.target = target
        self.container = container
        self.targetAttachment = targetAttachment
        self.containerAttachment = containerAttachment
        containerEpoch = container.scrollSourceEpoch
        self.axis = axis
        self.pointerSequence = pointerSequence
        scrollIntent = container.captureLazyListScrollIntentIdentity()
        expectedOffset = container.scrollOffset
    }

    fileprivate func arm() -> Bool {
        guard state == .unarmed else { return false }
        state = .waiting
        return true
    }

    fileprivate func take() -> Bool {
        guard state == .waiting else { return false }
        state = .consuming
        return true
    }

    fileprivate func finish() {
        state = .finished
        receipt = nil
    }
}

/// An on-demand logical List item, not an offscreen ViewNode or an authority
/// to run row actions. The token owns only native identity markers; every
/// runtime, adapter, and container reference is weak. A replaced adapter or
/// physical attachment invalidates an escaped action item instead of retargeting
/// it. A native membership marker can separately keep UIA identity metadata
/// across an accepted source continuation; it grants no action authority.
@MainActor
package final class RetainedLazyListAccessibilityItem {
    package let token: RetainedLazyListRowToken
    package private(set) weak var container: ViewNode?
    fileprivate weak var content: ViewNode?
    fileprivate weak var adapter: RetainedLazyListRuntimeAdapter?
    fileprivate weak var runtime: RetainedViewRuntime?
    fileprivate let attachment: RetainedAccessibilityTarget
    fileprivate let identity: RetainedLazyListViewIdentityProof
    fileprivate let containerIdentity: RetainedLazyListViewIdentityProof
    fileprivate let membership: RetainedLazyListMembershipIdentity
    fileprivate let realizationOwner = RetainedLazyListLogicalRealizationOwner()
    fileprivate var realization: RetainedLazyListLogicalRealization?

    fileprivate init(
        token: RetainedLazyListRowToken, container: ViewNode, content: ViewNode,
        adapter: RetainedLazyListRuntimeAdapter, runtime: RetainedViewRuntime,
        attachment: RetainedAccessibilityTarget
    ) {
        self.token = token
        self.container = container
        self.content = content
        self.adapter = adapter
        self.runtime = runtime
        self.attachment = attachment
        identity = content.captureLazyListIdentityProof()
        containerIdentity = container.captureLazyListIdentityProof()
        membership = adapter.logicalMembershipIdentity
    }

    /// Nil is unknown, not a promise that an element has one projected row.
    package var knownLeafCount: Int? {
        guard runtime?.isLazyListAccessibilityItemCurrent(self) == true else { return nil }
        return adapter?.knownLeafCount(for: token)
    }
}

/// One synchronous UIA preparation. Only native anchor corrections may advance
/// its scroll intent; every source, attachment, and input proof stays original.
@MainActor
private final class RetainedLazyListAccessibilityPreparation {
    let token: RetainedLazyListRowToken
    let witness: RetainedLazyListAccessibilityItem
    weak var adapter: RetainedLazyListRuntimeAdapter?
    let descriptor: RetainedLazyListManagedLogicalDescriptorBinding?
    let generation: RetainedLazyListGeneration
    let mutation: RetainedAccessibilityMutation
    weak var scroll: ViewNode?
    let scrollAttachment: RetainedAccessibilityTarget
    let scrollEpoch: RetainedScrollSourceEpoch?
    var scrollIntent: RetainedLazyListAttachmentIdentity
    var reservedAnchorIntent: RetainedLazyListAttachmentIdentity?
    let focusRevision: UInt64
    let pointerSequence: UInt64
    let modal: ObjectIdentifier?
    var isActive = true

    init(
        token: RetainedLazyListRowToken, witness: RetainedLazyListAccessibilityItem,
        adapter: RetainedLazyListRuntimeAdapter, descriptor: RetainedLazyListManagedLogicalDescriptorBinding?,
        generation: RetainedLazyListGeneration, mutation: RetainedAccessibilityMutation,
        scroll: ViewNode, scrollAttachment: RetainedAccessibilityTarget,
        focusRevision: UInt64, pointerSequence: UInt64, modal: ObjectIdentifier?
    ) {
        self.token = token
        self.witness = witness
        self.adapter = adapter
        self.descriptor = descriptor
        self.generation = generation
        self.mutation = mutation
        self.scroll = scroll
        self.scrollAttachment = scrollAttachment
        scrollEpoch = scroll.scrollSourceEpoch
        scrollIntent = scroll.captureLazyListScrollIntentIdentity()
        self.focusRevision = focusRevision
        self.pointerSequence = pointerSequence
        self.modal = modal
    }
}

/// Ready roots are actual retained output. An after-layout caller may use
/// their current pass geometry for programmatic scrolling; focus and UIA must
/// still obtain their separate completed settlement/attachment authority.
@MainActor
package enum RetainedLazyListTargetResolution {
    case ready([ViewNode])
    case pending
    case empty
    case obsolete
    case unsupported
}

@MainActor
private final class RetainedAccessibilityScrollContinuation {
    let mutation: RetainedAccessibilityMutation
    let attachment: RetainedAccessibilityTarget
    weak var target: ViewNode?
    weak var container: ViewNode?
    let axis: ScrollAxis
    var geometryRevision: UInt64
    var expectedOffset: Double
    var expectedRevision: UInt64
    var pointerSequence: UInt64
    var completionRevision: UInt64?

    init(
        mutation: RetainedAccessibilityMutation, attachment: RetainedAccessibilityTarget,
        target: ViewNode, container: ViewNode, axis: ScrollAxis,
        geometryRevision: UInt64, expectedOffset: Double, pointerSequence: UInt64
    ) {
        self.mutation = mutation
        self.attachment = attachment
        self.target = target
        self.container = container
        self.axis = axis
        self.geometryRevision = geometryRevision
        self.expectedOffset = expectedOffset
        self.expectedRevision = mutation.revision
        self.pointerSequence = pointerSequence
    }
}

/// The focus authority never reuses an admitted intent after exhaustion.
/// Kept separate from callback delivery so its boundary is deterministic.
struct RetainedFocusRevision {
    private(set) var value: UInt64
    private(set) var isExhausted = false

    init(value: UInt64 = 0) {
        self.value = value
    }

    mutating func advance() -> UInt64? {
        guard !isExhausted else { return nil }
        let next = value.addingReportingOverflow(1)
        guard !next.overflow else {
            isExhausted = true
            return nil
        }
        value = next.partialValue
        return value
    }
}

@MainActor
private final class RetainedFocusEntry {
    weak var target: ViewNode?
    let beganAttached: Bool
    var reaffirmation: RetainedFocusReaffirmation?

    init(target: ViewNode, beganAttached: Bool) {
        self.target = target
        self.beganAttached = beganAttached
    }
}

private enum RetainedFocusOrigin {
    case ordinary
    case accessibility
    case cleanup
}

private struct RetainedFocusReaffirmation {
    let revision: UInt64
    let origin: RetainedFocusOrigin
    let beganAttached: Bool
    let mutationWitness: UInt64
}

@MainActor
private final class RetainedFocusOperation {
    weak var target: ViewNode?
    let hasTarget: Bool
    var origin: RetainedFocusOrigin
    var beganAttached: Bool
    var revision: UInt64?
    var mutationWitness: UInt64
    let listNavigationReceipt: RetainedListNavigationReceipt?
    var remainingQualificationQueries = 4

    init(
        target: ViewNode?, origin: RetainedFocusOrigin, beganAttached: Bool,
        revision: UInt64?, mutationWitness: UInt64, listNavigationReceipt: RetainedListNavigationReceipt? = nil
    ) {
        self.target = target
        self.hasTarget = target != nil
        self.origin = origin
        self.beganAttached = beganAttached
        self.revision = revision
        self.mutationWitness = mutationWitness
        self.listNavigationReceipt = listNavigationReceipt
    }
}

/// Fixed bounds for the opt-in, two-fixture gallery diagnostic.
package enum RetainedSceneGeometryLimits {
    package static let maxNodes = 128
    package static let maxDepth = 32
    package static let maxPaths = 256
    package static let maxPathElements = 4096
    package static let maxSidecarBytes = 256 * 1024
}

/// Stored values from one painted scene, not a layout-settlement or font-face receipt.
package struct RetainedSceneGeometryDiagnostic: Encodable, Equatable, Sendable {
    package enum Status: String, Encodable, Equatable, Sendable {
        case captured
        case unavailable
    }

    package struct Measurement: Encodable, Equatable, Sendable {
        /// minWidth, maxWidth, minHeight, maxHeight. A null maximum is unbounded.
        package let constraints: [Double?]
        package let unbounded: [Bool]
        package let displayScale: Double
    }

    package struct RequestedTextStyle: Encodable, Equatable, Sendable {
        package let fontFamily: String
        package let nativeFontSize: Double?
        package let scale: Double
        package let weight: String
        package let fontWidth: String
        package let isItalic: Bool
        package let letterSpacing: Double
        package let nativeLetterSpacing: Double?
        package let lineSpacing: Double
        /// top, leading, bottom, trailing, in the node's stored style.
        package let insets: [Double]
        package let maximumNumberOfLines: Int?
        package let minimumNumberOfLines: Int?
        package let minimumScaleFactor: Double
        /// Only the base requested style is copied; spans are not font ownership.
        package let hasSpans: Bool
    }

    package struct Node: Encodable, Equatable, Sendable {
        /// Child-index paths describe this tree only; match variants by unique fixture roles.
        package let path: [Int]
        package let parentPath: [Int]?
        package let text: String?
        package let hasCanvas: Bool
        /// Node-local x, y, width, height. This is not the authored frame or a screen rectangle.
        package let resolvedFrame: [Double]
        package let resolvedContentSize: [Double]
        /// Resolved scroll offset, overshoot, presentation delta.
        package let scrollOffsets: [Double]
        package let declaredFillAxes: [Bool]
        package let inheritedFillAxes: [Bool]
        /// Constrained/explicit-size-adjusted cache, never a new natural-text measurement.
        package let cachedMeasuredSize: [Double]?
        package let measurement: Measurement?
        package let requestedTextStyle: RequestedTextStyle?
        package let subtreeDirtyFlags: UInt8
        package let hasPendingLayoutKey: Bool
    }

    package let status: Status
    package let reason: String?
    package let phase: String?
    package let layoutPassID: UInt64?
    package let contentRevisionBeforePublish: UInt64?
    package let geometryRevision: UInt64?
    package let pendingDirtyFlags: UInt8?
    package let nodes: [Node]

    fileprivate static func unavailable(_ reason: String) -> Self {
        Self(
            status: .unavailable, reason: reason, phase: nil, layoutPassID: nil,
            contentRevisionBeforePublish: nil, geometryRevision: nil, pendingDirtyFlags: nil, nodes: []
        )
    }
}

@MainActor
package final class RetainedSceneGeometryDiagnosticRequest {
    package private(set) var result: RetainedSceneGeometryDiagnostic?

    fileprivate func finish(_ value: RetainedSceneGeometryDiagnostic) {
        // A nested render cannot replace either an earlier failure or a frozen first scene.
        guard result == nil else { return }
        result = value
    }
}

@MainActor
public final class RetainedViewRuntime {
    private static let buttonRepeatInitialDelay = 0.45
    private static let buttonRepeatInterval = 0.08

    public let root: ViewNode
    private var sceneGeometryDiagnosticRequest: RetainedSceneGeometryDiagnosticRequest?

    /// Arms one diagnostic only. It never refreshes layout, a cache, or a font probe.
    package func requestSceneGeometryDiagnostic() -> RetainedSceneGeometryDiagnosticRequest {
        let request = RetainedSceneGeometryDiagnosticRequest()
        if let previous = sceneGeometryDiagnosticRequest {
            previous.finish(.unavailable("overlappingRequest"))
            sceneGeometryDiagnosticRequest = nil
            request.finish(.unavailable("overlappingRequest"))
        } else if isRendering {
            request.finish(.unavailable("requestDuringRender"))
        } else {
            sceneGeometryDiagnosticRequest = request
        }
        return request
    }

    private func sceneGeometryDiagnostic(
        nodes: [RetainedSceneGeometryDiagnostic.Node] = [], reason: String? = nil
    ) -> RetainedSceneGeometryDiagnostic {
        RetainedSceneGeometryDiagnostic(
            status: reason == nil ? .captured : .unavailable, reason: reason,
            phase: "paintedSceneBeforeEndRenderPass", layoutPassID: layoutPassID,
            contentRevisionBeforePublish: contentRevision, geometryRevision: layoutSettlementGeometryRevision,
            pendingDirtyFlags: pendingDirtyFlags.rawValue, nodes: nodes
        )
    }

    /// Copies fields only, at the selected paint. No layout/measurement getter or app closure is called.
    private func captureSceneGeometryDiagnostic() -> RetainedSceneGeometryDiagnostic {
        guard !isLayoutInProgress, !layoutSettlementGenerationsExhausted,
            pendingDirtyFlags.intersection([.layout, .children]).isEmpty
        else {
            return sceneGeometryDiagnostic(reason: "layoutUnavailable")
        }
        var nodes: [RetainedSceneGeometryDiagnostic.Node] = []
        var pending: [(node: ViewNode, path: [Int])] = [(root, [])]
        var visited: Set<ObjectIdentifier> = []
        var stringBytes = 0
        while let entry = pending.popLast() {
            guard entry.path.count <= RetainedSceneGeometryLimits.maxDepth else {
                return sceneGeometryDiagnostic(reason: "depthLimitExceeded")
            }
            guard nodes.count < RetainedSceneGeometryLimits.maxNodes else {
                return sceneGeometryDiagnostic(reason: "nodeLimitExceeded")
            }
            let node = entry.node
            guard visited.insert(ObjectIdentifier(node)).inserted else {
                return sceneGeometryDiagnostic(reason: "invalidStoredGeometry")
            }
            let frame = node.resolvedFrame
            let frameValues = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
            let contentValues = [node.resolvedContentSize.width, node.resolvedContentSize.height]
            let scrollValues = [node.resolvedScrollOffset, node.scrollOvershoot, node.scrollPresentedDelta]
            let cachedSize = node.cachedMeasuredSize.map { [$0.width, $0.height] }
            var finiteValues = frameValues + contentValues + scrollValues + (cachedSize ?? [])
            var measurement: RetainedSceneGeometryDiagnostic.Measurement?
            if let key = node.cachedMeasureKey {
                let constraints = key.constraints
                guard constraints.minWidth.isFinite, constraints.minHeight.isFinite,
                    constraints.maxWidth.isFinite || constraints.maxWidth == .infinity,
                    constraints.maxHeight.isFinite || constraints.maxHeight == .infinity,
                    key.displayScale.isFinite
                else {
                    return sceneGeometryDiagnostic(reason: "invalidStoredGeometry")
                }
                measurement = .init(
                    constraints: [
                        constraints.minWidth, constraints.maxWidth.isFinite ? constraints.maxWidth : nil,
                        constraints.minHeight, constraints.maxHeight.isFinite ? constraints.maxHeight : nil,
                    ],
                    unbounded: [false, constraints.maxWidth == .infinity, false, constraints.maxHeight == .infinity],
                    displayScale: key.displayScale
                )
            }
            var requestedStyle: RetainedSceneGeometryDiagnostic.RequestedTextStyle?
            if node.text != nil {
                let style = node.textStyle
                let insets = [style.insets.top, style.insets.leading, style.insets.bottom, style.insets.trailing]
                let weight: String
                switch style.weight {
                case .regular: weight = "regular"
                case .medium: weight = "medium"
                case .semibold: weight = "semibold"
                case .bold: weight = "bold"
                }
                let fontWidth: String
                switch style.fontWidth {
                case .compressed: fontWidth = "compressed"
                case .condensed: fontWidth = "condensed"
                case .standard: fontWidth = "standard"
                case .expanded: fontWidth = "expanded"
                }
                finiteValues +=
                    [
                        style.scale, style.letterSpacing, style.lineSpacing, style.minimumScaleFactor,
                    ] + insets
                if let value = style.nativeFontSize { finiteValues.append(value) }
                if let value = style.nativeLetterSpacing { finiteValues.append(value) }
                requestedStyle = .init(
                    fontFamily: style.fontFamily, nativeFontSize: style.nativeFontSize, scale: style.scale,
                    weight: weight, fontWidth: fontWidth,
                    isItalic: style.isItalic, letterSpacing: style.letterSpacing,
                    nativeLetterSpacing: style.nativeLetterSpacing, lineSpacing: style.lineSpacing, insets: insets,
                    maximumNumberOfLines: style.maximumNumberOfLines, minimumNumberOfLines: style.minimumNumberOfLines,
                    minimumScaleFactor: style.minimumScaleFactor, hasSpans: style.spans?.isEmpty == false
                )
            }
            guard finiteValues.allSatisfy({ $0.isFinite }) else {
                return sceneGeometryDiagnostic(reason: "invalidStoredGeometry")
            }
            for value in [node.text, requestedStyle?.fontFamily] {
                let count = value?.utf8.count ?? 0
                guard count <= RetainedSceneGeometryLimits.maxSidecarBytes - stringBytes else {
                    return sceneGeometryDiagnostic(reason: "sidecarLimitExceeded")
                }
                stringBytes += count
            }
            nodes.append(
                .init(
                    path: entry.path, parentPath: entry.path.isEmpty ? nil : Array(entry.path.dropLast()),
                    text: node.text, hasCanvas: node.canvasDraw != nil, resolvedFrame: frameValues,
                    resolvedContentSize: contentValues, scrollOffsets: scrollValues,
                    declaredFillAxes: [node.layoutFillAxes.horizontal, node.layoutFillAxes.vertical],
                    inheritedFillAxes: [node.inheritedStackFillAxes.horizontal, node.inheritedStackFillAxes.vertical],
                    cachedMeasuredSize: cachedSize, measurement: measurement, requestedTextStyle: requestedStyle,
                    subtreeDirtyFlags: node.subtreeDirtyFlags.rawValue,
                    hasPendingLayoutKey: node.pendingLayoutKey != nil
                )
            )
            guard node.children.count <= RetainedSceneGeometryLimits.maxNodes - nodes.count - pending.count else {
                return sceneGeometryDiagnostic(reason: "nodeLimitExceeded")
            }
            for index in node.children.indices.reversed() {
                pending.append((node.children[index], entry.path + [index]))
            }
        }
        return sceneGeometryDiagnostic(nodes: nodes)
    }

    private var activeAccessibilityMutation: RetainedAccessibilityMutation?

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
    public var clock: @MainActor () -> Double = { PlatformClock.now() }

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
        !colorAnimations.isEmpty || buttonRepeatState != nil || longPressAttempt != nil || !scrollMomenta.isEmpty
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

    /// Changes for every invalidation or layout entry, including a nested
    /// layout that drains callbacks queued before a selection getter ran.
    package private(set) var textInputReplayScopeRevision: UInt64? = 0

    /// Invalidation staging for the duration of a render pass — see
    /// `beginRenderPass()` / `endRenderPass()`.
    private var isRendering = false
    fileprivate var permitsRenderLifecycleCallbacks = true
    private var isDeliveringRenderLifecycleCallbacks = false
    fileprivate var renderLifecycleRevision: UInt64 = 0
    private var pendingDirtyFlags: DirtyFlags = []
    private var pendingDirtyNodes: [PendingNodeInvalidation] = []
    private var pendingAfterLayoutActions: [String: @MainActor () -> Void] = [:]
    private var pendingAfterLayoutActionKeys: [String] = []
    private var preparedListNavigationReplays: [ObjectIdentifier: PreparedListNavigationReplay] = [:]
    private var retiredPreparedListNavigationRetirements: [@MainActor () -> Void] = []
    private var hasFinishedRenderLifecycleTaskCancellation = false
    private var renderLifecycleTaskCancellationDepth = 0
    private var isDrainingAfterLayoutActions = false
    private var isUpdatingResolvedLayout = false
    private var isResolvingPresentationAction = false
    private var presentationMutationRevision: UInt64 = 0
    private var presentationPrepaintRevision: UInt64?
    private var presentationKeyDispatchDepth = 0
    private var pendingPresentationFocusRequests: [RetainedPresentationFocusRequest] = []
    private var isDrainingPresentationFocusRequests = false
    private weak var currentFocusEntry: RetainedFocusEntry?
    private var isWaitingForPresentationBuildSettlement = false
    private let presentationBuildSettlementOwner = NSObject()
    private var afterLayoutGeometryInvalidations: [WeakViewNodeRef] = []
    private var scrollObserverRegistry: RetainedScrollObserverRegistry?
    private struct PendingPreciseScrollAlignment {
        weak var target: ViewNode?
        weak var coarseTarget: ViewNode?
        weak var container: ViewNode?
        var containerEpoch: RetainedScrollSourceEpoch?
        var anchorX: Double?
        var anchorY: Double?
        var expectedOffset: Double
        var listNavigation: RetainedListNavigationReceipt? = nil
    }
    private var pendingPreciseScrollAlignments: [PendingPreciseScrollAlignment] = []
    private var cachedFrameSnapshot: FramePaintSnapshot?
    private var cachedSceneSnapshot: ScenePaintSnapshot?
    private var cachedFrame: RenderFrame? { cachedFrameSnapshot?.frame }
    private var cachedScene: GPUIScene? { cachedSceneSnapshot?.scene }
    /// The glyph-atlas generation `cachedScene`'s glyph quads were addressed
    /// against, or `nil` when it draws no native glyph. `nil` for a scene
    /// without glyphs rather than "unknown": there is nothing to go stale.
    private var cachedSceneAtlasGeneration: UInt64?
    private var sceneAtlasRefreshPending = false
    internal private(set) var sceneAtlasDeferralCount: UInt64 = 0
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
    private var isResolvingLayoutFrame = false

    /// Whether this runtime has begun at least one retained layout pass.
    /// Clients combine this with `isLayoutInProgress` to distinguish a
    /// genuinely premature request from a missing or disabled scroll target.
    public var hasCompletedLayout: Bool { layoutPassID != 0 }

    /// Geometry-affecting mutations waiting for the next render pass. The
    /// current render keeps its consumed dirty flags until it closes, so
    /// post-layout callbacks must not mistake those flags for stale geometry;
    /// `isLayoutInProgress` separately protects the active traversal. Runtime
    /// animation/momentum wakeups can conservatively raise all global flags
    /// without changing any node geometry, so the retained root must also
    /// carry an actual layout/child invalidation before a request is deferred.
    public var hasPendingLayout: Bool {
        !isRendering
            && !dirtyFlags.intersection([.layout, .children]).isEmpty
            && !root.subtreeDirtyFlags.intersection([.layout, .children]).isEmpty
    }

    // Layout-only queries leave render dirty flags intact. Their settlement
    // evidence therefore has its own checked generations; render lifecycle
    // revisions only advance while lifecycle callbacks are being delivered.
    private var layoutSettlementGeometryRevision: UInt64 = 0
    private var layoutSettlementResolutionSequence: UInt64 = 0
    private var layoutSettlementGenerationsExhausted = false
    private var isResolvingLayoutSettlement = false
    private var lastUnmutatedLayoutPassRevision: UInt64?
    private var layoutSettlementIdentity: RetainedLayoutSettlementIdentity?
    private var recordedLayoutSettlement: RetainedLayoutSettlementStatus = .unsettled

    /// Whether preflight may start a layout query outside Runtime callback
    /// scopes. This reads only owned flags, not the build coordinator. Hosts
    /// must separately require build settlement and retain a successful
    /// receipt; true is not final close authority and false does not request a
    /// retry. Exhausted generations remain `unavailable`, never merely busy.
    package var canPrepareLayoutSettlement: Bool {
        !layoutSettlementGenerationsExhausted
            && !isRendering && !isLayoutInProgress && !isResolvingLayoutFrame && !isResolvingLayoutSettlement
            && !isDeliveringRenderLifecycleCallbacks && !isDrainingAfterLayoutActions
            && scrollObserverRegistry?.isDelivering != true
            && longPressReconciliationDepth == 0 && !isDrainingReconciliationCallbacks
            && pendingLongPressCallbacks.isEmpty && pendingRetainedBuildCompletions.isEmpty
    }

    /// Read-only evidence for the last bounded layout resolution. Callers may
    /// first use `resolvedLayoutFrame(of:)` during preflight, never during final
    /// close validation. This getter does not lay out, walk nodes, call build
    /// leases, invoke application getters, or create a receipt.
    ///
    /// Build settlement remains a separate requirement. This covers ordinary
    /// invalidating retained mutations, not silent replacement of raw layout
    /// callback metadata or native SwiftUI behavior for hidden/deferred readers.
    package var layoutSettlementStatus: RetainedLayoutSettlementStatus {
        guard !layoutSettlementGenerationsExhausted else { return .unavailable }
        guard canReadLayoutSettlement else { return .unsettled }
        // Provider replacement/close revokes its native generation even when
        // no node property changed. A previously issued receipt cannot outlive
        // that source proof; this check never invokes provider metadata.
        guard !hasUnresolvedLazyListLayout else { return .unsettled }
        if case .settled = recordedLayoutSettlement,
            !pendingAfterLayoutActionKeys.isEmpty || !pendingPreciseScrollAlignments.isEmpty
        {
            return .unsettled
        }
        return recordedLayoutSettlement
    }

    /// Validates the original preflight receipt without refreshing its proof.
    /// Only internal identity and scalar comparisons occur here. A later
    /// layout resolution invalidates it even when the resulting bounds match.
    package func isLayoutSettlementReceiptCurrent(_ receipt: RetainedLayoutSettlementReceipt) -> Bool {
        guard case .settled(let current) = layoutSettlementStatus else { return false }
        return current.identity === receipt.identity
            && receipt.geometryRevision == layoutSettlementGeometryRevision
            && receipt.resolutionSequence == layoutSettlementResolutionSequence
            && current.geometryRevision == receipt.geometryRevision
            && current.resolutionSequence == receipt.resolutionSequence
    }

    private var canReadLayoutSettlement: Bool {
        canPrepareLayoutSettlement && !hasActiveRetainedBuild
    }

    private func recordLayoutSettlementInvalidation(_ flags: DirtyFlags) {
        guard !flags.intersection([.layout, .children]).isEmpty else { return }
        guard !layoutSettlementGenerationsExhausted else { return }
        let next = layoutSettlementGeometryRevision.addingReportingOverflow(1)
        guard !next.overflow else {
            layoutSettlementGenerationsExhausted = true
            recordedLayoutSettlement = .unavailable
            return
        }
        layoutSettlementGeometryRevision = next.partialValue
        recordedLayoutSettlement = .unsettled
    }

    private func beginLayoutSettlementResolution() -> UInt64? {
        guard !layoutSettlementGenerationsExhausted else { return nil }
        let next = layoutSettlementResolutionSequence.addingReportingOverflow(1)
        guard !next.overflow else {
            layoutSettlementGenerationsExhausted = true
            recordedLayoutSettlement = .unavailable
            return nil
        }
        layoutSettlementResolutionSequence = next.partialValue
        recordedLayoutSettlement = .unsettled
        lastUnmutatedLayoutPassRevision = nil
        return next.partialValue
    }

    private func finishLayoutSettlementResolution(
        sequence: UInt64?, wasNested: Bool, traversalOverflowCount: Int
    ) {
        recordedLayoutSettlement = .unavailable
        guard !layoutSettlementGenerationsExhausted, let sequence, !wasNested,
            sequence == layoutSettlementResolutionSequence,
            lastUnmutatedLayoutPassRevision == layoutSettlementGeometryRevision,
            ViewNode.traversalDepthOverflowCount == traversalOverflowCount,
            pendingAfterLayoutActionKeys.isEmpty, pendingPreciseScrollAlignments.isEmpty,
            !hasUnresolvedLayoutSettlementReader, !hasUnresolvedLazyListLayout
        else { return }

        let identity = layoutSettlementIdentity ?? RetainedLayoutSettlementIdentity()
        layoutSettlementIdentity = identity
        recordedLayoutSettlement = .settled(
            RetainedLayoutSettlementReceipt(
                identity: identity,
                geometryRevision: layoutSettlementGeometryRevision,
                resolutionSequence: sequence))
    }

    /// Inspect only the candidates reached by the existing final layout pass.
    /// Never call another reader body or a lease getter to test convergence:
    /// an exhausted loop, empty build, or deferred lease must remain unproven.
    private var hasUnresolvedLayoutSettlementReader: Bool {
        for reference in pendingGeometryReaderNodes {
            guard let node = reference.node, node.runtime === self, node.geometryReaderBuild != nil else { continue }
            let slot = node.resolvedFrame.size
            guard slot.width > 0, slot.height > 0 else { continue }
            guard let built = node.geometryReaderBuiltSize,
                abs(built.width - slot.width) < 0.5, abs(built.height - slot.height) < 0.5
            else { return true }
        }
        return false
    }

    // Test seams only move checked generations forward. They cannot reset an
    // exhausted runtime, restore a previous receipt, or wrap a generation.
    internal func exhaustLayoutGeometryGenerationOnNextInvalidationForTesting() {
        layoutSettlementGeometryRevision = .max
        recordedLayoutSettlement = .unsettled
    }

    internal func exhaustLayoutResolutionGenerationOnNextQueryForTesting() {
        layoutSettlementResolutionSequence = .max
        recordedLayoutSettlement = .unsettled
    }

    /// The `GeometryReader` nodes the pass that just ran walked past, in
    /// traversal order. Refilled by every pass and drained by
    /// `resolveGeometryReaderSlots`; empty for the overwhelming majority of
    /// trees, which is what keeps the convergence loop free when no reader
    /// is on screen.
    private var pendingGeometryReaderNodes: [WeakViewNodeRef] = []

    private struct LazyListRegistration {
        weak var node: ViewNode?
        weak var adapter: RetainedLazyListRuntimeAdapter?
    }

    fileprivate struct LazyListLayoutVisit {
        weak var node: ViewNode?
        weak var adapter: RetainedLazyListRuntimeAdapter?
        weak var scrollContainer: ViewNode?
        let attachment: RetainedLazyListAttachmentProof
        let scrollAttachment: RetainedLazyListAttachmentProof?
        let viewport: RetainedLazyListRuntimeAdapter.Viewport?
        let contentOriginY: Double
        let expectedScrollOffset: Double
        let scrollEpoch: RetainedScrollSourceEpoch?
        let passID: UInt64
        let geometryRevision: UInt64
    }

    private struct LazyListLeafMeasurement {
        let token: RetainedLazyListRowToken
        let leafIndex: Int
        weak var node: ViewNode?
        let attachment: RetainedLazyListAttachmentProof
    }

    /// Only an already admitted anchor may normalize its stored offset after
    /// the next full layout computes the enclosing range. This is a weak,
    /// native record per affected scroll container, never a logical-row cache.
    private struct LazyListAnchorClamp {
        weak var node: ViewNode?
        weak var adapter: RetainedLazyListRuntimeAdapter?
        weak var scroll: ViewNode?
        let adapterProof: RetainedLazyListRuntimeAdapter.LayoutProof
        let layoutProofs: [RetainedLazyListLocalLayoutProof]
        let scrollIntent: RetainedLazyListAttachmentIdentity
        let scrollEpoch: RetainedScrollSourceEpoch?
        let context: RetainedLazyListMeasurementContext
        let contentOriginY: Double
        let requestedOffset: Double
        let issuingPass: UInt64
    }

    // These registries contain actual retained attachments only. Metadata and
    // logical rows never allocate entries, and all node references are weak.
    let lazyListLogicalHostLifetime = RetainedLazyListLogicalHostLifetime()
    private var lazyListRegistrations: [ObjectIdentifier: LazyListRegistration] = [:]
    private var pendingLazyListVisits: [ObjectIdentifier: LazyListLayoutVisit] = [:]
    private var pendingLazyListOrder: [ObjectIdentifier] = []
    private var pendingLazyListMeasurements: [ObjectIdentifier: [LazyListLeafMeasurement]] = [:]
    private var pendingLazyListAnchorClamps: [ObjectIdentifier: LazyListAnchorClamp] = [:]
    private var lazyListAnchorNeedsLayout = false
    private var lazyListUnsupportedThisPass = false
    private var lazyListResolutionBudget: RetainedLazyListWorkBudget?
    private var lazyListResolutionDepth = 0
    private var lazyListScrollWorkDepth = 0
    private var isProbingLazyListScrollTarget = false
    private var lazyListScrollSearchNeedsMoreWork = false
    private var isResolvingLazyListLogicalTarget = false
    private weak var lazyListLogicalRevealScroll: ViewNode?
    private weak var lazyListAccessibilityPreparation: RetainedLazyListAccessibilityPreparation?
    fileprivate var hasLazyListLayoutScope: Bool { lazyListResolutionBudget != nil }
    private var lazyListElementLimit = 128
    private var lazyListRoundLimit = 4
    internal private(set) var lazyListResolveCount = 0
    internal private(set) var lastLazyListWorkCompletion: RetainedLazyListWorkBudget.Completion = .complete
    internal private(set) var lastLazyListConsumedElements = 0
    internal private(set) var lastLazyListConsumedRounds = 0

    /// Test/internal configuration only. A callback cannot expand the active
    /// scope's budget. No continuation or retry is scheduled on exhaustion.
    @discardableResult
    package func configureLazyListResolutionBudget(elementLimit: Int, roundLimit: Int) -> Bool {
        guard !isUpdatingResolvedLayout, !isResolvingLazyListLogicalTarget,
            lazyListScrollWorkDepth == 0, !isProbingLazyListScrollTarget,
            lazyListResolutionDepth == 0, elementLimit >= 0, roundLimit >= 0
        else {
            return false
        }
        lazyListElementLimit = elementLimit
        lazyListRoundLimit = roundLimit
        invalidate(.layout)
        return true
    }

    private var hasUnresolvedLazyListLayout: Bool {
        if !pendingLazyListAnchorClamps.isEmpty || lazyListAnchorNeedsLayout { return true }
        guard !lazyListRegistrations.isEmpty else { return false }
        if lazyListUnsupportedThisPass || hasActiveRetainedBuild { return true }
        for registration in lazyListRegistrations.values {
            guard let node = registration.node, let adapter = registration.adapter,
                node.runtime === self, node.retainedLazyListAdapter === adapter
            else { continue }
            if !adapter.ownsAttachment(node) || adapter.hasUnresolvedWork { return true }
        }
        return false
    }

    fileprivate func registerLazyListContainer(_ node: ViewNode) {
        guard node.runtime === self, let adapter = node.retainedLazyListAdapter,
            !node.isRetiringLazyListAttachment, ownsLazyListAttachment(node)
        else { return }
        lazyListRegistrations[ObjectIdentifier(node)] = LazyListRegistration(node: node, adapter: adapter)
        if !adapter.claimAttachment(to: node) { lazyListUnsupportedThisPass = true }
        if lazyListResolutionDepth > 0 { ensureLazyListResolutionBudget() }
    }

    /// Legacy addChild publishes membership after assigning runtime. Finish
    /// registration only once those nodes are actually in the retained tree;
    /// the checked path already publishes the whole subtree before attaching.
    fileprivate func registerLazyListAttachments(in root: ViewNode) {
        var work: [(ViewNode, Int)] = [(root, 0)]
        while let (node, depth) = work.popLast() {
            guard depth < ViewNode.maximumTraversalDepth, node.runtime === self else { continue }
            if node.retainedLazyListAdapter != nil { registerLazyListContainer(node) }
            for child in node.children { work.append((child, depth + 1)) }
        }
    }

    /// Revocation/registry removal is native and does not release mapped rows.
    /// The retiring attachment holds the weak claim through its cleanup scope.
    fileprivate func unregisterLazyListContainer(_ node: ViewNode, revokingAdapter: Bool = true) {
        lazyListRegistrations.removeValue(forKey: ObjectIdentifier(node))
        pendingLazyListAnchorClamps = pendingLazyListAnchorClamps.filter { _, correction in
            correction.node != nil && correction.scroll != nil
                && correction.node !== node && correction.scroll !== node
        }
        if revokingAdapter { node.retainedLazyListAdapter?.revokePendingCandidate() }
    }

    private func ensureLazyListResolutionBudget() {
        guard lazyListResolutionBudget == nil, !lazyListRegistrations.isEmpty else { return }
        lazyListScrollSearchNeedsMoreWork = false
        lazyListResolutionBudget = RetainedLazyListWorkBudget(
            elementLimit: lazyListElementLimit, roundLimit: lazyListRoundLimit)
    }

    private func finishLazyListResolutionBudgetIfIdle() {
        guard lazyListResolutionDepth == 0, lazyListScrollWorkDepth == 0,
            !isResolvingLazyListLogicalTarget
        else { return }
        if let budget = lazyListResolutionBudget {
            lastLazyListConsumedElements = lazyListElementLimit - budget.remainingElements
            lastLazyListConsumedRounds = lazyListRoundLimit - budget.remainingRounds
            lastLazyListWorkCompletion = budget.completion(
                hasPendingWork: hasUnresolvedLazyListLayout || hasUnresolvedLayoutSettlementReader
                    || lazyListScrollSearchNeedsMoreWork)
        } else {
            lastLazyListConsumedElements = 0
            lastLazyListConsumedRounds = 0
            lastLazyListWorkCompletion = .complete
        }
        lazyListResolutionBudget = nil
        lazyListScrollSearchNeedsMoreWork = false
    }

    fileprivate func ownsLazyListAttachment(_ node: ViewNode) -> Bool {
        guard permitsRetainedActionInvocation, node.runtime === self,
            !node.isRetiringLazyListAttachment
        else { return false }
        var child = node
        var depth = 0
        while child !== root, depth < ViewNode.maximumTraversalDepth {
            guard let parent = child.parent, parent.runtime === self,
                parent.children.contains(where: { $0 === child }), !parent.isRetiringLazyListAttachment
            else { return false }
            child = parent
            depth += 1
        }
        return child === root
    }

    fileprivate func recordLazyListLayoutCandidate(_ node: ViewNode) {
        guard let adapter = node.retainedLazyListAdapter else { return }
        let key = ObjectIdentifier(node)
        let context = node.lazyListViewport(displayScale: displayScale)
        if pendingLazyListVisits[key] == nil { pendingLazyListOrder.append(key) }
        pendingLazyListVisits[key] = LazyListLayoutVisit(
            node: node, adapter: adapter, scrollContainer: context?.1,
            attachment: node.captureLazyListAttachmentProof(),
            scrollAttachment: context?.1.captureLazyListAttachmentProof(), viewport: context?.0,
            contentOriginY: context?.2 ?? 0, expectedScrollOffset: context?.1.scrollOffset ?? 0,
            scrollEpoch: context?.1.scrollSourceEpoch,
            passID: layoutPassID, geometryRevision: layoutSettlementGeometryRevision)
        if context == nil || lazyListRegistrations[key]?.adapter !== adapter || !adapter.ownsAttachment(node) {
            lazyListUnsupportedThisPass = true
        }
    }

    fileprivate func lazyListVisitIsCurrent(_ visit: LazyListLayoutVisit) -> Bool {
        guard visit.passID == layoutPassID, visit.geometryRevision == layoutSettlementGeometryRevision,
            visit.attachment.isCurrent, visit.scrollAttachment?.isCurrent == true,
            let node = visit.node, let adapter = visit.adapter, let scroll = visit.scrollContainer,
            let viewport = visit.viewport, ownsLazyListAttachment(node), ownsLazyListAttachment(scroll),
            node.retainedLazyListAdapter === adapter, adapter.ownsAttachment(node),
            lazyListRegistrations[ObjectIdentifier(node)]?.adapter === adapter,
            scroll.scrollOffset == visit.expectedScrollOffset, scroll.scrollSourceEpoch == visit.scrollEpoch,
            let current = node.lazyListViewport(displayScale: displayScale), current.0 == viewport,
            current.1 === scroll, current.2 == visit.contentOriginY
        else { return false }
        return true
    }

    fileprivate func lazyListLayoutPlan(
        for node: ViewNode
    ) -> (LazyListLayoutVisit, RetainedLazyListRuntimeAdapter.LayoutPlan)? {
        guard let visit = pendingLazyListVisits[ObjectIdentifier(node)], lazyListVisitIsCurrent(visit),
            let viewport = visit.viewport, let adapter = visit.adapter
        else {
            lazyListUnsupportedThisPass = true
            return nil
        }
        guard adapter.updateProtectedRoots(protectedLazyListRoots(in: node)) else {
            lazyListUnsupportedThisPass = true
            return nil
        }
        return (visit, adapter.layoutPlan(viewport: viewport))
    }

    fileprivate func rejectLazyListLayoutVisit() { lazyListUnsupportedThisPass = true }

    fileprivate func recordLazyListLeafMeasurement(
        _ placement: RetainedLazyListRuntimeAdapter.Placement,
        attachment: RetainedLazyListAttachmentProof, container: ViewNode
    ) {
        pendingLazyListMeasurements[ObjectIdentifier(container), default: []].append(
            LazyListLeafMeasurement(
                token: placement.token, leafIndex: placement.leafIndex,
                node: placement.node, attachment: attachment))
    }

    /// Leaf callbacks and child layout have finished before their scalar
    /// heights reach the index. A reentrant pass, detach, context change, or
    /// mutation anywhere in the pass leaves this batch explicitly unproven.
    private func recordResolvedLazyListMeasurements() -> Bool {
        var changed = false
        for key in pendingLazyListOrder {
            guard let visit = pendingLazyListVisits[key], lazyListVisitIsCurrent(visit),
                let node = visit.node, let adapter = visit.adapter, let viewport = visit.viewport
            else {
                lazyListUnsupportedThisPass = true
                continue
            }
            let records = pendingLazyListMeasurements[key, default: []]
            var measurements: [RetainedLazyListRuntimeAdapter.Measurement] = []
            var valid = true
            for record in records {
                guard let leaf = record.node, record.attachment.isCurrent, leaf.parent === node,
                    leaf.runtime === self, leaf.isHidden || leaf.lastLayoutVisitPassID == visit.passID,
                    leaf.resolvedFrame.height.isFinite, leaf.resolvedFrame.height >= 0
                else {
                    valid = false
                    break
                }
                measurements.append(
                    RetainedLazyListRuntimeAdapter.Measurement(
                        token: record.token, leafIndex: record.leafIndex, node: leaf,
                        extent: leaf.isHidden ? 0 : leaf.resolvedFrame.height))
            }
            guard valid, lazyListVisitIsCurrent(visit) else {
                lazyListUnsupportedThisPass = true
                continue
            }
            let anchor = lazyListAnchor(adapter: adapter, viewport: viewport)
            guard let update = adapter.recordMeasurements(measurements, viewport: viewport),
                lazyListVisitIsCurrent(visit)
            else { continue }
            guard publishLazyListRowChrome(records, in: node, adapter: adapter, visit: visit) else {
                lazyListUnsupportedThisPass = true
                continue
            }
            if update.extentChanged {
                // Invalidate the old geometry before capturing this owned
                // anchor correction. Active input, authored anchors, and
                // explicit requests retain priority over its later range clamp.
                node.markDirty(.layout)
                invalidate(.layout, from: node)
                if let anchor { _ = applyLazyListAnchor(anchor, adapter: adapter, visit: visit) }
                changed = true
            }
        }
        return changed
    }

    /// Only accepted, fully measured actual roots receive framework chrome.
    /// This runs after leaf callbacks and outside layout traversal. Unknown
    /// preceding output contributes estimated parity, never a prefix scan.
    private func publishLazyListRowChrome(
        _ records: [LazyListLeafMeasurement], in container: ViewNode,
        adapter: RetainedLazyListRuntimeAdapter, visit: LazyListLayoutVisit
    ) -> Bool {
        guard records.contains(where: { $0.node?.retainedLazyListRowChrome != nil }) else { return true }
        guard let proof = adapter.captureLayoutProof(), proof.isCurrent, lazyListVisitIsCurrent(visit) else {
            return false
        }
        let groups = Dictionary(grouping: records, by: \.token)
        for (token, group) in groups {
            guard proof.isCurrent, lazyListVisitIsCurrent(visit) else { return false }
            guard adapter.knownLeafCount(for: token) == group.count,
                let ordinal = adapter.projectedRowOrdinalBefore(token)
            else { continue }
            var isOdd = ordinal.parity
            for record in group.sorted(by: { $0.leafIndex < $1.leafIndex }) {
                guard let node = record.node, record.attachment.isCurrent,
                    node.parent === container, node.runtime === self,
                    container.children.contains(where: { $0 === node }),
                    proof.isCurrent, lazyListVisitIsCurrent(visit)
                else { return false }
                guard node.retainedLazyListGap == nil else { continue }
                node.publishRetainedLazyListRowChrome(isOdd: isOdd, hasUnknownPrefix: ordinal.hasUnknownPrefix)
                isOdd.toggle()
            }
        }
        return proof.isCurrent && lazyListVisitIsCurrent(visit)
    }

    private func applyLazyListAnchor(
        _ anchor: RetainedLazyListAnchor, adapter: RetainedLazyListRuntimeAdapter,
        visit: LazyListLayoutVisit
    ) -> Bool {
        guard visit.passID == layoutPassID,
            let node = visit.node, let scroll = visit.scrollContainer, let viewport = visit.viewport,
            visit.attachment.isCurrent, visit.scrollAttachment?.isCurrent == true,
            ownsLazyListAttachment(node), ownsLazyListAttachment(scroll), adapter.ownsAttachment(node),
            node.retainedLazyListAdapter === adapter, lazyListAnchorMayControl(scroll),
            scroll.scrollOffset == visit.expectedScrollOffset, scroll.scrollSourceEpoch == visit.scrollEpoch,
            let adapterProof = adapter.captureLayoutProof(),
            let local = adapter.resolveAnchor(anchor, viewportExtent: 0)
        else { return false }
        let requested = local + visit.contentOriginY
        guard requested.isFinite, requested >= 0,
            permitsLazyListAnchorDuringAccessibilityPreparation(in: scroll, for: node, adapter: adapter)
        else { return false }
        // No active tween needs cancellation, but invalidation can still
        // release a displaced scheduler capture. A scoped UIA correction
        // checks its reserved intent after the complete shared setter.
        // The next layout pass clamps against the enclosing total extent.
        // Keep this intent even when the local anchor did not move: a shorter
        // last row can still reduce that enclosing range underneath it.
        let changed = requested != scroll.scrollOffset
        if changed {
            guard setLazyListAnchorOffset(requested, in: scroll, for: node, adapter: adapter) else { return false }
        }
        var proofs: [RetainedLazyListLocalLayoutProof] = []
        var ancestor: ViewNode? = node
        while let current = ancestor, proofs.count < ViewNode.maximumTraversalDepth {
            proofs.append(current.captureLazyListLocalLayoutProof())
            if current === root { break }
            ancestor = current.parent
        }
        pendingLazyListAnchorClamps[ObjectIdentifier(scroll)] = LazyListAnchorClamp(
            node: node, adapter: adapter, scroll: scroll, adapterProof: adapterProof,
            layoutProofs: proofs, scrollIntent: scroll.captureLazyListScrollIntentIdentity(),
            scrollEpoch: scroll.scrollSourceEpoch, context: viewport.context,
            contentOriginY: visit.contentOriginY, requestedOffset: requested, issuingPass: layoutPassID)
        return changed
    }

    private func lazyListAnchorMayControl(_ scroll: ViewNode) -> Bool {
        lazyListLogicalRevealScroll !== scroll
            && !(pendingListNavigationReveal?.container === scroll
                && pendingListNavigationReveal.map(isListNavigationRevealCurrent) == true)
            && scroll.scrollAxis == .vertical && scroll.scrollPresentedDelta == 0 && scroll.scrollOvershoot == 0
            && scrollPresentedTweens[ObjectIdentifier(scroll)] == nil
            && scrollMomenta[ObjectIdentifier(scroll)] == nil
            && scrollDragState?.node !== scroll && activeScrollIndicatorNode !== scroll
            && !pendingPreciseScrollAlignments.contains(where: { $0.container === scroll })
            && scroll.initialScrollAnchor == nil && scroll.scrollSizeChangeAnchor == nil
    }

    private func normalizeLazyListAnchorOffsets() -> Bool {
        guard !pendingLazyListAnchorClamps.isEmpty else { return false }
        let corrections = pendingLazyListAnchorClamps
        pendingLazyListAnchorClamps = [:]
        var changed = false
        for correction in corrections.values {
            guard correction.issuingPass != layoutPassID, correction.adapterProof.isCurrent,
                correction.layoutProofs.allSatisfy(\.isCurrent),
                let node = correction.node, let adapter = correction.adapter, let scroll = correction.scroll,
                ownsLazyListAttachment(node), ownsLazyListAttachment(scroll), adapter.ownsAttachment(node),
                node.retainedLazyListAdapter === adapter, lazyListAnchorMayControl(scroll),
                node.lastLayoutVisitPassID == layoutPassID, scroll.lastLayoutVisitPassID == layoutPassID,
                scroll.lazyListScrollIntentIdentity === correction.scrollIntent,
                scroll.scrollSourceEpoch == correction.scrollEpoch, scroll.scrollOffset == correction.requestedOffset,
                let current = node.lazyListViewport(displayScale: displayScale),
                current.0.context == correction.context, current.1 === scroll,
                current.2 == correction.contentOriginY
            else { continue }
            let normalized = scroll.clampedScrollOffset(for: correction.requestedOffset)
            guard normalized != scroll.scrollOffset else { continue }
            // The ownership policy above excludes the callbackful cancellation
            // path. A following bounded pass must prove the corrected viewport.
            guard setLazyListAnchorOffset(normalized, in: scroll, for: node, adapter: adapter) else { continue }
            changed = true
        }
        return changed
    }

    private func lazyListAnchor(
        adapter: RetainedLazyListRuntimeAdapter, viewport: RetainedLazyListRuntimeAdapter.Viewport
    ) -> RetainedLazyListAnchor? {
        // A list cannot claim the leading edge while it lies in an earlier
        // header or later sibling. Index capture clamps such signed offsets;
        // adding the list origin back would otherwise scroll that content away.
        guard viewport.offset >= 0, viewport.offset < adapter.contentExtent else { return nil }
        return adapter.captureAnchor(at: viewport.offset)
    }

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
    /// Every admitted focus intent counts, including a request for the target
    /// that already has focus. A deferred restoration must not override it.
    private var focusRevision = RetainedFocusRevision()
    package var presentationFocusRevision: UInt64 { focusRevision.value }
    /// Accessibility integration hook (UI Automation, Phase 2): called on the
    /// main actor after the focused node changes. Additive only — no effect
    /// on focus behavior itself.
    public var onAccessibilityFocusChanged: ((ViewNode?) -> Void)?
    private weak var hoveredScrollIndicatorNode: ViewNode?
    private weak var activeScrollIndicatorNode: ViewNode?
    private var colorAnimations: [ColorAnimationKey: ViewColorAnimation] = [:]
    private var buttonRepeatState: ButtonRepeatState?
    private var longPressAttempt: LongPressAttempt?
    private var longPressReconciliationDepth = 0
    private var pendingLongPressCallbacks: [@MainActor () -> Void] = []
    private var isDrainingReconciliationCallbacks = false
    private var pendingRetainedBuildCompletions: [@MainActor () -> Void] = []
    private var retainedBuildCoordinatorStorage: RetainedBuildCoordinator?

    var hasActiveRetainedBuild: Bool { retainedBuildCoordinatorStorage?.isBuilding == true }

    var retainedBuildCoordinator: RetainedBuildCoordinator {
        if let retainedBuildCoordinatorStorage { return retainedBuildCoordinatorStorage }
        let coordinator = RetainedBuildCoordinator(
            onBuildStarted: { [weak self] in
                // A completed build can replace retained behavior without a
                // geometry change. Retire close evidence, not layout caches or
                // render flags; the next ordinary query can establish new proof.
                self?.recordLayoutSettlementInvalidation(.layout)
            },
            retainedCallbacksAreSettled: { [weak self] in
                guard let self else { return false }
                return self.longPressReconciliationDepth == 0
                    && !self.isDrainingReconciliationCallbacks
                    && self.pendingLongPressCallbacks.isEmpty
                    && self.pendingRetainedBuildCompletions.isEmpty
            },
            layoutCallbacksAreAvailable: { [weak self] in
                guard let self else { return false }
                return self.canPrepareLayoutSettlement && !self.isResolvingLazyListLogicalTarget
                    && !self.isProbingLazyListScrollTarget
            })
        retainedBuildCoordinatorStorage = coordinator
        return coordinator
    }
    /// Callback code may synchronously begin another pointer sequence. Older
    /// release/cancellation work must not clear that new sequence's state.
    private var pointerSequence: UInt64 = 0
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
        // Keep the physical spring displacement separate from its 80pt
        // presentation cap; clipping the state each frame changes its path.
        var rubberBandDisplacement: Double? = nil
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
    // edge. The slightly overdamped spring returns without oscillating.
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
        guard node.acceptsScrollInput, refusedOffsetDelta != 0 else {
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
        state.rubberBandDisplacement = node.scrollOvershoot
        scrollMomenta[key] = state
        invalidate(.paint)
    }

    // Keyboard scroll (PageUp/Down, Home, End, arrow keys) jumps `scrollOffset`
    // to its new target synchronously so external observers see the value
    // immediately, but visually we keep a lag delta that tweens to 0 over
    // ~220ms with ease-out so the viewport feels animated.
    // Programmatic requests share that presentation path with their authored
    // duration and easing. Their origin keeps input disabling from cancelling
    // an application-requested animation.
    fileprivate struct ScrollPresentedTween {
        enum Origin {
            case keyboard
            case programmatic(AnimationEasing)

            var isProgrammatic: Bool {
                if case .programmatic = self { return true }
                return false
            }
        }

        weak var node: ViewNode?
        weak var target: ViewNode?
        var startDelta: Double
        var startTime: Double
        var lastTime: Double
        var duration: Double
        var targetOffset: Double
        var scrollLimit: Double
        var origin: Origin
        var listNavigationReveal: RetainedListNavigationRevealContinuation? = nil
    }
    private var scrollPresentedTweens: [ObjectIdentifier: ScrollPresentedTween] = [:]
    private weak var latestListNavigationAction: RetainedListNavigationReceipt?
    private var pendingListNavigationReveal: RetainedListNavigationRevealContinuation?
    private var consumingListNavigationReveal: RetainedListNavigationRevealContinuation?
    private var isDrainingListNavigationReveal = false
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

    /// Layout-only preparation for an isolated Canvas symbol. In particular,
    /// this must not call renderScene/ScenePainter or begin a glyph-atlas frame:
    /// symbols can be resolved while their owning Canvas is already painting.
    internal func prepareCanvasSymbolLayout(content: ViewNode) -> Size? {
        if content !== root { root.setChildren([content]) }
        // Declaration lookup may remove tagged siblings carrying transitions.
        // Those discarded declarations are not a part of the resolved symbol.
        transitionOverlays.removeAll()
        let size = content.intrinsicContentSize()
        guard CanvasSymbolSource.pixelSize(for: size, displayScale: displayScale) != nil else { return nil }
        root.frame = Rect(origin: .zero, size: size)
        content.frame = Rect(origin: .zero, size: size)
        updateResolvedLayout()
        transitionOverlays.removeAll()
        return size
    }

    public func renderFrame(at timestamp: Double = 0) -> RenderFrame {
        if let request = sceneGeometryDiagnosticRequest {
            request.finish(.unavailable(isRendering ? "nestedRender" : "frameRender"))
            sceneGeometryDiagnosticRequest = nil
        }
        if scrollObserverRegistry?.isDelivering == true, let cachedFrame {
            return cachedFrame
        }
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
        deliverRenderLifecycleCallbacks(ownsRenderPass: ownsRenderPass)

        let previousFrame = cachedFrameSnapshot
        let snapshotIdentity = PaintSnapshotIdentity()
        var commands: [RenderCommand] = []
        var replayCount = 0
        var deferredDrawReplayCount = 0
        root.appendCommands(
            into: &commands,
            parentOrigin: .zero,
            inheritedClip: nil,
            previousRenderedFrame: previousFrame,
            snapshotIdentity: snapshotIdentity,
            displayScale: displayScale,
            replayCount: &replayCount
        )
        appendDeferredDraws(
            into: &commands,
            previousFrame: previousFrame,
            snapshotIdentity: snapshotIdentity,
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
                snapshotIdentity: snapshotIdentity,
                displayScale: displayScale,
                replayCount: &overlayReplayCount
            )
            replayCount += overlayReplayCount
        }

        let frame = RenderFrame(clearColor: clearColor, commands: commands)
        lastFrameReplayCount = replayCount
        lastDeferredDrawFrameReplayCount = deferredDrawReplayCount
        lastDeferredDrawSceneReplayCount = 0
        cachedFrameSnapshot = FramePaintSnapshot(frame: frame, identity: snapshotIdentity)
        cachedSceneSnapshot = nil
        cachedSceneAtlasGeneration = nil
        contentRevision &+= 1
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return frame
    }

    /// Render the current view tree as a GPUIScene for batch rendering.
    public func renderScene(at timestamp: Double = 0) -> GPUIScene {
        let geometryRequest = sceneGeometryDiagnosticRequest
        if isRendering, let geometryRequest {
            geometryRequest.finish(.unavailable("nestedRender"))
            sceneGeometryDiagnosticRequest = nil
        }
        defer {
            if let geometryRequest {
                geometryRequest.finish(.unavailable("noFreshScene"))
                if sceneGeometryDiagnosticRequest === geometryRequest {
                    sceneGeometryDiagnosticRequest = nil
                }
            }
        }
        discardSceneWithStaleAtlas()
        if scrollObserverRegistry?.isDelivering == true {
            if let cachedScene { return shippable(cachedScene) }
            if sceneAtlasRefreshPending {
                // A callback cannot re-enter layout to repair stale UVs. Ship
                // an explicit empty snapshot for this inspection; the normal
                // render resumes after delivery and reconstructs the source.
                sceneAtlasDeferralCount &+= 1
                if sceneAtlasDeferralCount == 1 {
                    FileHandle.standardError.write(
                        Data(
                            "[SwiftWindowsUI] Scene snapshot deferred during scroll observation after glyph-atlas recycling.\n"
                                .utf8))
                }
                var deferredScene = GPUIScene(clearColor: clearColor)
                deferredScene.finish()
                return deferredScene
            }
        }
        // WS-14's stale-UV rule, applied to the one holder that had escaped it.
        // `shippable` staples the *current* shared atlas onto a scene whose
        // glyph quads were addressed against an earlier one, and the atlas is
        // process-wide: a clean, unchanged window that never repaints would
        // have shipped pre-recovery UVs against a post-recovery atlas forever,
        // because a clear triggered by some *other* window leaves nothing in
        // this runtime dirty. Dropping the cache forces a real paint — which
        // also drops the replay source, since replayed primitives carry the
        // same dead UVs.
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
        let phaseStartedAt = collectsPhaseTimings ? PlatformClock.now() : 0
        updateResolvedLayout()
        applyMatchedGeometryAnimations()
        deliverRenderLifecycleCallbacks(ownsRenderPass: ownsRenderPass)
        // Another window can recycle the process atlas during a layout or
        // observation callback, after entry but before replay selection.
        discardSceneWithStaleAtlas()
        let layoutEndedAt = collectsPhaseTimings ? PlatformClock.now() : 0

        let previousScene = cachedSceneSnapshot
        var replayCount = 0
        var deferredDrawReplayCount = 0
        var deferredDraws = prepaintState.deferredDraws
        let paintedSnapshot = ScenePainter.paintSnapshot(
            root: root,
            clearColor: clearColor,
            surfaceSize: root.frame.size,
            displayScale: displayScale,
            textSystem: textSystem,
            previousSnapshot: previousScene,
            deferredDraws: &deferredDraws,
            replayCount: &replayCount,
            deferredReplayCount: &deferredDrawReplayCount,
            overlays: transitionOverlays
        )
        let scene = paintedSnapshot.scene
        if let geometryRequest {
            if geometryRequest.result == nil {
                geometryRequest.finish(captureSceneGeometryDiagnostic())
            }
            // Clear before endRenderPass delivers callbacks; the first-scene result is now frozen.
            if sceneGeometryDiagnosticRequest === geometryRequest {
                sceneGeometryDiagnosticRequest = nil
            }
        }
        prepaintState.deferredDraws = deferredDraws
        if collectsPhaseTimings {
            let paintEndedAt = PlatformClock.now()
            lastLayoutSeconds = layoutEndedAt - phaseStartedAt
            lastPaintSeconds = paintEndedAt - layoutEndedAt
        }

        // The retained copy drops the atlases on purpose: it outlives the
        // frame, and a snapshot holding the atlas `Data` across frames turns
        // the next glyph write into a copy of the whole 2048² buffer. Child
        // scene sources are replay holders too; detach their references and
        // include their native UVs in generation invalidation.
        var cachedSceneCopy = scene
        let cachesNativeGlyphs = ScenePainter.detachGlyphAtlasesForReplay(from: &cachedSceneCopy)
        sceneRebuildCount &+= 1
        contentRevision &+= 1
        lastSceneReplayCount = replayCount
        lastDeferredDrawSceneReplayCount = deferredDrawReplayCount
        lastDeferredDrawFrameReplayCount = 0
        lastScenePaintMetrics = scene.paintMetrics
        cachedSceneSnapshot = ScenePaintSnapshot(scene: cachedSceneCopy, identity: paintedSnapshot.identity)
        cachedSceneAtlasGeneration = cachesNativeGlyphs ? NativeGlyphAtlas.shared.atlasGeneration : nil
        sceneAtlasRefreshPending = false
        cachedFrameSnapshot = nil
        if timestamp > 0 {
            lastRenderTime = timestamp
        }
        return scene
    }

    private func discardSceneWithStaleAtlas() {
        guard let generation = cachedSceneAtlasGeneration,
            generation != NativeGlyphAtlas.shared.atlasGeneration
        else { return }
        cachedSceneSnapshot = nil
        cachedSceneAtlasGeneration = nil
        sceneAtlasRefreshPending = true
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
        let sequence = pointerSequence
        updateLongPressPosition(point, at: clock())
        guard pointerSequence == sequence else { return }

        if var dragState = scrollDragState {
            guard let node = dragState.node else {
                scrollDragState = nil
                updateScrollIndicatorHover(to: nil)
                return
            }

            let delta =
                dragState.axis == .vertical ? point.y - dragState.startPoint.y : point.x - dragState.startPoint.x
            let didScroll = node.applyScrollIndicatorDrag(
                startOffset: dragState.startOffset, delta: delta, travel: dragState.track.travel)
            if didScroll {
                dragState.didScroll = true
                scrollDragState = dragState
                recordScrollPhase(.interacting, for: node)
            }
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
        pointerSequence &+= 1
        let sequence = pointerSequence
        let cancelledPressedNode = pressedNode
        let cancelledNodeDrag = nodeDragState
        let cancelledDragNode = cancelledNodeDrag?.node
        let cancelledScrollIndicatorNode = activeScrollIndicatorNode

        pressedNode = nil
        buttonRepeatState = nil
        nodeDragState = nil
        scrollDragState = nil
        activeScrollIndicatorNode = nil

        if let attempt = longPressAttempt {
            finishLongPress(attempt, recognized: false)
        }
        guard pointerSequence == sequence else { return }

        if let cancelledNodeDrag, let cancelledDragNode {
            let delta = Point(
                x: cancelledNodeDrag.lastPoint.x - cancelledNodeDrag.startPoint.x,
                y: cancelledNodeDrag.lastPoint.y - cancelledNodeDrag.startPoint.y
            )
            cancelledDragNode.onDragEnd?(cancelledNodeDrag.lastPoint, delta)
        }

        guard pointerSequence == sequence else { return }

        updateHoverTarget(to: nil)
        guard pointerSequence == sequence else { return }
        updateScrollIndicatorHover(to: nil)

        if let cancelledScrollIndicatorNode {
            recordScrollPhase(.idle, for: cancelledScrollIndicatorNode)
            animateColor(
                .scrollIndicator,
                of: cancelledScrollIndicatorNode,
                to: cancelledScrollIndicatorNode.restingScrollIndicatorColor,
                duration: 0.12,
                at: clock()
            )
        }

        cancelledPressedNode?.onPointerUpOutside?()
        guard pointerSequence == sequence else { return }
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
        guard delta.isFinite, delta != 0, point.x.isFinite, point.y.isFinite else {
            return
        }

        // Advance old velocity to the event time before adding an impulse.
        // Resetting lastTime on every event without advancing it made a
        // continuous stream accumulate an unbounded glide tail.
        _ = tickScrollMomenta(at: clock())
        guard
            let initialTarget = scrollTarget(at: point, axis: axis)
                ?? nearestScrollableNode(from: hoveredNode, axis: axis)
        else {
            return
        }

        let modal = activeModalPresentationNode
        guard modal.map({ Self.isInteractionTarget(initialTarget, within: $0) }) ?? true else {
            return
        }
        let requestedAxis = axis ?? initialTarget.scrollAxis
        var candidate: ViewNode? = initialTarget
        var remainingDelta = delta
        var didMove = false
        while let scrollableNode = candidate {
            cancelScrollPresentedTween(for: scrollableNode, preservingPresentation: true)
            let reversesOvershoot =
                scrollableNode.scrollOvershoot != 0
                && (scrollableNode.scrollOvershoot > 0) == (remainingDelta > 0)
            if reversesOvershoot || (source != .precise && scrollableNode.scrollOvershoot == 0) {
                cancelScrollMomentum(for: scrollableNode)
            }

            let previousGeometry = scrollObserverRegistry.map { _ in
                scrollGeometry(of: scrollableNode, useResolvedOffset: false)
            }
            let refusedDelta = scrollableNode.refusedMouseWheelDelta(remainingDelta)
            let appliedDelta = scrollableNode.applyMouseWheelDelta(remainingDelta)
            didMove = didMove || appliedDelta != 0
            if appliedDelta != 0 {
                recordScrollPhase(.interacting, for: scrollableNode, geometry: previousGeometry)
            }

            // Pass only unused line movement to an ancestor on the same
            // axis. A nested viewport whose content fits must not swallow
            // the wheel, and ancestors may have a different per-line step.
            if appliedDelta == 0 || refusedDelta != 0,
                let ancestor = wheelScrollAncestor(of: scrollableNode, delta: remainingDelta, axis: requestedAxis),
                modal.map({ Self.isInteractionTarget(ancestor, within: $0) }) ?? true
            {
                if appliedDelta != 0 {
                    remainingDelta += appliedDelta / scrollableNode.scrollStep
                }
                cancelScrollMomentum(for: scrollableNode)
                if appliedDelta != 0 { recordScrollPhase(.idle, for: scrollableNode) }
                candidate = ancestor
                continue
            }

            if refusedDelta != 0 {
                if appliedDelta == 0 {
                    recordScrollPhase(.interacting, for: scrollableNode, geometry: previousGeometry)
                }
                // Include a push that first reaches the edge: dropping its
                // refused part made offsets 0 and 0.1 react differently to
                // exactly the same wheel event.
                beginEdgeRubberBand(for: scrollableNode, refusedOffsetDelta: refusedDelta)
                revealScrollIndicator(for: scrollableNode)
                didMove = true
            } else if source == .precise, appliedDelta != 0 {
                seedScrollMomentum(for: scrollableNode, wheelDelta: remainingDelta, appliedOffsetDelta: appliedDelta)
            }
            recordScrollPhase(scrollPhase(of: scrollableNode), for: scrollableNode)
            break
        }

        if didMove {
            updateHoverTarget(to: pointerInteractionTarget(from: hitTest(at: point), at: point))
        }
    }

    private func wheelScrollAncestor(of node: ViewNode, delta: Double, axis: ScrollAxis?) -> ViewNode? {
        var candidate = nearestScrollableNode(from: node.parent, axis: axis)
        while let ancestor = candidate {
            let offset = ancestor.clampedScrollOffset(for: ancestor.scrollOffset + ancestor.scrollPresentedDelta)
            let canMove = delta < 0 ? offset < ancestor.maxScrollOffset : offset > 0
            if ancestor.maxScrollOffset > 0, ancestor.scrollStep.isFinite, ancestor.scrollStep > 0,
                node.maxScrollOffset == 0 || canMove
            {
                return ancestor
            }
            candidate = nearestScrollableNode(from: ancestor.parent, axis: axis)
        }
        return nil
    }

    public func pointerDown(at point: Point) {
        pointerSequence &+= 1
        let sequence = pointerSequence
        let timestamp = clock()
        let previousPressedNode = pressedNode
        pressedNode = nil
        buttonRepeatState = nil
        applyInteractionChrome(to: previousPressedNode)
        if let attempt = longPressAttempt {
            finishLongPress(attempt, recognized: false)
        }
        guard pointerSequence == sequence else { return }

        if let scrollIndicatorHit = scrollIndicatorHit(at: point) {
            cancelScrollMomentum(for: scrollIndicatorHit.node)
            cancelScrollPresentedTween(for: scrollIndicatorHit.node, preservingPresentation: true)
            scrollDragState = ScrollDragState(
                node: scrollIndicatorHit.node, axis: scrollIndicatorHit.track.axis, startPoint: point,
                startOffset: scrollIndicatorHit.node.scrollOffset, track: scrollIndicatorHit.track)
            activeScrollIndicatorNode = scrollIndicatorHit.node
            recordScrollPhase(.tracking, for: scrollIndicatorHit.node)
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
        guard pointerSequence == sequence else { return }
        updateHoverTarget(to: hoverNode)
        guard pointerSequence == sequence else { return }
        pressedNode = interactionNode
        interactionNode?.onPointerDown?()
        guard pointerSequence == sequence, pressedNode === interactionNode else { return }
        applyInteractionChrome(to: interactionNode)
        beginButtonRepeatIfNeeded(for: interactionNode)
        beginLongPressIfNeeded(for: interactionNode, at: point, timestamp: timestamp)
    }

    public func pointerUp(at point: Point) {
        let sequence = pointerSequence
        if let attempt = longPressAttempt {
            // A release can be the first event after the deadline. Validate
            // its final displacement even if no intervening move was sent.
            let timestamp = clock()
            updateLongPressPosition(point, at: timestamp)
            if longPressAttempt === attempt,
                !attempt.isCheckingDeadline || !timestamp.isFinite || timestamp < attempt.deadline
            {
                finishLongPress(attempt, recognized: false)
            }
        }
        guard pointerSequence == sequence else { return }

        if let dragState = scrollDragState {
            scrollDragState = nil
            activeScrollIndicatorNode = nil
            let nextIndicatorHit = scrollIndicatorHit(at: point)
            updateScrollIndicatorHover(to: nextIndicatorHit)

            if let node = dragState.node {
                recordScrollPhase(.idle, for: node)
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
                guard pointerSequence == sequence, pressedNode.runtime === self else { return }
                pressedNode.onPointerUpInsideAt?(point)
                guard pointerSequence == sequence, pressedNode.runtime === self else { return }
                if !didRepeat {
                    pressedNode.onActivate?()
                }
            } else {
                pressedNode.onPointerUpOutside?()
            }
        }

        guard pointerSequence == sequence else { return }
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
        presentationKeyDispatchDepth += 1
        defer {
            presentationKeyDispatchDepth -= 1
            if presentationKeyDispatchDepth == 0, !pendingPresentationFocusRequests.isEmpty,
                permitsRenderLifecycleCallbacks
            {
                // A nested render may have consumed the enqueue invalidation.
                // Keep one later layout pending, without restoring into the
                // background while this key is still being dispatched.
                invalidate(.layout)
            }
        }
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

        // A newly presented modal can still inherit focus from the control
        // that opened it. Never let its first Enter/Space/Escape reach that
        // obscured control: move focus into the active presentation first.
        if let modal = activeModalPresentationNode,
            focusedNode.map({ !Self.isInteractionTarget($0, within: modal) }) ?? true
        {
            let firstModalFocus = prepaintState.focusOrder.first {
                guard let candidate = node(for: $0) else { return false }
                return Self.isInteractionTarget(candidate, within: modal)
            }
            updateFocusTarget(to: node(for: firstModalFocus))
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

        // A multiline editor owns its caret movement even when an enclosing
        // scroll view can consume the same key. Explicit application shortcuts
        // have already run; other controls retain their unmodified-arrow rule.
        if let focusedNode,
            focusedNode.interceptsVerticalArrowKeys,
            focusedNode.accessibilityTraits.contains(.isTextInput),
            event.modifiers.isSubset(of: [.shift, .control]),
            let key = event.key,
            key == .upArrow || key == .downArrow || key == .home || key == .end
        {
            focusedNode.onKeyDown?(event)
            return
        }

        if let key = event.key,
            key == .upArrow || key == .downArrow,
            event.modifiers.isEmpty,
            focusedNode?.interceptsVerticalArrowKeys == true
        {
            focusedNode?.onKeyDown?(event)
            return
        }

        // Ctrl+Left/Right belong to an active text editor even when it sits
        // inside an overflowing horizontal scroll view. Window shortcuts
        // were already offered the event above; ordinary arrows and focused
        // non-editor controls keep the existing scroll behavior.
        if event.modifiers.contains(.control),
            event.key == .leftArrow || event.key == .rightArrow,
            let focusedNode,
            focusedNode.accessibilityTraits.contains(.isTextInput)
        {
            focusedNode.onKeyDown?(event)
            return
        }

        if let key = event.key, handleScrollKey(key) {
            return
        }

        focusedNode?.onKeyDown?(event)
    }

    public func keyboardFocusDidLeaveWindow() {
        let sequence = pointerSequence
        buttonRepeatState = nil
        if let attempt = longPressAttempt {
            finishLongPress(attempt, recognized: false)
        }
        guard pointerSequence == sequence else { return }
        updateFocusTarget(to: nil, origin: .cleanup)
    }

    /// Routes an IME composition event to the focused text input. Nodes
    /// without an `onIMEComposition` handler ignore it; when no IME is
    /// active this is never called and keyboard input flows through
    /// `keyDown` exactly as before.
    public func imeComposition(_ event: IMECompositionEvent) {
        if let modal = activeModalPresentationNode,
            let focusedNode,
            !Self.isInteractionTarget(focusedNode, within: modal)
        {
            return
        }
        focusedNode?.onIMEComposition?(event)
    }

    /// Caret rectangle of the focused text input in root (logical)
    /// coordinates, used to position the OS IME candidate/composition
    /// window. `nil` when the focused node is not a text input or cannot
    /// report a caret.
    public var focusedTextInputCaretRect: Rect? {
        if let modal = activeModalPresentationNode,
            let focusedNode,
            !Self.isInteractionTarget(focusedNode, within: modal)
        {
            return nil
        }
        return focusedNode?.textInputCaretRectProvider?()
    }

    public func requestFocus(_ node: ViewNode?) {
        // FocusState builds its destination before the new subtree is
        // attached, so detached candidates must remain eligible. Attached
        // background controls cannot steal focus from the current modal.
        // External accessibility entry has its own stricter layout authority.
        updateFocusTarget(to: node)
    }

    /// List navigation adds its physical attachment check to ordinary focus.
    /// It never grants eligibility to a still-deferred or detached target.
    @discardableResult
    package func requestListNavigationFocus(_ node: ViewNode, receipt: RetainedListNavigationReceipt) -> Bool {
        guard receipt.permitsFocusEntry(in: self, target: node) else { return false }
        return updateFocusTarget(to: node, listNavigationReceipt: receipt)
    }

    /// External focus needs an actually attached, currently projected owner.
    /// False can follow a callback that already changed focus; it is never a
    /// request to retry the operation or undo a newer accepted focus choice.
    package func requestAccessibilityFocus(_ node: ViewNode) -> Bool {
        guard permitsRenderLifecycleCallbacks, !focusRevision.isExhausted,
            canReadLayoutSettlement, node.isFocusable, isPresentationNodeAvailable(node)
        else { return false }
        let revision = presentationFocusRevision
        guard queryFocusLayout(usingFrameQuery: true),
            permitsRenderLifecycleCallbacks, !focusRevision.isExhausted,
            presentationFocusRevision == revision,
            accessibilityFocusContextIsCurrent(for: node)
        else { return false }
        return updateFocusTarget(to: node, origin: .accessibility)
    }

    /// Stored admission only: construction and retained callbacks must finish
    /// before an escaped presentation action can consult application bindings.
    package var presentationActionsAreAvailable: Bool {
        presentationRuntimeIsIdle && !isResolvingPresentationAction
    }

    private var presentationRuntimeIsIdle: Bool {
        permitsRenderLifecycleCallbacks
            && !isRendering && !isLayoutInProgress && !isUpdatingResolvedLayout
            && !isResolvingLayoutFrame && !isDeliveringRenderLifecycleCallbacks
            && !isDrainingAfterLayoutActions && longPressReconciliationDepth == 0
            && !isDrainingReconciliationCallbacks && pendingLongPressCallbacks.isEmpty
            && pendingRetainedBuildCompletions.isEmpty
            && retainedBuildCoordinatorStorage?.isBuildSettled != false
    }

    /// The last accepted prepaint's modal, without running layout or a user
    /// callback while the next presentation is being constructed.
    package var presentationModalSnapshot: ViewNode? {
        guard permitsRenderLifecycleCallbacks else { return nil }
        return prepaintState.dispatchNodes.last {
            $0.node.isModalPresentationScope
                && isPresentationNodeAvailable($0.node, requiresEnabled: false)
        }?.node
    }

    /// The presentation itself is eligible for an implicit dismissal; it need
    /// not be focusable or hit-testable. Custom actions must belong to this
    /// exact, frontmost modal after layout and any deferred builds settle.
    package func permitsPresentationAction(on node: ViewNode, within presentation: ViewNode) -> Bool {
        guard presentationActionsAreAvailable else { return false }
        isResolvingPresentationAction = true
        defer { isResolvingPresentationAction = false }
        updateResolvedLayout()
        return presentationRuntimeIsIdle
            && presentationPrepaintRevision == presentationMutationRevision
            && presentationModalSnapshot === presentation
            && isPresentationNodeAvailable(node)
            && Self.isInteractionTarget(node, within: presentation)
            && prepaintState.dispatchNodes.contains { $0.node === node }
    }

    package func schedulePresentationFocusRestoration(_ request: RetainedPresentationFocusRequest) {
        guard permitsRenderLifecycleCallbacks, !focusRevision.isExhausted, !request.isRevoked else {
            request.finish()
            return
        }
        if let index = pendingPresentationFocusRequests.firstIndex(where: { $0.owner === request.owner }) {
            let previous = pendingPresentationFocusRequests[index]
            guard previous !== request else { return }
            previous.revoke()
            pendingPresentationFocusRequests[index] = request
            // Publish the replacement before finishing the old receipt:
            // releasing its captures can enqueue another request for this slot.
            previous.finish()
        } else {
            pendingPresentationFocusRequests.append(request)
        }
        guard pendingPresentationFocusRequests.contains(where: { $0 === request }), !request.isRevoked else { return }
        invalidate(.layout)
        drainPresentationFocusRestorations()
    }

    private var presentationFocusCanRun: Bool {
        !focusRevision.isExhausted && presentationActionsAreAvailable && presentationKeyDispatchDepth == 0
    }

    private func waitForPresentationBuildSettlementIfNeeded() {
        guard permitsRenderLifecycleCallbacks, !focusRevision.isExhausted, !pendingPresentationFocusRequests.isEmpty,
            !isWaitingForPresentationBuildSettlement
        else { return }
        let coordinator = retainedBuildCoordinator
        guard !coordinator.isBuildSettled else { return }
        isWaitingForPresentationBuildSettlement = true
        coordinator.scheduleAfterBuildsSettled(owner: presentationBuildSettlementOwner) { [weak self] in
            guard let self else { return }
            self.isWaitingForPresentationBuildSettlement = false
            self.drainPresentationFocusRestorations()
        }
    }

    private func drainPresentationFocusRestorations(layoutIsFresh: Bool = false) {
        guard permitsRenderLifecycleCallbacks, !pendingPresentationFocusRequests.isEmpty,
            !isDrainingPresentationFocusRequests
        else { return }
        guard presentationFocusCanRun else {
            waitForPresentationBuildSettlementIfNeeded()
            return
        }
        isDrainingPresentationFocusRequests = true
        defer {
            isDrainingPresentationFocusRequests = false
            waitForPresentationBuildSettlementIfNeeded()
        }
        // A callback-created request belongs to a later independent layout or
        // settlement opportunity, never another iteration of this drain.
        let requests = pendingPresentationFocusRequests
        if !layoutIsFresh || presentationPrepaintRevision != presentationMutationRevision {
            _ = queryFocusLayout(usingFrameQuery: false)
        }
        for request in requests {
            guard pendingPresentationFocusRequests.contains(where: { $0 === request }) else { continue }
            guard presentationFocusCanRun else { return }
            guard presentationFocusRequestIsCurrent(request, revision: request.expectedFocusRevision) else {
                guard permitsRenderLifecycleCallbacks else { return }
                finishPresentationFocusRequest(request)
                continue
            }
            if presentationPrepaintRevision != presentationMutationRevision {
                _ = queryFocusLayout(usingFrameQuery: false)
            }
            guard presentationFocusCanRun else { return }
            restorePresentationFocus(request)
            guard permitsRenderLifecycleCallbacks else { return }
            // A resolver may have begun independent retained work after the
            // first readiness check. Keep the receipt until that work settles;
            // a started focus transition will then fail its old revision.
            guard presentationFocusCanRun else { return }
            finishPresentationFocusRequest(request)
        }
    }

    private func finishPresentationFocusRequest(_ request: RetainedPresentationFocusRequest) {
        if let index = pendingPresentationFocusRequests.firstIndex(where: { $0 === request }) {
            pendingPresentationFocusRequests.remove(at: index)
        }
        request.finish()
    }

    private func presentationFocusRequestIsCurrent(
        _ request: RetainedPresentationFocusRequest, revision: UInt64
    ) -> Bool {
        guard presentationFocusCanRun, !request.isRevoked,
            presentationFocusRevision == revision,
            pendingPresentationFocusRequests.contains(where: { $0 === request }),
            request.isCurrent?() == true
        else { return false }
        // The facade promises a stored-only predicate. Still recheck the
        // primitive admission after calling across that package boundary.
        return presentationFocusCanRun && !request.isRevoked && presentationFocusRevision == revision
            && pendingPresentationFocusRequests.contains(where: { $0 === request })
    }

    private func isPresentationNodeAvailable(_ node: ViewNode, requiresEnabled: Bool = true) -> Bool {
        var current: ViewNode? = node
        var depth = 0
        while let candidate = current, depth < ViewNode.maximumTraversalDepth {
            guard candidate.runtime === self, !candidate.isHidden, !candidate.isRemovalOverlay,
                !candidate.isLayoutDeferredByVirtualization,
                !requiresEnabled || candidate.accessibilityRespondsToUserInteraction != false
            else { return false }
            if candidate === root { return true }
            current = candidate.parent
            depth += 1
        }
        return false
    }

    private func presentationFocusTargetIsEligible(
        _ node: ViewNode, base: ViewNode, modal: ViewNode?, request: RetainedPresentationFocusRequest
    ) -> Bool {
        guard node.isFocusable, isPresentationNodeAvailable(node),
            prepaintState.dispatchNodes.contains(where: { $0.node === node })
        else { return false }
        if let modal {
            return modal === request.underlyingModal && Self.isInteractionTarget(node, within: modal)
        }
        return Self.isInteractionTarget(node, within: base)
    }

    private func presentationFocusContextIsCurrent(
        _ request: RetainedPresentationFocusRequest, revision: UInt64, base: ViewNode, target: ViewNode? = nil
    ) -> Bool {
        guard presentationFocusRequestIsCurrent(request, revision: revision) else { return false }
        if presentationPrepaintRevision != presentationMutationRevision {
            _ = queryFocusLayout(usingFrameQuery: false)
        }
        guard presentationFocusRequestIsCurrent(request, revision: revision),
            presentationPrepaintRevision == presentationMutationRevision,
            isPresentationNodeAvailable(base),
            prepaintState.dispatchNodes.contains(where: { $0.node === base })
        else { return false }
        let modal = presentationModalSnapshot
        guard modal == nil || modal === request.underlyingModal else { return false }
        return target.map { presentationFocusTargetIsEligible($0, base: base, modal: modal, request: request) } ?? true
    }

    private func restorePresentationFocus(_ request: RetainedPresentationFocusRequest) {
        let expectedRevision = request.expectedFocusRevision
        guard presentationFocusRequestIsCurrent(request, revision: expectedRevision),
            let base = request.resolveBase?(),
            presentationFocusContextIsCurrent(request, revision: expectedRevision, base: base)
        else { return }
        let modal = presentationModalSnapshot
        let preferred = request.preferred.flatMap { candidate in
            presentationFocusTargetIsEligible(candidate, base: base, modal: modal, request: request) ? candidate : nil
        }
        let fallback = prepaintState.focusOrder.lazy.compactMap { self.node(for: $0) }.first { candidate in
            Self.isInteractionTarget(candidate, within: base)
                && self.presentationFocusTargetIsEligible(candidate, base: base, modal: modal, request: request)
        }
        guard let target = preferred ?? fallback, focusedNode !== target else { return }

        guard let revision = advanceFocusRevision() else { return }
        var previous = focusedNode
        var previousTimestamp = 0.0
        if previous?.interactionSurface != nil {
            previousTimestamp = sampleFocusClock()
            guard presentationFocusContextIsCurrent(request, revision: revision, base: base, target: target) else {
                return
            }
        }
        // An exit callback can request focus itself. Remove the old pointer
        // first so that nested ordinary request does not re-enter this exit.
        focusedNode = nil
        previous?.isFocused = false
        applyInteractionChrome(to: previous, at: previousTimestamp)
        guard presentationFocusRequestIsCurrent(request, revision: revision) else { return }
        deliverFocusExit(previous)
        previous = nil
        guard presentationFocusContextIsCurrent(request, revision: revision, base: base, target: target) else { return }

        focusedNode = target
        target.isFocused = true
        let entry = RetainedFocusEntry(target: target, beganAttached: true)
        currentFocusEntry = entry
        defer { clearFocusEntry(entry) }
        deliverFocusEnter(target)
        if let reaffirmation = takeFocusReaffirmation(entry) {
            // Complete the newer intent under its own policy, without
            // borrowing the old removal's authority or its build restrictions.
            completeReaffirmedPresentationFocus(target, entry: entry, reaffirmation: reaffirmation)
            return
        }
        guard presentationFocusContextIsCurrent(request, revision: revision, base: base, target: target),
            focusedNode === target
        else {
            withdrawInterruptedPresentationFocus(target, revision: revision)
            return
        }
        let timestamp = target.interactionSurface == nil ? 0 : sampleFocusClock()
        if let reaffirmation = takeFocusReaffirmation(entry) {
            completeReaffirmedPresentationFocus(
                target, entry: entry, reaffirmation: reaffirmation, at: timestamp)
            return
        }
        guard presentationFocusContextIsCurrent(request, revision: revision, base: base, target: target),
            focusedNode === target
        else {
            withdrawInterruptedPresentationFocus(target, revision: revision)
            return
        }
        resetCaretBlink()
        applyInteractionChrome(to: target, at: timestamp)
        guard presentationFocusContextIsCurrent(request, revision: revision, base: base, target: target),
            focusedNode === target
        else {
            withdrawInterruptedPresentationFocus(target, revision: revision)
            return
        }
        invalidate(.paint)
        clearFocusEntry(entry)
        deliverAccessibilityFocusNotification(target)
    }

    private func completeReaffirmedPresentationFocus(
        _ target: ViewNode, entry: RetainedFocusEntry, reaffirmation: RetainedFocusReaffirmation,
        at timestamp: Double? = nil
    ) {
        let operation = RetainedFocusOperation(
            target: target, origin: reaffirmation.origin, beganAttached: true,
            revision: reaffirmation.revision, mutationWitness: reaffirmation.mutationWitness)
        _ = finishFocusEntry(operation, to: target, entry: entry, at: timestamp)
    }

    private func withdrawInterruptedPresentationFocus(_ target: ViewNode, revision: UInt64) {
        // Do not erase a focus choice made by an enter/exit callback, and do
        // not deliver a stale exit or UIA notification after close/replacement.
        guard presentationFocusRevision == revision, focusedNode === target else { return }
        focusedNode = nil
        target.isFocused = false
    }

    /// The current layout frame in root coordinates, including presented
    /// ancestor scroll offsets. Authored `ViewNode.frame` values do not
    /// describe the placement of children in stacks or frame wrappers.
    ///
    /// Settles pending layout before reading. Hidden, detached, foreign, or
    /// removed nodes, and queries during rendering or another geometry query,
    /// return nil. This is layout space; node transforms are not applied.
    public func resolvedLayoutFrame(of node: ViewNode) -> Rect? {
        guard node.runtime === self, !isRendering, !isLayoutInProgress, !isResolvingLayoutFrame else { return nil }
        lazyListScrollWorkDepth += 1
        defer {
            lazyListScrollWorkDepth -= 1
            finishLazyListResolutionBudgetIfIdle()
        }
        settleLayoutFrameQuery()

        var origin = Point.zero
        var current: ViewNode? = node
        var depth = 0
        while let ancestor = current, depth < ViewNode.maximumTraversalDepth {
            guard ancestor.runtime === self, !ancestor.isHidden else { return nil }
            origin.x += ancestor.resolvedFrame.origin.x
            origin.y += ancestor.resolvedFrame.origin.y
            if ancestor !== node {
                switch ancestor.scrollAxis {
                case .horizontal: origin.x -= ancestor.resolvedScrollOffset
                case .vertical: origin.y -= ancestor.resolvedScrollOffset
                case nil: break
                }
            }
            if ancestor === root {
                return Rect(origin: origin, size: node.resolvedFrame.size)
            }
            current = ancestor.parent
            depth += 1
        }
        return nil
    }

    private func settleLayoutFrameQuery() {
        isResolvingLayoutFrame = true
        defer {
            isResolvingLayoutFrame = false
            let reveal = captureListNavigationRevealSettlement()
            drainPresentationFocusRestorations(layoutIsFresh: true)
            retainedBuildCoordinatorStorage?.retainedCallbacksDidDrain()
            drainListNavigationReveal(reveal)
        }
        updateResolvedLayout()
    }

    /// Uses the existing settlement queue, not an independent scheduler.
    /// Callers retain a native registration marker, capture their request
    /// weakly, and recheck its exact target before any binding or focus work.
    package func scheduleAfterLazyListLayout(
        owner: AnyObject, perform action: @escaping @MainActor () -> Void
    ) {
        retainedBuildCoordinator.scheduleAfterLayoutAndBuildsSettled(owner: owner, action: action)
    }

    private func preparedListNavigationReplayKey(for owner: AnyObject) -> String {
        "list.prepared.navigation.\(ObjectIdentifier(owner))"
    }

    /// The runtime and its existing queues own this bounded payload. A receipt
    /// never stores the callbacks, so callbacks may retain a facade request
    /// without forming a receipt/request cycle. The native owner keeps the
    /// ObjectIdentifier key alive; the exact receipt reference remains weak.
    @MainActor
    private final class PreparedListNavigationReplay {
        let owner: AnyObject
        weak var receipt: RetainedListNavigationReceipt?
        var action: (@MainActor () -> Void)?
        private var onCancel: (@MainActor () -> Void)?

        init(
            owner: AnyObject, receipt: RetainedListNavigationReceipt,
            action: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void
        ) {
            self.owner = owner
            self.receipt = receipt
            self.action = action
            self.onCancel = onCancel
        }

        /// Clear native delivery authority before any callback or captured
        /// application payload can be released. Locals retain both payloads
        /// until the returned retirement reaches ordinary safe cleanup.
        func takeRetirement(notifyingCancellation: Bool) -> (@MainActor () -> Void)? {
            guard let action, let onCancel else { return nil }
            self.action = nil
            self.onCancel = nil
            return {
                if notifyingCancellation { onCancel() }
                withExtendedLifetime((action, onCancel)) {}
            }
        }
    }

    func schedulePreparedListNavigationReplay(
        owner: AnyObject, receipt: RetainedListNavigationReceipt, afterLayout: Bool,
        perform action: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void
    ) {
        beginLongPressReconciliation()
        defer { endLongPressReconciliation() }
        let replay = PreparedListNavigationReplay(owner: owner, receipt: receipt, action: action, onCancel: onCancel)
        let previous = preparedListNavigationReplays.updateValue(replay, forKey: ObjectIdentifier(owner))
        var retirements: [@MainActor () -> Void] = []
        if let previous,
            let retirement = previous.takeRetirement(notifyingCancellation: previous.receipt !== receipt)
        {
            // Rescheduling the exact receipt replaces only this delivery. A
            // newer receipt ends the old request even if its callback is in
            // an existing delivery snapshot or still executing below it.
            retirements.append(retirement)
        }
        let delivery: @MainActor () -> Void = { [weak self, replay] in
            self?.deliverPreparedListNavigationReplay(replay)
        }
        let key = preparedListNavigationReplayKey(for: owner)
        let displaced: (@MainActor () -> Void)?
        if afterLayout {
            displaced = retainedBuildCoordinatorStorage?.removeSettlementCallback(owner: owner)
            scheduleAfterLayout(key: key, perform: delivery)
        } else {
            displaced = pendingAfterLayoutActions.removeValue(forKey: key)
            pendingAfterLayoutActionKeys.removeAll { $0 == key }
            scheduleAfterLazyListLayout(owner: owner, perform: delivery)
        }
        if let displaced { retirements.append { withExtendedLifetime(displaced) {} } }
        schedulePreparedListNavigationRetirements(retirements)
    }

    private func deliverPreparedListNavigationReplay(_ replay: PreparedListNavigationReplay) {
        let identifier = ObjectIdentifier(replay.owner)
        guard preparedListNavigationReplays[identifier] === replay else { return }
        guard replay.receipt?.permitsPreparedNavigationReplay == true else {
            cancelPreparedListNavigationReplay(owner: replay.owner)
            return
        }
        guard let action = replay.action else { return }
        action()
        // Keep the native record during the call so supersession, departure,
        // or close can cancel an executing request. A callback that reschedules
        // itself has already installed a distinct delivery for the same intent.
        if preparedListNavigationReplays[identifier] === replay {
            preparedListNavigationReplays.removeValue(forKey: identifier)
            if let retirement = replay.takeRetirement(notifyingCancellation: false) {
                schedulePreparedListNavigationRetirements([retirement])
            }
        }
        withExtendedLifetime(action) {}
    }

    func cancelPreparedListNavigationReplay(owner: AnyObject) {
        let replay = preparedListNavigationReplays.removeValue(forKey: ObjectIdentifier(owner))
        var retirements: [@MainActor () -> Void] = []
        if let retirement = replay?.takeRetirement(notifyingCancellation: true) { retirements.append(retirement) }
        let key = preparedListNavigationReplayKey(for: owner)
        let afterLayout = pendingAfterLayoutActions.removeValue(forKey: key)
        pendingAfterLayoutActionKeys.removeAll { $0 == key }
        let idle = retainedBuildCoordinatorStorage?.removeSettlementCallback(owner: owner)
        let callbacks = [afterLayout, idle].compactMap { $0 }
        if !callbacks.isEmpty { retirements.append { withExtendedLifetime(callbacks) {} } }
        schedulePreparedListNavigationRetirements(retirements)
    }

    private func schedulePreparedListNavigationRetirements(_ retirements: [@MainActor () -> Void]) {
        guard !retirements.isEmpty else { return }
        if !permitsRenderLifecycleCallbacks && !hasFinishedRenderLifecycleTaskCancellation {
            // stopRenderLifecycleCallbacks is a native revocation prepass.
            // Neither cancellation nor captured payload destruction may run
            // until the host has revoked State/editor/task writes.
            retiredPreparedListNavigationRetirements.append(contentsOf: retirements)
            return
        }
        afterRetainedCallbacks { [weak self] in
            guard let self else { return }
            // A retirement queued while live can cross host closure before
            // this delivery. Check the native cleanup phase again here.
            if !self.permitsRenderLifecycleCallbacks && !self.hasFinishedRenderLifecycleTaskCancellation {
                self.retiredPreparedListNavigationRetirements.append(contentsOf: retirements)
                return
            }
            for index in retirements.indices {
                retirements[index]()
                if !self.permitsRenderLifecycleCallbacks && !self.hasFinishedRenderLifecycleTaskCancellation {
                    // A notification can start host closure. Do not invoke
                    // the remaining notifications or destroy even the already
                    // invoked payloads until its terminal cleanup completes.
                    self.retiredPreparedListNavigationRetirements.append(contentsOf: retirements.dropFirst(index + 1))
                    self.retiredPreparedListNavigationRetirements.append { withExtendedLifetime(retirements) {} }
                    return
                }
            }
        }
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

    fileprivate func registerScrollObservationNode(_ node: ViewNode) {
        let registry = scrollObserverRegistry ?? RetainedScrollObserverRegistry()
        registry.register(node)
        scrollObserverRegistry = registry
    }

    fileprivate func unregisterScrollObservationNode(_ node: ViewNode) {
        guard let registry = scrollObserverRegistry else { return }
        registry.unregister(node)
        if registry.isEmpty, !registry.isDelivering {
            scrollObserverRegistry = nil
        }
    }

    /// A modifier outside a ScrollView observes the first enclosed container,
    /// not every nested scroller. Stop descending at each container boundary.
    private func observedScrollSource(
        for owner: ViewNode, storage: RetainedScrollObserverStorage,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> ViewNode? {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return nil }
        let attachment = admission == nil && nativeCheck == nil ? nil : owner.captureLazyListAttachmentProof()
        let identity = nativeCheck == nil ? nil : owner.captureLazyListIdentityProof()
        var work: [(ViewNode, Int)] = [(owner, 0)]
        var first: ViewNode?
        while let (node, depth) = work.popLast() {
            guard depth < ViewNode.maximumTraversalDepth else { continue }
            if node.scrollContainerState != nil || node.scrollAxis != nil {
                if first == nil {
                    first = node
                } else {
                    if !storage.reportedMultipleSources {
                        storage.reportedMultipleSources = true
                        FileHandle.standardError.write(
                            Data(
                                "[SwiftWindowsUI] Scroll observation found multiple scroll views; only the first is observed.\n"
                                    .utf8))
                    }
                    break
                }
                continue
            }
            for child in node.children.reversed() { work.append((child, depth + 1)) }
        }
        guard
            storage.selectSource(
                first, admission: admission, attachment: attachment, nativeCheck: nativeCheck,
                owner: nativeCheck == nil ? nil : owner, ownerIdentity: identity),
            admission?.isCurrent != false, attachment?.isCurrent != false, identity?.isCurrent != false,
            nativeCheck?.isCurrent != false,
            (admission == nil && nativeCheck == nil) || owner.scrollObserverStorage === storage
        else { return nil }
        return first
    }

    private func scrollGeometry(of node: ViewNode, useResolvedOffset: Bool) -> RetainedScrollGeometry {
        let authoredInsets = node.layoutMode.stackLayout?.padding ?? .zero
        let insets = EdgeInsets(
            top: sanitizedLayoutCoordinate(authoredInsets.top),
            leading: sanitizedLayoutCoordinate(authoredInsets.leading),
            bottom: sanitizedLayoutCoordinate(authoredInsets.bottom),
            trailing: sanitizedLayoutCoordinate(authoredInsets.trailing))
        // Natural extents are captured before the viewport floor and before
        // layout sanitation. Observers must receive the same finite coordinate
        // range as presentation, including malformed application margins.
        let extent = sanitizedLayoutSize(node.scrollContainerState?.contentSize ?? node.resolvedContentSize)
        let offset = useResolvedOffset ? node.resolvedScrollOffset : node.effectiveScrollOffset
        return RetainedScrollGeometry(
            contentOffset: Point(
                x: sanitizedLayoutCoordinate((node.scrollAxis == .horizontal ? offset : 0) - insets.leading),
                y: sanitizedLayoutCoordinate((node.scrollAxis == .vertical ? offset : 0) - insets.top)),
            contentSize: sanitizedLayoutSize(
                Size(
                    width: extent.width - insets.leading - insets.trailing,
                    height: extent.height - insets.top - insets.bottom)),
            contentInsets: insets,
            containerSize: node.resolvedFrame.size)
    }

    private func scrollPhase(of node: ViewNode) -> RetainedScrollPhase {
        guard node.scrollAxis != nil, !Self.hasHiddenAncestor(node) else { return .idle }
        let identifier = ObjectIdentifier(node)
        if let tween = scrollPresentedTweens[identifier],
            tween.origin.isProgrammatic || node.acceptsScrollInput
        {
            return .animating
        }
        guard node.acceptsScrollInput else { return .idle }
        if let drag = scrollDragState, drag.node === node {
            return drag.didScroll ? .interacting : .tracking
        }
        if scrollMomenta[identifier] != nil { return .decelerating }
        return .idle
    }

    private func scrollPhaseContext(
        of node: ViewNode,
        geometry: RetainedScrollGeometry? = nil
    ) -> RetainedScrollPhaseChangeContext {
        let velocity = scrollMomenta[ObjectIdentifier(node)].map { state in
            Point(
                x: node.scrollAxis == .horizontal ? state.velocity : 0,
                y: node.scrollAxis == .vertical ? state.velocity : 0)
        }
        return RetainedScrollPhaseChangeContext(
            geometry: geometry ?? scrollGeometry(of: node, useResolvedOffset: false), velocity: velocity)
    }

    @discardableResult
    private func recordScrollPhase(
        _ phase: RetainedScrollPhase,
        for node: ViewNode,
        geometry: RetainedScrollGeometry? = nil,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        let attachment = admission == nil ? nil : node.captureLazyListAttachmentProof()
        guard let registry = scrollObserverRegistry else { return true }
        for reference in registry.nodes {
            guard admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
            else { return false }
            guard let owner = reference.node, owner.runtime === self,
                let storage = owner.scrollObserverStorage, !storage.phase.isEmpty
            else { continue }
            let ownerAttachment = admission == nil && nativeCheck == nil ? nil : owner.captureLazyListAttachmentProof()
            let ownerIdentity = nativeCheck == nil ? nil : owner.captureLazyListIdentityProof()
            let source = observedScrollSource(
                for: owner, storage: storage, admission: admission, nativeCheck: nativeCheck)
            guard admission?.isCurrent != false, attachment?.isCurrent != false,
                ownerAttachment?.isCurrent != false, ownerIdentity?.isCurrent != false,
                nativeCheck?.isCurrent != false,
                (admission == nil && nativeCheck == nil) || owner.scrollObserverStorage === storage
            else { return false }
            guard source === node else { continue }
            if storage.currentPhase != phase {
                storage.recordPhase(phase, context: scrollPhaseContext(of: node, geometry: geometry))
                invalidate(.paint)
            }
        }
        return admission?.isCurrent != false && attachment?.isCurrent != false && nativeCheck?.isCurrent != false
    }

    /// A final momentum tick can retire without changing a pixel. It must still
    /// schedule the idle notification instead of stranding app state as active.
    private func refreshScrollObservationPhases() {
        guard let registry = scrollObserverRegistry else { return }
        for reference in registry.nodes {
            guard let owner = reference.node, owner.runtime === self,
                let storage = owner.scrollObserverStorage, !storage.phase.isEmpty,
                let source = observedScrollSource(for: owner, storage: storage)
            else { continue }
            let phase = scrollPhase(of: source)
            if storage.currentPhase != phase {
                storage.recordPhase(phase, context: scrollPhaseContext(of: source))
                invalidate(.paint)
            }
        }
    }

    private func scrollVisibilityFraction(of node: ViewNode) -> Double {
        var chain: [ViewNode] = []
        var ancestor: ViewNode? = node
        while let current = ancestor, chain.count < ViewNode.maximumTraversalDepth {
            guard !current.isHidden else { return 0 }
            chain.append(current)
            if current === root { break }
            ancestor = current.parent
        }
        guard chain.last === root else { return 0 }

        // The physical surface bounds do not rotate with a transformed root.
        var clips = [
            RetainedScrollVisibilityGeometry.corners(
                of: Rect(origin: .zero, size: root.frame.size), transform: .identity)
        ]
        var parentOrigin = Point.zero
        var transform = Transform2D.identity
        var inverse: Transform2D?
        var polygon: [Point] = []
        for current in chain.reversed() {
            let frame = Rect(
                x: parentOrigin.x + current.resolvedFrame.origin.x,
                y: parentOrigin.y + current.resolvedFrame.origin.y,
                width: current.resolvedFrame.width, height: current.resolvedFrame.height)
            let geometry = ViewNode.prepaintGeometry(
                of: frame, transform: current.transform,
                inheritedTransform: transform, inheritedInverseTransform: inverse)
            transform = geometry.effectiveTransform
            inverse = geometry.inverseTransform
            polygon = RetainedScrollVisibilityGeometry.corners(of: frame, transform: transform)
            if current !== node,
                current.clipsToBounds || current.scrollContainerState != nil || current.scrollAxis != nil
            {
                clips.append(polygon)
            }
            parentOrigin = Point(
                x: frame.minX - (current.scrollAxis == .horizontal ? current.resolvedScrollOffset : 0),
                y: frame.minY - (current.scrollAxis == .vertical ? current.resolvedScrollOffset : 0))
        }
        let area = RetainedScrollVisibilityGeometry.area(of: polygon)
        guard area.isFinite, area > 0 else { return 0 }
        for clip in clips {
            polygon = RetainedScrollVisibilityGeometry.intersect(polygon, with: clip)
            if polygon.isEmpty { return 0 }
        }
        let fraction = RetainedScrollVisibilityGeometry.area(of: polygon) / area
        return fraction.isFinite ? min(1, max(0, fraction)) : 0
    }

    /// Snapshot all values before running any app action. Callbacks run only
    /// after a completed paint, never from layout or input dispatch, so a state
    /// mutation schedules another frame rather than recursively sampling one.
    private func deliverScrollObservations() {
        guard let registry = scrollObserverRegistry, !registry.isDelivering else { return }
        registry.isDelivering = true
        registry.compact()
        defer {
            registry.isDelivering = false
            if registry.renderedDuringDelivery {
                // A callback may explicitly render through the other backend
                // path, for which no cached output exists yet. That nested
                // paint cannot consume the next observation of its mutation.
                registry.renderedDuringDelivery = false
                invalidate(.paint)
            }
            if registry.isEmpty { scrollObserverRegistry = nil }
        }
        var actions:
            [(
                RetainedScrollObserverRegistry.NodeRef, RetainedScrollObserverStorage,
                UInt64, RetainedScrollObserverRegistry.NodeRef?, () -> Void
            )] = []
        for reference in registry.nodes {
            guard let owner = reference.node, owner.runtime === self,
                let storage = owner.scrollObserverStorage
            else { continue }
            if !storage.geometry.isEmpty || !storage.phase.isEmpty,
                let source = observedScrollSource(for: owner, storage: storage)
            {
                let sourceReference = RetainedScrollObserverRegistry.NodeRef(node: source)
                if !Self.hasHiddenAncestor(source), source.cachedLayoutKey != nil {
                    let geometry = scrollGeometry(of: source, useResolvedOffset: true)
                    for observer in storage.geometry {
                        if let action = observer.sample(geometry) {
                            actions.append((reference, storage, storage.generation, sourceReference, action))
                        }
                    }
                }
                storage.recordPhase(scrollPhase(of: source), context: scrollPhaseContext(of: source))
                for observer in storage.phase {
                    for action in observer.pendingActions() {
                        actions.append((reference, storage, storage.generation, sourceReference, action))
                    }
                }
            }
            if !storage.visibility.isEmpty {
                let fraction = scrollVisibilityFraction(of: owner)
                for observer in storage.visibility {
                    if let action = observer.sample(fraction) {
                        actions.append((reference, storage, storage.generation, nil, action))
                    }
                }
            }
        }
        for (reference, storage, generation, sourceReference, action) in actions {
            guard let owner = reference.node, owner.runtime === self,
                owner.scrollObserverStorage === storage, storage.generation == generation
            else { continue }
            if let sourceReference {
                guard let source = sourceReference.node, source.runtime === self,
                    Self.isInteractionTarget(source, within: owner),
                    source.scrollSourceEpoch == sourceReference.sourceEpoch
                else { continue }
            }
            action()
        }
    }

    /// Reveals a caret in the explicitly owned text viewport without searching
    /// for or moving an enclosing application scroll view. The rectangle uses
    /// unscrolled viewport-content coordinates; a zero-width caret is valid.
    /// Call after layout, using the current controller's visual text layout.
    /// False leaves a premature or stale request for its owner to reconsider;
    /// true includes an already-visible caret and a request clamped at an edge.
    @discardableResult
    package func revealTextInputRect(
        _ rect: Rect,
        in viewport: ViewNode,
        ownedBy editor: ViewNode,
        controller: any RetainedTextInputController
    ) -> Bool {
        guard focusedNode === editor, editor.textInputController === controller,
            editor.accessibilityTraits.contains(.isTextInput),
            editor.runtime === self, viewport.runtime === self, viewport.parent === editor,
            viewport.scrollAxis == .vertical, viewport.clipsToBounds,
            layoutPassID != 0, !isLayoutInProgress,
            isDrainingAfterLayoutActions || !hasPendingLayout,
            editor.cachedLayoutKey?.displayScale == displayScale, editor.pendingLayoutKey == nil,
            viewport.cachedLayoutKey?.displayScale == displayScale, viewport.pendingLayoutKey == nil,
            displayScale.isFinite,
            rect.origin.x.isFinite, rect.origin.y.isFinite,
            rect.size.width.isFinite, rect.size.width >= 0,
            rect.size.height.isFinite, rect.size.height > 0, rect.maxX.isFinite, rect.maxY.isFinite,
            viewport.resolvedFrame.origin.x.isFinite, viewport.resolvedFrame.origin.y.isFinite,
            viewport.resolvedFrame.size.width.isFinite, viewport.resolvedFrame.size.width > 0,
            viewport.resolvedFrame.size.height.isFinite, viewport.resolvedFrame.size.height > 0,
            viewport.resolvedContentSize.width.isFinite,
            viewport.resolvedContentSize.height.isFinite, viewport.resolvedContentSize.height >= 0
        else { return false }

        var ancestor: ViewNode? = viewport
        var reachedRoot = false
        var depth = 0
        while let node = ancestor, depth < ViewNode.maximumTraversalDepth {
            guard node.runtime === self, !node.isHidden, !node.isRemovalOverlay,
                !node.isLayoutDeferredByVirtualization
            else { return false }
            if node === root {
                reachedRoot = true
                break
            }
            ancestor = node.parent
            depth += 1
        }
        guard reachedRoot,
            activeModalPresentationNode.map({ Self.isInteractionTarget(editor, within: $0) }) ?? true
        else { return false }

        // Geometry queries also drain these callbacks before painting, while
        // hasPendingLayout still includes the layout that just completed.
        // Accept that settled geometry, but not a mutation made by an earlier
        // callback to this editor's content, viewport, or enclosing placement.
        if isDrainingAfterLayoutActions {
            for reference in afterLayoutGeometryInvalidations {
                guard let node = reference.node else { continue }
                if Self.isInteractionTarget(node, within: editor)
                    || Self.isInteractionTarget(editor, within: node)
                {
                    return false
                }
                // A sibling can change the proposal assigned by a shared
                // stack/flex layout. Independent absolute branches do not
                // reflow each other unless their parent has custom placement.
                var placementAncestor = node.parent
                var placementDepth = 0
                while let ancestor = placementAncestor, placementDepth < ViewNode.maximumTraversalDepth {
                    if Self.isInteractionTarget(editor, within: ancestor) {
                        switch ancestor.layoutMode {
                        case .absolute:
                            if ancestor.absoluteChildFrame != nil { return false }
                        case .stack, .lazyStack, .flex, .grid, .gridRow:
                            return false
                        }
                    }
                    placementAncestor = ancestor.parent
                    placementDepth += 1
                }
            }
        }

        let visibleOffset = viewport.effectiveScrollOffset
        let clampedLogicalOffset = viewport.clampedScrollOffset(for: viewport.scrollOffset)
        let needsLogicalClamp = clampedLogicalOffset != viewport.scrollOffset
        let viewportHeight = viewport.resolvedFrame.size.height
        let visibleEnd = visibleOffset + viewportHeight
        guard visibleEnd.isFinite else { return false }
        // A line taller than a short viewport cannot fit completely. Once it
        // fills the viewport, keep that position instead of alternating its
        // leading and trailing edges on repeated reveal requests.
        let requestedOffset: Double
        if rect.minY <= visibleOffset, rect.maxY >= visibleEnd {
            guard needsLogicalClamp else { return true }
            requestedOffset = visibleOffset
        } else if rect.minY < visibleOffset {
            requestedOffset = rect.minY
        } else if rect.maxY > visibleEnd {
            requestedOffset = rect.maxY - viewportHeight
        } else {
            // Shorter content can make the caret visible through clamping
            // while an obsolete logical offset remains stored. Normalize it
            // so growing the document cannot revive that old scroll request.
            guard needsLogicalClamp else { return true }
            requestedOffset = visibleOffset
        }
        let nextOffset = viewport.clampedScrollOffset(for: requestedOffset)
        guard nextOffset != visibleOffset || needsLogicalClamp else { return true }

        // A visible caret with an in-range logical target leaves motion alone.
        // Movement or clamping interrupts only this viewport; neither an outer
        // scroll tween nor an unrelated pointer gesture belongs to it.
        cancelScrollMomentum(for: viewport)
        cancelScrollPresentedTween(for: viewport)
        _ = viewport.setScrollOffset(nextOffset)
        recordScrollPhase(scrollPhase(of: viewport), for: viewport)
        return true
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
        var transaction = currentTransaction ?? Transaction()
        if currentTransaction == nil, let animation = currentAnimationTransaction {
            transaction.animation = Animation(duration: animation.duration, easing: animation.easing)
        }
        return scrollToDescendant(descendant, anchorX: anchorX, anchorY: anchorY, transaction: transaction)
    }

    /// Uses the transaction captured when a request was made. A deferred
    /// proxy replay must not inherit a different animation from the later
    /// layout pass, including when the original request explicitly used nil.
    @discardableResult
    public func scrollToDescendant(
        _ descendant: ViewNode,
        anchorX: Double? = nil,
        anchorY: Double? = nil,
        transaction: Transaction
    ) -> Bool {
        let animation =
            transaction.disablesAnimations
            ? nil
            : transaction.animation.map {
                AnimationTransaction(duration: $0.duration, easing: $0.easing)
            }
        return performProgrammaticScroll(
            to: descendant, anchorX: anchorX, anchorY: anchorY, animation: animation, at: clock())
    }

    /// UIA owns a separate synchronous admission path. Public programmatic
    /// requests still work from after-layout callbacks and with input disabled.
    @inline(never)
    package func realizeAccessibilityTarget(
        _ attachment: RetainedAccessibilityTarget, during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        guard let descendant = attachment.node,
            let element = AccessibilityProjection.mutationElement(
                for: attachment, in: self, during: mutation, resolvingLayout: true),
            element.isVirtualizedPlaceholder,
            let (target, container) = descendant.nearestScrollTarget(), let axis = container.scrollAxis
        else { return false }
        let continuation = RetainedAccessibilityScrollContinuation(
            mutation: mutation, attachment: attachment, target: target, container: container, axis: axis,
            geometryRevision: layoutSettlementGeometryRevision, expectedOffset: container.scrollOffset,
            pointerSequence: pointerSequence)
        guard permitsAccessibilityScrollCancellation(of: container) else { return false }
        var transaction = currentTransaction ?? Transaction()
        if currentTransaction == nil, let animation = currentAnimationTransaction {
            transaction.animation = Animation(duration: animation.duration, easing: animation.easing)
        }
        let animation =
            transaction.disablesAnimations
            ? nil
            : transaction.animation.map {
                AnimationTransaction(duration: $0.duration, easing: $0.easing)
            }
        let timestamp = sampleAccessibilityScrollClock()
        guard validateAccessibilityScroll(continuation) else { return false }
        let performed = performProgrammaticScroll(
            to: descendant, anchorX: nil, anchorY: nil, animation: animation, at: timestamp,
            accessibility: continuation)
        // The helper has released its callback/temporary captures. Never run a
        // query or retry after an offset may already have been applied.
        return performed && isAccessibilityTargetCurrent(attachment, during: mutation)
            && continuation.completionRevision == mutation.revision
            && container.scrollAxis == axis && container.scrollOffset == continuation.expectedOffset
    }

    @inline(never)
    private func sampleAccessibilityScrollClock() -> Double { clock() }

    private func validateAccessibilityScroll(_ continuation: RetainedAccessibilityScrollContinuation) -> Bool {
        guard accessibilityScrollContinuationIsCurrent(continuation),
            let element = AccessibilityProjection.mutationElement(
                for: continuation.attachment, in: self, during: continuation.mutation,
                resolvingLayout: false), element.isVirtualizedPlaceholder
        else { return false }
        return true
    }

    private func accessibilityScrollContinuationIsCurrent(
        _ continuation: RetainedAccessibilityScrollContinuation
    ) -> Bool {
        guard isAccessibilityTargetCurrent(continuation.attachment, during: continuation.mutation),
            continuation.mutation.revision == continuation.expectedRevision,
            layoutSettlementGeometryRevision == continuation.geometryRevision,
            pointerSequence == continuation.pointerSequence,
            let descendant = continuation.attachment.node, let target = continuation.target,
            let container = continuation.container, container.scrollAxis == continuation.axis,
            container.scrollOffset == continuation.expectedOffset,
            let (currentTarget, currentContainer) = descendant.nearestScrollTarget(),
            currentTarget === target, currentContainer === container
        else { return false }
        return true
    }

    private func recordOwnedAccessibilityScrollEffects(_ continuation: RetainedAccessibilityScrollContinuation) {
        continuation.geometryRevision = layoutSettlementGeometryRevision
        continuation.expectedRevision = continuation.mutation.revision
    }

    private func permitsAccessibilityScrollCancellation(of container: ViewNode) -> Bool {
        guard scrollDragState?.node === container || activeScrollIndicatorNode === container else { return true }
        // Repeated public pointerDown calls can leave mixed ownership. UIA must
        // not take over the public cancellation contract for another gesture.
        return nodeDragState == nil && longPressAttempt == nil && pressedNode == nil && buttonRepeatState == nil
    }

    @inline(never)
    private func cancelAccessibilityScrollPointer(
        _ continuation: RetainedAccessibilityScrollContinuation, at timestamp: Double
    ) -> Bool {
        guard let container = continuation.container, permitsAccessibilityScrollCancellation(of: container),
            accessibilityScrollContinuationIsCurrent(continuation)
        else { return false }
        let nextSequence = pointerSequence.addingReportingOverflow(1)
        guard !nextSequence.overflow else { return false }
        let previousHover = hoveredNode
        let previousIndicator = hoveredScrollIndicatorNode
        let activeIndicator = activeScrollIndicatorNode
        let previousHoverAttachment = previousHover.flatMap { accessibilityTarget(for: $0) }
        let previousIndicatorAttachment = previousIndicator.flatMap { accessibilityTarget(for: $0) }
        guard previousHover == nil || previousHoverAttachment != nil,
            previousIndicator == nil || previousIndicatorAttachment != nil,
            activeIndicator == nil || activeIndicator === container
        else { return false }

        // Publish ownership before any callback or capture can be released.
        // This branch owns only the scroll interaction, never another gesture.
        pointerSequence = nextSequence.partialValue
        continuation.pointerSequence = pointerSequence
        scrollDragState = nil
        activeScrollIndicatorNode = nil
        hoveredNode = nil
        hoveredScrollIndicatorNode = nil
        previousHover?.isHovered = false
        recordOwnedAccessibilityScrollEffects(continuation)

        deliverAccessibilityHoverExit(previousHover)
        guard accessibilityScrollContinuationIsCurrent(continuation),
            previousHoverAttachment?.isCurrent(in: self) ?? true,
            previousIndicatorAttachment?.isCurrent(in: self) ?? true
        else { return false }
        // These chrome helpers use a previously sampled timestamp and contain
        // no application callbacks. Do not reopen the clock after cancellation.
        applyInteractionChrome(to: previousHover, at: timestamp)
        if let previousIndicator {
            animateColor(
                .scrollIndicator, of: previousIndicator, to: previousIndicator.restingScrollIndicatorColor,
                duration: 0.12, at: timestamp)
        }
        recordOwnedAccessibilityScrollEffects(continuation)
        if let activeIndicator {
            recordAccessibilityScrollPhase(.idle, for: activeIndicator, continuation: continuation)
            guard accessibilityScrollContinuationIsCurrent(continuation) else { return false }
            animateColor(
                .scrollIndicator, of: activeIndicator, to: activeIndicator.restingScrollIndicatorColor,
                duration: 0.12, at: timestamp)
            recordOwnedAccessibilityScrollEffects(continuation)
        }
        return accessibilityScrollContinuationIsCurrent(continuation)
    }

    @inline(never)
    private func deliverAccessibilityHoverExit(_ node: ViewNode?) { node?.onPointerExit?() }

    @inline(never)
    private func recordAccessibilityScrollPhase(
        _ phase: RetainedScrollPhase, for node: ViewNode, continuation: RetainedAccessibilityScrollContinuation
    ) {
        // Selecting a changed observation source retires cached Any values.
        // Pin those payloads until scalar phase bookkeeping has finished, then
        // release outside its accesses and validate before any further effect.
        var retiredValues: [Any] = []
        if let registry = scrollObserverRegistry {
            for reference in registry.nodes {
                guard let owner = reference.node, owner.runtime === self,
                    let storage = owner.scrollObserverStorage, !storage.phase.isEmpty
                else { continue }
                for observer in storage.geometry {
                    if let value = observer.previousValue { retiredValues.append(value) }
                }
            }
        }
        recordScrollPhase(phase, for: node)
        recordOwnedAccessibilityScrollEffects(continuation)
        withExtendedLifetime(retiredValues) {}
    }

    /// A valid action supersedes an older reveal even when its selection is
    /// unchanged. Stale handlers never reach this native publication point.
    func didPrepareListNavigationAction(_ receipt: RetainedListNavigationReceipt) {
        latestListNavigationAction = receipt
        if let pendingListNavigationReveal { cancelListNavigationReveal(pendingListNavigationReveal) }
        if let consumingListNavigationReveal { cancelListNavigationReveal(consumingListNavigationReveal) }
    }

    func cancelListNavigationReveal(_ continuation: RetainedListNavigationRevealContinuation) {
        guard continuation.state != .finished else { return }
        let receipt = continuation.receipt
        if pendingListNavigationReveal === continuation { pendingListNavigationReveal = nil }
        if consumingListNavigationReveal === continuation { consumingListNavigationReveal = nil }
        if let container = continuation.container,
            scrollPresentedTweens[ObjectIdentifier(container)]?.listNavigationReveal === continuation
        {
            // Revoking focus ownership does not undo an already accepted
            // visual scroll. A later explicit scroll owns tween cancellation.
            scrollPresentedTweens[ObjectIdentifier(container)]?.listNavigationReveal = nil
        }
        continuation.finish()
        receipt?.cancelReveal()
    }

    /// Original native intent and physical paths, without consulting layout,
    /// providers, selection getters, or the old geometry revision. Ordinary
    /// bounded viewport adoption is allowed to produce a later settlement.
    func isListNavigationRevealCurrent(_ continuation: RetainedListNavigationRevealContinuation) -> Bool {
        guard continuation.state != .finished,
            pendingListNavigationReveal === continuation
                || (consumingListNavigationReveal === continuation && continuation.state == .consuming),
            let receipt = continuation.receipt, latestListNavigationAction === receipt,
            receipt.ownsRevealContinuation(continuation), permitsRetainedActionInvocation,
            let container = continuation.container, let target = continuation.target,
            continuation.targetAttachment.isCurrent(in: self), continuation.containerAttachment.isCurrent(in: self),
            container.scrollAxis == continuation.axis, container.scrollSourceEpoch == continuation.containerEpoch,
            container.scrollOffset == continuation.expectedOffset,
            container.lazyListScrollIntentIdentity === continuation.scrollIntent,
            pointerSequence == continuation.pointerSequence,
            nearestRetainedScrollContainer(of: target) === container,
            !hasActiveScrollInputCapture(for: container), scrollMomenta[ObjectIdentifier(container)] == nil
        else { return false }
        let tween = scrollPresentedTweens[ObjectIdentifier(container)]
        if continuation.hasAnimation && !continuation.animationHasCompleted {
            guard tween?.listNavigationReveal === continuation else { return false }
        } else if tween != nil || container.scrollPresentedDelta != 0 || container.scrollOvershoot != 0 {
            return false
        }
        return true
    }

    /// Ordinary focus invalidates its own paint/chrome fields, but a nested
    /// query, active build, or revoked logical source cannot renew the fixed
    /// terminal settlement that admitted this asynchronous continuation.
    func isListNavigationRevealFocusCurrent(_ continuation: RetainedListNavigationRevealContinuation) -> Bool {
        continuation.state == .consuming && isListNavigationRevealCurrent(continuation)
            && canReadLayoutSettlement && !hasUnresolvedLazyListLayout && !hasUnresolvedLayoutSettlementReader
            && continuation.focusResolutionSequence == layoutSettlementResolutionSequence
            && continuation.focusGeometryRevision == layoutSettlementGeometryRevision
    }

    private func recordOwnedListNavigationRevealFocusEffects(_ receipt: RetainedListNavigationReceipt) {
        guard let continuation = consumingListNavigationReveal, continuation.receipt === receipt else { return }
        guard isListNavigationRevealCurrent(continuation), canReadLayoutSettlement,
            !hasUnresolvedLazyListLayout, !hasUnresolvedLayoutSettlementReader,
            continuation.focusResolutionSequence == layoutSettlementResolutionSequence
        else {
            cancelListNavigationReveal(continuation)
            return
        }
        // Called only at the existing callback-free focus mutation sites.
        // Never update the resolution sequence or borrow a later query's proof.
        continuation.focusGeometryRevision = layoutSettlementGeometryRevision
    }

    private func registerListNavigationReveal(
        receipt: RetainedListNavigationReceipt, target: ViewNode, container: ViewNode, axis: ScrollAxis
    ) -> RetainedListNavigationRevealContinuation? {
        guard receipt.canRegisterRevealContinuation, latestListNavigationAction === receipt,
            let targetAttachment = accessibilityTarget(for: target),
            let containerAttachment = accessibilityTarget(for: container)
        else { return nil }
        let continuation = RetainedListNavigationRevealContinuation(
            receipt: receipt, target: target, container: container,
            targetAttachment: targetAttachment, containerAttachment: containerAttachment,
            axis: axis, pointerSequence: pointerSequence)
        guard receipt.registerRevealContinuation(continuation) else { return nil }
        if let pendingListNavigationReveal { cancelListNavigationReveal(pendingListNavigationReveal) }
        pendingListNavigationReveal = continuation
        return continuation
    }

    func armListNavigationReveal(
        _ continuation: RetainedListNavigationRevealContinuation, target: ViewNode,
        receipt: RetainedListNavigationReceipt
    ) -> Bool {
        guard continuation.receipt === receipt, continuation.target === target,
            receipt.permitsContinuation, isListNavigationRevealCurrent(continuation)
        else { return false }
        return continuation.arm()
    }

    private struct ListNavigationRevealSettlement {
        let continuation: RetainedListNavigationRevealContinuation
        let settlement: RetainedLayoutSettlementReceipt?
    }

    /// Capture before ordinary callbacks. A callback may invalidate this
    /// proof, but a nested query may not lend its replacement proof to us.
    private func captureListNavigationRevealSettlement() -> ListNavigationRevealSettlement? {
        guard !isDrainingListNavigationReveal, let continuation = pendingListNavigationReveal,
            continuation.state == .waiting
        else { return nil }
        let settlement: RetainedLayoutSettlementReceipt?
        if case .settled(let value) = layoutSettlementStatus { settlement = value } else { settlement = nil }
        return ListNavigationRevealSettlement(continuation: continuation, settlement: settlement)
    }

    private func drainListNavigationReveal(
        _ captured: ListNavigationRevealSettlement?, afterRender: Bool = false
    ) {
        guard let captured, pendingListNavigationReveal === captured.continuation else { return }
        _ = completeListNavigationReveal(
            captured.continuation, settlement: captured.settlement, queryingLayout: false, afterRender: afterRender)
    }

    /// False can mean an accepted scroll waiting for ordinary layout/tween
    /// completion. The native slot owns that continuation; callers must never
    /// repeat their binding write or call finishNavigation on it again.
    func completeListNavigationRevealIfReady(
        _ continuation: RetainedListNavigationRevealContinuation, queryingLayout: Bool
    ) -> Bool {
        let settlement: RetainedLayoutSettlementReceipt?
        if case .settled(let value) = layoutSettlementStatus { settlement = value } else { settlement = nil }
        return completeListNavigationReveal(
            continuation, settlement: settlement, queryingLayout: queryingLayout, afterRender: false)
    }

    private func completeListNavigationReveal(
        _ continuation: RetainedListNavigationRevealContinuation,
        settlement capturedSettlement: RetainedLayoutSettlementReceipt?, queryingLayout: Bool, afterRender: Bool
    ) -> Bool {
        guard !isDrainingListNavigationReveal, continuation.state == .waiting,
            pendingListNavigationReveal === continuation
        else { return false }
        guard isListNavigationRevealCurrent(continuation),
            let receipt = continuation.receipt, receipt.permitsPendingRevealContinuation(continuation),
            let target = continuation.target, let container = continuation.container,
            !layoutSettlementGenerationsExhausted
        else {
            cancelListNavigationReveal(continuation)
            return false
        }
        if continuation.hasAnimation {
            guard continuation.animationHasCompleted,
                scrollPresentedTweens[ObjectIdentifier(container)] == nil, afterRender
            else { return false }
        }
        guard canPrepareLayoutSettlement, !hasActiveRetainedBuild,
            !isResolvingLazyListLogicalTarget, !isProbingLazyListScrollTarget
        else { return false }
        isDrainingListNavigationReveal = true
        lazyListScrollWorkDepth += 1
        defer {
            lazyListScrollWorkDepth -= 1
            finishLazyListResolutionBudgetIfIdle()
            isDrainingListNavigationReveal = false
        }
        let settlement = queryingLayout ? queryListNavigationRevealSettlement() : capturedSettlement
        guard isListNavigationRevealCurrent(continuation), receipt.permitsPendingRevealContinuation(continuation) else {
            cancelListNavigationReveal(continuation)
            return false
        }
        guard let settlement, isLayoutSettlementReceiptCurrent(settlement),
            isPresentationNodeAvailable(target, requiresEnabled: false), !isListNavigationTargetDeferred(target)
        else {
            if listNavigationRevealCanWaitForLayout {
                // Paint wakeup only: do not erase a settlement merely to
                // register waiting work, or manufacture another factory budget.
                invalidate(.paint)
            } else {
                cancelListNavigationReveal(continuation)
            }
            return false
        }
        if scrollVisibilityFraction(of: target) <= 0 {
            guard
                let requested = ViewNode.requestedScrollOffset(
                    for: target, within: container, anchor: nil, visibleOffset: container.effectiveScrollOffset),
                container.clampedScrollOffset(for: requested) != container.scrollOffset,
                isListNavigationRevealCurrent(continuation), isLayoutSettlementReceiptCurrent(settlement),
                container.assignScrollOffset(
                    container.clampedScrollOffset(for: requested), admission: nil,
                    continuingListReveal: continuation)
            else {
                cancelListNavigationReveal(continuation)
                return false
            }
            // One native correction from accepted actual geometry. It owns
            // no new tween and can build only on the next ordinary opportunity.
            invalidate(.paint)
            return false
        }
        guard isListNavigationRevealCurrent(continuation), receipt.permitsPendingRevealContinuation(continuation),
            isLayoutSettlementReceiptCurrent(settlement), continuation.take()
        else { return false }
        pendingListNavigationReveal = nil
        consumingListNavigationReveal = continuation
        continuation.focusResolutionSequence = settlement.resolutionSequence
        continuation.focusGeometryRevision = settlement.geometryRevision
        defer {
            if consumingListNavigationReveal === continuation { consumingListNavigationReveal = nil }
            continuation.finish()
        }
        // Refresh only from the fixed, still-current terminal proof, before
        // entering focus. The focus path keeps its existing callback checks.
        receipt.recordGeometryRevision(settlement.geometryRevision)
        return receipt.finishPendingRevealFocus(continuation, target: target, in: self, settlement: settlement)
    }

    private var listNavigationRevealCanWaitForLayout: Bool {
        guard !layoutSettlementGenerationsExhausted, !lazyListUnsupportedThisPass else { return false }
        switch layoutSettlementStatus {
        case .settled:
            // A callback produced a different proof. Require another ordinary
            // opportunity instead of borrowing that callback's settlement.
            return true
        case .unavailable:
            return false
        case .unsettled:
            if hasActiveRetainedBuild || !pendingAfterLayoutActionKeys.isEmpty
                || !pendingPreciseScrollAlignments.isEmpty
            {
                return true
            }
            if hasUnresolvedLazyListLayout {
                return lazyListResolutionBudget?.completion(hasPendingWork: true) == .budgetExhausted
            }
            if case .unsettled = recordedLayoutSettlement { return true }
            return false
        }
    }

    @inline(never)
    private func queryListNavigationRevealSettlement() -> RetainedLayoutSettlementReceipt? {
        guard canPrepareLayoutSettlement else { return nil }
        isResolvingLayoutFrame = true
        updateResolvedLayout()
        isResolvingLayoutFrame = false
        let settlement: RetainedLayoutSettlementReceipt?
        if case .settled(let value) = layoutSettlementStatus { settlement = value } else { settlement = nil }
        deliverListNavigationSettlementCallbacks()
        guard let settlement, isLayoutSettlementReceiptCurrent(settlement) else { return nil }
        return settlement
    }

    @inline(never)
    private func deliverListNavigationSettlementCallbacks() {
        drainPresentationFocusRestorations(layoutIsFresh: true)
        retainedBuildCoordinatorStorage?.retainedCallbacksDidDrain()
    }

    /// A setter may synchronously rebuild the List. Query the actual retained
    /// target once, then validate after layout callbacks and their cleanup.
    func settlePreparedListNavigationTarget(
        _ target: ViewNode, receipt: RetainedListNavigationReceipt
    ) -> RetainedListNavigationReadiness {
        guard receipt.permitsContinuation, target.runtime === self else { return .obsolete }
        guard canPrepareLayoutSettlement, !hasActiveRetainedBuild,
            !isResolvingLazyListLogicalTarget, !isProbingLazyListScrollTarget
        else { return .pending }
        guard queryListNavigationLayout(target), receipt.permitsContinuation else {
            return receipt.permitsContinuation ? .pending : .obsolete
        }
        switch layoutSettlementStatus {
        case .settled(let settlement):
            return isLayoutSettlementReceiptCurrent(settlement) && receipt.permitsContinuation ? .ready : .pending
        case .unsettled:
            return .pending
        case .unavailable:
            return .obsolete
        }
    }

    func prepareListNavigationTarget(_ target: ViewNode, receipt: RetainedListNavigationReceipt) -> Bool {
        guard receipt.permitsContinuation, canPrepareLayoutSettlement,
            queryListNavigationLayout(target), receipt.permitsContinuation,
            case .settled(let settlement) = layoutSettlementStatus,
            isLayoutSettlementReceiptCurrent(settlement), receipt.permitsContinuation,
            receipt.recordPreparedLayoutSettlement(settlement)
        else { return false }
        receipt.recordGeometryRevision(layoutSettlementGeometryRevision)
        return true
    }

    func isListNavigationTargetDeferred(_ target: ViewNode) -> Bool {
        var candidate: ViewNode? = target
        var depth = 0
        while let node = candidate, depth < ViewNode.maximumTraversalDepth {
            if node.isLayoutDeferredByVirtualization { return true }
            if node === root { return false }
            candidate = node.parent
            depth += 1
        }
        return false
    }

    /// The offset has already been accepted. This is one bounded settlement,
    /// not a paint, a UIA Realize, or permission to focus deferred descendants.
    func settleRevealedListNavigationTarget(_ target: ViewNode, receipt: RetainedListNavigationReceipt) -> Bool {
        guard receipt.permitsReveal(in: self, target: target), canPrepareLayoutSettlement,
            queryListNavigationLayout(target),
            receipt.permitsReveal(in: self, target: target),
            case .settled(let settlement) = layoutSettlementStatus,
            isLayoutSettlementReceiptCurrent(settlement),
            receipt.permitsReveal(in: self, target: target),
            isPresentationNodeAvailable(target, requiresEnabled: false),
            !isListNavigationTargetDeferred(target)
        else { return false }
        return true
    }

    @inline(never)
    private func queryListNavigationLayout(_ target: ViewNode) -> Bool {
        resolvedLayoutFrame(of: target) != nil
    }

    func isListNavigationGeometryCurrent(_ receipt: RetainedListNavigationReceipt) -> Bool {
        !layoutSettlementGenerationsExhausted && receipt.geometryRevision == layoutSettlementGeometryRevision
    }

    /// Enqueueing this one reveal invalidates layout itself. Acknowledge only
    /// that owned write, after displaced callback captures finish retiring.
    func scheduleListNavigationReveal(
        key: String, target: ViewNode, receipt: RetainedListNavigationReceipt
    ) {
        guard receipt.permitsReveal(in: self, target: target) else { return }
        let mutationBeforeRetirement = presentationMutationRevision
        let layoutBeforeRetirement = layoutPassID
        let priorIndex = retirePendingListNavigationReveal(key: key)
        guard presentationMutationRevision == mutationBeforeRetirement,
            layoutPassID == layoutBeforeRetirement,
            receipt.permitsReveal(in: self, target: target),
            pendingAfterLayoutActions[key] == nil,
            !pendingAfterLayoutActionKeys.contains(key),
            priorIndex.map({ $0 <= pendingAfterLayoutActionKeys.count }) ?? true
        else {
            receipt.cancelReveal()
            return
        }

        invalidate(.layout)
        receipt.recordGeometryRevision(layoutSettlementGeometryRevision)
        guard receipt.permitsReveal(in: self, target: target) else {
            receipt.cancelReveal()
            return
        }
        pendingAfterLayoutActions[key] = { [receipt, weak self, weak target] in
            guard let self, let target, receipt.permitsReveal(in: self, target: target) else { return }
            _ = self.revealListNavigationTarget(target, receipt: receipt)
        }
        if let priorIndex {
            pendingAfterLayoutActionKeys.insert(key, at: priorIndex)
        } else {
            pendingAfterLayoutActionKeys.append(key)
        }
    }

    @inline(never)
    private func retirePendingListNavigationReveal(key: String) -> Int? {
        let priorIndex = pendingAfterLayoutActionKeys.firstIndex(of: key)
        var displaced = pendingAfterLayoutActions.removeValue(forKey: key)
        pendingAfterLayoutActionKeys.removeAll { $0 == key }
        withExtendedLifetime(displaced) {}
        displaced = nil
        return priorIndex
    }

    package func revealListNavigationTarget(_ target: ViewNode, receipt: RetainedListNavigationReceipt) -> Bool {
        guard receipt.permitsReveal(in: self, target: target) else { return false }
        var transaction = currentTransaction ?? Transaction()
        if currentTransaction == nil, let animation = currentAnimationTransaction {
            transaction.animation = Animation(duration: animation.duration, easing: animation.easing)
        }
        let animation =
            transaction.disablesAnimations
            ? nil
            : transaction.animation.map {
                AnimationTransaction(duration: $0.duration, easing: $0.easing)
            }
        guard let timestamp = listNavigationClock(receipt) else { return false }
        let performed = performProgrammaticScroll(
            to: target, anchorX: nil, anchorY: nil, animation: animation, at: timestamp, listNavigation: receipt)
        return performed && receipt.permitsReveal(in: self, target: target)
    }

    private func listNavigationClock(_ receipt: RetainedListNavigationReceipt) -> Double? {
        let revision = presentationMutationRevision
        let sequence = pointerSequence
        guard revision != UInt64.max else {
            receipt.cancelReveal()
            return nil
        }
        // This existing noninline helper releases the exact sampled callback
        // before any result can authorize a scroll write.
        let timestamp = sampleFocusClock()
        guard presentationMutationRevision == revision, pointerSequence == sequence else {
            receipt.cancelReveal()
            return nil
        }
        return timestamp
    }

    private func permitsListScrollCancellation(of container: ViewNode) -> Bool {
        guard scrollDragState?.node === container || activeScrollIndicatorNode === container else { return true }
        return nodeDragState == nil && longPressAttempt == nil && pressedNode == nil && buttonRepeatState == nil
            && (scrollDragState == nil || scrollDragState?.node === container)
            && (activeScrollIndicatorNode == nil || activeScrollIndicatorNode === container)
    }

    private func listScrollCancellationHasNoReplacement(_ sequence: UInt64) -> Bool {
        pointerSequence == sequence && scrollDragState == nil && activeScrollIndicatorNode == nil
            && hoveredNode == nil && hoveredScrollIndicatorNode == nil
            && nodeDragState == nil && longPressAttempt == nil && pressedNode == nil && buttonRepeatState == nil
    }

    /// Only a matching scroll interaction is cancelled here. Publish cleared
    /// ownership before exit, and never enter legacy pointerCancelled from a
    /// List receipt. Public input and UIA retain their separate paths.
    @inline(never)
    private func cancelListScrollPointer(
        for container: ViewNode, target: ViewNode, receipt: RetainedListNavigationReceipt, at timestamp: Double
    ) -> (sequence: UInt64, mutation: UInt64)? {
        guard permitsListScrollCancellation(of: container), receipt.permitsReveal(in: self, target: target) else {
            return nil
        }
        let next = pointerSequence.addingReportingOverflow(1)
        guard !next.overflow, next.partialValue != UInt64.max else { return nil }
        let previousHover = hoveredNode
        let previousIndicator = hoveredScrollIndicatorNode
        let activeIndicator = activeScrollIndicatorNode

        pointerSequence = next.partialValue
        scrollDragState = nil
        activeScrollIndicatorNode = nil
        hoveredNode = nil
        hoveredScrollIndicatorNode = nil
        previousHover?.isHovered = false
        receipt.recordGeometryRevision(layoutSettlementGeometryRevision)

        let mutationBeforeExit = presentationMutationRevision
        deliverListNavigationHoverExit(previousHover)
        guard presentationMutationRevision == mutationBeforeExit,
            receipt.permitsReveal(in: self, target: target), listScrollCancellationHasNoReplacement(next.partialValue)
        else { return nil }

        applyInteractionChrome(to: previousHover, at: timestamp)
        if let previousIndicator {
            animateColor(
                .scrollIndicator, of: previousIndicator, to: previousIndicator.restingScrollIndicatorColor,
                duration: 0.12, at: timestamp)
        }
        receipt.recordGeometryRevision(layoutSettlementGeometryRevision)
        if let activeIndicator {
            let mutation = recordListNavigationScrollPhase(.idle, for: activeIndicator, receipt: receipt)
            guard presentationMutationRevision == mutation, receipt.permitsReveal(in: self, target: target),
                listScrollCancellationHasNoReplacement(next.partialValue)
            else { return nil }
            animateColor(
                .scrollIndicator, of: activeIndicator, to: activeIndicator.restingScrollIndicatorColor,
                duration: 0.12, at: timestamp)
            receipt.recordGeometryRevision(layoutSettlementGeometryRevision)
        }
        let mutation = presentationMutationRevision
        withExtendedLifetime((previousHover, previousIndicator, activeIndicator)) {}
        // The caller checks this witness after all three node pins retire.
        return (next.partialValue, mutation)
    }

    @inline(never)
    private func deliverListNavigationHoverExit(_ node: ViewNode?) {
        var callback = node?.onPointerExit
        callback?()
        callback = nil
    }

    @inline(never)
    private func recordListNavigationScrollPhase(
        _ phase: RetainedScrollPhase, for node: ViewNode, receipt: RetainedListNavigationReceipt
    ) -> UInt64 {
        var retiredValues: [Any] = []
        if let registry = scrollObserverRegistry {
            for reference in registry.nodes {
                guard let owner = reference.node, owner.runtime === self,
                    let storage = owner.scrollObserverStorage, !storage.phase.isEmpty
                else { continue }
                for observer in storage.geometry {
                    if let value = observer.previousValue { retiredValues.append(value) }
                }
            }
        }
        recordScrollPhase(phase, for: node)
        receipt.recordGeometryRevision(layoutSettlementGeometryRevision)
        let mutation = presentationMutationRevision
        withExtendedLifetime(retiredValues) {}
        // Never acknowledge destruction of an authored Any payload as an
        // owned geometry change. The caller validates after this frame ends.
        return mutation
    }

    @inline(never)
    private func performProgrammaticScroll(
        to descendant: ViewNode,
        anchorX: Double?,
        anchorY: Double?,
        animation: AnimationTransaction?,
        at timestamp: Double,
        accessibility: RetainedAccessibilityScrollContinuation? = nil,
        listNavigation: RetainedListNavigationReceipt? = nil
    ) -> Bool {
        if let listNavigation, !listNavigation.permitsReveal(in: self, target: descendant) { return false }
        guard descendant.runtime === self, layoutPassID != 0, !Self.hasHiddenAncestor(descendant) else {
            return false
        }

        guard let (target, scrollContainer) = descendant.nearestScrollTarget(),
            let axis = scrollContainer.scrollAxis,
            !isLayoutInProgress,
            // Settled queries retain render dirty flags. A deferred List row
            // needs its exact preparation proof before focus; public scrolling
            // and already-realized List rows keep their pending-layout policy.
            accessibility != nil || !hasPendingLayout
                || listNavigation?.permitsPreparedLayoutReveal(in: self, target: descendant) == true,
            scrollContainer.cachedLayoutKey != nil,
            scrollContainer.pendingLayoutKey == nil
        else {
            return false
        }

        if let accessibility {
            guard accessibility.target === target, accessibility.container === scrollContainer,
                permitsAccessibilityScrollCancellation(of: scrollContainer),
                validateAccessibilityScroll(accessibility)
            else { return false }
        }
        if let listNavigation, !permitsListScrollCancellation(of: scrollContainer) {
            listNavigation.cancelReveal()
            return false
        }

        let anchor = axis == .horizontal ? anchorX : anchorY
        guard
            let requestedOffset = ViewNode.requestedScrollOffset(
                for: target,
                within: scrollContainer,
                anchor: anchor,
                visibleOffset: scrollContainer.effectiveScrollOffset
            )
        else {
            return false
        }

        // Retarget from the last presented position, including a keyboard
        // tween or wheel glide that this request interrupts. The logical
        // target changes immediately while every presented consumer shares
        // the lag delta, including the lazy-layout viewport.
        if let listNavigation,
            scrollDragState?.node === scrollContainer || activeScrollIndicatorNode === scrollContainer
        {
            let layoutBeforeCancellation = layoutPassID
            let offsetBeforeCancellation = scrollContainer.scrollOffset
            guard
                let cancelled = cancelListScrollPointer(
                    for: scrollContainer, target: descendant, receipt: listNavigation, at: timestamp),
                presentationMutationRevision == cancelled.mutation,
                listScrollCancellationHasNoReplacement(cancelled.sequence),
                listNavigation.permitsReveal(in: self, target: descendant),
                layoutPassID == layoutBeforeCancellation,
                scrollContainer.scrollOffset == offsetBeforeCancellation,
                scrollContainer.scrollAxis == axis, !isLayoutInProgress,
                !hasPendingLayout || listNavigation.permitsPreparedLayoutReveal(in: self, target: descendant),
                scrollContainer.cachedLayoutKey != nil, scrollContainer.pendingLayoutKey == nil
            else {
                listNavigation.cancelReveal()
                return false
            }
        }
        let presentedOffset = scrollContainer.effectiveScrollOffset
        cancelScrollMomentum(for: scrollContainer)
        cancelScrollPresentedTween(for: scrollContainer)
        // These cancellations touch only owned scalar/weak-node scroll state.
        // A later application callback may not rebase this geometry witness.
        if let accessibility { recordOwnedAccessibilityScrollEffects(accessibility) }
        if listNavigation == nil,
            scrollDragState?.node === scrollContainer || activeScrollIndicatorNode === scrollContainer
        {
            if let accessibility {
                guard cancelAccessibilityScrollPointer(accessibility, at: timestamp),
                    accessibilityScrollContinuationIsCurrent(accessibility)
                else { return false }
            } else {
                pointerCancelled()
            }
        }
        // This proof admits one offset attempt. The later realization query
        // must produce its own settlement; no callback may refresh this proof.
        listNavigation?.consumePreparedLayoutSettlement()
        // A new explicit request supersedes prior intent even when clamping
        // produces the same number and the ordinary setter has no work to do.
        scrollContainer.revokeLazyListScrollIntent()
        _ = scrollContainer.setScrollOffset(requestedOffset)
        accessibility?.expectedOffset = scrollContainer.scrollOffset
        let listReveal: RetainedListNavigationRevealContinuation?
        if let listNavigation, listNavigation.canRegisterRevealContinuation {
            guard
                let continuation = registerListNavigationReveal(
                    receipt: listNavigation, target: descendant, container: scrollContainer, axis: axis)
            else {
                listNavigation.cancelReveal()
                return false
            }
            listReveal = continuation
        } else {
            listReveal = nil
        }
        let delta = presentedOffset - scrollContainer.scrollOffset
        if let animation, animation.duration.isFinite, animation.duration > 0,
            timestamp.isFinite, delta.isFinite, delta != 0
        {
            listReveal?.hasAnimation = true
            scrollContainer.scrollPresentedDelta = delta
            scrollPresentedTweens[ObjectIdentifier(scrollContainer)] = ScrollPresentedTween(
                node: scrollContainer,
                target: descendant,
                startDelta: delta,
                startTime: timestamp,
                lastTime: timestamp,
                duration: animation.duration,
                targetOffset: scrollContainer.scrollOffset,
                scrollLimit: scrollContainer.maxScrollOffset,
                origin: .programmatic(animation.easing),
                listNavigationReveal: listReveal
            )
            if let accessibility {
                invalidate(.paint)
                recordOwnedAccessibilityScrollEffects(accessibility)
                recordAccessibilityScrollPhase(.animating, for: scrollContainer, continuation: accessibility)
            } else if let listNavigation {
                invalidate(.paint)
                let mutation = recordListNavigationScrollPhase(
                    .animating, for: scrollContainer, receipt: listNavigation)
                guard presentationMutationRevision == mutation,
                    listNavigation.permitsReveal(in: self, target: descendant)
                else {
                    listNavigation.cancelReveal()
                    return false
                }
            } else {
                recordScrollPhase(.animating, for: scrollContainer)
                invalidate(.paint)
            }
        } else {
            if let accessibility {
                recordOwnedAccessibilityScrollEffects(accessibility)
                recordAccessibilityScrollPhase(.idle, for: scrollContainer, continuation: accessibility)
            } else if let listNavigation {
                let mutation = recordListNavigationScrollPhase(.idle, for: scrollContainer, receipt: listNavigation)
                guard presentationMutationRevision == mutation,
                    listNavigation.permitsReveal(in: self, target: descendant)
                else {
                    listNavigation.cancelReveal()
                    return false
                }
            } else {
                recordScrollPhase(.idle, for: scrollContainer)
            }
        }
        if let accessibility, !accessibilityScrollContinuationIsCurrent(accessibility) { return false }

        // The next explicit request for a container supersedes any older
        // deferred correction. Once its oversized lazy row is realized, an
        // ID living deeper in that row needs one bounded second alignment to
        // its own now-real frame rather than the row's coarse fallback.
        pendingPreciseScrollAlignments.removeAll {
            $0.container == nil || $0.target == nil || $0.container === scrollContainer
        }
        if target !== descendant, listNavigation?.hasNativeRevealContinuation != true {
            pendingPreciseScrollAlignments.append(
                PendingPreciseScrollAlignment(
                    target: descendant,
                    coarseTarget: target,
                    container: scrollContainer,
                    containerEpoch: scrollContainer.scrollSourceEpoch,
                    anchorX: anchorX,
                    anchorY: anchorY,
                    expectedOffset: scrollContainer.scrollOffset,
                    listNavigation: listNavigation
                )
            )
        }
        accessibility?.expectedOffset = scrollContainer.scrollOffset
        accessibility?.completionRevision = accessibility?.mutation.revision
        listNavigation?.recordGeometryRevision(layoutSettlementGeometryRevision)
        return true
    }

    /// A retained subtree that disappears cannot keep receiving keyboard,
    /// hover, repeat, or drag events merely because application code still
    /// holds one of its nodes alive. This also emits the matching focus/UIA
    /// exit while the removed node is still available to its callbacks.
    fileprivate func releaseInteractionTargets(in subtree: ViewNode) {
        cancelScrollAnimations(in: subtree)
        let ownsPointerInteraction =
            Self.isInteractionTarget(pressedNode, within: subtree)
            || Self.isInteractionTarget(longPressAttempt?.node, within: subtree)
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
            updateFocusTarget(to: nil, origin: .cleanup)
        }
    }

    /// A changed text source invalidates a prepared selection. Queue the
    /// owning editor's next layout without reading bindings or invoking layout
    /// callbacks while that selection is being rejected.
    package func invalidateTextInputLayout(for node: ViewNode, controller: any RetainedTextInputController) {
        guard permitsRenderLifecycleCallbacks, node.runtime === self,
            node.textInputController === controller
        else { return }
        node.markDirty(.layout)
        invalidate(.layout, from: node)
    }

    /// Tests the current retained input scope without exposing facade-specific
    /// command or history types to the renderer-neutral runtime.
    public func permitsTextInputReplay(on node: ViewNode) -> Bool {
        updateResolvedLayout()
        guard node.runtime === self, Self.isInteractionTarget(node, within: root), !Self.hasHiddenAncestor(node) else {
            return false
        }
        return activeModalPresentationNode.map { Self.isInteractionTarget(node, within: $0) } ?? true
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

    fileprivate func longPressConfigurationDidChange(on node: ViewNode) {
        guard let attempt = longPressAttempt, attempt.node === node else { return }
        guard let configuration = node.longPressGesture, configuration.canRecognize, node.isHitTestVisible else {
            finishLongPress(attempt, recognized: false)
            return
        }
        // Keep the original thresholds for this attempt, but deliver its
        // remaining callbacks to the current retained view configuration.
        attempt.configuration = configuration
    }

    /// Property adoption can cancel a held recognizer. Deliver its terminal
    /// callbacks only after the enclosing reconciliation has installed its
    /// children, so a callback's new rebuild cannot be overwritten by it.
    func beginLongPressReconciliation() {
        longPressReconciliationDepth += 1
    }

    func endLongPressReconciliation() {
        longPressReconciliationDepth -= 1
        drainReconciliationCallbacks()
    }

    /// Finishing a build is distinct from ending one nested gesture scope.
    /// In particular, a terminal callback can enqueue another reconciliation
    /// without allowing it to finish the still-running outer callback batch.
    func afterRetainedCallbacks(_ completion: @escaping @MainActor () -> Void) {
        pendingRetainedBuildCompletions.append(completion)
        drainReconciliationCallbacks()
    }

    private func drainReconciliationCallbacks() {
        guard longPressReconciliationDepth == 0, !isDrainingReconciliationCallbacks else { return }
        isDrainingReconciliationCallbacks = true
        defer {
            isDrainingReconciliationCallbacks = false
            retainedBuildCoordinatorStorage?.retainedCallbacksDidDrain()
        }
        while longPressReconciliationDepth == 0 {
            if !pendingLongPressCallbacks.isEmpty {
                let callbacks = pendingLongPressCallbacks
                pendingLongPressCallbacks.removeAll(keepingCapacity: true)
                for callback in callbacks { callback() }
                continue
            }
            guard !pendingRetainedBuildCompletions.isEmpty else { return }
            let completion = pendingRetainedBuildCompletions.removeFirst()
            completion()
        }
    }

    private func performLongPressCallback(_ callback: @escaping @MainActor () -> Void) {
        pendingLongPressCallbacks.append(callback)
        drainReconciliationCallbacks()
    }

    fileprivate func cancelLongPress(in subtree: ViewNode) {
        guard let attempt = longPressAttempt, Self.isInteractionTarget(attempt.node, within: subtree) else {
            return
        }
        finishLongPress(attempt, recognized: false)
    }

    private func beginLongPressIfNeeded(for node: ViewNode?, at point: Point, timestamp: Double) {
        guard let node, node.runtime === self, pressedNode === node, node.isHitTestVisible,
            !Self.hasHiddenAncestor(node),
            let configuration = node.longPressGesture, configuration.canRecognize,
            point.x.isFinite, point.y.isFinite, timestamp.isFinite,
            (timestamp + configuration.minimumDuration).isFinite
        else { return }

        let attempt = LongPressAttempt(node: node, point: point, timestamp: timestamp, configuration: configuration)
        longPressAttempt = attempt
        // A pending hold needs the host's frame timer even when no pixels
        // animate. No registration or traversal is needed on ordinary nodes.
        invalidate(.paint)

        let cleanup = configuration.onBegin? { !attempt.didFinish && self.longPressAttempt === attempt }
        if attempt.didFinish {
            // An updating callback can remove/cancel the node before its
            // cleanup closure is returned. Still retire that update once.
            if let cleanup {
                performLongPressCallback(cleanup)
            }
            return
        }
        attempt.cleanup = cleanup
        guard longPressAttempt === attempt else { return }
        attempt.didNotifyPressing = true
        attempt.configuration.onPressingChanged?(true)
        if longPressAttempt === attempt {
            _ = advanceLongPress(at: clock())
        }
    }

    private func updateLongPressPosition(_ point: Point, at timestamp: Double) {
        guard let attempt = longPressAttempt else { return }
        let distance = hypot(point.x - attempt.startPoint.x, point.y - attempt.startPoint.y)
        guard point.x.isFinite, point.y.isFinite, distance <= attempt.maximumDistance else {
            finishLongPress(attempt, recognized: false)
            return
        }
        _ = advanceLongPress(at: timestamp)
    }

    @discardableResult
    private func advanceLongPress(at timestamp: Double) -> Bool {
        guard let attempt = longPressAttempt else { return false }
        guard !attempt.isCheckingDeadline else { return false }
        guard let node = attempt.node, node.runtime === self, pressedNode === node,
            node.isHitTestVisible, !Self.hasHiddenAncestor(node),
            node.longPressGesture?.canRecognize == true, timestamp.isFinite
        else {
            finishLongPress(attempt, recognized: false)
            return true
        }
        guard timestamp >= attempt.deadline else {
            return false
        }
        attempt.isCheckingDeadline = true
        defer { attempt.isCheckingDeadline = false }
        // Honor the same modal scope as keyboard and wheel routing. Resolve
        // inserted presentations and paint-only ordering changes before
        // recognition, once at the deadline rather than every pending frame.
        if !dirtyFlags.intersection([.layout, .children]).isEmpty {
            updateResolvedLayout()
        } else if dirtyFlags.contains(.paint) {
            updatePrepaintState()
        }
        guard longPressAttempt === attempt else { return true }
        if let modal = activeModalPresentationNode, !Self.isInteractionTarget(node, within: modal) {
            finishLongPress(attempt, recognized: false)
            return true
        }
        finishLongPress(attempt, recognized: true)
        return true
    }

    private func finishLongPress(_ attempt: LongPressAttempt, recognized: Bool) {
        guard !attempt.didFinish else { return }
        attempt.didFinish = true
        if longPressAttempt === attempt {
            longPressAttempt = nil
        }
        let configuration = attempt.configuration
        let cleanup = attempt.cleanup
        attempt.cleanup = nil
        invalidate(.paint)

        // Commit termination before invoking app code. Rebuilds, removal,
        // cancellation, and a new press from a callback cannot finish this
        // attempt twice. The cleanup owns only its original state update.
        performLongPressCallback {
            if attempt.didNotifyPressing {
                configuration.onPressingChanged?(false)
            }
            cleanup?()
            if recognized {
                configuration.onRecognized()
            }
        }
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

    /// A rebuild with the same colour destination must keep the original
    /// tween, just as it does for scalar properties. Re-seeding it here would
    /// prevent a switch's track from ever arriving during frequent updates.
    @discardableResult
    fileprivate func reconcileColor(
        _ property: AnimatedColorProperty, of node: ViewNode, to targetColor: Color,
        animation: AnimationTransaction?, animationsDisabled: Bool,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        let key = ColorAnimationKey(node: node, property: property)
        if !animationsDisabled, colorAnimations[key]?.endColor == targetColor { return true }
        if !animationsDisabled, property == .background, let running = colorAnimations[key],
            let surface = node.interactionSurface,
            surface.background(for: interactionPhase(for: node)) == running.endColor
        {
            return true
        }
        guard node.color(for: property) != targetColor else {
            admission?.markMutationStarted()
            colorAnimations.removeValue(forKey: key)
            return true
        }
        if let animation, animation.duration > 0, !animationsDisabled {
            let timestamp: Double
            if let admission {
                let attachment = node.captureLazyListAttachmentProof()
                guard let currentTime = node.reconciliationAnimationTime(admission: admission),
                    admission.isCurrent, attachment.isCurrent
                else { return false }
                timestamp = currentTime
            } else {
                // Preserve the ordinary runtime clock, including its original
                // ownership if an unguarded caller supplied a detached node.
                timestamp = clock()
            }
            guard nativeCheck?.isCurrent != false else { return false }
            admission?.markMutationStarted()
            animateColor(
                property, of: node, to: targetColor, duration: animation.duration,
                at: timestamp, easing: animation.easing)
        } else {
            admission?.markMutationStarted()
            colorAnimations.removeValue(forKey: key)
            if node.color(for: property) != targetColor { node.setColor(targetColor, for: property) }
        }
        return admission?.isCurrent != false && nativeCheck?.isCurrent != false
    }

    fileprivate func cancelColorAnimation(_ property: AnimatedColorProperty, of node: ViewNode) {
        guard !colorAnimations.isEmpty else { return }
        colorAnimations.removeValue(forKey: ColorAnimationKey(node: node, property: property))
    }

    fileprivate func cancelColorAnimations(of node: ViewNode) {
        guard !colorAnimations.isEmpty else { return }
        let identifier = ObjectIdentifier(node)
        for key in Array(colorAnimations.keys) where key.nodeIdentifier == identifier {
            colorAnimations.removeValue(forKey: key)
        }
    }

    @discardableResult
    public func tickAnimations(at timestamp: Double) -> Bool {
        defer { refreshScrollObservationPhases() }
        // First, because a due rebuild produces the tree the rest of this tick
        // advances — a phase boundary that landed this frame should be animated
        // from this frame, not from the next one.
        let didRunDeferredRebuild = tickDeferredRebuilds(at: timestamp)
        let didAdvanceLongPress = advanceLongPress(at: timestamp)
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
        if didAdvanceOverlayAnimations || !completedOverlays.isEmpty {
            // Removal overlays are detached from the live tree, so their
            // property observers cannot invalidate this runtime. Without
            // this, a removal replays the cached scene until its final tick.
            invalidate(.paint)
        }

        guard !colorAnimations.isEmpty else {
            return didRunDeferredRebuild || didAdvanceLongPress || didAdvanceButtonRepeat || didAdvanceScrollMomenta
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

        return didUpdateAnyAnimation || didRunDeferredRebuild || didAdvanceLongPress || didAdvanceButtonRepeat
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
        guard node.acceptsScrollInput, appliedOffsetDelta.isFinite, appliedOffsetDelta != 0 else {
            return
        }

        // Sign: applyMouseWheelDelta moves offset by `-wheelDelta * scrollStep`,
        // so positive wheelDelta produces a negative velocity (offset shrinks).
        // Use the actual applied delta so we don't accumulate velocity against
        // a clamped edge.
        let impulse = appliedOffsetDelta * Self.scrollMomentumImpulseFactor
        guard impulse.isFinite else { return }
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
        invalidate(.paint)
    }

    /// Cancels any pending wheel momentum on `node`. Called when the user
    /// takes manual control (keyboard scroll, indicator drag) so momentum
    /// doesn't fight the user input. Also zeros any rubber-band overshoot so
    /// content snaps back to the clamped offset instead of staying overscrolled.
    fileprivate func cancelScrollMomentum(for node: ViewNode) {
        scrollMomenta.removeValue(forKey: ObjectIdentifier(node))
        if node.scrollOvershoot != 0 {
            node.scrollOvershoot = 0
        }
    }

    fileprivate func hasActiveScrollInputCapture(for node: ViewNode) -> Bool {
        scrollDragState?.node === node || activeScrollIndicatorNode === node
    }

    @discardableResult
    fileprivate func disableScrollInput(
        for node: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        let attachment = admission == nil ? nil : node.captureLazyListAttachmentProof()
        // Freeze an in-flight keyboard tween or glide where the content is
        // currently presented, rather than exposing its logical target when
        // the presentation delta is cleared. Rubber-band space is clamped
        // back into the scrollable content when input is disabled.
        let presentedOffset = node.effectiveScrollOffset
        let hasProgrammaticTween = scrollPresentedTweens[ObjectIdentifier(node)]?.origin.isProgrammatic == true
        cancelScrollMomentum(for: node)
        if !hasProgrammaticTween {
            cancelScrollPresentedTween(for: node, cancelsPendingAlignment: false)
            let nextOffset = node.clampedScrollOffset(for: presentedOffset)
            if nextOffset != node.scrollOffset,
                !node.assignScrollOffset(nextOffset, admission: admission, nativeCheck: nativeCheck)
            {
                return false
            }
        }
        guard admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
        else { return false }
        if scrollDragState?.node === node || activeScrollIndicatorNode === node {
            // Offset observers above can start a new interaction. Legacy
            // cancellation does not carry checked admission through its
            // hover, phase, clock, and chrome callbacks; never enter it here.
            guard admission == nil, nativeCheck == nil else { return false }
            pointerCancelled()
        }
        guard admission?.isCurrent != false, attachment?.isCurrent != false, nativeCheck?.isCurrent != false
        else { return false }
        return recordScrollPhase(
            hasProgrammaticTween ? .animating : .idle, for: node, admission: admission, nativeCheck: nativeCheck)
    }

    /// Drops any in-flight presented scroll tween for `node` so the next
    /// imperative offset change isn't double-counted with stale lag.
    fileprivate func cancelScrollPresentedTween(
        for node: ViewNode,
        preservingPresentation: Bool = false,
        cancelsPendingAlignment: Bool = true
    ) {
        if let pendingListNavigationReveal, pendingListNavigationReveal.container === node {
            cancelListNavigationReveal(pendingListNavigationReveal)
        }
        if let consumingListNavigationReveal, consumingListNavigationReveal.container === node {
            cancelListNavigationReveal(consumingListNavigationReveal)
        }
        if cancelsPendingAlignment {
            pendingPreciseScrollAlignments.removeAll {
                $0.container === node || $0.container == nil || $0.target == nil
            }
        }
        if scrollPresentedTweens.removeValue(forKey: ObjectIdentifier(node)) != nil {
            let presentedOffset = node.scrollOffset + node.scrollPresentedDelta
            node.scrollPresentedDelta = 0
            if preservingPresentation {
                _ = node.setScrollOffset(presentedOffset)
            }
        }
    }

    @discardableResult
    fileprivate func cancelProgrammaticScrollIfTargetChanged(
        for node: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, nativeCheck?.isCurrent != false else { return false }
        if let pendingListNavigationReveal, pendingListNavigationReveal.container === node,
            node.scrollOffset != pendingListNavigationReveal.expectedOffset
                || node.lazyListScrollIntentIdentity !== pendingListNavigationReveal.scrollIntent
        {
            cancelListNavigationReveal(pendingListNavigationReveal)
        }
        if let consumingListNavigationReveal, consumingListNavigationReveal.container === node,
            node.scrollOffset != consumingListNavigationReveal.expectedOffset
                || node.lazyListScrollIntentIdentity !== consumingListNavigationReveal.scrollIntent
        {
            cancelListNavigationReveal(consumingListNavigationReveal)
        }
        guard let tween = scrollPresentedTweens[ObjectIdentifier(node)],
            tween.origin.isProgrammatic, node.scrollOffset != tween.targetOffset
        else { return true }
        cancelScrollPresentedTween(for: node)
        return recordScrollPhase(.idle, for: node, admission: admission, nativeCheck: nativeCheck)
    }

    private func settleProgrammaticScrollRangeChanges() -> Bool {
        var didCancel = false
        for key in Array(scrollPresentedTweens.keys) {
            guard var tween = scrollPresentedTweens[key], tween.origin.isProgrammatic,
                let node = tween.node, node.runtime === self
            else { continue }
            let limit = node.maxScrollOffset
            guard limit != tween.scrollLimit else { continue }
            let previousLimit = tween.scrollLimit
            tween.scrollLimit = limit
            scrollPresentedTweens[key] = tween

            // Use the prior logical target with its lag, not the newly
            // clamped target: mixing the new limit with the old lag can
            // produce negative presentation after a viewport/content resize.
            let presentedOffset = tween.targetOffset + node.scrollPresentedDelta
            guard limit < previousLimit,
                node.clampedScrollOffset(for: tween.targetOffset) != tween.targetOffset
                    || node.clampedScrollOffset(for: presentedOffset) != presentedOffset
            else { continue }
            cancelScrollPresentedTween(for: node)
            _ = node.setScrollOffset(presentedOffset)
            recordScrollPhase(.idle, for: node)
            didCancel = true
        }
        return didCancel
    }

    private func cancelScrollAnimations(in subtree: ViewNode) {
        pendingPreciseScrollAlignments.removeAll {
            $0.target == nil || $0.container == nil
                || Self.isInteractionTarget($0.target, within: subtree)
                || Self.isInteractionTarget($0.container, within: subtree)
        }
        for state in Array(scrollMomenta.values) {
            if let node = state.node, Self.isInteractionTarget(node, within: subtree) {
                cancelScrollMomentum(for: node)
            }
        }
        for tween in Array(scrollPresentedTweens.values) {
            if let node = tween.node {
                if Self.isInteractionTarget(node, within: subtree) {
                    cancelScrollPresentedTween(for: node)
                } else if Self.isInteractionTarget(tween.target, within: subtree) {
                    cancelScrollPresentedTween(for: node, preservingPresentation: true)
                    recordScrollPhase(.idle, for: node)
                }
            }
        }
    }

    private static func advancedScrollRubberBand(
        overshoot: Double, velocity: Double, elapsed: Double
    ) -> (overshoot: Double, velocity: Double) {
        // Exact solution of x'' + c*x' + k*x = 0. These constants are
        // slightly overdamped, with two distinct negative real roots.
        let halfDamping = scrollRubberBandDamping * 0.5
        let discriminant = sqrt(halfDamping * halfDamping - scrollRubberBandStiffness)
        let slowRate = -halfDamping + discriminant
        let fastRate = -halfDamping - discriminant
        let slowAmplitude = (velocity - fastRate * overshoot) / (slowRate - fastRate)
        let fastAmplitude = overshoot - slowAmplitude
        let slowPart = slowAmplitude * exp(slowRate * elapsed)
        let fastPart = fastAmplitude * exp(fastRate * elapsed)
        return (slowPart + fastPart, slowRate * slowPart + fastRate * fastPart)
    }

    private func tickScrollMomenta(at timestamp: Double) -> Bool {
        guard !scrollMomenta.isEmpty, timestamp.isFinite else { return false }

        var didUpdate = false
        for key in Array(scrollMomenta.keys) {
            guard var state = scrollMomenta[key] else { continue }
            guard let node = state.node, node.runtime === self else {
                scrollMomenta.removeValue(forKey: key)
                continue
            }
            guard node.acceptsScrollInput, !Self.hasHiddenAncestor(node) else {
                didUpdate = didUpdate || node.scrollOvershoot != 0
                cancelScrollMomentum(for: node)
                continue
            }

            let dt = timestamp - state.lastTime
            guard dt > 0 else {
                // A repeated or delayed frame cannot rewind the integration
                // clock and make the next valid frame apply the same time twice.
                continue
            }

            if state.rubberBandDisplacement != nil || node.scrollOvershoot != 0 {
                // Integrate the slightly overdamped spring analytically.
                // Euler steps made a 50ms frame return almost twice as far
                // as three 60Hz frames and kept old motion alive after pauses.
                let previousOvershoot = state.rubberBandDisplacement ?? node.scrollOvershoot
                let spring = Self.advancedScrollRubberBand(
                    overshoot: previousOvershoot, velocity: state.velocity, elapsed: dt)
                let nextOvershoot = spring.overshoot
                state.velocity = spring.velocity
                // Snap to zero once the spring has settled and would otherwise
                // oscillate across the bound.
                let crossedZero = previousOvershoot != 0 && (nextOvershoot > 0) != (previousOvershoot > 0)
                if crossedZero
                    || (abs(nextOvershoot) < Self.scrollMomentumEpsilon * 0.1
                        && abs(state.velocity) < Self.scrollMomentumEpsilon)
                {
                    node.scrollOvershoot = 0
                    scrollMomenta.removeValue(forKey: key)
                    didUpdate = true
                    continue
                }
                node.scrollOvershoot = max(min(nextOvershoot, Self.scrollRubberBandMax), -Self.scrollRubberBandMax)
                state.rubberBandDisplacement = nextOvershoot
                state.lastTime = timestamp
                scrollMomenta[key] = state
                didUpdate = true
                continue
            }

            let speed = abs(state.velocity)
            guard speed > Self.scrollMomentumEpsilon else {
                scrollMomenta.removeValue(forKey: key)
                continue
            }
            // Integrating v(t) gives the same travel at every refresh rate.
            // Stop exactly at the velocity threshold, including across a long
            // frame gap, instead of replaying an old glide when focus returns.
            let timeToRest = log(speed / Self.scrollMomentumEpsilon) / Self.scrollMomentumDecay
            let travelTime = min(dt, timeToRest)
            let attenuation = exp(-Self.scrollMomentumDecay * travelTime)
            let initialVelocity = state.velocity
            let distance = initialVelocity * (1 - attenuation) / Self.scrollMomentumDecay
            state.velocity *= attenuation
            let previousOffset = node.scrollOffset
            let proposedOffset = previousOffset + distance
            let nextOffset = node.clampedScrollOffset(for: proposedOffset)
            if nextOffset != previousOffset {
                node.scrollOffset = nextOffset
                didUpdate = true
            }

            // Resolve the exact time of contact with a bound, then integrate
            // the spring for the rest of this frame. Starting it only on the
            // next tick made edge motion depend on refresh rate and revived
            // a bounce after a long inactive gap.
            if proposedOffset != nextOffset {
                let contactAttenuation = min(
                    1,
                    max(
                        attenuation,
                        1 - Self.scrollMomentumDecay * (nextOffset - previousOffset) / initialVelocity))
                let contactTime = -log(contactAttenuation) / Self.scrollMomentumDecay
                let spring = Self.advancedScrollRubberBand(
                    overshoot: 0, velocity: initialVelocity * contactAttenuation,
                    elapsed: max(0, dt - contactTime))
                state.velocity = spring.velocity
                if abs(spring.overshoot) < Self.scrollMomentumEpsilon * 0.1,
                    abs(state.velocity) < Self.scrollMomentumEpsilon
                {
                    node.scrollOvershoot = 0
                    scrollMomenta.removeValue(forKey: key)
                    continue
                }
                node.scrollOvershoot = max(min(spring.overshoot, Self.scrollRubberBandMax), -Self.scrollRubberBandMax)
                state.rubberBandDisplacement = spring.overshoot
                state.lastTime = timestamp
                scrollMomenta[key] = state
                didUpdate = true
                continue
            }

            state.lastTime = timestamp
            if dt >= timeToRest {
                scrollMomenta.removeValue(forKey: key)
            } else {
                scrollMomenta[key] = state
            }
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
            let value = state.interpolatedValue(at: timestamp)
            // Zero means an automatic extent in the retained layout model.
            // A spring between positive fixed sizes can undershoot zero, but
            // that must collapse visually without releasing its fixed-size
            // constraint and expanding to the parent's proposal.
            let minimumDimension = state.startValue > 0 && state.endValue > 0 ? Double.leastNormalMagnitude : 0
            let dimensionValue = max(minimumDimension, value)

            switch property {
            case .opacity:
                let opacity = min(1, max(0, value))
                if node.opacity != opacity {
                    node.opacity = opacity
                    didUpdate = true
                }
            case .outlineWidth:
                let width = max(0, value)
                if node.outlineWidth != width {
                    node.outlineWidth = width
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
                let newSize = Size(width: dimensionValue, height: node.frame.size.height)
                let newFrame = Rect(origin: node.frame.origin, size: newSize)
                if node.frame != newFrame {
                    node.frame = newFrame
                    node.resolvedFrame.size.width = newSize.width
                    didUpdate = true
                }
            case .frameHeight:
                let newSize = Size(width: node.frame.size.width, height: dimensionValue)
                let newFrame = Rect(origin: node.frame.origin, size: newSize)
                if node.frame != newFrame {
                    node.frame = newFrame
                    node.resolvedFrame.size.height = newSize.height
                    didUpdate = true
                }
            case .preferredWidth:
                if var size = node.preferredSize, size.width != dimensionValue {
                    size.width = dimensionValue
                    node.preferredSize = size
                    didUpdate = true
                }
            case .preferredHeight:
                if var size = node.preferredSize, size.height != dimensionValue {
                    size.height = dimensionValue
                    node.preferredSize = size
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

            if state.isComplete(at: timestamp) {
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

    /// Closing a host revokes future render callbacks without delivering any
    /// lifecycle or releasing application payloads. A retained runtime can
    /// still be inspected after its host has gone away.
    package var permitsRetainedActionInvocation: Bool { permitsRenderLifecycleCallbacks }

    package func beginAccessibilityMutation() -> RetainedAccessibilityMutation? {
        guard activeAccessibilityMutation == nil, permitsRenderLifecycleCallbacks,
            canReadLayoutSettlement, !isUpdatingResolvedLayout, !isResolvingPresentationAction
        else {
            return nil
        }
        let mutation = RetainedAccessibilityMutation()
        activeAccessibilityMutation = mutation
        return mutation
    }

    package func endAccessibilityMutation(_ mutation: RetainedAccessibilityMutation) {
        guard activeAccessibilityMutation === mutation else { return }
        activeAccessibilityMutation = nil
    }

    /// Admission and continuation are separate from public scrolling and focus.
    /// Reading this never settles layout or invokes an application callback.
    package func isAccessibilityMutationCurrent(_ mutation: RetainedAccessibilityMutation) -> Bool {
        activeAccessibilityMutation === mutation && !mutation.isExhausted
            && permitsRenderLifecycleCallbacks && canReadLayoutSettlement
            && !isUpdatingResolvedLayout && !isResolvingPresentationAction
    }

    package func accessibilityTarget(for node: ViewNode) -> RetainedAccessibilityTarget? {
        var path: [RetainedAccessibilityTarget.Link] = []
        var candidate: ViewNode? = node
        while let current = candidate, path.count < ViewNode.maximumTraversalDepth {
            guard current.runtime === self else { return nil }
            path.append(.init(node: current, identity: current.accessibilityAttachmentIdentity))
            if current === root { return RetainedAccessibilityTarget(node: node, path: path) }
            guard let parent = current.parent, parent.children.contains(where: { $0 === current }) else { return nil }
            candidate = parent
        }
        return nil
    }

    package func isAccessibilityTargetCurrent(
        _ target: RetainedAccessibilityTarget, during mutation: RetainedAccessibilityMutation
    ) -> Bool {
        isAccessibilityMutationCurrent(mutation) && target.isCurrent(in: self)
    }

    /// A callback-free continuation check for an already-admitted editor
    /// mutation. Every physical modal must enclose the target, deliberately
    /// refusing sibling modal stacks instead of guessing new paint order.
    /// This reads stored state only; it never resolves layout or projection.
    package func permitsConservativeAccessibilityValueTarget(_ node: ViewNode) -> Bool {
        guard let ancestors = Self.valueAncestorIDs(of: node, root: root) else { return false }
        return Self.hasNoCompetingValueModal(in: root, ancestors: ancestors)
    }

    private static func valueAncestorIDs(of node: ViewNode, root: ViewNode) -> Set<ObjectIdentifier>? {
        var ancestors: Set<ObjectIdentifier> = []
        var candidate: ViewNode? = node
        while let current = candidate, ancestors.count < ViewNode.maximumTraversalDepth {
            guard ancestors.insert(ObjectIdentifier(current)).inserted,
                !current.isHidden, !current.isAccessibilityHidden, !current.isRemovalOverlay,
                !current.isLayoutDeferredByVirtualization, current.accessibilityRespondsToUserInteraction != false
            else { return nil }
            if current === root { return root.parent == nil ? ancestors : nil }
            candidate = current.parent
        }
        return nil
    }

    /// A callback can install an accessibility-hidden modal without moving
    /// focus. The tree-only accessibility projection omits such a modal; the
    /// input runtime does not. Conservatively require every physical modal to
    /// enclose this target, including clipped, hidden, and deferred scopes.
    /// This refuses sibling modal stacks rather than guessing new paint order.
    private static func hasNoCompetingValueModal(in root: ViewNode, ancestors: Set<ObjectIdentifier>) -> Bool {
        var pending: [(node: ViewNode, depth: Int)] = [(root, 0)]
        var visited: Set<ObjectIdentifier> = []
        while let entry = pending.popLast() {
            guard entry.depth < ViewNode.maximumTraversalDepth,
                visited.insert(ObjectIdentifier(entry.node)).inserted
            else { return false }
            if entry.node.isModalPresentationScope, !ancestors.contains(ObjectIdentifier(entry.node)) { return false }
            for child in entry.node.children {
                guard child.parent === entry.node else { return false }
                pending.append((child, entry.depth + 1))
            }
        }
        return true
    }

    /// Callers choose a bounded query point, then recheck their original target
    /// and handler witnesses. A successful query does not authorize a new node.
    @inline(never)
    package func prepareAccessibilityMutation(_ mutation: RetainedAccessibilityMutation) -> Bool {
        guard isAccessibilityMutationCurrent(mutation), resolvedLayoutFrame(of: root) != nil,
            isAccessibilityMutationCurrent(mutation), case .settled = layoutSettlementStatus,
            hasCurrentAccessibilityPrepaint
        else { return false }
        return true
    }

    /// Focus restoration can publish callbacks after a query records prepaint.
    /// Read this after the query, before invoking a retained accessibility action.
    var hasCurrentAccessibilityPrepaint: Bool {
        presentationPrepaintRevision == presentationMutationRevision
    }

    /// This terminal revocation also prevents retained accessibility actions
    /// from entering application code through the still-inspectable tree.
    public func stopRenderLifecycleCallbacks() {
        lazyListLogicalHostLifetime.revoke()
        permitsRenderLifecycleCallbacks = false
        lazyListAccessibilityPreparation?.isActive = false
        lazyListAccessibilityPreparation = nil
        if let pendingListNavigationReveal { cancelListNavigationReveal(pendingListNavigationReveal) }
        if let consumingListNavigationReveal { cancelListNavigationReveal(consumingListNavigationReveal) }
        renderLifecycleRevision &+= 1
        pendingLazyListAnchorClamps = [:]
        lazyListAnchorNeedsLayout = false
        for registration in lazyListRegistrations.values { registration.adapter?.revokePendingCandidate() }
        for request in pendingPresentationFocusRequests { request.revoke() }
        var nodes = [root] + transitionOverlays
        var visited = Set<ObjectIdentifier>()
        while let node = nodes.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            nodes.append(contentsOf: node.children)
            node.listNavigationOwner?.revoke()
        }
        // Also retire a slot already removed from an ordinary queue for
        // delivery, or whose stale scope no longer appears in the live tree.
        let replayOwners = preparedListNavigationReplays.values.map(\.owner)
        for owner in replayOwners { cancelPreparedListNavigationReplay(owner: owner) }
    }

    /// Cancel a closed host's tasks only after its editor and State writes
    /// have been revoked: cancellation handlers can synchronously reenter app
    /// code. Clear every owned task slot before the first handler runs, without
    /// synthesizing disappearance, focus changes, or platform callbacks.
    public func cancelRenderLifecycleTasks() {
        renderLifecycleTaskCancellationDepth += 1
        if renderLifecycleTaskCancellationDepth == 1 { hasFinishedRenderLifecycleTaskCancellation = false }
        let navigationRetirements = retiredPreparedListNavigationRetirements
        retiredPreparedListNavigationRetirements.removeAll()
        let groupTaskCleanup = ViewNode.claimLazyGroupTaskDepartures(in: [root] + transitionOverlays)
        let focusRequests = pendingPresentationFocusRequests
        for request in focusRequests { request.revoke() }
        pendingPresentationFocusRequests.removeAll()
        var nodes = [root] + transitionOverlays
        var visited = Set<ObjectIdentifier>()
        var tasks: [Task<Void, Never>] = []
        var scopedRetirements: [RetainedTaskRetirement] = []
        while let node = nodes.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            nodes.append(contentsOf: node.children)
            tasks.append(contentsOf: node.takeLifecycleTasks(retiring: true))
            if let state = node.existingRetainedTaskState {
                scopedRetirements.append(state.takeForTerminal())
            }
        }
        for request in focusRequests { request.finish() }
        for task in tasks { task.cancel() }
        for retirement in scopedRetirements { retirement.cancel() }
        for cleanup in groupTaskCleanup { cleanup.finish() }
        withExtendedLifetime(scopedRetirements) {}
        renderLifecycleTaskCancellationDepth -= 1
        guard renderLifecycleTaskCancellationDepth == 0 else {
            // A cancellation handler may request task cleanup again. Its
            // nested return cannot release payloads before the outer batch
            // finishes the task retirements that were already claimed.
            retiredPreparedListNavigationRetirements =
                navigationRetirements + retiredPreparedListNavigationRetirements
            return
        }
        hasFinishedRenderLifecycleTaskCancellation = !permitsRenderLifecycleCallbacks
        // Task cleanup can reenter and retire another replay. Publish the
        // completed native cleanup phase before releasing either batch.
        let reentrantNavigationRetirements = retiredPreparedListNavigationRetirements
        retiredPreparedListNavigationRetirements.removeAll()
        schedulePreparedListNavigationRetirements(navigationRetirements + reentrantNavigationRetirements)
    }

    /// An accepted rebuild can retain a node while replacing its callbacks and
    /// geometry. Its old lifecycle snapshot must not run on the new build.
    func invalidateRenderLifecycleCandidates() {
        activeAccessibilityMutation?.recordMutation()
        presentationMutationRevision &+= 1
        if isDeliveringRenderLifecycleCallbacks { renderLifecycleRevision &+= 1 }
    }

    fileprivate func canDeliverRenderLifecycle(to node: ViewNode) -> Bool {
        guard permitsRenderLifecycleCallbacks, node.runtime === self else { return false }
        var current: ViewNode? = node
        var depth = 0
        while let candidate = current, depth < ViewNode.maximumTraversalDepth {
            guard !candidate.isHidden, !candidate.isRemovalOverlay, !candidate.isLayoutDeferredByVirtualization
            else { return false }
            if candidate === root { return true }
            current = candidate.parent
            depth += 1
        }
        return false
    }

    fileprivate func isDeliveringRetainedTaskAppearance(revision: UInt64) -> Bool {
        isDeliveringRenderLifecycleCallbacks && renderLifecycleRevision == revision
    }

    /// Both presentation paths enter here after layout has settled. Neither a
    /// hit-test/layout query nor a painter's atlas retry or isolated recording
    /// is a new appearance. Paint cache replay cannot bypass this stage.
    private func deliverRenderLifecycleCallbacks(ownsRenderPass: Bool) {
        guard ownsRenderPass, permitsRenderLifecycleCallbacks else { return }
        guard !hasActiveRetainedBuild, !isLayoutInProgress, !isResolvingLayoutFrame else {
            // A completion may render while its build still owns the guard.
            // Keep a normal follow-up render pending even if its pixels cache.
            invalidate(.layout)
            return
        }
        isDeliveringRenderLifecycleCallbacks = true
        defer { isDeliveringRenderLifecycleCallbacks = false }
        let revision = renderLifecycleRevision
        var candidates: [ViewNode.RenderLifecycleCandidate] = []
        root.appendRenderLifecycleCandidates(into: &candidates, parentOrigin: .zero, inheritedClip: nil)
        for index in orderedDeferredDrawIndices(prepaintState.deferredDraws) {
            guard case .subtree(let payload) = prepaintState.deferredDraws[index].payload,
                let node = payload.node
            else { continue }
            node.appendRenderLifecycleCandidates(
                into: &candidates, parentOrigin: payload.parentOrigin, inheritedClip: payload.inheritedClip,
                inheritedOpacity: payload.inheritedOpacity, inheritedTransform: payload.inheritedTransform)
        }
        var delivered = Set<ObjectIdentifier>()
        for candidate in candidates {
            guard permitsRenderLifecycleCallbacks else { return }
            guard renderLifecycleRevision == revision else {
                // Application callbacks may synchronously rebuild, move, or
                // remove the rest of this snapshot. Resolve the new tree on a
                // later pass instead of delivering its stale frames/callbacks.
                invalidate(.layout)
                return
            }
            guard let node = candidate.node, delivered.insert(ObjectIdentifier(node)).inserted else { continue }
            node.fireRenderLifecycleCallbacks(absoluteFrame: candidate.absoluteFrame, in: self)
        }
        if permitsRenderLifecycleCallbacks, renderLifecycleRevision != revision {
            invalidate(.layout)
        }
    }

    fileprivate func invalidate(_ flags: DirtyFlags = .all) {
        recordLayoutSettlementInvalidation(flags)
        advanceTextInputReplayScopeRevision(&textInputReplayScopeRevision)
        invalidateRenderLifecycleCandidates()
        guard isRendering else {
            dirtyFlags.insert(flags)
            return
        }
        pendingDirtyFlags.insert(flags)
    }

    fileprivate func invalidate(_ flags: DirtyFlags, from node: ViewNode) {
        recordLayoutSettlementInvalidation(flags)
        advanceTextInputReplayScopeRevision(&textInputReplayScopeRevision)
        if isDrainingAfterLayoutActions, !flags.intersection([.layout, .children]).isEmpty {
            afterLayoutGeometryInvalidations.append(WeakViewNodeRef(node: node))
        }
        invalidateRenderLifecycleCandidates()
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
        // Layout, after-layout work, and lifecycle callbacks in this owned
        // render borrow one construction budget. An onAppear scroll request
        // must not obtain another full budget after the initial layout ends.
        lazyListScrollWorkDepth += 1
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
        defer {
            lazyListScrollWorkDepth -= 1
            finishLazyListResolutionBudgetIfIdle()
        }
        isRendering = false
        for pending in pendingDirtyNodes {
            pending.node.node?.markDirty(pending.flags)
        }
        pendingDirtyNodes.removeAll(keepingCapacity: true)
        dirtyFlags = pendingDirtyFlags
        pendingDirtyFlags = []
        if let registry = scrollObserverRegistry, registry.isDelivering {
            registry.renderedDuringDelivery = true
        }
        let reveal = captureListNavigationRevealSettlement()
        deliverScrollObservations()
        drainPresentationFocusRestorations(layoutIsFresh: true)
        retainedBuildCoordinatorStorage?.retainedCallbacksDidDrain()
        drainListNavigationReveal(reveal, afterRender: true)
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
        previousFrame: FramePaintSnapshot?,
        snapshotIdentity: PaintSnapshotIdentity,
        displayScale: Double,
        replayCount: inout Int
    ) {
        for deferredDrawIndex in orderedDeferredDrawIndices(prepaintState.deferredDraws) {
            let startCommandIndex = commands.count
            if let previousFrame,
                prepaintState.deferredDraws[deferredDrawIndex].cachedFrameSnapshotIdentity == previousFrame.identity,
                let cachedFrameCommandRange = prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange,
                cachedFrameCommandRange.lowerBound >= 0,
                cachedFrameCommandRange.upperBound <= previousFrame.frame.commands.count
            {
                commands.append(contentsOf: previousFrame.frame.commands[cachedFrameCommandRange])
                if case .subtree(let payload) = prepaintState.deferredDraws[deferredDrawIndex].payload {
                    payload.node?.shiftCachedFrameRangesRecursively(
                        by: startCommandIndex - cachedFrameCommandRange.lowerBound,
                        from: previousFrame.identity, to: snapshotIdentity)
                }
                prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange =
                    startCommandIndex..<commands.count
                prepaintState.deferredDraws[deferredDrawIndex].cachedFrameSnapshotIdentity = snapshotIdentity
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
                    prepaintState.deferredDraws[deferredDrawIndex].cachedFrameSnapshotIdentity = snapshotIdentity
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
                    snapshotIdentity: snapshotIdentity,
                    displayScale: displayScale,
                    replayCount: &replayCount
                )
            }

            prepaintState.deferredDraws[deferredDrawIndex].cachedFrameCommandRange = startCommandIndex..<commands.count
            prepaintState.deferredDraws[deferredDrawIndex].cachedFrameSnapshotIdentity = snapshotIdentity
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

            if ancestor.onActivate != nil || ancestor.longPressGesture?.canRecognize == true {
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
            node.longPressGesture == nil,
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
            guard interaction.node.acceptsScrollInput else {
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
                guard let node = node(for: dispatchIndex), node.acceptsScrollInput else {
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
        let modal = activeModalPresentationNode
        let focusableDispatchIndices = prepaintState.focusOrder.filter { dispatchIndex in
            guard let modal else { return true }
            guard let candidate = node(for: dispatchIndex) else { return false }
            return Self.isInteractionTarget(candidate, within: modal)
        }
        guard !focusableDispatchIndices.isEmpty else {
            if modal != nil {
                updateFocusTarget(to: nil)
            }
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
                    candidate.acceptsScrollInput && (axis == nil || candidate.scrollAxis == axis)
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

    /// The last modal reached by prepaint is the frontmost presentation:
    /// deferred overlays follow inline content and nested overlays follow the
    /// presentation underneath them. Reading the same flattened ordering as
    /// painting keeps this scope renderer- and platform-independent.
    internal var activeModalPresentationNode: ViewNode? {
        prepaintState.dispatchNodes.last {
            $0.node.isModalPresentationScope
                && !Self.hasHiddenAncestor($0.node)
        }?.node
    }

    private func activateKeyboardShortcut(for event: KeyboardEvent) -> Bool {
        updateResolvedLayout()
        let modal = activeModalPresentationNode
        for dispatchState in prepaintState.dispatchNodes {
            let node = dispatchState.node
            guard
                modal.map({ Self.isInteractionTarget(node, within: $0) }) ?? true,
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
        let modal = activeModalPresentationNode
        let candidates = [nearestScrollableNode(from: focusedNode), nearestScrollableNode(from: hoveredNode)]
        let scrollableNode = candidates.compactMap { $0 }.first { candidate in
            guard let modal else { return true }
            return Self.isInteractionTarget(candidate, within: modal)
        }
        // Activation and editing keys must not cancel an application
        // scroll. Only a key this axis actually
        // handles may take control of that motion. Compute again after any
        // interruption so arrows still start from the presented offset.
        guard let scrollableNode, scrollableNode.requestedKeyboardScrollOffset(for: key) != nil else {
            return false
        }

        if scrollPresentedTweens[ObjectIdentifier(scrollableNode)]?.origin.isProgrammatic == true {
            cancelScrollPresentedTween(for: scrollableNode, preservingPresentation: true)
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
        let timestamp = clock()
        pendingPreciseScrollAlignments.removeAll { $0.container === node || $0.container == nil || $0.target == nil }
        node.scrollPresentedDelta = combinedStart
        scrollPresentedTweens[key] = ScrollPresentedTween(
            node: node,
            target: nil,
            startDelta: combinedStart,
            startTime: timestamp,
            lastTime: timestamp,
            duration: Self.scrollKeyboardTweenDuration,
            targetOffset: node.scrollOffset,
            scrollLimit: node.maxScrollOffset,
            origin: .keyboard
        )
        recordScrollPhase(.animating, for: node)
        invalidate(.paint)
    }

    private func tickScrollPresentedTweens(at timestamp: Double) -> Bool {
        guard !scrollPresentedTweens.isEmpty, timestamp.isFinite else { return false }

        var didUpdate = false
        for key in Array(scrollPresentedTweens.keys) {
            guard var tween = scrollPresentedTweens[key] else { continue }
            guard let node = tween.node, node.runtime === self else {
                if let continuation = tween.listNavigationReveal { cancelListNavigationReveal(continuation) }
                scrollPresentedTweens.removeValue(forKey: key)
                continue
            }
            if let continuation = tween.listNavigationReveal,
                !isListNavigationRevealCurrent(continuation) || continuation.receipt?.permitsContinuation != true
            {
                cancelListNavigationReveal(continuation)
                tween.listNavigationReveal = nil
            }
            guard node.scrollAxis != nil, !Self.hasHiddenAncestor(node),
                tween.origin.isProgrammatic || node.acceptsScrollInput,
                !tween.origin.isProgrammatic || node.scrollOffset == tween.targetOffset
            else {
                didUpdate = didUpdate || node.scrollPresentedDelta != 0
                cancelScrollPresentedTween(for: node)
                continue
            }

            let elapsed = max(0, timestamp - tween.startTime)
            let progress = tween.duration > 0 ? min(1, elapsed / tween.duration) : 1
            let eased: Double
            switch tween.origin {
            case .keyboard:
                // Preserve the existing macOS-style keyboard curve.
                eased = 1 - pow(1 - progress, 3)
            case .programmatic(let easing):
                let value = progress == 0 ? 0 : progress == 1 ? 1 : easing.apply(progress)
                eased = value.isFinite ? value : progress
            }
            let nextDelta = tween.startDelta * (1 - eased)
            let finiteDelta = nextDelta.isFinite ? nextDelta : 0
            if node.scrollPresentedDelta != finiteDelta {
                node.scrollPresentedDelta = finiteDelta
                didUpdate = true
            }
            if progress >= 1 {
                node.scrollPresentedDelta = 0
                if let continuation = tween.listNavigationReveal, isListNavigationRevealCurrent(continuation) {
                    continuation.animationHasCompleted = true
                    // An easing sample can reach zero before elapsed time
                    // reaches its end. The terminal native transition still
                    // needs a real render, even when no pixel delta changes.
                    didUpdate = true
                    invalidate(.paint)
                }
                scrollPresentedTweens.removeValue(forKey: key)
            } else {
                tween.lastTime = max(tween.lastTime, timestamp)
                scrollPresentedTweens[key] = tween
            }
        }

        return didUpdate
    }

    private func updateResolvedLayout() {
        lazyListResolutionDepth += 1
        lazyListRegistrations = lazyListRegistrations.filter { _, registration in
            guard let node = registration.node, let adapter = registration.adapter else { return false }
            return node.runtime === self && node.retainedLazyListAdapter === adapter
        }
        pendingLazyListAnchorClamps = pendingLazyListAnchorClamps.filter { _, correction in
            guard let node = correction.node, let adapter = correction.adapter, let scroll = correction.scroll else {
                return false
            }
            return correction.adapterProof.isCurrent && node.runtime === self && scroll.runtime === self
                && node.retainedLazyListAdapter === adapter && adapter.ownsAttachment(node)
        }
        ensureLazyListResolutionBudget()
        let wasResolvingLayoutSettlement = isResolvingLayoutSettlement
        let wasUpdatingLayout = isUpdatingResolvedLayout
        isResolvingLayoutSettlement = true
        isUpdatingResolvedLayout = true
        defer {
            isResolvingLayoutSettlement = wasResolvingLayoutSettlement
            isUpdatingResolvedLayout = wasUpdatingLayout
            let reveal = !wasUpdatingLayout && !isRendering ? captureListNavigationRevealSettlement() : nil
            if !wasUpdatingLayout { drainPresentationFocusRestorations(layoutIsFresh: true) }
            if !wasUpdatingLayout, !isRendering { retainedBuildCoordinatorStorage?.retainedCallbacksDidDrain() }
            drainListNavigationReveal(reveal)
            // Keep the budget through nested queries and focus restoration's
            // ordinary settle passes. Only the outermost scope releases it.
            lazyListResolutionDepth -= 1
            finishLazyListResolutionBudgetIfIdle()
        }
        let settlementSequence = beginLayoutSettlementResolution()
        let traversalOverflowCount = ViewNode.traversalDepthOverflowCount
        advanceTextInputReplayScopeRevision(&textInputReplayScopeRevision)
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
        convergeResolvedSubtrees()

        if settleProgrammaticScrollRangeChanges() {
            settleLayoutAfterProgrammaticScroll()
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

        if settleProgrammaticScrollRangeChanges() {
            // A deferred target can change the content extent during its
            // settle pass. Correct that range before this frame is painted.
            settleLayoutAfterProgrammaticScroll()
        }

        let prepaintRevision = presentationMutationRevision
        updatePrepaintState()
        finishLayoutSettlementResolution(
            sequence: settlementSequence,
            wasNested: wasResolvingLayoutSettlement,
            traversalOverflowCount: traversalOverflowCount)
        presentationPrepaintRevision = prepaintRevision
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
        afterLayoutGeometryInvalidations.removeAll(keepingCapacity: true)
        defer {
            isDrainingAfterLayoutActions = false
            afterLayoutGeometryInvalidations.removeAll(keepingCapacity: true)
        }

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
                alignment.listNavigation?.permitsReveal(in: self, target: target) ?? true,
                target.runtime === self, container.runtime === self,
                container.scrollSourceEpoch == alignment.containerEpoch,
                container.scrollOffset == alignment.expectedOffset,
                nearestRetainedScrollContainer(of: target) === container,
                let (placedTarget, placedContainer) = target.nearestScrollTarget(),
                placedContainer === container
            else {
                continue
            }

            let tween = scrollPresentedTweens[ObjectIdentifier(container)]
            if placedTarget !== target, placedTarget === alignment.coarseTarget {
                // Presentation has not reached the deferred row yet. Keep
                // its request without restarting the animation on every
                // intermediate render or realizing offscreen content early.
                if tween?.origin.isProgrammatic == true {
                    pendingPreciseScrollAlignments.append(alignment)
                }
                continue
            }

            var continuation: AnimationTransaction?
            var timestamp: Double
            if let listNavigation = alignment.listNavigation {
                guard let sample = listNavigationClock(listNavigation) else { continue }
                timestamp = sample
            } else {
                timestamp = clock()
            }
            if let tween, case .programmatic(let easing) = tween.origin {
                // A more precise target uses the remaining authored time.
                // This is a correction to the same request, not a second
                // animation with a new full duration. Once the tween has
                // completed, the final alignment settles before painting.
                timestamp = tween.lastTime
                continuation = AnimationTransaction(
                    duration: max(0, tween.duration - max(0, timestamp - tween.startTime)), easing: easing)
            }
            if performProgrammaticScroll(
                to: target, anchorX: alignment.anchorX, anchorY: alignment.anchorY,
                animation: continuation, at: timestamp, listNavigation: alignment.listNavigation)
            {
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
        convergeResolvedSubtrees()
    }

    private func convergeResolvedSubtrees() {
        var legacyRounds = 0
        while true {
            if let budget = lazyListResolutionBudget {
                guard budget.consumeRound() else { return }
            } else {
                guard legacyRounds < Self.geometryReaderConvergenceLimit else { return }
            }
            var changed = lazyListAnchorNeedsLayout
            if !changed {
                changed = recordResolvedLazyListMeasurements()
                if resolveGeometryReaderSlots() { changed = true }
                if let budget = lazyListResolutionBudget, resolveLazyListContainers(budget: budget) { changed = true }
            }
            guard changed else { return }
            legacyRounds += 1
            runLayoutPass()
        }
    }

    private func runLayoutPass() {
        let wasLayoutInProgress = isLayoutInProgress
        isLayoutInProgress = true
        let geometryRevision = layoutSettlementGeometryRevision
        let resolutionSequence = layoutSettlementResolutionSequence
        let traversalOverflowCount = ViewNode.traversalDepthOverflowCount
        defer {
            isLayoutInProgress = wasLayoutInProgress
            if !wasLayoutInProgress, !layoutSettlementGenerationsExhausted,
                geometryRevision == layoutSettlementGeometryRevision,
                resolutionSequence == layoutSettlementResolutionSequence,
                traversalOverflowCount == ViewNode.traversalDepthOverflowCount
            {
                lastUnmutatedLayoutPassRevision = geometryRevision
            } else {
                lastUnmutatedLayoutPassRevision = nil
            }
        }

        layoutPassID &+= 1
        currentPassLayoutVisitCount = 0
        pendingGeometryReaderNodes.removeAll(keepingCapacity: true)
        pendingLazyListVisits.removeAll(keepingCapacity: true)
        pendingLazyListOrder.removeAll(keepingCapacity: true)
        pendingLazyListMeasurements.removeAll(keepingCapacity: true)
        lazyListUnsupportedThisPass = false
        root.resolvedFrame = root.frame
        root.layoutSubtree(displayScale: displayScale)
        if !wasLayoutInProgress, lazyListResolutionDepth == 1,
            geometryRevision == layoutSettlementGeometryRevision,
            resolutionSequence == layoutSettlementResolutionSequence,
            traversalOverflowCount == ViewNode.traversalDepthOverflowCount
        {
            // Failed or nested passes cannot erase the fact that a previous
            // correction still needs its viewport proved by fresh layout.
            lazyListAnchorNeedsLayout = normalizeLazyListAnchorOffsets()
        }
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
            if hasLazyListLayoutScope, !permitsRetainedActionInvocation { break }
            guard let node = reference.node, node.runtime === self, let build = node.geometryReaderBuild else {
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

            if let budget = lazyListResolutionBudget, !budget.consumeElement() { break }

            if let lease = node.retainedSubtreeBuildLease {
                if rebuildManagedGeometryReader(node, slot: slot, build: build, lease: lease) {
                    didRebuild = true
                }
            } else {
                guard let rebuilt = build(self, slot).first else { continue }
                beginLongPressReconciliation()
                adoptGeometryReader(rebuilt, into: node, slot: slot)
                didRebuild = true
                endLongPressReconciliation()
            }
        }

        return didRebuild
    }

    private struct LazyListAdoptedCandidate {
        let candidate: RetainedLazyListRuntimeAdapter.Candidate
        let completion: RetainedLazyListAdoptionCompletion
    }

    /// The pointer/focus/scroll targets are a bounded exception to the visible
    /// window, not permission to retain every previously visited row. The
    /// adapter applies its configured owner/record/leaf caps to this set.
    private func protectedLazyListRoots(in container: ViewNode) -> Set<ObjectIdentifier> {
        var targets: [ViewNode?] = [
            focusedNode, pressedNode, longPressAttempt?.node, nodeDragState?.node,
            scrollDragState?.node, activeScrollIndicatorNode,
        ]
        targets.append(
            contentsOf: scrollPresentedTweens.values.compactMap { tween in
                tween.origin.isProgrammatic ? tween.target : nil
            })
        targets.append(contentsOf: pendingPreciseScrollAlignments.compactMap(\.target))
        targets.append(contentsOf: pendingPreciseScrollAlignments.compactMap(\.coarseTarget))
        // A prepared List action needs its actual source through target
        // realization and focus, even when no node was focused at entry. The
        // native scope keeps this receipt weakly; no visited row is cached.
        var ancestor: ViewNode? = container
        var ancestorDepth = 0
        while let node = ancestor, ancestorDepth < ViewNode.maximumTraversalDepth {
            targets.append(contentsOf: node.listNavigationOwner?.currentActionProtectedNodes(in: self) ?? [])
            ancestor = node.parent
            ancestorDepth += 1
        }
        var protected = Set<ObjectIdentifier>()
        for target in targets {
            guard var node = target, node !== container, node.runtime === self else { continue }
            var depth = 0
            while let parent = node.parent, depth < ViewNode.maximumTraversalDepth {
                if parent === container {
                    if container.children.contains(where: { $0 === node }) { protected.insert(ObjectIdentifier(node)) }
                    break
                }
                node = parent
                depth += 1
            }
        }
        return protected
    }

    private func resolveLazyListContainers(budget: RetainedLazyListWorkBudget) -> Bool {
        var changed = false
        // Copy only the native order. A callback can replace the pass registry;
        // each visit is admitted again before its first protocol call.
        let order = pendingLazyListOrder
        for key in order {
            guard let visit = pendingLazyListVisits[key], lazyListVisitIsCurrent(visit),
                let node = visit.node, let adapter = visit.adapter, let viewport = visit.viewport,
                adapter.hasUnresolvedWork
            else { continue }
            if rebuildLazyList(node, adapter: adapter, viewport: viewport, visit: visit, budget: budget) {
                changed = true
            }
        }
        return changed
    }

    private func rebuildLazyList(
        _ node: ViewNode, adapter: RetainedLazyListRuntimeAdapter,
        viewport: RetainedLazyListRuntimeAdapter.Viewport, visit: LazyListLayoutVisit,
        budget: RetainedLazyListWorkBudget
    ) -> Bool {
        guard lazyListVisitIsCurrent(visit), let lease = node.retainedSubtreeBuildLease else { return false }
        let managedDescriptor = adapter.managedLogicalDescriptorBinding
        let managedIdentity = managedDescriptor == nil ? nil : node.captureLazyListIdentityProof()
        let canBuild = lease.canBuild
        guard canBuild, lazyListVisitIsCurrent(visit), node.retainedSubtreeBuildLease === lease,
            managedIdentity?.isCurrent != false
        else { return false }
        let coordinator = retainedBuildCoordinator
        // Pending is explicit. This adapter adds no retry queue or scheduler;
        // the next ordinary build/layout opportunity can retry with fresh proof.
        guard let sequence = coordinator.beginBuild() else { return false }
        if managedDescriptor != nil {
            guard lazyListVisitIsCurrent(visit), managedIdentity?.isCurrent == true,
                node.retainedSubtreeBuildLease === lease
            else {
                coordinator.finishBuild()
                return false
            }
        }
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: node, runtime: self, coordinator: coordinator, sequence: sequence)
        let transaction = RetainedBuildTransaction()
        let originalExtent = adapter.contentExtent
        let anchor = lazyListAnchor(adapter: adapter, viewport: viewport)
        var epoch: (any RetainedBuildEpoch)?
        var lazyJournal: RetainedLazyListAdoptionJournal?
        var lazyActivity: (any RetainedLazyListBuildActivity)?
        var adopted: LazyListAdoptedCandidate?
        func performBuild() {
            beginLongPressReconciliation()
            epoch = admission.isBuildCurrent ? lease.beginBuild() : nil
            coordinator.install(epoch, startedAt: sequence)

            if managedDescriptor != nil, let epoch, let activity = epoch as? any RetainedLazyListBuildActivity,
                admission.isBuildCurrent, managedDescriptor?.isCurrent == true,
                let scope = coordinator.beginDescriptorBuildScope(
                    origin: .managedSubtree, epoch: epoch, hostLifetime: lazyListLogicalHostLifetime,
                    ownerLifetime: node.lazyListActivityStorage().descriptorOwnerLifetime)
            {
                let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: transaction)
                let bound = activity.bindLazyListDescriptorScope(scope)
                if bound, scope.canConstructDescriptors, admission.isBuildCurrent, journal.bindDescriptorScope(scope) {
                    lazyJournal = journal
                    lazyActivity = activity
                } else {
                    journal.revokeBeforeAbandon()
                }
            }
            if let epoch, admission.isBuildCurrent {
                if managedDescriptor == nil || (lazyJournal != nil && lazyActivity != nil) {
                    adopted = prepareAndAdoptLazyList(
                        node, adapter: adapter, viewport: viewport, budget: budget,
                        protectedRoots: protectedLazyListRoots(in: node), epoch: epoch, admission: admission,
                        lazyJournal: lazyJournal, lazyActivity: lazyActivity, transaction: transaction,
                        preservingAnchor: visit.scrollContainer.map(lazyListAnchorMayControl) == true ? anchor : nil)
                } else {
                    // A present binding that failed its exact refinement or scope
                    // cannot enter the ordinary raw provider path.
                    adopted = nil
                }
            } else {
                adopted = nil
            }
            // Once a retained mutation started, abandonment would be a rollback
            // of accepted application effects. Finish that admitted scope even
            // when it is now obsolete; never continue its remaining adoption.
            if managedDescriptor != nil {
                if let lazyJournal, let lazyActivity {
                    let disposition = lazyJournal.seal(completedCheckedAdoption: adopted != nil)
                    if disposition.stop != .noAcceptance || adopted != nil {
                        lazyActivity.commitLazyList(disposition)
                    } else {
                        lazyJournal.revokeBeforeAbandon()
                        epoch?.abandon()
                    }
                } else {
                    epoch?.abandon()
                }
            } else if admission.didMutate || adopted != nil {
                epoch?.commit()
            } else {
                epoch?.abandon()
            }
            endLongPressReconciliation()
        }
        if managedDescriptor == nil {
            performBuild()
        } else {
            transaction.perform(performBuild)
        }

        afterRetainedCallbacks { [weak self, weak node, weak adapter] in
            transaction.perform {
                epoch?.finishAfterCallbacks()
                lazyJournal?.finishAcceptedTaskCleanup()
                // Completion permission is distinct from construction permission.
                // This getter is a callout too: check the native admitted scope
                // again before publishing any actual-row mapping.
                let mayComplete = adopted != nil ? epoch?.canComplete == true : false
                var accepted = false
                if mayComplete, let node, let adapter, let adopted,
                    admission.isCurrent, adopted.completion.isCurrent,
                    lazyJournal != nil
                        || adapter.complete(candidate: adopted.candidate, adoptedChildren: node.children),
                    admission.isCurrent, adopted.completion.isCurrent
                {
                    accepted = true
                }
                admission.finishCandidatePayload()
                lazyJournal?.releaseUnadoptedTransport()
                let completedAfterPayloadCleanup = accepted ? epoch?.canComplete == true : false
                if completedAfterPayloadCleanup, let self, let node, let adapter, let adopted,
                    admission.isBuildCurrent, adopted.completion.isCurrent
                {
                    self.lazyListResolveCount += 1
                    node.markDirty(.layout)
                    self.invalidate(.layout, from: node)
                    if let anchor { _ = self.applyLazyListAnchor(anchor, adapter: adapter, visit: visit) }
                } else {
                    admission.revokeUnfinishedCandidate()
                }
            }
            // Epoch cleanup and candidate acceptance remain inside the one
            // existing coordinator scope; queued root requests run afterwards.
            coordinator.finishBuild()
        }

        let extentChanged = adapter.contentExtent != originalExtent
        if extentChanged, ownsLazyListAttachment(node), node.retainedLazyListAdapter === adapter {
            node.markDirty(.layout)
            invalidate(.layout, from: node)
        }
        return admission.didMutate || adopted != nil || extentChanged
    }

    private func prepareAndAdoptLazyList(
        _ node: ViewNode, adapter: RetainedLazyListRuntimeAdapter,
        viewport: RetainedLazyListRuntimeAdapter.Viewport, budget: RetainedLazyListWorkBudget,
        protectedRoots: Set<ObjectIdentifier>, epoch: any RetainedBuildEpoch,
        admission: RetainedLazyListAdoptionAdmission,
        lazyJournal: RetainedLazyListAdoptionJournal?, lazyActivity: (any RetainedLazyListBuildActivity)?,
        transaction: RetainedBuildTransaction, preservingAnchor: RetainedLazyListAnchor?
    ) -> LazyListAdoptedCandidate? {
        let mayPrepare = epoch.canAdopt
        guard mayPrepare, admission.isBuildCurrent else { return nil }
        lazyJournal?.seedExistingContributions(from: node.children)
        lazyJournal?.seedExistingRowActivities(adapter.materializedRowActivities)
        let preparation = adapter.prepare(
            viewport: viewport, protectedRoots: protectedRoots, budget: budget, admission: admission,
            activity: lazyActivity, journal: lazyJournal, preserving: preservingAnchor)
        guard admission.isBuildCurrent else { return nil }
        guard case .ready(let candidate) = preparation, candidate.viewport == viewport,
            admission.installCandidate(candidate)
        else { return nil }
        let mayAdopt = epoch.canAdopt
        guard mayAdopt, admission.isCurrent else { return nil }
        let nativePreparation: RetainedLazyListAdoptionPreparation?
        if let lazyJournal {
            guard let lazyActivity, lazyJournal.canContinueConstruction else { return nil }
            guard lazyJournal.registerSourceDescriptors(in: candidate.children) else { return nil }
            for child in candidate.children where child.parent === node { lazyJournal.recordUnchangedNode(child) }
            guard let preparation = lazyJournal.preparation(), admission.isCurrent else { return nil }
            let prepared = lazyActivity.willAdoptLazyList(preparation)
            guard admission.isCurrent, let prepared,
                lazyJournal.beginAdoption(preparation, preparedActivity: prepared),
                candidate.configureManagedPublication(preparation)
            else { return nil }
            nativePreparation = preparation
        } else {
            let prepared = epoch.willAdopt()
            // willAdopt may leave the epoch's construction phase. Its successful
            // one-shot predicate is not rerun; only primitive admitted proof is.
            guard prepared, admission.isCurrent else { return nil }
            nativePreparation = nil
        }
        let taskAdoption = lazyJournal.map { _ in
            RetainedTaskAdoptionContext(runtime: self, epoch: epoch, transaction: transaction)
        }
        let result = ComponentHost.reconcileChildren(
            of: node, oldChildren: node.children, newNodes: candidate.children, admission: admission,
            taskAdoption: taskAdoption, lazyJournal: lazyJournal)
        guard result.completed, admission.isCurrent, let completion = result.completion, completion.isCurrent else {
            return nil
        }
        if let lazyJournal {
            let anchor = node.lazyListActivityStorage().captureActualAttachment(of: node, in: self)
            guard nativePreparation != nil,
                adapter.complete(
                    candidate: candidate, adoptedChildren: node.children, journal: lazyJournal,
                    structuralAnchor: anchor),
                admission.isCurrent, completion.isCurrent
            else { return nil }
        }
        return LazyListAdoptedCandidate(candidate: candidate, completion: completion)
    }

    private func rebuildManagedGeometryReader(
        _ node: ViewNode, slot: Size, build: (RetainedViewRuntime, Size) -> [ViewNode],
        lease: any RetainedSubtreeBuildLease
    ) -> Bool {
        let parent = node.parent
        let nativeAdmission = GeometryDescriptorAdmission(node: node, runtime: self, lease: lease, parent: parent)
        let hasManagedNativeActivity = node.retainedLazyListActivityStorage != nil
        guard lease.canBuild else {
            // Cleanup can render while the adopted reader's lease is still
            // provisional. Preserve its unresolved path through this render;
            // ordinary idle denial must not create retries or new work.
            if isRendering, hasActiveRetainedBuild, node.runtime === self,
                node.retainedSubtreeBuildLease === lease, node.geometryReaderBuild != nil,
                !hasManagedNativeActivity || nativeAdmission.isCurrent
            {
                node.markDirty(.layout)
                invalidate(.layout, from: node)
            }
            return false
        }
        guard !hasManagedNativeActivity || nativeAdmission.isCurrent else { return false }
        let coordinator = retainedBuildCoordinator
        guard let sequence = coordinator.beginBuild() else {
            coordinator.scheduleWhenIdle(for: node) { [weak self, weak node, weak parent] in
                guard let self, let node, node.runtime === self, node.parent === parent,
                    node.retainedSubtreeBuildLease === lease,
                    !hasManagedNativeActivity || nativeAdmission.isCurrent,
                    lease.canBuild, !hasManagedNativeActivity || nativeAdmission.isCurrent
                else { return }
                node.markDirty(.layout)
                self.invalidate(.layout, from: node)
            }
            return false
        }
        guard !hasManagedNativeActivity || nativeAdmission.isCurrent else {
            coordinator.finishBuild()
            return false
        }
        let transaction = RetainedBuildTransaction()
        var epoch: (any RetainedBuildEpoch)?
        if hasManagedNativeActivity {
            transaction.perform {
                epoch = lease.beginBuild()
                coordinator.install(epoch, startedAt: sequence)
            }
        } else {
            epoch = lease.beginBuild()
            coordinator.install(epoch, startedAt: sequence)
        }
        beginLongPressReconciliation()

        var didAdopt = false
        var descriptorBuild: GeometryDescriptorBuild?
        if let epoch, let activity = epoch as? any RetainedLazyListBuildActivity {
            transaction.perform {
                descriptorBuild = beginGeometryDescriptorBuild(
                    on: node, epoch: epoch, activity: activity, transaction: transaction, admission: nativeAdmission)
                if let descriptorBuild {
                    didAdopt = buildAndAdoptGeometryDescriptor(
                        on: node, parent: parent, slot: slot, build: build, lease: lease, epoch: epoch,
                        descriptorBuild: descriptorBuild, sequence: sequence, transaction: transaction)
                    // The helper's throwaway node and typed payloads have
                    // unwound. Their destructors cannot certify completion.
                    didAdopt = didAdopt && descriptorBuild.permitsCompletion
                    let disposition = descriptorBuild.journal.seal(
                        completedCheckedAdoption: didAdopt && descriptorBuild.completion?.isCurrent == true)
                    if descriptorBuild.usesManagedPublication {
                        if didAdopt || disposition.stop != .noAcceptance {
                            activity.commitLazyList(disposition)
                        } else {
                            descriptorBuild.journal.revokeBeforeAbandon()
                            epoch.abandon()
                        }
                    } else if didAdopt {
                        epoch.commit()
                    } else {
                        descriptorBuild.journal.revokeBeforeAbandon()
                        epoch.abandon()
                    }
                } else {
                    epoch.abandon()
                }
                endLongPressReconciliation()
            }
        } else {
            if let epoch, epoch.canAdopt, let rebuilt = build(self, slot).first,
                node.runtime === self, node.parent === parent, node.retainedSubtreeBuildLease === lease,
                lease.canBuild, epoch.canAdopt, !coordinator.wasSuperseded(since: sequence), epoch.willAdopt()
            {
                let taskAdoption = RetainedTaskAdoptionContext(runtime: self, epoch: epoch, transaction: transaction)
                adoptGeometryReader(rebuilt, into: node, slot: slot, taskAdoption: taskAdoption)
                didAdopt = true
                epoch.commit()
            } else {
                epoch?.abandon()
            }
            endLongPressReconciliation()
        }

        afterRetainedCallbacks {
            transaction.perform {
                epoch?.finishAfterCallbacks()
                descriptorBuild?.journal.finishAcceptedTaskCleanup()
                descriptorBuild?.journal.releaseUnadoptedTransport()
            }
            coordinator.finishBuild()
        }
        return didAdopt
    }

    /// Original physical and lease identity captured before any deferred-build
    /// callout. Replacing just the lease must reject the old construction too.
    @MainActor
    private final class GeometryDescriptorAdmission {
        weak var node: ViewNode?
        private weak var runtime: RetainedViewRuntime?
        private weak var lease: (any RetainedSubtreeBuildLease)?
        private weak var parent: ViewNode?
        private let hadParent: Bool
        private let attachment: RetainedLazyListAttachmentProof
        private let identity: RetainedLazyListViewIdentityProof

        init(node: ViewNode, runtime: RetainedViewRuntime, lease: any RetainedSubtreeBuildLease, parent: ViewNode?) {
            self.node = node
            self.runtime = runtime
            self.lease = lease
            self.parent = parent
            hadParent = parent != nil
            attachment = node.captureLazyListAttachmentProof()
            identity = node.captureLazyListIdentityProof()
        }

        var isPhysicallyCurrent: Bool {
            guard let node, let runtime, !hadParent || parent != nil else { return false }
            return attachment.isCurrent && identity.isCurrent && node.parent === parent
                && node.isRetainedLazyListAttached(in: runtime)
        }

        var isCurrent: Bool {
            guard let node, let lease else { return false }
            return isPhysicallyCurrent && node.retainedSubtreeBuildLease === lease
        }
    }

    @MainActor
    private final class GeometryDescriptorBuild {
        let journal: RetainedLazyListAdoptionJournal
        let activity: any RetainedLazyListBuildActivity
        let attribution: RetainedLazyListBuildAttribution?
        let admission: GeometryDescriptorAdmission
        var completion: RetainedLazyListAdoptionCompletion?
        weak var acceptedLease: (any RetainedSubtreeBuildLease)?
        var acceptedHadLease = false
        var usesManagedPublication: Bool

        init(
            journal: RetainedLazyListAdoptionJournal, activity: any RetainedLazyListBuildActivity,
            attribution: RetainedLazyListBuildAttribution?, admission: GeometryDescriptorAdmission
        ) {
            self.journal = journal
            self.activity = activity
            self.attribution = attribution
            self.admission = admission
            usesManagedPublication = attribution != nil
        }

        var permitsCompletion: Bool {
            guard usesManagedPublication else { return true }
            guard admission.isPhysicallyCurrent, completion?.isCurrent == true,
                let node = admission.node, !acceptedHadLease || acceptedLease != nil
            else { return false }
            return node.retainedSubtreeBuildLease === acceptedLease
        }
    }

    private func beginGeometryDescriptorBuild(
        on node: ViewNode, epoch: any RetainedBuildEpoch, activity: any RetainedLazyListBuildActivity,
        transaction: RetainedBuildTransaction, admission: GeometryDescriptorAdmission
    ) -> GeometryDescriptorBuild? {
        guard admission.isCurrent else { return nil }
        let storage = node.lazyListActivityStorage()
        guard
            let initial = retainedBuildCoordinator.beginDescriptorBuildScope(
                origin: .managedSubtree, epoch: epoch, hostLifetime: lazyListLogicalHostLifetime,
                ownerLifetime: storage.descriptorOwnerLifetime), initial.canConstructDescriptors
        else { return nil }
        let scope: RetainedLazyListDescriptorBuildScope
        if let anchor = storage.deferredSubtreeAnchor {
            guard anchor.isCurrent,
                let qualified = initial.withAdmittedDeferredSubtree(
                    originalActivity: anchor.contribution, originalAttachment: anchor.actual)
            else {
                initial.revoke()
                return nil
            }
            scope = qualified
        } else if let anchor = storage.descriptorDeferredSubtreeAnchor {
            guard anchor.isCurrent,
                let qualified = initial.withAdmittedOrdinaryDeferredSubtree(
                    originalActivity: anchor.contribution, originalAttachment: anchor.actual)
            else {
                initial.revoke()
                return nil
            }
            scope = qualified
        } else {
            scope = initial
        }
        guard activity.bindLazyListDescriptorScope(scope), scope.canConstructDescriptors,
            admission.isCurrent
        else {
            scope.revoke()
            return nil
        }
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
        journal.seedExistingContributions(from: [node])
        let attribution: RetainedLazyListBuildAttribution?
        if let anchor = storage.deferredSubtreeAnchor {
            guard let admitted = journal.beginDeferredSubtree(originalAnchor: anchor) else {
                journal.revokeBeforeAbandon()
                return nil
            }
            attribution = admitted
        } else {
            attribution = nil
        }
        return GeometryDescriptorBuild(
            journal: journal, activity: activity, attribution: attribution, admission: admission)
    }

    @inline(never)
    private func buildAndAdoptGeometryDescriptor(
        on node: ViewNode, parent: ViewNode?, slot: Size, build: (RetainedViewRuntime, Size) -> [ViewNode],
        lease: any RetainedSubtreeBuildLease, epoch: any RetainedBuildEpoch,
        descriptorBuild: GeometryDescriptorBuild, sequence: UInt64, transaction: RetainedBuildTransaction
    ) -> Bool {
        let nativeAdmission = descriptorBuild.admission
        let journal = descriptorBuild.journal
        var didAdopt = false
        defer { if !didAdopt { journal.revokeBeforeAbandon() } }
        func nativeConstructionIsCurrent() -> Bool {
            journal.canContinueConstruction && nativeAdmission.isCurrent
                && !retainedBuildCoordinator.wasSuperseded(since: sequence)
        }
        guard epoch.canAdopt, nativeConstructionIsCurrent() else { return false }
        let candidates = buildGeometryDescriptorContent(
            slot: slot, build: build, descriptorBuild: descriptorBuild)
        guard nativeConstructionIsCurrent(), candidates.count == 1,
            !ViewNode.containsRejectedRetainedSource(in: candidates), let rebuilt = candidates.first
        else { return false }
        let leaseCanBuild = lease.canBuild
        guard nativeConstructionIsCurrent(), leaseCanBuild, epoch.canAdopt, nativeConstructionIsCurrent(),
            journal.registerSourceDescriptors(in: candidates), let preparation = journal.preparation()
        else { return false }
        descriptorBuild.usesManagedPublication =
            descriptorBuild.usesManagedPublication || journal.hasManagedContributions
        if descriptorBuild.usesManagedPublication {
            let prepared = descriptorBuild.activity.willAdoptLazyList(preparation)
            guard nativeAdmission.isCurrent, let prepared,
                journal.beginAdoption(preparation, preparedActivity: prepared)
            else { return false }
        } else {
            guard epoch.willAdopt() else { return false }
            _ = journal.beginOrdinaryAdoption()
        }
        let taskAdoption = RetainedTaskAdoptionContext(runtime: self, epoch: epoch, transaction: transaction)
        let expectedLease = rebuilt.retainedSubtreeBuildLease
        let result = ComponentHost.adopt(
            source: rebuilt, into: node, taskAdoption: taskAdoption, lazyJournal: journal)
        if !journal.isOrdinaryAdoption {
            guard result.completed, nativeAdmission.isPhysicallyCurrent,
                node.retainedSubtreeBuildLease === expectedLease,
                journal.canContinueAdoption
            else { return false }
        }
        descriptorBuild.completion =
            result.completed
            ? (result.completion ?? RetainedLazyListAdoptionCompletion(of: node)) : nil
        descriptorBuild.acceptedLease = expectedLease
        descriptorBuild.acceptedHadLease = expectedLease != nil
        // This scalar is the actual slot used for the accepted reader body.
        node.geometryReaderBuiltSize = slot
        let anchor = node.lazyListActivityStorage().captureActualAttachment(of: node, in: self)
        let ordinaryEmpty = preparation.ordinaryComponents.flatMap(\.groups)
            .filter { $0.construction == .closedEmpty }.map(\.group)
        if result.completed {
            journal.recordAcceptedOrdinaryEmptyGroups(structuralAnchor: anchor, groups: ordinaryEmpty)
            let recordedScope = journal.recordCompletedOwnedDescriptorScope(structuralAnchor: anchor)
            if !journal.isOrdinaryAdoption, !recordedScope { return false }
        }
        if let attribution = descriptorBuild.attribution {
            for proposal in preparation.groups
            where proposal.membership === attribution.membership && proposal.physical === attribution.physical.id
                && proposal.construction == .closedEmpty
            {
                _ = journal.recordAcceptedEmpty(proposal, structuralAnchor: anchor)
            }
        }
        geometryReaderResolveCount &+= 1
        didAdopt = true
        return true
    }

    /// The entered frame is always left before its caller rechecks native
    /// admission, including failure during enter or the existing build closure.
    @inline(never)
    private func buildGeometryDescriptorContent(
        slot: Size, build: (RetainedViewRuntime, Size) -> [ViewNode], descriptorBuild: GeometryDescriptorBuild
    ) -> [ViewNode] {
        guard let attribution = descriptorBuild.attribution else {
            return descriptorBuild.journal.canContinueConstruction && descriptorBuild.admission.isCurrent
                ? build(self, slot) : []
        }
        guard descriptorBuild.admission.isCurrent, descriptorBuild.journal.canContinueConstruction else { return [] }
        let entered = descriptorBuild.activity.enterLazyListMaterialization(attribution)
        let nodes: [ViewNode]
        if entered, descriptorBuild.admission.isCurrent, descriptorBuild.journal.canContinueConstruction,
            attribution.constructionState == .admittedForConstruction
        {
            nodes = build(self, slot)
        } else {
            nodes = []
        }
        descriptorBuild.activity.leaveLazyListMaterialization(attribution)
        return nodes
    }

    private func adoptGeometryReader(
        _ rebuilt: ViewNode, into node: ViewNode, slot: Size, taskAdoption: RetainedTaskAdoptionContext? = nil
    ) {
        ComponentHost.adopt(source: rebuilt, into: node, taskAdoption: taskAdoption)
        // The builder and its resolved size travel together during adoption.
        // This explicit assignment also bounds convergence for custom readers.
        node.geometryReaderBuiltSize = slot
        geometryReaderResolveCount &+= 1
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
    func applyInteractionChrome(to node: ViewNode?, animated: Bool = true, at timestamp: Double? = nil) {
        guard let node, let surface = node.interactionSurface else {
            return
        }

        let phase = interactionPhase(for: node)
        let duration = animated ? surface.duration(intoPhase: phase) : 0
        let timestamp = timestamp ?? clock()

        func applyColor(_ property: AnimatedColorProperty, to color: Color) {
            if !animated, let running = colorAnimations[ColorAnimationKey(node: node, property: property)],
                running.endColor == color
            {
                let current = running.startColor.interpolated(to: color, progress: running.progress(at: timestamp))
                if node.color(for: property) != current { node.setColor(current, for: property) }
            } else {
                animateColor(property, of: node, to: color, duration: duration, at: timestamp)
            }
        }

        if let background = surface.background(for: phase) {
            applyColor(.background, to: background)
            if surface.appliesSurfaceSheen {
                node.backgroundGradient = Controls.backgroundSheen(for: node.backgroundColor ?? background)
            }
        }
        if let border = surface.border(for: phase) {
            applyColor(.border, to: border)
            if surface.appliesSurfaceSheen {
                node.borderGradient = Controls.borderSheen(for: node.borderColor)
            }
        }
        if let shadow = surface.shadow(for: phase) {
            applyColor(.shadow, to: shadow)
        }

        if let focusRingColor = surface.focusRingColor {
            // Keyed off focus itself, not the resolved phase: a press outranks
            // focus for the *fill*, but AppKit keeps the ring on a focused
            // control the whole time the mouse is held down on it.
            let isFocused = node.isFocused
            applyColor(.outline, to: isFocused ? focusRingColor : .clear)
            // macOS does not cross-fade the ring's alpha in place: it grows
            // out of the control's edge. Animating the width alongside the
            // colour is what makes it read as a ring arriving rather than a
            // blue haze resolving. See `docs/AnimationParity.md`.
            animateOutlineWidth(
                of: node, to: isFocused ? surface.focusRingWidth : 0,
                duration: duration, at: timestamp, preservingActiveAnimation: !animated)
        }

        let isPressed = phase == .pressed
        if surface.pressedScale != 1 {
            animateScale(
                of: node, to: isPressed ? surface.pressedScale : 1, duration: duration, at: timestamp,
                preservingActiveAnimation: !animated)
        }
        if surface.pressedContentOpacity != 1 {
            animateOpacity(
                of: node, to: isPressed ? surface.pressedContentOpacity : 1,
                duration: duration, at: timestamp, preservingActiveAnimation: !animated)
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

    private func animateOutlineWidth(
        of node: ViewNode, to target: Double, duration: Double, at timestamp: Double,
        preservingActiveAnimation: Bool = false
    ) {
        if preservingActiveAnimation, let state = node.animationStates[.outlineWidth], state.endValue == target {
            node.outlineWidth = max(0, state.interpolatedValue(at: timestamp))
            return
        }
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

    private func animateScale(
        of node: ViewNode, to target: Double, duration: Double, at timestamp: Double,
        preservingActiveAnimation: Bool = false
    ) {
        if preservingActiveAnimation,
            let horizontal = node.animationStates[.transformScaleX], horizontal.endValue == target,
            let vertical = node.animationStates[.transformScaleY], vertical.endValue == target
        {
            node.transform.scaleX = horizontal.interpolatedValue(at: timestamp)
            node.transform.scaleY = vertical.interpolatedValue(at: timestamp)
            return
        }
        guard duration > 0 else {
            node.animationStates[.transformScaleX] = nil
            node.animationStates[.transformScaleY] = nil
            node.transform.scaleX = target
            node.transform.scaleY = target
            return
        }
        let startX = node.transform.scaleX
        let startY = node.transform.scaleY
        guard startX != target || startY != target else {
            node.animationStates[.transformScaleX] = nil
            node.animationStates[.transformScaleY] = nil
            return
        }
        node.animationStates[.transformScaleX] = AnimationState(
            startValue: startX, endValue: target, startTime: timestamp, duration: duration, easing: .easeOut)
        node.animationStates[.transformScaleY] = AnimationState(
            startValue: startY, endValue: target, startTime: timestamp, duration: duration, easing: .easeOut)
    }

    private func animateOpacity(
        of node: ViewNode, to target: Double, duration: Double, at timestamp: Double,
        preservingActiveAnimation: Bool = false
    ) {
        if preservingActiveAnimation, let state = node.animationStates[.opacity], state.endValue == target {
            node.opacity = min(1, max(0, state.interpolatedValue(at: timestamp)))
            return
        }
        guard duration > 0 else {
            node.animationStates[.opacity] = nil
            node.opacity = target
            return
        }
        let start = node.opacity
        guard start != target else {
            node.animationStates[.opacity] = nil
            return
        }
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

    private func advanceFocusRevision() -> UInt64? {
        if let revision = focusRevision.advance() { return revision }
        // Revoke before any finished receipt releases application captures.
        // Terminal/overflow cleanup can still clear an old focus, but no new
        // intent or deferred restoration can reuse this exhausted authority.
        currentFocusEntry = nil
        let retired = pendingPresentationFocusRequests
        for request in retired { request.revoke() }
        pendingPresentationFocusRequests.removeAll()
        for request in retired { request.finish() }
        return nil
    }

    private func isAttachedFocusNode(_ node: ViewNode) -> Bool {
        var candidate: ViewNode? = node
        var depth = 0
        while let current = candidate, depth < ViewNode.maximumTraversalDepth {
            guard current.runtime === self else { return false }
            if current === root { return true }
            candidate = current.parent
            depth += 1
        }
        return false
    }

    private func focusTargetIsEligible(
        _ node: ViewNode, origin: RetainedFocusOrigin, beganAttached: Bool
    ) -> Bool {
        guard !node.isRetiringLazyListAttachment, node.isFocusable, !Self.hasHiddenAncestor(node) else { return false }
        if beganAttached || origin == .accessibility {
            guard isAttachedFocusNode(node),
                isPresentationNodeAvailable(node, requiresEnabled: origin == .accessibility)
            else { return false }
        } else {
            // Construction eligibility belongs only to an originally
            // detached candidate, never a target removed during a callback.
            var candidate: ViewNode? = node
            var depth = 0
            while let current = candidate, depth < ViewNode.maximumTraversalDepth {
                guard current.runtime == nil || current.runtime === self else { return false }
                candidate = current.parent
                depth += 1
            }
            guard candidate == nil else { return false }
        }
        if origin != .accessibility, isAttachedFocusNode(node), let modal = activeModalPresentationNode {
            return Self.isInteractionTarget(node, within: modal)
        }
        return true
    }

    private func accessibilityFocusContextIsCurrent(for node: ViewNode) -> Bool {
        guard permitsRenderLifecycleCallbacks, !focusRevision.isExhausted,
            case .settled = layoutSettlementStatus, hasCurrentAccessibilityPrepaint,
            node.isFocusable, isAttachedFocusNode(node), isPresentationNodeAvailable(node),
            let element = AccessibilityProjection.project(runtime: self)?
                .flattened().first(where: { $0.sourceNode === node })
        else { return false }
        return element.isEnabled && element.permitsModalActions
    }

    private func focusOperationHasAuthority(
        _ operation: RetainedFocusOperation, expectedFocus: ViewNode?
    ) -> Bool {
        let isCleanup = operation.origin == .cleanup && !operation.hasTarget
        guard permitsRenderLifecycleCallbacks || isCleanup, focusedNode === expectedFocus else { return false }
        if let revision = operation.revision {
            guard !focusRevision.isExhausted, presentationFocusRevision == revision else { return false }
        } else {
            guard isCleanup, focusRevision.isExhausted else { return false }
        }
        guard operation.hasTarget else { return true }
        guard let target = operation.target else { return false }
        if let receipt = operation.listNavigationReceipt,
            !receipt.permitsFocusOwnership(in: self, target: target)
        {
            return false
        }
        return focusTargetIsEligible(target, origin: operation.origin, beganAttached: operation.beganAttached)
    }

    private func validateFocusOperation(
        _ operation: RetainedFocusOperation, expectedFocus: ViewNode?, mayQuery: Bool
    ) -> Bool {
        guard focusOperationHasAuthority(operation, expectedFocus: expectedFocus) else { return false }
        guard operation.origin == .accessibility else { return true }
        // Beginning a build or entering a retained callback phase need not
        // invalidate paint. Check phase admission independently of the owned
        // mutation witness, without rejecting our own dirty paint/layout bits.
        guard canReadLayoutSettlement else { return false }
        guard presentationMutationRevision != operation.mutationWitness else { return true }
        guard let target = operation.target else { return false }

        if accessibilityFocusContextIsCurrent(for: target) {
            operation.mutationWitness = presentationMutationRevision
            return focusOperationHasAuthority(operation, expectedFocus: expectedFocus)
        }
        guard mayQuery, operation.remainingQualificationQueries > 0 else { return false }
        operation.remainingQualificationQueries -= 1
        // Keep the original intent and expected focus across the query. A
        // callback cannot rebase this operation onto a newer focus revision.
        guard queryFocusLayout(usingFrameQuery: true),
            focusOperationHasAuthority(operation, expectedFocus: expectedFocus),
            accessibilityFocusContextIsCurrent(for: target)
        else { return false }
        operation.mutationWitness = presentationMutationRevision
        return true
    }

    /// A layout callback may choose focus, but cannot lend that intent to a
    /// suspended entry. Preserve the exact existing query API and retire its
    /// callback frame before conditionally publishing the old entry again.
    @inline(never)
    private func queryFocusLayout(usingFrameQuery: Bool) -> Bool {
        let entry = currentFocusEntry
        let revision = presentationFocusRevision
        currentFocusEntry = nil
        let result = performFocusLayoutQuery(usingFrameQuery: usingFrameQuery)
        if let entry, currentFocusEntry == nil, permitsRenderLifecycleCallbacks,
            !focusRevision.isExhausted, presentationFocusRevision == revision,
            focusedNode === entry.target
        {
            currentFocusEntry = entry
        }
        return result
    }

    @inline(never)
    private func performFocusLayoutQuery(usingFrameQuery: Bool) -> Bool {
        if usingFrameQuery { return resolvedLayoutFrame(of: root) != nil }
        updateResolvedLayout()
        return true
    }

    private func clearFocusEntry(_ entry: RetainedFocusEntry?) {
        if let entry, currentFocusEntry === entry { currentFocusEntry = nil }
    }

    private func takeFocusReaffirmation(_ entry: RetainedFocusEntry?) -> RetainedFocusReaffirmation? {
        guard let entry, currentFocusEntry === entry, let target = entry.target,
            focusedNode === target, !focusRevision.isExhausted,
            let reaffirmation = entry.reaffirmation,
            reaffirmation.revision == presentationFocusRevision
        else { return nil }
        entry.reaffirmation = nil
        return reaffirmation
    }

    private func adoptFocusReaffirmation(_ entry: RetainedFocusEntry?, into operation: RetainedFocusOperation) {
        guard let reaffirmation = takeFocusReaffirmation(entry) else { return }
        operation.origin = reaffirmation.origin
        // A same-entry request must not turn a formerly attached target into
        // a detached construction exception while its entry is incomplete.
        operation.beganAttached = operation.beganAttached || reaffirmation.beganAttached
        operation.revision = reaffirmation.revision
        operation.mutationWitness = reaffirmation.mutationWitness
        // Keep the suspended operation's remaining query budget unchanged.
    }

    private func recordOwnedFocusEffects(_ operation: RetainedFocusOperation) {
        // Only call after the callback-free focus bit, caret, timestamp-fed
        // chrome, or explicit invalidation writes below. This does not alter
        // the runtime's global prepaint or layout settlement authority.
        operation.mutationWitness = presentationMutationRevision
        if let receipt = operation.listNavigationReceipt { recordOwnedListNavigationRevealFocusEffects(receipt) }
        operation.listNavigationReceipt?.recordGeometryRevision(layoutSettlementGeometryRevision)
    }

    // Separate non-inlined frames make callback capture release precede the
    // caller's next validity check, including a self-replacing callback.
    @inline(never)
    private func deliverFocusExit(_ node: ViewNode?) {
        var callback = node?.onFocusExit
        callback?()
        callback = nil
    }

    @inline(never)
    private func deliverFocusEnter(_ node: ViewNode?) {
        var callback = node?.onFocusEnter
        callback?()
        callback = nil
    }

    @inline(never)
    private func deliverAccessibilityFocusNotification(_ node: ViewNode?) {
        var callback = onAccessibilityFocusChanged
        callback?(node)
        callback = nil
    }

    @inline(never)
    private func sampleFocusClock() -> Double {
        var callback: (@MainActor () -> Double)? = clock
        let timestamp = callback?() ?? 0
        callback = nil
        return timestamp
    }

    private func withdrawFocusOperation(_ operation: RetainedFocusOperation) {
        guard let revision = operation.revision, presentationFocusRevision == revision,
            let target = operation.target, focusedNode === target
        else { return }
        focusedNode = nil
        target.isFocused = false
    }

    @discardableResult
    private func updateFocusTarget(
        to nextFocusedNode: ViewNode?, origin: RetainedFocusOrigin = .ordinary,
        listNavigationReceipt: RetainedListNavigationReceipt? = nil
    ) -> Bool {
        let isCleanup = origin == .cleanup && nextFocusedNode == nil
        guard permitsRenderLifecycleCallbacks || isCleanup else { return false }
        let beganAttached =
            nextFocusedNode.map {
                isAttachedFocusNode($0)
                    || (currentFocusEntry?.target === $0 && currentFocusEntry?.beganAttached == true)
            } ?? false
        if let nextFocusedNode {
            guard focusTargetIsEligible(nextFocusedNode, origin: origin, beganAttached: beganAttached) else {
                return false
            }
        }
        let revision = advanceFocusRevision()
        guard revision != nil || isCleanup else { return false }
        let operation = RetainedFocusOperation(
            target: nextFocusedNode, origin: origin, beganAttached: beganAttached,
            revision: revision, mutationWitness: presentationMutationRevision,
            listNavigationReceipt: listNavigationReceipt)
        let completed = performFocusTransition(operation, to: nextFocusedNode)
        // The inner frame has released its old node and callback captures.
        // Final notification/cleanup can make an already performed transition
        // unqualified; do not query, retry, or roll back a newer focus here.
        let isCurrent = validateFocusOperation(operation, expectedFocus: nextFocusedNode, mayQuery: false)
        let ownsOriginalIntent = origin != .accessibility || operation.revision == revision
        return completed && isCurrent && ownsOriginalIntent
            && (!operation.hasTarget || nextFocusedNode?.isFocused == true)
    }

    @inline(never)
    private func performFocusTransition(_ operation: RetainedFocusOperation, to nextFocusedNode: ViewNode?) -> Bool {
        guard focusedNode !== nextFocusedNode else {
            if let entry = currentFocusEntry, let nextFocusedNode, entry.target === nextFocusedNode,
                let revision = operation.revision
            {
                entry.reaffirmation = RetainedFocusReaffirmation(
                    revision: revision, origin: operation.origin, beganAttached: operation.beganAttached,
                    mutationWitness: operation.mutationWitness)
            }
            return true
        }
        // Only this entry can consume its same-target reaffirmation. A full
        // nested away-and-back transition cannot revive an outer witness.
        currentFocusEntry = nil
        var previousNode = focusedNode
        var previousTimestamp = 0.0
        if previousNode?.interactionSurface != nil, permitsRenderLifecycleCallbacks {
            let mutationBeforeClock = presentationMutationRevision
            previousTimestamp = sampleFocusClock()
            if presentationMutationRevision != mutationBeforeClock { operation.listNavigationReceipt?.cancelReveal() }
            guard validateFocusOperation(operation, expectedFocus: previousNode, mayQuery: true) else { return false }
        }
        focusedNode = nil
        previousNode?.isFocused = false
        applyInteractionChrome(to: previousNode, animated: permitsRenderLifecycleCallbacks, at: previousTimestamp)
        recordOwnedFocusEffects(operation)
        let mutationBeforeExit = presentationMutationRevision
        deliverFocusExit(previousNode)
        previousNode = nil
        // Include the old node's final payload release as well as the exit
        // helper's callback-capture cleanup before recording owned effects.
        if presentationMutationRevision != mutationBeforeExit { operation.listNavigationReceipt?.cancelReveal() }
        guard validateFocusOperation(operation, expectedFocus: nil, mayQuery: true) else { return false }

        focusedNode = nextFocusedNode
        nextFocusedNode?.isFocused = true
        recordOwnedFocusEffects(operation)
        let entry = nextFocusedNode.map { RetainedFocusEntry(target: $0, beganAttached: operation.beganAttached) }
        currentFocusEntry = entry
        defer { clearFocusEntry(entry) }
        let mutationBeforeEnter = presentationMutationRevision
        deliverFocusEnter(nextFocusedNode)
        if presentationMutationRevision != mutationBeforeEnter { operation.listNavigationReceipt?.cancelReveal() }
        return finishFocusEntry(operation, to: nextFocusedNode, entry: entry)
    }

    @inline(never)
    private func finishFocusEntry(
        _ operation: RetainedFocusOperation, to nextFocusedNode: ViewNode?, entry: RetainedFocusEntry?,
        at sampledTimestamp: Double? = nil
    ) -> Bool {
        defer { clearFocusEntry(entry) }
        adoptFocusReaffirmation(entry, into: operation)
        guard validateFocusOperation(operation, expectedFocus: nextFocusedNode, mayQuery: true) else {
            withdrawFocusOperation(operation)
            return false
        }
        resetCaretBlink()
        recordOwnedFocusEffects(operation)
        var timestamp = sampledTimestamp ?? 0
        if sampledTimestamp == nil, nextFocusedNode?.interactionSurface != nil, permitsRenderLifecycleCallbacks {
            let mutationBeforeClock = presentationMutationRevision
            timestamp = sampleFocusClock()
            if presentationMutationRevision != mutationBeforeClock { operation.listNavigationReceipt?.cancelReveal() }
            adoptFocusReaffirmation(entry, into: operation)
            guard validateFocusOperation(operation, expectedFocus: nextFocusedNode, mayQuery: true) else {
                withdrawFocusOperation(operation)
                return false
            }
        }
        applyInteractionChrome(to: nextFocusedNode, animated: permitsRenderLifecycleCallbacks, at: timestamp)
        invalidate()
        recordOwnedFocusEffects(operation)
        clearFocusEntry(entry)
        let mutationBeforeNotification = presentationMutationRevision
        deliverAccessibilityFocusNotification(nextFocusedNode)
        if presentationMutationRevision != mutationBeforeNotification {
            operation.listNavigationReceipt?.cancelReveal()
        }
        return true
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
    var didScroll = false
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
    case preferredWidth
    case preferredHeight
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
        guard duration > 0, elapsed < duration else {
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
        guard duration > 0, elapsed < duration else {
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

@MainActor
private struct LazyListAttachmentEntry {
    let node: ViewNode
    let children: [ViewNode]
    var attachment: RetainedLazyListAttachmentProof
    let identity: RetainedLazyListViewIdentityProof
    let controller: (any RetainedTextInputController)?
    let observerStorage: RetainedScrollObserverStorage?
    let adapter: RetainedLazyListRuntimeAdapter?

    init(_ node: ViewNode) {
        self.node = node
        children = node.children
        attachment = node.captureLazyListAttachmentProof()
        identity = node.captureLazyListIdentityProof()
        controller = node.textInputController
        observerStorage = node.scrollObserverStorage
        adapter = node.retainedLazyListAdapter
    }

    var isCurrent: Bool {
        attachment.isCurrent && identity.isCurrent && ViewNode.sameLazyListChildren(children, node.children)
            && node.textInputController === controller && node.scrollObserverStorage === observerStorage
            && node.retainedLazyListAdapter === adapter
    }
}

/// The current parent membership and every subtree accepted before a later
/// controller callback. This is native data, not an arbitrary validator.
@MainActor
private struct LazyListPublishedChildrenProof {
    weak var parent: ViewNode?
    let attachment: RetainedLazyListAttachmentProof
    let identity: RetainedLazyListViewIdentityProof
    let children: [ViewNode]
    let entries: [LazyListAttachmentEntry]

    var isCurrent: Bool {
        guard let parent else { return false }
        return attachment.isCurrent && identity.isCurrent && ViewNode.sameLazyListChildren(children, parent.children)
            && entries.allSatisfy(\.isCurrent)
    }
}

@MainActor
private struct LazyListRetiredNode {
    let node: ViewNode
    let runtime: RetainedViewRuntime?
    let controller: (any RetainedTextInputController)?
    let observerStorage: RetainedScrollObserverStorage?
    let adapter: RetainedLazyListRuntimeAdapter?
    let dismantle: ((ViewNode) -> Void)?
    let disappear: (() -> Void)?
    let disappearWithNode: ((ViewNode) -> Void)?
    let tasks: [Task<Void, Never>]
    let history: [Any]

    init(_ node: ViewNode) {
        self.node = node
        runtime = node.runtime
        controller = node.textInputController
        observerStorage = node.scrollObserverStorage
        adapter = node.retainedLazyListAdapter
        dismantle = node.onDismantlePlatformView
        disappear = node.hasAppeared ? node.onDisappear : nil
        disappearWithNode = node.hasAppeared ? node.onDisappearWithNode : nil
        // Both helpers transfer old payloads without releasing them. In
        // particular, geometry history destructors cannot run during capture.
        tasks = node.takeLifecycleTasks()
        history = node.scrollObserverStorage?.takeLazyListRetiredHistory() ?? []
        node.consumeLazyListAppearanceForRetirement()
    }
}

/// This contains only native identity/weak references. The delayed completion
/// must not retain captured callbacks or opaque history after it clears gates.
@MainActor
private final class LazyListRetirementGate {
    let identity = RetainedLazyListAttachmentIdentity()
    private let nodes: [WeakViewNodeRef]
    private var didFinish = false

    init(nodes: [ViewNode]) {
        self.nodes = nodes.map { WeakViewNodeRef(node: $0) }
        for node in nodes { node.installLazyListRetirementGate(identity) }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        for reference in nodes {
            reference.node?.finishLazyListRetirementGate(identity)
        }
    }
}

extension ViewNode {
    /// Claim complete group owners across a physical forest before its first
    /// callback. Individual participant states may return the same native
    /// owner; claiming is one-shot and never cancels application Tasks here.
    fileprivate static func claimLazyGroupTaskDepartures(in roots: [ViewNode]) -> [RetainedLazyListAcceptedTaskCleanup]
    {
        var pending = roots
        var visited = Set<ObjectIdentifier>()
        var cleanup: [RetainedLazyListAcceptedTaskCleanup] = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            if let state = node.existingRetainedTaskState {
                cleanup.append(contentsOf: state.claimLazyGroupTaskDepartures())
            }
            pending.append(contentsOf: node.children)
        }
        return cleanup
    }

    /// The shared completion snapshot lives in ComponentHost.swift; keep the
    /// runtime reference fileprivate and expose only this native comparison.
    func hasSameLazyListRuntime(as other: ViewNode) -> Bool { runtime === other.runtime }

    /// Prepared reconciliation calls this for each actual departure batch,
    /// recursively, BEFORE any ownership revocation or property adoption.
    /// The second call in setChildrenChecked is a defensive repeat.
    static func supportsLazyListRemoval(
        of roots: [ViewNode], admission: RetainedLazyListAdoptionAdmission?,
        removalReason: RetainedChildRemovalReason = .structural,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil
    ) -> Bool {
        guard admission?.isCurrent != false, lazyJournal?.canContinueAdoption != false,
            let nodes = lazyListNodes(in: roots)
        else { return false }
        guard nodes.allSatisfy({ !$0.isRetiringLazyListAttachment }) else { return false }
        for root in roots {
            let reason: RetainedChildRemovalReason
            switch removalReason {
            case .virtualization: reason = .virtualization
            case .structural: reason = admission?.removalReason(for: root) ?? .structural
            }
            if case .structural = reason, root.runtime != nil, root.transition.removal.kind != .identity {
                // A structural overlay defers disappearance until animation
                // completion. This dormant slice has no captured-overlay
                // completion/close bridge, so it must not change that timing.
                return false
            }
        }
        let identifiers = Set(nodes.map(ObjectIdentifier.init))
        var inspectedRuntimes = Set<ObjectIdentifier>()
        for node in nodes {
            guard let runtime = node.runtime,
                inspectedRuntimes.insert(ObjectIdentifier(runtime)).inserted
            else { continue }
            guard runtime.canRetireLazyListInteractionOwners(in: identifiers) else { return false }
        }
        return admission?.isCurrent != false && lazyJournal?.canContinueAdoption != false
    }

    /// A bounded-depth physical-tree walk, not a walk of logical model IDs.
    /// Reject a malformed/cyclic snapshot before publishing any mutation.
    fileprivate static func lazyListNodes(in roots: [ViewNode]) -> [ViewNode]? {
        var result: [ViewNode] = []
        var work = roots.reversed().map { ($0, 0) }
        var seen = Set<ObjectIdentifier>()
        while let (node, depth) = work.popLast() {
            guard depth < maximumTraversalDepth, seen.insert(ObjectIdentifier(node)).inserted else { return nil }
            result.append(node)
            for child in node.children.reversed() {
                guard child.parent === node, child.runtime === node.runtime else { return nil }
                work.append((child, depth + 1))
            }
        }
        return result
    }

    fileprivate static func sameLazyListChildren(_ first: [ViewNode], _ second: [ViewNode]) -> Bool {
        first.count == second.count && zip(first, second).allSatisfy { pair in pair.0 === pair.1 }
    }

    fileprivate func installLazyListRetirementGate(_ identity: RetainedLazyListAttachmentIdentity) {
        if lifecycleHandlers == nil { lifecycleHandlers = ViewNodeLifecycleHandlers() }
        lifecycleHandlers?.lazyListRetirementIdentity = identity
    }

    fileprivate func finishLazyListRetirementGate(_ identity: RetainedLazyListAttachmentIdentity) {
        guard lifecycleHandlers?.lazyListRetirementIdentity === identity else { return }
        // The claim prevented another node from acquiring this adapter while
        // old mounted payloads and callbacks were being drained. It confers no
        // runtime, focus, UIA, or physical attachment power.
        if let adapter = retainedLazyListAdapter, adapter.ownsAttachment(self) {
            adapter.releaseAttachment(from: self)
        }
        lifecycleHandlers?.lazyListRetirementIdentity = nil
    }

    fileprivate func consumeLazyListAppearanceForRetirement() {
        hasAppeared = false
        hasPendingAppearanceCallbacks = false
        hasPendingAppearanceNodeCallback = false
        isInitialBuildNode = false
        didPlayInsertionTransition = false
    }

    @discardableResult
    func setChildren(
        _ nextChildren: [ViewNode], admission: RetainedLazyListAdoptionAdmission? = nil,
        removalReason: RetainedChildRemovalReason = .structural,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil,
        sourceParent: ViewNode? = nil
    ) -> RetainedLazyListAdoptionResult {
        guard !isRetiringLazyListAttachment,
            lazyJournal?.isOrdinaryAdoption == true || lazyJournal?.canContinueAdoption != false
        else {
            return RetainedLazyListAdoptionResult(completed: false, didMutate: false, children: children)
        }
        if admission == nil, lazyJournal?.isOrdinaryAdoption != false {
            let changed = !isChildListUnchanged(nextChildren)
            setChildrenUnchecked(
                nextChildren, lazyJournal: lazyJournal, taskAdoption: taskAdoption, sourceParent: sourceParent)
            return RetainedLazyListAdoptionResult(
                completed: isChildListUnchanged(nextChildren), didMutate: changed, children: children)
        }
        guard admission?.permitsMutation(of: self) != false else {
            return lazyListChildResult(false, admission: admission, lazyJournal: lazyJournal)
        }
        let parentAttachment = captureLazyListAttachmentProof()
        let parentIdentity = captureLazyListIdentityProof()
        let interactionRuntime = runtime
        interactionRuntime?.beginLongPressReconciliation()
        let completion = setChildrenChecked(
            nextChildren, admission: admission, parentAttachment: parentAttachment, parentIdentity: parentIdentity,
            removalReason: removalReason,
            lazyJournal: lazyJournal, taskAdoption: taskAdoption, sourceParent: sourceParent)
        // Do not form the result in a return followed by a defer. Ending this
        // scope can drain callbacks that change both admission and children.
        interactionRuntime?.endLongPressReconciliation()
        return lazyListChildResult(
            completion?.isCurrent == true && parentAttachment.isCurrent && parentIdentity.isCurrent
                && admission?.permitsMutation(of: self) != false,
            admission: admission, lazyJournal: lazyJournal, completion: completion)
    }

    private func lazyListChildResult(
        _ completed: Bool, admission: RetainedLazyListAdoptionAdmission?,
        lazyJournal: RetainedLazyListAdoptionJournal?,
        completion: RetainedLazyListAdoptionCompletion? = nil
    ) -> RetainedLazyListAdoptionResult {
        RetainedLazyListAdoptionResult(
            completed: completed && admission?.isCurrent != false
                && lazyJournal?.canContinueAdoption != false && completion?.isCurrent == true,
            didMutate: admission?.didMutate ?? (lazyJournal?.hasAcceptedContributions == true),
            children: children, completion: completion)
    }

    private func setChildrenChecked(
        _ nextChildren: [ViewNode], admission: RetainedLazyListAdoptionAdmission?,
        parentAttachment: RetainedLazyListAttachmentProof, parentIdentity: RetainedLazyListViewIdentityProof,
        removalReason: RetainedChildRemovalReason,
        lazyJournal: RetainedLazyListAdoptionJournal?, taskAdoption: RetainedTaskAdoptionContext?,
        sourceParent: ViewNode?
    ) -> RetainedLazyListAdoptionCompletion? {
        guard admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
            lazyJournal?.canContinueAdoption != false
        else {
            return nil
        }
        if isChildListUnchanged(nextChildren) {
            if let sourceParent, let lazyJournal {
                guard lazyJournal.prepareOwnedStructuralDeclaration(from: sourceParent, to: self) else { return nil }
                lazyJournal.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
            }
            return RetainedLazyListAdoptionCompletion(of: self)
        }
        guard Set(nextChildren.map(ObjectIdentifier.init)).count == nextChildren.count else { return nil }
        let oldChildren = children
        let surviving = Set(nextChildren.map(ObjectIdentifier.init))
        let departing = oldChildren.filter { !surviving.contains(ObjectIdentifier($0)) }
        guard
            Self.supportsLazyListRemoval(
                of: departing, admission: admission, removalReason: removalReason, lazyJournal: lazyJournal),
            let departingNodes = Self.lazyListNodes(in: departing)
        else { return nil }
        let departingIDs = Set(departingNodes.map(ObjectIdentifier.init))
        let survivingChildren = nextChildren.filter { $0.parent === self }
        guard
            survivingChildren.allSatisfy({ child in
                oldChildren.contains(where: { $0 === child }) && child.runtime === runtime
            }), let survivingNodes = Self.lazyListNodes(in: survivingChildren),
            departingNodes.allSatisfy({ $0.runtime === runtime })
        else { return nil }
        var retainedEntries = survivingNodes.map(LazyListAttachmentEntry.init)

        // Existing retained children survive in place. Every new subtree must
        // still be a detached candidate from this attempt. A callback may move
        // it elsewhere; this path never steals it back from the new owner.
        var incoming: [ObjectIdentifier: [LazyListAttachmentEntry]] = [:]
        for child in nextChildren where child.parent !== self {
            guard child !== self, let nodes = Self.lazyListNodes(in: [child]),
                nodes.allSatisfy({
                    $0 !== self && !departingIDs.contains(ObjectIdentifier($0))
                        && !$0.isRetiringLazyListAttachment && $0.runtime == nil && !$0.hasAppeared
                }), child.parent?.runtime == nil, child.parent?.isRetiringLazyListAttachment != true
            else { return nil }
            incoming[ObjectIdentifier(child)] = nodes.map(LazyListAttachmentEntry.init)
            for node in nodes {
                guard lazyJournal?.prepareInsertedNode(from: node) != false else { return nil }
            }
        }
        guard admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
            lazyJournal?.canContinueAdoption != false,
            Self.sameLazyListChildren(oldChildren, children)
        else { return nil }

        var expectedChildren = survivingChildren
        // An intermediate survivor list is not the source parent's declared
        // children table. Publish its marker only at the exact final table.
        let publishesFinalSurvivors = Self.sameLazyListChildren(expectedChildren, nextChildren)
        var deferredOwnedDepartures: [ObjectIdentifier: RetainedLazyListDepartureCause] = [:]
        if publishesFinalSurvivors, let sourceParent, let lazyJournal {
            guard lazyJournal.prepareOwnedStructuralDeclaration(from: sourceParent, to: self) else { return nil }
        }
        if !departing.isEmpty {
            guard lazyJournal?.markMutationStarted() != false else { return nil }
            admission?.markMutationStarted()
            deferredOwnedDepartures = retireLazyListChildren(
                departing, nodes: departingNodes, survivingChildren: expectedChildren, admission: admission,
                removalReason: removalReason, lazyJournal: lazyJournal,
                deferringOwnedDeparture: sourceParent != nil && !publishesFinalSurvivors,
                sourceParent: publishesFinalSurvivors ? sourceParent : nil)
        } else if !Self.sameLazyListChildren(expectedChildren, children) {
            guard lazyJournal?.markMutationStarted() != false else { return nil }
            admission?.markMutationStarted()
            children = expectedChildren
            if publishesFinalSurvivors, let sourceParent {
                lazyJournal?.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
            }
            invalidateRuntime(.children)
        }
        guard admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
            lazyJournal?.canContinueAdoption != false,
            retainedEntries.allSatisfy(\.isCurrent),
            Self.sameLazyListChildren(expectedChildren, children)
        else { return nil }

        for (destinationIndex, child) in nextChildren.enumerated() {
            guard admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
                lazyJournal?.canContinueAdoption != false,
                retainedEntries.allSatisfy(\.isCurrent),
                Self.sameLazyListChildren(expectedChildren, children)
            else { return nil }
            if child.parent === self {
                guard children.contains(where: { $0 === child }), child.runtime === runtime else { return nil }
                continue
            }
            guard var entries = incoming[ObjectIdentifier(child)], entries.allSatisfy(\.isCurrent) else {
                return nil
            }
            // Transfer out of a still-current temporary construction parent.
            // No runtime or appearance ownership can exist in this branch.
            if let temporaryParent = child.parent {
                guard temporaryParent.runtime == nil, !temporaryParent.isRetiringLazyListAttachment,
                    let index = temporaryParent.children.firstIndex(where: { $0 === child })
                else { return nil }
                guard lazyJournal?.markMutationStarted() != false else { return nil }
                admission?.markMutationStarted()
                temporaryParent.children.remove(at: index)
                child.revokeLazyListAttachmentProofs()
                child.parent = nil
                temporaryParent.invalidateRuntime(.children)
                entries[0].attachment = child.captureLazyListAttachmentProof()
                // This matches the existing move out of a temporary parent:
                // dismantling may call application code even with runtime nil.
                child.onDismantlePlatformView?(child)
                guard admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
                    lazyJournal?.canContinueAdoption != false,
                    entries.allSatisfy(\.isCurrent),
                    retainedEntries.allSatisfy(\.isCurrent),
                    Self.sameLazyListChildren(expectedChildren, children)
                else { return nil }
            }
            guard child.parent == nil, entries.allSatisfy(\.isCurrent) else { return nil }
            var publishedChildren = expectedChildren
            publishedChildren.insert(child, at: destinationIndex)
            let publishesFinalChildren = Self.sameLazyListChildren(publishedChildren, nextChildren)
            if publishesFinalChildren, let sourceParent, let lazyJournal {
                guard lazyJournal.prepareOwnedStructuralDeclaration(from: sourceParent, to: self) else { return nil }
            }
            guard lazyJournal?.markMutationStarted() != false else { return nil }
            admission?.markMutationStarted()
            child.revokeLazyListAttachmentProofs()
            child.parent = self
            expectedChildren = publishedChildren
            children = expectedChildren
            if publishesFinalChildren, let sourceParent {
                lazyJournal?.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
            }
            if publishesFinalChildren {
                // Earlier outgoing callbacks saw suspended structural writes.
                // Only this final accepted table can now decide which owned
                // declarations remain dormant and which slots actually leave.
                for node in departingNodes {
                    if let cause = deferredOwnedDepartures[ObjectIdentifier(node)] {
                        lazyJournal?.recordOwnedPhysicalDeparture(of: node, cause: cause)
                    }
                }
                deferredOwnedDepartures.removeAll()
            }
            invalidateRuntime(.children)
            entries[0].attachment = child.captureLazyListAttachmentProof()
            let published = LazyListPublishedChildrenProof(
                parent: self, attachment: parentAttachment, identity: parentIdentity,
                children: expectedChildren, entries: retainedEntries)
            guard
                let attachedEntries = child.attachLazyListCandidate(
                    entries: entries, to: runtime, published: published, admission: admission,
                    lazyJournal: lazyJournal, taskAdoption: taskAdoption),
                admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
                lazyJournal?.canContinueAdoption != false,
                retainedEntries.allSatisfy(\.isCurrent),
                Self.sameLazyListChildren(expectedChildren, children)
            else { return nil }
            // A later attachment callback can move a previously inserted
            // subtree away and back. Keep its new native proof in the same
            // cumulative set as the rows that survived this reconciliation.
            retainedEntries.append(contentsOf: attachedEntries)
        }
        guard admission?.isCurrent != false, parentAttachment.isCurrent && parentIdentity.isCurrent,
            lazyJournal?.canContinueAdoption != false,
            retainedEntries.allSatisfy(\.isCurrent),
            isChildListUnchanged(nextChildren)
        else { return nil }
        return RetainedLazyListAdoptionCompletion(of: self)
    }

    /// Publish a complete departure batch before any old callback or opaque
    /// history payload is released. Reentry cannot revive these attachments.
    private func retireLazyListChildren(
        _ roots: [ViewNode], nodes: [ViewNode], survivingChildren: [ViewNode],
        admission: RetainedLazyListAdoptionAdmission?, removalReason: RetainedChildRemovalReason,
        lazyJournal: RetainedLazyListAdoptionJournal?,
        deferringOwnedDeparture: Bool,
        sourceParent: ViewNode?
    ) -> [ObjectIdentifier: RetainedLazyListDepartureCause] {
        let interactionRuntime = runtime
        let groupTaskCleanup = Self.claimLazyGroupTaskDepartures(in: roots)
        if let lazyJournal {
            for cleanup in groupTaskCleanup { lazyJournal.claimTaskCleanup(cleanup) }
        }
        // Capture and revoke every original scoped state before even the first
        // controller revocation. A zero-slot state still owns attachment and
        // pending declaration authority; later callbacks cannot redirect this
        // cleanup to a replacement state installed on the same ViewNode.
        var scopedTaskCleanup: [RetainedLazyListAcceptedTaskCleanup] = []
        var departureCauses: [ObjectIdentifier: RetainedLazyListDepartureCause] = [:]
        for root in roots {
            let cause: RetainedLazyListDepartureCause
            switch admission?.removalReason(for: root) ?? removalReason {
            case .virtualization: cause = .viewportEviction
            case .structural: cause = .acceptedReplacement
            }
            var pending = [root]
            while let node = pending.popLast() {
                departureCauses[ObjectIdentifier(node)] = cause
                pending.append(contentsOf: node.children)
            }
        }
        for node in nodes {
            let cause = departureCauses[ObjectIdentifier(node)] ?? .acceptedReplacement
            let departure = lazyJournal?.recordPhysicalDeparture(of: node, cause: cause, retireOwned: false)
            if let state = node.existingRetainedTaskState {
                let cleanup: RetainedLazyListAcceptedTaskCleanup
                if let departure {
                    cleanup = state.claimLazyPhysicalDeparture(departure)
                } else {
                    cleanup = state.claimLazyPhysicalDeparture()
                }
                scopedTaskCleanup.append(cleanup)
                lazyJournal?.claimTaskCleanup(cleanup)
            }
        }
        let gate = LazyListRetirementGate(nodes: nodes)
        // This phase is required by RetainedTextInputController's contract to
        // invoke no bindings, release no application payloads, and run no app
        // callbacks. Opaque implementations must honor that contract.
        for node in nodes {
            node.fileDialogPresenterIsDeparting = true
            node.fileDialogPresenterLease?.invalidate()
            node.revokeLazyListAttachmentProofs()
            node.retainedLazyListAdapter?.revokePendingCandidate()
        }
        for node in nodes { node.textInputController?.revokeOwnership(from: node) }

        // Capture task/history/appearance state before publishing callbacks.
        // The helper's scope releases every captured old payload while gates
        // are still installed; its return does not permit obsolete adoption.
        publishAndDrainLazyListRetirement(
            roots: roots, nodes: nodes, survivingChildren: survivingChildren,
            interactionRuntime: interactionRuntime, admission: admission,
            scopedTaskCleanup: scopedTaskCleanup, groupTaskCleanup: groupTaskCleanup,
            lazyJournal: lazyJournal, sourceParent: sourceParent,
            departureCauses: departureCauses, deferringOwnedDeparture: deferringOwnedDeparture)
        if let interactionRuntime {
            // Long-press terminal callbacks use the existing reconciliation
            // queue. Their captured cleanup must run before reattachment is
            // possible; no additional scheduler is introduced here.
            interactionRuntime.afterRetainedCallbacks { gate.finish() }
        } else {
            gate.finish()
        }
        return deferringOwnedDeparture ? departureCauses : [:]
    }

    private func publishAndDrainLazyListRetirement(
        roots: [ViewNode], nodes: [ViewNode], survivingChildren: [ViewNode],
        interactionRuntime: RetainedViewRuntime?, admission: RetainedLazyListAdoptionAdmission?,
        scopedTaskCleanup: [RetainedLazyListAcceptedTaskCleanup],
        groupTaskCleanup: [RetainedLazyListAcceptedTaskCleanup],
        lazyJournal: RetainedLazyListAdoptionJournal?, sourceParent: ViewNode?,
        departureCauses: [ObjectIdentifier: RetainedLazyListDepartureCause], deferringOwnedDeparture: Bool
    ) {
        let captured = nodes.map(LazyListRetiredNode.init)
        children = survivingChildren
        if let sourceParent {
            lazyJournal?.recordAcceptedOwnedStructuralDeclaration(from: sourceParent, to: self)
        }
        if !deferringOwnedDeparture {
            for node in nodes {
                if let cause = departureCauses[ObjectIdentifier(node)] {
                    lazyJournal?.recordOwnedPhysicalDeparture(of: node, cause: cause)
                }
            }
        }
        for root in roots {
            root.revokeLazyListAttachmentProofs()
            root.parent = nil
        }
        for entry in captured {
            let node = entry.node
            entry.runtime?.unregisterLazyListContainer(node)
            entry.runtime?.unregisterScrollObservationNode(node)
            entry.runtime?.unregisterAnimatingNode(node)
            entry.runtime?.cancelColorAnimations(of: node)
            if let state = node.scrollContainerState { state.attachmentGeneration &+= 1 }
            node.revokeLazyListAttachmentProofs()
            node.storedAccessibilityAttachmentIdentity = nil
            node.runtime = nil
        }
        invalidateRuntime(.children)
        let interactionCallbacks = interactionRuntime?.takeLazyListRetiredInteractionCallbacks(in: nodes) ?? []

        // These are already-admitted cleanup obligations, not permission to
        // adopt more nodes. They all finish even when an earlier callback
        // revokes the candidate, changes the source, or closes the host.
        for entry in captured where entry.runtime != nil { entry.controller?.willDetach(from: entry.node) }
        for callback in interactionCallbacks { callback() }
        for entry in captured {
            entry.dismantle?(entry.node)
            entry.disappear?()
            entry.disappearWithNode?(entry.node)
        }
        for entry in captured {
            for task in entry.tasks { task.cancel() }
            if entry.runtime != nil { entry.controller?.detach(from: entry.node) }
        }
        for cleanup in scopedTaskCleanup { cleanup.finish() }
        for cleanup in groupTaskCleanup { cleanup.finish() }
        for entry in captured {
            if let adapter = entry.adapter, adapter.ownsAttachment(entry.node) {
                adapter.releaseMountedRecords()
            }
        }
        // Old history and task/controller captures unwind here, after the
        // stored child/runtime writes and before retireLazyListChildren can
        // arrange gate completion or inspect admission again.
        withExtendedLifetime(captured) {}
        withExtendedLifetime(interactionCallbacks) {}
        withExtendedLifetime(scopedTaskCleanup) {}
    }

    /// The checked path only accepts previously detached incoming trees. It
    /// never runs the callbackful legacy setRuntime over an attached old tree.
    /// Actual parent membership has already been published by the caller.
    private func attachLazyListCandidate(
        entries originalEntries: [LazyListAttachmentEntry], to nextRuntime: RetainedViewRuntime?,
        published: LazyListPublishedChildrenProof,
        admission: RetainedLazyListAdoptionAdmission?,
        lazyJournal: RetainedLazyListAdoptionJournal?, taskAdoption: RetainedTaskAdoptionContext?
    ) -> [LazyListAttachmentEntry]? {
        var entries = originalEntries
        guard admission?.isCurrent != false, published.isCurrent, lazyJournal?.canContinueAdoption != false,
            entries.allSatisfy(\.isCurrent),
            entries.allSatisfy({ !$0.node.isRetiringLazyListAttachment && $0.node.runtime == nil }),
            nextRuntime?.permitsRetainedActionInvocation != false
        else { return nil }
        for entry in entries {
            let node = entry.node
            if nextRuntime != nil {
                node.storedAccessibilityAttachmentIdentity = nil
                node.revokeLazyListAttachmentProofs()
                if let state = node.scrollContainerState { state.attachmentGeneration &+= 1 }
                node.fileDialogPresenterLease?.invalidate()
                node.fileDialogPresenterIsDeparting = false
                node.fileDialogPreparedRevocations = 0
            }
            node.runtime = nextRuntime
            if !node.animationStates.isEmpty { nextRuntime?.registerAnimatingNode(node) }
            if entry.observerStorage != nil { nextRuntime?.registerScrollObservationNode(node) }
            if entry.adapter != nil { nextRuntime?.registerLazyListContainer(node) }
        }
        // These are the exact controlled attachment changes just published.
        // No application call has occurred since the previous proof checks.
        for index in entries.indices {
            entries[index].attachment = entries[index].node.captureLazyListAttachmentProof()
        }
        // All native parent/runtime writes have landed, and no controller has
        // run. Publish insertion acceptance at this boundary, never by scanning
        // the final children after an attachment callback has released captures.
        if let lazyJournal {
            for entry in entries {
                let node = entry.node
                let accepted = lazyJournal.recordAcceptedInsertedNode(on: node)
                for group in accepted {
                    taskAdoption?.associateLazyAccepted(group, journal: lazyJournal)
                }
                for group in lazyJournal.takeAcceptedDescriptorTaskGroups() {
                    taskAdoption?.associateDescriptorAccepted(group, journal: lazyJournal)
                }
            }
        }
        // Do not run even the first controller if a nested adapter failed its
        // physical claim during publication. The partial tree is incomplete.
        guard
            entries.allSatisfy({ entry in
                nextRuntime == nil || entry.adapter == nil || entry.adapter?.ownsAttachment(entry.node) == true
            })
        else { return nil }
        for entry in entries {
            guard admission?.isCurrent != false, published.isCurrent, lazyJournal?.canContinueAdoption != false,
                entries.allSatisfy(\.isCurrent),
                nextRuntime?.permitsRetainedActionInvocation != false,
                entry.node.textInputController === entry.controller,
                entry.node.scrollObserverStorage === entry.observerStorage,
                entry.node.retainedLazyListAdapter === entry.adapter
            else { return nil }
            if let adapter = entry.adapter, nextRuntime != nil, !adapter.ownsAttachment(entry.node) {
                return nil
            }
            if nextRuntime != nil { entry.controller?.attach(to: entry.node) }
            guard admission?.isCurrent != false, published.isCurrent, lazyJournal?.canContinueAdoption != false,
                entries.allSatisfy(\.isCurrent),
                entry.node.textInputController === entry.controller
            else { return nil }
        }
        if let lazyJournal {
            for entry in entries {
                guard admission?.isCurrent != false, published.isCurrent, lazyJournal.canContinueAdoption,
                    entries.allSatisfy(\.isCurrent)
                else { return nil }
                let accepted = lazyJournal.recordCompletedNode(from: entry.node, to: entry.node)
                for group in accepted {
                    taskAdoption?.associateLazyAccepted(group, journal: lazyJournal)
                }
                for group in lazyJournal.takeAcceptedDescriptorTaskGroups() {
                    taskAdoption?.associateDescriptorAccepted(group, journal: lazyJournal)
                }
                admission?.recordCompletedOwnedSource(from: entry.node, to: entry.node, journal: lazyJournal)
            }
        }
        return admission?.isCurrent != false && lazyJournal?.canContinueAdoption != false
            && published.isCurrent && entries.allSatisfy(\.isCurrent) ? entries : nil
    }
}

extension RetainedViewRuntime {
    /// No mutation/callbacks: retirement does not copy existing programmatic
    /// scroll cancellation/anchor policy for a surviving outside container.
    fileprivate func canRetireLazyListInteractionOwners(in identifiers: Set<ObjectIdentifier>) -> Bool {
        func isDeparting(_ node: ViewNode?) -> Bool {
            node.map { identifiers.contains(ObjectIdentifier($0)) } ?? false
        }
        for tween in scrollPresentedTweens.values {
            if tween.origin.isProgrammatic, isDeparting(tween.target), !isDeparting(tween.node) { return false }
        }
        for alignment in pendingPreciseScrollAlignments {
            if isDeparting(alignment.target) || isDeparting(alignment.coarseTarget),
                !isDeparting(alignment.container)
            {
                return false
            }
        }
        return true
    }

    /// Native ownership removal only. It must run after ALL departed nodes
    /// have runtime nil and their editor/file-dialog leases revoked, before
    /// the first old controller, task, history, or lifecycle callback runs.
    /// It deliberately does not call pointerCancelled/updateFocusTarget/
    /// updateHoverTarget, which have trailing live-owner writes and clocks.
    fileprivate func takeLazyListRetiredInteractionCallbacks(in nodes: [ViewNode]) -> [@MainActor () -> Void] {
        let identifiers = Set(nodes.map(ObjectIdentifier.init))
        func isDeparting(_ node: ViewNode?) -> Bool {
            node.map { identifiers.contains(ObjectIdentifier($0)) } ?? false
        }
        precondition(canRetireLazyListInteractionOwners(in: identifiers))
        var callbacks: [@MainActor () -> Void] = []
        var pointerUpOutside: (() -> Void)?

        // All motion whose physical owner leaves can be discarded natively.
        // A tween owned outside this batch was rejected by the preflight.
        pendingPreciseScrollAlignments.removeAll {
            $0.container == nil || $0.target == nil || isDeparting($0.container)
        }
        for node in nodes {
            scrollMomenta.removeValue(forKey: ObjectIdentifier(node))
            scrollPresentedTweens.removeValue(forKey: ObjectIdentifier(node))
            node.scrollOvershoot = 0
            node.scrollPresentedDelta = 0
            scrollIndicatorReveals.removeValue(forKey: ObjectIdentifier(node))
        }

        let ownsPointer =
            isDeparting(pressedNode) || isDeparting(longPressAttempt?.node)
            || isDeparting(nodeDragState?.node) || isDeparting(scrollDragState?.node)
            || isDeparting(activeScrollIndicatorNode)
        if ownsPointer {
            pointerSequence &+= 1
            let previousPressed = pressedNode
            let previousDrag = nodeDragState
            let previousAttempt = longPressAttempt
            pressedNode = nil
            buttonRepeatState = nil
            nodeDragState = nil
            scrollDragState = nil
            activeScrollIndicatorNode = nil
            if let previousAttempt, !previousAttempt.didFinish {
                previousAttempt.didFinish = true
                longPressAttempt = nil
                let configuration = previousAttempt.configuration
                let cleanup = previousAttempt.cleanup
                let didNotifyPressing = previousAttempt.didNotifyPressing
                previousAttempt.cleanup = nil
                // Preserve the runtime's normal terminal-callback ordering.
                // The gate finishes through afterRetainedCallbacks afterward.
                callbacks.append { [weak self] in
                    self?.performLongPressCallback {
                        if didNotifyPressing { configuration.onPressingChanged?(false) }
                        cleanup?()
                    }
                }
            }
            if let previousDrag, let dragNode = previousDrag.node, let action = dragNode.onDragEnd {
                let delta = Point(
                    x: previousDrag.lastPoint.x - previousDrag.startPoint.x,
                    y: previousDrag.lastPoint.y - previousDrag.startPoint.y)
                callbacks.append { action(previousDrag.lastPoint, delta) }
            }
            pointerUpOutside = previousPressed?.onPointerUpOutside
            // Retired nodes are not painted; do not create new chrome tweens
            // on them from an old cancellation callback or an authored clock.
        }
        // A hover owner outside the departing batch remains live. Retiring a
        // row must not consume its callbacks or create a new clock/chrome
        // transaction on behalf of an unrelated surviving node.
        if isDeparting(hoveredNode) {
            let previousHover = hoveredNode
            hoveredNode = nil
            previousHover?.isHovered = false
            if let action = previousHover?.onPointerExit {
                callbacks.append { @MainActor [action] in action() }
            }
        }
        if isDeparting(hoveredScrollIndicatorNode) { hoveredScrollIndicatorNode = nil }
        if let pointerUpOutside {
            callbacks.append { @MainActor [pointerUpOutside] in pointerUpOutside() }
        }
        if isDeparting(focusedNode) {
            let previousFocus = focusedNode
            let onExit = previousFocus?.onFocusExit
            let onAccessibilityChange = onAccessibilityFocusChanged
            // advanceFocusRevision can finish authored receipt captures on
            // exhaustion. Keep that cleanup after native ownership publication.
            let revision = focusRevision.advance()
            currentFocusEntry = nil
            let retiredFocusRequests: [RetainedPresentationFocusRequest]
            if revision == nil {
                retiredFocusRequests = pendingPresentationFocusRequests
                for request in retiredFocusRequests { request.revoke() }
                pendingPresentationFocusRequests.removeAll()
            } else {
                retiredFocusRequests = []
            }
            focusedNode = nil
            previousFocus?.isFocused = false
            resetCaretBlink()
            callbacks.append { [weak self] in
                for request in retiredFocusRequests { request.finish() }
                onExit?()
                guard let self, self.permitsRetainedActionInvocation, self.focusedNode == nil else { return }
                if let revision {
                    guard !self.focusRevision.isExhausted, self.presentationFocusRevision == revision else { return }
                } else {
                    guard self.focusRevision.isExhausted else { return }
                }
                onAccessibilityChange?(nil)
            }
        }
        invalidate(.paint)
        return callbacks
    }
}

extension RetainedViewRuntime {
    /// A candidate List can inspect only an already attached predecessor. Typed
    /// path equality runs under both the original physical witness and the
    /// constructing descriptor scope, stopping after each authored key call.
    package func lazyListPredecessor(
        for identity: RetainedViewIdentity, during scope: RetainedLazyListDescriptorBuildScope? = nil
    ) -> RetainedLazyListRuntimeAdapter? {
        guard permitsRetainedActionInvocation, scope?.canConstructDescriptors != false,
            scope == nil || scope?.logicalHostLifetimeForScopeConstruction === lazyListLogicalHostLifetime
        else { return nil }
        var result: RetainedLazyListRuntimeAdapter?
        var resultNode: ViewNode?
        var resultAttachment: RetainedLazyListAttachmentProof?
        var resultIdentity: RetainedLazyListViewIdentityProof?
        var resultBinding: RetainedLazyListManagedLogicalDescriptorBinding?
        let registrations = Array(lazyListRegistrations.values)
        for registration in registrations {
            guard permitsRetainedActionInvocation, scope?.canConstructDescriptors != false else { return nil }
            guard let node = registration.node, let adapter = registration.adapter,
                ownsLazyListAttachment(node), adapter.ownsAttachment(node),
                node.retainedLazyListAdapter === adapter,
                let binding = adapter.managedLogicalDescriptorBinding, binding.isCurrent,
                let currentIdentity = node.retainedViewIdentity
            else { continue }
            let attachment = node.captureLazyListAttachmentProof()
            let identityProof = node.captureLazyListIdentityProof()
            func isCurrent() -> Bool {
                permitsRetainedActionInvocation && scope?.canConstructDescriptors != false
                    && attachment.isCurrent && identityProof.isCurrent
                    && ownsLazyListAttachment(node) && node.retainedLazyListAdapter === adapter
                    && adapter.ownsAttachment(node) && adapter.managedLogicalDescriptorBinding === binding
                    && binding.isCurrent
            }
            guard let matches = currentIdentity.checkedEquals(identity, isCurrent: isCurrent), isCurrent() else {
                return nil
            }
            if matches {
                // An ambiguous raw identity is not permission to pick whichever
                // List happened to register first.
                guard result == nil else { return nil }
                result = adapter
                resultNode = node
                resultAttachment = attachment
                resultIdentity = identityProof
                resultBinding = binding
            }
        }
        guard permitsRetainedActionInvocation, scope?.canConstructDescriptors != false,
            let result, let resultNode, resultAttachment?.isCurrent == true,
            resultIdentity?.isCurrent == true, ownsLazyListAttachment(resultNode),
            resultNode.retainedLazyListAdapter === result, result.ownsAttachment(resultNode),
            result.managedLogicalDescriptorBinding === resultBinding, resultBinding?.isCurrent == true
        else { return nil }
        return result
    }

    private func lazyListContent(in container: ViewNode) -> ViewNode? {
        guard ownsLazyListAttachment(container), !Self.hasHiddenAncestor(container) else { return nil }
        var node = container
        var depth = 0
        while depth < ViewNode.maximumTraversalDepth {
            if let adapter = node.retainedLazyListAdapter {
                return adapter.ownsAttachment(node) && adapter.hasCurrentLogicalSnapshot ? node : nil
            }
            // The public List has one inner lazy stack. Do not search arbitrary
            // branches or accidentally enumerate a nested independent List.
            guard node.children.count == 1, let child = node.children.first,
                child.parent === node, child.runtime === self, !child.isHidden
            else { return nil }
            node = child
            depth += 1
        }
        return nil
    }

    /// One public request can inspect several Lists and then realize its actual
    /// destination. All of that work borrows the active layout budget, including
    /// nested layout queries. A new independent layout pass gets a fresh budget.
    /// This depth is separate from layout depth, which controls anchor proof.
    package func withLazyListResolutionBudget<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        lazyListScrollWorkDepth += 1
        ensureLazyListResolutionBudget()
        defer {
            lazyListScrollWorkDepth -= 1
            finishLazyListResolutionBudgetIfIdle()
        }
        return try body()
    }

    /// Captures only the accepted native source and its exact container path.
    /// An empty source still needs this proof: a later explicit ID search must
    /// not treat an obsolete empty List as proof that no matching row exists.
    package func captureLazyListScrollSource(in container: ViewNode) -> RetainedLazyListScrollSearchCursor? {
        guard permitsRetainedActionInvocation, ownsLazyListAttachment(container),
            let content = lazyListContent(in: container), let adapter = content.retainedLazyListAdapter,
            let lease = content.retainedSubtreeBuildLease, let proof = adapter.captureLayoutProof()
        else { return nil }
        return RetainedLazyListScrollSearchCursor(
            runtime: self, container: container, content: content, adapter: adapter,
            lease: lease, descriptor: adapter.managedLogicalDescriptorBinding, adapterProof: proof)
    }

    /// Unlike an actionable row receipt, a source witness can be checked while
    /// the adapter is constructing a doomed search candidate. It performs no
    /// row lookup, provider callback, or snapshot query that rejects preparing.
    package func isLazyListScrollSourceCurrent(
        _ source: RetainedLazyListScrollSearchCursor, in container: ViewNode
    ) -> Bool {
        permitsRetainedActionInvocation && lazyListScrollSearchIsCurrent(source, in: container)
    }

    /// The caller already checked the live reader tree. Only new detached row
    /// roots reach matches; matching is inspection, not permission to invoke or
    /// retain any candidate action. Neither result nor cursor owns row content.
    package func probeLazyListScrollTarget(
        in container: ViewNode,
        after previous: RetainedLazyListScrollSearchCursor? = nil,
        requestIsCurrent: @escaping @MainActor () -> Bool,
        matches: @MainActor ([ViewNode]) -> Bool
    ) -> RetainedLazyListScrollSearchResult {
        withLazyListResolutionBudget {
            guard !isProbingLazyListScrollTarget else { return .deferred }
            isProbingLazyListScrollTarget = true
            defer { isProbingLazyListScrollTarget = false }
            let result = probeLazyListScrollTargetInCurrentBudget(
                in: container, after: previous,
                requestIsCurrent: requestIsCurrent, matches: matches)
            switch result {
            case .more, .deferred:
                lazyListScrollSearchNeedsMoreWork = true
            case .found, .notFound, .obsolete:
                break
            }
            return result
        }
    }

    private func lazyListScrollSearchIsCurrent(
        _ cursor: RetainedLazyListScrollSearchCursor, in container: ViewNode
    ) -> Bool {
        guard cursor.runtime === self, cursor.container === container,
            cursor.containerAttachment.isCurrent, cursor.contentAttachment.isCurrent,
            cursor.containerIdentity.isCurrent, cursor.contentIdentity.isCurrent,
            cursor.adapterProof.isCurrent, cursor.ancestry.allSatisfy(\.isCurrent),
            let content = cursor.content, let adapter = cursor.adapter,
            let lease = cursor.lease, content.retainedSubtreeBuildLease === lease,
            content.retainedLazyListAdapter === adapter, !Self.hasHiddenAncestor(container),
            adapter.ownsAttachment(content), ownsLazyListAttachment(container), ownsLazyListAttachment(content)
        else { return false }
        if cursor.hadManagedDescriptor {
            guard let descriptor = cursor.descriptor,
                adapter.managedLogicalDescriptorBinding === descriptor, descriptor.isCurrent
            else { return false }
        } else if adapter.managedLogicalDescriptorBinding != nil {
            return false
        }
        // hasCurrentLogicalSnapshot intentionally denies queries while the
        // adapter is preparing. Validate this original path without that query.
        var node = content
        var depth = 0
        while node !== container, depth < ViewNode.maximumTraversalDepth {
            guard let parent = node.parent, parent.children.count == 1,
                parent.children.first === node, !node.isHidden
            else { return false }
            node = parent
            depth += 1
        }
        return node === container
    }

    private func probeLazyListScrollTargetInCurrentBudget(
        in container: ViewNode, after previous: RetainedLazyListScrollSearchCursor?,
        requestIsCurrent: @escaping @MainActor () -> Bool,
        matches: @MainActor ([ViewNode]) -> Bool
    ) -> RetainedLazyListScrollSearchResult {
        guard permitsRetainedActionInvocation, ownsLazyListAttachment(container), requestIsCurrent(),
            permitsRetainedActionInvocation, ownsLazyListAttachment(container)
        else { return .obsolete }
        guard !isLayoutInProgress, !hasActiveRetainedBuild, activeAccessibilityMutation == nil else {
            return .deferred
        }
        let originalAttachment = container.captureLazyListAttachmentProof()
        let originalIdentity = container.captureLazyListIdentityProof()
        // An existing after-layout callback already has its fresh native pass.
        // It must not recursively enter updateResolvedLayout from this hook.
        if !isUpdatingResolvedLayout, !hasCompletedLayout || hasPendingLayout {
            updateResolvedLayout()
        }
        guard originalAttachment.isCurrent, originalIdentity.isCurrent,
            requestIsCurrent(), originalAttachment.isCurrent, originalIdentity.isCurrent,
            ownsLazyListAttachment(container)
        else { return .obsolete }
        guard let content = lazyListContent(in: container), let adapter = content.retainedLazyListAdapter,
            let lease = content.retainedSubtreeBuildLease, let proof = adapter.captureLayoutProof()
        else { return .deferred }
        let cursor =
            previous
            ?? RetainedLazyListScrollSearchCursor(
                runtime: self, container: container, content: content, adapter: adapter,
                lease: lease, descriptor: adapter.managedLogicalDescriptorBinding, adapterProof: proof)
        func isCurrent() -> Bool {
            guard lazyListScrollSearchIsCurrent(cursor, in: container) else { return false }
            let current = requestIsCurrent()
            return current && lazyListScrollSearchIsCurrent(cursor, in: container)
        }
        guard isCurrent() else { return .obsolete }
        if adapter.logicalRecordCount == 0 { return .notFound }
        guard let budget = lazyListResolutionBudget, budget.remainingElements > 0,
            budget.consumeRound()
        else { return .deferred }
        let canBuild = lease.canBuild
        guard isCurrent() else { return .obsolete }
        guard canBuild else { return .deferred }
        let coordinator = retainedBuildCoordinator
        guard let sequence = coordinator.beginBuild() else { return .deferred }
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: content, runtime: self, coordinator: coordinator, sequence: sequence)
        let transaction = RetainedBuildTransaction()
        var epoch: (any RetainedBuildEpoch)?
        var journal: RetainedLazyListAdoptionJournal?
        var probe: RetainedLazyListRuntimeAdapter.ScrollProbeResult = .obsolete
        beginLongPressReconciliation()
        transaction.perform {
            defer {
                // A probe never calls willAdopt or mutates the retained tree.
                // Revocation precedes teardown of candidate values and actions.
                admission.revoke()
                journal?.revokeBeforeAbandon()
                _ = journal?.seal()
                epoch?.abandon()
            }
            guard isCurrent(), admission.isBuildCurrent else { return }
            epoch = lease.beginBuild()
            coordinator.install(epoch, startedAt: sequence)
            guard isCurrent(), admission.isBuildCurrent, let activeEpoch = epoch else { return }
            let mayConstruct = activeEpoch.canAdopt
            guard mayConstruct, isCurrent(), admission.isBuildCurrent else { return }
            var activity: (any RetainedLazyListBuildActivity)?
            if let descriptor = adapter.managedLogicalDescriptorBinding {
                guard descriptor.isCurrent, let managed = activeEpoch as? any RetainedLazyListBuildActivity,
                    let scope = coordinator.beginDescriptorBuildScope(
                        origin: .managedSubtree, epoch: activeEpoch, hostLifetime: lazyListLogicalHostLifetime,
                        ownerLifetime: content.lazyListActivityStorage().descriptorOwnerLifetime)
                else { return }
                let candidateJournal = RetainedLazyListAdoptionJournal(
                    admission: admission, transaction: transaction)
                journal = candidateJournal
                let bound = managed.bindLazyListDescriptorScope(scope)
                guard bound, isCurrent(), admission.isBuildCurrent, scope.canConstructDescriptors,
                    candidateJournal.bindDescriptorScope(scope)
                else { return }
                activity = managed
            }
            probe = adapter.probeScrollTarget(
                after: cursor.lastExaminedToken, budget: budget, admission: admission,
                activity: activity, journal: journal, requestIsCurrent: isCurrent, matches: matches)
            // The adapter has destroyed detached row roots and identity-key
            // temporaries before this check. Their deinit may supersede us.
            if !isCurrent() || !admission.isBuildCurrent { probe = .obsolete }
        }
        endLongPressReconciliation()
        var finishedCleanup = false
        afterRetainedCallbacks {
            transaction.perform {
                epoch?.finishAfterCallbacks()
                journal?.finishAcceptedTaskCleanup()
                admission.finishCandidatePayload()
                journal?.releaseUnadoptedTransport()
            }
            // Queued root work cannot run until every speculative payload and
            // provisional state transport is gone from this coordinator scope.
            coordinator.finishBuild()
            finishedCleanup = true
        }
        guard finishedCleanup else { return .deferred }
        guard isCurrent() else { return .obsolete }
        switch probe {
        case .found(let token):
            return adapter.containsLogicalToken(token) ? .found(token) : .obsolete
        case .more(let last):
            // A zero-progress slice is not permission to schedule an endless
            // callback chain when the configured budget is zero or unavailable.
            guard let last, last != cursor.lastExaminedToken else { return .deferred }
            return .more(RetainedLazyListScrollSearchCursor(advancing: cursor, through: last))
        case .notFound:
            return .notFound
        case .obsolete:
            return .obsolete
        }
    }

    package func supportsLazyListAccessibilityItems(in container: ViewNode) -> Bool {
        lazyListContent(in: container) != nil
    }

    package func lazyListTarget(
        in container: ViewNode, token: RetainedLazyListRowToken
    ) -> RetainedLazyListAccessibilityItem? {
        guard let content = lazyListContent(in: container), let adapter = content.retainedLazyListAdapter,
            adapter.containsLogicalToken(token), let attachment = accessibilityTarget(for: content)
        else { return nil }
        return RetainedLazyListAccessibilityItem(
            token: token, container: container, content: content, adapter: adapter,
            runtime: self, attachment: attachment)
    }

    package func lazyListTarget(
        in container: ViewNode, key: RetainedViewIdentity.Key, occurrence: Int = 0
    ) -> RetainedLazyListAccessibilityItem? {
        guard let content = lazyListContent(in: container), let adapter = content.retainedLazyListAdapter,
            let attachment = accessibilityTarget(for: content)
        else { return nil }
        let identity = content.captureLazyListIdentityProof()
        let token = adapter.token(for: key, occurrence: occurrence)
        guard permitsRetainedActionInvocation, attachment.isCurrent(in: self),
            identity.isCurrent,
            lazyListContent(in: container) === content, content.retainedLazyListAdapter === adapter,
            let token, adapter.containsLogicalToken(token)
        else { return nil }
        return RetainedLazyListAccessibilityItem(
            token: token, container: container, content: content, adapter: adapter,
            runtime: self, attachment: attachment)
    }

    package func lazyListAccessibilityItem(
        in container: ViewNode, after previous: RetainedLazyListAccessibilityItem? = nil
    ) -> RetainedLazyListAccessibilityItem? {
        guard let content = lazyListContent(in: container), let adapter = content.retainedLazyListAdapter else {
            return nil
        }
        if let previous {
            guard isLazyListAccessibilityItemCurrent(previous), previous.content === content,
                previous.adapter === adapter
            else { return nil }
        }
        guard let token = adapter.logicalToken(after: previous?.token) else { return nil }
        return lazyListTarget(in: container, token: token)
    }

    package func lazyListAccessibilityItem(
        in container: ViewNode, containing node: ViewNode
    ) -> RetainedLazyListAccessibilityItem? {
        guard let content = lazyListContent(in: container), let adapter = content.retainedLazyListAdapter,
            node.runtime === self, let token = adapter.mountedToken(containing: node)
        else { return nil }
        return lazyListTarget(in: container, token: token)
    }

    package func isLazyListAccessibilityContainerCurrent(_ item: RetainedLazyListAccessibilityItem) -> Bool {
        guard item.runtime === self, permitsRetainedActionInvocation,
            let container = item.container, let content = item.content, let adapter = content.retainedLazyListAdapter,
            item.attachment.isCurrent(in: self), item.identity.isCurrent, item.containerIdentity.isCurrent,
            adapter.logicalMembershipIdentity === item.membership, adapter.ownsAttachment(content),
            ownsLazyListAttachment(container), ownsLazyListAttachment(content), !Self.hasHiddenAncestor(container)
        else { return false }
        if let descriptor = adapter.managedLogicalDescriptorBinding {
            guard descriptor.isCurrent else { return false }
        } else {
            guard adapter.hasCurrentLogicalSnapshot else { return false }
        }
        var node = content
        var depth = 0
        while node !== container, depth < ViewNode.maximumTraversalDepth {
            guard let parent = node.parent, parent.children.count == 1,
                parent.children.first === node, !node.isHidden
            else { return false }
            node = parent
            depth += 1
        }
        return node === container
    }

    package func isLazyListAccessibilityItemCurrent(_ item: RetainedLazyListAccessibilityItem) -> Bool {
        guard isLazyListAccessibilityContainerCurrent(item), let adapter = item.adapter,
            item.content?.retainedLazyListAdapter === adapter, adapter.hasCurrentLogicalSnapshot
        else { return false }
        return adapter.containsLogicalToken(item.token)
    }

    /// Logical presence only: an accepted successor may not have prepared any
    /// rows yet. Keep the original container namespace, but query the currently
    /// installed adapter rather than granting the witness's old physical item.
    package func isLazyListAccessibilityTokenCurrent(
        _ token: RetainedLazyListRowToken, in witness: RetainedLazyListAccessibilityItem
    ) -> Bool {
        guard isLazyListAccessibilityContainerCurrent(witness),
            let adapter = witness.content?.retainedLazyListAdapter
        else { return false }
        return adapter.containsAcceptedLogicalToken(token)
    }

    /// The caller holds one withLazyListResolutionBudget around this preparation
    /// and its subsequent realizer. This does one ordinary layout query, then
    /// reconstructs the same logical token without reviving an old row receipt.
    @inline(never)
    package func prepareLazyListAccessibilityTarget(
        token: RetainedLazyListRowToken, in witness: RetainedLazyListAccessibilityItem,
        during mutation: RetainedAccessibilityMutation
    ) -> RetainedLazyListAccessibilityItem? {
        guard lazyListScrollWorkDepth > 0, lazyListAccessibilityPreparation == nil,
            isAccessibilityMutationCurrent(mutation), isLazyListAccessibilityTokenCurrent(token, in: witness),
            let content = witness.content, let adapter = content.retainedLazyListAdapter,
            let generation = adapter.managedLogicalDescriptorBinding?.sourceGeneration
                ?? adapter.currentLogicalGeneration,
            let (_, scroll) = content.nearestScrollTarget(), scroll.scrollAxis == .vertical,
            let scrollAttachment = accessibilityTarget(for: scroll)
        else { return nil }
        let preparation = RetainedLazyListAccessibilityPreparation(
            token: token, witness: witness, adapter: adapter, descriptor: adapter.managedLogicalDescriptorBinding,
            generation: generation, mutation: mutation, scroll: scroll, scrollAttachment: scrollAttachment,
            focusRevision: presentationFocusRevision, pointerSequence: pointerSequence,
            modal: presentationModalSnapshot.map(ObjectIdentifier.init))
        lazyListAccessibilityPreparation = preparation
        defer {
            preparation.isActive = false
            if lazyListAccessibilityPreparation === preparation { lazyListAccessibilityPreparation = nil }
        }
        guard isLazyListAccessibilityPreparationCurrent(preparation), prepareAccessibilityMutation(mutation),
            isAccessibilityMutationCurrent(mutation), isLazyListAccessibilityPreparationCurrent(preparation),
            let container = witness.container, let item = lazyListTarget(in: container, token: token),
            item.adapter === adapter
        else { return nil }
        return item
    }

    /// This native check also runs inside the existing anchor pass, so it does
    /// not require layout to be idle or borrow a later settlement as authority.
    private func isLazyListAccessibilityPreparationCurrent(
        _ preparation: RetainedLazyListAccessibilityPreparation, checkingScrollIntent: Bool = true
    ) -> Bool {
        guard preparation.isActive, lazyListAccessibilityPreparation === preparation,
            activeAccessibilityMutation === preparation.mutation, !preparation.mutation.isExhausted,
            isLazyListAccessibilityTokenCurrent(preparation.token, in: preparation.witness),
            let content = preparation.witness.content, let adapter = preparation.adapter,
            content.retainedLazyListAdapter === adapter,
            adapter.managedLogicalDescriptorBinding === preparation.descriptor,
            preparation.generation.isCurrent,
            (preparation.descriptor?.sourceGeneration ?? adapter.currentLogicalGeneration) == preparation.generation,
            !focusRevision.isExhausted, presentationFocusRevision == preparation.focusRevision,
            pointerSequence == preparation.pointerSequence,
            presentationModalSnapshot.map(ObjectIdentifier.init) == preparation.modal,
            let scroll = preparation.scroll, preparation.scrollAttachment.isCurrent(in: self),
            scroll.scrollAxis == .vertical, scroll.scrollSourceEpoch == preparation.scrollEpoch,
            content.nearestScrollTarget()?.container === scroll, !hasActiveScrollInputCapture(for: scroll),
            permitsConservativeAccessibilityValueTarget(content)
        else { return false }
        return !checkingScrollIntent || scroll.lazyListScrollIntentIdentity === preparation.scrollIntent
    }

    private func permitsLazyListAnchorDuringAccessibilityPreparation(
        in scroll: ViewNode, for content: ViewNode, adapter: RetainedLazyListRuntimeAdapter
    ) -> Bool {
        guard let preparation = lazyListAccessibilityPreparation, preparation.scroll === scroll else { return true }
        guard preparation.witness.content === content, preparation.adapter === adapter else {
            // A successor may converge in the same layout query after the
            // original row callback replaces its source. It cannot borrow the
            // obsolete preparation to correct this scroll owner's offset.
            preparation.isActive = false
            return false
        }
        guard preparation.reservedAnchorIntent == nil, isLazyListAccessibilityPreparationCurrent(preparation) else {
            // Also gate unchanged anchors: publishing their clamp would capture
            // a newer authored intent even though no offset setter ran here.
            preparation.isActive = false
            return false
        }
        return true
    }

    private func setLazyListAnchorOffset(
        _ offset: Double, in scroll: ViewNode, for content: ViewNode, adapter: RetainedLazyListRuntimeAdapter
    ) -> Bool {
        guard let preparation = lazyListAccessibilityPreparation, preparation.scroll === scroll else {
            scroll.scrollOffset = offset
            return true
        }
        guard permitsLazyListAnchorDuringAccessibilityPreparation(in: scroll, for: content, adapter: adapter) else {
            // A failed matching preparation remains a barrier until its owner
            // unwinds; later passes must not overwrite the newer scroll intent.
            return false
        }
        let intent = RetainedLazyListAttachmentIdentity()
        preparation.reservedAnchorIntent = intent
        defer { preparation.reservedAnchorIntent = nil }
        // Grid invalidation can release a displaced scheduler callback. Never
        // read a replacement intent after that callout and bless it as ours.
        guard scroll.assignScrollOffset(offset, admission: nil, continuingAccessibilityAnchor: intent),
            isLazyListAccessibilityAnchorCorrectionCurrent(in: scroll, intent: intent)
        else {
            preparation.isActive = false
            return false
        }
        preparation.scrollIntent = intent
        return true
    }

    fileprivate func canBeginLazyListAccessibilityAnchorCorrection(
        in scroll: ViewNode, intent: RetainedLazyListAttachmentIdentity
    ) -> Bool {
        guard let preparation = lazyListAccessibilityPreparation, preparation.scroll === scroll,
            preparation.reservedAnchorIntent === intent
        else { return false }
        return isLazyListAccessibilityPreparationCurrent(preparation)
    }

    fileprivate func isLazyListAccessibilityAnchorCorrectionCurrent(
        in scroll: ViewNode, intent: RetainedLazyListAttachmentIdentity
    ) -> Bool {
        guard let preparation = lazyListAccessibilityPreparation, preparation.scroll === scroll,
            preparation.reservedAnchorIntent === intent, scroll.lazyListScrollIntentIdentity === intent
        else { return false }
        return isLazyListAccessibilityPreparationCurrent(preparation, checkingScrollIntent: false)
    }

    package func lazyListAccessibilityGeneration(
        for item: RetainedLazyListAccessibilityItem
    ) -> RetainedLazyListGeneration? {
        guard isLazyListAccessibilityContainerCurrent(item) else { return nil }
        return item.content?.retainedLazyListAdapter?.currentLogicalGeneration
    }

    /// Actual roots only. The facade/platform projection can choose one or
    /// several accessibility elements; a logical record is never a fake row.
    package func realizedLazyListAccessibilityNodes(for item: RetainedLazyListAccessibilityItem) -> [ViewNode]? {
        guard isLazyListAccessibilityItemCurrent(item), case .settled = layoutSettlementStatus,
            hasCurrentAccessibilityPrepaint, let content = item.content,
            let nodes = item.adapter?.mountedNodes(for: item.token),
            nodes.allSatisfy({ node in
                node.parent === content && node.runtime === self && !node.isRetiringLazyListAttachment
                    && !node.isLayoutDeferredByVirtualization && content.children.contains(where: { $0 === node })
            })
        else { return nil }
        return nodes
    }

    /// Ends only this native logical protection. After navigation focuses the
    /// actual target, ordinary focus protection keeps its row mounted. Failure
    /// releases the extra row at the next bounded layout opportunity.
    package func releaseLazyListTarget(_ item: RetainedLazyListAccessibilityItem) {
        releaseLazyListTarget(item, invalidatingLayout: true)
    }

    private func releaseLazyListTarget(
        _ item: RetainedLazyListAccessibilityItem, invalidatingLayout: Bool
    ) {
        guard item.runtime === self, let realization = item.realization else { return }
        item.realization = nil
        realization.revoke()
        item.adapter?.endLogicalRealization(realization)
        if invalidatingLayout, let content = item.content, ownsLazyListAttachment(content) {
            content.markDirty(.layout)
            invalidate(.layout, from: content)
        }
    }

    private func beginLazyListTargetResolution(during mutation: RetainedAccessibilityMutation?) -> Bool {
        guard !isResolvingLazyListLogicalTarget, permitsRetainedActionInvocation,
            canReadLayoutSettlement, !isUpdatingResolvedLayout,
            mutation == nil ? activeAccessibilityMutation == nil : mutation === activeAccessibilityMutation
        else { return false }
        if let mutation, !isAccessibilityMutationCurrent(mutation) { return false }
        isResolvingLazyListLogicalTarget = true
        ensureLazyListResolutionBudget()
        return true
    }

    private func finishLazyListTargetResolution() {
        lazyListLogicalRevealScroll = nil
        isResolvingLazyListLogicalTarget = false
        finishLazyListResolutionBudgetIfIdle()
    }

    /// Materializes one bounded logical exception without moving the viewport.
    /// Its native lease remains held until releaseLazyListTarget, so a binding
    /// write can rebuild the List before the caller prepares/focuses the real
    /// row. Scrolling then uses the ordinary captured-transaction path.
    package func realizeLazyListTarget(_ item: RetainedLazyListAccessibilityItem) -> ViewNode? {
        guard case .ready(let roots) = resolveLazyListTarget(item),
            let first = roots.first(where: { !$0.isHidden && !$0.isSeparatorRule })
        else {
            releaseLazyListTarget(item)
            return nil
        }
        return first
    }

    /// Keeps a pending native demand alive across the framework's existing
    /// after-layout replay. It does not enqueue another scheduler or repeat a
    /// binding write; the request owner releases the item on cancellation.
    package func resolveLazyListTarget(_ item: RetainedLazyListAccessibilityItem) -> RetainedLazyListTargetResolution {
        guard item.runtime === self, permitsRetainedActionInvocation else { return .obsolete }
        guard !hasActiveRetainedBuild, !isResolvingLazyListLogicalTarget else { return .pending }
        guard isLazyListAccessibilityItemCurrent(item), let adapter = item.adapter, let content = item.content else {
            return .obsolete
        }
        guard adapter.updateProtectedRoots(protectedLazyListRoots(in: content)) else { return .unsupported }
        if adapter.knownLeafCount(for: item.token) == 0 { return .empty }
        if isUpdatingResolvedLayout, isDrainingAfterLayoutActions {
            guard activeAccessibilityMutation == nil else { return .unsupported }
            if let roots = currentPassLazyListRoots(for: item), !roots.isEmpty,
                roots.contains(where: { !$0.isHidden && !$0.isSeparatorRule })
            {
                // Existing pending protection must remain held through the
                // caller's final scroll and request completion.
                if item.realization?.isActive == true { return .ready(roots) }
            }
            if item.realization?.isActive != true {
                guard let realization = adapter.beginLogicalRealization(of: item.token, owner: item.realizationOwner)
                else { return adapter.hasUnresolvedWork ? .pending : .unsupported }
                item.realization = realization
                content.markDirty(.layout)
                invalidate(.layout, from: content)
            }
            // The ordinary settle after this callback constructs the requested
            // row. Recursive layout here would fabricate a nested settlement.
            return .pending
        }
        guard beginLazyListTargetResolution(during: nil) else { return .pending }
        defer { finishLazyListTargetResolution() }
        if let roots = materializeLazyListTarget(item, during: nil) { return .ready(roots) }
        guard isLazyListAccessibilityItemCurrent(item) else { return .obsolete }
        return adapter.knownLeafCount(for: item.token) == 0 ? .empty : .pending
    }

    private func currentPassLazyListRoots(for item: RetainedLazyListAccessibilityItem) -> [ViewNode]? {
        guard isLazyListAccessibilityItemCurrent(item), let content = item.content, let adapter = item.adapter,
            !adapter.hasUnresolvedWork, let visit = pendingLazyListVisits[ObjectIdentifier(content)],
            lazyListVisitIsCurrent(visit), content.lastLayoutVisitPassID == layoutPassID,
            let nodes = adapter.mountedNodes(for: item.token),
            nodes.allSatisfy({ node in
                node.parent === content && node.runtime === self && !node.isRetiringLazyListAttachment
                    && !node.isLayoutDeferredByVirtualization
                    && (node.isHidden || node.lastLayoutVisitPassID == layoutPassID)
                    && content.children.contains(where: { $0 === node })
            })
        else { return nil }
        return nodes
    }

    private func materializeLazyListTarget(
        _ item: RetainedLazyListAccessibilityItem, during mutation: RetainedAccessibilityMutation?
    ) -> [ViewNode]? {
        guard isLazyListAccessibilityItemCurrent(item), let content = item.content, let adapter = item.adapter,
            adapter.knownLeafCount(for: item.token) != 0
        else { return nil }
        guard adapter.updateProtectedRoots(protectedLazyListRoots(in: content)) else { return nil }
        let originalFocus = presentationFocusRevision
        let originalPointer = pointerSequence
        let originalModal = presentationModalSnapshot.map(ObjectIdentifier.init)
        func isCurrent() -> Bool {
            isLazyListAccessibilityItemCurrent(item) && presentationFocusRevision == originalFocus
                && pointerSequence == originalPointer
                && presentationModalSnapshot.map(ObjectIdentifier.init) == originalModal
                && (mutation == nil || isAccessibilityMutationCurrent(mutation!))
        }
        if case .settled = layoutSettlementStatus {
            // The existing settled viewport needs no additional query.
        } else {
            guard resolvedLayoutFrame(of: root) != nil, isCurrent(), case .settled = layoutSettlementStatus else {
                return nil
            }
        }
        if item.realization?.isActive != true {
            guard
                let realization = adapter.beginLogicalRealization(of: item.token, owner: item.realizationOwner),
                isCurrent()
            else { return nil }
            item.realization = realization
            content.markDirty(.layout)
            invalidate(.layout, from: content)
        }
        guard resolvedLayoutFrame(of: content) != nil, isCurrent(), case .settled = layoutSettlementStatus,
            let nodes = realizedLazyListAccessibilityNodes(for: item), !nodes.isEmpty
        else { return nil }
        return nodes
    }

    /// UIA receives only current attached roots after bounded construction and
    /// a precise immediate reveal. No synthetic row is installed for unknown,
    /// empty, expired, or still-unsettled logical output.
    package func realizeLazyListAccessibilityItem(
        _ item: RetainedLazyListAccessibilityItem, during mutation: RetainedAccessibilityMutation
    ) -> [ViewNode]? {
        guard beginLazyListTargetResolution(during: mutation) else { return nil }
        var completed = false
        defer {
            releaseLazyListTarget(item, invalidatingLayout: !completed)
            finishLazyListTargetResolution()
        }
        guard let nodes = materializeLazyListTarget(item, during: mutation),
            let target = nodes.first(where: { !$0.isHidden && !$0.isSeparatorRule }),
            let targetAttachment = accessibilityTarget(for: target),
            let (_, scroll) = target.nearestScrollTarget(), scroll.scrollAxis == .vertical,
            let scrollAttachment = accessibilityTarget(for: scroll), !hasActiveScrollInputCapture(for: scroll),
            permitsConservativeAccessibilityValueTarget(target),
            let requested = ViewNode.requestedScrollOffset(
                for: target, within: scroll, anchor: nil, visibleOffset: scroll.effectiveScrollOffset)
        else { return nil }
        let originalFocus = presentationFocusRevision
        let originalPointer = pointerSequence
        let sourceEpoch = scroll.scrollSourceEpoch
        func isCurrent() -> Bool {
            isAccessibilityMutationCurrent(mutation) && isLazyListAccessibilityItemCurrent(item)
                && targetAttachment.isCurrent(in: self) && scrollAttachment.isCurrent(in: self)
                && presentationFocusRevision == originalFocus && pointerSequence == originalPointer
                && scroll.scrollSourceEpoch == sourceEpoch && !hasActiveScrollInputCapture(for: scroll)
                && permitsConservativeAccessibilityValueTarget(target)
        }
        lazyListLogicalRevealScroll = scroll
        cancelScrollMomentum(for: scroll)
        guard isCurrent() else { return nil }
        cancelScrollPresentedTween(for: scroll)
        guard isCurrent() else { return nil }
        var nextOffset = requested
        for _ in 0..<Self.geometryReaderConvergenceLimit {
            _ = scroll.setScrollOffset(nextOffset)
            guard isCurrent() else { return nil }
            let expectedIntent = scroll.captureLazyListScrollIntentIdentity()
            guard resolvedLayoutFrame(of: target) != nil, isCurrent(),
                scroll.lazyListScrollIntentIdentity === expectedIntent,
                case .settled = layoutSettlementStatus, hasCurrentAccessibilityPrepaint,
                let realized = realizedLazyListAccessibilityNodes(for: item), !realized.isEmpty
            else { return nil }
            if scrollVisibilityFraction(of: target) > 0 {
                completed = true
                return realized
            }
            // The new viewport may have replaced estimates with real heights
            // above the target. Correct from that accepted geometry, borrowing
            // this same request's remaining work budget and exact attachments.
            // A newer scroll intent or a zero-progress correction ends here.
            guard let budget = lazyListResolutionBudget, budget.remainingRounds > 0,
                let correction = ViewNode.requestedScrollOffset(
                    for: target, within: scroll, anchor: nil, visibleOffset: scroll.effectiveScrollOffset),
                scroll.clampedScrollOffset(for: correction) != scroll.scrollOffset,
                isCurrent(), scroll.lazyListScrollIntentIdentity === expectedIntent
            else { return nil }
            nextOffset = correction
        }
        return nil
    }
}
