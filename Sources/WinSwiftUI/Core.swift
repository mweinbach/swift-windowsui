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
public typealias StrokeStyle = SwiftWindowsGraphics.StrokeStyle
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

public struct Animation: Sendable {
    public var duration: Double
    public var easing: AnimationEasing

    public init(duration: Double = 0.25, easing: AnimationEasing = .easeInOut) {
        self.duration = duration
        self.easing = easing
    }

    public static let `default` = Animation()
    public static let linear = Animation(easing: .linear)
    public static let easeIn = Animation(easing: .easeIn)
    public static let easeOut = Animation(easing: .easeOut)
    public static let easeInOut = Animation(easing: .easeInOut)

    public static func linear(duration: Double) -> Animation {
        Animation(duration: duration, easing: .linear)
    }

    public static func easeIn(duration: Double) -> Animation {
        Animation(duration: duration, easing: .easeIn)
    }

    public static func easeOut(duration: Double) -> Animation {
        Animation(duration: duration, easing: .easeOut)
    }

    public static func easeInOut(duration: Double) -> Animation {
        Animation(duration: duration, easing: .easeInOut)
    }
}

@discardableResult
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try body()
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

public struct NavigationPath: Equatable {
    private var elements: [AnyHashable]

    public init() {
        self.elements = []
    }

    public var count: Int {
        elements.count
    }

    public var isEmpty: Bool {
        elements.isEmpty
    }

    var anyElements: [AnyHashable] {
        elements
    }

    public mutating func append<Value: Hashable>(_ value: Value) {
        elements.append(AnyHashable(value))
    }

    mutating func appendAnyHashable(_ value: AnyHashable) {
        elements.append(value)
    }

    public mutating func removeLast(_ count: Int = 1) {
        elements.removeLast(Swift.min(Swift.max(0, count), elements.count))
    }
}

public enum NavigationBarItem {
    public enum TitleDisplayMode: Sendable, Equatable {
        case automatic
        case inline
        case large
    }
}

public enum NavigationSplitViewVisibility: Sendable, Equatable {
    case automatic
    case all
    case doubleColumn
    case detailOnly
}

@MainActor
struct NavigationDestinationRegistration {
    let resolve: (AnyHashable) -> [AnyView]?
}

@MainActor
struct NavigationPresentedDestination {
    let destination: () -> [AnyView]?
    let dismiss: () -> Void
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

public enum ColorScheme: Sendable, Equatable {
    case light
    case dark
}

public enum ColorSchemeContrast: Sendable, Equatable {
    case standard
    case increased
}

public enum ScenePhase: Sendable, Equatable, Hashable {
    case active
    case inactive
    case background
}

public enum ControlActiveState: Sendable, Equatable, Hashable, CaseIterable {
    case key
    case active
    case inactive
}

public enum EditMode: Sendable, Equatable, Hashable {
    case inactive
    case transient
    case active

    public var isEditing: Bool {
        self != .inactive
    }
}

public enum LegibilityWeight: Sendable, Equatable {
    case regular
    case bold

    var retainedFontWeight: Font.Weight {
        switch self {
        case .regular:
            return .regular
        case .bold:
            return .bold
        }
    }
}

public enum LayoutDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft
}

public enum UserInterfaceSizeClass: Sendable, Equatable, Hashable {
    case compact
    case regular
}

public enum DynamicTypeSize: Int, CaseIterable, Comparable, Sendable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5

    public static func < (lhs: DynamicTypeSize, rhs: DynamicTypeSize) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var isAccessibilitySize: Bool {
        self >= .accessibility1
    }

    var retainedFontScale: Double {
        switch self {
        case .xSmall:
            return 0.82
        case .small:
            return 0.88
        case .medium:
            return 0.95
        case .large:
            return 1.0
        case .xLarge:
            return 1.12
        case .xxLarge:
            return 1.24
        case .xxxLarge:
            return 1.36
        case .accessibility1:
            return 1.55
        case .accessibility2:
            return 1.75
        case .accessibility3:
            return 2.0
        case .accessibility4:
            return 2.35
        case .accessibility5:
            return 2.75
        }
    }
}

public enum TextInputAutocapitalization: Sendable, Equatable {
    case never
    case words
    case sentences
    case characters
}

public enum Visibility: Sendable, Equatable {
    case automatic
    case visible
    case hidden

    var hidesRetainedScrollContentBackground: Bool {
        self == .hidden
    }
}

public struct HoverEffect: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case highlight
        case lift
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = HoverEffect(kind: .automatic)
    public static let highlight = HoverEffect(kind: .highlight)
    public static let lift = HoverEffect(kind: .lift)

    var retainedEffect: RetainedHoverEffect {
        switch kind {
        case .automatic:
            return .automatic
        case .highlight:
            return .highlight
        case .lift:
            return .lift
        }
    }
}

public struct RedactionReasons: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let placeholder = RedactionReasons(rawValue: 1 << 0)

    var retainedReasons: RetainedRedactionReasons {
        var reasons: RetainedRedactionReasons = []
        if contains(.placeholder) {
            reasons.insert(.placeholder)
        }
        return reasons
    }
}

public enum Prominence: Sendable, Equatable, Hashable {
    case standard
    case increased
}

public struct BadgeProminence: Sendable, Equatable, Hashable {
    private enum Level: Sendable, Equatable, Hashable {
        case decreased
        case standard
        case increased
    }

    private let level: Level

    private init(_ level: Level) {
        self.level = level
    }

    public static let decreased = BadgeProminence(.decreased)
    public static let standard = BadgeProminence(.standard)
    public static let increased = BadgeProminence(.increased)
}

public protocol EnvironmentKey {
    associatedtype Value

    static var defaultValue: Value { get }
}

@MainActor
public final class UndoManager: @unchecked Sendable {
    private struct UndoAction {
        var name: String
        let handler: @MainActor () -> Void
    }

    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    private var pendingActionName = ""

    public private(set) var isUndoing = false
    public private(set) var isRedoing = false

    public init() {}

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public var undoActionName: String {
        undoStack.last?.name ?? ""
    }

    public var redoActionName: String {
        redoStack.last?.name ?? ""
    }

    public func registerUndo<TargetType: AnyObject>(
        withTarget target: TargetType,
        handler: @escaping @MainActor (TargetType) -> Void
    ) {
        let action = UndoAction(name: pendingActionName) { [target] in
            handler(target)
        }
        pendingActionName = ""

        if isUndoing {
            redoStack.append(action)
        } else {
            undoStack.append(action)
            if !isRedoing {
                redoStack.removeAll()
            }
        }
    }

    public func setActionName(_ actionName: String) {
        if isUndoing, !redoStack.isEmpty {
            redoStack[redoStack.count - 1].name = actionName
        } else if isRedoing, !undoStack.isEmpty {
            undoStack[undoStack.count - 1].name = actionName
        } else if !undoStack.isEmpty {
            undoStack[undoStack.count - 1].name = actionName
        } else {
            pendingActionName = actionName
        }
    }

    public func undo() {
        guard let action = undoStack.popLast() else {
            return
        }

        isUndoing = true
        action.handler()
        isUndoing = false
    }

    public func redo() {
        guard let action = redoStack.popLast() else {
            return
        }

        isRedoing = true
        action.handler()
        isRedoing = false
    }

    public func removeAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        pendingActionName = ""
    }
}

public struct OpenURLAction: @unchecked Sendable {
    public enum Result: Sendable, Equatable {
        case handled
        case discarded
        case systemAction
    }

    private let handler: @MainActor (URL) -> Result

    public init(handler: @escaping @MainActor (URL) -> Result) {
        self.handler = handler
    }

    @discardableResult
    @MainActor
    public func callAsFunction(_ url: URL) -> Result {
        handler(url)
    }

    public static let system = OpenURLAction { url in
        defaultOpenURL(url) ? .handled : .discarded
    }
}

public struct DismissAction: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    public init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction() {
        handler()
    }

    public static let noop = DismissAction {}
}

public struct RefreshAction: @unchecked Sendable {
    private let handler: @Sendable () async -> Void

    public init(action: @escaping @Sendable () async -> Void) {
        self.handler = action
    }

    public func callAsFunction() async {
        await handler()
    }
}

public struct OpenWindowAction: @unchecked Sendable {
    private let handler: @MainActor (_ id: String?) -> Void

    public init(handler: @escaping @MainActor (_ id: String?) -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction(id: String) {
        handler(id)
    }

    @MainActor
    public func callAsFunction<Value>(id: String, value: Value) where Value: Codable, Value: Hashable {
        handler(id)
    }

    @MainActor
    public func callAsFunction<Value>(value: Value) where Value: Codable, Value: Hashable {
        handler(nil)
    }

    public static let noop = OpenWindowAction { _ in }
}

public struct DismissWindowAction: @unchecked Sendable {
    private let handler: @MainActor (_ id: String?) -> Void

