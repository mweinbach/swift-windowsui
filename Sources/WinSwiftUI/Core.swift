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
public typealias LocalizedStringKey = String
public typealias LocalizedStringResource = String
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

public struct Circle: Shape, Equatable {
    public init() {}
}

public struct Ellipse: Shape, Equatable {
    public init() {}
}

public struct Capsule: Shape, Equatable {
    public var style: RoundedCornerStyle

    public init(style: RoundedCornerStyle = .continuous) {
        self.style = style
    }
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
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    private let box: StateObjectBox<ObjectType>

    public init(wrappedValue makeObject: @autoclosure @escaping @MainActor () -> ObjectType) {
        self.box = StateObjectBox(makeObject: makeObject)
    }

    public var wrappedValue: ObjectType {
        let object = box.object
        ViewBuildContextScope.current?.observe(object)
        return object
    }

    public var projectedValue: ObservedObject<ObjectType> {
        let object = box.object
        ViewBuildContextScope.current?.observe(object)
        return ObservedObject(wrappedValue: object)
    }
}

@MainActor
private final class StateObjectBox<ObjectType: ObservableObject> {
    private let makeObject: @MainActor () -> ObjectType
    private var cachedObject: ObjectType?

    var object: ObjectType {
        if let cachedObject {
            return cachedObject
        }

        let object = makeObject()
        cachedObject = object
        return object
    }

    init(makeObject: @escaping @MainActor () -> ObjectType) {
        self.makeObject = makeObject
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
    var buttonStyle: ButtonStyle?
    var listStyle: ListStyle?
    var labelStyle: LabelStyle?
    var toggleStyle: ToggleStyle?
    var pickerStyle: PickerStyle?
    var menuStyle: MenuStyle
    var controlGroupStyle: ControlGroupStyle
    var controlSize: ControlSize
    var textFieldStyle: TextFieldStyle
    var progressViewStyle: ProgressViewStyle
    var gaugeStyle: GaugeStyle
    var datePickerStyle: DatePickerStyle
    var submitAction: (() -> Void)?
    var containerAxis: Axis?

    public var canvasSize: Size {
        canvasSizeProvider()
    }

    init(
        canvasSizeProvider: @escaping () -> Size,
        invalidateHandler: @escaping () -> Void,
        observedObjectHandler: @escaping (any ObservableObject) -> Void = { _ in },
        tintColor: Color? = nil,
        buttonStyle: ButtonStyle? = nil,
        listStyle: ListStyle? = nil,
        labelStyle: LabelStyle? = nil,
        toggleStyle: ToggleStyle? = nil,
        pickerStyle: PickerStyle? = nil,
        menuStyle: MenuStyle = .automatic,
        controlGroupStyle: ControlGroupStyle = .automatic,
        controlSize: ControlSize = .regular,
        textFieldStyle: TextFieldStyle = .automatic,
        progressViewStyle: ProgressViewStyle = .automatic,
        gaugeStyle: GaugeStyle = .automatic,
        datePickerStyle: DatePickerStyle = .automatic,
        submitAction: (() -> Void)? = nil,
        containerAxis: Axis? = nil
    ) {
        self.canvasSizeProvider = canvasSizeProvider
        self.invalidateHandler = invalidateHandler
        self.observedObjectHandler = observedObjectHandler
        self.tintColor = tintColor
        self.buttonStyle = buttonStyle
        self.listStyle = listStyle
        self.labelStyle = labelStyle
        self.toggleStyle = toggleStyle
        self.pickerStyle = pickerStyle
        self.menuStyle = menuStyle
        self.controlGroupStyle = controlGroupStyle
        self.controlSize = controlSize
        self.textFieldStyle = textFieldStyle
        self.progressViewStyle = progressViewStyle
        self.gaugeStyle = gaugeStyle
        self.datePickerStyle = datePickerStyle
        self.submitAction = submitAction
        self.containerAxis = containerAxis
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
            tintColor: color,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withButtonStyle(_ style: ButtonStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: style,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withListStyle(_ style: ListStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: style,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withLabelStyle(_ style: LabelStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: style,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withToggleStyle(_ style: ToggleStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: style,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withPickerStyle(_ style: PickerStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: style,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withMenuStyle(_ style: MenuStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: style,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withControlGroupStyle(_ style: ControlGroupStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: style,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withControlSize(_ size: ControlSize) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: size,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withTextFieldStyle(_ style: TextFieldStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: style,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withProgressViewStyle(_ style: ProgressViewStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: style,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withGaugeStyle(_ style: GaugeStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: style,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withDatePickerStyle(_ style: DatePickerStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: style,
            submitAction: submitAction,
            containerAxis: containerAxis
        )
    }

    func withSubmitAction(_ action: @escaping () -> Void) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: action,
            containerAxis: containerAxis
        )
    }

    func withContainerAxis(_ axis: Axis?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            tintColor: tintColor,
            buttonStyle: buttonStyle,
            listStyle: listStyle,
            labelStyle: labelStyle,
            toggleStyle: toggleStyle,
            pickerStyle: pickerStyle,
            menuStyle: menuStyle,
            controlGroupStyle: controlGroupStyle,
            controlSize: controlSize,
            textFieldStyle: textFieldStyle,
            progressViewStyle: progressViewStyle,
            gaugeStyle: gaugeStyle,
            datePickerStyle: datePickerStyle,
            submitAction: submitAction,
            containerAxis: axis
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

public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 0)
    public static let date = DatePickerComponents(rawValue: 1 << 1)
}

public enum ScrollIndicatorVisibility: Sendable, Equatable {
    case automatic
    case visible
    case hidden
}

public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

public struct GridItem: Sendable {
    public enum Size: Sendable {
        case fixed(Double)
        case flexible(minimum: Double = 10, maximum: Double = .infinity)
        case adaptive(minimum: Double, maximum: Double = .infinity)
    }

    public var size: Size
    public var spacing: Double?
    public var alignment: Alignment?

    public init(_ size: Size = .flexible(), spacing: Double? = nil, alignment: Alignment? = nil) {
        self.size = size
        self.spacing = spacing
        self.alignment = alignment
    }
}

public enum Anchor<Value>: Sendable {
    public enum Source: Sendable, Equatable {
        case bounds
    }
}

public enum PopoverAttachmentAnchor: Sendable, Equatable {
    case rect(Anchor<CGRect>.Source)
}

public enum Edge: Sendable, Equatable {
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
        var font = style.font
        if let design {
            font.design = design
        }
        if let weight {
            font.weight = weight
        }
        return font
    }

    public static func custom(_ name: String, size: Double) -> Font {
        Font(size: size, family: name)
    }

    public static func custom(_ name: String, fixedSize: Double) -> Font {
        Font(size: fixedSize, family: name)
    }

    public static let largeTitle = Font(size: 34, weight: .regular)
    public static let title = Font(size: 28, weight: .regular)
    public static let title2 = Font(size: 22, weight: .regular)
    public static let title3 = Font(size: 20, weight: .regular)
    public static let headline = Font(size: 17, weight: .semibold)
    public static let subheadline = Font(size: 15, weight: .regular)
    public static let body = Font(size: 17, weight: .regular)
    public static let callout = Font(size: 16, weight: .regular)
    public static let footnote = Font(size: 13, weight: .regular)
    public static let caption = Font(size: 12, weight: .regular)
    public static let caption2 = Font(size: 11, weight: .regular)
}

public struct Material: Sendable, Equatable {
    public var backgroundColor: Color
    public var borderColor: Color
    public var borderWidth: Double
    public var cornerRadius: Double
    public var blurRadius: Double
    public var shadowColor: Color
    public var shadowOffset: Point
    public var shadowSpread: Double

    public init(
        backgroundColor: Color,
        borderColor: Color = Color(red: 1, green: 1, blue: 1, alpha: 0.16),
        borderWidth: Double = 1,
        cornerRadius: Double = 18,
        blurRadius: Double = 18,
        shadowColor: Color = Color(red: 0, green: 0, blue: 0, alpha: 0.18),
        shadowOffset: Point = Point(x: 0, y: 12),
        shadowSpread: Double = 18
    ) {
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.blurRadius = blurRadius
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowSpread = shadowSpread
    }

    public static let ultraThinMaterial = Material(
        backgroundColor: Color(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.12),
        blurRadius: 26
    )
    public static let thinMaterial = Material(
        backgroundColor: Color(red: 0.92, green: 0.95, blue: 1.0, alpha: 0.18),
        blurRadius: 22
    )
    public static let regularMaterial = Material(
        backgroundColor: Color(red: 0.88, green: 0.92, blue: 0.98, alpha: 0.26),
        blurRadius: 18
    )
    public static let thickMaterial = Material(
        backgroundColor: Color(red: 0.82, green: 0.88, blue: 0.96, alpha: 0.36),
        blurRadius: 14
    )
    public static let ultraThickMaterial = Material(
        backgroundColor: Color(red: 0.76, green: 0.84, blue: 0.94, alpha: 0.46),
        blurRadius: 10
    )
    public static let bar = Material(
        backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.23, alpha: 0.72),
        borderColor: Color(red: 1, green: 1, blue: 1, alpha: 0.10),
        cornerRadius: 14,
        blurRadius: 20,
        shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.12),
        shadowOffset: Point(x: 0, y: 8),
        shadowSpread: 12
    )
}

struct ControlSizeMetrics: Sendable {
    var buttonPadding: EdgeInsets
    var buttonCornerRadius: Double
    var switchPreferredSize: Size
    var checkboxBoxSize: Double
    var checkboxIconSize: Double
    var checkboxCornerRadius: Double
    var checkboxPadding: EdgeInsets
    var checkboxSpacing: Double
    var toggleButtonPlaceholderSize: Size
    var textFieldPreferredSize: Size
    var textEditorPreferredSize: Size
    var sliderPreferredSize: Size
    var progressPreferredSize: Size
    var progressRingPreferredSize: Size
    var pickerMenuPreferredSize: Size
    var pickerSegmentedPreferredSize: Size
    var pickerRadioRowPreferredSize: Size?
}

public struct ControlSize: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case mini
        case small
        case regular
        case large
        case extraLarge
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let mini = ControlSize(kind: .mini)
    public static let small = ControlSize(kind: .small)
    public static let regular = ControlSize(kind: .regular)
    public static let large = ControlSize(kind: .large)
    public static let extraLarge = ControlSize(kind: .extraLarge)

    var metrics: ControlSizeMetrics {
        switch kind {
        case .mini:
            return ControlSizeMetrics(
                buttonPadding: EdgeInsets(top: 3, leading: 7, bottom: 3, trailing: 7),
                buttonCornerRadius: 10,
                switchPreferredSize: Size(width: 46, height: 28),
                checkboxBoxSize: 16,
                checkboxIconSize: 10,
                checkboxCornerRadius: 4,
                checkboxPadding: EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6),
                checkboxSpacing: 7,
                toggleButtonPlaceholderSize: Size(width: 34, height: 16),
                textFieldPreferredSize: Size(width: 180, height: 30),
                textEditorPreferredSize: Size(width: 260, height: 84),
                sliderPreferredSize: Size(width: 160, height: 24),
                progressPreferredSize: Size(width: 160, height: 5),
                progressRingPreferredSize: Size(width: 22, height: 22),
                pickerMenuPreferredSize: Size(width: 160, height: 30),
                pickerSegmentedPreferredSize: Size(width: 180, height: 30),
                pickerRadioRowPreferredSize: Size(width: 180, height: 30)
            )
        case .small:
            return ControlSizeMetrics(
                buttonPadding: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10),
                buttonCornerRadius: 12,
                switchPreferredSize: Size(width: 48, height: 30),
                checkboxBoxSize: 18,
                checkboxIconSize: 12,
                checkboxCornerRadius: 5,
                checkboxPadding: EdgeInsets(top: 5, leading: 7, bottom: 5, trailing: 7),
                checkboxSpacing: 8,
                toggleButtonPlaceholderSize: Size(width: 38, height: 18),
                textFieldPreferredSize: Size(width: 200, height: 34),
                textEditorPreferredSize: Size(width: 290, height: 102),
                sliderPreferredSize: Size(width: 180, height: 26),
                progressPreferredSize: Size(width: 180, height: 6),
                progressRingPreferredSize: Size(width: 26, height: 26),
                pickerMenuPreferredSize: Size(width: 180, height: 34),
                pickerSegmentedPreferredSize: Size(width: 200, height: 34),
                pickerRadioRowPreferredSize: Size(width: 200, height: 34)
            )
        case .regular:
            return ControlSizeMetrics(
                buttonPadding: EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14),
                buttonCornerRadius: 16,
                switchPreferredSize: Size(width: 52, height: 32),
                checkboxBoxSize: 20,
                checkboxIconSize: 14,
                checkboxCornerRadius: 6,
                checkboxPadding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                checkboxSpacing: 10,
                toggleButtonPlaceholderSize: Size(width: 44, height: 20),
                textFieldPreferredSize: Size(width: 220, height: 38),
                textEditorPreferredSize: Size(width: 320, height: 120),
                sliderPreferredSize: Size(width: 200, height: 28),
                progressPreferredSize: Size(width: 200, height: 8),
                progressRingPreferredSize: Size(width: 30, height: 30),
                pickerMenuPreferredSize: Size(width: 200, height: 36),
                pickerSegmentedPreferredSize: Size(width: 220, height: 38),
                pickerRadioRowPreferredSize: nil
            )
        case .large:
            return ControlSizeMetrics(
                buttonPadding: EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18),
                buttonCornerRadius: 18,
                switchPreferredSize: Size(width: 60, height: 38),
                checkboxBoxSize: 24,
                checkboxIconSize: 16,
                checkboxCornerRadius: 7,
                checkboxPadding: EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10),
                checkboxSpacing: 12,
                toggleButtonPlaceholderSize: Size(width: 52, height: 24),
                textFieldPreferredSize: Size(width: 260, height: 44),
                textEditorPreferredSize: Size(width: 360, height: 148),
                sliderPreferredSize: Size(width: 240, height: 34),
                progressPreferredSize: Size(width: 240, height: 10),
                progressRingPreferredSize: Size(width: 36, height: 36),
                pickerMenuPreferredSize: Size(width: 240, height: 42),
                pickerSegmentedPreferredSize: Size(width: 260, height: 44),
                pickerRadioRowPreferredSize: Size(width: 240, height: 42)
            )
        case .extraLarge:
            return ControlSizeMetrics(
                buttonPadding: EdgeInsets(top: 13, leading: 22, bottom: 13, trailing: 22),
                buttonCornerRadius: 22,
                switchPreferredSize: Size(width: 68, height: 44),
                checkboxBoxSize: 28,
                checkboxIconSize: 18,
                checkboxCornerRadius: 8,
                checkboxPadding: EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12),
                checkboxSpacing: 14,
                toggleButtonPlaceholderSize: Size(width: 60, height: 28),
                textFieldPreferredSize: Size(width: 300, height: 52),
                textEditorPreferredSize: Size(width: 420, height: 180),
                sliderPreferredSize: Size(width: 280, height: 40),
                progressPreferredSize: Size(width: 280, height: 12),
                progressRingPreferredSize: Size(width: 44, height: 44),
                pickerMenuPreferredSize: Size(width: 280, height: 50),
                pickerSegmentedPreferredSize: Size(width: 300, height: 52),
                pickerRadioRowPreferredSize: Size(width: 280, height: 50)
            )
        }
    }
}

