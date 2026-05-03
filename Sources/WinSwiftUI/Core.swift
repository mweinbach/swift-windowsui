import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsUI

public typealias Color = SwiftWindowsCore.Color
public typealias EdgeInsets = SwiftWindowsCore.EdgeInsets
public typealias CGFloat = Double
public typealias CGPoint = SwiftWindowsCore.Point
public typealias CGRect = SwiftWindowsCore.Rect
public typealias CGSize = SwiftWindowsCore.Size
public typealias IntSize = SwiftWindowsCore.IntSize
public typealias LinearGradient = SwiftWindowsGraphics.LinearGradient
public typealias Point = SwiftWindowsCore.Point
public typealias Rect = SwiftWindowsCore.Rect
public typealias Size = SwiftWindowsCore.Size
public typealias ControlAnimationStyle = SwiftWindowsUI.ControlAnimationStyle
public typealias SurfaceChrome = SwiftWindowsUI.SurfaceChrome
public typealias SurfacePalette = SwiftWindowsUI.SurfacePalette

public struct UnitPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let top = UnitPoint(x: 0.5, y: 0.0)
    public static let bottom = UnitPoint(x: 0.5, y: 1.0)
    public static let leading = UnitPoint(x: 0.0, y: 0.5)
    public static let trailing = UnitPoint(x: 1.0, y: 0.5)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let topLeading = UnitPoint(x: 0.0, y: 0.0)
    public static let topTrailing = UnitPoint(x: 1.0, y: 0.0)
    public static let bottomLeading = UnitPoint(x: 0.0, y: 1.0)
    public static let bottomTrailing = UnitPoint(x: 1.0, y: 1.0)
}

public struct Angle: Sendable, Equatable {
    public var radians: Double

    public init(radians: Double) {
        self.radians = radians
    }

    public var degrees: Double {
        radians * 180.0 / Double.pi
    }

    public static func radians(_ value: Double) -> Angle {
        Angle(radians: value)
    }

    public static func degrees(_ value: Double) -> Angle {
        Angle(radians: value * Double.pi / 180.0)
    }
}

public struct Gradient: Sendable, Equatable {
    public var colors: [Color]

    public init(colors: [Color]) {
        self.colors = colors
    }
}

public protocol Shape: Sendable {}

public struct FillStyle: Sendable, Equatable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        self.isEOFilled = eoFill
        self.isAntialiased = antialiased
    }
}

public struct Rectangle: Shape, Equatable {
    public init() {}
}

public enum RoundedCornerStyle: Sendable, Equatable {
    case circular
    case continuous
}

public struct RoundedRectangle: Shape, Equatable {
    public var cornerRadius: Double
    public var style: RoundedCornerStyle

    public init(cornerRadius: Double, style: RoundedCornerStyle = .continuous) {
        self.cornerRadius = cornerRadius
        self.style = style
    }
}

public enum CoordinateSpace: Sendable, Equatable {
    case local
    case global
}

public protocol Gesture {}

public struct DragGesture: Gesture {
    public struct Value: Sendable, Equatable {
        public var time: Date
        public var location: Point
        public var startLocation: Point
        public var translation: Size
        public var predictedEndLocation: Point
        public var predictedEndTranslation: Size

        public init(
            time: Date = Date(),
            location: Point,
            startLocation: Point,
            translation: Size,
            predictedEndLocation: Point? = nil,
            predictedEndTranslation: Size? = nil
        ) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
            self.translation = translation
            self.predictedEndLocation = predictedEndLocation ?? location
            self.predictedEndTranslation = predictedEndTranslation ?? translation
        }
    }

    public var minimumDistance: Double
    public var coordinateSpace: CoordinateSpace

    var onChangedHandler: (@MainActor (Value) -> Void)?
    var onEndedHandler: (@MainActor (Value) -> Void)?

    public init(minimumDistance: Double = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
    }

    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture {
        var copy = self
        copy.onChangedHandler = action
        return copy
    }

    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture {
        var copy = self
        copy.onEndedHandler = action
        return copy
    }
}

@MainActor
public protocol ObservableObject: AnyObject {}

@MainActor
public final class ObservationToken {
    private let cancelHandler: @MainActor () -> Void

    init(cancelHandler: @escaping @MainActor () -> Void) {
        self.cancelHandler = cancelHandler
    }

    public func cancel() {
        cancelHandler()
    }
}

@MainActor
final class ObservableObjectCenter {
    static let shared = ObservableObjectCenter()

    private var observers: [ObjectIdentifier: [UUID: @MainActor () -> Void]] = [:]