    public init(handler: @escaping @MainActor (_ id: String?) -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction() {
        handler(nil)
    }

    @MainActor
    public func callAsFunction(id: String) {
        handler(id)
    }

    @MainActor
    public func callAsFunction<Value>(id: String, value: Value) where Value: Codable, Value: Hashable {
        handler(id)
    }

    @MainActor
    public func callAsFunction<Value>(value: Value) where Value: Codable, Value: Hashable {
        handler(nil)
    }

    public static let noop = DismissWindowAction { _ in }
}

public struct EnvironmentValues: @unchecked Sendable {
    public var colorScheme: ColorScheme
    public var colorSchemeContrast: ColorSchemeContrast
    public var scenePhase: ScenePhase
    public var controlActiveState: ControlActiveState
    public var appearsActive: Bool
    public var supportsMultipleWindows: Bool
    public var editMode: Binding<EditMode>?
    public var legibilityWeight: LegibilityWeight?
    public var displayScale: Double
    public var pixelLength: Double
    public var accessibilityDifferentiateWithoutColor: Bool
    public var accessibilityInvertColors: Bool
    public var accessibilityReduceMotion: Bool
    public var accessibilityReduceTransparency: Bool
    public var accessibilityShowButtonShapes: Bool
    public var accessibilitySwitchControlEnabled: Bool
    public var accessibilityVoiceOverEnabled: Bool
    public var calendar: Calendar
    public var timeZone: TimeZone
    public var locale: Locale
    public var layoutDirection: LayoutDirection
    public var horizontalSizeClass: UserInterfaceSizeClass?
    public var verticalSizeClass: UserInterfaceSizeClass?
    public var dynamicTypeSize: DynamicTypeSize
    public var isEnabled: Bool
    public var foregroundStyle: ForegroundStyle?
    public var tint: Color?
    public var font: Font?
    public var multilineTextAlignment: TextAlignment
    public var lineLimit: Int?
    public var lineSpacing: Double?
    public var truncationMode: Text.TruncationMode?
    public var allowsTightening: Bool
    public var textCase: Text.Case?
    public var imageScale: Image.Scale
    public var controlSize: ControlSize
    public var labelStyle: LabelStyle
    public var toggleStyle: ToggleStyle
    public var textFieldStyle: TextFieldStyle
    public var listStyle: ListStyle
    public var textInputAutocapitalization: TextInputAutocapitalization?
    public var isAutocorrectionDisabled: Bool
    public var isScrollEnabled: Bool
    public var defaultHoverEffect: HoverEffect?
    public var isHoverEffectEnabled: Bool
    public var redactionReasons: RedactionReasons
    public var isPrivacySensitive: Bool
    var isScrollClipDisabled: Bool
    var scrollContentBackgroundVisibility: Visibility
    var listRowSpacing: Double?
    var gridHorizontalSpacing: Double?
    public var defaultMinListRowHeight: Double
    public var defaultMinListHeaderHeight: CGFloat?
    public var headerProminence: Prominence
    public var badgeProminence: BadgeProminence
    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility
    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility
    public var openURL: OpenURLAction
    public var dismiss: DismissAction
    public var refresh: RefreshAction?
    public var undoManager: UndoManager?
    public var openWindow: OpenWindowAction
    public var dismissWindow: DismissWindowAction
    private var customValues: [ObjectIdentifier: Any]

    public init(
        colorScheme: ColorScheme = .dark,
        colorSchemeContrast: ColorSchemeContrast = .standard,
        scenePhase: ScenePhase = .active,
        controlActiveState: ControlActiveState = .active,
        appearsActive: Bool = true,
        supportsMultipleWindows: Bool = false,
        editMode: Binding<EditMode>? = nil,
        legibilityWeight: LegibilityWeight? = nil,
        displayScale: Double = 1,
        pixelLength: Double = 1,
        accessibilityDifferentiateWithoutColor: Bool = false,
        accessibilityInvertColors: Bool = false,
        accessibilityReduceMotion: Bool = false,
        accessibilityReduceTransparency: Bool = false,
        accessibilityShowButtonShapes: Bool = false,
        accessibilitySwitchControlEnabled: Bool = false,
        accessibilityVoiceOverEnabled: Bool = false,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!,
        locale: Locale = .current,
        layoutDirection: LayoutDirection = .leftToRight,
        horizontalSizeClass: UserInterfaceSizeClass? = nil,
        verticalSizeClass: UserInterfaceSizeClass? = nil,
        dynamicTypeSize: DynamicTypeSize = .large,
        isEnabled: Bool = true,
        foregroundStyle: ForegroundStyle? = nil,
        tint: Color? = nil,
        font: Font? = nil,
        multilineTextAlignment: TextAlignment = .center,
        lineLimit: Int? = nil,
        lineSpacing: Double? = nil,
        truncationMode: Text.TruncationMode? = nil,
        allowsTightening: Bool = true,
        textCase: Text.Case? = nil,
        imageScale: Image.Scale = .medium,
        controlSize: ControlSize = .regular,
        labelStyle: LabelStyle = .automatic,
        toggleStyle: ToggleStyle = .automatic,
        textFieldStyle: TextFieldStyle = .automatic,
        listStyle: ListStyle = .automatic,
        textInputAutocapitalization: TextInputAutocapitalization? = nil,
        isAutocorrectionDisabled: Bool = false,
        isScrollEnabled: Bool = true,
        defaultHoverEffect: HoverEffect? = nil,
        isHoverEffectEnabled: Bool = true,
        redactionReasons: RedactionReasons = [],
        isPrivacySensitive: Bool = false,
        defaultMinListRowHeight: Double = 0,
        defaultMinListHeaderHeight: CGFloat? = nil,
        headerProminence: Prominence = .standard,
        badgeProminence: BadgeProminence = .standard,
        horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility = .automatic,
        verticalScrollIndicatorVisibility: ScrollIndicatorVisibility = .automatic,
        openURL: OpenURLAction = .system,
        dismiss: DismissAction = .noop,
        refresh: RefreshAction? = nil,
        undoManager: UndoManager? = nil,
        openWindow: OpenWindowAction = .noop,
        dismissWindow: DismissWindowAction = .noop
    ) {
        self.colorScheme = colorScheme
        self.colorSchemeContrast = colorSchemeContrast
        self.scenePhase = scenePhase
        self.controlActiveState = controlActiveState
        self.appearsActive = appearsActive
        self.supportsMultipleWindows = supportsMultipleWindows
        self.editMode = editMode
        self.legibilityWeight = legibilityWeight
        self.displayScale = displayScale
        self.pixelLength = pixelLength
        self.accessibilityDifferentiateWithoutColor = accessibilityDifferentiateWithoutColor
        self.accessibilityInvertColors = accessibilityInvertColors
        self.accessibilityReduceMotion = accessibilityReduceMotion
        self.accessibilityReduceTransparency = accessibilityReduceTransparency
        self.accessibilityShowButtonShapes = accessibilityShowButtonShapes
        self.accessibilitySwitchControlEnabled = accessibilitySwitchControlEnabled
        self.accessibilityVoiceOverEnabled = accessibilityVoiceOverEnabled
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone
        self.calendar = resolvedCalendar
        self.timeZone = timeZone
        self.locale = locale
        self.layoutDirection = layoutDirection
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.dynamicTypeSize = dynamicTypeSize
        self.isEnabled = isEnabled
        self.foregroundStyle = foregroundStyle
        self.tint = tint
        self.font = font
        self.multilineTextAlignment = multilineTextAlignment
        self.lineLimit = lineLimit
        self.lineSpacing = lineSpacing
        self.truncationMode = truncationMode
        self.allowsTightening = allowsTightening
        self.textCase = textCase
        self.imageScale = imageScale
        self.controlSize = controlSize
        self.labelStyle = labelStyle
        self.toggleStyle = toggleStyle
        self.textFieldStyle = textFieldStyle
        self.listStyle = listStyle
        self.textInputAutocapitalization = textInputAutocapitalization
        self.isAutocorrectionDisabled = isAutocorrectionDisabled
        self.isScrollEnabled = isScrollEnabled
        self.defaultHoverEffect = defaultHoverEffect
        self.isHoverEffectEnabled = isHoverEffectEnabled
        self.redactionReasons = redactionReasons
        self.isPrivacySensitive = isPrivacySensitive
        self.isScrollClipDisabled = false
        self.scrollContentBackgroundVisibility = .automatic
        self.listRowSpacing = nil
        self.gridHorizontalSpacing = nil
        self.defaultMinListRowHeight = defaultMinListRowHeight
        self.defaultMinListHeaderHeight = defaultMinListHeaderHeight
        self.headerProminence = headerProminence
        self.badgeProminence = badgeProminence
        self.horizontalScrollIndicatorVisibility = horizontalScrollIndicatorVisibility
        self.verticalScrollIndicatorVisibility = verticalScrollIndicatorVisibility
        self.openURL = openURL
        self.dismiss = dismiss
        self.refresh = refresh
        self.undoManager = undoManager
        self.openWindow = openWindow
        self.dismissWindow = dismissWindow
        self.customValues = [:]
    }

    public subscript<Key: EnvironmentKey>(_ key: Key.Type) -> Key.Value {
        get {
            customValues[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue
        }
        set {
            customValues[ObjectIdentifier(key)] = newValue
        }
    }
}

@MainActor
@propertyWrapper
public struct Environment<Value> {
    private let keyPath: KeyPath<EnvironmentValues, Value>

    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        let values = ViewBuildContextScope.current?.environmentValues ?? EnvironmentValues()
        return values[keyPath: keyPath]
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
    private let fontDesignProvider: () -> Font.Design?
    private let fontWeightProvider: () -> Font.Weight?
    private let textAlignmentProvider: () -> TextAlignment
    private let lineLimitProvider: () -> Int?
    private let truncationModeProvider: () -> Text.TruncationMode?
    private let allowsTighteningProvider: () -> Bool
    private let textCaseProvider: () -> Text.Case?
    private let labelsHiddenProvider: () -> Bool
    private let controlSizeProvider: () -> ControlSize
    private let stackAxisProvider: () -> StackAxis?
    private let buttonStyleProvider: () -> ButtonStyle
    private let pickerStyleProvider: () -> PickerStyle
    private let environmentValuesProvider: () -> EnvironmentValues
    private let navigationDestinationHandlerProvider: () -> (([AnyView]) -> Void)?
    private let navigationValueHandlerProvider: () -> ((AnyHashable) -> Bool)?
    private let navigationDestinationRegistrationsProvider: () -> [NavigationDestinationRegistration]
    private let navigationPresentedDestinationsProvider: () -> [NavigationPresentedDestination]