struct TextFieldStyleMetrics: Sendable {
    var palette: SurfacePalette
    var chrome: SurfaceChrome
    var cornerRadius: Double
    var clipsToBounds: Bool
}

public struct TextFieldStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case roundedBorder
        case plain
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = TextFieldStyle(kind: .automatic)
    public static let roundedBorder = TextFieldStyle(kind: .roundedBorder)
    public static let plain = TextFieldStyle(kind: .plain)

    var metrics: TextFieldStyleMetrics {
        switch kind {
        case .automatic, .roundedBorder:
            return TextFieldStyleMetrics(
                palette: SurfacePalette(
                    idle: Color(red: 0.15, green: 0.19, blue: 0.27, alpha: 0.92),
                    hovered: Color(red: 0.18, green: 0.23, blue: 0.32, alpha: 0.96),
                    focused: Color(red: 0.20, green: 0.27, blue: 0.38, alpha: 0.98),
                    pressed: Color(red: 0.20, green: 0.27, blue: 0.38, alpha: 0.98)
                ),
                chrome: SurfaceChrome(
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                    borderHoveredColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22),
                    borderFocusedColor: Color(red: 0.48, green: 0.72, blue: 1.0, alpha: 0.58),
                    borderWidth: 1,
                    focusRingColor: Color(red: 0.50, green: 0.74, blue: 1.0, alpha: 0.20),
                    focusRingWidth: 2
                ),
                cornerRadius: 12,
                clipsToBounds: true
            )
        case .plain:
            return TextFieldStyleMetrics(
                palette: SurfacePalette(
                    idle: .clear,
                    hovered: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.05),
                    focused: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    pressed: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    disabledBackground: .clear,
                    disabledBorder: .clear
                ),
                chrome: SurfaceChrome(
                    borderColor: .clear,
                    borderHoveredColor: .clear,
                    borderFocusedColor: .clear,
                    borderPressedColor: .clear,
                    borderWidth: 0,
                    focusRingColor: Color(red: 0.50, green: 0.74, blue: 1.0, alpha: 0.18),
                    focusRingWidth: 2
                ),
                cornerRadius: 0,
                clipsToBounds: false
            )
        }
    }
}

public struct DefaultTextFieldStyle: Sendable {
    public init() {}
}

public struct RoundedBorderTextFieldStyle: Sendable {
    public init() {}
}

public struct PlainTextFieldStyle: Sendable {
    public init() {}
}

enum ProgressViewControlKind: Sendable {
    case linear
    case circular
}

public struct ProgressViewStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case linear
        case circular
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ProgressViewStyle(kind: .automatic)
    public static let linear = ProgressViewStyle(kind: .linear)
    public static let circular = ProgressViewStyle(kind: .circular)

    var controlKind: ProgressViewControlKind {
        switch kind {
        case .automatic, .linear:
            return .linear
        case .circular:
            return .circular
        }
    }
}

public struct DefaultProgressViewStyle: Sendable {
    public init() {}
}

public struct LinearProgressViewStyle: Sendable {
    public init() {}
}

public struct CircularProgressViewStyle: Sendable {
    public init() {}
}

enum GaugeControlKind: Sendable {
    case linear
    case circular
}

public struct GaugeStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case linear
        case accessoryLinear
        case accessoryLinearCapacity
        case circular
        case accessoryCircular
        case accessoryCircularCapacity
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = GaugeStyle(kind: .automatic)
    public static let linear = GaugeStyle(kind: .linear)
    public static let accessoryLinear = GaugeStyle(kind: .accessoryLinear)
    public static let accessoryLinearCapacity = GaugeStyle(kind: .accessoryLinearCapacity)
    public static let circular = GaugeStyle(kind: .circular)
    public static let accessoryCircular = GaugeStyle(kind: .accessoryCircular)
    public static let accessoryCircularCapacity = GaugeStyle(kind: .accessoryCircularCapacity)

    var controlKind: GaugeControlKind {
        switch kind {
        case .automatic, .linear, .accessoryLinear, .accessoryLinearCapacity:
            return .linear
        case .circular, .accessoryCircular, .accessoryCircularCapacity:
            return .circular
        }
    }
}