    func addObserver(
        for object: any ObservableObject,
        observer: @escaping @MainActor () -> Void
    ) -> ObservationToken {
        let objectID = ObjectIdentifier(object)
        let tokenID = UUID()
        var objectObservers = observers[objectID] ?? [:]
        objectObservers[tokenID] = observer
        observers[objectID] = objectObservers

        return ObservationToken { [weak self] in
            guard let self else {
                return
            }

            var remainingObservers = self.observers[objectID] ?? [:]
            remainingObservers.removeValue(forKey: tokenID)
            if remainingObservers.isEmpty {
                self.observers.removeValue(forKey: objectID)
            } else {
                self.observers[objectID] = remainingObservers
            }
        }
    }

    func notify(_ object: any ObservableObject) {
        let callbacks = observers[ObjectIdentifier(object)]?.map(\.value) ?? []
        for callback in callbacks {
            callback()
        }
    }
}

@MainActor
@propertyWrapper
public struct Published<Value> {
    private var value: Value

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance instance: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Value {
        get {
            instance[keyPath: storageKeyPath].value
        }
        set {
            instance[keyPath: storageKeyPath].value = newValue
            ObservableObjectCenter.shared.notify(instance)
        }
    }

    public var wrappedValue: Value {
        get {
            fatalError("@Published can only be used on properties of ObservableObject classes")
        }
        set {
            fatalError("@Published can only be used on properties of ObservableObject classes")
        }
    }
}

@MainActor
@dynamicMemberLookup
@propertyWrapper
public struct Binding<Value> {
    private let getter: @MainActor () -> Value
    private let setter: @MainActor (Value) -> Void
    private let invalidatesOnSet: Bool

    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.init(get: get, set: set, invalidatesOnSet: false)
    }

    init(
        get: @escaping @MainActor () -> Value,
        set: @escaping @MainActor (Value) -> Void,
        invalidatesOnSet: Bool
    ) {
        self.getter = get
        self.setter = set
        self.invalidatesOnSet = invalidatesOnSet
    }

    public var wrappedValue: Value {
        get {
            getter()
        }
        nonmutating set {
            setter(newValue)
        }
    }

    public var projectedValue: Binding<Value> {
        self
    }

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(
            get: {
                wrappedValue[keyPath: keyPath]
            },
            set: { newValue in
                var value = wrappedValue
                value[keyPath: keyPath] = newValue
                wrappedValue = value
            },
            invalidatesOnSet: invalidatesOnSet
        )
    }

    func invalidateContextIfNeeded(_ context: ViewBuildContext) {
        if !invalidatesOnSet {
            context.invalidate()
        }
    }
}

@MainActor
@propertyWrapper
public struct State<Value> {
    private let box: StateBox<Value>

    public init(wrappedValue: Value) {
        self.box = StateBox(value: wrappedValue)
    }

    public var wrappedValue: Value {
        get {
            bindToCurrentContext()
            return box.value
        }
        nonmutating set {
            box.value = newValue
            box.invalidate?()
        }
    }

    public var projectedValue: Binding<Value> {
        bindToCurrentContext()
        return Binding<Value>(
            get: {
                box.value
            },
            set: { newValue in
                box.value = newValue
                box.invalidate?()
            },
            invalidatesOnSet: true
        )
    }

    private func bindToCurrentContext() {
        guard let context = ViewBuildContextScope.current else {
            return
        }

        box.invalidate = {
            context.invalidate()
        }
    }
}

@MainActor
private final class StateBox<Value> {
    var value: Value
    var invalidate: (() -> Void)?

    init(value: Value) {
        self.value = value
    }
}

@MainActor
@dynamicMemberLookup
@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject> {
    private var object: ObjectType

    public init(wrappedValue: ObjectType) {
        self.object = wrappedValue
    }

    public var wrappedValue: ObjectType {
        get {
            ViewBuildContextScope.current?.observe(object)
            return object
        }
        set {
            object = newValue
        }
    }

    public var projectedValue: ObservedObject<ObjectType> {
        ViewBuildContextScope.current?.observe(object)
        return self
    }

    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Value>) -> Binding<Value> {
        Binding<Value>(
            get: {
                object[keyPath: keyPath]
            },
            set: { newValue in
                object[keyPath: keyPath] = newValue
            }
        )
    }
}

@MainActor
public struct ViewBuildContext {
    private let canvasSizeProvider: () -> Size
    private let invalidateHandler: () -> Void
    private let observedObjectHandler: (any ObservableObject) -> Void
    var tintColor: Color?