    public var canvasSize: Size {
        canvasSizeProvider()
    }

    public var isEnabled: Bool {
        isEnabledProvider()
    }

    public var foregroundColor: Color {
        switch environmentValuesProvider().foregroundStyle {
        case .color(let color):
            return color.resolvedForContrast(colorSchemeContrast)
        case .linearGradient(let gradient):
            return gradient.startColor.resolvedForContrast(colorSchemeContrast)
        case nil:
            return foregroundColorProvider().resolvedForContrast(colorSchemeContrast)
        }
    }

    var foregroundStyle: ForegroundStyle {
        (environmentValuesProvider().foregroundStyle ?? .color(foregroundColorProvider()))
            .resolvedForContrast(colorSchemeContrast)
    }

    public var tint: Color {
        environmentValuesProvider().tint ?? tintProvider()
    }

    public var imageScale: Image.Scale {
        environmentValuesProvider().imageScale
    }

    public var font: Font {
        var resolvedFont = environmentValuesProvider().font ?? fontProvider()
        if let design = fontDesignProvider() {
            resolvedFont = resolvedFont.withDesign(design)
        }
        return resolvedFont
    }

    public var fontDesign: Font.Design? {
        fontDesignProvider()
    }

    public var fontWeight: Font.Weight? {
        fontWeightProvider() ?? environmentValuesProvider().legibilityWeight?.retainedFontWeight
    }

    public var textAlignment: TextAlignment {
        environmentValuesProvider().multilineTextAlignment
    }

    public var lineLimit: Int? {
        environmentValuesProvider().lineLimit ?? lineLimitProvider()
    }

    public var lineSpacing: Double? {
        environmentValuesProvider().lineSpacing
    }

    public var truncationMode: Text.TruncationMode? {
        environmentValuesProvider().truncationMode ?? truncationModeProvider()
    }

    public var allowsTightening: Bool {
        environmentValuesProvider().allowsTightening
    }

    public var textCase: Text.Case? {
        environmentValuesProvider().textCase ?? textCaseProvider()
    }

    public var labelsHidden: Bool {
        labelsHiddenProvider()
    }

    public var controlSize: ControlSize {
        environmentValuesProvider().controlSize
    }

    public var stackAxis: StackAxis? {
        stackAxisProvider()
    }

    public var buttonStyle: ButtonStyle {
        buttonStyleProvider()
    }

    public var pickerStyle: PickerStyle {
        pickerStyleProvider()
    }

    public var labelStyle: LabelStyle {
        environmentValuesProvider().labelStyle
    }

    public var toggleStyle: ToggleStyle {
        environmentValuesProvider().toggleStyle
    }

    public var textFieldStyle: TextFieldStyle {
        environmentValuesProvider().textFieldStyle
    }

    public var listStyle: ListStyle {
        environmentValuesProvider().listStyle
    }

    public var textInputAutocapitalization: TextInputAutocapitalization? {
        environmentValuesProvider().textInputAutocapitalization
    }

    public var isAutocorrectionDisabled: Bool {
        environmentValuesProvider().isAutocorrectionDisabled
    }

    public var isScrollEnabled: Bool {
        environmentValuesProvider().isScrollEnabled
    }

    var isScrollClipDisabled: Bool {
        environmentValuesProvider().isScrollClipDisabled
    }

    var scrollContentBackgroundVisibility: Visibility {
        environmentValuesProvider().scrollContentBackgroundVisibility
    }

    var listRowSpacing: Double? {
        environmentValuesProvider().listRowSpacing
    }

    var gridHorizontalSpacing: Double? {
        environmentValuesProvider().gridHorizontalSpacing
    }

    public var defaultMinListRowHeight: Double {
        environmentValuesProvider().defaultMinListRowHeight
    }

    public var defaultMinListHeaderHeight: CGFloat? {
        environmentValuesProvider().defaultMinListHeaderHeight
    }

    public var headerProminence: Prominence {
        environmentValuesProvider().headerProminence
    }

    public var badgeProminence: BadgeProminence {
        environmentValuesProvider().badgeProminence
    }

    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        environmentValuesProvider().horizontalScrollIndicatorVisibility
    }

    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        environmentValuesProvider().verticalScrollIndicatorVisibility
    }

    func scrollIndicatorVisibility(for axis: Axis) -> ScrollIndicatorVisibility {
        switch axis {
        case .horizontal:
            return horizontalScrollIndicatorVisibility
        case .vertical:
            return verticalScrollIndicatorVisibility
        }
    }

    public var environmentValues: EnvironmentValues {
        var values = environmentValuesProvider()
        values.isEnabled = values.isEnabled && isEnabled
        if values.tint == nil {
            values.tint = tintProvider()
        }
        return values
    }

    public var layoutDirection: LayoutDirection {
        environmentValues.layoutDirection
    }

    public var colorSchemeContrast: ColorSchemeContrast {
        environmentValues.colorSchemeContrast
    }

    public var dynamicTypeSize: DynamicTypeSize {
        environmentValues.dynamicTypeSize
    }

    public var displayScale: Double {
        environmentValues.displayScale
    }

    public var pixelLength: Double {
        environmentValues.pixelLength
    }

    public var accessibilityReduceMotion: Bool {
        environmentValues.accessibilityReduceMotion
    }

    var navigationDestinationRegistrations: [NavigationDestinationRegistration] {
        navigationDestinationRegistrationsProvider()
    }

    var navigationPresentedDestinations: [NavigationPresentedDestination] {
        navigationPresentedDestinationsProvider()
    }

    init(
        canvasSizeProvider: @escaping () -> Size,
        invalidateHandler: @escaping () -> Void,
        observedObjectHandler: @escaping (any ObservableObject) -> Void = { _ in },
        isEnabledProvider: @escaping () -> Bool = { true },
        foregroundColorProvider: @escaping () -> Color = { .white },
        tintProvider: @escaping () -> Color = { ViewBuildContext.defaultTint },
        fontProvider: @escaping () -> Font = { .system(size: 2) },
        fontDesignProvider: @escaping () -> Font.Design? = { nil },
        fontWeightProvider: @escaping () -> Font.Weight? = { nil },
        textAlignmentProvider: @escaping () -> TextAlignment = { .center },
        lineLimitProvider: @escaping () -> Int? = { nil },
        truncationModeProvider: @escaping () -> Text.TruncationMode? = { nil },
        allowsTighteningProvider: @escaping () -> Bool = { true },
        textCaseProvider: @escaping () -> Text.Case? = { nil },
        labelsHiddenProvider: @escaping () -> Bool = { false },
        controlSizeProvider: @escaping () -> ControlSize = { .regular },
        stackAxisProvider: @escaping () -> StackAxis? = { nil },
        buttonStyleProvider: @escaping () -> ButtonStyle = { .automatic },
        pickerStyleProvider: @escaping () -> PickerStyle = { .automatic },
        environmentValuesProvider: @escaping () -> EnvironmentValues = { EnvironmentValues() },
        navigationDestinationHandlerProvider: @escaping () -> (([AnyView]) -> Void)? = { nil },
        navigationValueHandlerProvider: @escaping () -> ((AnyHashable) -> Bool)? = { nil },
        navigationDestinationRegistrationsProvider: @escaping () -> [NavigationDestinationRegistration] = { [] },
        navigationPresentedDestinationsProvider: @escaping () -> [NavigationPresentedDestination] = { [] }
    ) {
        self.canvasSizeProvider = canvasSizeProvider
        self.invalidateHandler = invalidateHandler
        self.observedObjectHandler = observedObjectHandler
        self.isEnabledProvider = isEnabledProvider
        self.foregroundColorProvider = foregroundColorProvider
        self.tintProvider = tintProvider
        self.fontProvider = fontProvider
        self.fontDesignProvider = fontDesignProvider
        self.fontWeightProvider = fontWeightProvider
        self.textAlignmentProvider = textAlignmentProvider
        self.lineLimitProvider = lineLimitProvider
        self.truncationModeProvider = truncationModeProvider
        self.allowsTighteningProvider = allowsTighteningProvider
        self.textCaseProvider = textCaseProvider
        self.labelsHiddenProvider = labelsHiddenProvider
        self.controlSizeProvider = controlSizeProvider
        self.stackAxisProvider = stackAxisProvider
        self.buttonStyleProvider = buttonStyleProvider
        self.pickerStyleProvider = pickerStyleProvider
        self.environmentValuesProvider = environmentValuesProvider
        self.navigationDestinationHandlerProvider = navigationDestinationHandlerProvider
        self.navigationValueHandlerProvider = navigationValueHandlerProvider
        self.navigationDestinationRegistrationsProvider = navigationDestinationRegistrationsProvider
        self.navigationPresentedDestinationsProvider = navigationPresentedDestinationsProvider
    }

    public static let defaultTint = Color(red: 0.20, green: 0.60, blue: 1.0, alpha: 1.0)

    func invalidate() {
        invalidateHandler()
    }

    func observe(_ object: any ObservableObject) {
        observedObjectHandler(object)
    }

    func pushNavigationDestination(_ destination: [AnyView]) -> Bool {
        guard let handler = navigationDestinationHandlerProvider() else {
            return false
        }

        handler(destination)
        return true
    }