public struct DefaultGaugeStyle: Sendable {
    public init() {}
}

public struct LinearGaugeStyle: Sendable {
    public init() {}
}

public struct AccessoryLinearGaugeStyle: Sendable {
    public init() {}
}

public struct AccessoryLinearCapacityGaugeStyle: Sendable {
    public init() {}
}

public struct CircularGaugeStyle: Sendable {
    public init() {}
}

public struct AccessoryCircularGaugeStyle: Sendable {
    public init() {}
}

public struct AccessoryCircularCapacityGaugeStyle: Sendable {
    public init() {}
}

struct DatePickerStyleMetrics: Sendable {
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: Double
    var cornerRadius: Double
    var padding: EdgeInsets
    var spacing: Double
    var valueMinWidth: Double
    var buttonStyle: ButtonStyle
}

public struct DatePickerStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case compact
        case field
        case stepperField
        case graphical
        case wheel
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = DatePickerStyle(kind: .automatic)
    public static let compact = DatePickerStyle(kind: .compact)
    public static let field = DatePickerStyle(kind: .field)
    public static let stepperField = DatePickerStyle(kind: .stepperField)
    public static let graphical = DatePickerStyle(kind: .graphical)
    public static let wheel = DatePickerStyle(kind: .wheel)

    var metrics: DatePickerStyleMetrics {
        switch kind {
        case .automatic, .compact:
            return DatePickerStyleMetrics(
                backgroundColor: Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.72),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
                borderWidth: 1,
                cornerRadius: 14,
                padding: EdgeInsets(top: 5, leading: 6, bottom: 5, trailing: 6),
                spacing: 6,
                valueMinWidth: 132,
                buttonStyle: .borderless
            )
        case .field, .stepperField:
            return DatePickerStyleMetrics(
                backgroundColor: Color(red: 0.15, green: 0.19, blue: 0.27, alpha: 0.92),
                borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
                borderWidth: 1,
                cornerRadius: 12,
                padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                spacing: 7,
                valueMinWidth: 142,
                buttonStyle: .bordered
            )
        case .graphical:
            return DatePickerStyleMetrics(
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.86),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.16),
                borderWidth: 1,
                cornerRadius: 18,
                padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10),
                spacing: 8,
                valueMinWidth: 150,
                buttonStyle: .borderless
            )
        case .wheel:
            return DatePickerStyleMetrics(
                backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.21, alpha: 0.82),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: 16,
                padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8),
                spacing: 6,
                valueMinWidth: 144,
                buttonStyle: .borderless
            )
        }
    }
}

public struct DefaultDatePickerStyle: Sendable {
    public init() {}
}

public struct CompactDatePickerStyle: Sendable {
    public init() {}
}

public struct FieldDatePickerStyle: Sendable {
    public init() {}
}

public struct StepperFieldDatePickerStyle: Sendable {
    public init() {}
}

public struct GraphicalDatePickerStyle: Sendable {
    public init() {}
}

public struct WheelDatePickerStyle: Sendable {
    public init() {}
}

struct ControlGroupStyleMetrics: Sendable {
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: Double
    var shadowColor: Color
    var shadowOffset: Point
    var shadowSpread: Double
    var cornerRadius: Double
    var clipsToBounds: Bool
    var spacing: Double
    var padding: EdgeInsets
    var childButtonStyle: ButtonStyle?
}

public struct ControlGroupStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case navigation
        case palette
        case menu
        case compactMenu
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ControlGroupStyle(kind: .automatic)
    public static let navigation = ControlGroupStyle(kind: .navigation)
    public static let palette = ControlGroupStyle(kind: .palette)
    public static let menu = ControlGroupStyle(kind: .menu)
    public static let compactMenu = ControlGroupStyle(kind: .compactMenu)

    var metrics: ControlGroupStyleMetrics {
        switch kind {
        case .automatic:
            return ControlGroupStyleMetrics(
                backgroundColor: Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.58),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.12),
                shadowOffset: Point(x: 0, y: 10),
                shadowSpread: 6,
                cornerRadius: 18,
                clipsToBounds: true,
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                childButtonStyle: nil
            )
        case .navigation:
            return ControlGroupStyleMetrics(
                backgroundColor: .clear,
                borderColor: .clear,
                borderWidth: 0,
                shadowColor: .clear,
                shadowOffset: .zero,
                shadowSpread: 0,
                cornerRadius: 0,
                clipsToBounds: false,
                spacing: 6,
                padding: .zero,
                childButtonStyle: .borderless
            )
        case .palette:
            return ControlGroupStyleMetrics(
                backgroundColor: Color(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.82),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.14),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.18),
                shadowOffset: Point(x: 0, y: 12),
                shadowSpread: 8,
                cornerRadius: 16,
                clipsToBounds: true,
                spacing: 3,
                padding: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3),
                childButtonStyle: .borderless
            )
        case .menu:
            return ControlGroupStyleMetrics(
                backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.21, alpha: 0.88),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.12),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.20),
                shadowOffset: Point(x: 0, y: 14),
                shadowSpread: 8,
                cornerRadius: 16,
                clipsToBounds: true,
                spacing: 2,
                padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4),
                childButtonStyle: .borderless
            )
        case .compactMenu:
            return ControlGroupStyleMetrics(
                backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.23, alpha: 0.72),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                borderWidth: 1,
                shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.14),
                shadowOffset: Point(x: 0, y: 8),
                shadowSpread: 5,
                cornerRadius: 14,
                clipsToBounds: true,
                spacing: 1,
                padding: EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2),
                childButtonStyle: .borderless
            )
        }
    }
}

public struct AutomaticControlGroupStyle: Sendable {
    public init() {}
}

public struct NavigationControlGroupStyle: Sendable {
    public init() {}
}

public struct PaletteControlGroupStyle: Sendable {
    public init() {}
}

public struct MenuControlGroupStyle: Sendable {
    public init() {}
}

public struct CompactMenuControlGroupStyle: Sendable {
    public init() {}
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
    public static let prominent = ButtonSurfaceStyle(
        palette: SurfacePalette(
            idle: Color(red: 0.05, green: 0.36, blue: 0.82, alpha: 0.86),
            hovered: Color(red: 0.08, green: 0.44, blue: 0.94, alpha: 0.92),
            focused: Color(red: 0.12, green: 0.50, blue: 1.0, alpha: 0.96),
            pressed: Color(red: 0.18, green: 0.58, blue: 1.0, alpha: 1.0),
            activated: Color(red: 0.32, green: 0.68, blue: 1.0, alpha: 1.0),
            disabledBackground: Color(red: 0.16, green: 0.24, blue: 0.34, alpha: 0.58),
            disabledForeground: Color(red: 0.62, green: 0.70, blue: 0.78, alpha: 0.72),
            disabledBorder: Color(red: 0.34, green: 0.48, blue: 0.64, alpha: 0.30),
            errorBorder: Color(red: 0.90, green: 0.22, blue: 0.20, alpha: 0.90)
        ),
        chrome: SurfaceChrome(
            borderColor: Color(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.18),
            borderHoveredColor: Color(red: 0.84, green: 0.94, blue: 1.0, alpha: 0.32),
            borderFocusedColor: Color(red: 0.90, green: 0.97, blue: 1.0, alpha: 0.42),
            borderPressedColor: Color(red: 0.94, green: 0.99, blue: 1.0, alpha: 0.48),
            borderWidth: 1,
            focusRingColor: Color(red: 0.58, green: 0.78, blue: 1.0, alpha: 0.36),
            focusRingWidth: 2,
            shadowColor: Color(red: 0.02, green: 0.12, blue: 0.28, alpha: 0.22),
            shadowHoveredColor: Color(red: 0.02, green: 0.16, blue: 0.36, alpha: 0.28),
            shadowFocusedColor: Color(red: 0.04, green: 0.20, blue: 0.44, alpha: 0.34),
            shadowPressedColor: Color(red: 0.02, green: 0.08, blue: 0.20, alpha: 0.18),
            shadowOffset: Point(x: 0, y: 16),
            shadowSpread: 12
        )
    )
    public static let destructive = ButtonSurfaceStyle(
        palette: SurfacePalette(
            idle: Color(red: 0.50, green: 0.12, blue: 0.14, alpha: 0.82),
            hovered: Color(red: 0.62, green: 0.16, blue: 0.18, alpha: 0.90),
            focused: Color(red: 0.72, green: 0.20, blue: 0.22, alpha: 0.94),
            pressed: Color(red: 0.84, green: 0.26, blue: 0.28, alpha: 0.98),
            activated: Color(red: 0.92, green: 0.34, blue: 0.36, alpha: 1.0),
            disabledBackground: Color(red: 0.28, green: 0.16, blue: 0.17, alpha: 0.56),
            disabledForeground: Color(red: 0.72, green: 0.60, blue: 0.61, alpha: 0.70),
            disabledBorder: Color(red: 0.56, green: 0.28, blue: 0.30, alpha: 0.32),
            errorBorder: Color(red: 0.96, green: 0.28, blue: 0.30, alpha: 0.94)
        ),
        chrome: SurfaceChrome(
            borderColor: Color(red: 1.0, green: 0.76, blue: 0.76, alpha: 0.18),
            borderHoveredColor: Color(red: 1.0, green: 0.82, blue: 0.82, alpha: 0.30),
            borderFocusedColor: Color(red: 1.0, green: 0.86, blue: 0.86, alpha: 0.40),
            borderPressedColor: Color(red: 1.0, green: 0.90, blue: 0.90, alpha: 0.46),
            borderWidth: 1,
            focusRingColor: Color(red: 1.0, green: 0.62, blue: 0.62, alpha: 0.34),
            focusRingWidth: 2,
            shadowColor: Color(red: 0.18, green: 0.02, blue: 0.03, alpha: 0.18),
            shadowHoveredColor: Color(red: 0.24, green: 0.03, blue: 0.04, alpha: 0.24),
            shadowFocusedColor: Color(red: 0.30, green: 0.04, blue: 0.05, alpha: 0.30),
            shadowPressedColor: Color(red: 0.12, green: 0.02, blue: 0.02, alpha: 0.16),
            shadowOffset: Point(x: 0, y: 16),
            shadowSpread: 10
        )
    )
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

public enum ButtonRole: Sendable, Equatable {
    case cancel
    case destructive
}

public struct ButtonStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case bordered
        case borderedProminent
        case borderless
        case plain
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonStyle(kind: .automatic)
    public static let bordered = ButtonStyle(kind: .bordered)
    public static let borderedProminent = ButtonStyle(kind: .borderedProminent)
    public static let borderless = ButtonStyle(kind: .borderless)
    public static let plain = ButtonStyle(kind: .plain)