    public var canvasSize: Size {
        canvasSizeProvider()
    }

    init(
        canvasSizeProvider: @escaping () -> Size,
        invalidateHandler: @escaping () -> Void,
        observedObjectHandler: @escaping (any ObservableObject) -> Void = { _ in },
        tintColor: Color? = nil
    ) {
        self.canvasSizeProvider = canvasSizeProvider
        self.invalidateHandler = invalidateHandler
        self.observedObjectHandler = observedObjectHandler
        self.tintColor = tintColor
    }

    func invalidate() {
        invalidateHandler()
    }

    func observe(_ object: any ObservableObject) {
        observedObjectHandler(object)
    }

    func withTint(_ color: Color) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: color
        )
    }
}

@MainActor
public protocol View {
    associatedtype Body: View

    var body: Body { get }

    func makeComponent(context: ViewBuildContext) -> Component
}

public extension View {
    func makeComponent(context: ViewBuildContext) -> Component {
        ViewBuildContextScope.withCurrent(context) {
            body.makeComponent(context: context)
        }
    }

    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}

@MainActor
enum ViewBuildContextScope {
    private static var currentContext: ViewBuildContext?

    static var current: ViewBuildContext? {
        currentContext
    }

    static func withCurrent<Result>(_ context: ViewBuildContext, _ body: () -> Result) -> Result {
        let previous = currentContext
        currentContext = context
        defer {
            currentContext = previous
        }
        return body()
    }
}

extension Never: View {
    public var body: Never {
        fatalError("Never has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        fatalError("Never cannot build a component")
    }
}

@MainActor
public struct AnyView: View {
    public typealias Body = Never

    private let buildComponent: (ViewBuildContext) -> Component

    public init<V: View>(_ view: V) {
        self.buildComponent = { context in
            ViewBuildContextScope.withCurrent(context) {
                view.makeComponent(context: context)
            }
        }
    }

    public var body: Never {
        fatalError("AnyView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        buildComponent(context)
    }
}

extension Array: View where Element == AnyView {
    public typealias Body = Never

    public var body: Never {
        fatalError("[AnyView] has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        composeComponent(from: self, context: context)
    }
}

@MainActor
@resultBuilder
public enum ViewBuilder {
    public static func buildExpression<V: View>(_ expression: V) -> [AnyView] {
        [AnyView(expression)]
    }

    public static func buildExpression(_ expression: [AnyView]) -> [AnyView] {
        expression
    }

    public static func buildExpression(_ expression: Void) -> [AnyView] {
        []
    }

    public static func buildBlock(_ components: [AnyView]...) -> [AnyView] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ components: [AnyView]?) -> [AnyView] {
        components ?? []
    }

    public static func buildEither(first components: [AnyView]) -> [AnyView] {
        components
    }

    public static func buildEither(second components: [AnyView]) -> [AnyView] {
        components
    }

    public static func buildArray(_ components: [[AnyView]]) -> [AnyView] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ components: [AnyView]) -> [AnyView] {
        components
    }
}

@MainActor
public struct EmptyView: View {
    public typealias Body = Never

    public init() {}

    public var body: Never {
        fatalError("EmptyView has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            Controls.panel(preferredSize: .zero, isHitTestVisible: false)
        }
    }
}

public enum HorizontalAlignment: Sendable {
    case leading
    case center
    case trailing
}

public enum VerticalAlignment: Sendable {
    case top
    case center
    case bottom
}

public struct Alignment: Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(horizontal: HorizontalAlignment = .center, vertical: VerticalAlignment = .center) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment()
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

public enum TextAlignment: Sendable {
    case leading
    case center
    case trailing
}

public enum Axis: Sendable {
    case horizontal
    case vertical
}

public enum Edge {
    case top
    case leading
    case bottom
    case trailing

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let top = Set(rawValue: 1 << 0)
        public static let leading = Set(rawValue: 1 << 1)
        public static let bottom = Set(rawValue: 1 << 2)
        public static let trailing = Set(rawValue: 1 << 3)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

public struct Font: Sendable, Equatable {
    public enum Weight: Sendable, Equatable {
        case regular
        case semibold
        case bold
    }

    public enum Design: Sendable, Equatable {
        case `default`
        case rounded
        case monospaced
    }

    public var size: Double
    public var weight: Weight
    public var design: Design
    public var family: String?

    public init(size: Double, weight: Weight = .regular, design: Design = .default, family: String? = nil) {
        self.size = size
        self.weight = weight
        self.design = design
        self.family = family
    }