    func pushNavigationValue(_ value: AnyHashable) -> Bool {
        guard let handler = navigationValueHandlerProvider() else {
            return false
        }

        return handler(value)
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.foregroundStyle = .color(color)
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.tint = tint
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withFont(_ font: Font?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.font = font
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withFontDesign(_ design: Font.Design?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: { design },
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: { weight },
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.multilineTextAlignment = alignment
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.lineLimit = lineLimit
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withTruncationMode(_ mode: Text.TruncationMode?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.truncationMode = mode
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withAllowsTightening(_ allowsTightening: Bool) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.allowsTightening = allowsTightening
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withTextCase(_ textCase: Text.Case?) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.textCase = textCase
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withLabelsHidden(_ labelsHidden: Bool) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: { labelsHidden },
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withControlSize(_ controlSize: ControlSize) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: { controlSize },
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values.controlSize = controlSize
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
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
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: { axis },
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withButtonStyle(_ buttonStyle: ButtonStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: { buttonStyle },
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withPickerStyle(_ pickerStyle: PickerStyle) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: { pickerStyle },
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withEnvironmentValue<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: {
                var values = environmentValuesProvider()
                values[keyPath: keyPath] = value
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withNavigationDestinationHandler(_ handler: @escaping ([AnyView]) -> Void) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: { handler },
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withNavigationValueHandler(_ handler: @escaping (AnyHashable) -> Bool) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: { handler },
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withNavigationDestinationRegistration(_ registration: NavigationDestinationRegistration) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: {
                navigationDestinationRegistrationsProvider() + [registration]
            },
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withNavigationPresentedDestination(_ destination: NavigationPresentedDestination) -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: canvasSizeProvider,
            invalidateHandler: invalidateHandler,
            observedObjectHandler: observedObjectHandler,
            isEnabledProvider: isEnabledProvider,
            foregroundColorProvider: foregroundColorProvider,
            tintProvider: tintProvider,
            fontProvider: fontProvider,
            fontDesignProvider: fontDesignProvider,
            fontWeightProvider: fontWeightProvider,
            textAlignmentProvider: textAlignmentProvider,
            lineLimitProvider: lineLimitProvider,
            truncationModeProvider: truncationModeProvider,
            allowsTighteningProvider: allowsTighteningProvider,
            textCaseProvider: textCaseProvider,
            labelsHiddenProvider: labelsHiddenProvider,
            controlSizeProvider: controlSizeProvider,
            stackAxisProvider: stackAxisProvider,
            buttonStyleProvider: buttonStyleProvider,
            pickerStyleProvider: pickerStyleProvider,
            environmentValuesProvider: environmentValuesProvider,
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: {
                navigationPresentedDestinationsProvider() + [destination]
            }
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
public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = ViewModifierContent

    @ViewBuilder
    func body(content: Content) -> Body
}

@MainActor
public struct ViewModifierContent: View, TaggedViewMetadata {
    public typealias Body = Never

    private let content: AnyView

    init<V: View>(_ content: V) {
        self.content = AnyView(content)
    }

    public var body: Never {
        fatalError("ViewModifierContent has no body")
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

    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? {
        content.navigationTitleDisplayMode
    }

    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        content.navigationDestinationRegistrations
    }

    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        content.navigationPresentedDestinations
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        content.makeComponent(context: context)
    }
}

@MainActor
public struct ModifiedContent<Content: View, Modifier: ViewModifier>: View, TaggedViewMetadata {
    public typealias Body = Never

    public let content: Content
    public let modifier: Modifier

    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }

    public var body: Never {
        fatalError("ModifiedContent has no body")
    }

    var anySelectionTag: AnyHashable? {
        (content as? any TaggedViewMetadata)?.anySelectionTag
    }

    var anyTabItem: [AnyView]? {
        (content as? any TaggedViewMetadata)?.anyTabItem
    }

    var anyBadge: [AnyView]? {
        (content as? any TaggedViewMetadata)?.anyBadge
    }

    var anyNavigationTitle: [AnyView]? {
        (content as? any TaggedViewMetadata)?.anyNavigationTitle
    }

    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? {
        (content as? any TaggedViewMetadata)?.anyNavigationTitleDisplayMode
    }

    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        (content as? any TaggedViewMetadata)?.anyNavigationDestinationRegistrations ?? []
    }

    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        (content as? any TaggedViewMetadata)?.anyNavigationPresentedDestinations ?? []
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        modifier
            .body(content: ViewModifierContent(content))
            .makeComponent(context: context)
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
    let selectionTag: AnyHashable?
    let tabItem: [AnyView]?
    let badge: [AnyView]?
    let navigationTitle: [AnyView]?
    let navigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode?
    let navigationDestinationRegistrations: [NavigationDestinationRegistration]
    let navigationPresentedDestinations: [NavigationPresentedDestination]

    public init<V: View>(_ view: V) {
        self.selectionTag = (view as? any TaggedViewMetadata)?.anySelectionTag
        self.tabItem = (view as? any TaggedViewMetadata)?.anyTabItem
        self.badge = (view as? any TaggedViewMetadata)?.anyBadge
        self.navigationTitle = (view as? any TaggedViewMetadata)?.anyNavigationTitle
        self.navigationTitleDisplayMode = (view as? any TaggedViewMetadata)?.anyNavigationTitleDisplayMode
        self.navigationDestinationRegistrations = (view as? any TaggedViewMetadata)?.anyNavigationDestinationRegistrations ?? []
        self.navigationPresentedDestinations = (view as? any TaggedViewMetadata)?.anyNavigationPresentedDestinations ?? []
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

public struct PinnedScrollableViews: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
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

    public struct Set: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)
        public static let all: Set = [.horizontal, .vertical]
    }
}

public enum ContentMode: Sendable {
    case fit
    case fill
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

public struct ContentShapeKinds: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let interaction = ContentShapeKinds(rawValue: 1 << 0)
    public static let dragPreview = ContentShapeKinds(rawValue: 1 << 1)
    public static let contextMenuPreview = ContentShapeKinds(rawValue: 1 << 2)
    public static let focusEffect = ContentShapeKinds(rawValue: 1 << 3)
    public static let hoverEffect = ContentShapeKinds(rawValue: 1 << 4)
    public static let accessibility = ContentShapeKinds(rawValue: 1 << 5)
}

public struct EventModifiers: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let capsLock = EventModifiers(rawValue: 1 << 0)
    public static let shift = EventModifiers(rawValue: 1 << 1)
    public static let control = EventModifiers(rawValue: 1 << 2)
    public static let option = EventModifiers(rawValue: 1 << 3)
    public static let command = EventModifiers(rawValue: 1 << 4)
    public static let numericPad = EventModifiers(rawValue: 1 << 5)
    public static let all: EventModifiers = [.capsLock, .shift, .control, .option, .command, .numericPad]

    var retainedKeyboardModifiers: KeyboardModifiers {
        var modifiers: KeyboardModifiers = []
        if contains(.shift) {
            modifiers.insert(.shift)
        }
        if contains(.control) || contains(.command) {
            modifiers.insert(.control)
        }
        if contains(.option) {
            modifiers.insert(.alt)
        }
        return modifiers
    }
}

public struct KeyEquivalent: Sendable, Equatable, Hashable, ExpressibleByExtendedGraphemeClusterLiteral, ExpressibleByUnicodeScalarLiteral {
    public typealias ExtendedGraphemeClusterLiteralType = Character
    public typealias UnicodeScalarLiteralType = UnicodeScalar

    let retainedKeyCode: UInt32

    public init(_ character: Character) {
        self.retainedKeyCode = Self.retainedKeyCode(for: character)
    }

    public init(extendedGraphemeClusterLiteral value: Character) {
        self.init(value)
    }

    public init(unicodeScalarLiteral value: UnicodeScalar) {
        self.retainedKeyCode = value.value
    }

    private init(retainedKeyCode: UInt32) {
        self.retainedKeyCode = retainedKeyCode
    }

    public static let upArrow = KeyEquivalent(retainedKeyCode: 0x26)
    public static let downArrow = KeyEquivalent(retainedKeyCode: 0x28)
    public static let leftArrow = KeyEquivalent(retainedKeyCode: 0x25)
    public static let rightArrow = KeyEquivalent(retainedKeyCode: 0x27)
    public static let escape = KeyEquivalent(retainedKeyCode: 0x1B)
    public static let delete = KeyEquivalent(retainedKeyCode: 0x08)
    public static let deleteForward = KeyEquivalent(retainedKeyCode: 0x2E)
    public static let `return` = KeyEquivalent(retainedKeyCode: 0x0D)
    public static let tab = KeyEquivalent(retainedKeyCode: 0x09)
    public static let space = KeyEquivalent(retainedKeyCode: 0x20)

    private static func retainedKeyCode(for character: Character) -> UInt32 {
        switch character {
        case " ":
            return KeyboardKey.space.rawValue
        case "\t":
            return KeyboardKey.tab.rawValue
        case "\n", "\r":
            return KeyboardKey.enter.rawValue
        default:
            let uppercased = String(character).uppercased()
            return uppercased.unicodeScalars.first?.value ?? 0
        }
    }
}

public struct KeyboardShortcut: Sendable, Equatable, Hashable {
    let key: KeyEquivalent
    let modifiers: EventModifiers

    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])

    var retainedBinding: KeyboardShortcutBinding {
        KeyboardShortcutBinding(
            keyCode: key.retainedKeyCode,
            modifiers: modifiers.retainedKeyboardModifiers
        )
    }
}