    var surfaceStyle: ButtonSurfaceStyle {
        switch kind {
        case .automatic, .bordered:
            return .default
        case .borderedProminent:
            return .prominent
        case .borderless, .plain:
            return .plain
        }
    }
}

struct MenuStyleMetrics: Sendable {
    var buttonStyle: ButtonStyle
    var showsDisclosureIndicator: Bool
    var indicatorColor: Color
    var contentBackgroundColor: Color
    var contentBorderColor: Color
    var contentBorderWidth: Double
    var contentCornerRadius: Double
    var contentPadding: EdgeInsets
    var contentSpacing: Double
}

public struct MenuStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case button
        case borderedButton
        case borderlessButton
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = MenuStyle(kind: .automatic)
    public static let button = MenuStyle(kind: .button)
    public static let borderedButton = MenuStyle(kind: .borderedButton)
    public static let borderlessButton = MenuStyle(kind: .borderlessButton)

    var metrics: MenuStyleMetrics {
        switch kind {
        case .automatic, .borderedButton:
            return MenuStyleMetrics(
                buttonStyle: .bordered,
                showsDisclosureIndicator: true,
                indicatorColor: Color(red: 0.72, green: 0.82, blue: 1.0, alpha: 0.88),
                contentBackgroundColor: Color(red: 0.08, green: 0.12, blue: 0.19, alpha: 0.82),
                contentBorderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                contentBorderWidth: 1,
                contentCornerRadius: 16,
                contentPadding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                contentSpacing: 6
            )
        case .button:
            return MenuStyleMetrics(
                buttonStyle: .bordered,
                showsDisclosureIndicator: false,
                indicatorColor: Color(red: 0.72, green: 0.82, blue: 1.0, alpha: 0.88),
                contentBackgroundColor: Color(red: 0.10, green: 0.14, blue: 0.21, alpha: 0.86),
                contentBorderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.12),
                contentBorderWidth: 1,
                contentCornerRadius: 16,
                contentPadding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                contentSpacing: 6
            )
        case .borderlessButton:
            return MenuStyleMetrics(
                buttonStyle: .borderless,
                showsDisclosureIndicator: true,
                indicatorColor: Color(red: 0.72, green: 0.82, blue: 1.0, alpha: 0.88),
                contentBackgroundColor: Color(red: 0.08, green: 0.12, blue: 0.19, alpha: 0.82),
                contentBorderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.10),
                contentBorderWidth: 1,
                contentCornerRadius: 16,
                contentPadding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                contentSpacing: 6
            )
        }
    }
}

public struct DefaultMenuStyle: Sendable {
    public init() {}
}

public struct ButtonMenuStyle: Sendable {
    public init() {}
}

public struct BorderedButtonMenuStyle: Sendable {
    public init() {}
}

public struct BorderlessButtonMenuStyle: Sendable {
    public init() {}
}

public struct ListStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case plain
        case inset
        case grouped
        case insetGrouped
        case sidebar
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ListStyle(kind: .automatic)
    public static let plain = ListStyle(kind: .plain)
    public static let inset = ListStyle(kind: .inset)
    public static let grouped = ListStyle(kind: .grouped)
    public static let insetGrouped = ListStyle(kind: .insetGrouped)
    public static let sidebar = ListStyle(kind: .sidebar)

    var scrollViewStyle: ScrollViewStyle {
        switch kind {
        case .automatic, .insetGrouped:
            return ScrollViewStyle(
                spacing: 6,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .leading,
                backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.54),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 16,
                scrollStep: 44
            )
        case .plain:
            return ScrollViewStyle(
                spacing: 0,
                padding: .zero,
                alignment: .leading,
                backgroundColor: nil,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0,
                scrollStep: 44
            )
        case .inset:
            return ScrollViewStyle(
                spacing: 4,
                padding: EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10),
                alignment: .leading,
                backgroundColor: nil,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0,
                scrollStep: 44
            )
        case .grouped:
            return ScrollViewStyle(
                spacing: 8,
                padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10),
                alignment: .leading,
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.62),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.06),
                borderWidth: 1,
                cornerRadius: 18,
                scrollStep: 44
            )
        case .sidebar:
            return ScrollViewStyle(
                spacing: 6,
                padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                alignment: .leading,
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.38),
                borderColor: Color(red: 0.98, green: 0.99, blue: 1.0, alpha: 0.06),
                borderWidth: 1,
                cornerRadius: 20,
                scrollStep: 40,
                indicatorThickness: 4
            )
        }
    }
}

public struct DefaultListStyle: Sendable {
    public init() {}
}

public struct PlainListStyle: Sendable {
    public init() {}
}

public struct InsetListStyle: Sendable {
    public init() {}
}

public struct GroupedListStyle: Sendable {
    public init() {}
}

public struct InsetGroupedListStyle: Sendable {
    public init() {}
}

public struct SidebarListStyle: Sendable {
    public init() {}
}

public struct LabelStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case titleAndIcon
        case titleOnly
        case iconOnly
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = LabelStyle(kind: .automatic)
    public static let titleAndIcon = LabelStyle(kind: .titleAndIcon)
    public static let titleOnly = LabelStyle(kind: .titleOnly)
    public static let iconOnly = LabelStyle(kind: .iconOnly)

    var showsTitle: Bool {
        switch kind {
        case .automatic, .titleAndIcon, .titleOnly:
            return true
        case .iconOnly:
            return false
        }
    }

    var showsIcon: Bool {
        switch kind {
        case .automatic, .titleAndIcon, .iconOnly:
            return true
        case .titleOnly:
            return false
        }
    }
}

public struct DefaultLabelStyle: Sendable {
    public init() {}
}

public struct TitleAndIconLabelStyle: Sendable {
    public init() {}
}

public struct TitleOnlyLabelStyle: Sendable {
    public init() {}
}

public struct IconOnlyLabelStyle: Sendable {
    public init() {}
}

enum ToggleControlKind: Sendable {
    case switchControl
    case checkbox
    case button
}

public struct ToggleStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case switchControl
        case checkbox
        case button
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ToggleStyle(kind: .automatic)
    public static let `switch` = ToggleStyle(kind: .switchControl)
    public static let checkbox = ToggleStyle(kind: .checkbox)
    public static let button = ToggleStyle(kind: .button)

    var controlKind: ToggleControlKind {
        switch kind {
        case .automatic, .switchControl:
            return .switchControl
        case .checkbox:
            return .checkbox
        case .button:
            return .button
        }
    }
}

public struct DefaultToggleStyle: Sendable {
    public init() {}
}

public struct SwitchToggleStyle: Sendable {
    public init() {}
}

public struct CheckboxToggleStyle: Sendable {
    public init() {}
}

public struct ButtonToggleStyle: Sendable {
    public init() {}
}

enum PickerControlKind: Sendable {
    case menu
    case segmented
    case radioGroup
}

public struct PickerStyle: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case automatic
        case menu
        case segmented
        case radioGroup
        case inline
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PickerStyle(kind: .automatic)
    public static let menu = PickerStyle(kind: .menu)
    public static let segmented = PickerStyle(kind: .segmented)
    public static let radioGroup = PickerStyle(kind: .radioGroup)
    public static let inline = PickerStyle(kind: .inline)

    var controlKind: PickerControlKind {
        switch kind {
        case .automatic, .menu:
            return .menu
        case .segmented:
            return .segmented
        case .radioGroup, .inline:
            return .radioGroup
        }
    }
}

public struct DefaultPickerStyle: Sendable {
    public init() {}
}

public struct MenuPickerStyle: Sendable {
    public init() {}
}

public struct SegmentedPickerStyle: Sendable {
    public init() {}
}

public struct RadioGroupPickerStyle: Sendable {
    public init() {}
}

public struct InlinePickerStyle: Sendable {
    public init() {}
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
    var selectionTag: AnyHashable?