    public static func system(size: Double, weight: Weight = .regular, design: Design = .default) -> Font {
        Font(size: size, weight: weight, design: design)
    }
}

public struct ButtonSurfaceStyle: Sendable {
    public var cornerRadius: Double
    public var palette: SurfacePalette
    public var chrome: SurfaceChrome
    public var clipsToBounds: Bool
    public var animation: ControlAnimationStyle

    public init(
        cornerRadius: Double = 16,
        palette: SurfacePalette = ButtonSurfaceStyle.defaultPalette,
        chrome: SurfaceChrome = .elevatedButton,
        clipsToBounds: Bool = true,
        animation: ControlAnimationStyle = .default
    ) {
        self.cornerRadius = cornerRadius
        self.palette = palette
        self.chrome = chrome
        self.clipsToBounds = clipsToBounds
        self.animation = animation
    }

    public static let `default` = ButtonSurfaceStyle()
    public static let plain = ButtonSurfaceStyle(
        cornerRadius: 0,
        palette: SurfacePalette(
            idle: .clear,
            hovered: .clear,
            focused: .clear,
            pressed: .clear,
            activated: .clear
        ),
        chrome: SurfaceChrome(),
        clipsToBounds: false,
        animation: .default
    )

    public static let defaultPalette = SurfacePalette(
        idle: Color(red: 0.18, green: 0.23, blue: 0.31, alpha: 0.74),
        hovered: Color(red: 0.22, green: 0.29, blue: 0.39, alpha: 0.82),
        focused: Color(red: 0.26, green: 0.35, blue: 0.47, alpha: 0.88),
        pressed: Color(red: 0.31, green: 0.42, blue: 0.56, alpha: 0.94),
        activated: Color(red: 0.36, green: 0.48, blue: 0.63, alpha: 0.96)
    )
}

public struct ButtonStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case plain
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonStyle(kind: .automatic)
    public static let plain = ButtonStyle(kind: .plain)

    var surfaceStyle: ButtonSurfaceStyle {
        switch kind {
        case .automatic:
            return .default
        case .plain:
            return .plain
        }
    }
}

public struct ScrollViewStyle: Sendable {
    public var spacing: Double
    public var padding: EdgeInsets
    public var alignment: HorizontalAlignment
    public var backgroundColor: Color?
    public var borderColor: Color
    public var borderWidth: Double
    public var shadowColor: Color
    public var shadowOffset: Point
    public var shadowSpread: Double
    public var cornerRadius: Double
    public var scrollStep: Double
    public var indicatorColor: Color
    public var indicatorHoverColor: Color
    public var indicatorActiveColor: Color
    public var indicatorThickness: Double
    public var isHitTestVisible: Bool

    public init(
        spacing: Double = 0,
        padding: EdgeInsets = .zero,
        alignment: HorizontalAlignment = .leading,
        backgroundColor: Color? = nil,
        borderColor: Color = .clear,
        borderWidth: Double = 0,
        shadowColor: Color = .clear,
        shadowOffset: Point = .zero,
        shadowSpread: Double = 0,
        cornerRadius: Double = 0,
        scrollStep: Double = 64,
        indicatorColor: Color = Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
        indicatorHoverColor: Color = Color(red: 0.97, green: 0.99, blue: 1.0, alpha: 0.30),
        indicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.46),
        indicatorThickness: Double = 5,
        isHitTestVisible: Bool = true
    ) {
        self.spacing = spacing
        self.padding = padding
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
        self.cornerRadius = cornerRadius
        self.scrollStep = scrollStep
        self.indicatorColor = indicatorColor
        self.indicatorHoverColor = indicatorHoverColor
        self.indicatorActiveColor = indicatorActiveColor
        self.indicatorThickness = indicatorThickness
        self.isHitTestVisible = isHitTestVisible
    }

    public static let `default` = ScrollViewStyle()
}

public struct SectionStyle: Sendable {
    public var spacing: Double
    public var padding: EdgeInsets
    public var alignment: HorizontalAlignment
    public var backgroundColor: Color
    public var backgroundGradient: LinearGradient?
    public var borderColor: Color
    public var shadowColor: Color
    public var cornerRadius: Double
    public var scrollAxis: Axis?
    public var scrollStep: Double
    public var indicatorColor: Color
    public var indicatorHoverColor: Color
    public var indicatorActiveColor: Color
    public var indicatorThickness: Double
    public var headerColor: Color
    public var headerFont: Font
    public var isHitTestVisible: Bool