public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let text = SubmitTriggers(rawValue: 1 << 0)
    public static let search = SubmitTriggers(rawValue: 1 << 1)
    public static let all: SubmitTriggers = [.text, .search]

    var submitsTextInput: Bool {
        !intersection(.all).isEmpty
    }
}

public extension StrokeStyle {
    init(
        lineWidth: Double = 1,
        lineCap: LineCap = .butt,
        lineJoin: LineJoin = .miter,
        miterLimit: Double = 10,
        dash: [Double] = [],
        dashPhase: Double = 0
    ) {
        _ = miterLimit
        self.init(
            lineWidth: lineWidth,
            dashPattern: dash,
            dashOffset: dashPhase,
            lineCap: lineCap,
            lineJoin: lineJoin
        )
    }
}

public enum SubmitLabel: Sendable, Equatable {
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

    public func monospaced() -> Font {
        withDesign(.monospaced)
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
        case bordered
        case borderedProminent
        case borderless
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonStyle(kind: .automatic)
    public static let plain = ButtonStyle(kind: .plain)
    public static let bordered = ButtonStyle(kind: .bordered)
    public static let borderedProminent = ButtonStyle(kind: .borderedProminent)
    public static let borderless = ButtonStyle(kind: .borderless)

    var surfaceStyle: ButtonSurfaceStyle {
        switch kind {
        case .automatic, .bordered, .borderedProminent:
            return .default
        case .plain, .borderless:
            return .plain
        }
    }
}

public struct PickerStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case segmented
        case menu
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PickerStyle(kind: .automatic)
    public static let segmented = PickerStyle(kind: .segmented)
    public static let menu = PickerStyle(kind: .menu)
}

public enum ForegroundStyle: Sendable, Equatable {
    case color(Color)
    case linearGradient(LinearGradient)
}

public enum ControlSize: Sendable, Equatable {
    case mini
    case small
    case regular
    case large
    case extraLarge
}

public struct LabelStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case titleAndIcon
        case iconOnly
        case titleOnly
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = LabelStyle(kind: .automatic)
    public static let titleAndIcon = LabelStyle(kind: .titleAndIcon)
    public static let iconOnly = LabelStyle(kind: .iconOnly)
    public static let titleOnly = LabelStyle(kind: .titleOnly)
}

public struct ToggleStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case `switch`
        case checkbox
        case button
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ToggleStyle(kind: .automatic)
    public static let `switch` = ToggleStyle(kind: .switch)
    public static let checkbox = ToggleStyle(kind: .checkbox)
    public static let button = ToggleStyle(kind: .button)
}

public struct TextFieldStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case plain
        case roundedBorder
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = TextFieldStyle(kind: .automatic)
    public static let plain = TextFieldStyle(kind: .plain)
    public static let roundedBorder = TextFieldStyle(kind: .roundedBorder)
}

public struct ListStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case plain
        case grouped
        case inset
        case insetGrouped
        case sidebar
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ListStyle(kind: .automatic)
    public static let plain = ListStyle(kind: .plain)
    public static let grouped = ListStyle(kind: .grouped)
    public static let inset = ListStyle(kind: .inset)
    public static let insetGrouped = ListStyle(kind: .insetGrouped)
    public static let sidebar = ListStyle(kind: .sidebar)

    var retainedChrome: RetainedListChrome {
        switch kind {
        case .automatic, .plain:
            return RetainedListChrome()
        case .grouped:
            return RetainedListChrome(
                defaultSpacing: 8,
                padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.72),
                borderColor: Color(red: 0.72, green: 0.80, blue: 0.92, alpha: 0.16),
                borderWidth: 1,
                cornerRadius: 12
            )
        case .inset:
            return RetainedListChrome(
                defaultSpacing: 6,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
                backgroundColor: nil,
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 0
            )
        case .insetGrouped:
            return RetainedListChrome(
                defaultSpacing: 8,
                padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12),
                backgroundColor: Color(red: 0.09, green: 0.12, blue: 0.18, alpha: 0.78),
                borderColor: Color(red: 0.76, green: 0.84, blue: 0.96, alpha: 0.18),
                borderWidth: 1,
                cornerRadius: 14
            )
        case .sidebar:
            return RetainedListChrome(
                defaultSpacing: 4,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                backgroundColor: Color(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.68),
                borderColor: .clear,
                borderWidth: 0,
                cornerRadius: 10
            )
        }
    }
}

struct RetainedListChrome: Sendable, Equatable {
    var defaultSpacing: Double = 0
    var padding: EdgeInsets = .zero
    var backgroundColor: Color? = nil
    var borderColor: Color = .clear
    var borderWidth: Double = 0
    var cornerRadius: Double = 0
}

public struct ScrollIndicatorVisibility: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case visible
        case hidden
        case never
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ScrollIndicatorVisibility(kind: .automatic)
    public static let visible = ScrollIndicatorVisibility(kind: .visible)
    public static let hidden = ScrollIndicatorVisibility(kind: .hidden)
    public static let never = ScrollIndicatorVisibility(kind: .never)

    var showsRetainedScrollIndicator: Bool {
        switch kind {
        case .automatic, .visible:
            return true
        case .hidden, .never:
            return false
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
struct ModifiedView<Content: View>: View, TaggedViewMetadata {
    typealias Body = Never

    let content: Content
    let transform: (Content, ViewBuildContext) -> Component

    /// Optional stable identity for the modified view, propagated to the
    /// resulting ViewNode so the diffing algorithm can match nodes across
    /// rebuilds by identity rather than position alone.
    var id: String?
    var selectionTag: AnyHashable?
    var tabItem: [AnyView]?
    var badge: [AnyView]?
    var navigationTitle: [AnyView]?
    var navigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode?
    var navigationDestinationRegistrations: [NavigationDestinationRegistration] = []
    var navigationPresentedDestinations: [NavigationPresentedDestination] = []

    var anySelectionTag: AnyHashable? {
        selectionTag ?? (content as? any TaggedViewMetadata)?.anySelectionTag
    }

    var anyTabItem: [AnyView]? {
        tabItem ?? (content as? any TaggedViewMetadata)?.anyTabItem
    }

    var anyBadge: [AnyView]? {
        badge ?? (content as? any TaggedViewMetadata)?.anyBadge
    }

    var anyNavigationTitle: [AnyView]? {
        navigationTitle ?? (content as? any TaggedViewMetadata)?.anyNavigationTitle
    }

    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? {
        navigationTitleDisplayMode ?? (content as? any TaggedViewMetadata)?.anyNavigationTitleDisplayMode
    }

    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        ((content as? any TaggedViewMetadata)?.anyNavigationDestinationRegistrations ?? []) + navigationDestinationRegistrations
    }

    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        ((content as? any TaggedViewMetadata)?.anyNavigationPresentedDestinations ?? []) + navigationPresentedDestinations
    }

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
protocol TaggedViewMetadata {
    var anySelectionTag: AnyHashable? { get }
    var anyTabItem: [AnyView]? { get }
    var anyBadge: [AnyView]? { get }
    var anyNavigationTitle: [AnyView]? { get }
    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? { get }
    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] { get }
    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] { get }
}

extension TaggedViewMetadata {
    var anyTabItem: [AnyView]? {
        nil
    }

    var anyBadge: [AnyView]? {
        nil
    }

    var anyNavigationTitle: [AnyView]? {
        nil
    }

    var anyNavigationTitleDisplayMode: NavigationBarItem.TitleDisplayMode? {
        nil
    }

    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        []
    }

    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        []
    }
}

@MainActor
struct TaggedView<Content: View, Tag: Hashable>: View, TaggedViewMetadata {
    typealias Body = Never

    let content: Content
    let tag: Tag

    var anySelectionTag: AnyHashable? {
        AnyHashable(tag)
    }