    var body: Never {
        fatalError("ModifiedView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let inner = transform(content, context)
        guard id != nil || selectionTag != nil else {
            return inner
        }

        // Wrap the inner component so the resulting node carries metadata.
        let capturedID = id
        let capturedSelectionTag = selectionTag
        return Component { runtime in
            let node = inner.makeNode(runtime: runtime)
            if let capturedID {
                node.nodeTag = capturedID
            }
            node.selectionTag = capturedSelectionTag
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

private enum ShapeFillStyle {
    case color(Color)
    case gradient(LinearGradient)
}

@MainActor
private struct ShapeFillView<S: Shape>: View {
    typealias Body = Never

    let shape: S
    let fill: ShapeFillStyle

    var body: Never {
        fatalError("ShapeFillView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let cornerRadius = clipCornerRadius(for: shape)
        return Component { _ in
            switch fill {
            case .color(let color):
                return Controls.panel(
                    backgroundColor: color,
                    cornerRadius: cornerRadius,
                    clipsToBounds: cornerRadius > 0,
                    isHitTestVisible: false
                )
            case .gradient(let gradient):
                return Controls.panel(
                    backgroundGradient: gradient,
                    cornerRadius: cornerRadius,
                    clipsToBounds: cornerRadius > 0,
                    isHitTestVisible: false
                )
            }
        }
    }
}

@MainActor
private struct ShapeStrokeView<S: Shape>: View {
    typealias Body = Never

    let shape: S
    let color: Color
    let lineWidth: Double

    var body: Never {
        fatalError("ShapeStrokeView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        let cornerRadius = clipCornerRadius(for: shape)
        return Component { _ in
            Controls.panel(
                borderColor: color,
                borderWidth: max(0, lineWidth),
                cornerRadius: cornerRadius,
                clipsToBounds: cornerRadius > 0,
                isHitTestVisible: false
            )
        }
    }
}

extension Rectangle: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Rectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ShapeFillView(shape: self, fill: .color(.white)).makeComponent(context: context)
    }
}

extension Circle: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Circle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ShapeFillView(shape: self, fill: .color(.white)).makeComponent(context: context)
    }
}

extension Ellipse: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Ellipse has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ShapeFillView(shape: self, fill: .color(.white)).makeComponent(context: context)
    }
}

extension Capsule: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("Capsule has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ShapeFillView(shape: self, fill: .color(.white)).makeComponent(context: context)
    }
}

extension RoundedRectangle: View {
    public typealias Body = Never

    public var body: Never {
        fatalError("RoundedRectangle has no body")
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        ShapeFillView(shape: self, fill: .color(.white)).makeComponent(context: context)
    }
}

public extension Shape {
    func fill(_ color: Color) -> some View {
        ShapeFillView(shape: self, fill: .color(color))
    }

    func fill(_ gradient: LinearGradient) -> some View {
        ShapeFillView(shape: self, fill: .gradient(gradient))
    }

    func stroke(_ color: Color, lineWidth: Double = 1) -> some View {
        ShapeStrokeView(shape: self, color: color, lineWidth: lineWidth)
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

@MainActor
private func updateTextCase(in node: ViewNode, _ textCase: Text.Case?) {
    guard let textCase else {
        return
    }

    if let text = node.text {
        var style = node.textStyle
        if let spans = style.spans, !spans.isEmpty {
            let transformed = transformedTextSpans(spans, textCase: textCase)
            node.text = transformed.text
            style.spans = transformed.spans
            node.textStyle = style
        } else {
            node.text = transformedText(text, textCase: textCase)
        }
    }

    for child in node.children {
        updateTextCase(in: child, textCase)
    }
}

func transformedText(_ text: String, textCase: Text.Case) -> String {
    switch textCase {
    case .uppercase:
        return text.uppercased()
    case .lowercase:
        return text.lowercased()
    }
}

private func transformedTextSpans(_ spans: [TextSpan], textCase: Text.Case) -> (text: String, spans: [TextSpan]) {
    let segments = spans.map { span in
        (text: transformedText(span.text, textCase: textCase), style: span.style)
    }
    let text = segments.map(\.text).joined()
    var cursor = text.startIndex
    var transformedSpans: [TextSpan] = []
    transformedSpans.reserveCapacity(segments.count)

    for segment in segments {
        guard !segment.text.isEmpty else {
            continue
        }
        let nextCursor = text.index(cursor, offsetBy: segment.text.count)
        transformedSpans.append(TextSpan(text: segment.text, style: segment.style, range: cursor..<nextCursor))
        cursor = nextCursor
    }

    return (text, transformedSpans)
}

@MainActor
private func suppressInteraction(in node: ViewNode) {
    node.isHitTestVisible = false
    node.isFocusable = false
    node.onPointerEnter = nil
    node.onPointerExit = nil
    node.onPointerDown = nil
    node.onPointerDownAt = nil
    node.onPointerUpInside = nil
    node.onPointerUpOutside = nil
    node.onFocusEnter = nil
    node.onFocusExit = nil
    node.onKeyDown = nil
    node.onTextInput = nil
    node.onActivate = nil
    node.onDragStart = nil
    node.onDragChange = nil
    node.onDragEnd = nil
    node.onDragStartAt = nil
    node.onDragChangeAt = nil
    node.onDragEndAt = nil

    for child in node.children {
        suppressInteraction(in: child)
    }
}

@MainActor
private func updateScrollIndicatorVisibility(in node: ViewNode, visibility: ScrollIndicatorVisibility) {
    if node.scrollAxis != nil {
        switch visibility {
        case .automatic:
            break
        case .visible:
            node.showsScrollIndicator = true
        case .hidden:
            node.showsScrollIndicator = false
        }
    }

    for child in node.children {
        updateScrollIndicatorVisibility(in: child, visibility: visibility)
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

extension Font.TextStyle {
    var font: Font {
        switch self {
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

extension Text.TruncationMode {
    var lineBreakMode: TextLineBreakMode {
        switch self {
        case .head:
            return .truncateHead
        case .tail:
            return .truncateTail
        case .middle:
            return .truncateMiddle
        }
    }
}

public extension SwiftWindowsCore.Color {
    init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.init(red: Float(red), green: Float(green), blue: Float(blue), alpha: Float(opacity))
    }

    init(white: Double, opacity: Double = 1.0) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }

    init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1.0) {
        let clampedSaturation = min(max(saturation, 0), 1)
        let clampedBrightness = min(max(brightness, 0), 1)
        let normalizedHue = hue - floor(hue)

        guard clampedSaturation > 0 else {
            self.init(white: clampedBrightness, opacity: opacity)
            return
        }

        let scaledHue = normalizedHue * 6
        let sector = Int(floor(scaledHue))
        let fraction = scaledHue - Double(sector)
        let p = clampedBrightness * (1 - clampedSaturation)
        let q = clampedBrightness * (1 - clampedSaturation * fraction)
        let t = clampedBrightness * (1 - clampedSaturation * (1 - fraction))

        switch sector {
        case 0:
            self.init(red: clampedBrightness, green: t, blue: p, opacity: opacity)
        case 1:
            self.init(red: q, green: clampedBrightness, blue: p, opacity: opacity)
        case 2:
            self.init(red: p, green: clampedBrightness, blue: t, opacity: opacity)
        case 3:
            self.init(red: p, green: q, blue: clampedBrightness, opacity: opacity)
        case 4:
            self.init(red: t, green: p, blue: clampedBrightness, opacity: opacity)
        default:
            self.init(red: clampedBrightness, green: p, blue: q, opacity: opacity)
        }
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

private func resolvedPaddingLength(_ length: Double?) -> Double {
    length ?? 16
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

    if shape is Circle || shape is Ellipse || shape is Capsule {
        return maximumCapsuleCornerRadius
    }

    return 0
}

private let maximumCapsuleCornerRadius = 1_000_000.0

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

            let measuredLayerSize = layerNode.intrinsicContentSize()
            let layerSize = Size(
                width: measuredLayerSize.width > 0 ? measuredLayerSize.width : bounds.size.width,
                height: measuredLayerSize.height > 0 ? measuredLayerSize.height : bounds.size.height
            )
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

@MainActor
private func materialComponent(_ material: Material) -> Component {
    Component { _ in
        let node = Controls.panel(
            backgroundColor: material.backgroundColor,
            borderColor: material.borderColor,
            borderWidth: max(0, material.borderWidth),
            shadowColor: material.shadowColor,
            shadowOffset: material.shadowOffset,
            shadowSpread: max(0, material.shadowSpread),
            cornerRadius: max(0, material.cornerRadius),
            clipsToBounds: true,
            isHitTestVisible: false
        )
        node.blurRadius = max(0, material.blurRadius)
        return node
    }
}

@MainActor
private func alertComponent(
    base: Component,
    title: String,
    isPresented: Binding<Bool>,
    actions actionViews: [AnyView],
    message messageViews: [AnyView],
    context: ViewBuildContext
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        guard isPresented.wrappedValue else {
            return baseNode
        }

        let titleNode = Text(title)
            .font(.system(size: 2.2, weight: .semibold))
            .foregroundColor(Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .makeComponent(context: context)
            .makeNode(runtime: runtime)

        let messageNode: ViewNode? = messageViews.isEmpty ? nil : composeComponent(
            from: messageViews,
            context: context,
            fallbackLayout: .stack(.vertical(spacing: 6, alignment: .stretch))
        )
        .makeNode(runtime: runtime)

        let actions = actionViews.isEmpty
            ? [
                AnyView(
                    Button("OK") {
                        isPresented.wrappedValue = false
                        isPresented.invalidateContextIfNeeded(context)
                    }
                    .buttonStyle(.borderedProminent)
                )
            ]
            : actionViews
        let actionNodes = actions.map { actionView -> ViewNode in
            let node = actionView.makeComponent(context: context).makeNode(runtime: runtime)
            installAlertDismissal(on: node, isPresented: isPresented, context: context)
            return node
        }
        let actionsRow = Controls.stackPanel(
            stackLayout: .horizontal(spacing: 10, alignment: .center, mainAlignment: .end),
            isHitTestVisible: false,
            children: actionNodes
        )

        var cardChildren = [titleNode]
        if let messageNode {
            cardChildren.append(messageNode)
        }
        cardChildren.append(actionsRow)

        let scrim = Controls.panel(
            backgroundColor: Color(red: 0.01, green: 0.02, blue: 0.04, alpha: 0.46),
            isHitTestVisible: true
        )
        let card = Controls.stackPanel(
            preferredSize: Size(width: 340, height: 0),
            backgroundColor: Color(red: 0.11, green: 0.15, blue: 0.22, alpha: 0.94),
            borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.18),
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.32),
            shadowOffset: Point(x: 0, y: 20),
            shadowSpread: 26,
            cornerRadius: 26,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 16,
                padding: EdgeInsets(top: 24, leading: 24, bottom: 22, trailing: 24),
                alignment: .stretch
            ),
            isHitTestVisible: true,
            children: cardChildren
        )
        card.blurRadius = 18

        let overlayRoot = Controls.panel(
            preferredSize: context.canvasSize,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, scrim, card]
        )

        overlayRoot.onLayout = { bounds in
            let fullFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != fullFrame {
                baseNode.frame = fullFrame
            }
            if scrim.frame != fullFrame {
                scrim.frame = fullFrame
            }

            let horizontalMargin = min(28.0, max(12.0, bounds.size.width * 0.06))
            let cardWidth = min(380.0, max(240.0, bounds.size.width - horizontalMargin * 2))
            let preferredCardSize = Size(width: cardWidth, height: 0)
            if card.preferredSize != preferredCardSize {
                card.preferredSize = preferredCardSize
            }

            let measuredCardSize = card.intrinsicContentSize()
            let cardSize = Size(
                width: cardWidth,
                height: min(max(0, bounds.size.height - 32), measuredCardSize.height)
            )
            let cardFrame = Rect(
                origin: Alignment.center.frameOrigin(for: cardSize, in: bounds.size),
                size: cardSize
            )
            if card.frame != cardFrame {
                card.frame = cardFrame
            }
        }

        return overlayRoot
    }
}

@MainActor
private func installAlertDismissal(
    on node: ViewNode,
    isPresented: Binding<Bool>,
    context: ViewBuildContext
) {
    if let action = node.onActivate {
        node.onActivate = {
            action()
            isPresented.wrappedValue = false
            isPresented.invalidateContextIfNeeded(context)
        }
    } else if let pointerUpInside = node.onPointerUpInside {
        node.onPointerUpInside = {
            pointerUpInside()
            isPresented.wrappedValue = false
            isPresented.invalidateContextIfNeeded(context)
        }
    }

    for child in node.children {
        installAlertDismissal(on: child, isPresented: isPresented, context: context)
    }
}

@MainActor
private func sheetComponent(
    base: Component,
    isPresented: Binding<Bool>,
    onDismiss: (@MainActor () -> Void)?,
    content sheetViews: [AnyView],
    context: ViewBuildContext
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        guard isPresented.wrappedValue else {
            return baseNode
        }

        let sheetContext = context.withContainerAxis(.vertical)
        let sheetContent = composeComponent(
            from: sheetViews,
            context: sheetContext,
            fallbackLayout: .stack(.vertical(spacing: 12, alignment: .stretch))
        )
        .makeNode(runtime: runtime)
        let grabber = Controls.panel(
            preferredSize: Size(width: 46, height: 5),
            backgroundColor: Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 0.36),
            cornerRadius: 3,
            isHitTestVisible: false
        )
        let grabberRow = Controls.stackPanel(
            stackLayout: .horizontal(spacing: 0, alignment: .center, mainAlignment: .center),
            isHitTestVisible: false,
            children: [grabber]
        )
        let scrim = Controls.panel(
            backgroundColor: Color(red: 0.01, green: 0.02, blue: 0.04, alpha: 0.38),
            isHitTestVisible: true
        )
        let sheetPanel = Controls.stackPanel(
            preferredSize: Size(width: 520, height: 0),
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.21, alpha: 0.94),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.34),
            shadowOffset: Point(x: 0, y: 24),
            shadowSpread: 28,
            cornerRadius: 30,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 18,
                padding: EdgeInsets(top: 14, leading: 22, bottom: 22, trailing: 22),
                alignment: .stretch
            ),
            isHitTestVisible: true,
            children: [grabberRow, sheetContent]
        )
        sheetPanel.blurRadius = 20

        scrim.onPointerUpInside = {
            isPresented.wrappedValue = false
            onDismiss?()
            isPresented.invalidateContextIfNeeded(context)
        }

        let overlayRoot = Controls.panel(
            preferredSize: context.canvasSize,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, scrim, sheetPanel]
        )

        overlayRoot.onLayout = { bounds in
            let fullFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != fullFrame {
                baseNode.frame = fullFrame
            }
            if scrim.frame != fullFrame {
                scrim.frame = fullFrame
            }

            let horizontalMargin = min(36.0, max(12.0, bounds.size.width * 0.06))
            let sheetWidth = min(560.0, max(260.0, bounds.size.width - horizontalMargin * 2))
            let preferredSheetSize = Size(width: sheetWidth, height: 0)
            if sheetPanel.preferredSize != preferredSheetSize {
                sheetPanel.preferredSize = preferredSheetSize
            }

            let measuredSheetSize = sheetPanel.intrinsicContentSize()
            let maxSheetHeight = max(0, bounds.size.height - 32)
            let sheetSize = Size(width: sheetWidth, height: min(maxSheetHeight, measuredSheetSize.height))
            let bottomInset = min(28.0, max(12.0, bounds.size.height * 0.05))
            let sheetFrame = Rect(
                x: max(0, (bounds.size.width - sheetSize.width) * 0.5),
                y: max(0, bounds.size.height - sheetSize.height - bottomInset),
                width: sheetSize.width,
                height: sheetSize.height
            )
            if sheetPanel.frame != sheetFrame {
                sheetPanel.frame = sheetFrame
            }
        }

        return overlayRoot
    }
}