    public init(
        spacing: Double = 16,
        padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        alignment: HorizontalAlignment = .leading,
        backgroundColor: Color = Color(red: 0.10, green: 0.14, blue: 0.22, alpha: 0.78),
        backgroundGradient: LinearGradient? = nil,
        borderColor: Color = Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
        shadowColor: Color = Color(red: 0.02, green: 0.05, blue: 0.10, alpha: 0.16),
        cornerRadius: Double = 28,
        scrollAxis: Axis? = nil,
        scrollStep: Double = 64,
        indicatorColor: Color = Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
        indicatorHoverColor: Color = Color(red: 0.97, green: 0.99, blue: 1.0, alpha: 0.30),
        indicatorActiveColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.46),
        indicatorThickness: Double = 5,
        headerColor: Color = Color(red: 0.93, green: 0.97, blue: 1.0, alpha: 0.94),
        headerFont: Font = .system(size: 1.5, weight: .semibold),
        isHitTestVisible: Bool = false
    ) {
        self.spacing = spacing
        self.padding = padding
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.backgroundGradient = backgroundGradient
        self.borderColor = borderColor
        self.shadowColor = shadowColor
        self.cornerRadius = cornerRadius
        self.scrollAxis = scrollAxis
        self.scrollStep = scrollStep
        self.indicatorColor = indicatorColor
        self.indicatorHoverColor = indicatorHoverColor
        self.indicatorActiveColor = indicatorActiveColor
        self.indicatorThickness = indicatorThickness
        self.headerColor = headerColor
        self.headerFont = headerFont
        self.isHitTestVisible = isHitTestVisible
    }

    public static let `default` = SectionStyle()
}

@MainActor
struct ModifiedView<Content: View>: View {
    typealias Body = Never

    let content: Content
    let transform: (Content, ViewBuildContext) -> Component

    /// Optional stable identity for the modified view, propagated to the
    /// resulting ViewNode so the diffing algorithm can match nodes across
    /// rebuilds by identity rather than position alone.
    var id: String?

    var body: Never {
        fatalError("ModifiedView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let inner = transform(content, context)
        guard let id else {
            return inner
        }

        // Wrap the inner component so the resulting node carries the id.
        let capturedID = id
        return Component { runtime in
            let node = inner.makeNode(runtime: runtime)
            node.nodeTag = capturedID
            return node
        }
    }
}

@MainActor
func composeComponent(
    from views: [AnyView],
    context: ViewBuildContext,
    fallbackLayout: ViewLayoutMode = .absolute,
    isHitTestVisible: Bool = false
) -> Component {
    if views.count == 1, let view = views.first {
        return view.makeComponent(context: context)
    }

    return Component { runtime in
        Controls.panel(
            layoutMode: fallbackLayout,
            isHitTestVisible: isHitTestVisible,
            children: views.map { $0.makeComponent(context: context).makeNode(runtime: runtime) }
        )
    }
}

@MainActor
private func updateTextStyles(in node: ViewNode, _ update: (inout PixelTextStyle) -> Void) {
    if node.text != nil {
        var style = node.textStyle
        update(&style)
        if var spans = style.spans {
            for index in spans.indices {
                update(&spans[index].style)
            }
            style.spans = spans
        }
        node.textStyle = style
    }

    for child in node.children {
        updateTextStyles(in: child, update)
    }
}

extension HorizontalAlignment {
    var stackAlignment: StackCrossAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var textAlignment: TextHorizontalAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

extension VerticalAlignment {
    var stackAlignment: StackCrossAlignment {
        switch self {
        case .top:
            return .leading
        case .center:
            return .center
        case .bottom:
            return .trailing
        }
    }