    var body: Never {
        fatalError("TaggedView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        content.makeComponent(context: context)
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
    func resolved(for layoutDirection: LayoutDirection) -> HorizontalAlignment {
        switch (self, layoutDirection) {
        case (.leading, .rightToLeft):
            return .trailing
        case (.trailing, .rightToLeft):
            return .leading
        case (.leading, .leftToRight), (.center, _), (.trailing, .leftToRight):
            return self
        }
    }

    var stackAlignment: StackCrossAlignment {
        stackAlignment(layoutDirection: .leftToRight)
    }

    func stackAlignment(layoutDirection: LayoutDirection) -> StackCrossAlignment {
        switch resolved(for: layoutDirection) {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    var textAlignment: TextHorizontalAlignment {
        textAlignment(layoutDirection: .leftToRight)
    }

    func textAlignment(layoutDirection: LayoutDirection) -> TextHorizontalAlignment {
        switch resolved(for: layoutDirection) {
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

    func textAlignment(layoutDirection: LayoutDirection) -> TextHorizontalAlignment {
        horizontalAlignment.textAlignment(layoutDirection: layoutDirection)
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
    func withDesign(_ design: Design) -> Font {
        Font(size: size, weight: weight, design: design, family: family)
    }

    func scaled(for dynamicTypeSize: DynamicTypeSize) -> Font {
        Font(
            size: size * dynamicTypeSize.retainedFontScale,
            weight: weight,
            design: design,
            family: family
        )
    }

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
    static let highContrastSecondary = SwiftWindowsCore.Color(red: 0.88, green: 0.92, blue: 0.98, alpha: 1)
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

    func resolvedForContrast(_ contrast: ColorSchemeContrast) -> SwiftWindowsCore.Color {
        guard contrast == .increased, self == .secondary else {
            return self
        }

        let alpha = rgba.3
        let highContrastComponents = SwiftWindowsCore.Color.highContrastSecondary.rgba
        return SwiftWindowsCore.Color(
            red: highContrastComponents.0,
            green: highContrastComponents.1,
            blue: highContrastComponents.2,
            alpha: alpha
        )
    }
}

extension ForegroundStyle {
    func resolvedForContrast(_ contrast: ColorSchemeContrast) -> ForegroundStyle {
        switch self {
        case .color(let color):
            return .color(color.resolvedForContrast(contrast))
        case .linearGradient(let gradient):
            return .linearGradient(gradient.resolvedForContrast(contrast))
        }
    }
}

extension LinearGradient {
    func resolvedForContrast(_ contrast: ColorSchemeContrast) -> LinearGradient {
        LinearGradient(
            startColor: startColor.resolvedForContrast(contrast),
            endColor: endColor.resolvedForContrast(contrast),
            axis: axis
        )
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

private func resolvedStyleFill(from style: ForegroundStyle) -> (color: Color?, gradient: LinearGradient?) {
    switch style {
    case .color(let color):
        return (color, nil)
    case .linearGradient(let gradient):
        return (nil, gradient)
    }
}

extension BadgeProminence {
    var retainedBadgeBackgroundColor: Color {
        switch level {
        case .decreased:
            return Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12)
        case .standard:
            return Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.22)
        case .increased:
            return Color(red: 0.92, green: 0.18, blue: 0.24, alpha: 0.96)
        }
    }

    var retainedBadgeTextColor: Color {
        switch level {
        case .decreased:
            return Color(red: 0.86, green: 0.92, blue: 0.98, alpha: 0.78)
        case .standard, .increased:
            return .white
        }
    }
}

extension ViewBuildContext {
    var badgeContext: ViewBuildContext {
        withForegroundColor(badgeProminence.retainedBadgeTextColor)
            .withFont(.caption)
            .withLineLimit(1)
    }

    func makeRetainedBadgeNode(from views: [AnyView], runtime: RetainedViewRuntime) -> ViewNode {
        let badgeContentNode = composeComponent(
            from: views,
            context: badgeContext,
            fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center))
        )
        .makeNode(runtime: runtime)

        let badgeNode = Controls.stackPanel(
            backgroundColor: badgeProminence.retainedBadgeBackgroundColor,
            cornerRadius: 9,
            stackLayout: .horizontal(
                spacing: 0,
                padding: EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6),
                alignment: .center,
                mainAlignment: .center
            ),
            isHitTestVisible: false,
            children: [badgeContentNode]
        )
        badgeNode.layoutConstraints = LayoutConstraints(minWidth: 18, minHeight: 18)
        return badgeNode
    }
}

private func resolvedStyleColor(from style: ForegroundStyle) -> Color {
    switch style {
    case .color(let color):
        return color
    case .linearGradient(let gradient):
        return gradient.startColor
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
    public init() {
        self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    static func all(_ value: Double) -> EdgeInsets {
        EdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }
}

extension Alignment {
    func frameOrigin(
        for childSize: Size,
        in containerSize: Size,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> Point {
        let x: Double
        switch horizontal.resolved(for: layoutDirection) {
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

@MainActor
private final class OnChangeObservationRegistry {
    static let shared = OnChangeObservationRegistry()

    private var values: [String: Any] = [:]

    func observe<Value: Equatable>(
        value: Value,
        key: String,
        initial: Bool
    ) -> (oldValue: Value, newValue: Value)? {
        if let previous = values[key] as? Value {
            guard previous != value else {
                return nil
            }

            values[key] = value
            return (previous, value)
        }

        values[key] = value
        return initial ? (value, value) : nil
    }
}

public extension View {
    func modifier<Modifier: ViewModifier>(_ modifier: Modifier) -> ModifiedContent<Self, Modifier> {
        ModifiedContent(content: self, modifier: modifier)
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
                        alignment: alignment.horizontal.stackAlignment(layoutDirection: context.layoutDirection),
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
                        alignment: alignment.horizontal.stackAlignment(layoutDirection: context.layoutDirection),
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

    func safeAreaPadding(_ length: Double? = nil) -> some View {
        self
    }

    func safeAreaPadding(_ edges: Edge.Set, _ length: Double? = nil) -> some View {
        self
    }

    func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        self
    }

    func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
        self
    }

    func scaledToFit() -> some View {
        aspectRatio(contentMode: .fit)
    }

    func scaledToFill() -> some View {
        aspectRatio(contentMode: .fill)
    }

    func padding(_ length: Double = 16) -> some View {
        padding(EdgeInsets.all(length))
    }

    func padding(_ length: Double?) -> some View {
        padding(length ?? 16)
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

    func padding(_ edges: Edge.Set, _ length: Double?) -> some View {
        padding(edges, length ?? 16)
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

    func background(_ color: Color, ignoresSafeAreaEdges edges: Edge.Set) -> some View {
        _ = edges
        return background(color)
    }

    func background(_ color: Color?, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        return ModifiedView(content: self) { content, context in
            guard let color else {
                return content.makeComponent(context: context)
            }

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

    func background(_ style: ForegroundStyle, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        let fill = resolvedStyleFill(from: style)
        return backgroundStyle(color: fill.color, gradient: fill.gradient)
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

    func background(_ gradient: LinearGradient, ignoresSafeAreaEdges edges: Edge.Set) -> some View {
        _ = edges
        return background(gradient)
    }

    private func backgroundStyle(color: Color?, gradient: LinearGradient?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    backgroundColor: color,
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
                    let backgroundOrigin = alignment.frameOrigin(
                        for: backgroundSize,
                        in: containerSize,
                        layoutDirection: context.layoutDirection
                    )
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

    func overlay(_ color: Color) -> some View {
        overlayStyle(color: color, gradient: nil)
    }

    func overlay(_ color: Color, ignoresSafeAreaEdges edges: Edge.Set) -> some View {
        _ = edges
        return overlay(color)
    }

    func overlay(_ color: Color?, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        return overlayStyle(color: color, gradient: nil)
    }

    func overlay(_ style: ForegroundStyle, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        let fill = resolvedStyleFill(from: style)
        return overlayStyle(color: fill.color, gradient: fill.gradient)
    }

    func overlay(_ gradient: LinearGradient) -> some View {
        overlayStyle(color: nil, gradient: gradient)
    }

    func overlay(_ gradient: LinearGradient, ignoresSafeAreaEdges edges: Edge.Set) -> some View {
        _ = edges
        return overlay(gradient)
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
                    let overlayOrigin = alignment.frameOrigin(
                        for: overlaySize,
                        in: containerSize,
                        layoutDirection: context.layoutDirection
                    )
                    let overlayFrame = Rect(origin: overlayOrigin, size: overlaySize)
                    if overlayNode.frame != overlayFrame {
                        overlayNode.frame = overlayFrame
                    }
                }

                return root
            }
        }
    }

    private func overlayStyle(color: Color?, gradient: LinearGradient?) -> some View {
        ModifiedView(content: self) { content, context in
            guard color != nil || gradient != nil else {
                return content.makeComponent(context: context)
            }

            let base = content.makeComponent(context: context)

            return Component { runtime in
                let baseNode = base.makeNode(runtime: runtime)
                let overlayNode = Controls.panel(
                    backgroundColor: color,
                    backgroundGradient: gradient,
                    isHitTestVisible: false
                )
                let preferredSize = baseNode.intrinsicContentSize()
                let root = Controls.panel(
                    preferredSize: preferredSize,
                    layoutMode: .absolute,
                    isHitTestVisible: false,
                    children: [baseNode, overlayNode]
                )

                root.onLayout = { bounds in
                    let frame = Rect(origin: .zero, size: bounds.size)
                    if baseNode.frame != frame {
                        baseNode.frame = frame
                    }
                    if overlayNode.frame != frame {
                        overlayNode.frame = frame
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

    func foregroundColor(_ color: Color?) -> some View {
        ModifiedView(content: self) { content, context in
            guard let color else {
                return content.makeComponent(context: context)
            }

            return content.makeComponent(context: context.withForegroundColor(color))
        }
    }

    func foregroundStyle(_ color: Color) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withForegroundColor(color))
        }
    }

    func foregroundStyle(_ primary: Color, _ secondary: Color) -> some View {
        _ = secondary
        return foregroundStyle(primary)
    }

    func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> some View {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    func foregroundStyle(_ style: ForegroundStyle) -> some View {
        ModifiedView(content: self) { content, context in
            switch style {
            case .color(let color):
                content.makeComponent(context: context.withForegroundColor(color))
            case .linearGradient:
                content.makeComponent(context: context.withEnvironmentValue(\.foregroundStyle, style))
            }
        }
    }

    func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle) -> some View {
        _ = secondary
        return foregroundStyle(primary)
    }

    func foregroundStyle(_ primary: ForegroundStyle, _ secondary: ForegroundStyle, _ tertiary: ForegroundStyle) -> some View {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    func foregroundStyle(_ gradient: LinearGradient) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.foregroundStyle, .linearGradient(gradient)))
        }
    }

    func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient) -> some View {
        _ = secondary
        return foregroundStyle(primary)
    }

    func foregroundStyle(_ primary: LinearGradient, _ secondary: LinearGradient, _ tertiary: LinearGradient) -> some View {
        _ = secondary
        _ = tertiary
        return foregroundStyle(primary)
    }

    func imageScale(_ scale: Image.Scale) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.imageScale, scale))
        }
    }

    func tint(_ tint: Color) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTint(tint))
        }
    }

    func tint(_ tint: Color?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTint(tint ?? ViewBuildContext.defaultTint))
        }
    }

    func accentColor(_ accentColor: Color?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTint(accentColor ?? ViewBuildContext.defaultTint))
        }
    }

    func buttonStyle(_ style: ButtonStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withButtonStyle(style))
        }
    }

    func pickerStyle(_ style: PickerStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withPickerStyle(style))
        }
    }

    func labelStyle(_ style: LabelStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.labelStyle, style))
        }
    }

    func toggleStyle(_ style: ToggleStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.toggleStyle, style))
        }
    }

    func textFieldStyle(_ style: TextFieldStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textFieldStyle, style))
        }
    }

    func listStyle(_ style: ListStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.listStyle, style))
        }
    }

    func textInputAutocapitalization(_ textInputAutocapitalization: TextInputAutocapitalization?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textInputAutocapitalization, textInputAutocapitalization))
        }
    }

    func autocorrectionDisabled(_ disable: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isAutocorrectionDisabled, disable))
        }
    }

    func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        navigationTitle(Text(String(title)))
    }

    func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        navigationTitle(Text(titleKey))
    }

    func navigationTitle(_ title: Text) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.navigationTitle = [AnyView(title)]
        return modified
    }

    func navigationBarTitle<S: StringProtocol>(
        _ title: S,
        displayMode: NavigationBarItem.TitleDisplayMode = .automatic
    ) -> some View {
        navigationTitle(Text(String(title)))
            .navigationBarTitleDisplayMode(displayMode)
    }

    func navigationBarTitle(
        _ title: Text,
        displayMode: NavigationBarItem.TitleDisplayMode = .automatic
    ) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(displayMode)
    }

    func navigationBarTitleDisplayMode(_ displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.navigationTitleDisplayMode = displayMode
        return modified
    }

    func navigationDestination<Data>(
        for data: Data.Type,
        @ViewBuilder destination: @escaping (Data) -> [AnyView]
    ) -> some View where Data: Hashable {
        _ = data
        let registration = NavigationDestinationRegistration { value in
            guard let typedValue = value.base as? Data else {
                return nil
            }

            return destination(typedValue)
        }
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withNavigationDestinationRegistration(registration))
        }
        modified.navigationDestinationRegistrations = [registration]
        return modified
    }

    func navigationDestination(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> [AnyView]
    ) -> some View {
        let presentedDestination = NavigationPresentedDestination(
            destination: {
                isPresented.wrappedValue ? destination() : nil
            },
            dismiss: {
                isPresented.wrappedValue = false
            }
        )
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withNavigationPresentedDestination(presentedDestination))
        }
        modified.navigationPresentedDestinations = [presentedDestination]
        return modified
    }

    func navigationDestination<Item>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> [AnyView]
    ) -> some View where Item: Identifiable {
        let presentedDestination = NavigationPresentedDestination(
            destination: {
                guard let selectedItem = item.wrappedValue else {
                    return nil
                }

                return destination(selectedItem)
            },
            dismiss: {
                item.wrappedValue = nil
            }
        )
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withNavigationPresentedDestination(presentedDestination))
        }
        modified.navigationPresentedDestinations = [presentedDestination]
        return modified
    }

    func tabItem(@ViewBuilder _ label: () -> [AnyView]) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.tabItem = label()
        return modified
    }

    func environment<Value>(_ keyPath: WritableKeyPath<EnvironmentValues, Value>, _ value: Value) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(keyPath, value))
        }
    }

    func preferredColorScheme(_ colorScheme: ColorScheme?) -> some View {
        ModifiedView(content: self) { content, context in
            let resolvedContext: ViewBuildContext
            if let colorScheme {
                resolvedContext = context.withEnvironmentValue(\.colorScheme, colorScheme)
            } else {
                resolvedContext = context
            }

            return content.makeComponent(context: resolvedContext)
        }
    }

    func dynamicTypeSize(_ size: DynamicTypeSize) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.dynamicTypeSize, size))
        }
    }

    func legibilityWeight(_ weight: LegibilityWeight?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.legibilityWeight, weight))
        }
    }

    func headerProminence(_ prominence: Prominence) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.headerProminence, prominence))
        }
    }

    func badge(_ count: Int) -> some View {
        badge(count == 0 ? nil : Text(String(count)))
    }

    func badge<S: StringProtocol>(_ label: S?) -> some View {
        badge(label.map { Text(String($0)) })
    }

    func badge(_ key: LocalizedStringKey?) -> some View {
        badge(key.map { Text($0) })
    }

    func badge(_ label: Text?) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            let rendersIntoTabChrome = (content as? any TaggedViewMetadata)?.anyTabItem != nil
            guard let label, !rendersIntoTabChrome else {
                return component
            }

            return Component { runtime in
                let contentNode = component.makeNode(runtime: runtime)
                let badgeNode = context.makeRetainedBadgeNode(from: [AnyView(label)], runtime: runtime)

                return Controls.stackPanel(
                    stackLayout: .horizontal(spacing: 8, padding: .zero, alignment: .center),
                    isHitTestVisible: contentNode.isHitTestVisible,
                    children: [
                        contentNode,
                        Controls.panel(layoutPriority: 1, isHitTestVisible: false),
                        badgeNode,
                    ]
                )
            }
        }
        modified.badge = label.map { [AnyView($0)] }
        return modified
    }

    func badgeProminence(_ prominence: BadgeProminence) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.badgeProminence, prominence))
        }
    }

    func font(_ font: Font) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withFont(font))
        }
    }

    func font(_ font: Font?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withFont(font))
        }
    }

    func fontDesign(_ design: Font.Design?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withFontDesign(design))
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

    func lineLimit(_ lineLimit: Int, reservesSpace: Bool) -> some View {
        _ = reservesSpace
        return self.lineLimit(lineLimit)
    }

    func lineSpacing(_ lineSpacing: Double) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.lineSpacing, lineSpacing))
        }
    }

    func truncationMode(_ mode: Text.TruncationMode) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTruncationMode(mode))
        }
    }

    func allowsTightening(_ flag: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withAllowsTightening(flag))
        }
    }

    func textCase(_ textCase: Text.Case?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTextCase(textCase))
        }
    }

    func labelsHidden() -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withLabelsHidden(true))
        }
    }

    func controlSize(_ controlSize: ControlSize) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withControlSize(controlSize))
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

    func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        contentShape(.interaction, shape, eoFill: eoFill)
    }

    func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View {
        _ = kind
        _ = shape
        _ = eoFill
        return self
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

    func border(_ style: ForegroundStyle, width: Double = 1, cornerRadius: Double = 0) -> some View {
        border(resolvedStyleColor(from: style), width: width, cornerRadius: cornerRadius)
    }

    func border(_ gradient: LinearGradient, width: Double = 1, cornerRadius: Double = 0) -> some View {
        border(.linearGradient(gradient), width: width, cornerRadius: cornerRadius)
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

    func shadow(radius: Double, x: Double = 0, y: Double = 0) -> some View {
        shadow(color: .black.opacity(0.33), radius: radius, x: x, y: y)
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

    func gridCellColumns(_ count: Int) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            let retainedPriority = Double(max(1, count))
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.layoutPriority = max(childNode.layoutPriority, retainedPriority)
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

    func focusable(_ isFocusable: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isFocusable = isFocusable
                if isFocusable {
                    childNode.isHitTestVisible = true
                }
                return childNode
            }
        }
    }

    func hoverEffect(_ effect: HoverEffect = .automatic, isEnabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                if isEnabled, context.environmentValues.isHoverEffectEnabled {
                    let resolvedEffect = effect == .automatic
                        ? context.environmentValues.defaultHoverEffect ?? effect
                        : effect
                    childNode.hoverEffect = resolvedEffect.retainedEffect
                    childNode.isHoverEffectDisabled = false
                    childNode.isHitTestVisible = true
                } else {
                    childNode.hoverEffect = nil
                    childNode.isHoverEffectDisabled = true
                }
                return childNode
            }
        }
    }

    func defaultHoverEffect(_ effect: HoverEffect?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(\.defaultHoverEffect, effect)
            )
        }
    }

    func hoverEffectDisabled(_ disabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let resolvedContext = context.withEnvironmentValue(
                \.isHoverEffectEnabled,
                context.environmentValues.isHoverEffectEnabled && !disabled
            )
            let child = content.makeComponent(context: resolvedContext)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHoverEffectDisabled = disabled
                if disabled {
                    childNode.hoverEffect = nil
                }
                return childNode
            }
        }
    }

    func focusEffectDisabled(_ disabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isFocusEffectDisabled = disabled
                return childNode
            }
        }
    }

    func redacted(reason: RedactionReasons) -> some View {
        ModifiedView(content: self) { content, context in
            var values = context.environmentValues
            values.redactionReasons.formUnion(reason)
            let resolvedContext = context.withEnvironmentValue(\.redactionReasons, values.redactionReasons)
            let child = content.makeComponent(context: resolvedContext)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.redactionReasons = values.redactionReasons.retainedReasons
                return childNode
            }
        }
    }

    func unredacted() -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(
                context: context.withEnvironmentValue(\.redactionReasons, [])
            )
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.redactionReasons = []
                return childNode
            }
        }
    }

    func privacySensitive(_ sensitive: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(
                context: context.withEnvironmentValue(\.isPrivacySensitive, sensitive)
            )
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isPrivacySensitive = sensitive
                return childNode
            }
        }
    }

    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers))
    }

    func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.keyboardShortcuts = shortcut.map { [$0.retainedBinding] } ?? []
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

    func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View {
        accessibilityLabelText(String(label))
    }

    func accessibilityLabel(_ labelKey: LocalizedStringKey) -> some View {
        accessibilityLabelText(labelKey.resolvedString)
    }

    func accessibilityLabel(_ label: Text) -> some View {
        accessibilityLabelText(label.plainContent)
    }

    private func accessibilityLabelText(_ label: String) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityLabel = label
                return childNode
            }
        }
    }

    func accessibilityValue<S: StringProtocol>(_ value: S) -> some View {
        accessibilityValueText(String(value))
    }

    func accessibilityValue(_ valueKey: LocalizedStringKey) -> some View {
        accessibilityValueText(valueKey.resolvedString)
    }

    func accessibilityValue(_ value: Text) -> some View {
        accessibilityValueText(value.plainContent)
    }

    private func accessibilityValueText(_ value: String) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityValue = value
                return childNode
            }
        }
    }

    func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View {
        accessibilityHintText(String(hint))
    }

    func accessibilityHint(_ hintKey: LocalizedStringKey) -> some View {
        accessibilityHintText(hintKey.resolvedString)
    }

    func accessibilityHint(_ hint: Text) -> some View {
        accessibilityHintText(hint.plainContent)
    }

    private func accessibilityHintText(_ hint: String) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityHint = hint
                return childNode
            }
        }
    }

    func help<S: StringProtocol>(_ text: S) -> some View {
        helpText(String(text))
    }

    func help(_ textKey: LocalizedStringKey) -> some View {
        helpText(textKey.resolvedString)
    }

    func help(_ text: Text) -> some View {
        helpText(text.plainContent)
    }

    private func helpText(_ text: String) -> some View {
        accessibilityHintText(text)
    }

    func accessibilityIdentifier(_ identifier: String) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityIdentifier = identifier
                return childNode
            }
        }
    }

    func accessibilityHidden(_ hidden: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isAccessibilityHidden = hidden
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

    func scrollDisabled(_ disabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isScrollEnabled, !disabled))
        }
    }

    func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isScrollClipDisabled, disabled))
        }
    }

    func scrollContentBackground(_ visibility: Visibility) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.scrollContentBackgroundVisibility, visibility))
        }
    }

    func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = .all) -> some View {
        ModifiedView(content: self) { content, context in
            var resolvedContext = context
            if axes.contains(.horizontal) {
                resolvedContext = resolvedContext.withEnvironmentValue(\.horizontalScrollIndicatorVisibility, visibility)
            }
            if axes.contains(.vertical) {
                resolvedContext = resolvedContext.withEnvironmentValue(\.verticalScrollIndicatorVisibility, visibility)
            }
            return content.makeComponent(context: resolvedContext)
        }
    }

    func listRowBackground<Background: View>(_ view: Background?) -> some View {
        ModifiedView(content: self) { content, context in
            guard let view else {
                return content.makeComponent(context: context)
            }

            let base = content.makeComponent(context: context)
            let background = view.makeComponent(context: context)
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
                    let frame = Rect(origin: .zero, size: bounds.size)
                    if backgroundNode.frame != frame {
                        backgroundNode.frame = frame
                    }
                    if baseNode.frame != frame {
                        baseNode.frame = frame
                    }
                }

                return root
            }
        }
    }

    func listRowBackground(_ color: Color?) -> some View {
        listRowBackgroundStyle(color: color, gradient: nil)
    }

    func listRowBackground(_ gradient: LinearGradient?) -> some View {
        listRowBackgroundStyle(color: nil, gradient: gradient)
    }

    func listRowBackground(_ style: ForegroundStyle?) -> some View {
        guard let style else {
            return listRowBackgroundStyle(color: nil, gradient: nil)
        }

        let fill = resolvedStyleFill(from: style)
        return listRowBackgroundStyle(color: fill.color, gradient: fill.gradient)
    }

    private func listRowBackgroundStyle(color: Color?, gradient: LinearGradient?) -> some View {
        ModifiedView(content: self) { content, context in
            guard color != nil || gradient != nil else {
                return content.makeComponent(context: context)
            }

            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    backgroundColor: color,
                    backgroundGradient: gradient,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
    }

    func listRowInsets(_ insets: EdgeInsets?) -> some View {
        ModifiedView(content: self) { content, context in
            guard let insets else {
                return content.makeComponent(context: context)
            }

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

    func listRowInsets(_ edges: Edge.Set, _ length: Double?) -> some View {
        listRowInsets(
            EdgeInsets(
                top: edges.contains(.top) ? length ?? 16 : 0,
                leading: edges.contains(.leading) ? length ?? 16 : 0,
                bottom: edges.contains(.bottom) ? length ?? 16 : 0,
                trailing: edges.contains(.trailing) ? length ?? 16 : 0
            )
        )
    }

    func listRowSpacing(_ spacing: Double?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.listRowSpacing, spacing))
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

    func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let existingOnAppear = childNode.onAppear
                childNode.onAppear = {
                    existingOnAppear?()
                    Swift.Task(priority: priority) {
                        await action()
                    }
                }
                return childNode
            }
        }
    }

    func task<Value: Equatable>(
        id value: Value,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void,
        fileID: String = #fileID,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        let key = "\(fileID):\(line):\(column):task:\(Value.self)"
        return ModifiedView(content: self) { content, context in
            let launchState = OnChangeObservationRegistry.shared.observe(value: value, key: key, initial: true)
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                guard let launchState else {
                    return childNode
                }

                if launchState.oldValue != launchState.newValue {
                    Swift.Task(priority: priority) {
                        await action()
                    }
                    return childNode
                }

                let existingOnAppear = childNode.onAppear
                childNode.onAppear = {
                    existingOnAppear?()
                    Swift.Task(priority: priority) {
                        await action()
                    }
                }
                return childNode
            }
        }
    }

    func refreshable(action: @escaping @Sendable () async -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(
                    \.refresh,
                    RefreshAction(action: action)
                )
            )
        }
    }

    func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ action: @escaping (Value, Value) -> Void,
        fileID: String = #fileID,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        let key = "\(fileID):\(line):\(column):\(Value.self)"
        return ModifiedView(content: self) { content, context in
            if let change = OnChangeObservationRegistry.shared.observe(value: value, key: key, initial: initial) {
                action(change.oldValue, change.newValue)
            }

            return content.makeComponent(context: context)
        }
    }

    func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        perform action: @escaping (Value) -> Void,
        fileID: String = #fileID,
        line: Int = #line,
        column: Int = #column
    ) -> some View {
        onChange(
            of: value,
            initial: initial,
            { _, newValue in
                action(newValue)
            },
            fileID: fileID,
            line: line,
            column: column
        )
    }

    func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                attachSubmitHandler(
                    to: childNode,
                    triggers: triggers,
                    action: action,
                    invalidate: context.invalidate
                )
                return childNode
            }
        }
    }

    func submitLabel(_ submitLabel: SubmitLabel) -> some View {
        _ = submitLabel
        return ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
    }

    func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true

                let existingOnPointerEnter = childNode.onPointerEnter
                childNode.onPointerEnter = {
                    existingOnPointerEnter?()
                    action(true)
                }

                let existingOnPointerExit = childNode.onPointerExit
                childNode.onPointerExit = {
                    existingOnPointerExit?()
                    action(false)
                }

                return childNode
            }
        }
    }

    func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            let requiredTapCount = max(1, count)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true
                var tapProgress = 0

                let existingOnPointerUpInside = childNode.onPointerUpInside
                childNode.onPointerUpInside = {
                    existingOnPointerUpInside?()
                    tapProgress += 1
                    guard tapProgress >= requiredTapCount else {
                        return
                    }

                    tapProgress = 0
                    action()
                }

                let existingOnPointerUpOutside = childNode.onPointerUpOutside
                childNode.onPointerUpOutside = {
                    existingOnPointerUpOutside?()
                    tapProgress = 0
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

    func id<ID: Hashable>(_ identifier: ID) -> some View {
        id(String(describing: identifier))
    }

    func tag<Tag: Hashable>(_ tag: Tag) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.selectionTag = AnyHashable(tag)
        return modified
    }

    func animation(_ animation: Animation?) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                guard let animation, !context.accessibilityReduceMotion else {
                    return node
                }

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
                    duration: animation.duration,
                    easing: animation.easing
                )
                if let bg = node.backgroundColor {
                    node.animationStates[.backgroundColor] = AnimationState(
                        startValue: 0,
                        endValue: 0,
                        startTime: now,
                        duration: animation.duration,
                        easing: animation.easing
                    )
                    // Store previous color for interpolation.
                    node.previousPropertyValues?.backgroundColor = bg
                }

                return node
            }
        }
    }

    /// Attach an animation context to this view.  When properties (opacity,
    /// background color) change between rebuilds, the runtime will
    /// interpolate between the old and new values over the given duration
    /// using the specified easing curve.
    func animation(_ duration: Double = 0.25, easing: AnimationEasing = .easeInOut) -> some View {
        animation(Animation(duration: duration, easing: easing))
    }

    func animation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        self.animation(animation)
    }
}

@MainActor
private func attachSubmitHandler(
    to node: ViewNode,
    triggers: SubmitTriggers,
    action: @escaping () -> Void,
    invalidate: @escaping () -> Void
) {
    if node.onKeyDown != nil {
        let existingOnKeyDown = node.onKeyDown
        node.onKeyDown = { event in
            guard event.key == .enter, triggers.submitsTextInput else {
                existingOnKeyDown?(event)
                return
            }

            action()
            invalidate()
        }
    }

    for child in node.children {
        attachSubmitHandler(to: child, triggers: triggers, action: action, invalidate: invalidate)
    }
}