@MainActor
private func popoverComponent(
    base: Component,
    isPresented: Binding<Bool>,
    attachmentAnchor: PopoverAttachmentAnchor,
    arrowEdge: Edge,
    content popoverViews: [AnyView],
    context: ViewBuildContext
) -> Component {
    Component { runtime in
        _ = attachmentAnchor

        let baseNode = base.makeNode(runtime: runtime)
        guard isPresented.wrappedValue else {
            return baseNode
        }

        let popoverContext = context.withContainerAxis(.vertical)
        let popoverContent = composeComponent(
            from: popoverViews,
            context: popoverContext,
            fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
        )
        .makeNode(runtime: runtime)
        let dismissLayer = Controls.panel(
            backgroundColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.01),
            isHitTestVisible: true
        )
        let popoverSurfaceColor = Color(red: 0.11, green: 0.15, blue: 0.22, alpha: 0.95)
        let popoverBorderColor = Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18)
        let arrowSize = popoverArrowSize(for: arrowEdge)
        let arrow = Controls.path(
            popoverArrowPath(for: arrowEdge, size: arrowSize),
            preferredSize: arrowSize,
            fillColor: popoverSurfaceColor,
            strokeColor: popoverBorderColor,
            strokeStyle: StrokeStyle(lineWidth: 1, lineJoin: .round),
            isHitTestVisible: false
        )
        let card = Controls.stackPanel(
            preferredSize: Size(width: 300, height: 0),
            backgroundColor: popoverSurfaceColor,
            borderColor: popoverBorderColor,
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.30),
            shadowOffset: Point(x: 0, y: 16),
            shadowSpread: 20,
            cornerRadius: 20,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 10,
                padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
                alignment: .stretch
            ),
            isHitTestVisible: true,
            children: [popoverContent]
        )
        card.blurRadius = 16

        dismissLayer.onPointerUpInside = {
            isPresented.wrappedValue = false
            isPresented.invalidateContextIfNeeded(context)
        }

        let overlayRoot = Controls.panel(
            preferredSize: context.canvasSize,
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, dismissLayer, arrow, card]
        )

        overlayRoot.onLayout = { bounds in
            let fullFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != fullFrame {
                baseNode.frame = fullFrame
            }
            if dismissLayer.frame != fullFrame {
                dismissLayer.frame = fullFrame
            }

            let outerInset = min(24.0, max(10.0, min(bounds.size.width, bounds.size.height) * 0.06))
            let popoverInset = outerInset + popoverArrowDepth(for: arrowEdge, size: arrowSize)
            let availablePopoverWidth = max(0, bounds.size.width - popoverInset * 2)
            let popoverWidth = min(340.0, availablePopoverWidth)
            let preferredPopoverSize = Size(width: popoverWidth, height: 0)
            if card.preferredSize != preferredPopoverSize {
                card.preferredSize = preferredPopoverSize
            }

            let measuredSize = card.intrinsicContentSize()
            let cardSize = Size(
                width: popoverWidth,
                height: min(max(0, bounds.size.height - popoverInset * 2), measuredSize.height)
            )
            let cardFrame = popoverFrame(
                in: bounds.size,
                cardSize: cardSize,
                arrowEdge: arrowEdge,
                inset: popoverInset
            )
            if card.frame != cardFrame {
                card.frame = cardFrame
            }

            let arrowFrame = popoverArrowFrame(cardFrame: cardFrame, arrowEdge: arrowEdge, arrowSize: arrowSize)
            if arrow.frame != arrowFrame {
                arrow.frame = arrowFrame
            }
        }

        return overlayRoot
    }
}

private func popoverArrowSize(for edge: Edge) -> Size {
    switch edge {
    case .top, .bottom:
        return Size(width: 24, height: 11)
    case .leading, .trailing:
        return Size(width: 11, height: 24)
    }
}

private func popoverArrowDepth(for edge: Edge, size: Size) -> Double {
    switch edge {
    case .top, .bottom:
        return size.height
    case .leading, .trailing:
        return size.width
    }
}