    var mainAlignment: StackMainAlignment {
        switch self {
        case .top:
            return .start
        case .center:
            return .center
        case .bottom:
            return .end
        }
    }
}

extension TextAlignment {
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

extension Axis {
    var scrollAxis: ScrollAxis {
        switch self {
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        }
    }
}

extension Font.Weight {
    var textWeight: TextWeight {
        switch self {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}

extension Font {
    var resolvedScale: Double {
        size >= 8 ? size / 10.0 : size
    }

    var resolvedFamily: String {
        if let family {
            return family
        }

        switch design {
        case .default, .rounded:
            return "Segoe UI"
        case .monospaced:
            return "Cascadia Mono"
        }
    }
}

public extension SwiftWindowsCore.Color {
    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.init(red: Float(red), green: Float(green), blue: Float(blue), alpha: Float(opacity))
    }

    static let primary = SwiftWindowsCore.Color(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0)
    static let secondary = SwiftWindowsCore.Color(red: 0.36, green: 0.40, blue: 0.48, alpha: 1.0)
    static let accentColor = SwiftWindowsCore.Color(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
    static let orange = SwiftWindowsCore.Color(red: 1.0, green: 0.58, blue: 0.0, alpha: 1.0)
    static let yellow = SwiftWindowsCore.Color(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
    static let mint = SwiftWindowsCore.Color(red: 0.0, green: 0.78, blue: 0.75, alpha: 1.0)
    static let teal = SwiftWindowsCore.Color(red: 0.0, green: 0.78, blue: 0.88, alpha: 1.0)
    static let cyan = SwiftWindowsCore.Color(red: 0.20, green: 0.68, blue: 0.90, alpha: 1.0)
    static let indigo = SwiftWindowsCore.Color(red: 0.35, green: 0.34, blue: 0.84, alpha: 1.0)
    static let purple = SwiftWindowsCore.Color(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0)
    static let pink = SwiftWindowsCore.Color(red: 1.0, green: 0.18, blue: 0.45, alpha: 1.0)
    static let brown = SwiftWindowsCore.Color(red: 0.64, green: 0.52, blue: 0.37, alpha: 1.0)
    static let gray = SwiftWindowsCore.Color(red: 0.56, green: 0.56, blue: 0.58, alpha: 1.0)

    func opacity(_ value: Double) -> SwiftWindowsCore.Color {
        SwiftWindowsCore.Color(red: self.red, green: self.green, blue: self.blue, alpha: Float(value))
    }
}

public extension SwiftWindowsGraphics.LinearGradient {
    init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
        self.init(
            gradient: Gradient(colors: colors),
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
        let colors = gradient.colors.isEmpty ? [.clear, .clear] : gradient.colors
        let startColor = colors.first ?? .clear
        let endColor = colors.last ?? startColor
        let horizontalDelta = abs(endPoint.x - startPoint.x)
        let verticalDelta = abs(endPoint.y - startPoint.y)
        let axis: GradientAxis = horizontalDelta >= verticalDelta ? .horizontal : .vertical

        self.init(startColor: startColor, endColor: endColor, axis: axis)
    }
}

extension EdgeInsets {
    static func all(_ value: Double) -> EdgeInsets {
        EdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

extension Alignment {
    func frameOrigin(for childSize: Size, in containerSize: Size) -> Point {
        let x: Double
        switch horizontal {
        case .leading:
            x = 0
        case .center:
            x = max(0, (containerSize.width - childSize.width) * 0.5)
        case .trailing:
            x = max(0, containerSize.width - childSize.width)
        }

        let y: Double
        switch vertical {
        case .top:
            y = 0
        case .center:
            y = max(0, (containerSize.height - childSize.height) * 0.5)
        case .bottom:
            y = max(0, containerSize.height - childSize.height)
        }

        return Point(x: x, y: y)
    }
}

private func clipCornerRadius<S: Shape>(for shape: S) -> Double {
    if let roundedRectangle = shape as? RoundedRectangle {
        return max(0, roundedRectangle.cornerRadius)
    }

    return 0
}

private func dragValue(start: Point, current: Point) -> DragGesture.Value {
    let translation = Size(width: current.x - start.x, height: current.y - start.y)
    return DragGesture.Value(
        location: current,
        startLocation: start,
        translation: translation
    )
}

private func dragDistance(from start: Point, to current: Point) -> Double {
    let dx = current.x - start.x
    let dy = current.y - start.y
    return (dx * dx + dy * dy).squareRoot()
}

private enum LayerPlacement: Equatable {
    case behind
    case above
}

@MainActor
private func layeredComponent(
    base: Component,
    layer: Component,
    alignment: Alignment,
    placement: LayerPlacement
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let layerNode = layer.makeNode(runtime: runtime)
        let baseSize = baseNode.intrinsicContentSize()
        let children = placement == .behind ? [layerNode, baseNode] : [baseNode, layerNode]
        let root = Controls.panel(
            preferredSize: baseSize,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: children
        )

        root.onLayout = { bounds in
            let baseFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != baseFrame {
                baseNode.frame = baseFrame
            }

            let layerSize = layerNode.intrinsicContentSize()
            let layerFrame = Rect(
                origin: alignment.frameOrigin(for: layerSize, in: bounds.size),
                size: layerSize
            )
            if layerNode.frame != layerFrame {
                layerNode.frame = layerFrame
            }
        }

        return root
    }
}

public extension View {
    func foregroundColor(_ color: Color) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.color = color
                }
                return node
            }
        }
    }

