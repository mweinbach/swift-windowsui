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

public struct LocalizedStringKey: Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, CustomStringConvertible {
    let resolvedString: String

    public init(_ value: String) {
        self.resolvedString = value
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        self.init(stringInterpolation.output)
    }

    public var description: String {
        resolvedString
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var output = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            output.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            output += literal
        }

        public mutating func appendInterpolation<T>(_ value: T) {
            output += String(describing: value)
        }
    }
}

public struct Angle: Sendable, Equatable {
    public var radians: Double

    public init(radians: Double) {
        self.radians = radians
    }

    public init(degrees: Double) {
        self.radians = degrees * .pi / 180
    }

    public var degrees: Double {
        radians * 180 / .pi
    }

    public static func radians(_ radians: Double) -> Angle {
        Angle(radians: radians)
    }

    public static func degrees(_ degrees: Double) -> Angle {
        Angle(degrees: degrees)
    }
}

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

public struct Gradient: Sendable, Equatable {
    public var colors: [Color]

    public init(colors: [Color]) {
        self.colors = colors
    }
}

public struct FillStyle: Sendable, Equatable {
    public var isEOFilled: Bool
    public var isAntialiased: Bool

    public init(eoFill: Bool = false, antialiased: Bool = true) {
        self.isEOFilled = eoFill
        self.isAntialiased = antialiased
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
        self
    }
}

@MainActor
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    private var object: ObjectType

    public init(wrappedValue: @autoclosure () -> ObjectType) {
        self.object = wrappedValue()
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

    public var projectedValue: StateObject<ObjectType> {
        self
    }
}