private func popoverArrowPath(for edge: Edge, size: Size) -> RenderPath {
    var path = RenderPath()
    switch edge {
    case .top:
        path.move(to: Point(x: size.width * 0.5, y: 0))
        path.addLine(to: Point(x: size.width, y: size.height))
        path.addLine(to: Point(x: 0, y: size.height))
    case .bottom:
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: size.width, y: 0))
        path.addLine(to: Point(x: size.width * 0.5, y: size.height))
    case .leading:
        path.move(to: Point(x: 0, y: size.height * 0.5))
        path.addLine(to: Point(x: size.width, y: 0))
        path.addLine(to: Point(x: size.width, y: size.height))
    case .trailing:
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: size.width, y: size.height * 0.5))
        path.addLine(to: Point(x: 0, y: size.height))
    }
    path.close()
    return path
}

private func popoverArrowFrame(cardFrame: Rect, arrowEdge: Edge, arrowSize: Size) -> Rect {
    let horizontalCenter = cardFrame.origin.x + (cardFrame.size.width - arrowSize.width) * 0.5
    let verticalCenter = cardFrame.origin.y + (cardFrame.size.height - arrowSize.height) * 0.5
    let seamOverlap = 1.0

    switch arrowEdge {
    case .top:
        return Rect(x: horizontalCenter, y: cardFrame.origin.y - arrowSize.height + seamOverlap, width: arrowSize.width, height: arrowSize.height)
    case .bottom:
        return Rect(x: horizontalCenter, y: cardFrame.maxY - seamOverlap, width: arrowSize.width, height: arrowSize.height)
    case .leading:
        return Rect(x: cardFrame.origin.x - arrowSize.width + seamOverlap, y: verticalCenter, width: arrowSize.width, height: arrowSize.height)
    case .trailing:
        return Rect(x: cardFrame.maxX - seamOverlap, y: verticalCenter, width: arrowSize.width, height: arrowSize.height)
    }
}

private func popoverFrame(in bounds: Size, cardSize: Size, arrowEdge: Edge, inset: Double) -> Rect {
    let centeredX = max(inset, (bounds.width - cardSize.width) * 0.5)
    let centeredY = max(inset, (bounds.height - cardSize.height) * 0.5)
    let trailingX = max(inset, bounds.width - cardSize.width - inset)
    let bottomY = max(inset, bounds.height - cardSize.height - inset)

    switch arrowEdge {
    case .top:
        return Rect(x: centeredX, y: inset, width: cardSize.width, height: cardSize.height)
    case .bottom:
        return Rect(x: centeredX, y: bottomY, width: cardSize.width, height: cardSize.height)
    case .leading:
        return Rect(x: inset, y: centeredY, width: cardSize.width, height: cardSize.height)
    case .trailing:
        return Rect(x: trailingX, y: centeredY, width: cardSize.width, height: cardSize.height)
    }
}

private func finiteFrameExtent(_ extent: Double?) -> Double? {
    guard let extent, extent.isFinite else {
        return nil
    }

    return extent
}

private func frameConstraintSize(width: Double?, height: Double?, unconstrainedFallback: Double = 0) -> Size? {
    guard width != nil || height != nil else {
        return nil
    }

    return Size(width: width ?? unconstrainedFallback, height: height ?? unconstrainedFallback)
}

private func framePreferredSize(
    idealWidth: Double?,
    idealHeight: Double?,
    minWidth: Double?,
    minHeight: Double?,
    maxWidth: Double?,
    maxHeight: Double?
) -> Size? {
    let preferredWidth = idealWidth ?? fixedFrameExtent(min: minWidth, max: maxWidth)
    let preferredHeight = idealHeight ?? fixedFrameExtent(min: minHeight, max: maxHeight)
    return frameConstraintSize(width: preferredWidth, height: preferredHeight)
}

private func fixedFrameExtent(min minimum: Double?, max maximum: Double?) -> Double? {
    guard let minimum, let maximum, minimum == maximum, maximum.isFinite else {
        return nil
    }

    return minimum
}