    func foregroundStyle(_ color: Color) -> some View {
        foregroundColor(color)
    }

    func tint(_ color: Color) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTint(color))
        }
    }

    func font(_ font: Font) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    let preservesIconFont = style.fontFamily == "Segoe Fluent Icons"
                    style.scale = font.resolvedScale
                    style.weight = font.weight.textWeight
                    if !preservesIconFont {
                        style.fontFamily = font.resolvedFamily
                    }
                }
                return node
            }
        }
    }

    func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.alignment = alignment.horizontalAlignment.textAlignment
                }
                return node
            }
        }
    }

    func lineLimit(_ lineLimit: Int?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.maximumNumberOfLines = lineLimit
                    style.lineBreakMode = lineLimit == 1 ? .truncateTail : .wrap
                }
                return node
            }
        }
    }

    func frame(width: Double? = nil, height: Double? = nil, alignment: Alignment = .center) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                if width != nil || height != nil {
                    let existingPreferredSize = childNode.preferredSize ?? .zero
                    childNode.preferredSize = Size(
                        width: width ?? existingPreferredSize.width,
                        height: height ?? existingPreferredSize.height
                    )
                }
                return Controls.stackPanel(
                    preferredSize: Size(width: width ?? 0, height: height ?? 0),
                    stackLayout: .vertical(
                        padding: .zero,
                        alignment: alignment.horizontal.stackAlignment,
                        mainAlignment: alignment.vertical.mainAlignment
                    ),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func padding(_ length: Double = 16) -> some View {
        padding(EdgeInsets.all(length))
    }

    func padding(_ edges: Edge.Set, _ length: Double = 16) -> some View {
        padding(
            EdgeInsets(
                top: edges.contains(.top) ? length : 0,
                leading: edges.contains(.leading) ? length : 0,
                bottom: edges.contains(.bottom) ? length : 0,
                trailing: edges.contains(.trailing) ? length : 0
            )
        )
    }

    func padding(_ insets: EdgeInsets) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    stackLayout: .vertical(padding: insets, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func background(_ color: Color) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    backgroundColor: color,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func background(_ gradient: LinearGradient) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    backgroundGradient: gradient,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func background(alignment: Alignment = .center, @ViewBuilder content: () -> [AnyView]) -> some View {
        let backgroundViews = content()

        return ModifiedView(content: self) { baseContent, context in
            layeredComponent(
                base: baseContent.makeComponent(context: context),
                layer: composeComponent(from: backgroundViews, context: context),
                alignment: alignment,
                placement: .behind
            )
        }
    }

    func overlay(alignment: Alignment = .center, @ViewBuilder content: () -> [AnyView]) -> some View {
        let overlayViews = content()

        return ModifiedView(content: self) { baseContent, context in
            layeredComponent(
                base: baseContent.makeComponent(context: context),
                layer: composeComponent(from: overlayViews, context: context),
                alignment: alignment,
                placement: .above
            )
        }
    }

    func cornerRadius(_ radius: Double, antialiased: Bool = true) -> some View {
        _ = antialiased

        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    cornerRadius: max(0, radius),
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func clipped(antialiased: Bool = false) -> some View {
        _ = antialiased

        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        _ = style

        let cornerRadius = clipCornerRadius(for: shape)

        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    cornerRadius: cornerRadius,
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func border(_ color: Color, width: Double = 1, cornerRadius: Double = 0) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    borderColor: color,
                    borderWidth: width,
                    cornerRadius: cornerRadius,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func shadow(color: Color, radius: Double = 0, x: Double = 0, y: Double = 0) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    shadowColor: color,
                    shadowOffset: Point(x: x, y: y),
                    shadowSpread: radius,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func opacity(_ opacity: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.opacity = min(max(opacity, 0), 1)
                return childNode
            }
        }
    }

    func blur(radius: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.blurRadius = max(0, radius)
                return childNode
            }
        }
    }

    func offset(x: Double = 0, y: Double = 0) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.transform = childNode.transform.concatenating(.translation(x: x, y: y))
                return childNode
            }
        }
    }

    func offset(_ offset: Size) -> some View {
        self.offset(x: offset.width, y: offset.height)
    }

    func zIndex(_ value: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.zIndex = value
                return childNode
            }
        }
    }

    func scaleEffect(_ scale: Double) -> some View {
        scaleEffect(x: scale, y: scale)
    }

    func scaleEffect(x: Double, y: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.transform = childNode.transform.concatenating(.scale(x: x, y: y))
                return childNode
            }
        }
    }

    func rotationEffect(_ angle: Angle) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.transform = childNode.transform.concatenating(Transform2D(rotation: angle.radians))
                return childNode
            }
        }
    }

    func layoutPriority(_ priority: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.layoutPriority = priority
                return childNode
            }
        }
    }

    func allowsHitTesting(_ enabled: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = enabled
                return childNode
            }
        }
    }

    func disabled(_ disabled: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                guard disabled else {
                    return childNode
                }

                childNode.isHitTestVisible = false
                childNode.isFocusable = false
                childNode.onPointerEnter = nil
                childNode.onPointerExit = nil
                childNode.onPointerDown = nil
                childNode.onPointerUpInside = nil
                childNode.onPointerUpOutside = nil
                childNode.onFocusEnter = nil
                childNode.onFocusExit = nil
                childNode.onKeyDown = nil
                childNode.onTextInput = nil
                childNode.onActivate = nil
                childNode.onDragStart = nil
                childNode.onDragChange = nil
                childNode.onDragEnd = nil
                return childNode
            }
        }
    }

    func onAppear(perform action: @escaping @MainActor () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.onAppear = action
                return childNode
            }
        }
    }

    func onDisappear(perform action: @escaping @MainActor () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.onDisappear = action
                return childNode
            }
        }
    }

    func onTapGesture(count: Int = 1, perform action: @escaping @MainActor () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true
                childNode.onPointerUpInside = {
                    if count <= 1 {
                        action()
                    }
                }
                return childNode
            }
        }
    }

    func gesture(_ gesture: DragGesture) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let minimumDistance = max(0, gesture.minimumDistance)
                var startPoint: Point?
                var didRecognize = false

                childNode.isHitTestVisible = true
                childNode.onDragStart = { point in
                    startPoint = point
                    didRecognize = minimumDistance == 0
                    if didRecognize {
                        gesture.onChangedHandler?(dragValue(start: point, current: point))
                    }
                }
                childNode.onDragChange = { point, _ in
                    guard let start = startPoint else {
                        return
                    }

                    if !didRecognize {
                        guard dragDistance(from: start, to: point) >= minimumDistance else {
                            return
                        }
                        didRecognize = true
                    }

                    gesture.onChangedHandler?(dragValue(start: start, current: point))
                }
                childNode.onDragEnd = { point, _ in
                    defer {
                        startPoint = nil
                        didRecognize = false
                    }

                    guard let start = startPoint, didRecognize else {
                        return
                    }

                    gesture.onEndedHandler?(dragValue(start: start, current: point))
                }
                return childNode
            }
        }
    }

    /// Assign a stable identity to this view so the diffing algorithm can
    /// match it across rebuilds by identity rather than position.
    func id(_ identifier: String) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.id = identifier
        return modified
    }

    /// Attach a SwiftUI-style integer selection tag. `Picker` currently uses
    /// these tags to map declarative options into retained dropdown rows.
    func tag(_ value: Int) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.id = String(value)
        return modified
    }

    /// Attach an animation context to this view.  When properties (opacity,
    /// background color) change between rebuilds, the runtime will
    /// interpolate between the old and new values over the given duration
    /// using the specified easing curve.
    func animation(_ duration: Double = 0.25, easing: AnimationEasing = .easeInOut) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)

                // Snapshot the current property values so that subsequent
                // property changes can be detected and animated.
                node.previousPropertyValues = PropertySnapshot(
                    opacity: Double(node.backgroundColor?.alpha ?? 1.0),
                    backgroundColor: node.backgroundColor
                )

                // Store animation configuration on the node for the runtime
                // to pick up when it detects property changes during
                // reconciliation.
                let now = 0.0 // Placeholder; actual start time is set when
                              // a property change is detected at reconciliation.
                node.animationStates[.opacity] = AnimationState(
                    startValue: Double(node.backgroundColor?.alpha ?? 1.0),
                    endValue: Double(node.backgroundColor?.alpha ?? 1.0),
                    startTime: now,
                    duration: duration,
                    easing: easing
                )
                if let bg = node.backgroundColor {
                    node.animationStates[.backgroundColor] = AnimationState(
                        startValue: 0,
                        endValue: 0,
                        startTime: now,
                        duration: duration,
                        easing: easing
                    )
                    // Store previous color for interpolation.
                    node.previousPropertyValues?.backgroundColor = bg
                }

                return node
            }
        }
    }
}