@MainActor
@propertyWrapper
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    public var wrappedValue: Value {
        get {
            getValue()
        }
        nonmutating set {
            setValue(newValue)
        }
    }

    public var projectedValue: Binding<Value> {
        self
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

@MainActor
@propertyWrapper
public struct State<Value> {
    @MainActor
    private final class Storage {
        var value: Value
        var invalidate: (@MainActor () -> Void)?

        init(value: Value) {
            self.value = value
        }
    }

    private let storage: Storage

    public init(wrappedValue: Value) {
        self.storage = Storage(value: wrappedValue)
    }

    public init(initialValue: Value) {
        self.storage = Storage(value: initialValue)
    }

    public var wrappedValue: Value {
        get {
            if let context = ViewBuildContextScope.current {
                storage.invalidate = {
                    context.invalidate()
                }
            }
            return storage.value
        }
        nonmutating set {
            storage.value = newValue
            storage.invalidate?()
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: {
                wrappedValue
            },
            set: { newValue in
                wrappedValue = newValue
            }
        )
    }
}

@MainActor
public struct ViewBuildContext {
    private let canvasSizeProvider: () -> Size
    private let invalidateHandler: () -> Void
    private let observedObjectHandler: (any ObservableObject) -> Void
    private let isEnabledProvider: () -> Bool
    private let foregroundColorProvider: () -> Color
    private let tintProvider: () -> Color
    private let fontProvider: () -> Font
    private let fontWeightProvider: () -> Font.Weight?
    private let textAlignmentProvider: () -> TextAlignment
    private let lineLimitProvider: () -> Int?
    private let stackAxisProvider: () -> StackAxis?

    public var canvasSize: Size {
        canvasSizeProvider()
    }

    public var isEnabled: Bool {
        isEnabledProvider()
    }

    public var foregroundColor: Color {
        foregroundColorProvider()
    }

    public var tint: Color {
        tintProvider()
    }

    public var font: Font {
        fontProvider()
    }

    public var fontWeight: Font.Weight? {
        fontWeightProvider()
    }

    public var textAlignment: TextAlignment {
        textAlignmentProvider()
    }

    public var lineLimit: Int? {
        lineLimitProvider()
    }

    public var stackAxis: StackAxis? {
        stackAxisProvider()
    }

    init(
        canvasSizeProvider: @escaping () -> Size,
        invalidateHandler: @escaping () -> Void,
        observedObjectHandler: @escaping (any ObservableObject) -> Void = { _ in },
        isEnabledProvider: @escaping () -> Bool = { true },
        foregroundColorProvider: @escaping () -> Color = { .white },
        tintProvider: @escaping () -> Color = { ViewBuildContext.defaultTint },
        fontProvider: @escaping () -> Font = { .system(size: 2) },
        fontWeightProvider: @escaping () -> Font.Weight? = { nil },
        textAlignmentProvider: @escaping () -> TextAlignment = { .center },
        lineLimitProvider: @escaping () -> Int? = { nil },
        stackAxisProvider: @escaping () -> StackAxis? = { nil }
    ) {
        self.canvasSizeProvider = canvasSizeProvider
        self.invalidateHandler = invalidateHandler
        self.observedObjectHandler = observedObjectHandler
        self.isEnabledProvider = isEnabledProvider
        self.foregroundColorProvider = foregroundColorProvider
        self.tintProvider = tintProvider
        self.fontProvider = fontProvider
        self.fontWeightProvider = fontWeightProvider
        self.textAlignmentProvider = textAlignmentProvider
        self.lineLimitProvider = lineLimitProvider
        self.stackAxisProvider = stackAxisProvider
    }

    public static let defaultTint = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0)

    func invalidate() {
        invalidateHandler()
    }

    func observe(_ object: any ObservableObject) {
        observedObjectHandler(object)
    }

    func withEnabled(_ isEnabled: Bool) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: {
                self.isEnabled && isEnabled
            },
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: stackAxisProvider
        )
    }

    func withForegroundColor(_ color: Color) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: { color },
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: stackAxisProvider
        )
    }

    func withTint(_ tint: Color) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: { tint },
            fontProvider: fontProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: stackAxisProvider
        )
    }

    func withFont(_ font: Font) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: { font },
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: stackAxisProvider
        )
    }

    func withFontWeight(_ weight: Font.Weight?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontWeightProvider: { weight },
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: stackAxisProvider
        )
    }

    func withTextAlignment(_ alignment: TextAlignment) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: { alignment },
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: stackAxisProvider
        )
    }

    func withLineLimit(_ lineLimit: Int?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: { lineLimit },
            stackAxisProvider: stackAxisProvider
        )
    }

    func withStackAxis(_ axis: StackAxis?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            stackAxisProvider: { axis }
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
public protocol Shape: View {}

public extension Shape {
    var body: Never {
        fatalError("Shape body is not materialized by WinSwiftUI")
    }
}

enum RetainedClipShapeStyle {
    case rectangle
    case roundedRectangle(Double)
    case capsule

    var staticCornerRadius: Double {
        switch self {
        case .rectangle, .capsule:
            return 0
        case .roundedRectangle(let radius):
            return max(0, radius)
        }
    }
}

@MainActor
protocol RetainedClipShape: Shape {
    var retainedClipShapeStyle: RetainedClipShapeStyle { get }
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

    public static func buildExpression<Data, ID>(
        _ expression: ForEach<Data, ID>
    ) -> [AnyView] {
        expression.contentViews
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

public struct SafeAreaRegions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let container = SafeAreaRegions(rawValue: 1 << 0)
    public static let keyboard = SafeAreaRegions(rawValue: 1 << 1)
    public static let all: SafeAreaRegions = [.container, .keyboard]
}

public struct Font: Sendable, Equatable {
    public enum Weight: Sendable, Equatable {
        case ultraLight
        case thin
        case light
        case regular
        case medium
        case semibold
        case bold
        case heavy
        case black
    }

    public enum Design: Sendable, Equatable {
        case `default`
        case rounded
        case monospaced
    }

    public enum TextStyle: Sendable, Equatable {
        case largeTitle
        case title
        case title2
        case title3
        case headline
        case subheadline
        case body
        case callout
        case footnote
        case caption
        case caption2
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

    public static func system(_ style: TextStyle, design: Design? = nil, weight: Weight? = nil) -> Font {
        let font = defaultFont(for: style)
        return Font(
            size: font.size,
            weight: weight ?? font.weight,
            design: design ?? font.design,
            family: font.family
        )
    }

    public static let largeTitle = Font(size: 34)
    public static let title = Font(size: 28)
    public static let title2 = Font(size: 22)
    public static let title3 = Font(size: 20)
    public static let headline = Font(size: 17, weight: .semibold)
    public static let subheadline = Font(size: 15)
    public static let body = Font(size: 17)
    public static let callout = Font(size: 16)
    public static let footnote = Font(size: 13)
    public static let caption = Font(size: 12)
    public static let caption2 = Font(size: 11)

    public func weight(_ weight: Weight) -> Font {
        Font(size: size, weight: weight, design: design, family: family)
    }

    private static func defaultFont(for style: TextStyle) -> Font {
        switch style {
        case .largeTitle:
            return .largeTitle
        case .title:
            return .title
        case .title2:
            return .title2
        case .title3:
            return .title3
        case .headline:
            return .headline
        case .subheadline:
            return .subheadline
        case .body:
            return .body
        case .callout:
            return .callout
        case .footnote:
            return .footnote
        case .caption:
            return .caption
        case .caption2:
            return .caption2
        }
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

    public static let destructive = ButtonSurfaceStyle(
        cornerRadius: 16,
        palette: SurfacePalette(
            idle: Color(red: 0.50, green: 0.12, blue: 0.14, alpha: 0.78),
            hovered: Color(red: 0.62, green: 0.16, blue: 0.18, alpha: 0.86),
            focused: Color(red: 0.70, green: 0.20, blue: 0.22, alpha: 0.92),
            pressed: Color(red: 0.78, green: 0.24, blue: 0.26, alpha: 0.96),
            activated: Color(red: 0.88, green: 0.28, blue: 0.30, alpha: 0.98),
            disabledBackground: Color(red: 0.18, green: 0.10, blue: 0.11, alpha: 0.45),
            disabledBorder: Color(red: 0.55, green: 0.20, blue: 0.22, alpha: 0.18)
        ),
        chrome: SurfaceChrome(
            borderColor: Color(red: 1.0, green: 0.64, blue: 0.64, alpha: 0.18),
            borderHoveredColor: Color(red: 1.0, green: 0.72, blue: 0.72, alpha: 0.28),
            borderFocusedColor: Color(red: 1.0, green: 0.78, blue: 0.78, alpha: 0.38),
            borderPressedColor: Color(red: 1.0, green: 0.86, blue: 0.86, alpha: 0.46),
            borderWidth: 1,
            focusRingColor: Color(red: 1.0, green: 0.50, blue: 0.50, alpha: 0.30),
            focusRingWidth: 2,
            shadowColor: Color(red: 0.32, green: 0.04, blue: 0.05, alpha: 0.22),
            shadowHoveredColor: Color(red: 0.42, green: 0.05, blue: 0.06, alpha: 0.28),
            shadowFocusedColor: Color(red: 0.52, green: 0.07, blue: 0.08, alpha: 0.34),
            shadowPressedColor: Color(red: 0.22, green: 0.03, blue: 0.04, alpha: 0.18),
            shadowOffset: Point(x: 0, y: 16),
            shadowSpread: 10
        ),
        clipsToBounds: true,
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

public enum ButtonRole: Sendable, Equatable {
    case destructive
    case cancel
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
        case .ultraLight, .thin, .light, .regular, .medium:
            return .regular
        case .semibold:
            return .semibold
        case .bold, .heavy, .black:
            return .bold
        }
    }
}

extension Font {
    var resolvedScale: Double {
        size >= 8 ? size / 10.0 : size
    }

    var resolvedNativeTextSize: Double {
        size >= 8 ? size : max(12, size * 6 + 8)
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
    static let red = SwiftWindowsCore.Color(red: 1, green: 0, blue: 0, alpha: 1)
    static let orange = SwiftWindowsCore.Color(red: 1, green: 0.5, blue: 0, alpha: 1)
    static let yellow = SwiftWindowsCore.Color(red: 1, green: 1, blue: 0, alpha: 1)
    static let green = SwiftWindowsCore.Color(red: 0, green: 1, blue: 0, alpha: 1)
    static let mint = SwiftWindowsCore.Color(red: 0, green: 0.78, blue: 0.75, alpha: 1)
    static let teal = SwiftWindowsCore.Color(red: 0, green: 0.5, blue: 0.5, alpha: 1)
    static let cyan = SwiftWindowsCore.Color(red: 0, green: 1, blue: 1, alpha: 1)
    static let blue = SwiftWindowsCore.Color(red: 0, green: 0, blue: 1, alpha: 1)
    static let indigo = SwiftWindowsCore.Color(red: 0.29, green: 0, blue: 0.51, alpha: 1)
    static let purple = SwiftWindowsCore.Color(red: 0.5, green: 0, blue: 0.5, alpha: 1)
    static let pink = SwiftWindowsCore.Color(red: 1, green: 0.41, blue: 0.71, alpha: 1)
    static let brown = SwiftWindowsCore.Color(red: 0.6, green: 0.4, blue: 0.2, alpha: 1)
    static let gray = SwiftWindowsCore.Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    static let primary = SwiftWindowsCore.Color.white
    static let secondary = SwiftWindowsCore.Color(red: 0.70, green: 0.74, blue: 0.80, alpha: 1)
    static let accentColor = SwiftWindowsCore.Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0)

    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.init(red: Float(red), green: Float(green), blue: Float(blue), alpha: Float(opacity))
    }

    init(white: Double, opacity: Double = 1.0) {
        let channel = Float(clampedUnitInterval(white))
        self.init(red: channel, green: channel, blue: channel, alpha: Float(clampedUnitInterval(opacity)))
    }

    init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1.0) {
        let normalizedHue = normalizedHueUnit(hue)
        let saturation = clampedUnitInterval(saturation)
        let brightness = clampedUnitInterval(brightness)
        let chroma = brightness * saturation
        let hueSector = normalizedHue * 6
        let secondary = chroma * (1 - abs(hueSector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma

        let components: (Double, Double, Double)
        switch hueSector {
        case 0..<1:
            components = (chroma, secondary, 0)
        case 1..<2:
            components = (secondary, chroma, 0)
        case 2..<3:
            components = (0, chroma, secondary)
        case 3..<4:
            components = (0, secondary, chroma)
        case 4..<5:
            components = (secondary, 0, chroma)
        default:
            components = (chroma, 0, secondary)
        }

        self.init(
            red: Float(components.0 + match),
            green: Float(components.1 + match),
            blue: Float(components.2 + match),
            alpha: Float(clampedUnitInterval(opacity))
        )
    }

    func opacity(_ value: Double) -> SwiftWindowsCore.Color {
        let components = rgba
        return SwiftWindowsCore.Color(red: components.0, green: components.1, blue: components.2, alpha: Float(value))
    }
}

private func clampedUnitInterval(_ value: Double) -> Double {
    guard value.isFinite else {
        return 0
    }

    return min(max(value, 0), 1)
}

private func normalizedHueUnit(_ hue: Double) -> Double {
    guard hue.isFinite else {
        return 0
    }

    let normalized = hue.truncatingRemainder(dividingBy: 1)
    return normalized >= 0 ? normalized : normalized + 1
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

private func normalizedFrameMinimum(_ value: Double?) -> Double {
    guard let value, value.isFinite else {
        return 0
    }

    return max(0, value)
}

private func normalizedFrameMaximum(_ value: Double?, minimum: Double) -> Double {
    guard let value else {
        return .infinity
    }

    guard value.isFinite else {
        return .infinity
    }

    return max(minimum, value)
}

private func normalizedFrameIdeal(_ value: Double?) -> Double? {
    guard let value, value.isFinite else {
        return nil
    }

    return max(0, value)
}

public extension View {
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

    func frame(
        minWidth: Double? = nil,
        idealWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        idealHeight: Double? = nil,
        maxHeight: Double? = nil,
        alignment: Alignment = .center
    ) -> some View {
        let resolvedMinWidth = normalizedFrameMinimum(minWidth)
        let resolvedMinHeight = normalizedFrameMinimum(minHeight)
        let constraints = LayoutConstraints(
            minWidth: resolvedMinWidth,
            maxWidth: normalizedFrameMaximum(maxWidth, minimum: resolvedMinWidth),
            minHeight: resolvedMinHeight,
            maxHeight: normalizedFrameMaximum(maxHeight, minimum: resolvedMinHeight)
        )
        let idealSize = Size(
            width: normalizedFrameIdeal(idealWidth) ?? 0,
            height: normalizedFrameIdeal(idealHeight) ?? 0
        )
        let hasIdealSize = idealWidth != nil || idealHeight != nil

        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let root = Controls.stackPanel(
                    preferredSize: hasIdealSize ? idealSize : nil,
                    stackLayout: .vertical(
                        padding: .zero,
                        alignment: alignment.horizontal.stackAlignment,
                        mainAlignment: alignment.vertical.mainAlignment
                    ),
                    isHitTestVisible: false,
                    children: [childNode]
                )
                root.layoutConstraints = constraints
                return root
            }
        }
    }

    func fixedSize() -> some View {
        fixedSize(horizontal: true, vertical: true)
    }

    func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.fixedSizeAxes = FixedSizeAxes(horizontal: horizontal, vertical: vertical)
                return childNode
            }
        }
    }

    func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> some View {
        self
    }

    func edgesIgnoringSafeArea(_ edges: Edge.Set) -> some View {
        ignoresSafeArea(.all, edges: edges)
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

    func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
        self.background(alignment: alignment) {
            background
        }
    }

    func background(alignment: Alignment = .center, @ViewBuilder content backgroundContent: () -> [AnyView]) -> some View {
        let backgroundViews = backgroundContent()
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            let background = composeComponent(from: backgroundViews, context: context, fallbackLayout: .absolute)

            return Component { runtime in
                let backgroundNode = background.makeNode(runtime: runtime)
                let baseNode = base.makeNode(runtime: runtime)
                let preferredSize = baseNode.intrinsicContentSize()
                let root = Controls.panel(
                    preferredSize: preferredSize,
                    layoutMode: .absolute,
                    isHitTestVisible: false,
                    children: [backgroundNode, baseNode]
                )

                root.onLayout = { bounds in
                    let containerSize = bounds.size
                    let baseFrame = Rect(origin: .zero, size: containerSize)
                    if baseNode.frame != baseFrame {
                        baseNode.frame = baseFrame
                    }

                    let backgroundSize = backgroundNode.intrinsicContentSize()
                    let backgroundOrigin = alignment.frameOrigin(for: backgroundSize, in: containerSize)
                    let backgroundFrame = Rect(origin: backgroundOrigin, size: backgroundSize)
                    if backgroundNode.frame != backgroundFrame {
                        backgroundNode.frame = backgroundFrame
                    }
                }

                return root
            }
        }
    }

    func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
        self.overlay(alignment: alignment) {
            overlay
        }
    }

    func overlay(alignment: Alignment = .center, @ViewBuilder content overlayContent: () -> [AnyView]) -> some View {
        let overlayViews = overlayContent()
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            let overlay = composeComponent(from: overlayViews, context: context, fallbackLayout: .absolute)

            return Component { runtime in
                let baseNode = base.makeNode(runtime: runtime)
                let overlayNode = overlay.makeNode(runtime: runtime)
                let preferredSize = baseNode.intrinsicContentSize()
                let root = Controls.panel(
                    preferredSize: preferredSize,
                    layoutMode: .absolute,
                    isHitTestVisible: false,
                    children: [baseNode, overlayNode]
                )

                root.onLayout = { bounds in
                    let containerSize = bounds.size
                    let baseFrame = Rect(origin: .zero, size: containerSize)
                    if baseNode.frame != baseFrame {
                        baseNode.frame = baseFrame
                    }

                    let overlaySize = overlayNode.intrinsicContentSize()
                    let overlayOrigin = alignment.frameOrigin(for: overlaySize, in: containerSize)
                    let overlayFrame = Rect(origin: overlayOrigin, size: overlaySize)
                    if overlayNode.frame != overlayFrame {
                        overlayNode.frame = overlayFrame
                    }
                }

                return root
            }
        }
    }

    func foregroundColor(_ color: Color) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withForegroundColor(color))
        }
    }

    func foregroundStyle(_ color: Color) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withForegroundColor(color))
        }
    }

    func tint(_ tint: Color) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTint(tint))
        }
    }

    func accentColor(_ accentColor: Color?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTint(accentColor ?? ViewBuildContext.defaultTint))
        }
    }

    func font(_ font: Font) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withFont(font))
        }
    }

    func fontWeight(_ weight: Font.Weight?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withFontWeight(weight))
        }
    }

    func bold() -> some View {
        fontWeight(.bold)
    }

    func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTextAlignment(alignment))
        }
    }

    func lineLimit(_ lineLimit: Int?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withLineLimit(lineLimit))
        }
    }

    func cornerRadius(_ radius: Double, antialiased: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    cornerRadius: radius,
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func clipped(antialiased: Bool = false) -> some View {
        ModifiedView(content: self) { content, context in
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
        let clipStyle = (shape as? any RetainedClipShape)?.retainedClipShapeStyle ?? .rectangle
        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let root = Controls.stackPanel(
                    cornerRadius: clipStyle.staticCornerRadius,
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )

                if case .capsule = clipStyle {
                    root.onLayout = { [weak root] bounds in
                        let radius = max(0, min(bounds.size.width, bounds.size.height) * 0.5)
                        if root?.cornerRadius != radius {
                            root?.cornerRadius = radius
                        }
                    }
                }

                return root
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

    func opacity(_ opacity: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.opacity = max(0, min(1, opacity))
                return childNode
            }
        }
    }

    func hidden(_ shouldHide: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHidden = shouldHide
                return childNode
            }
        }
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

    func offset(_ offset: CGSize) -> some View {
        self.offset(x: offset.width, y: offset.height)
    }

    func scaleEffect(_ scale: Double) -> some View {
        scaleEffect(x: scale, y: scale)
    }

    func scaleEffect(x: Double = 1, y: Double = 1) -> some View {
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

    func disabled(_ disabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnabled(!disabled))
        }
    }

    func onAppear(perform action: (() -> Void)? = nil) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let existingOnAppear = childNode.onAppear
                childNode.onAppear = {
                    existingOnAppear?()
                    action?()
                }
                return childNode
            }
        }
    }

    func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let existingOnDisappear = childNode.onDisappear
                childNode.onDisappear = {
                    existingOnDisappear?()
                    action?()
                }
                return childNode
            }
        }
    }

    func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true

                guard count == 1 else {
                    return childNode
                }

                let existingOnPointerUpInside = childNode.onPointerUpInside
                childNode.onPointerUpInside = {
                    existingOnPointerUpInside?()
                    action()
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