public extension View {
    func foregroundColor(_ color: Color?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                if let color {
                    updateTextStyles(in: node) { style in
                        style.color = color
                    }
                }
                return node
            }
        }
    }

    func foregroundStyle(_ color: Color?) -> some View {
        foregroundColor(color)
    }

    func tint(_ color: Color?) -> some View {
        ModifiedView(content: self) { content, context in
            let childContext = color.map { context.withTint($0) } ?? context
            return content.makeComponent(context: childContext)
        }
    }

    func accentColor(_ color: Color?) -> some View {
        tint(color)
    }

    func controlSize(_ size: ControlSize) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withControlSize(size))
        }
    }

    func textFieldStyle(_ style: TextFieldStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTextFieldStyle(style))
        }
    }

    func textFieldStyle(_ style: DefaultTextFieldStyle) -> some View {
        textFieldStyle(.automatic)
    }

    func textFieldStyle(_ style: RoundedBorderTextFieldStyle) -> some View {
        textFieldStyle(.roundedBorder)
    }

    func textFieldStyle(_ style: PlainTextFieldStyle) -> some View {
        textFieldStyle(.plain)
    }

    func progressViewStyle(_ style: ProgressViewStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withProgressViewStyle(style))
        }
    }

    func progressViewStyle(_ style: DefaultProgressViewStyle) -> some View {
        progressViewStyle(.automatic)
    }

    func progressViewStyle(_ style: LinearProgressViewStyle) -> some View {
        progressViewStyle(.linear)
    }

    func progressViewStyle(_ style: CircularProgressViewStyle) -> some View {
        progressViewStyle(.circular)
    }

    func gaugeStyle(_ style: GaugeStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withGaugeStyle(style))
        }
    }

    func gaugeStyle(_ style: DefaultGaugeStyle) -> some View {
        gaugeStyle(.automatic)
    }

    func gaugeStyle(_ style: LinearGaugeStyle) -> some View {
        gaugeStyle(.linear)
    }

    func gaugeStyle(_ style: AccessoryLinearGaugeStyle) -> some View {
        gaugeStyle(.accessoryLinear)
    }

    func gaugeStyle(_ style: AccessoryLinearCapacityGaugeStyle) -> some View {
        gaugeStyle(.accessoryLinearCapacity)
    }

    func gaugeStyle(_ style: CircularGaugeStyle) -> some View {
        gaugeStyle(.circular)
    }

    func gaugeStyle(_ style: AccessoryCircularGaugeStyle) -> some View {
        gaugeStyle(.accessoryCircular)
    }

    func gaugeStyle(_ style: AccessoryCircularCapacityGaugeStyle) -> some View {
        gaugeStyle(.accessoryCircularCapacity)
    }

    func datePickerStyle(_ style: DatePickerStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withDatePickerStyle(style))
        }
    }

    func datePickerStyle(_ style: DefaultDatePickerStyle) -> some View {
        datePickerStyle(.automatic)
    }

    func datePickerStyle(_ style: CompactDatePickerStyle) -> some View {
        datePickerStyle(.compact)
    }

    func datePickerStyle(_ style: FieldDatePickerStyle) -> some View {
        datePickerStyle(.field)
    }

    func datePickerStyle(_ style: StepperFieldDatePickerStyle) -> some View {
        datePickerStyle(.stepperField)
    }

    func datePickerStyle(_ style: GraphicalDatePickerStyle) -> some View {
        datePickerStyle(.graphical)
    }

    func datePickerStyle(_ style: WheelDatePickerStyle) -> some View {
        datePickerStyle(.wheel)
    }

    func menuStyle(_ style: MenuStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withMenuStyle(style))
        }
    }

    func menuStyle(_ style: DefaultMenuStyle) -> some View {
        menuStyle(.automatic)
    }

    func menuStyle(_ style: ButtonMenuStyle) -> some View {
        menuStyle(.button)
    }

    func menuStyle(_ style: BorderedButtonMenuStyle) -> some View {
        menuStyle(.borderedButton)
    }

    func menuStyle(_ style: BorderlessButtonMenuStyle) -> some View {
        menuStyle(.borderlessButton)
    }

    func controlGroupStyle(_ style: ControlGroupStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withControlGroupStyle(style))
        }
    }

    func controlGroupStyle(_ style: AutomaticControlGroupStyle) -> some View {
        controlGroupStyle(.automatic)
    }

    func controlGroupStyle(_ style: NavigationControlGroupStyle) -> some View {
        controlGroupStyle(.navigation)
    }

    func controlGroupStyle(_ style: PaletteControlGroupStyle) -> some View {
        controlGroupStyle(.palette)
    }

    func controlGroupStyle(_ style: MenuControlGroupStyle) -> some View {
        controlGroupStyle(.menu)
    }

    func controlGroupStyle(_ style: CompactMenuControlGroupStyle) -> some View {
        controlGroupStyle(.compactMenu)
    }

    func buttonStyle(_ style: ButtonStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withButtonStyle(style))
        }
    }

    func listStyle(_ style: ListStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withListStyle(style))
        }
    }

    func listStyle(_ style: DefaultListStyle) -> some View {
        listStyle(.automatic)
    }

    func listStyle(_ style: PlainListStyle) -> some View {
        listStyle(.plain)
    }

    func listStyle(_ style: InsetListStyle) -> some View {
        listStyle(.inset)
    }

    func listStyle(_ style: GroupedListStyle) -> some View {
        listStyle(.grouped)
    }

    func listStyle(_ style: InsetGroupedListStyle) -> some View {
        listStyle(.insetGrouped)
    }

    func listStyle(_ style: SidebarListStyle) -> some View {
        listStyle(.sidebar)
    }

    func labelStyle(_ style: LabelStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withLabelStyle(style))
        }
    }

    func labelStyle(_ style: DefaultLabelStyle) -> some View {
        labelStyle(.automatic)
    }

    func labelStyle(_ style: TitleAndIconLabelStyle) -> some View {
        labelStyle(.titleAndIcon)
    }

    func labelStyle(_ style: TitleOnlyLabelStyle) -> some View {
        labelStyle(.titleOnly)
    }

    func labelStyle(_ style: IconOnlyLabelStyle) -> some View {
        labelStyle(.iconOnly)
    }

    func toggleStyle(_ style: ToggleStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withToggleStyle(style))
        }
    }

    func toggleStyle(_ style: DefaultToggleStyle) -> some View {
        toggleStyle(.automatic)
    }

    func toggleStyle(_ style: SwitchToggleStyle) -> some View {
        toggleStyle(.switch)
    }

    func toggleStyle(_ style: CheckboxToggleStyle) -> some View {
        toggleStyle(.checkbox)
    }

    func toggleStyle(_ style: ButtonToggleStyle) -> some View {
        toggleStyle(.button)
    }

    func pickerStyle(_ style: PickerStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withPickerStyle(style))
        }
    }

    func pickerStyle(_ style: DefaultPickerStyle) -> some View {
        pickerStyle(.automatic)
    }

    func pickerStyle(_ style: MenuPickerStyle) -> some View {
        pickerStyle(.menu)
    }

    func pickerStyle(_ style: SegmentedPickerStyle) -> some View {
        pickerStyle(.segmented)
    }

    func pickerStyle(_ style: RadioGroupPickerStyle) -> some View {
        pickerStyle(.radioGroup)
    }

    func pickerStyle(_ style: InlinePickerStyle) -> some View {
        pickerStyle(.inline)
    }

    func scrollIndicators(_ visibility: ScrollIndicatorVisibility) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateScrollIndicatorVisibility(in: node, visibility: visibility)
                return node
            }
        }
    }

    func onSubmit(_ action: @escaping @MainActor () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withSubmitAction(action))
        }
    }

    func font(_ font: Font?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                if let font {
                    updateTextStyles(in: node) { style in
                        let preservesIconFont = style.fontFamily == "Segoe Fluent Icons"
                        style.scale = font.resolvedScale
                        style.weight = font.weight.textWeight
                        if !preservesIconFont {
                            style.fontFamily = font.resolvedFamily
                        }
                    }
                }
                return node
            }
        }
    }

    func fontDesign(_ design: Font.Design?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                if let design {
                    let family = Font(size: 1, design: design).resolvedFamily
                    updateTextStyles(in: node) { style in
                        if style.fontFamily != "Segoe Fluent Icons" {
                            style.fontFamily = family
                        }
                    }
                }
                return node
            }
        }
    }

    func textCase(_ textCase: Text.Case?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextCase(in: node, textCase)
                return node
            }
        }
    }

    func kerning(_ value: CGFloat) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.letterSpacing = value
                }
                return node
            }
        }
    }

    func tracking(_ value: CGFloat) -> some View {
        kerning(value)
    }

    func lineSpacing(_ value: CGFloat) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.lineSpacing = value
                }
                return node
            }
        }
    }

    func fontWeight(_ weight: Font.Weight?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                if let weight {
                    updateTextStyles(in: node) { style in
                        style.weight = weight.textWeight
                    }
                }
                return node
            }
        }
    }

    func bold() -> some View {
        fontWeight(.bold)
    }

    func italic() -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.italic = true
                }
                return node
            }
        }
    }

    func monospaced() -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    if style.fontFamily != "Segoe Fluent Icons" {
                        style.fontFamily = "Cascadia Mono"
                    }
                }
                return node
            }
        }
    }

    func underline(_ active: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.underline = active
                }
                return node
            }
        }
    }

    func strikethrough(_ active: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.strikethrough = active
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

    func truncationMode(_ mode: Text.TruncationMode) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                updateTextStyles(in: node) { style in
                    style.lineBreakMode = mode.lineBreakMode
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

    func frame(
        minWidth: Double? = nil,
        idealWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        idealHeight: Double? = nil,
        maxHeight: Double? = nil,
        alignment: Alignment = .center
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            let fillsWidth = maxWidth?.isInfinite == true
            let fillsHeight = maxHeight?.isInfinite == true
            let expandsAlongContainerAxis = (
                (fillsWidth && context.containerAxis == .horizontal) ||
                (fillsHeight && context.containerAxis == .vertical)
            )
            let preferredSize = framePreferredSize(
                idealWidth: idealWidth,
                idealHeight: idealHeight,
                minWidth: minWidth,
                minHeight: minHeight,
                maxWidth: maxWidth,
                maxHeight: maxHeight
            )
            let minimumSize = frameConstraintSize(width: minWidth, height: minHeight)
            let maximumSize = frameConstraintSize(
                width: finiteFrameExtent(maxWidth),
                height: finiteFrameExtent(maxHeight),
                unconstrainedFallback: .infinity
            )

            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let node = Controls.stackPanel(
                    preferredSize: preferredSize,
                    layoutPriority: expandsAlongContainerAxis ? 1 : 0,
                    stackLayout: .vertical(
                        padding: .zero,
                        alignment: alignment.horizontal.stackAlignment,
                        mainAlignment: alignment.vertical.mainAlignment
                    ),
                    isHitTestVisible: false,
                    children: [childNode]
                )
                node.minimumSize = minimumSize
                node.maximumSize = maximumSize
                node.fillsAvailableWidth = fillsWidth
                node.fillsAvailableHeight = fillsHeight
                return node
            }
        }
    }

    func fixedSize(horizontal: Bool = true, vertical: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let intrinsicSize = childNode.intrinsicContentSize()
                let preferredSize = childNode.preferredSize ?? .zero
                var minimumSize = childNode.minimumSize ?? .zero
                if horizontal {
                    childNode.fixedSizeHorizontal = true
                    childNode.fillsAvailableWidth = false
                    minimumSize.width = max(minimumSize.width, intrinsicSize.width, preferredSize.width, childNode.frame.size.width)
                }
                if vertical {
                    childNode.fixedSizeVertical = true
                    childNode.fillsAvailableHeight = false
                    minimumSize.height = max(minimumSize.height, intrinsicSize.height, preferredSize.height, childNode.frame.size.height)
                }
                if horizontal || vertical {
                    childNode.minimumSize = minimumSize
                }
                return childNode
            }
        }
    }

    func padding(_ length: Double? = nil) -> some View {
        padding(EdgeInsets.all(resolvedPaddingLength(length)))
    }

    func padding(_ edges: Edge.Set, _ length: Double? = nil) -> some View {
        let resolvedLength = resolvedPaddingLength(length)
        return padding(
            EdgeInsets(
                top: edges.contains(.top) ? resolvedLength : 0,
                leading: edges.contains(.leading) ? resolvedLength : 0,
                bottom: edges.contains(.bottom) ? resolvedLength : 0,
                trailing: edges.contains(.trailing) ? resolvedLength : 0
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

    func background(_ material: Material) -> some View {
        ModifiedView(content: self) { baseContent, context in
            layeredComponent(
                base: baseContent.makeComponent(context: context),
                layer: materialComponent(material),
                alignment: .center,
                placement: .behind
            )
        }
    }

    func background<V: View>(_ background: V, alignment: Alignment = .center) -> some View {
        ModifiedView(content: self) { baseContent, context in
            layeredComponent(
                base: baseContent.makeComponent(context: context),
                layer: background.makeComponent(context: context),
                alignment: alignment,
                placement: .behind
            )
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

    func overlay(_ material: Material, alignment: Alignment = .center) -> some View {
        ModifiedView(content: self) { baseContent, context in
            layeredComponent(
                base: baseContent.makeComponent(context: context),
                layer: materialComponent(material),
                alignment: alignment,
                placement: .above
            )
        }
    }

    func overlay<V: View>(_ overlay: V, alignment: Alignment = .center) -> some View {
        ModifiedView(content: self) { baseContent, context in
            layeredComponent(
                base: baseContent.makeComponent(context: context),
                layer: overlay.makeComponent(context: context),
                alignment: alignment,
                placement: .above
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

    func alert(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> [AnyView] = { [] },
        @ViewBuilder message: () -> [AnyView] = { [] }
    ) -> some View {
        let actionViews = actions()
        let messageViews = message()

        return ModifiedView(content: self) { baseContent, context in
            alertComponent(
                base: baseContent.makeComponent(context: context),
                title: title,
                isPresented: isPresented,
                actions: actionViews,
                message: messageViews,
                context: context
            )
        }
    }

    func sheet(
        isPresented: Binding<Bool>,
        onDismiss: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: () -> [AnyView]
    ) -> some View {
        let sheetViews = content()

        return ModifiedView(content: self) { baseContent, context in
            sheetComponent(
                base: baseContent.makeComponent(context: context),
                isPresented: isPresented,
                onDismiss: onDismiss,
                content: sheetViews,
                context: context
            )
        }
    }

    func popover(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge = .top,
        @ViewBuilder content: () -> [AnyView]
    ) -> some View {
        let popoverViews = content()

        return ModifiedView(content: self) { baseContent, context in
            popoverComponent(
                base: baseContent.makeComponent(context: context),
                isPresented: isPresented,
                attachmentAnchor: attachmentAnchor,
                arrowEdge: arrowEdge,
                content: popoverViews,
                context: context
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

    func hidden() -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.opacity = 0
                suppressInteraction(in: childNode)
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
                childNode.onPointerDownAt = nil
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
                childNode.onDragStartAt = nil
                childNode.onDragChangeAt = nil
                childNode.onDragEndAt = nil
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
    func id<ID: Hashable>(_ identifier: ID) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.id = String(describing: identifier)
        return modified
    }

    /// Attach a SwiftUI-style selection tag. `Picker` uses the typed value to
    /// map declarative options into retained dropdown rows while the string
    /// tag remains available for retained-node reconciliation.
    func tag<Value: Hashable>(_ value: Value) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.id = String(describing: value)
        modified.selectionTag = AnyHashable(value)
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
