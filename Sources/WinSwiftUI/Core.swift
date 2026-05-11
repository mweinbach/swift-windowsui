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

public struct LocalizedStringResource: Sendable, Equatable, Hashable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, CustomStringConvertible {
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

public extension String {
    init(localized resource: LocalizedStringResource) {
        self = resource.resolvedString
    }
}

public struct ImageResource: Equatable, Hashable, @unchecked Sendable {
    public var name: String
    public var bundle: Bundle

    public init(name: String, bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }

    public static func == (lhs: ImageResource, rhs: ImageResource) -> Bool {
        lhs.name == rhs.name && lhs.bundle.bundlePath == rhs.bundle.bundlePath
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(bundle.bundlePath)
    }
}

public struct ColorResource: Equatable, Hashable, @unchecked Sendable {
    public var name: String
    public var bundle: Bundle

    public init(name: String, bundle: Bundle) {
        self.name = name
        self.bundle = bundle
    }

    public static func == (lhs: ColorResource, rhs: ColorResource) -> Bool {
        lhs.name == rhs.name && lhs.bundle.bundlePath == rhs.bundle.bundlePath
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(bundle.bundlePath)
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

public struct Transaction: Sendable {
    public var animation: Animation?
    public var disablesAnimations: Bool

    public init(animation: Animation? = nil) {
        self.animation = animation
        self.disablesAnimations = false
    }
}

@discardableResult
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try body()
}

@discardableResult
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
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

public struct PopoverAttachmentAnchor: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case rect(UnitPoint)
        case point(UnitPoint)
    }

    public var kind: Kind

    public init(_ kind: Kind = .rect(.center)) {
        self.kind = kind
    }

    public static func rect(_ anchor: UnitPoint = .center) -> PopoverAttachmentAnchor {
        PopoverAttachmentAnchor(.rect(anchor))
    }

    public static func point(_ anchor: UnitPoint) -> PopoverAttachmentAnchor {
        PopoverAttachmentAnchor(.point(anchor))
    }
}

@MainActor
public struct Alert {
    @MainActor
    public struct Button {
        let label: Text
        let role: ButtonRole?
        let action: (@MainActor () -> Void)?

        private init(label: Text, role: ButtonRole?, action: (@MainActor () -> Void)?) {
            self.label = label
            self.role = role
            self.action = action
        }

        public static func `default`(_ label: Text) -> Button {
            Button(label: label, role: nil, action: nil)
        }

        public static func `default`(_ label: Text, action: @escaping @MainActor () -> Void) -> Button {
            Button(label: label, role: nil, action: action)
        }

        public static func cancel() -> Button {
            Button(label: Text("Cancel"), role: .cancel, action: nil)
        }

        public static func cancel(_ label: Text) -> Button {
            Button(label: label, role: .cancel, action: nil)
        }

        public static func cancel(_ label: Text, action: @escaping @MainActor () -> Void) -> Button {
            Button(label: label, role: .cancel, action: action)
        }

        public static func destructive(_ label: Text) -> Button {
            Button(label: label, role: .destructive, action: nil)
        }

        public static func destructive(_ label: Text, action: @escaping @MainActor () -> Void) -> Button {
            Button(label: label, role: .destructive, action: action)
        }
    }

    let title: Text
    let message: Text?
    let buttons: [Button]

    public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
        self.title = title
        self.message = message
        self.buttons = [dismissButton ?? .default(Text("OK"))]
    }

    public init(title: Text, message: Text? = nil, primaryButton: Button, secondaryButton: Button) {
        self.title = title
        self.message = message
        self.buttons = [primaryButton, secondaryButton]
    }
}

@MainActor
public struct ActionSheet {
    @MainActor
    public struct Button {
        let label: Text
        let role: ButtonRole?
        let action: (@MainActor () -> Void)?

        private init(label: Text, role: ButtonRole?, action: (@MainActor () -> Void)?) {
            self.label = label
            self.role = role
            self.action = action
        }

        public static func `default`(_ label: Text) -> Button {
            Button(label: label, role: nil, action: nil)
        }

        public static func `default`(_ label: Text, action: @escaping @MainActor () -> Void) -> Button {
            Button(label: label, role: nil, action: action)
        }

        public static func cancel() -> Button {
            Button(label: Text("Cancel"), role: .cancel, action: nil)
        }

        public static func cancel(_ label: Text) -> Button {
            Button(label: label, role: .cancel, action: nil)
        }

        public static func cancel(_ label: Text, action: @escaping @MainActor () -> Void) -> Button {
            Button(label: label, role: .cancel, action: action)
        }

        public static func destructive(_ label: Text) -> Button {
            Button(label: label, role: .destructive, action: nil)
        }

        public static func destructive(_ label: Text, action: @escaping @MainActor () -> Void) -> Button {
            Button(label: label, role: .destructive, action: action)
        }
    }

    let title: Text
    let message: Text?
    let buttons: [Button]

    public init(title: Text, message: Text? = nil, buttons: [Button] = [.cancel()]) {
        self.title = title
        self.message = message
        self.buttons = buttons
    }
}

public struct MatchedGeometryProperties: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let position = MatchedGeometryProperties(rawValue: 1 << 0)
    public static let size = MatchedGeometryProperties(rawValue: 1 << 1)
    public static let frame: MatchedGeometryProperties = [.position, .size]
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

public struct NavigationViewStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case stack
        case doubleColumn
        case columns
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = NavigationViewStyle(kind: .automatic)
    public static let stack = NavigationViewStyle(kind: .stack)
    public static let doubleColumn = NavigationViewStyle(kind: .doubleColumn)
    public static let columns = NavigationViewStyle(kind: .columns)
}

public struct DefaultNavigationViewStyle: Sendable, Equatable {
    public init() {}
}

public struct StackNavigationViewStyle: Sendable, Equatable {
    public init() {}
}

public struct DoubleColumnNavigationViewStyle: Sendable, Equatable {
    public init() {}
}

public struct ColumnsNavigationViewStyle: Sendable, Equatable {
    public init() {}
}

public struct NavigationSplitViewStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case balanced
        case prominentDetail
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = NavigationSplitViewStyle(kind: .automatic)
    public static let balanced = NavigationSplitViewStyle(kind: .balanced)
    public static let prominentDetail = NavigationSplitViewStyle(kind: .prominentDetail)
}

public struct AutomaticNavigationSplitViewStyle: Sendable, Equatable {
    public init() {}
}

public struct BalancedNavigationSplitViewStyle: Sendable, Equatable {
    public init() {}
}

public struct ProminentDetailNavigationSplitViewStyle: Sendable, Equatable {
    public init() {}
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
public protocol DynamicProperty {
    mutating func update()
}

public extension DynamicProperty {
    mutating func update() {}
}

@MainActor
@propertyWrapper
public struct Namespace: DynamicProperty {
    public struct ID: Sendable, Hashable, CustomStringConvertible {
        fileprivate let rawValue: String

        fileprivate init(rawValue: String = UUID().uuidString) {
            self.rawValue = rawValue
        }

        public var description: String {
            rawValue
        }
    }

    @MainActor
    private final class Storage {
        let id = ID()
    }

    private let storage: Storage

    public init() {
        self.storage = Storage()
    }

    public var wrappedValue: ID {
        storage.id
    }

    public var projectedValue: ID {
        storage.id
    }
}

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
public struct ObservedObject<ObjectType: ObservableObject>: DynamicProperty {
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

public enum TextSelectionAffinity: Sendable, Equatable, Hashable {
    case automatic
    case upstream
    case downstream

    var retainedAffinity: RetainedTextSelectionAffinity {
        switch self {
        case .automatic:
            return .automatic
        case .upstream:
            return .upstream
        case .downstream:
            return .downstream
        }
    }
}

public struct TextSelection: Sendable, Equatable, Hashable {
    public enum Indices: Sendable, Equatable, Hashable {
        case selection(Range<String.Index>)
        case multiSelection(RangeSet<String.Index>)
    }

    public var indices: Indices
    public var affinity: TextSelectionAffinity

    public init(insertionPoint: String.Index) {
        self.indices = .selection(insertionPoint..<insertionPoint)
        self.affinity = .automatic
    }

    public init(range: Range<String.Index>) {
        self.indices = .selection(range)
        self.affinity = .automatic
    }

    public init(ranges: RangeSet<String.Index>) {
        self.indices = .multiSelection(ranges)
        self.affinity = .automatic
    }

    init(indices: Indices, affinity: TextSelectionAffinity) {
        self.indices = indices
        self.affinity = affinity
    }

    public var isInsertion: Bool {
        switch indices {
        case .selection(let range):
            return range.isEmpty
        case .multiSelection(let ranges):
            return ranges.ranges.isEmpty
        }
    }

    func retainedSelection(in text: String) -> RetainedTextSelection {
        RetainedTextSelection(
            indices: retainedIndices(in: text),
            affinity: affinity.retainedAffinity
        )
    }

    func caretOffset(in text: String) -> Int {
        switch indices {
        case .selection(let range):
            return clampedTextSelectionOffset(for: range.upperBound, in: text)
        case .multiSelection(let ranges):
            return ranges.ranges.last.map { clampedTextSelectionOffset(for: $0.upperBound, in: text) } ?? text.count
        }
    }

    func editableSelectedOffsetRange(in text: String) -> Range<Int>? {
        guard case .selection(let range) = indices, !range.isEmpty else {
            return nil
        }

        let lowerBound = clampedTextSelectionOffset(for: range.lowerBound, in: text)
        let upperBound = clampedTextSelectionOffset(for: range.upperBound, in: text)
        guard lowerBound < upperBound else {
            return nil
        }
        return lowerBound..<upperBound
    }

    private func retainedIndices(in text: String) -> RetainedTextSelection.Indices {
        switch indices {
        case .selection(let range):
            if range.isEmpty {
                return .insertionPoint(clampedTextSelectionOffset(for: range.lowerBound, in: text))
            }
            return .range(
                clampedTextSelectionOffset(for: range.lowerBound, in: text)..<clampedTextSelectionOffset(for: range.upperBound, in: text)
            )
        case .multiSelection(let ranges):
            return .ranges(
                ranges.ranges.map {
                    clampedTextSelectionOffset(for: $0.lowerBound, in: text)..<clampedTextSelectionOffset(for: $0.upperBound, in: text)
                }
            )
        }
    }

    static func insertion(at offset: Int, in text: String, affinity: TextSelectionAffinity) -> TextSelection {
        let index = textIndex(at: offset, in: text)
        return TextSelection(indices: .selection(index..<index), affinity: affinity)
    }
}

private func clampedTextSelectionOffset(for index: String.Index, in text: String) -> Int {
    let offset = text.distance(from: text.startIndex, to: index)
    return min(max(0, offset), text.count)
}

private func textIndex(at offset: Int, in text: String) -> String.Index {
    text.index(text.startIndex, offsetBy: min(max(0, offset), text.count))
}

public struct UIKeyboardType: RawRepresentable, Sendable, Equatable, Hashable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let `default` = UIKeyboardType(rawValue: 0)
    public static let asciiCapable = UIKeyboardType(rawValue: 1)
    public static let numbersAndPunctuation = UIKeyboardType(rawValue: 2)
    public static let URL = UIKeyboardType(rawValue: 3)
    public static let numberPad = UIKeyboardType(rawValue: 4)
    public static let phonePad = UIKeyboardType(rawValue: 5)
    public static let namePhonePad = UIKeyboardType(rawValue: 6)
    public static let emailAddress = UIKeyboardType(rawValue: 7)
    public static let decimalPad = UIKeyboardType(rawValue: 8)
    public static let twitter = UIKeyboardType(rawValue: 9)
    public static let webSearch = UIKeyboardType(rawValue: 10)
    public static let asciiCapableNumberPad = UIKeyboardType(rawValue: 11)
    public static let alphabet = UIKeyboardType(rawValue: 1)

    var retainedKeyboardType: RetainedKeyboardType {
        if self == .default {
            return .default
        } else if self == .asciiCapable {
            return .asciiCapable
        } else if self == .numbersAndPunctuation {
            return .numbersAndPunctuation
        } else if self == .URL {
            return .URL
        } else if self == .numberPad {
            return .numberPad
        } else if self == .phonePad {
            return .phonePad
        } else if self == .namePhonePad {
            return .namePhonePad
        } else if self == .emailAddress {
            return .emailAddress
        } else if self == .decimalPad {
            return .decimalPad
        } else if self == .twitter {
            return .twitter
        } else if self == .webSearch {
            return .webSearch
        } else if self == .asciiCapableNumberPad {
            return .asciiCapableNumberPad
        } else {
            return .default
        }
    }
}

public struct WritingToolsBehavior: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case complete
        case limited
        case disabled
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = WritingToolsBehavior(kind: .automatic)
    public static let complete = WritingToolsBehavior(kind: .complete)
    public static let limited = WritingToolsBehavior(kind: .limited)
    public static let disabled = WritingToolsBehavior(kind: .disabled)

    var retainedBehavior: RetainedWritingToolsBehavior {
        switch kind {
        case .automatic:
            return .automatic
        case .complete:
            return .complete
        case .limited:
            return .limited
        case .disabled:
            return .disabled
        }
    }
}

public struct TextInputDictationActivation: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case onLook
        case onSelect
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let onLook = TextInputDictationActivation(kind: .onLook)
    public static let onSelect = TextInputDictationActivation(kind: .onSelect)

    var retainedActivation: RetainedTextInputDictationActivation {
        switch kind {
        case .onLook:
            return .onLook
        case .onSelect:
            return .onSelect
        }
    }
}

public struct TextInputDictationBehavior: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case preventDictation
        case inline(TextInputDictationActivation)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = TextInputDictationBehavior(kind: .automatic)
    public static let preventDictation = TextInputDictationBehavior(kind: .preventDictation)

    public static func inline(activation: TextInputDictationActivation) -> TextInputDictationBehavior {
        TextInputDictationBehavior(kind: .inline(activation))
    }

    var retainedBehavior: RetainedTextInputDictationBehavior {
        switch kind {
        case .automatic:
            return .automatic
        case .preventDictation:
            return .preventDictation
        case .inline(let activation):
            return .inline(activation: activation.retainedActivation)
        }
    }
}

public struct NSTextContentType: RawRepresentable, Sendable, Equatable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public static let username = NSTextContentType(rawValue: "username")
    public static let password = NSTextContentType(rawValue: "password")
    public static let newPassword = NSTextContentType(rawValue: "newPassword")
    public static let oneTimeCode = NSTextContentType(rawValue: "oneTimeCode")
    public static let emailAddress = NSTextContentType(rawValue: "emailAddress")
    public static let telephoneNumber = NSTextContentType(rawValue: "telephoneNumber")
    public static let URL = NSTextContentType(rawValue: "URL")
    public static let name = NSTextContentType(rawValue: "name")
    public static let namePrefix = NSTextContentType(rawValue: "namePrefix")
    public static let givenName = NSTextContentType(rawValue: "givenName")
    public static let middleName = NSTextContentType(rawValue: "middleName")
    public static let familyName = NSTextContentType(rawValue: "familyName")
    public static let nameSuffix = NSTextContentType(rawValue: "nameSuffix")
    public static let nickname = NSTextContentType(rawValue: "nickname")
    public static let organizationName = NSTextContentType(rawValue: "organizationName")
    public static let jobTitle = NSTextContentType(rawValue: "jobTitle")
    public static let location = NSTextContentType(rawValue: "location")
    public static let fullStreetAddress = NSTextContentType(rawValue: "fullStreetAddress")
    public static let streetAddressLine1 = NSTextContentType(rawValue: "streetAddressLine1")
    public static let streetAddressLine2 = NSTextContentType(rawValue: "streetAddressLine2")
    public static let addressCity = NSTextContentType(rawValue: "addressCity")
    public static let addressState = NSTextContentType(rawValue: "addressState")
    public static let addressCityAndState = NSTextContentType(rawValue: "addressCityAndState")
    public static let postalCode = NSTextContentType(rawValue: "postalCode")
    public static let countryName = NSTextContentType(rawValue: "countryName")
    public static let creditCardNumber = NSTextContentType(rawValue: "creditCardNumber")
    public static let creditCardName = NSTextContentType(rawValue: "creditCardName")
    public static let creditCardGivenName = NSTextContentType(rawValue: "creditCardGivenName")
    public static let creditCardMiddleName = NSTextContentType(rawValue: "creditCardMiddleName")
    public static let creditCardFamilyName = NSTextContentType(rawValue: "creditCardFamilyName")
    public static let creditCardExpiration = NSTextContentType(rawValue: "creditCardExpiration")
    public static let creditCardExpirationMonth = NSTextContentType(rawValue: "creditCardExpirationMonth")
    public static let creditCardExpirationYear = NSTextContentType(rawValue: "creditCardExpirationYear")
    public static let creditCardSecurityCode = NSTextContentType(rawValue: "creditCardSecurityCode")

    var retainedContentType: RetainedTextContentType {
        RetainedTextContentType(rawValue: rawValue)
    }
}

public enum Visibility: Sendable, Equatable {
    case automatic
    case visible
    case hidden

    var hidesRetainedScrollContentBackground: Bool {
        self == .hidden
    }

    var retainedWritingToolsAffordanceVisibility: RetainedWritingToolsAffordanceVisibility {
        switch self {
        case .automatic:
            return .automatic
        case .visible:
            return .visible
        case .hidden:
            return .hidden
        }
    }
}

public struct ContentMarginPlacement: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case scrollContent
        case scrollIndicators
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ContentMarginPlacement(kind: .automatic)
    public static let scrollContent = ContentMarginPlacement(kind: .scrollContent)
    public static let scrollIndicators = ContentMarginPlacement(kind: .scrollIndicators)
}

struct ContentMarginEdges: Sendable, Equatable {
    var top: CGFloat?
    var leading: CGFloat?
    var bottom: CGFloat?
    var trailing: CGFloat?

    static let empty = ContentMarginEdges()

    mutating func set(_ edges: Edge.Set, to length: CGFloat?) {
        if edges.contains(.top) {
            top = length
        }
        if edges.contains(.leading) {
            leading = length
        }
        if edges.contains(.bottom) {
            bottom = length
        }
        if edges.contains(.trailing) {
            trailing = length
        }
    }

    func applying(to insets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: top ?? insets.top,
            leading: leading ?? insets.leading,
            bottom: bottom ?? insets.bottom,
            trailing: trailing ?? insets.trailing
        )
    }
}

struct ContentMarginValues: Sendable, Equatable {
    var automatic = ContentMarginEdges.empty
    var scrollContent = ContentMarginEdges.empty
    var scrollIndicators = ContentMarginEdges.empty

    static let empty = ContentMarginValues()

    mutating func set(_ edges: Edge.Set, to length: CGFloat?, for placement: ContentMarginPlacement) {
        switch placement.kind {
        case .automatic:
            automatic.set(edges, to: length)
        case .scrollContent:
            scrollContent.set(edges, to: length)
        case .scrollIndicators:
            scrollIndicators.set(edges, to: length)
        }
    }

    func insets(for placement: ContentMarginPlacement, defaultInsets: EdgeInsets) -> EdgeInsets {
        var resolved = automatic.applying(to: defaultInsets)
        switch placement.kind {
        case .automatic:
            return resolved
        case .scrollContent:
            resolved = scrollContent.applying(to: resolved)
        case .scrollIndicators:
            resolved = scrollIndicators.applying(to: resolved)
        }
        return resolved
    }
}

public struct ScrollAnchorRole: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case initialOffset
        case sizeChanges
        case alignment
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let initialOffset = ScrollAnchorRole(kind: .initialOffset)
    public static let sizeChanges = ScrollAnchorRole(kind: .sizeChanges)
    public static let alignment = ScrollAnchorRole(kind: .alignment)
}

private enum ScrollAnchorAssignment: Sendable, Equatable {
    case inherited
    case assigned(UnitPoint?)

    var assignedAnchor: UnitPoint?? {
        switch self {
        case .inherited:
            return nil
        case .assigned(let anchor):
            return .some(anchor)
        }
    }
}

struct DefaultScrollAnchorValues: Sendable, Equatable {
    private var all: ScrollAnchorAssignment = .inherited
    private var initialOffset: ScrollAnchorAssignment = .inherited
    private var sizeChanges: ScrollAnchorAssignment = .inherited
    private var alignment: ScrollAnchorAssignment = .inherited

    static let empty = DefaultScrollAnchorValues()

    mutating func set(_ anchor: UnitPoint?) {
        all = .assigned(anchor)
    }

    mutating func set(_ anchor: UnitPoint?, for role: ScrollAnchorRole) {
        switch role.kind {
        case .initialOffset:
            initialOffset = .assigned(anchor)
        case .sizeChanges:
            sizeChanges = .assigned(anchor)
        case .alignment:
            alignment = .assigned(anchor)
        }
    }

    func anchor(for role: ScrollAnchorRole) -> UnitPoint? {
        let roleAssignment: ScrollAnchorAssignment
        switch role.kind {
        case .initialOffset:
            roleAssignment = initialOffset
        case .sizeChanges:
            roleAssignment = sizeChanges
        case .alignment:
            roleAssignment = alignment
        }

        if let anchor = roleAssignment.assignedAnchor {
            return anchor
        }
        if let anchor = all.assignedAnchor {
            return anchor
        }
        return nil
    }
}

public struct PresentationDetent: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case medium
        case large
        case height(Double)
        case fraction(Double)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let medium = PresentationDetent(kind: .medium)
    public static let large = PresentationDetent(kind: .large)

    public static func height(_ height: Double) -> PresentationDetent {
        PresentationDetent(kind: .height(height))
    }

    public static func fraction(_ fraction: Double) -> PresentationDetent {
        PresentationDetent(kind: .fraction(fraction))
    }
}

private extension PresentationDetent {
    var retainedDetent: RetainedPresentationDetent {
        switch kind {
        case .medium:
            return .medium
        case .large:
            return .large
        case let .height(height):
            return .height(height)
        case let .fraction(fraction):
            return .fraction(fraction)
        }
    }
}

public struct PresentationAdaptation: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case none
        case popover
        case sheet
        case fullScreenCover
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PresentationAdaptation(kind: .automatic)
    public static let none = PresentationAdaptation(kind: .none)
    public static let popover = PresentationAdaptation(kind: .popover)
    public static let sheet = PresentationAdaptation(kind: .sheet)
    public static let fullScreenCover = PresentationAdaptation(kind: .fullScreenCover)
}

private extension PresentationAdaptation {
    var retainedAdaptation: RetainedPresentationAdaptation {
        switch kind {
        case .automatic:
            return .automatic
        case .none:
            return .none
        case .popover:
            return .popover
        case .sheet:
            return .sheet
        case .fullScreenCover:
            return .fullScreenCover
        }
    }
}

public struct PresentationContentInteraction: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case resizes
        case scrolls
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PresentationContentInteraction(kind: .automatic)
    public static let resizes = PresentationContentInteraction(kind: .resizes)
    public static let scrolls = PresentationContentInteraction(kind: .scrolls)
}

private extension PresentationContentInteraction {
    var retainedContentInteraction: RetainedPresentationContentInteraction {
        switch kind {
        case .automatic:
            return .automatic
        case .resizes:
            return .resizes
        case .scrolls:
            return .scrolls
        }
    }
}

public struct PresentationBackgroundInteraction: Sendable, Equatable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case disabled
        case enabled
        case enabledUpThrough(PresentationDetent)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PresentationBackgroundInteraction(kind: .automatic)
    public static let disabled = PresentationBackgroundInteraction(kind: .disabled)
    public static let enabled = PresentationBackgroundInteraction(kind: .enabled)

    public static func enabled(upThrough detent: PresentationDetent) -> PresentationBackgroundInteraction {
        PresentationBackgroundInteraction(kind: .enabledUpThrough(detent))
    }

    var allowsRetainedBackgroundInteraction: Bool {
        switch kind {
        case .enabled, .enabledUpThrough:
            return true
        case .automatic, .disabled:
            return false
        }
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

public enum HoverPhase: Sendable, Equatable {
    case active(CGPoint)
    case ended
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

public struct BackgroundProminence: Sendable, Equatable, Hashable {
    private enum Level: Sendable, Equatable, Hashable {
        case standard
        case increased
    }

    private let level: Level

    private init(_ level: Level) {
        self.level = level
    }

    public static let standard = BackgroundProminence(.standard)
    public static let increased = BackgroundProminence(.increased)
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

public protocol FocusedValueKey {
    associatedtype Value
}

private struct FocusedObjectKey<ObjectType: ObservableObject>: FocusedValueKey {
    typealias Value = ObjectType
}

public struct FocusedValues: @unchecked Sendable {
    private var values: [ObjectIdentifier: Any]

    public init() {
        self.values = [:]
    }

    public subscript<Key: FocusedValueKey>(_ key: Key.Type) -> Key.Value? {
        get {
            values[ObjectIdentifier(key)] as? Key.Value
        }
        set {
            if let newValue {
                values[ObjectIdentifier(key)] = newValue
            } else {
                values.removeValue(forKey: ObjectIdentifier(key))
            }
        }
    }

    public func focusedObject<ObjectType: ObservableObject>(
        _ type: ObjectType.Type = ObjectType.self
    ) -> ObjectType? {
        self[FocusedObjectKey<ObjectType>.self]
    }

    public mutating func setFocusedObject<ObjectType: ObservableObject>(
        _ object: ObjectType?,
        for type: ObjectType.Type = ObjectType.self
    ) {
        self[FocusedObjectKey<ObjectType>.self] = object
    }
}

private struct EnvironmentObjectKey<ObjectType: ObservableObject> {}

public struct EnvironmentObjectValues: @unchecked Sendable {
    private var values: [ObjectIdentifier: Any]

    public init() {
        self.values = [:]
    }

    public func object<ObjectType: ObservableObject>(
        _ type: ObjectType.Type = ObjectType.self
    ) -> ObjectType? {
        values[ObjectIdentifier(EnvironmentObjectKey<ObjectType>.self)] as? ObjectType
    }

    public mutating func setObject<ObjectType: ObservableObject>(
        _ object: ObjectType,
        for type: ObjectType.Type = ObjectType.self
    ) {
        values[ObjectIdentifier(EnvironmentObjectKey<ObjectType>.self)] = object
    }
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

public struct DismissSearchAction: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    public init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction() {
        handler()
    }

    public static let noop = DismissSearchAction {}
}

public struct RenameAction: @unchecked Sendable {
    private let handler: () -> Void

    public init(action: @escaping () -> Void) {
        self.handler = action
    }

    @MainActor
    public func callAsFunction() {
        handler()
    }
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

public struct WindowActionPayload: @unchecked Sendable, Equatable {
    public var id: String?
    public var value: AnyHashable?

    public init(id: String? = nil, value: AnyHashable? = nil) {
        self.id = id
        self.value = value
    }
}

public struct OpenWindowAction: @unchecked Sendable {
    private let handler: @MainActor (_ payload: WindowActionPayload) -> Void

    public init(handler: @escaping @MainActor (_ id: String?) -> Void) {
        self.handler = { payload in handler(payload.id) }
    }

    public init(payloadHandler: @escaping @MainActor (_ payload: WindowActionPayload) -> Void) {
        self.handler = payloadHandler
    }

    @MainActor
    public func callAsFunction(id: String) {
        handler(WindowActionPayload(id: id))
    }

    @MainActor
    public func callAsFunction<Value>(id: String, value: Value) where Value: Codable, Value: Hashable {
        handler(WindowActionPayload(id: id, value: AnyHashable(value)))
    }

    @MainActor
    public func callAsFunction<Value>(value: Value) where Value: Codable, Value: Hashable {
        handler(WindowActionPayload(value: AnyHashable(value)))
    }

    public static let noop = OpenWindowAction(handler: { _ in })
}

public struct DismissWindowAction: @unchecked Sendable {
    private let handler: @MainActor (_ payload: WindowActionPayload) -> Void

    public init(handler: @escaping @MainActor (_ id: String?) -> Void) {
        self.handler = { payload in handler(payload.id) }
    }

    public init(payloadHandler: @escaping @MainActor (_ payload: WindowActionPayload) -> Void) {
        self.handler = payloadHandler
    }

    @MainActor
    public func callAsFunction() {
        handler(WindowActionPayload())
    }

    @MainActor
    public func callAsFunction(id: String) {
        handler(WindowActionPayload(id: id))
    }

    @MainActor
    public func callAsFunction<Value>(id: String, value: Value) where Value: Codable, Value: Hashable {
        handler(WindowActionPayload(id: id, value: AnyHashable(value)))
    }

    @MainActor
    public func callAsFunction<Value>(value: Value) where Value: Codable, Value: Hashable {
        handler(WindowActionPayload(value: AnyHashable(value)))
    }

    public static let noop = DismissWindowAction(handler: { _ in })
}

public struct OpenSettingsAction: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    public init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction() {
        handler()
    }

    public static let noop = OpenSettingsAction {}
}

public struct RequestReviewAction: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    public init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction() {
        handler()
    }

    public static let noop = RequestReviewAction {}
}

public struct SearchFieldPlacement: Sendable, Equatable, Hashable {
    public struct NavigationBarDrawerDisplayMode: Sendable, Equatable, Hashable {
        private let rawValue: String

        private init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public static let automatic = NavigationBarDrawerDisplayMode("automatic")
        public static let always = NavigationBarDrawerDisplayMode("always")
    }

    private enum Storage: Sendable, Equatable, Hashable {
        case automatic
        case navigationBarDrawer(NavigationBarDrawerDisplayMode?)
        case sidebar
        case toolbar
    }

    private let storage: Storage

    private init(_ storage: Storage) {
        self.storage = storage
    }

    public static let automatic = SearchFieldPlacement(.automatic)
    public static let navigationBarDrawer = SearchFieldPlacement(.navigationBarDrawer(nil))
    public static var sidebar: SearchFieldPlacement {
        SearchFieldPlacement(.sidebar)
    }
    public static let toolbar = SearchFieldPlacement(.toolbar)

    public static func navigationBarDrawer(
        displayMode: NavigationBarDrawerDisplayMode
    ) -> SearchFieldPlacement {
        SearchFieldPlacement(.navigationBarDrawer(displayMode))
    }
}

struct TextDecorationSetting: Sendable {
    var isActive: Bool
    var pattern: Text.LineStyle.Pattern
    var color: Color?
}

public struct EnvironmentValues: @unchecked Sendable {
    public var colorScheme: ColorScheme
    public var colorSchemeContrast: ColorSchemeContrast
    public var scenePhase: ScenePhase
    public var controlActiveState: ControlActiveState
    public var appearsActive: Bool
    public var supportsMultipleWindows: Bool
    public var isPresented: Bool
    public var isSceneCaptured: Bool
    public var isTabBarShowingSections: Bool
    public var editMode: Binding<EditMode>?
    public var isFocused: Bool
    public var legibilityWeight: LegibilityWeight?
    public var displayScale: Double
    public var pixelLength: Double
    public var accessibilityAssistiveAccessEnabled: Bool
    public var accessibilityDimFlashingLights: Bool
    public var accessibilityDifferentiateWithoutColor: Bool
    public var accessibilityEnabled: Bool
    public var accessibilityInvertColors: Bool
    public var accessibilityLargeContentViewerEnabled: Bool
    public var accessibilityPlayAnimatedImages: Bool
    public var accessibilityPrefersHeadAnchorAlternative: Bool
    public var accessibilityQuickActionsEnabled: Bool
    public var accessibilityReduceHighlightingEffects: Bool
    public var accessibilityReduceMotion: Bool
    public var accessibilityReduceTransparency: Bool
    public var accessibilityShowButtonShapes: Bool
    public var accessibilityShowBorders: Bool
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
    var fontItalic: Bool?
    var fontMonospacedDigits: Bool
    var underlineStyle: TextDecorationSetting?
    var strikethroughStyle: TextDecorationSetting?
    public var multilineTextAlignment: TextAlignment
    public var lineLimit: Int?
    var minimumLineLimit: Int?
    var lineLimitReservesSpace: Bool
    public var lineSpacing: Double?
    public var truncationMode: Text.TruncationMode?
    public var minimumScaleFactor: CGFloat
    public var allowsTightening: Bool
    public var textCase: Text.Case?
    public var textSelectability: TextSelectability?
    public var textSelectionAffinity: TextSelectionAffinity
    public var imageScale: Image.Scale
    public var symbolRenderingMode: SymbolRenderingMode?
    public var symbolVariants: SymbolVariants
    public var controlSize: ControlSize
    public var labelStyle: LabelStyle
    public var labeledContentStyle: LabeledContentStyle
    public var formStyle: FormStyle
    public var groupBoxStyle: GroupBoxStyle
    public var disclosureGroupStyle: DisclosureGroupStyle
    public var menuStyle: MenuStyle
    public var controlGroupStyle: ControlGroupStyle
    public var progressViewStyle: ProgressViewStyle
    public var gaugeStyle: GaugeStyle
    public var datePickerStyle: DatePickerStyle
    public var tabViewStyle: TabViewStyle
    public var indexViewStyle: IndexViewStyle
    public var toggleStyle: ToggleStyle
    public var textFieldStyle: TextFieldStyle
    public var submitLabel: SubmitLabel
    public var contentTransition: ContentTransition
    public var contentTransitionAddsDrawingGroup: Bool
    public var listStyle: ListStyle
    public var textInputAutocapitalization: TextInputAutocapitalization?
    public var isAutocorrectionDisabled: Bool
    var textContentType: NSTextContentType?
    var keyboardType: UIKeyboardType
    var textInputCompletion: String?
    var textInputSuggestions: [AnyView]?
    public var writingToolsBehavior: WritingToolsBehavior?
    public var writingToolsAffordanceVisibility: Visibility
    var searchDictationBehavior: TextInputDictationBehavior?
    var isFindDisabled: Bool
    var isReplaceDisabled: Bool
    var isFindNavigatorPresented: Bool
    public var isScrollEnabled: Bool
    public var defaultHoverEffect: HoverEffect?
    public var isHoverEffectEnabled: Bool
    public var isFocusEffectEnabled: Bool
    public var buttonRepeatBehavior: ButtonRepeatBehavior
    public var buttonSizing: ButtonSizing
    public var buttonBorderShape: ButtonBorderShape
    public var menuIndicatorVisibility: Visibility
    public var navigationViewStyle: NavigationViewStyle
    public var navigationSplitViewStyle: NavigationSplitViewStyle
    public var isLuminanceReduced: Bool
    public var redactionReasons: RedactionReasons
    public var isPrivacySensitive: Bool
    var isScrollClipDisabled: Bool
    var scrollContentBackgroundVisibility: Visibility
    var contentMargins: ContentMarginValues
    var defaultScrollAnchors: DefaultScrollAnchorValues
    var listRowSpacing: Double?
    var gridHorizontalSpacing: Double?
    public var defaultMinListRowHeight: Double
    public var defaultMinListHeaderHeight: CGFloat?
    public var backgroundProminence: BackgroundProminence
    public var headerProminence: Prominence
    public var badgeProminence: BadgeProminence
    public var defaultWheelPickerItemHeight: CGFloat
    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility
    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility
    public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode
    public var isSearching: Bool
    public var openURL: OpenURLAction
    public var dismiss: DismissAction
    public var dismissSearch: DismissSearchAction
    public var rename: RenameAction?
    public var refresh: RefreshAction?
    public var undoManager: UndoManager?
    public var openWindow: OpenWindowAction
    public var dismissWindow: DismissWindowAction
    public var openSettings: OpenSettingsAction
    public var requestReview: RequestReviewAction
    public var focusedValues: FocusedValues
    public var environmentObjects: EnvironmentObjectValues
    private var customValues: [ObjectIdentifier: Any]

    public init(
        colorScheme: ColorScheme = .dark,
        colorSchemeContrast: ColorSchemeContrast = .standard,
        scenePhase: ScenePhase = .active,
        controlActiveState: ControlActiveState = .active,
        appearsActive: Bool = true,
        supportsMultipleWindows: Bool = false,
        isPresented: Bool = false,
        isSceneCaptured: Bool = false,
        isTabBarShowingSections: Bool = false,
        editMode: Binding<EditMode>? = nil,
        isFocused: Bool = false,
        legibilityWeight: LegibilityWeight? = nil,
        displayScale: Double = 1,
        pixelLength: Double = 1,
        accessibilityAssistiveAccessEnabled: Bool = false,
        accessibilityDimFlashingLights: Bool = false,
        accessibilityDifferentiateWithoutColor: Bool = false,
        accessibilityEnabled: Bool = false,
        accessibilityInvertColors: Bool = false,
        accessibilityLargeContentViewerEnabled: Bool = false,
        accessibilityPlayAnimatedImages: Bool = true,
        accessibilityPrefersHeadAnchorAlternative: Bool = false,
        accessibilityQuickActionsEnabled: Bool = false,
        accessibilityReduceHighlightingEffects: Bool = false,
        accessibilityReduceMotion: Bool = false,
        accessibilityReduceTransparency: Bool = false,
        accessibilityShowButtonShapes: Bool = false,
        accessibilityShowBorders: Bool = false,
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
        minimumLineLimit: Int? = nil,
        lineLimitReservesSpace: Bool = false,
        lineSpacing: Double? = nil,
        truncationMode: Text.TruncationMode? = nil,
        minimumScaleFactor: CGFloat = 1,
        allowsTightening: Bool = true,
        textCase: Text.Case? = nil,
        textSelectability: TextSelectability? = nil,
        textSelectionAffinity: TextSelectionAffinity = .automatic,
        imageScale: Image.Scale = .medium,
        symbolRenderingMode: SymbolRenderingMode? = nil,
        symbolVariants: SymbolVariants = .none,
        controlSize: ControlSize = .regular,
        labelStyle: LabelStyle = .automatic,
        labeledContentStyle: LabeledContentStyle = .automatic,
        formStyle: FormStyle = .automatic,
        groupBoxStyle: GroupBoxStyle = .automatic,
        disclosureGroupStyle: DisclosureGroupStyle = .automatic,
        menuStyle: MenuStyle = .automatic,
        controlGroupStyle: ControlGroupStyle = .automatic,
        progressViewStyle: ProgressViewStyle = .automatic,
        gaugeStyle: GaugeStyle = .automatic,
        datePickerStyle: DatePickerStyle = .automatic,
        tabViewStyle: TabViewStyle = .automatic,
        indexViewStyle: IndexViewStyle = .page,
        toggleStyle: ToggleStyle = .automatic,
        textFieldStyle: TextFieldStyle = .automatic,
        submitLabel: SubmitLabel = .return,
        contentTransition: ContentTransition = .identity,
        contentTransitionAddsDrawingGroup: Bool = false,
        listStyle: ListStyle = .automatic,
        textInputAutocapitalization: TextInputAutocapitalization? = nil,
        isAutocorrectionDisabled: Bool = false,
        isScrollEnabled: Bool = true,
        defaultHoverEffect: HoverEffect? = nil,
        isHoverEffectEnabled: Bool = true,
        isFocusEffectEnabled: Bool = true,
        buttonRepeatBehavior: ButtonRepeatBehavior = .automatic,
        buttonSizing: ButtonSizing = .automatic,
        buttonBorderShape: ButtonBorderShape = .automatic,
        menuIndicatorVisibility: Visibility = .automatic,
        navigationViewStyle: NavigationViewStyle = .automatic,
        navigationSplitViewStyle: NavigationSplitViewStyle = .automatic,
        isLuminanceReduced: Bool = false,
        redactionReasons: RedactionReasons = [],
        isPrivacySensitive: Bool = false,
        defaultMinListRowHeight: Double = 0,
        defaultMinListHeaderHeight: CGFloat? = nil,
        backgroundProminence: BackgroundProminence = .standard,
        headerProminence: Prominence = .standard,
        badgeProminence: BadgeProminence = .standard,
        defaultWheelPickerItemHeight: CGFloat = 32,
        horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility = .automatic,
        verticalScrollIndicatorVisibility: ScrollIndicatorVisibility = .automatic,
        scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode = .automatic,
        isSearching: Bool = false,
        openURL: OpenURLAction = .system,
        dismiss: DismissAction = .noop,
        dismissSearch: DismissSearchAction = .noop,
        rename: RenameAction? = nil,
        refresh: RefreshAction? = nil,
        undoManager: UndoManager? = nil,
        openWindow: OpenWindowAction = .noop,
        dismissWindow: DismissWindowAction = .noop,
        openSettings: OpenSettingsAction = .noop,
        requestReview: RequestReviewAction = .noop,
        focusedValues: FocusedValues = FocusedValues(),
        environmentObjects: EnvironmentObjectValues = EnvironmentObjectValues()
    ) {
        self.colorScheme = colorScheme
        self.colorSchemeContrast = colorSchemeContrast
        self.scenePhase = scenePhase
        self.controlActiveState = controlActiveState
        self.appearsActive = appearsActive
        self.supportsMultipleWindows = supportsMultipleWindows
        self.isPresented = isPresented
        self.isSceneCaptured = isSceneCaptured
        self.isTabBarShowingSections = isTabBarShowingSections
        self.editMode = editMode
        self.isFocused = isFocused
        self.legibilityWeight = legibilityWeight
        self.displayScale = displayScale
        self.pixelLength = pixelLength
        self.accessibilityAssistiveAccessEnabled = accessibilityAssistiveAccessEnabled
        self.accessibilityDimFlashingLights = accessibilityDimFlashingLights
        self.accessibilityDifferentiateWithoutColor = accessibilityDifferentiateWithoutColor
        self.accessibilityEnabled = accessibilityEnabled
        self.accessibilityInvertColors = accessibilityInvertColors
        self.accessibilityLargeContentViewerEnabled = accessibilityLargeContentViewerEnabled
        self.accessibilityPlayAnimatedImages = accessibilityPlayAnimatedImages
        self.accessibilityPrefersHeadAnchorAlternative = accessibilityPrefersHeadAnchorAlternative
        self.accessibilityQuickActionsEnabled = accessibilityQuickActionsEnabled
        self.accessibilityReduceHighlightingEffects = accessibilityReduceHighlightingEffects
        self.accessibilityReduceMotion = accessibilityReduceMotion
        self.accessibilityReduceTransparency = accessibilityReduceTransparency
        self.accessibilityShowButtonShapes = accessibilityShowButtonShapes
        self.accessibilityShowBorders = accessibilityShowBorders
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
        self.fontItalic = nil
        self.fontMonospacedDigits = false
        self.underlineStyle = nil
        self.strikethroughStyle = nil
        self.multilineTextAlignment = multilineTextAlignment
        self.lineLimit = lineLimit
        self.minimumLineLimit = minimumLineLimit
        self.lineLimitReservesSpace = lineLimitReservesSpace
        self.lineSpacing = lineSpacing
        self.truncationMode = truncationMode
        self.minimumScaleFactor = Self.clampedMinimumScaleFactor(minimumScaleFactor)
        self.allowsTightening = allowsTightening
        self.textCase = textCase
        self.textSelectability = textSelectability
        self.textSelectionAffinity = textSelectionAffinity
        self.imageScale = imageScale
        self.symbolRenderingMode = symbolRenderingMode
        self.symbolVariants = symbolVariants
        self.controlSize = controlSize
        self.labelStyle = labelStyle
        self.labeledContentStyle = labeledContentStyle
        self.formStyle = formStyle
        self.groupBoxStyle = groupBoxStyle
        self.disclosureGroupStyle = disclosureGroupStyle
        self.menuStyle = menuStyle
        self.controlGroupStyle = controlGroupStyle
        self.progressViewStyle = progressViewStyle
        self.gaugeStyle = gaugeStyle
        self.datePickerStyle = datePickerStyle
        self.tabViewStyle = tabViewStyle
        self.indexViewStyle = indexViewStyle
        self.toggleStyle = toggleStyle
        self.textFieldStyle = textFieldStyle
        self.submitLabel = submitLabel
        self.contentTransition = contentTransition
        self.contentTransitionAddsDrawingGroup = contentTransitionAddsDrawingGroup
        self.listStyle = listStyle
        self.textInputAutocapitalization = textInputAutocapitalization
        self.isAutocorrectionDisabled = isAutocorrectionDisabled
        self.textContentType = nil
        self.keyboardType = .default
        self.textInputCompletion = nil
        self.textInputSuggestions = nil
        self.writingToolsBehavior = nil
        self.writingToolsAffordanceVisibility = .automatic
        self.searchDictationBehavior = nil
        self.isFindDisabled = false
        self.isReplaceDisabled = false
        self.isFindNavigatorPresented = false
        self.isScrollEnabled = isScrollEnabled
        self.defaultHoverEffect = defaultHoverEffect
        self.isHoverEffectEnabled = isHoverEffectEnabled
        self.isFocusEffectEnabled = isFocusEffectEnabled
        self.buttonRepeatBehavior = buttonRepeatBehavior
        self.buttonSizing = buttonSizing
        self.buttonBorderShape = buttonBorderShape
        self.menuIndicatorVisibility = menuIndicatorVisibility
        self.navigationViewStyle = navigationViewStyle
        self.navigationSplitViewStyle = navigationSplitViewStyle
        self.isLuminanceReduced = isLuminanceReduced
        self.redactionReasons = redactionReasons
        self.isPrivacySensitive = isPrivacySensitive
        self.isScrollClipDisabled = false
        self.scrollContentBackgroundVisibility = .automatic
        self.contentMargins = .empty
        self.defaultScrollAnchors = .empty
        self.listRowSpacing = nil
        self.gridHorizontalSpacing = nil
        self.defaultMinListRowHeight = defaultMinListRowHeight
        self.defaultMinListHeaderHeight = defaultMinListHeaderHeight
        self.backgroundProminence = backgroundProminence
        self.headerProminence = headerProminence
        self.badgeProminence = badgeProminence
        self.defaultWheelPickerItemHeight = defaultWheelPickerItemHeight
        self.horizontalScrollIndicatorVisibility = horizontalScrollIndicatorVisibility
        self.verticalScrollIndicatorVisibility = verticalScrollIndicatorVisibility
        self.scrollDismissesKeyboardMode = scrollDismissesKeyboardMode
        self.isSearching = isSearching
        self.openURL = openURL
        self.dismiss = dismiss
        self.dismissSearch = dismissSearch
        self.rename = rename
        self.refresh = refresh
        self.undoManager = undoManager
        self.openWindow = openWindow
        self.dismissWindow = dismissWindow
        self.openSettings = openSettings
        self.requestReview = requestReview
        self.focusedValues = focusedValues
        self.environmentObjects = environmentObjects
        self.customValues = [:]
    }

    static func clampedMinimumScaleFactor(_ factor: CGFloat) -> CGFloat {
        min(max(factor, 0), 1)
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
public struct Environment<Value>: DynamicProperty {
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
public struct EnvironmentObject<ObjectType: ObservableObject>: DynamicProperty {
    public init() {}

    public var wrappedValue: ObjectType {
        let object = ViewBuildContextScope.current?.environmentValues.environmentObjects.object(ObjectType.self)
        guard let object else {
            fatalError("No EnvironmentObject of type \(ObjectType.self) was found in the current WinSwiftUI environment")
        }

        ViewBuildContextScope.current?.observe(object)
        return object
    }

    public var projectedValue: ObservedObject<ObjectType> {
        ObservedObject(wrappedValue: wrappedValue)
    }
}

@MainActor
@propertyWrapper
public struct FocusedValue<Value>: DynamicProperty {
    private let keyPath: KeyPath<FocusedValues, Value>

    public init(_ keyPath: KeyPath<FocusedValues, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        let values = ViewBuildContextScope.current?.environmentValues.focusedValues ?? FocusedValues()
        return values[keyPath: keyPath]
    }
}

@MainActor
@propertyWrapper
public struct FocusedBinding<Value>: DynamicProperty {
    private let keyPath: KeyPath<FocusedValues, Binding<Value>?>

    public init(_ keyPath: KeyPath<FocusedValues, Binding<Value>?>) {
        self.keyPath = keyPath
    }

    private var binding: Binding<Value>? {
        let values = ViewBuildContextScope.current?.environmentValues.focusedValues ?? FocusedValues()
        return values[keyPath: keyPath]
    }

    public var wrappedValue: Value? {
        get {
            binding?.wrappedValue
        }
        nonmutating set {
            guard let newValue else {
                return
            }
            binding?.wrappedValue = newValue
        }
    }

    public var projectedValue: Binding<Value>? {
        binding
    }
}

@MainActor
@propertyWrapper
public struct FocusedObject<ObjectType: ObservableObject>: DynamicProperty {
    public init() {}

    public var wrappedValue: ObjectType? {
        let object = ViewBuildContextScope.current?.environmentValues.focusedValues.focusedObject(ObjectType.self)
        if let object {
            ViewBuildContextScope.current?.observe(object)
        }
        return object
    }
}

@MainActor
@propertyWrapper
public struct StateObject<ObjectType: ObservableObject>: DynamicProperty {
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
public struct Binding<Value>: DynamicProperty {
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
public struct State<Value>: DynamicProperty {
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
@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    @MainActor
    private final class Storage {
        let key: String
        let defaultValue: Value
        let store: UserDefaults
        var invalidate: (@MainActor () -> Void)?

        init(key: String, defaultValue: Value, store: UserDefaults) {
            self.key = key
            self.defaultValue = defaultValue
            self.store = store
        }

        var value: Value {
            get {
                guard store.object(forKey: key) != nil else {
                    return defaultValue
                }

                if Value.self == Bool.self {
                    return store.bool(forKey: key) as! Value
                } else if Value.self == Int.self {
                    return store.integer(forKey: key) as! Value
                } else if Value.self == Double.self {
                    return store.double(forKey: key) as! Value
                } else if Value.self == String.self {
                    return (store.string(forKey: key) ?? defaultValue as! String) as! Value
                } else if Value.self == Data.self {
                    return (store.data(forKey: key) ?? defaultValue as! Data) as! Value
                } else if Value.self == URL.self {
                    return (store.url(forKey: key) ?? defaultValue as! URL) as! Value
                }

                return (store.object(forKey: key) as? Value) ?? defaultValue
            }
            set {
                if let url = newValue as? URL {
                    store.set(url, forKey: key)
                } else {
                    store.set(newValue, forKey: key)
                }
                invalidate?()
            }
        }
    }

    private let storage: Storage

    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        self.storage = Storage(key: key, defaultValue: wrappedValue, store: store ?? .standard)
    }

    public init(_ key: String, store: UserDefaults? = nil) where Value == Bool {
        self.init(wrappedValue: false, key, store: store)
    }

    public init(_ key: String, store: UserDefaults? = nil) where Value == Int {
        self.init(wrappedValue: 0, key, store: store)
    }

    public init(_ key: String, store: UserDefaults? = nil) where Value == Double {
        self.init(wrappedValue: 0, key, store: store)
    }

    public init(_ key: String, store: UserDefaults? = nil) where Value == String {
        self.init(wrappedValue: "", key, store: store)
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
private final class SceneStorageCenter {
    static let shared = SceneStorageCenter()

    private var values: [String: Any] = [:]

    func value<Value>(for key: String, default defaultValue: Value) -> Value {
        values[key] as? Value ?? defaultValue
    }

    func setValue<Value>(_ value: Value, for key: String) {
        values[key] = value
    }
}

@MainActor
@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    @MainActor
    private final class Storage {
        let key: String
        let defaultValue: Value
        var invalidate: (@MainActor () -> Void)?

        init(key: String, defaultValue: Value) {
            self.key = key
            self.defaultValue = defaultValue
        }

        var value: Value {
            get {
                SceneStorageCenter.shared.value(for: key, default: defaultValue)
            }
            set {
                SceneStorageCenter.shared.setValue(newValue, for: key)
                invalidate?()
            }
        }
    }

    private let storage: Storage

    public init(wrappedValue: Value, _ key: String) {
        self.storage = Storage(key: key, defaultValue: wrappedValue)
    }

    public init(_ key: String) where Value == Bool {
        self.init(wrappedValue: false, key)
    }

    public init(_ key: String) where Value == Int {
        self.init(wrappedValue: 0, key)
    }

    public init(_ key: String) where Value == Double {
        self.init(wrappedValue: 0, key)
    }

    public init(_ key: String) where Value == String {
        self.init(wrappedValue: "", key)
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
@propertyWrapper
public struct ScaledMetric<Value: BinaryFloatingPoint>: DynamicProperty {
    private let baseValue: Value
    private let relativeTextStyle: Font.TextStyle

    public init(wrappedValue: Value, relativeTo textStyle: Font.TextStyle = .body) {
        self.baseValue = wrappedValue
        self.relativeTextStyle = textStyle
    }

    public var wrappedValue: Value {
        let dynamicTypeSize = ViewBuildContextScope.current?.environmentValues.dynamicTypeSize ?? .large
        return baseValue * Value(dynamicTypeSize.retainedFontScale)
    }

    public var projectedValue: ScaledMetric<Value> {
        self
    }

    public var relativeTo: Font.TextStyle {
        relativeTextStyle
    }
}

@MainActor
@propertyWrapper
public struct FocusState<Value>: DynamicProperty {
    @MainActor
    private final class Storage {
        var value: Value
        var invalidate: (@MainActor () -> Void)?

        init(value: Value) {
            self.value = value
        }
    }

    private let storage: Storage

    public init() where Value == Bool {
        self.storage = Storage(value: false)
    }

    public init<Wrapped>() where Value == Wrapped? {
        self.storage = Storage(value: nil)
    }

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

    public var projectedValue: Binding {
        Binding(
            get: {
                wrappedValue
            },
            set: { newValue in
                wrappedValue = newValue
            }
        )
    }

    @MainActor
    public struct Binding {
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
    }
}

@MainActor
public struct ViewBuildContext {
    typealias NavigationDestinationDismissHandler = @MainActor () -> Void
    typealias NavigationDestinationPushHandler = @MainActor ([AnyView], NavigationDestinationDismissHandler?) -> Void

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
    private let navigationDestinationHandlerProvider: () -> NavigationDestinationPushHandler?
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
            return color.resolvedForVisualEnvironment(
                contrast: colorSchemeContrast,
                backgroundProminence: backgroundProminence
            )
        case .linearGradient(let gradient):
            return gradient.startColor.resolvedForVisualEnvironment(
                contrast: colorSchemeContrast,
                backgroundProminence: backgroundProminence
            )
        case nil:
            return foregroundColorProvider().resolvedForVisualEnvironment(
                contrast: colorSchemeContrast,
                backgroundProminence: backgroundProminence
            )
        }
    }

    var foregroundStyle: ForegroundStyle {
        (environmentValuesProvider().foregroundStyle ?? .color(foregroundColorProvider()))
            .resolvedForVisualEnvironment(
                contrast: colorSchemeContrast,
                backgroundProminence: backgroundProminence
            )
    }

    public var tint: Color {
        environmentValuesProvider().tint ?? tintProvider()
    }

    public var imageScale: Image.Scale {
        environmentValuesProvider().imageScale
    }

    public var symbolRenderingMode: SymbolRenderingMode? {
        environmentValuesProvider().symbolRenderingMode
    }

    public var symbolVariants: SymbolVariants {
        environmentValuesProvider().symbolVariants
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

    public var isFontItalic: Bool {
        environmentValuesProvider().fontItalic == true
    }

    public var usesMonospacedDigits: Bool {
        environmentValuesProvider().fontMonospacedDigits
    }

    var underlineStyle: TextDecorationSetting? {
        environmentValuesProvider().underlineStyle
    }

    var strikethroughStyle: TextDecorationSetting? {
        environmentValuesProvider().strikethroughStyle
    }

    public var textAlignment: TextAlignment {
        environmentValuesProvider().multilineTextAlignment
    }

    public var lineLimit: Int? {
        environmentValuesProvider().lineLimit ?? lineLimitProvider()
    }

    var minimumLineLimit: Int? {
        environmentValuesProvider().minimumLineLimit
    }

    public var lineLimitReservesSpace: Bool {
        environmentValuesProvider().lineLimitReservesSpace
    }

    public var lineSpacing: Double? {
        environmentValuesProvider().lineSpacing
    }

    public var truncationMode: Text.TruncationMode? {
        environmentValuesProvider().truncationMode ?? truncationModeProvider()
    }

    public var minimumScaleFactor: CGFloat {
        environmentValuesProvider().minimumScaleFactor
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

    public var labeledContentStyle: LabeledContentStyle {
        environmentValuesProvider().labeledContentStyle
    }

    public var formStyle: FormStyle {
        environmentValuesProvider().formStyle
    }

    public var groupBoxStyle: GroupBoxStyle {
        environmentValuesProvider().groupBoxStyle
    }

    public var disclosureGroupStyle: DisclosureGroupStyle {
        environmentValuesProvider().disclosureGroupStyle
    }

    public var menuStyle: MenuStyle {
        environmentValuesProvider().menuStyle
    }

    public var controlGroupStyle: ControlGroupStyle {
        environmentValuesProvider().controlGroupStyle
    }

    public var navigationViewStyle: NavigationViewStyle {
        environmentValuesProvider().navigationViewStyle
    }

    public var navigationSplitViewStyle: NavigationSplitViewStyle {
        environmentValuesProvider().navigationSplitViewStyle
    }

    public var progressViewStyle: ProgressViewStyle {
        environmentValuesProvider().progressViewStyle
    }

    public var gaugeStyle: GaugeStyle {
        environmentValuesProvider().gaugeStyle
    }

    public var datePickerStyle: DatePickerStyle {
        environmentValuesProvider().datePickerStyle
    }

    public var tabViewStyle: TabViewStyle {
        environmentValuesProvider().tabViewStyle
    }

    public var indexViewStyle: IndexViewStyle {
        environmentValuesProvider().indexViewStyle
    }

    public var toggleStyle: ToggleStyle {
        environmentValuesProvider().toggleStyle
    }

    public var textFieldStyle: TextFieldStyle {
        environmentValuesProvider().textFieldStyle
    }

    public var submitLabel: SubmitLabel {
        environmentValuesProvider().submitLabel
    }

    public var contentTransition: ContentTransition {
        environmentValuesProvider().contentTransition
    }

    public var contentTransitionAddsDrawingGroup: Bool {
        environmentValuesProvider().contentTransitionAddsDrawingGroup
    }

    public var listStyle: ListStyle {
        environmentValuesProvider().listStyle
    }

    public var textInputAutocapitalization: TextInputAutocapitalization? {
        environmentValuesProvider().textInputAutocapitalization
    }

    public var textSelectionAffinity: TextSelectionAffinity {
        environmentValuesProvider().textSelectionAffinity
    }

    public var isAutocorrectionDisabled: Bool {
        environmentValuesProvider().isAutocorrectionDisabled
    }

    var textContentType: NSTextContentType? {
        environmentValuesProvider().textContentType
    }

    var keyboardType: UIKeyboardType {
        environmentValuesProvider().keyboardType
    }

    var textInputCompletion: String? {
        environmentValuesProvider().textInputCompletion
    }

    var textInputSuggestions: [AnyView]? {
        environmentValuesProvider().textInputSuggestions
    }

    public var writingToolsBehavior: WritingToolsBehavior? {
        environmentValuesProvider().writingToolsBehavior
    }

    public var writingToolsAffordanceVisibility: Visibility {
        environmentValuesProvider().writingToolsAffordanceVisibility
    }

    var searchDictationBehavior: TextInputDictationBehavior? {
        environmentValuesProvider().searchDictationBehavior
    }

    var isFindDisabled: Bool {
        environmentValuesProvider().isFindDisabled
    }

    var isReplaceDisabled: Bool {
        environmentValuesProvider().isReplaceDisabled
    }

    var isFindNavigatorPresented: Bool {
        environmentValuesProvider().isFindNavigatorPresented
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

    func contentInsets(for placement: ContentMarginPlacement, defaultInsets: EdgeInsets) -> EdgeInsets {
        environmentValuesProvider().contentMargins.insets(for: placement, defaultInsets: defaultInsets)
    }

    func defaultScrollAnchor(for role: ScrollAnchorRole) -> UnitPoint? {
        environmentValuesProvider().defaultScrollAnchors.anchor(for: role)
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

    public var backgroundProminence: BackgroundProminence {
        environmentValuesProvider().backgroundProminence
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
        navigationDestinationHandlerProvider: @escaping () -> NavigationDestinationPushHandler? = { nil },
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

    func pushNavigationDestination(
        _ destination: [AnyView],
        onDismiss: NavigationDestinationDismissHandler? = nil
    ) -> Bool {
        guard let handler = navigationDestinationHandlerProvider() else {
            return false
        }

        handler(destination, onDismiss)
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

    func withLineLimit(
        _ lineLimit: Int?,
        minimumLineLimit: Int? = nil,
        reservesSpace: Bool = false
    ) -> ViewBuildContext {
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
                values.minimumLineLimit = minimumLineLimit
                values.lineLimitReservesSpace = reservesSpace && lineLimit != nil
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

    func withTransformedEnvironmentValue<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ transform: @escaping (inout Value) -> Void
    ) -> ViewBuildContext {
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
                transform(&values[keyPath: keyPath])
                return values
            },
            navigationDestinationHandlerProvider: navigationDestinationHandlerProvider,
            navigationValueHandlerProvider: navigationValueHandlerProvider,
            navigationDestinationRegistrationsProvider: navigationDestinationRegistrationsProvider,
            navigationPresentedDestinationsProvider: navigationPresentedDestinationsProvider
        )
    }

    func withNavigationDestinationHandler(_ handler: @escaping NavigationDestinationPushHandler) -> ViewBuildContext {
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

    var anyNavigationBarBackButtonHidden: Bool? {
        (content as? any TaggedViewMetadata)?.anyNavigationBarBackButtonHidden
    }

    var anyNavigationBarHidden: Bool? {
        (content as? any TaggedViewMetadata)?.anyNavigationBarHidden
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        (content as? any TaggedViewMetadata)?.anyToolbarItemPlacement
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
public struct EquatableView<Content: View & Equatable>: View, TaggedViewMetadata {
    public typealias Body = Never

    public let content: Content

    public init(content: Content) {
        self.content = content
    }

    public var body: Never {
        fatalError("EquatableView has no body")
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

    var anyNavigationBarBackButtonHidden: Bool? {
        (content as? any TaggedViewMetadata)?.anyNavigationBarBackButtonHidden
    }

    var anyNavigationBarHidden: Bool? {
        (content as? any TaggedViewMetadata)?.anyNavigationBarHidden
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        (content as? any TaggedViewMetadata)?.anyToolbarItemPlacement
    }

    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] {
        (content as? any TaggedViewMetadata)?.anyNavigationDestinationRegistrations ?? []
    }

    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] {
        (content as? any TaggedViewMetadata)?.anyNavigationPresentedDestinations ?? []
    }

    public func makeComponent(context: ViewBuildContext) -> Component {
        content.makeComponent(context: context)
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

    var retainedContentShapeStyle: SwiftWindowsUI.RetainedContentShapeStyle {
        switch self {
        case .rectangle:
            return .rectangle
        case .roundedRectangle(let radius):
            return .roundedRectangle(radius)
        case .capsule:
            return .capsule
        }
    }
}

@MainActor
protocol RetainedClipShape: Shape {
    var retainedClipShapeStyle: RetainedClipShapeStyle { get }
}

@MainActor
private func retainedContentShapeStyle<S: Shape>(for shape: S) -> SwiftWindowsUI.RetainedContentShapeStyle {
    if shape is Circle || shape is Ellipse {
        return .ellipse
    }

    return (shape as? any RetainedClipShape)?.retainedClipShapeStyle.retainedContentShapeStyle ?? .rectangle
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
    let navigationBarBackButtonHidden: Bool?
    let navigationBarHidden: Bool?
    let toolbarItemPlacement: ToolbarItemPlacement?
    let navigationDestinationRegistrations: [NavigationDestinationRegistration]
    let navigationPresentedDestinations: [NavigationPresentedDestination]

    public init<V: View>(_ view: V) {
        self.selectionTag = (view as? any TaggedViewMetadata)?.anySelectionTag
        self.tabItem = (view as? any TaggedViewMetadata)?.anyTabItem
        self.badge = (view as? any TaggedViewMetadata)?.anyBadge
        self.navigationTitle = (view as? any TaggedViewMetadata)?.anyNavigationTitle
        self.navigationTitleDisplayMode = (view as? any TaggedViewMetadata)?.anyNavigationTitleDisplayMode
        self.navigationBarBackButtonHidden = (view as? any TaggedViewMetadata)?.anyNavigationBarBackButtonHidden
        self.navigationBarHidden = (view as? any TaggedViewMetadata)?.anyNavigationBarHidden
        self.toolbarItemPlacement = (view as? any TaggedViewMetadata)?.anyToolbarItemPlacement
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

public enum TextSelectability: Sendable, Equatable, Hashable {
    case enabled
    case disabled

    var retainedSelectability: RetainedTextSelectability {
        switch self {
        case .enabled:
            return .enabled
        case .disabled:
            return .disabled
        }
    }
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

public enum Edge: Sendable, Equatable, Hashable {
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

public struct AnyTransition: Sendable, Equatable {
    indirect enum Kind: Sendable, Equatable {
        case identity
        case move(edge: Edge)
        case offset(x: Double, y: Double)
        case opacity
        case push(from: Edge)
        case scale(scale: Double, anchor: UnitPoint)
        case slide
        case asymmetric(insertion: AnyTransition, removal: AnyTransition)
        case combined(AnyTransition, AnyTransition)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let identity = AnyTransition(kind: .identity)
    public static let opacity = AnyTransition(kind: .opacity)
    public static let scale = AnyTransition(kind: .scale(scale: 1, anchor: .center))
    public static let slide = AnyTransition(kind: .slide)

    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition(kind: .move(edge: edge))
    }

    public static func offset(_ offset: CGSize) -> AnyTransition {
        AnyTransition(kind: .offset(x: offset.width, y: offset.height))
    }

    public static func offset(x: Double, y: Double) -> AnyTransition {
        AnyTransition(kind: .offset(x: x, y: y))
    }

    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition(kind: .push(from: edge))
    }

    public static func scale(scale: Double, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(kind: .scale(scale: scale, anchor: anchor))
    }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(kind: .asymmetric(insertion: insertion, removal: removal))
    }

    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(kind: .combined(self, other))
    }
}

public struct ContentTransition: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case identity
        case interpolate
        case numericTextCountsDown(Bool)
        case numericTextValue(Double)
        case opacity
        case symbolEffect
        case symbolEffectConfiguration(SymbolEffectConfiguration, SymbolEffectOptions)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let identity = ContentTransition(kind: .identity)
    public static let interpolate = ContentTransition(kind: .interpolate)
    public static let opacity = ContentTransition(kind: .opacity)
    public static let symbolEffect = ContentTransition(kind: .symbolEffect)

    public static func numericText(countsDown: Bool = false) -> ContentTransition {
        ContentTransition(kind: .numericTextCountsDown(countsDown))
    }

    public static func numericText(value: Double) -> ContentTransition {
        ContentTransition(kind: .numericTextValue(value))
    }

    public static func symbolEffect<T: SymbolEffect>(
        _ effect: T,
        options: SymbolEffectOptions = .default
    ) -> ContentTransition where T: ContentTransitionSymbolEffect {
        ContentTransition(kind: .symbolEffectConfiguration(effect.configuration, options))
    }
}

public struct SymbolEffectConfiguration: Sendable, Equatable, Hashable {
    enum Effect: Sendable, Equatable, Hashable {
        case appear
        case automatic
        case bounce
        case breathe
        case disappear
        case drawOff
        case drawOn
        case pulse
        case replace
        case rotate
        case scale
        case variableColor
        case wiggle
    }

    enum Scope: Sendable, Equatable, Hashable {
        case automatic
        case byLayer
        case wholeSymbol
    }

    enum Direction: Sendable, Equatable, Hashable {
        case automatic
        case up
        case down
    }

    var effect: Effect
    var scope: Scope
    var direction: Direction
    var reverses: Bool

    init(
        effect: Effect,
        scope: Scope = .automatic,
        direction: Direction = .automatic,
        reverses: Bool = false
    ) {
        self.effect = effect
        self.scope = scope
        self.direction = direction
        self.reverses = reverses
    }

    func withScope(_ scope: Scope) -> SymbolEffectConfiguration {
        SymbolEffectConfiguration(effect: effect, scope: scope, direction: direction, reverses: reverses)
    }

    func withDirection(_ direction: Direction) -> SymbolEffectConfiguration {
        SymbolEffectConfiguration(effect: effect, scope: scope, direction: direction, reverses: reverses)
    }

    func withReversing() -> SymbolEffectConfiguration {
        SymbolEffectConfiguration(effect: effect, scope: scope, direction: direction, reverses: true)
    }
}

public protocol SymbolEffect: Hashable, Sendable {
    var configuration: SymbolEffectConfiguration { get }
}

public protocol DiscreteSymbolEffect {}
public protocol IndefiniteSymbolEffect {}
public protocol ContentTransitionSymbolEffect {}
public protocol TransitionSymbolEffect {}

public struct SymbolEffectOptions: Sendable, Equatable, Hashable {
    public struct RepeatBehavior: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case periodic
            case continuous
        }

        let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let periodic = RepeatBehavior(kind: .periodic)
        public static let continuous = RepeatBehavior(kind: .continuous)
    }

    enum RepeatPreference: Sendable, Equatable, Hashable {
        case automatic
        case count(Int?)
        case repeating
        case nonRepeating
        case behavior(RepeatBehavior)
    }

    var repeatPreference: RepeatPreference
    var speedMultiplier: Double

    public init() {
        self.repeatPreference = .automatic
        self.speedMultiplier = 1
    }

    private init(repeatPreference: RepeatPreference, speedMultiplier: Double = 1) {
        self.repeatPreference = repeatPreference
        self.speedMultiplier = speedMultiplier
    }

    public static let `default` = SymbolEffectOptions()
    public static let repeating = SymbolEffectOptions(repeatPreference: .repeating)
    public static let nonRepeating = SymbolEffectOptions(repeatPreference: .nonRepeating)

    public var repeating: SymbolEffectOptions {
        var copy = self
        copy.repeatPreference = .repeating
        return copy
    }

    public var nonRepeating: SymbolEffectOptions {
        var copy = self
        copy.repeatPreference = .nonRepeating
        return copy
    }

    public static func `repeat`(_ count: Int?) -> SymbolEffectOptions {
        SymbolEffectOptions(repeatPreference: .count(count))
    }

    public func `repeat`(_ count: Int?) -> SymbolEffectOptions {
        var copy = self
        copy.repeatPreference = .count(count)
        return copy
    }

    public static func `repeat`(_ behavior: RepeatBehavior) -> SymbolEffectOptions {
        SymbolEffectOptions(repeatPreference: .behavior(behavior))
    }

    public func `repeat`(_ behavior: RepeatBehavior) -> SymbolEffectOptions {
        var copy = self
        copy.repeatPreference = .behavior(behavior)
        return copy
    }

    public static func speed(_ speed: Double) -> SymbolEffectOptions {
        SymbolEffectOptions(repeatPreference: .automatic, speedMultiplier: speed)
    }

    public func speed(_ speed: Double) -> SymbolEffectOptions {
        var copy = self
        copy.speedMultiplier = speed
        return copy
    }
}

protocol ConfigurableSymbolEffect {
    init(configuration: SymbolEffectConfiguration)
}

private extension ConfigurableSymbolEffect where Self: SymbolEffect {
    func withScope(_ scope: SymbolEffectConfiguration.Scope) -> Self {
        Self(configuration: configuration.withScope(scope))
    }

    func withDirection(_ direction: SymbolEffectConfiguration.Direction) -> Self {
        Self(configuration: configuration.withDirection(direction))
    }

    func withReversing() -> Self {
        Self(configuration: configuration.withReversing())
    }
}

public struct AppearSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, TransitionSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .appear))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var up: AppearSymbolEffect { withDirection(.up) }
    public var down: AppearSymbolEffect { withDirection(.down) }
    public var byLayer: AppearSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: AppearSymbolEffect { withScope(.wholeSymbol) }
}

public struct AutomaticSymbolEffect: SymbolEffect, ContentTransitionSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .automatic))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }
}

public struct BounceSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .bounce))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var up: BounceSymbolEffect { withDirection(.up) }
    public var down: BounceSymbolEffect { withDirection(.down) }
    public var byLayer: BounceSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: BounceSymbolEffect { withScope(.wholeSymbol) }
}

public struct BreatheSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .breathe))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var byLayer: BreatheSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: BreatheSymbolEffect { withScope(.wholeSymbol) }
}

public struct DisappearSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, TransitionSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .disappear))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var up: DisappearSymbolEffect { withDirection(.up) }
    public var down: DisappearSymbolEffect { withDirection(.down) }
    public var byLayer: DisappearSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: DisappearSymbolEffect { withScope(.wholeSymbol) }
}

public struct DrawOffSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, TransitionSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .drawOff))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }
}

public struct DrawOnSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, TransitionSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .drawOn))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }
}

public struct PulseSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .pulse))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var byLayer: PulseSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: PulseSymbolEffect { withScope(.wholeSymbol) }
}

public struct ReplaceSymbolEffect: SymbolEffect, ContentTransitionSymbolEffect, ConfigurableSymbolEffect {
    public struct MagicReplace: SymbolEffect, ContentTransitionSymbolEffect, ConfigurableSymbolEffect {
        public var configuration: SymbolEffectConfiguration

        public init() {
            self.init(configuration: SymbolEffectConfiguration(effect: .replace))
        }

        init(configuration: SymbolEffectConfiguration) {
            self.configuration = configuration
        }
    }

    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .replace))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public static let downUp = ReplaceSymbolEffect()
    public static let offUp = ReplaceSymbolEffect()
    public static let upUp = ReplaceSymbolEffect()
    public var downUp: ReplaceSymbolEffect { self }
    public var offUp: ReplaceSymbolEffect { self }
    public var upUp: ReplaceSymbolEffect { self }
    public var byLayer: ReplaceSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: ReplaceSymbolEffect { withScope(.wholeSymbol) }

    public func magic(fallback: ReplaceSymbolEffect) -> MagicReplace {
        _ = fallback
        return MagicReplace(configuration: configuration)
    }
}

public struct RotateSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .rotate))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var byLayer: RotateSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: RotateSymbolEffect { withScope(.wholeSymbol) }
}

public struct ScaleSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .scale))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var up: ScaleSymbolEffect { withDirection(.up) }
    public var down: ScaleSymbolEffect { withDirection(.down) }
    public var byLayer: ScaleSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: ScaleSymbolEffect { withScope(.wholeSymbol) }
}

public struct VariableColorSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .variableColor))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var reversing: VariableColorSymbolEffect { withReversing() }
    public var byLayer: VariableColorSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: VariableColorSymbolEffect { withScope(.wholeSymbol) }
}

public struct WiggleSymbolEffect: SymbolEffect, DiscreteSymbolEffect, IndefiniteSymbolEffect, ConfigurableSymbolEffect {
    public var configuration: SymbolEffectConfiguration

    public init() {
        self.init(configuration: SymbolEffectConfiguration(effect: .wiggle))
    }

    init(configuration: SymbolEffectConfiguration) {
        self.configuration = configuration
    }

    public var byLayer: WiggleSymbolEffect { withScope(.byLayer) }
    public var wholeSymbol: WiggleSymbolEffect { withScope(.wholeSymbol) }
}

public extension SymbolEffect where Self == AppearSymbolEffect {
    static var appear: AppearSymbolEffect { AppearSymbolEffect() }
}

public extension SymbolEffect where Self == AutomaticSymbolEffect {
    static var automatic: AutomaticSymbolEffect { AutomaticSymbolEffect() }
}

public extension SymbolEffect where Self == BounceSymbolEffect {
    static var bounce: BounceSymbolEffect { BounceSymbolEffect() }
}

public extension SymbolEffect where Self == BreatheSymbolEffect {
    static var breathe: BreatheSymbolEffect { BreatheSymbolEffect() }
}

public extension SymbolEffect where Self == DisappearSymbolEffect {
    static var disappear: DisappearSymbolEffect { DisappearSymbolEffect() }
}

public extension SymbolEffect where Self == DrawOffSymbolEffect {
    static var drawOff: DrawOffSymbolEffect { DrawOffSymbolEffect() }
}

public extension SymbolEffect where Self == DrawOnSymbolEffect {
    static var drawOn: DrawOnSymbolEffect { DrawOnSymbolEffect() }
}

public extension SymbolEffect where Self == PulseSymbolEffect {
    static var pulse: PulseSymbolEffect { PulseSymbolEffect() }
}

public extension SymbolEffect where Self == ReplaceSymbolEffect {
    static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() }
}

public extension SymbolEffect where Self == RotateSymbolEffect {
    static var rotate: RotateSymbolEffect { RotateSymbolEffect() }
}

public extension SymbolEffect where Self == ScaleSymbolEffect {
    static var scale: ScaleSymbolEffect { ScaleSymbolEffect() }
}

public extension SymbolEffect where Self == VariableColorSymbolEffect {
    static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() }
}

public extension SymbolEffect where Self == WiggleSymbolEffect {
    static var wiggle: WiggleSymbolEffect { WiggleSymbolEffect() }
}

public struct SensoryFeedback: Sendable, Equatable, Hashable {
    public struct Flexibility: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case rigid
            case solid
            case soft
        }

        let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let rigid = Flexibility(kind: .rigid)
        public static let solid = Flexibility(kind: .solid)
        public static let soft = Flexibility(kind: .soft)
    }

    public struct Weight: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case light
            case medium
            case heavy
        }

        let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let light = Weight(kind: .light)
        public static let medium = Weight(kind: .medium)
        public static let heavy = Weight(kind: .heavy)
    }

    public struct PressFeedback: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case `default`
            case depth
            case start
        }

        let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let `default` = PressFeedback(kind: .default)
        public static let depth = PressFeedback(kind: .depth)
        public static let start = PressFeedback(kind: .start)
    }

    public struct ReleaseFeedback: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case `default`
            case stop
        }

        let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let `default` = ReleaseFeedback(kind: .default)
        public static let stop = ReleaseFeedback(kind: .stop)
    }

    public struct SelectionFeedback: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case `default`
            case maximum
            case minimum
            case off
            case on
        }

        let kind: Kind

        private init(kind: Kind) {
            self.kind = kind
        }

        public static let `default` = SelectionFeedback(kind: .default)
        public static let maximum = SelectionFeedback(kind: .maximum)
        public static let minimum = SelectionFeedback(kind: .minimum)
        public static let off = SelectionFeedback(kind: .off)
        public static let on = SelectionFeedback(kind: .on)
    }

    enum Kind: Sendable, Equatable, Hashable {
        case alignment
        case decrease
        case error
        case impact
        case impactFlexibility(Flexibility, Double)
        case impactWeight(Weight, Double)
        case increase
        case levelChange
        case pathComplete
        case press(PressFeedback)
        case release(ReleaseFeedback)
        case selection
        case selectionFeedback(SelectionFeedback)
        case start
        case stop
        case success
        case warning
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let alignment = SensoryFeedback(kind: .alignment)
    public static let decrease = SensoryFeedback(kind: .decrease)
    public static let error = SensoryFeedback(kind: .error)
    public static let impact = SensoryFeedback(kind: .impact)
    public static let increase = SensoryFeedback(kind: .increase)
    public static let levelChange = SensoryFeedback(kind: .levelChange)
    public static let pathComplete = SensoryFeedback(kind: .pathComplete)
    public static let selection = SensoryFeedback(kind: .selection)
    public static let start = SensoryFeedback(kind: .start)
    public static let stop = SensoryFeedback(kind: .stop)
    public static let success = SensoryFeedback(kind: .success)
    public static let warning = SensoryFeedback(kind: .warning)

    public static func impact(weight: Weight = .medium, intensity: Double = 1.0) -> SensoryFeedback {
        SensoryFeedback(kind: .impactWeight(weight, intensity))
    }

    public static func impact(flexibility: Flexibility, intensity: Double = 1.0) -> SensoryFeedback {
        SensoryFeedback(kind: .impactFlexibility(flexibility, intensity))
    }

    public static func press(_ feedback: PressFeedback = .default) -> SensoryFeedback {
        SensoryFeedback(kind: .press(feedback))
    }

    public static func release(_ feedback: ReleaseFeedback = .default) -> SensoryFeedback {
        SensoryFeedback(kind: .release(feedback))
    }

    public static func selection(_ feedback: SelectionFeedback = .default) -> SensoryFeedback {
        SensoryFeedback(kind: .selectionFeedback(feedback))
    }
}

public enum VerticalEdge: Sendable, Equatable {
    case top
    case bottom
}

public enum HorizontalEdge: Sendable, Equatable {
    case leading
    case trailing

    func resolved(for layoutDirection: LayoutDirection) -> HorizontalEdge {
        switch (self, layoutDirection) {
        case (.leading, .rightToLeft):
            return .trailing
        case (.trailing, .rightToLeft):
            return .leading
        case (.leading, .leftToRight), (.trailing, .leftToRight):
            return self
        }
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

    var retainedKinds: RetainedContentShapeKinds {
        var retained: RetainedContentShapeKinds = []
        if contains(.interaction) { retained.insert(.interaction) }
        if contains(.dragPreview) { retained.insert(.dragPreview) }
        if contains(.contextMenuPreview) { retained.insert(.contextMenuPreview) }
        if contains(.focusEffect) { retained.insert(.focusEffect) }
        if contains(.hoverEffect) { retained.insert(.hoverEffect) }
        if contains(.accessibility) { retained.insert(.accessibility) }
        return retained
    }
}

public struct AccessibilityTraits: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)
    public static let isLink = AccessibilityTraits(rawValue: 1 << 3)
    public static let isImage = AccessibilityTraits(rawValue: 1 << 4)
    public static let isSearchField = AccessibilityTraits(rawValue: 1 << 5)
    public static let isKeyboardKey = AccessibilityTraits(rawValue: 1 << 6)
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 7)
    public static let isSummaryElement = AccessibilityTraits(rawValue: 1 << 8)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 9)
    public static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 10)
    public static let playsSound = AccessibilityTraits(rawValue: 1 << 11)
    public static let allowsDirectInteraction = AccessibilityTraits(rawValue: 1 << 12)
    public static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 13)
    public static let isModal = AccessibilityTraits(rawValue: 1 << 14)

    var retainedTraits: RetainedAccessibilityTraits {
        RetainedAccessibilityTraits(rawValue: rawValue)
    }
}

public enum AccessibilityChildBehavior: Sendable, Equatable, Hashable {
    case ignore
    case combine
    case contain

    var retainedBehavior: RetainedAccessibilityChildBehavior {
        switch self {
        case .ignore:
            return .ignore
        case .combine:
            return .combine
        case .contain:
            return .contain
        }
    }
}

public enum AccessibilityActionKind: Sendable, Equatable, Hashable {
    case `default`
    case escape
    case magicTap
    case increment
    case decrement

    var retainedKind: RetainedAccessibilityActionKind {
        switch self {
        case .default:
            return .default
        case .escape:
            return .escape
        case .magicTap:
            return .magicTap
        case .increment:
            return .increment
        case .decrement:
            return .decrement
        }
    }
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

public enum MoveCommandDirection: Sendable, Equatable, Hashable {
    case up
    case down
    case left
    case right
}

public struct GestureMask: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let gesture = GestureMask(rawValue: 1 << 0)
    public static let subviews = GestureMask(rawValue: 1 << 1)
    public static let all: GestureMask = [.gesture, .subviews]
    public static let none: GestureMask = []
}

@MainActor
public protocol Gesture {
    associatedtype Value

    func _applying<V: View>(to view: V, including mask: GestureMask) -> AnyView
}

public enum CoordinateSpace: Sendable, Equatable, Hashable {
    case global
    case local
    case named(String)
}

public struct TapGesture: Gesture {
    public typealias Value = Void

    public var count: Int
    private let endedAction: (@MainActor () -> Void)?

    public init(count: Int = 1) {
        self.count = count
        self.endedAction = nil
    }

    private init(count: Int, endedAction: (@MainActor () -> Void)?) {
        self.count = count
        self.endedAction = endedAction
    }

    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> TapGesture {
        TapGesture(count: count, endedAction: {
            action(())
        })
    }

    public func _applying<V: View>(to view: V, including mask: GestureMask) -> AnyView {
        guard mask.contains(.gesture) else {
            return AnyView(view)
        }

        return AnyView(
            view.onTapGesture(count: count) {
                endedAction?()
            }
        )
    }
}

public struct SpatialTapGesture: Gesture {
    public struct Value: Sendable, Equatable {
        public var location: CGPoint

        public init(location: CGPoint) {
            self.location = location
        }
    }

    public var count: Int
    public var coordinateSpace: CoordinateSpace
    private let endedAction: (@MainActor (Value) -> Void)?

    public init(count: Int = 1, coordinateSpace: CoordinateSpace = .local) {
        self.count = count
        self.coordinateSpace = coordinateSpace
        self.endedAction = nil
    }

    private init(
        count: Int,
        coordinateSpace: CoordinateSpace,
        endedAction: (@MainActor (Value) -> Void)?
    ) {
        self.count = count
        self.coordinateSpace = coordinateSpace
        self.endedAction = endedAction
    }

    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> SpatialTapGesture {
        SpatialTapGesture(
            count: count,
            coordinateSpace: coordinateSpace,
            endedAction: action
        )
    }

    public func _applying<V: View>(to view: V, including mask: GestureMask) -> AnyView {
        guard mask.contains(.gesture) else {
            return AnyView(view)
        }

        return AnyView(
            view.onTapGesture(count: count, coordinateSpace: coordinateSpace) { location in
                endedAction?(Value(location: location))
            }
        )
    }
}

public struct LongPressGesture: Gesture {
    public typealias Value = Bool

    public var minimumDuration: Double
    public var maximumDistance: CGFloat
    private let changedAction: (@MainActor (Bool) -> Void)?
    private let endedAction: (@MainActor (Bool) -> Void)?

    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
        self.changedAction = nil
        self.endedAction = nil
    }

    private init(
        minimumDuration: Double,
        maximumDistance: CGFloat,
        changedAction: (@MainActor (Bool) -> Void)?,
        endedAction: (@MainActor (Bool) -> Void)?
    ) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
        self.changedAction = changedAction
        self.endedAction = endedAction
    }

    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> LongPressGesture {
        LongPressGesture(
            minimumDuration: minimumDuration,
            maximumDistance: maximumDistance,
            changedAction: action,
            endedAction: endedAction
        )
    }

    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> LongPressGesture {
        LongPressGesture(
            minimumDuration: minimumDuration,
            maximumDistance: maximumDistance,
            changedAction: changedAction,
            endedAction: action
        )
    }

    public func _applying<V: View>(to view: V, including mask: GestureMask) -> AnyView {
        guard mask.contains(.gesture) else {
            return AnyView(view)
        }

        return AnyView(
            view.onLongPressGesture(
                minimumDuration: minimumDuration,
                maximumDistance: maximumDistance,
                perform: {
                    endedAction?(true)
                },
                onPressingChanged: { isPressing in
                    changedAction?(isPressing)
                }
            )
        )
    }
}

public struct DragGesture: Gesture {
    public struct Value: Sendable, Equatable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize
        public var predictedEndLocation: CGPoint
        public var predictedEndTranslation: CGSize

        public init(
            time: Date,
            location: CGPoint,
            startLocation: CGPoint,
            translation: CGSize,
            predictedEndLocation: CGPoint,
            predictedEndTranslation: CGSize
        ) {
            self.time = time
            self.location = location
            self.startLocation = startLocation
            self.translation = translation
            self.predictedEndLocation = predictedEndLocation
            self.predictedEndTranslation = predictedEndTranslation
        }
    }

    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace
    private let changedAction: (@MainActor (Value) -> Void)?
    private let endedAction: (@MainActor (Value) -> Void)?

    public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
        self.changedAction = nil
        self.endedAction = nil
    }

    private init(
        minimumDistance: CGFloat,
        coordinateSpace: CoordinateSpace,
        changedAction: (@MainActor (Value) -> Void)?,
        endedAction: (@MainActor (Value) -> Void)?
    ) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
        self.changedAction = changedAction
        self.endedAction = endedAction
    }

    public func onChanged(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture {
        DragGesture(
            minimumDistance: minimumDistance,
            coordinateSpace: coordinateSpace,
            changedAction: action,
            endedAction: endedAction
        )
    }

    public func onEnded(_ action: @escaping @MainActor (Value) -> Void) -> DragGesture {
        DragGesture(
            minimumDistance: minimumDistance,
            coordinateSpace: coordinateSpace,
            changedAction: changedAction,
            endedAction: action
        )
    }

    public func _applying<V: View>(to view: V, including mask: GestureMask) -> AnyView {
        guard mask.contains(.gesture) else {
            return AnyView(view)
        }

        return AnyView(
            ModifiedView(content: view) { content, context in
                let child = content.makeComponent(context: context)
                let minimumDistance = max(0, self.minimumDistance)
                return Component { runtime in
                    let childNode = child.makeNode(runtime: runtime)
                    childNode.isHitTestVisible = true
                    var startLocation: CGPoint?
                    var hasRecognized = false

                    func makeValue(location: CGPoint, translation: CGSize) -> Value {
                        let start = startLocation ?? CGPoint(
                            x: location.x - translation.width,
                            y: location.y - translation.height
                        )
                        return Value(
                            time: Date(),
                            location: location,
                            startLocation: start,
                            translation: translation,
                            predictedEndLocation: location,
                            predictedEndTranslation: translation
                        )
                    }

                    let existingOnDragStart = childNode.onDragStart
                    childNode.onDragStart = { point in
                        existingOnDragStart?(point)
                        startLocation = point
                        hasRecognized = minimumDistance == 0
                        if hasRecognized {
                            changedAction?(makeValue(location: point, translation: CGSize(width: 0, height: 0)))
                        }
                    }

                    let existingOnDragChange = childNode.onDragChange
                    childNode.onDragChange = { point, delta in
                        existingOnDragChange?(point, delta)
                        let distance = hypot(delta.x, delta.y)
                        guard hasRecognized || distance >= minimumDistance else {
                            return
                        }

                        hasRecognized = true
                        changedAction?(makeValue(location: point, translation: CGSize(width: delta.x, height: delta.y)))
                    }

                    let existingOnDragEnd = childNode.onDragEnd
                    childNode.onDragEnd = { point, delta in
                        existingOnDragEnd?(point, delta)
                        defer {
                            startLocation = nil
                            hasRecognized = false
                        }

                        let distance = hypot(delta.x, delta.y)
                        guard hasRecognized || distance >= minimumDistance else {
                            return
                        }

                        endedAction?(makeValue(location: point, translation: CGSize(width: delta.x, height: delta.y)))
                    }

                    return childNode
                }
            }
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
        self.init(
            lineWidth: lineWidth,
            dashPattern: dash,
            dashOffset: dashPhase,
            lineCap: lineCap,
            lineJoin: lineJoin,
            miterLimit: miterLimit
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

    var retainedSubmitLabel: RetainedSubmitLabel {
        switch self {
        case .return:
            return .return
        case .done:
            return .done
        case .go:
            return .go
        case .send:
            return .send
        case .join:
            return .join
        case .route:
            return .route
        case .search:
            return .search
        case .next:
            return .next
        case .continue:
            return .continue
        }
    }
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
        case serif
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

    public enum Leading: Sendable, Equatable {
        case standard
        case tight
        case loose
    }

    public var size: Double
    public var weight: Weight
    public var design: Design
    public var family: String?
    public var leading: Leading
    public var scalesWithDynamicType: Bool

    public init(
        size: Double,
        weight: Weight = .regular,
        design: Design = .default,
        family: String? = nil,
        leading: Leading = .standard,
        scalesWithDynamicType: Bool = true
    ) {
        self.size = size
        self.weight = weight
        self.design = design
        self.family = family
        self.leading = leading
        self.scalesWithDynamicType = scalesWithDynamicType
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
            family: font.family,
            leading: font.leading,
            scalesWithDynamicType: font.scalesWithDynamicType
        )
    }

    public static func custom(_ name: String, size: CGFloat) -> Font {
        Font(size: size, family: name)
    }

    public static func custom(_ name: String, fixedSize: CGFloat) -> Font {
        Font(size: fixedSize, family: name, scalesWithDynamicType: false)
    }

    public static func custom(_ name: String, size: CGFloat, relativeTo textStyle: TextStyle) -> Font {
        let font = defaultFont(for: textStyle)
        return Font(
            size: size,
            weight: font.weight,
            design: font.design,
            family: name,
            leading: font.leading,
            scalesWithDynamicType: font.scalesWithDynamicType
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
        Font(
            size: size,
            weight: weight,
            design: design,
            family: family,
            leading: leading,
            scalesWithDynamicType: scalesWithDynamicType
        )
    }

    public func monospaced() -> Font {
        monospaced(true)
    }

    public func monospaced(_ isActive: Bool) -> Font {
        withDesign(isActive ? .monospaced : .default)
    }

    public func leading(_ leading: Leading) -> Font {
        Font(
            size: size,
            weight: weight,
            design: design,
            family: family,
            leading: leading,
            scalesWithDynamicType: scalesWithDynamicType
        )
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
        case accessoryBar
        case accessoryBarAction
        case plain
        case bordered
        case borderedProminent
        case borderless
        case card
        case link
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonStyle(kind: .automatic)
    public static let accessoryBar = ButtonStyle(kind: .accessoryBar)
    public static let accessoryBarAction = ButtonStyle(kind: .accessoryBarAction)
    public static let plain = ButtonStyle(kind: .plain)
    public static let bordered = ButtonStyle(kind: .bordered)
    public static let borderedProminent = ButtonStyle(kind: .borderedProminent)
    public static let borderless = ButtonStyle(kind: .borderless)
    public static let card = ButtonStyle(kind: .card)
    public static let link = ButtonStyle(kind: .link)

    var surfaceStyle: ButtonSurfaceStyle {
        switch kind {
        case .automatic, .accessoryBar, .accessoryBarAction, .bordered, .borderedProminent, .card:
            return .default
        case .plain, .borderless, .link:
            return .plain
        }
    }
}

public struct DefaultButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct AccessoryBarButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct AccessoryBarActionButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct PlainButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct BorderedButtonStyle: Sendable, Equatable {
    public var tint: Color?

    public init() {
        self.tint = nil
    }

    public init(tint: Color) {
        self.tint = tint
    }
}

public struct BorderedProminentButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct BorderlessButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct CardButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct LinkButtonStyle: Sendable, Equatable {
    public init() {}
}

public struct ToolbarItemPlacement: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case principal
        case navigation
        case primaryAction
        case confirmationAction
        case cancellationAction
        case destructiveAction
        case status
        case bottomBar
        case keyboard
        case topBarLeading
        case topBarTrailing
        case navigationBarLeading
        case navigationBarTrailing
        case navigationBar
        case tabBar
        case windowToolbar
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ToolbarItemPlacement(.automatic)
    public static let principal = ToolbarItemPlacement(.principal)
    public static let navigation = ToolbarItemPlacement(.navigation)
    public static let primaryAction = ToolbarItemPlacement(.primaryAction)
    public static let confirmationAction = ToolbarItemPlacement(.confirmationAction)
    public static let cancellationAction = ToolbarItemPlacement(.cancellationAction)
    public static let destructiveAction = ToolbarItemPlacement(.destructiveAction)
    public static let status = ToolbarItemPlacement(.status)
    public static let bottomBar = ToolbarItemPlacement(.bottomBar)
    public static let keyboard = ToolbarItemPlacement(.keyboard)
    public static let topBarLeading = ToolbarItemPlacement(.topBarLeading)
    public static let topBarTrailing = ToolbarItemPlacement(.topBarTrailing)
    public static let navigationBarLeading = ToolbarItemPlacement(.navigationBarLeading)
    public static let navigationBarTrailing = ToolbarItemPlacement(.navigationBarTrailing)
    public static let navigationBar = ToolbarItemPlacement(.navigationBar)
    public static let tabBar = ToolbarItemPlacement(.tabBar)
    public static let windowToolbar = ToolbarItemPlacement(.windowToolbar)
}

public struct ToolbarRole: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case navigationStack
        case editor
        case browser
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ToolbarRole(.automatic)
    public static let navigationStack = ToolbarRole(.navigationStack)
    public static let editor = ToolbarRole(.editor)
    public static let browser = ToolbarRole(.browser)
}

public struct ToolbarTitleDisplayMode: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case inline
        case inlineLarge
        case large
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ToolbarTitleDisplayMode(.automatic)
    public static let inline = ToolbarTitleDisplayMode(.inline)
    public static let inlineLarge = ToolbarTitleDisplayMode(.inlineLarge)
    public static let large = ToolbarTitleDisplayMode(.large)
}

public struct ButtonRepeatBehavior: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case enabled
        case disabled
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonRepeatBehavior(.automatic)
    public static let enabled = ButtonRepeatBehavior(.enabled)
    public static let disabled = ButtonRepeatBehavior(.disabled)

    var retainedBehavior: RetainedButtonRepeatBehavior {
        switch kind {
        case .automatic:
            return .automatic
        case .enabled:
            return .enabled
        case .disabled:
            return .disabled
        }
    }
}

public struct ButtonSizing: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case fitted
        case flexible
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonSizing(.automatic)
    public static let fitted = ButtonSizing(.fitted)
    public static let flexible = ButtonSizing(.flexible)

    var retainedLayoutPriority: Double {
        kind == .flexible ? 1 : 0
    }
}

public struct ButtonBorderShape: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case capsule
        case circle
        case roundedRectangle(Double?)
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ButtonBorderShape(.automatic)
    public static let capsule = ButtonBorderShape(.capsule)
    public static let circle = ButtonBorderShape(.circle)
    public static let roundedRectangle = ButtonBorderShape(.roundedRectangle(nil))

    public static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape {
        ButtonBorderShape(.roundedRectangle(max(0, radius)))
    }

    func retainedCornerRadius(default defaultRadius: Double) -> Double {
        switch kind {
        case .automatic:
            return defaultRadius
        case .roundedRectangle(let radius):
            return radius ?? defaultRadius
        case .capsule, .circle:
            return 0
        }
    }

    @MainActor
    func applyRetainedDynamicCornerRadius(to node: ViewNode) {
        switch kind {
        case .capsule, .circle:
            let existingOnLayout = node.onLayout
            node.onLayout = { [weak node] bounds in
                existingOnLayout?(bounds)
                let radius = max(0, min(bounds.size.width, bounds.size.height) * 0.5)
                if node?.cornerRadius != radius {
                    node?.cornerRadius = radius
                }
            }
        case .automatic, .roundedRectangle:
            break
        }
    }
}

public struct PickerStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case inline
        case segmented
        case menu
        case navigationLink
        case palette
        case radioGroup
        case wheel
        case popUpButton
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PickerStyle(kind: .automatic)
    public static let inline = PickerStyle(kind: .inline)
    public static let segmented = PickerStyle(kind: .segmented)
    public static let menu = PickerStyle(kind: .menu)
    public static let navigationLink = PickerStyle(kind: .navigationLink)
    public static let palette = PickerStyle(kind: .palette)
    public static let radioGroup = PickerStyle(kind: .radioGroup)
    public static let wheel = PickerStyle(kind: .wheel)
    @available(*, deprecated, message: "Use MenuPickerStyle instead.")
    public static let popUpButton = PickerStyle(kind: .popUpButton)
}

public struct DefaultPickerStyle: Sendable, Equatable {
    public init() {}
}

public struct InlinePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct SegmentedPickerStyle: Sendable, Equatable {
    public init() {}
}

public struct MenuPickerStyle: Sendable, Equatable {
    public init() {}
}

public struct NavigationLinkPickerStyle: Sendable, Equatable {
    public init() {}
}

public struct PalettePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct RadioGroupPickerStyle: Sendable, Equatable {
    public init() {}
}

public struct WheelPickerStyle: Sendable, Equatable {
    public init() {}
}

@available(*, deprecated, message: "Use MenuPickerStyle instead.")
public struct PopUpButtonPickerStyle: Sendable, Equatable {
    public init() {}
}

public struct GaugeStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case linear
        case linearCapacity
        case accessoryLinear
        case accessoryLinearCapacity
        case circular
        case accessoryCircular
        case accessoryCircularCapacity
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = GaugeStyle(kind: .automatic)
    public static let linear = GaugeStyle(kind: .linear)
    public static let linearCapacity = GaugeStyle(kind: .linearCapacity)
    public static let accessoryLinear = GaugeStyle(kind: .accessoryLinear)
    public static let accessoryLinearCapacity = GaugeStyle(kind: .accessoryLinearCapacity)
    public static let circular = GaugeStyle(kind: .circular)
    public static let accessoryCircular = GaugeStyle(kind: .accessoryCircular)
    public static let accessoryCircularCapacity = GaugeStyle(kind: .accessoryCircularCapacity)
}

public struct DefaultGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct LinearGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct LinearCapacityGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct AccessoryLinearGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct AccessoryLinearCapacityGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct CircularGaugeStyle: Sendable, Equatable {
    public var tint: Color?

    public init(tint: Color? = nil) {
        self.tint = tint
    }
}

public struct AccessoryCircularGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct AccessoryCircularCapacityGaugeStyle: Sendable, Equatable {
    public init() {}
}

public struct ProgressViewStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case linear
        case circular
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ProgressViewStyle(kind: .automatic)
    public static let linear = ProgressViewStyle(kind: .linear)
    public static let circular = ProgressViewStyle(kind: .circular)
}

public struct DefaultProgressViewStyle: Sendable, Equatable {
    public init() {}
}

public struct LinearProgressViewStyle: Sendable, Equatable {
    public init() {}
}

public struct CircularProgressViewStyle: Sendable, Equatable {
    public init() {}
}

public struct DatePickerStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case compact
        case field
        case graphical
        case stepperField
        case wheel
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = DatePickerStyle(kind: .automatic)
    public static let compact = DatePickerStyle(kind: .compact)
    public static let field = DatePickerStyle(kind: .field)
    public static let graphical = DatePickerStyle(kind: .graphical)
    public static let stepperField = DatePickerStyle(kind: .stepperField)
    public static let wheel = DatePickerStyle(kind: .wheel)
}

public struct DefaultDatePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct CompactDatePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct FieldDatePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct GraphicalDatePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct StepperFieldDatePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct WheelDatePickerStyle: Sendable, Equatable {
    public init() {}
}

public struct ControlGroupStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case compactMenu
        case menu
        case navigation
        case palette
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ControlGroupStyle(kind: .automatic)
    public static let compactMenu = ControlGroupStyle(kind: .compactMenu)
    public static let menu = ControlGroupStyle(kind: .menu)
    public static let navigation = ControlGroupStyle(kind: .navigation)
    public static let palette = ControlGroupStyle(kind: .palette)
}

public struct AutomaticControlGroupStyle: Sendable, Equatable {
    public init() {}
}

public struct CompactMenuControlGroupStyle: Sendable, Equatable {
    public init() {}
}

public struct MenuControlGroupStyle: Sendable, Equatable {
    public init() {}
}

public struct NavigationControlGroupStyle: Sendable, Equatable {
    public init() {}
}

public struct PaletteControlGroupStyle: Sendable, Equatable {
    public init() {}
}

public struct TabViewStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case sidebarAdaptable
        case tabBarOnly
        case grouped
        case page(indexDisplayMode: PageTabViewStyle.IndexDisplayMode)
        case verticalPage(transitionStyle: VerticalPageTabViewStyle.TransitionStyle)
        case carousel
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = TabViewStyle(kind: .automatic)
    public static let sidebarAdaptable = TabViewStyle(kind: .sidebarAdaptable)
    public static let tabBarOnly = TabViewStyle(kind: .tabBarOnly)
    public static let grouped = TabViewStyle(kind: .grouped)
    public static let page = TabViewStyle(kind: .page(indexDisplayMode: .automatic))
    public static func page(indexDisplayMode: PageTabViewStyle.IndexDisplayMode) -> TabViewStyle {
        TabViewStyle(kind: .page(indexDisplayMode: indexDisplayMode))
    }
    public static let verticalPage = TabViewStyle(kind: .verticalPage(transitionStyle: .automatic))
    public static func verticalPage(transitionStyle: VerticalPageTabViewStyle.TransitionStyle) -> TabViewStyle {
        TabViewStyle(kind: .verticalPage(transitionStyle: transitionStyle))
    }
    public static let carousel = TabViewStyle(kind: .carousel)
}

public struct DefaultTabViewStyle: Sendable, Equatable {
    public init() {}
}

public struct SidebarAdaptableTabViewStyle: Sendable, Equatable {
    public init() {}
}

public struct TabBarOnlyTabViewStyle: Sendable, Equatable {
    public init() {}
}

public struct GroupedTabViewStyle: Sendable, Equatable {
    public init() {}
}

public struct PageTabViewStyle: Sendable, Equatable {
    public struct IndexDisplayMode: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case automatic
            case always
            case never
        }

        let kind: Kind

        private init(_ kind: Kind) {
            self.kind = kind
        }

        public static let automatic = IndexDisplayMode(.automatic)
        public static let always = IndexDisplayMode(.always)
        public static let never = IndexDisplayMode(.never)
    }

    public var indexDisplayMode: IndexDisplayMode

    public init(indexDisplayMode: IndexDisplayMode = .automatic) {
        self.indexDisplayMode = indexDisplayMode
    }
}

public struct VerticalPageTabViewStyle: Sendable, Equatable {
    public struct TransitionStyle: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case automatic
            case blur
            case identity
        }

        let kind: Kind

        private init(_ kind: Kind) {
            self.kind = kind
        }

        public static let automatic = TransitionStyle(.automatic)
        public static let blur = TransitionStyle(.blur)
        public static let identity = TransitionStyle(.identity)
    }

    public var transitionStyle: TransitionStyle

    public init(transitionStyle: TransitionStyle = .automatic) {
        self.transitionStyle = transitionStyle
    }
}

public struct CarouselTabViewStyle: Sendable, Equatable {
    public init() {}
}

public struct IndexViewStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case page(backgroundDisplayMode: PageIndexViewStyle.BackgroundDisplayMode)
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let page = IndexViewStyle(kind: .page(backgroundDisplayMode: .automatic))
    public static func page(backgroundDisplayMode: PageIndexViewStyle.BackgroundDisplayMode) -> IndexViewStyle {
        IndexViewStyle(kind: .page(backgroundDisplayMode: backgroundDisplayMode))
    }
}

public struct PageIndexViewStyle: Sendable, Equatable {
    public struct BackgroundDisplayMode: Sendable, Equatable, Hashable {
        enum Kind: Sendable, Equatable, Hashable {
            case automatic
            case always
            case interactive
            case never
        }

        let kind: Kind

        private init(_ kind: Kind) {
            self.kind = kind
        }

        public static let automatic = BackgroundDisplayMode(.automatic)
        public static let always = BackgroundDisplayMode(.always)
        public static let interactive = BackgroundDisplayMode(.interactive)
        public static let never = BackgroundDisplayMode(.never)
    }

    public var backgroundDisplayMode: BackgroundDisplayMode

    public init(backgroundDisplayMode: BackgroundDisplayMode = .automatic) {
        self.backgroundDisplayMode = backgroundDisplayMode
    }
}

public struct GroupBoxStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
    }

    let kind: Kind

    public init() {
        self.kind = .automatic
    }

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = GroupBoxStyle(kind: .automatic)
}

public typealias DefaultGroupBoxStyle = GroupBoxStyle

public struct FormStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case columns
        case grouped
    }

    let kind: Kind

    public init() {
        self.kind = .automatic
    }

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = FormStyle(kind: .automatic)
    public static let columns = FormStyle(kind: .columns)
    public static let grouped = FormStyle(kind: .grouped)
}

public struct AutomaticFormStyle: Sendable, Equatable {
    public init() {}
}

public struct ColumnsFormStyle: Sendable, Equatable {
    public init() {}
}

public struct GroupedFormStyle: Sendable, Equatable {
    public init() {}
}

public struct LabeledContentStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
    }

    let kind: Kind

    public init() {
        self.kind = .automatic
    }

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = LabeledContentStyle(kind: .automatic)
}

public typealias AutomaticLabeledContentStyle = LabeledContentStyle

public struct DisclosureGroupStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
    }

    let kind: Kind

    public init() {
        self.kind = .automatic
    }

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = DisclosureGroupStyle(kind: .automatic)
}

public typealias AutomaticDisclosureGroupStyle = DisclosureGroupStyle

public struct MenuStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case button
        case borderedButtonStyle(showsMenuIndicator: Bool)
        case borderlessButtonStyle(showsMenuIndicator: Bool)
    }

    let kind: Kind

    public init() {
        self.kind = .automatic
    }

    init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = MenuStyle(kind: .automatic)
    public static let button = MenuStyle(kind: .button)
    public static let borderedButton = MenuStyle(kind: .borderedButtonStyle(showsMenuIndicator: true))
    public static let borderlessButton = MenuStyle(kind: .borderlessButtonStyle(showsMenuIndicator: true))
}

public typealias DefaultMenuStyle = MenuStyle

public struct ButtonMenuStyle: Sendable, Equatable {
    public init() {}
}

public struct BorderedButtonMenuStyle: Sendable, Equatable {
    let showsMenuIndicator: Bool

    public init(showsMenuIndicator: Bool = true) {
        self.showsMenuIndicator = showsMenuIndicator
    }
}

public struct BorderlessButtonMenuStyle: Sendable, Equatable {
    let showsMenuIndicator: Bool

    public init(showsMenuIndicator: Bool = true) {
        self.showsMenuIndicator = showsMenuIndicator
    }
}

public enum ForegroundStyle: Sendable, Equatable {
    case color(Color)
    case linearGradient(LinearGradient)
}

public struct SymbolRenderingMode: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case monochrome
        case hierarchical
        case palette
        case multicolor
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let monochrome = SymbolRenderingMode(kind: .monochrome)
    public static let hierarchical = SymbolRenderingMode(kind: .hierarchical)
    public static let palette = SymbolRenderingMode(kind: .palette)
    public static let multicolor = SymbolRenderingMode(kind: .multicolor)
}

extension SymbolRenderingMode {
    var retainedSymbolRenderingMode: RetainedSymbolRenderingMode {
        switch kind {
        case .monochrome:
            return .monochrome
        case .hierarchical:
            return .hierarchical
        case .palette:
            return .palette
        case .multicolor:
            return .multicolor
        }
    }
}

public struct SymbolVariants: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let none: SymbolVariants = []
    public static let circle = SymbolVariants(rawValue: 1 << 0)
    public static let square = SymbolVariants(rawValue: 1 << 1)
    public static let rectangle = SymbolVariants(rawValue: 1 << 2)
    public static let fill = SymbolVariants(rawValue: 1 << 3)
    public static let slash = SymbolVariants(rawValue: 1 << 4)
}

extension SymbolVariants {
    var retainedSymbolVariants: RetainedSymbolVariants {
        RetainedSymbolVariants(rawValue: rawValue)
    }
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

public struct DefaultLabelStyle: Sendable, Equatable {
    public init() {}
}

public struct IconOnlyLabelStyle: Sendable, Equatable {
    public init() {}
}

public struct TitleAndIconLabelStyle: Sendable, Equatable {
    public init() {}
}

public struct TitleOnlyLabelStyle: Sendable, Equatable {
    public init() {}
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

public struct DefaultToggleStyle: Sendable, Equatable {
    public init() {}
}

public struct SwitchToggleStyle: Sendable, Equatable {
    public init() {}
}

public struct CheckboxToggleStyle: Sendable, Equatable {
    public init() {}
}

public struct ButtonToggleStyle: Sendable, Equatable {
    public init() {}
}

public struct TextFieldStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case plain
        case roundedBorder
        case squareBorder
    }

    let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = TextFieldStyle(kind: .automatic)
    public static let plain = TextFieldStyle(kind: .plain)
    public static let roundedBorder = TextFieldStyle(kind: .roundedBorder)
    public static let squareBorder = TextFieldStyle(kind: .squareBorder)
}

public struct DefaultTextFieldStyle: Sendable, Equatable {
    public init() {}
}

public struct PlainTextFieldStyle: Sendable, Equatable {
    public init() {}
}

public struct RoundedBorderTextFieldStyle: Sendable, Equatable {
    public init() {}
}

public struct SquareBorderTextFieldStyle: Sendable, Equatable {
    public init() {}
}

public struct ListStyle: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case bordered
        case carousel
        case elliptical
        case plain
        case grouped
        case inset
        case insetGrouped
        case sidebar
    }

    let kind: Kind
    private let alternatesRowBackgrounds: Bool?

    private init(kind: Kind, alternatesRowBackgrounds: Bool? = nil) {
        self.kind = kind
        self.alternatesRowBackgrounds = alternatesRowBackgrounds
    }

    public static let automatic = ListStyle(kind: .automatic)
    public static let bordered = ListStyle(kind: .bordered)
    public static let carousel = ListStyle(kind: .carousel)
    public static let elliptical = ListStyle(kind: .elliptical)
    public static let plain = ListStyle(kind: .plain)
    public static let grouped = ListStyle(kind: .grouped)
    public static let inset = ListStyle(kind: .inset)
    public static let insetGrouped = ListStyle(kind: .insetGrouped)
    public static let sidebar = ListStyle(kind: .sidebar)

    static func inset(alternatesRowBackgrounds: Bool?) -> ListStyle {
        ListStyle(kind: .inset, alternatesRowBackgrounds: alternatesRowBackgrounds)
    }

    public static func == (lhs: ListStyle, rhs: ListStyle) -> Bool {
        lhs.kind == rhs.kind
    }

    var retainedChrome: RetainedListChrome {
        switch kind {
        case .automatic, .plain:
            return RetainedListChrome()
        case .bordered:
            return RetainedListChrome(
                defaultSpacing: 0,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                backgroundColor: nil,
                borderColor: Color(red: 0.72, green: 0.80, blue: 0.92, alpha: 0.28),
                borderWidth: 1,
                cornerRadius: 6
            )
        case .carousel, .elliptical:
            return RetainedListChrome(
                defaultSpacing: 6,
                padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8),
                backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.68),
                borderColor: Color(red: 0.72, green: 0.80, blue: 0.92, alpha: 0.14),
                borderWidth: 1,
                cornerRadius: 16
            )
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
                cornerRadius: 0,
                alternatesRowBackgrounds: alternatesRowBackgrounds == true,
                alternatingRowBackgroundColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08)
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

public struct DefaultListStyle: Sendable, Equatable {
    public init() {}
}

public struct BorderedListStyle: Sendable, Equatable {
    public init() {}
}

public struct CarouselListStyle: Sendable, Equatable {
    public init() {}
}

public struct EllipticalListStyle: Sendable, Equatable {
    public init() {}
}

public struct PlainListStyle: Sendable, Equatable {
    public init() {}
}

public struct GroupedListStyle: Sendable, Equatable {
    public init() {}
}

public struct InsetListStyle: Sendable, Equatable {
    let alternatesRowBackgrounds: Bool?

    public init() {
        self.alternatesRowBackgrounds = nil
    }

    public init(alternatesRowBackgrounds: Bool) {
        self.alternatesRowBackgrounds = alternatesRowBackgrounds
    }
}

public struct InsetGroupedListStyle: Sendable, Equatable {
    public init() {}
}

public struct SidebarListStyle: Sendable, Equatable {
    public init() {}
}

struct RetainedListChrome: Sendable, Equatable {
    var defaultSpacing: Double = 0
    var padding: EdgeInsets = .zero
    var backgroundColor: Color? = nil
    var borderColor: Color = .clear
    var borderWidth: Double = 0
    var cornerRadius: Double = 0
    var alternatesRowBackgrounds: Bool = false
    var alternatingRowBackgroundColor: Color? = nil
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

public struct ScrollDismissesKeyboardMode: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case immediately
        case interactively
        case never
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    public static let automatic = ScrollDismissesKeyboardMode(.automatic)
    public static let immediately = ScrollDismissesKeyboardMode(.immediately)
    public static let interactively = ScrollDismissesKeyboardMode(.interactively)
    public static let never = ScrollDismissesKeyboardMode(.never)
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
    var navigationBarBackButtonHidden: Bool?
    var navigationBarHidden: Bool?
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

    var anyNavigationBarBackButtonHidden: Bool? {
        navigationBarBackButtonHidden ?? (content as? any TaggedViewMetadata)?.anyNavigationBarBackButtonHidden
    }

    var anyNavigationBarHidden: Bool? {
        navigationBarHidden ?? (content as? any TaggedViewMetadata)?.anyNavigationBarHidden
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
        (content as? any TaggedViewMetadata)?.anyToolbarItemPlacement
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
    var anyNavigationBarBackButtonHidden: Bool? { get }
    var anyNavigationBarHidden: Bool? { get }
    var anyToolbarItemPlacement: ToolbarItemPlacement? { get }
    var anyNavigationDestinationRegistrations: [NavigationDestinationRegistration] { get }
    var anyNavigationPresentedDestinations: [NavigationPresentedDestination] { get }
}

extension TaggedViewMetadata {
    var anySelectionTag: AnyHashable? {
        nil
    }

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

    var anyNavigationBarBackButtonHidden: Bool? {
        nil
    }

    var anyNavigationBarHidden: Bool? {
        nil
    }

    var anyToolbarItemPlacement: ToolbarItemPlacement? {
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

extension Axis.Set {
    var preferredRetainedAxis: Axis {
        contains(.horizontal) && !contains(.vertical) ? .horizontal : .vertical
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
        Font(
            size: size,
            weight: weight,
            design: design,
            family: family,
            leading: leading,
            scalesWithDynamicType: scalesWithDynamicType
        )
    }

    func scaled(for dynamicTypeSize: DynamicTypeSize) -> Font {
        Font(
            size: scalesWithDynamicType ? size * dynamicTypeSize.retainedFontScale : size,
            weight: weight,
            design: design,
            family: family,
            leading: leading,
            scalesWithDynamicType: scalesWithDynamicType
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
        case .serif:
            return "Georgia"
        case .monospaced:
            return "Cascadia Mono"
        }
    }

    var resolvedLineSpacing: Double {
        switch leading {
        case .standard:
            return 2
        case .tight:
            return 0
        case .loose:
            return 6
        }
    }
}

public extension SwiftWindowsCore.Color {
    enum RGBColorSpace: Sendable, Equatable, Hashable {
        case sRGB
        case sRGBLinear
        case displayP3
    }

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

    init(_ colorSpace: RGBColorSpace = .sRGB, red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.init(
            red: Float(retainedColorChannel(red, colorSpace: colorSpace)),
            green: Float(retainedColorChannel(green, colorSpace: colorSpace)),
            blue: Float(retainedColorChannel(blue, colorSpace: colorSpace)),
            alpha: Float(opacity)
        )
    }

    init(white: Double, opacity: Double = 1.0) {
        let channel = Float(clampedUnitInterval(white))
        self.init(red: channel, green: channel, blue: channel, alpha: Float(clampedUnitInterval(opacity)))
    }

    init(_ colorSpace: RGBColorSpace = .sRGB, white: Double, opacity: Double = 1.0) {
        let channel = Float(retainedColorChannel(clampedUnitInterval(white), colorSpace: colorSpace))
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

    init(_ name: String, bundle: Bundle? = nil) {
        self.init(ColorResource(name: name, bundle: bundle ?? .main))
    }

    init(_ resource: ColorResource) {
        self = resolvedColorResource(resource) ?? SwiftWindowsCore.Color.accentColor
    }

    func opacity(_ value: Double) -> SwiftWindowsCore.Color {
        let components = rgba
        return SwiftWindowsCore.Color(red: components.0, green: components.1, blue: components.2, alpha: Float(value))
    }

    func resolvedForContrast(_ contrast: ColorSchemeContrast) -> SwiftWindowsCore.Color {
        guard contrast == .increased, self == .secondary else {
            return self
        }

        return resolvedHighContrastSecondary()
    }

    func resolvedForBackgroundProminence(_ prominence: BackgroundProminence) -> SwiftWindowsCore.Color {
        guard prominence == .increased, self == .secondary else {
            return self
        }

        return resolvedHighContrastSecondary()
    }

    func resolvedForVisualEnvironment(
        contrast: ColorSchemeContrast,
        backgroundProminence: BackgroundProminence
    ) -> SwiftWindowsCore.Color {
        resolvedForContrast(contrast)
            .resolvedForBackgroundProminence(backgroundProminence)
    }

    private func resolvedHighContrastSecondary() -> SwiftWindowsCore.Color {
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

    func resolvedForVisualEnvironment(
        contrast: ColorSchemeContrast,
        backgroundProminence: BackgroundProminence
    ) -> ForegroundStyle {
        switch self {
        case .color(let color):
            return .color(
                color.resolvedForVisualEnvironment(
                    contrast: contrast,
                    backgroundProminence: backgroundProminence
                )
            )
        case .linearGradient(let gradient):
            return .linearGradient(
                gradient.resolvedForVisualEnvironment(
                    contrast: contrast,
                    backgroundProminence: backgroundProminence
                )
            )
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

    func resolvedForVisualEnvironment(
        contrast: ColorSchemeContrast,
        backgroundProminence: BackgroundProminence
    ) -> LinearGradient {
        LinearGradient(
            startColor: startColor.resolvedForVisualEnvironment(
                contrast: contrast,
                backgroundProminence: backgroundProminence
            ),
            endColor: endColor.resolvedForVisualEnvironment(
                contrast: contrast,
                backgroundProminence: backgroundProminence
            ),
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

private func retainedColorChannel(
    _ value: Double,
    colorSpace: SwiftWindowsCore.Color.RGBColorSpace
) -> Double {
    switch colorSpace {
    case .sRGB, .displayP3:
        return value
    case .sRGBLinear:
        return linearSRGBChannelToDisplaySRGB(value)
    }
}

private func linearSRGBChannelToDisplaySRGB(_ value: Double) -> Double {
    let channel = clampedUnitInterval(value)
    if channel <= 0.0031308 {
        return 12.92 * channel
    }

    return 1.055 * pow(channel, 1.0 / 2.4) - 0.055
}

private func orderedRetainedToolbarViews(_ views: [AnyView]) -> [AnyView] {
    views.enumerated()
        .sorted { lhs, rhs in
            let leftKey = retainedToolbarPlacementOrder(lhs.element.toolbarItemPlacement)
            let rightKey = retainedToolbarPlacementOrder(rhs.element.toolbarItemPlacement)
            if leftKey != rightKey {
                return leftKey < rightKey
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
}

private func retainedToolbarPlacementOrder(_ placement: ToolbarItemPlacement?) -> Int {
    guard let placement else {
        return 20
    }

    switch placement {
    case .navigation, .topBarLeading, .navigationBarLeading:
        return 0
    case .principal:
        return 10
    case .status:
        return 15
    case .automatic:
        return 20
    case .primaryAction, .confirmationAction, .destructiveAction, .cancellationAction, .topBarTrailing, .navigationBarTrailing:
        return 30
    case .bottomBar:
        return 40
    case .tabBar:
        return 50
    case .keyboard:
        return 60
    case .navigationBar:
        return 70
    case .windowToolbar:
        return 80
    default:
        return 20
    }
}

private func retainedToolbarPlacementTags(for views: [AnyView]) -> Set<String> {
    let tags = Set(views.compactMap { view in
        view.toolbarItemPlacement.map(retainedToolbarPlacementTag)
    })
    return tags.isEmpty ? [retainedToolbarPlacementTag(.automatic)] : tags
}

private func retainedToolbarMatches(_ tags: Set<String>, bars: [ToolbarItemPlacement]) -> Bool {
    guard !bars.isEmpty else {
        return true
    }

    let resolvedTags = tags.isEmpty ? [retainedToolbarPlacementTag(.automatic)] : tags
    return bars.contains { bar in
        retainedToolbarBarTags(for: bar).contains { resolvedTags.contains($0) }
    }
}

private func retainedToolbarBarTags(for bar: ToolbarItemPlacement) -> Set<String> {
    switch bar {
    case .automatic:
        return [
            retainedToolbarPlacementTag(.automatic),
            retainedToolbarPlacementTag(.principal),
            retainedToolbarPlacementTag(.navigation),
            retainedToolbarPlacementTag(.primaryAction),
            retainedToolbarPlacementTag(.confirmationAction),
            retainedToolbarPlacementTag(.cancellationAction),
            retainedToolbarPlacementTag(.destructiveAction),
            retainedToolbarPlacementTag(.status),
            retainedToolbarPlacementTag(.bottomBar),
            retainedToolbarPlacementTag(.keyboard),
            retainedToolbarPlacementTag(.topBarLeading),
            retainedToolbarPlacementTag(.topBarTrailing),
            retainedToolbarPlacementTag(.navigationBarLeading),
            retainedToolbarPlacementTag(.navigationBarTrailing),
            retainedToolbarPlacementTag(.navigationBar),
            retainedToolbarPlacementTag(.tabBar),
            retainedToolbarPlacementTag(.windowToolbar)
        ]
    case .navigationBar:
        return [
            retainedToolbarPlacementTag(.automatic),
            retainedToolbarPlacementTag(.principal),
            retainedToolbarPlacementTag(.navigation),
            retainedToolbarPlacementTag(.primaryAction),
            retainedToolbarPlacementTag(.confirmationAction),
            retainedToolbarPlacementTag(.cancellationAction),
            retainedToolbarPlacementTag(.destructiveAction),
            retainedToolbarPlacementTag(.status),
            retainedToolbarPlacementTag(.topBarLeading),
            retainedToolbarPlacementTag(.topBarTrailing),
            retainedToolbarPlacementTag(.navigationBarLeading),
            retainedToolbarPlacementTag(.navigationBarTrailing),
            retainedToolbarPlacementTag(.navigationBar)
        ]
    default:
        return [retainedToolbarPlacementTag(bar)]
    }
}

private func retainedToolbarPlacementTag(_ placement: ToolbarItemPlacement) -> String {
    switch placement {
    case .automatic:
        return "automatic"
    case .principal:
        return "principal"
    case .navigation:
        return "navigation"
    case .primaryAction:
        return "primaryAction"
    case .confirmationAction:
        return "confirmationAction"
    case .cancellationAction:
        return "cancellationAction"
    case .destructiveAction:
        return "destructiveAction"
    case .status:
        return "status"
    case .bottomBar:
        return "bottomBar"
    case .keyboard:
        return "keyboard"
    case .topBarLeading:
        return "topBarLeading"
    case .topBarTrailing:
        return "topBarTrailing"
    case .navigationBarLeading:
        return "navigationBarLeading"
    case .navigationBarTrailing:
        return "navigationBarTrailing"
    case .navigationBar:
        return "navigationBar"
    case .tabBar:
        return "tabBar"
    case .windowToolbar:
        return "windowToolbar"
    default:
        return "automatic"
    }
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

private func resolvedColorResource(_ resource: ColorResource) -> SwiftWindowsCore.Color? {
    parsedHexColor(resource.name)
}

private func parsedHexColor(_ value: String) -> SwiftWindowsCore.Color? {
    var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") {
        hex.removeFirst()
    } else if hex.lowercased().hasPrefix("0x") {
        hex.removeFirst(2)
    }
    hex.removeAll { $0 == "_" || $0 == "-" }

    let expanded: String
    switch hex.count {
    case 3, 4:
        expanded = hex.map { "\($0)\($0)" }.joined()
    case 6, 8:
        expanded = hex
    default:
        return nil
    }

    guard expanded.allSatisfy(\.isHexDigit),
          let rawValue = UInt32(expanded, radix: 16) else {
        return nil
    }

    let red: UInt32
    let green: UInt32
    let blue: UInt32
    let alpha: UInt32
    if expanded.count == 8 {
        red = (rawValue >> 24) & 0xFF
        green = (rawValue >> 16) & 0xFF
        blue = (rawValue >> 8) & 0xFF
        alpha = rawValue & 0xFF
    } else {
        red = (rawValue >> 16) & 0xFF
        green = (rawValue >> 8) & 0xFF
        blue = rawValue & 0xFF
        alpha = 0xFF
    }

    return SwiftWindowsCore.Color(
        red: Float(red) / 255.0,
        green: Float(green) / 255.0,
        blue: Float(blue) / 255.0,
        alpha: Float(alpha) / 255.0
    )
}

private func resolvedStyleColor(from style: ForegroundStyle) -> Color {
    switch style {
    case .color(let color):
        return color
    case .linearGradient(let gradient):
        return gradient.startColor
    }
}

private func resolvedBorderFill(from style: ForegroundStyle) -> (color: Color, gradient: LinearGradient?) {
    switch style {
    case .color(let color):
        return (color, nil)
    case .linearGradient(let gradient):
        return (gradient.startColor, gradient)
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

@MainActor
private func applyToolbarBackgroundStyle(
    to node: ViewNode,
    color: Color?,
    gradient: LinearGradient?,
    bars: [ToolbarItemPlacement] = []
) {
    if node.isToolbarContainer, retainedToolbarMatches(node.toolbarPlacementTags, bars: bars) {
        node.backgroundColor = color
        node.backgroundGradient = gradient
    }

    for child in node.children {
        applyToolbarBackgroundStyle(to: child, color: color, gradient: gradient, bars: bars)
    }
}

@MainActor
private func applyToolbarVisibility(to node: ViewNode, visibility: Visibility, bars: [ToolbarItemPlacement] = []) {
    if node.isToolbarContainer, retainedToolbarMatches(node.toolbarPlacementTags, bars: bars) {
        switch visibility {
        case .hidden:
            node.isHidden = true
        case .visible:
            node.isHidden = false
        case .automatic:
            break
        }
    }

    for child in node.children {
        applyToolbarVisibility(to: child, visibility: visibility, bars: bars)
    }
}

@MainActor
private func applyToolbarColorScheme(
    to node: ViewNode,
    colorScheme: ColorScheme?,
    bars: [ToolbarItemPlacement] = []
) {
    guard let colorScheme else {
        return
    }

    if node.isToolbarContainer, retainedToolbarMatches(node.toolbarPlacementTags, bars: bars) {
        if colorScheme == .light {
            if node.backgroundGradient == nil {
                node.backgroundColor = Color(red: 0.93, green: 0.96, blue: 1.0, alpha: 0.95)
            }
            node.borderColor = Color(red: 0.12, green: 0.16, blue: 0.24, alpha: 0.16)
            applyToolbarForegroundColor(to: node, color: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 1))
        } else {
            if node.backgroundGradient == nil {
                node.backgroundColor = Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.92)
            }
            node.borderColor = Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08)
            applyToolbarForegroundColor(to: node, color: Color(red: 0.94, green: 0.97, blue: 1.0, alpha: 1))
        }
        return
    }

    for child in node.children {
        applyToolbarColorScheme(to: child, colorScheme: colorScheme, bars: bars)
    }
}

@MainActor
private func applyToolbarForegroundColor(to node: ViewNode, color: Color) {
    if node.text != nil {
        var style = node.textStyle
        style.color = color
        node.textStyle = style
    }

    for child in node.children {
        applyToolbarForegroundColor(to: child, color: color)
    }
}

@MainActor
private func applyToolbarRoleChrome(to node: ViewNode, role: ToolbarRole) {
    if node.isToolbarContainer {
        if role == .editor {
            node.cornerRadius = 6
            node.borderWidth = 1
            node.borderColor = Color(red: 0.44, green: 0.60, blue: 0.86, alpha: 0.30)
            node.shadowColor = Color(red: 0.04, green: 0.06, blue: 0.10, alpha: 0.18)
            node.shadowOffset = Point(x: 0, y: 1)
            node.shadowSpread = 6
        } else if role == .browser {
            node.cornerRadius = 10
            node.borderWidth = 1
            node.borderColor = Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.12)
            node.shadowColor = Color(red: 0.02, green: 0.03, blue: 0.06, alpha: 0.24)
            node.shadowOffset = Point(x: 0, y: 2)
            node.shadowSpread = 10
        } else if role == .navigationStack {
            node.cornerRadius = 0
            node.borderWidth = 1
            node.borderColor = Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.10)
            node.shadowColor = .clear
            node.shadowOffset = .zero
            node.shadowSpread = 0
        }
    }

    for child in node.children {
        applyToolbarRoleChrome(to: child, role: role)
    }
}

@MainActor
private func applyToolbarTitleDisplayMode(to node: ViewNode, mode: ToolbarTitleDisplayMode) {
    if node.isToolbarContainer, case .stack(var layout) = node.layoutMode {
        if mode == .large {
            layout.padding = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        } else if mode == .inlineLarge {
            layout.padding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        } else {
            layout.padding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        }
        node.layoutMode = .stack(layout)
    }

    for child in node.children {
        applyToolbarTitleDisplayMode(to: child, mode: mode)
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

private func aspectRatioPreferredSize(
    baseSize: Size,
    requestedAspectRatio: Double?,
    contentMode: ContentMode
) -> Size {
    let nativeRatio = baseSize.width > 0 && baseSize.height > 0 ? baseSize.width / baseSize.height : 1
    let requestedRatio = requestedAspectRatio ?? nativeRatio
    let ratio = requestedRatio.isFinite && requestedRatio > 0 ? requestedRatio : 1
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

private func mergedPresentationChrome(
    _ base: RetainedPresentationChrome,
    applying override: RetainedPresentationChrome
) -> RetainedPresentationChrome {
    var result = base
    if override.hasBackgroundOverride {
        result.hasBackgroundOverride = true
        result.backgroundColor = override.backgroundColor
        result.backgroundGradient = override.backgroundGradient
    }
    if override.hasCornerRadiusOverride {
        result.hasCornerRadiusOverride = true
        result.cornerRadius = override.cornerRadius
    }
    if override.hasDragIndicatorOverride {
        result.hasDragIndicatorOverride = true
        result.showsDragIndicator = override.showsDragIndicator
    }
    if override.hasDetentsOverride {
        result.hasDetentsOverride = true
        result.detents = override.detents
        result.selectedDetent = override.selectedDetent
    }
    if override.hasInteractiveDismissDisabledOverride {
        result.hasInteractiveDismissDisabledOverride = true
        result.interactiveDismissDisabled = override.interactiveDismissDisabled
    }
    if override.hasBackgroundInteractionOverride {
        result.hasBackgroundInteractionOverride = true
        result.allowsBackgroundInteraction = override.allowsBackgroundInteraction
    }
    if override.hasContentInteractionOverride {
        result.hasContentInteractionOverride = true
        result.contentInteraction = override.contentInteraction
    }
    if override.hasCompactAdaptationOverride {
        result.hasCompactAdaptationOverride = true
        result.horizontalCompactAdaptation = override.horizontalCompactAdaptation
        result.verticalCompactAdaptation = override.verticalCompactAdaptation
    }
    return result
}

@MainActor
private func retainedPresentationChrome(in node: ViewNode) -> RetainedPresentationChrome {
    var chrome = RetainedPresentationChrome.empty
    for child in node.children {
        chrome = mergedPresentationChrome(chrome, applying: retainedPresentationChrome(in: child))
    }
    return mergedPresentationChrome(chrome, applying: node.presentationChrome)
}

private func retainedPresentationDetentSortKey(_ detent: RetainedPresentationDetent) -> (Int, Double) {
    switch detent {
    case .medium:
        return (0, 0)
    case let .fraction(fraction):
        return (1, fraction.isFinite ? fraction : 0)
    case let .height(height):
        return (2, height.isFinite ? height : 0)
    case .large:
        return (3, 0)
    }
}

private func retainedPresentationDetentPrecedes(
    _ lhs: RetainedPresentationDetent,
    _ rhs: RetainedPresentationDetent
) -> Bool {
    let lhsKey = retainedPresentationDetentSortKey(lhs)
    let rhsKey = retainedPresentationDetentSortKey(rhs)
    if lhsKey.0 != rhsKey.0 {
        return lhsKey.0 < rhsKey.0
    }
    return lhsKey.1 < rhsKey.1
}

private func retainedPresentationDetents(from detents: Set<PresentationDetent>) -> [RetainedPresentationDetent] {
    detents.map(\.retainedDetent).sorted(by: retainedPresentationDetentPrecedes)
}

private func clampedPresentationFraction(_ fraction: Double) -> Double {
    guard fraction.isFinite else {
        return 0
    }
    return min(1, max(0, fraction))
}

private func retainedPresentationHeight(
    chrome: RetainedPresentationChrome,
    boundsSize: Size
) -> Double? {
    guard chrome.hasDetentsOverride else {
        return nil
    }

    let detents = chrome.detents
    let selectedDetent = chrome.selectedDetent.flatMap { selected in
        detents.isEmpty || detents.contains(selected) ? selected : nil
    } ?? detents.first
    guard let selectedDetent else {
        return nil
    }

    let availableHeight = max(0, boundsSize.height - 48)
    let targetHeight: Double
    switch selectedDetent {
    case .medium:
        targetHeight = availableHeight * 0.5
    case .large:
        targetHeight = availableHeight
    case let .height(height):
        targetHeight = height.isFinite ? max(0, height) : 0
    case let .fraction(fraction):
        targetHeight = availableHeight * clampedPresentationFraction(fraction)
    }

    return min(availableHeight, targetHeight)
}

private func normalizedPresentationCornerRadius(_ value: Double?, defaultValue: Double) -> Double {
    guard let value, value.isFinite else {
        return defaultValue
    }
    return max(0, value)
}

@MainActor
private func retainedPresentationDragIndicatorNode() -> ViewNode {
    let handle = Controls.panel(
        preferredSize: Size(width: 36, height: 5),
        backgroundColor: Color(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.44),
        cornerRadius: 2.5,
        isHitTestVisible: false
    )
    return Controls.stackPanel(
        stackLayout: .horizontal(spacing: 0, alignment: .center, mainAlignment: .center),
        isHitTestVisible: false,
        children: [handle]
    )
}

@MainActor
private func retainedPresentationChildren(
    contentNode: ViewNode,
    chrome: RetainedPresentationChrome,
    wrapsScrollingContent: Bool = false
) -> [ViewNode] {
    let presentedContentNode = wrapsScrollingContent && chrome.contentInteraction == .scrolls
        ? retainedPresentationScrollContentNode(contentNode)
        : contentNode
    return chrome.showsDragIndicator
        ? [retainedPresentationDragIndicatorNode(), presentedContentNode]
        : [presentedContentNode]
}

@MainActor
private func retainedPresentationScrollContentNode(_ contentNode: ViewNode) -> ViewNode {
    let scrollNode = Controls.scrollPanel(
        axis: .vertical,
        layoutPriority: 1,
        stackLayout: .vertical(
            spacing: 0,
            padding: .zero,
            alignment: .stretch,
            mainAlignment: .start
        ),
        scrollStep: 64,
        scrollIndicatorColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.18),
        scrollIndicatorHoverColor: Color(red: 0.97, green: 0.99, blue: 1.0, alpha: 0.34),
        scrollIndicatorActiveColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.56),
        scrollIndicatorThickness: 5,
        isHitTestVisible: true,
        children: [contentNode]
    )
    scrollNode.nodeTag = "presentation-content-scrolls"
    return scrollNode
}

@MainActor
private func retainedSheetPresentation(
    base: Component,
    sheet: Component,
    context: ViewBuildContext,
    onInteractiveDismiss: @escaping @MainActor () -> Void
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let sheetContentNode = sheet.makeNode(runtime: runtime)
        let presentationChrome = retainedPresentationChrome(in: sheetContentNode)
        let allowsBackgroundInteraction = presentationChrome.allowsBackgroundInteraction
        let scrimDismissesSheet = !allowsBackgroundInteraction
            && !presentationChrome.interactiveDismissDisabled
        let scrimNode = Controls.panel(
            backgroundColor: Color(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.48),
            isHitTestVisible: scrimDismissesSheet
        )
        if allowsBackgroundInteraction {
            scrimNode.nodeTag = "sheet-scrim-background-interactive"
        } else if presentationChrome.interactiveDismissDisabled {
            scrimNode.nodeTag = "sheet-scrim-dismiss-disabled"
        } else {
            scrimNode.nodeTag = "sheet-scrim-dismiss-enabled"
        }
        if scrimDismissesSheet {
            scrimNode.onActivate = {
                onInteractiveDismiss()
            }
        }
        let sheetBackgroundColor = presentationChrome.hasBackgroundOverride
            ? presentationChrome.backgroundColor
            : Color(red: 0.11, green: 0.15, blue: 0.21, alpha: 0.98)
        let sheetBackgroundGradient = presentationChrome.hasBackgroundOverride
            ? presentationChrome.backgroundGradient
            : nil
        let sheetCornerRadius = presentationChrome.hasCornerRadiusOverride
            ? normalizedPresentationCornerRadius(presentationChrome.cornerRadius, defaultValue: 14)
            : 14
        let sheetNode = Controls.stackPanel(
            backgroundColor: sheetBackgroundColor,
            backgroundGradient: sheetBackgroundGradient,
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.14),
            borderWidth: 1,
            cornerRadius: sheetCornerRadius,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 10,
                padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: retainedPresentationChildren(
                contentNode: sheetContentNode,
                chrome: presentationChrome,
                wrapsScrollingContent: true
            )
        )
        let root = Controls.panel(
            preferredSize: baseNode.intrinsicContentSize(),
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, scrimNode, sheetNode]
        )

        root.onLayout = { bounds in
            let boundsFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != boundsFrame {
                baseNode.frame = boundsFrame
            }
            if scrimNode.frame != boundsFrame {
                scrimNode.frame = boundsFrame
            }

            var sheetSize = sheetNode.intrinsicContentSize()
            if let detentHeight = retainedPresentationHeight(
                chrome: presentationChrome,
                boundsSize: bounds.size
            ) {
                sheetSize.height = detentHeight
            }
            let sheetOrigin = Alignment.bottom.frameOrigin(
                for: sheetSize,
                in: bounds.size,
                layoutDirection: context.layoutDirection
            )
            let sheetFrame = Rect(origin: sheetOrigin, size: sheetSize)
            if sheetNode.frame != sheetFrame {
                sheetNode.frame = sheetFrame
            }
        }

        return root
    }
}

@MainActor
private func retainedFullScreenCoverPresentation(
    base: Component,
    cover: Component
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let coverContentNode = cover.makeNode(runtime: runtime)
        let presentationChrome = retainedPresentationChrome(in: coverContentNode)
        let coverBackgroundColor = presentationChrome.hasBackgroundOverride
            ? presentationChrome.backgroundColor
            : Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 1.0)
        let coverBackgroundGradient = presentationChrome.hasBackgroundOverride
            ? presentationChrome.backgroundGradient
            : nil
        let coverNode = Controls.stackPanel(
            backgroundColor: coverBackgroundColor,
            backgroundGradient: coverBackgroundGradient,
            cornerRadius: presentationChrome.hasCornerRadiusOverride
                ? normalizedPresentationCornerRadius(presentationChrome.cornerRadius, defaultValue: 0)
                : 0,
            clipsToBounds: presentationChrome.hasCornerRadiusOverride,
            stackLayout: .vertical(
                spacing: 0,
                padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                alignment: .stretch,
                mainAlignment: .start
            ),
            isHitTestVisible: false,
            children: retainedPresentationChildren(contentNode: coverContentNode, chrome: presentationChrome)
        )
        let root = Controls.panel(
            preferredSize: baseNode.intrinsicContentSize(),
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, coverNode]
        )

        root.onLayout = { bounds in
            let boundsFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != boundsFrame {
                baseNode.frame = boundsFrame
            }
            if coverNode.frame != boundsFrame {
                coverNode.frame = boundsFrame
            }
        }

        return root
    }
}

@MainActor
private func retainedPopoverPresentation(
    base: Component,
    popover: Component,
    context: ViewBuildContext,
    attachmentAnchor: PopoverAttachmentAnchor,
    arrowEdge: Edge
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let popoverContentNode = popover.makeNode(runtime: runtime)
        let presentationChrome = retainedPresentationChrome(in: popoverContentNode)
        let popoverBackgroundColor = presentationChrome.hasBackgroundOverride
            ? presentationChrome.backgroundColor
            : Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.98)
        let popoverBackgroundGradient = presentationChrome.hasBackgroundOverride
            ? presentationChrome.backgroundGradient
            : nil
        let popoverCornerRadius = presentationChrome.hasCornerRadiusOverride
            ? normalizedPresentationCornerRadius(presentationChrome.cornerRadius, defaultValue: 12)
            : 12
        let popoverNode = Controls.stackPanel(
            backgroundColor: popoverBackgroundColor,
            backgroundGradient: popoverBackgroundGradient,
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.28),
            shadowOffset: Point(x: 0, y: 10),
            shadowSpread: 16,
            cornerRadius: popoverCornerRadius,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 8,
                padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: retainedPresentationChildren(contentNode: popoverContentNode, chrome: presentationChrome)
        )
        let root = Controls.panel(
            preferredSize: baseNode.intrinsicContentSize(),
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, popoverNode]
        )

        root.onLayout = { bounds in
            let boundsFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != boundsFrame {
                baseNode.frame = boundsFrame
            }

            let popoverSize = popoverNode.intrinsicContentSize()
            let popoverOrigin = popoverOrigin(
                for: popoverSize,
                in: bounds.size,
                attachmentAnchor: attachmentAnchor,
                arrowEdge: arrowEdge,
                layoutDirection: context.layoutDirection
            )
            let popoverFrame = Rect(origin: popoverOrigin, size: popoverSize)
            if popoverNode.frame != popoverFrame {
                popoverNode.frame = popoverFrame
            }
        }

        return root
    }
}

private func popoverAttachmentPoint(_ anchor: PopoverAttachmentAnchor, in size: Size) -> Point {
    let unitPoint: UnitPoint
    switch anchor.kind {
    case let .rect(point), let .point(point):
        unitPoint = point
    }
    return Point(
        x: size.width * min(1, max(0, unitPoint.x)),
        y: size.height * min(1, max(0, unitPoint.y))
    )
}

private func resolvedPopoverArrowEdge(_ edge: Edge, layoutDirection: LayoutDirection) -> Edge {
    switch (edge, layoutDirection) {
    case (.leading, .rightToLeft):
        return .trailing
    case (.trailing, .rightToLeft):
        return .leading
    default:
        return edge
    }
}

private func clampedPopoverOrigin(_ origin: Point, popoverSize: Size, boundsSize: Size) -> Point {
    Point(
        x: min(max(0, boundsSize.width - popoverSize.width), max(0, origin.x)),
        y: min(max(0, boundsSize.height - popoverSize.height), max(0, origin.y))
    )
}

private func popoverOrigin(
    for popoverSize: Size,
    in boundsSize: Size,
    attachmentAnchor: PopoverAttachmentAnchor,
    arrowEdge: Edge,
    layoutDirection: LayoutDirection
) -> Point {
    let attachmentPoint = popoverAttachmentPoint(attachmentAnchor, in: boundsSize)
    let origin: Point
    switch resolvedPopoverArrowEdge(arrowEdge, layoutDirection: layoutDirection) {
    case .top:
        origin = Point(
            x: attachmentPoint.x - popoverSize.width * 0.5,
            y: attachmentPoint.y
        )
    case .bottom:
        origin = Point(
            x: attachmentPoint.x - popoverSize.width * 0.5,
            y: attachmentPoint.y - popoverSize.height
        )
    case .leading:
        origin = Point(
            x: attachmentPoint.x,
            y: attachmentPoint.y - popoverSize.height * 0.5
        )
    case .trailing:
        origin = Point(
            x: attachmentPoint.x - popoverSize.width,
            y: attachmentPoint.y - popoverSize.height * 0.5
        )
    }
    return clampedPopoverOrigin(origin, popoverSize: popoverSize, boundsSize: boundsSize)
}

@MainActor
private func retainedCompactPopoverAdaptation(
    chrome: RetainedPresentationChrome,
    context: ViewBuildContext
) -> RetainedPresentationAdaptation {
    guard chrome.hasCompactAdaptationOverride else {
        return .popover
    }

    var adaptation: RetainedPresentationAdaptation?
    let environment = context.environmentValues
    if environment.horizontalSizeClass == .compact {
        adaptation = chrome.horizontalCompactAdaptation
    }
    if environment.verticalSizeClass == .compact {
        adaptation = chrome.verticalCompactAdaptation
    }
    return adaptation ?? .popover
}

@MainActor
private func retainedCompactAdaptivePopoverPresentation(
    base: Component,
    popover: Component,
    context: ViewBuildContext,
    attachmentAnchor: PopoverAttachmentAnchor,
    arrowEdge: Edge,
    onInteractiveDismiss: @escaping @MainActor @Sendable () -> Void
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let popoverContentNode = popover.makeNode(runtime: runtime)
        let presentationChrome = retainedPresentationChrome(in: popoverContentNode)
        let baseComponent = Component { _ in baseNode }
        let popoverComponent = Component { _ in popoverContentNode }

        switch retainedCompactPopoverAdaptation(chrome: presentationChrome, context: context) {
        case .sheet:
            return retainedSheetPresentation(
                base: baseComponent,
                sheet: popoverComponent,
                context: context,
                onInteractiveDismiss: onInteractiveDismiss
            )
            .makeNode(runtime: runtime)
        case .fullScreenCover:
            return retainedFullScreenCoverPresentation(base: baseComponent, cover: popoverComponent)
                .makeNode(runtime: runtime)
        case .automatic, .none, .popover:
            return retainedPopoverPresentation(
                base: baseComponent,
                popover: popoverComponent,
                context: context,
                attachmentAnchor: attachmentAnchor,
                arrowEdge: arrowEdge
            )
            .makeNode(runtime: runtime)
        }
    }
}

@MainActor
private func retainedAlertPresentation(
    base: Component,
    title: Component,
    message: Component?,
    actions: Component,
    context: ViewBuildContext
) -> Component {
    Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let scrimNode = Controls.panel(
            backgroundColor: Color(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.52),
            isHitTestVisible: false
        )

        var alertChildren = [title.makeNode(runtime: runtime)]
        if let message {
            alertChildren.append(message.makeNode(runtime: runtime))
        }
        alertChildren.append(actions.makeNode(runtime: runtime))

        let alertNode = Controls.stackPanel(
            preferredSize: Size(width: 300, height: 0),
            backgroundColor: Color(red: 0.11, green: 0.15, blue: 0.21, alpha: 0.98),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.32),
            shadowOffset: Point(x: 0, y: 12),
            shadowSpread: 18,
            cornerRadius: 14,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 12,
                padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: alertChildren
        )
        let root = Controls.panel(
            preferredSize: baseNode.intrinsicContentSize(),
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, scrimNode, alertNode]
        )

        root.onLayout = { bounds in
            let boundsFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != boundsFrame {
                baseNode.frame = boundsFrame
            }
            if scrimNode.frame != boundsFrame {
                scrimNode.frame = boundsFrame
            }

            let alertSize = alertNode.intrinsicContentSize()
            let alertOrigin = Alignment.center.frameOrigin(
                for: alertSize,
                in: bounds.size,
                layoutDirection: context.layoutDirection
            )
            let alertFrame = Rect(origin: alertOrigin, size: alertSize)
            if alertNode.frame != alertFrame {
                alertNode.frame = alertFrame
            }
        }

        return root
    }
}

@MainActor
private func retainedAlertPresentation(
    base: Component,
    alert: Alert,
    context: ViewBuildContext,
    dismiss: @escaping @MainActor () -> Void
) -> Component {
    let alertContext = context
        .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
        .withEnvironmentValue(\.isPresented, true)
    let title = alert.title
        .font(.headline)
        .multilineTextAlignment(.center)
        .makeComponent(context: alertContext)
    let message = alert.message?
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .makeComponent(context: alertContext)
    let actions = retainedAlertActionsComponent(
        buttons: alert.buttons,
        context: alertContext,
        dismiss: dismiss
    )

    return retainedAlertPresentation(
        base: base,
        title: title,
        message: message,
        actions: actions,
        context: context
    )
}

@MainActor
private func retainedAlertActionsComponent(
    buttons: [Alert.Button],
    context: ViewBuildContext,
    dismiss: @escaping @MainActor () -> Void
) -> Component {
    let actionButtons = (buttons.isEmpty ? [.default(Text("OK"))] : buttons).map { button in
        AnyView(
            Button(button.label.plainContent, role: button.role) {
                button.action?()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        )
    }

    return composeComponent(
        from: actionButtons,
        context: context,
        fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .stretch, mainAlignment: .end))
    )
}

@MainActor
private func retainedAlertBuilderPresentation(
    base: Component,
    title: Text,
    messageViews: [AnyView],
    actionViews: [AnyView],
    context: ViewBuildContext,
    dismiss: @escaping @MainActor () -> Void
) -> Component {
    let alertContext = context
        .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
        .withEnvironmentValue(\.isPresented, true)
    let titleComponent = title
        .font(.headline)
        .multilineTextAlignment(.center)
        .makeComponent(context: alertContext)
    let messageComponent = messageViews.isEmpty ? nil : composeComponent(
        from: messageViews,
        context: alertContext.withEnvironmentValue(\.foregroundStyle, .color(.secondary)),
        fallbackLayout: .stack(.vertical(spacing: 4, alignment: .center))
    )
    let actions = actionViews.isEmpty
        ? [AnyView(Button("OK", role: .cancel) { dismiss() }.buttonStyle(.borderedProminent))]
        : actionViews
    let actionsComponent = composeComponent(
        from: actions,
        context: alertContext,
        fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .stretch, mainAlignment: .end))
    )

    return retainedAlertPresentation(
        base: base,
        title: titleComponent,
        message: messageComponent,
        actions: actionsComponent,
        context: context
    )
}

@MainActor
private func retainedConfirmationDialogPresentation(
    base: Component,
    title: Text,
    titleVisibility: Visibility,
    messageViews: [AnyView],
    actionViews: [AnyView],
    context: ViewBuildContext,
    dismiss: @escaping @MainActor () -> Void
) -> Component {
    let dialogContext = context
        .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
        .withEnvironmentValue(\.isPresented, true)
    var dialogChildren: [Component] = []
    if titleVisibility != .hidden {
        dialogChildren.append(
            title
                .font(.headline)
                .multilineTextAlignment(.center)
                .makeComponent(context: dialogContext)
        )
    }
    if !messageViews.isEmpty {
        dialogChildren.append(
            composeComponent(
                from: messageViews,
                context: dialogContext.withEnvironmentValue(\.foregroundStyle, .color(.secondary)),
                fallbackLayout: .stack(.vertical(spacing: 4, alignment: .center))
            )
        )
    }

    let actions = actionViews.isEmpty
        ? [AnyView(Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(.borderedProminent))]
        : actionViews
    dialogChildren.append(
        composeComponent(
            from: actions,
            context: dialogContext,
            fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
        )
    )

    return Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        let scrimNode = Controls.panel(
            backgroundColor: Color(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.44),
            isHitTestVisible: false
        )
        let dialogNode = Controls.stackPanel(
            preferredSize: Size(width: 340, height: 0),
            backgroundColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.99),
            borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.16),
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.30),
            shadowOffset: Point(x: 0, y: 10),
            shadowSpread: 16,
            cornerRadius: 14,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 12,
                padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: dialogChildren.map { $0.makeNode(runtime: runtime) }
        )
        let root = Controls.panel(
            preferredSize: baseNode.intrinsicContentSize(),
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, scrimNode, dialogNode]
        )

        root.onLayout = { bounds in
            let boundsFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != boundsFrame {
                baseNode.frame = boundsFrame
            }
            if scrimNode.frame != boundsFrame {
                scrimNode.frame = boundsFrame
            }

            let dialogSize = dialogNode.intrinsicContentSize()
            let dialogOrigin = Alignment.bottom.frameOrigin(
                for: dialogSize,
                in: bounds.size,
                layoutDirection: context.layoutDirection
            )
            let dialogFrame = Rect(origin: dialogOrigin, size: dialogSize)
            if dialogNode.frame != dialogFrame {
                dialogNode.frame = dialogFrame
            }
        }

        return root
    }
}

@MainActor
private func retainedActionSheetPresentation(
    base: Component,
    actionSheet: ActionSheet,
    context: ViewBuildContext,
    dismiss: @escaping @MainActor () -> Void
) -> Component {
    let sheetContext = context
        .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
        .withEnvironmentValue(\.isPresented, true)
    let messageViews = actionSheet.message.map { [AnyView($0.foregroundStyle(.secondary))] } ?? []
    let buttons = (actionSheet.buttons.isEmpty ? [.cancel()] : actionSheet.buttons).map { button in
        AnyView(
            Button(button.label.plainContent, role: button.role) {
                button.action?()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        )
    }

    return retainedConfirmationDialogPresentation(
        base: base,
        title: actionSheet.title,
        titleVisibility: .visible,
        messageViews: messageViews,
        actionViews: buttons,
        context: sheetContext,
        dismiss: dismiss
    )
}

@MainActor
private final class RetainedContextMenuState {
    var isPresented = false
    var anchor = Point.zero
}

@MainActor
private func installRetainedContextMenuHandler(
    on node: ViewNode,
    state: RetainedContextMenuState,
    context: ViewBuildContext
) {
    let previousHandler = node.onContextMenu
    node.isHitTestVisible = true
    node.onContextMenu = { point in
        previousHandler?(point)
        state.anchor = point
        state.isPresented = true
        context.invalidate()
    }
}

@MainActor
private func attachRetainedActivationDismiss(to node: ViewNode, dismiss: @escaping @MainActor () -> Void) {
    if let activate = node.onActivate {
        node.onActivate = {
            activate()
            dismiss()
        }
    }

    for child in node.children {
        attachRetainedActivationDismiss(to: child, dismiss: dismiss)
    }
}

@MainActor
private func retainedContextMenuPresentation(
    base: Component,
    menuItems: [AnyView],
    preview: [AnyView],
    state: RetainedContextMenuState,
    context: ViewBuildContext
) -> Component {
    let dismiss: @MainActor () -> Void = {
        guard state.isPresented else {
            return
        }

        state.isPresented = false
        context.invalidate()
    }
    let menuContext = context
        .withButtonStyle(.plain)
        .withControlSize(.small)
        .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
        .withEnvironmentValue(\.isPresented, true)
    let previewComponent = preview.isEmpty ? nil : composeComponent(
        from: preview,
        context: menuContext,
        fallbackLayout: .stack(.vertical(spacing: 4, alignment: .stretch)),
        isHitTestVisible: false
    )
    let itemComponent = composeComponent(
        from: menuItems,
        context: menuContext,
        fallbackLayout: .stack(.vertical(spacing: 2, alignment: .stretch)),
        isHitTestVisible: false
    )

    return Component { runtime in
        let baseNode = base.makeNode(runtime: runtime)
        installRetainedContextMenuHandler(on: baseNode, state: state, context: context)
        guard state.isPresented else {
            return baseNode
        }

        var panelChildren: [ViewNode] = []
        if let previewComponent {
            panelChildren.append(previewComponent.makeNode(runtime: runtime))
        }
        let itemNode = itemComponent.makeNode(runtime: runtime)
        attachRetainedActivationDismiss(to: itemNode, dismiss: dismiss)
        panelChildren.append(itemNode)

        let menuPanel = Controls.stackPanel(
            preferredSize: Size(width: 220, height: 0),
            backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.97),
            borderColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.16),
            borderWidth: 1,
            shadowColor: Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.28),
            shadowOffset: Point(x: 0, y: 10),
            shadowSpread: 12,
            cornerRadius: 10,
            clipsToBounds: true,
            stackLayout: .vertical(
                spacing: 6,
                padding: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6),
                alignment: .stretch
            ),
            isHitTestVisible: false,
            children: panelChildren
        )
        let root = Controls.panel(
            preferredSize: baseNode.intrinsicContentSize(),
            layoutMode: .absolute,
            isHitTestVisible: false,
            children: [baseNode, menuPanel]
        )

        root.onLayout = { bounds in
            let boundsFrame = Rect(origin: .zero, size: bounds.size)
            if baseNode.frame != boundsFrame {
                baseNode.frame = boundsFrame
            }

            let panelSize = menuPanel.intrinsicContentSize()
            let maxX = max(0, bounds.size.width - panelSize.width)
            let maxY = max(0, bounds.size.height - panelSize.height)
            let origin = Point(
                x: min(max(0, state.anchor.x), maxX),
                y: min(max(0, state.anchor.y), maxY)
            )
            let panelFrame = Rect(origin: origin, size: panelSize)
            if menuPanel.frame != panelFrame {
                menuPanel.frame = panelFrame
            }
        }

        return root
    }
}

public extension View {
    func modifier<Modifier: ViewModifier>(_ modifier: Modifier) -> ModifiedContent<Self, Modifier> {
        ModifiedContent(content: self, modifier: modifier)
    }

    func equatable() -> EquatableView<Self> where Self: Equatable {
        EquatableView(content: self)
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
        padding(length)
    }

    func safeAreaPadding(_ edges: Edge.Set, _ length: Double? = nil) -> some View {
        padding(edges, length)
    }

    func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        padding(insets)
    }

    func safeAreaInset(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content insetContent: () -> [AnyView]
    ) -> some View {
        let insetViews = insetContent()
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            let inset = composeComponent(
                from: insetViews,
                context: context,
                fallbackLayout: .stack(.vertical(
                    spacing: 0,
                    alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                )),
                isHitTestVisible: false
            )

            return Component { runtime in
                let baseNode = base.makeNode(runtime: runtime)
                let insetNode = inset.makeNode(runtime: runtime)
                let children: [ViewNode]
                switch edge {
                case .top:
                    children = [insetNode, baseNode]
                case .bottom:
                    children = [baseNode, insetNode]
                }

                return Controls.stackPanel(
                    stackLayout: .vertical(
                        spacing: spacing ?? 0,
                        alignment: alignment.stackAlignment(layoutDirection: context.layoutDirection)
                    ),
                    isHitTestVisible: false,
                    children: children
                )
            }
        }
    }

    func safeAreaInset(
        edge: HorizontalEdge,
        alignment: VerticalAlignment = .center,
        spacing: Double? = nil,
        @ViewBuilder content insetContent: () -> [AnyView]
    ) -> some View {
        let insetViews = insetContent()
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            let inset = composeComponent(
                from: insetViews,
                context: context,
                fallbackLayout: .stack(.horizontal(
                    spacing: 0,
                    alignment: alignment.stackAlignment
                )),
                isHitTestVisible: false
            )

            return Component { runtime in
                let baseNode = base.makeNode(runtime: runtime)
                let insetNode = inset.makeNode(runtime: runtime)
                let children: [ViewNode]
                switch edge.resolved(for: context.layoutDirection) {
                case .leading:
                    children = [insetNode, baseNode]
                case .trailing:
                    children = [baseNode, insetNode]
                }

                return Controls.stackPanel(
                    stackLayout: .horizontal(
                        spacing: spacing ?? 0,
                        alignment: alignment.stackAlignment
                    ),
                    isHitTestVisible: false,
                    children: children
                )
            }
        }
    }

    func contextMenu(@ViewBuilder menuItems: @escaping () -> [AnyView]) -> some View {
        retainedContextMenu(menuItems: menuItems)
    }

    func contextMenu(
        @ViewBuilder menuItems: @escaping () -> [AnyView],
        @ViewBuilder preview: @escaping () -> [AnyView]
    ) -> some View {
        retainedContextMenu(menuItems: menuItems, preview: preview)
    }

    private func retainedContextMenu(
        menuItems: @escaping () -> [AnyView],
        preview: (() -> [AnyView])? = nil
    ) -> some View {
        let state = RetainedContextMenuState()
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            let items = menuItems()
            let previewViews = preview?() ?? []
            guard !items.isEmpty || !previewViews.isEmpty else {
                return Component { runtime in
                    let baseNode = base.makeNode(runtime: runtime)
                    installRetainedContextMenuHandler(on: baseNode, state: state, context: context)
                    return baseNode
                }
            }

            return retainedContextMenuPresentation(
                base: base,
                menuItems: items,
                preview: previewViews,
                state: state,
                context: context
            )
        }
    }

    func toolbar(@ViewBuilder content toolbarContent: () -> [AnyView]) -> some View {
        toolbar(id: nil, content: toolbarContent)
    }

    func toolbar(id: String, @ViewBuilder content toolbarContent: () -> [AnyView]) -> some View {
        toolbar(id: Optional(id), content: toolbarContent)
    }

    private func toolbar(id: String?, @ViewBuilder content toolbarContent: () -> [AnyView]) -> some View {
        let toolbarViews = toolbarContent()
        let orderedToolbarViews = orderedRetainedToolbarViews(toolbarViews)
        let toolbarPlacementTags = retainedToolbarPlacementTags(for: toolbarViews)
        return ModifiedView(content: self) { content, context in
            guard !toolbarViews.isEmpty else {
                return content.makeComponent(context: context)
            }

            let base = content.makeComponent(context: context)
            let toolbarContext = context
                .withButtonStyle(.borderless)
                .withControlSize(.small)
            let toolbar = composeComponent(
                from: orderedToolbarViews,
                context: toolbarContext,
                fallbackLayout: .stack(.horizontal(spacing: 8, alignment: .center)),
                isHitTestVisible: false
            )

            return Component { runtime in
                let toolbarContentNode = toolbar.makeNode(runtime: runtime)
                let toolbarNode = Controls.stackPanel(
                    backgroundColor: Color(red: 0.08, green: 0.11, blue: 0.16, alpha: 0.92),
                    borderColor: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.08),
                    borderWidth: 1,
                    stackLayout: .horizontal(
                        spacing: 8,
                        padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8),
                        alignment: .center
                    ),
                    isHitTestVisible: false,
                    children: [toolbarContentNode]
                )
                toolbarNode.isToolbarContainer = true
                toolbarNode.toolbarPlacementTags = toolbarPlacementTags
                toolbarNode.nodeTag = id

                let baseNode = base.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    stackLayout: .vertical(spacing: 0, alignment: .stretch),
                    isHitTestVisible: false,
                    children: [toolbarNode, baseNode]
                )
            }
        }
    }

    func toolbar(_ visibility: Visibility, for bars: ToolbarItemPlacement...) -> some View {
        let bars = bars
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                applyToolbarVisibility(to: node, visibility: visibility, bars: bars)
                return node
            }
        }
    }

    func toolbarBackground(_ visibility: Visibility, for bars: ToolbarItemPlacement...) -> some View {
        let bars = bars
        let shouldHide = visibility == .hidden
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                if shouldHide {
                    applyToolbarBackgroundStyle(to: node, color: nil, gradient: nil, bars: bars)
                }
                return node
            }
        }
    }

    func toolbarBackground(_ color: Color, for bars: ToolbarItemPlacement...) -> some View {
        toolbarBackgroundStyle(color: color, gradient: nil, bars: bars)
    }

    func toolbarBackground(_ color: Color?, for bars: ToolbarItemPlacement...) -> some View {
        toolbarBackgroundStyle(color: color, gradient: nil, bars: bars)
    }

    func toolbarBackground(_ style: ForegroundStyle, for bars: ToolbarItemPlacement...) -> some View {
        let fill = resolvedStyleFill(from: style)
        return toolbarBackgroundStyle(color: fill.color, gradient: fill.gradient, bars: bars)
    }

    func toolbarBackground(_ gradient: LinearGradient, for bars: ToolbarItemPlacement...) -> some View {
        toolbarBackgroundStyle(color: nil, gradient: gradient, bars: bars)
    }

    private func toolbarBackgroundStyle(
        color: Color?,
        gradient: LinearGradient?,
        bars: [ToolbarItemPlacement] = []
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                applyToolbarBackgroundStyle(to: node, color: color, gradient: gradient, bars: bars)
                return node
            }
        }
    }

    func toolbarColorScheme(_ colorScheme: ColorScheme?, for bars: ToolbarItemPlacement...) -> some View {
        let bars = bars
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                applyToolbarColorScheme(to: node, colorScheme: colorScheme, bars: bars)
                return node
            }
        }
    }

    func toolbarRole(_ role: ToolbarRole) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                applyToolbarRoleChrome(to: node, role: role)
                return node
            }
        }
    }

    func toolbarTitleDisplayMode(_ mode: ToolbarTitleDisplayMode) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                applyToolbarTitleDisplayMode(to: node, mode: mode)
                return node
            }
        }
    }

    func navigationBarItems<Leading: View>(leading: Leading) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                leading
            }
        }
    }

    func navigationBarItems<Trailing: View>(trailing: Trailing) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                trailing
            }
        }
    }

    func navigationBarItems<Leading: View, Trailing: View>(
        leading: Leading,
        trailing: Trailing
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                leading
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                trailing
            }
        }
    }

    func sheet(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content sheetContent: @escaping () -> [AnyView]
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                onDismiss?()
                context.invalidate()
            }
            let sheetContext = context
                .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
                .withEnvironmentValue(\.isPresented, true)
            let sheet = composeComponent(
                from: sheetContent(),
                context: sheetContext,
                fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
            )

            return retainedSheetPresentation(
                base: base,
                sheet: sheet,
                context: context,
                onInteractiveDismiss: dismiss
            )
        }
    }

    func sheet<Item>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content sheetContent: @escaping (Item) -> [AnyView]
    ) -> some View where Item: Identifiable {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard let selectedItem = item.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard item.wrappedValue != nil else {
                    return
                }

                item.wrappedValue = nil
                onDismiss?()
                context.invalidate()
            }
            let sheetContext = context
                .withEnvironmentValue(\.dismiss, DismissAction(handler: dismiss))
                .withEnvironmentValue(\.isPresented, true)
            let sheet = composeComponent(
                from: sheetContent(selectedItem),
                context: sheetContext,
                fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
            )

            return retainedSheetPresentation(
                base: base,
                sheet: sheet,
                context: context,
                onInteractiveDismiss: dismiss
            )
        }
    }

    func fullScreenCover(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content coverContent: @escaping () -> [AnyView]
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let coverContext = context
                .withEnvironmentValue(\.dismiss, DismissAction(handler: {
                    guard isPresented.wrappedValue else {
                        return
                    }

                    isPresented.wrappedValue = false
                    onDismiss?()
                    context.invalidate()
                }))
                .withEnvironmentValue(\.isPresented, true)
            let cover = composeComponent(
                from: coverContent(),
                context: coverContext,
                fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
            )

            return retainedFullScreenCoverPresentation(base: base, cover: cover)
        }
    }

    func fullScreenCover<Item>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content coverContent: @escaping (Item) -> [AnyView]
    ) -> some View where Item: Identifiable {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard let selectedItem = item.wrappedValue else {
                return base
            }

            let coverContext = context
                .withEnvironmentValue(\.dismiss, DismissAction(handler: {
                    guard item.wrappedValue != nil else {
                        return
                    }

                    item.wrappedValue = nil
                    onDismiss?()
                    context.invalidate()
                }))
                .withEnvironmentValue(\.isPresented, true)
            let cover = composeComponent(
                from: coverContent(selectedItem),
                context: coverContext,
                fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
            )

            return retainedFullScreenCoverPresentation(base: base, cover: cover)
        }
    }

    func popover(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(),
        arrowEdge: Edge = .top,
        @ViewBuilder content popoverContent: @escaping () -> [AnyView]
    ) -> some View {
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let popoverContext = context
                .withEnvironmentValue(\.dismiss, DismissAction(handler: {
                    guard isPresented.wrappedValue else {
                        return
                    }

                    isPresented.wrappedValue = false
                    context.invalidate()
                }))
                .withEnvironmentValue(\.isPresented, true)
            let popover = composeComponent(
                from: popoverContent(),
                context: popoverContext,
                fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
            )

            let dismiss: @MainActor @Sendable () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedCompactAdaptivePopoverPresentation(
                base: base,
                popover: popover,
                context: context,
                attachmentAnchor: attachmentAnchor,
                arrowEdge: arrowEdge,
                onInteractiveDismiss: dismiss
            )
        }
    }

    func popover<Item>(
        item: Binding<Item?>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(),
        arrowEdge: Edge = .top,
        @ViewBuilder content popoverContent: @escaping (Item) -> [AnyView]
    ) -> some View where Item: Identifiable {
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard let selectedItem = item.wrappedValue else {
                return base
            }

            let popoverContext = context
                .withEnvironmentValue(\.dismiss, DismissAction(handler: {
                    guard item.wrappedValue != nil else {
                        return
                    }

                    item.wrappedValue = nil
                    context.invalidate()
                }))
                .withEnvironmentValue(\.isPresented, true)
            let popover = composeComponent(
                from: popoverContent(selectedItem),
                context: popoverContext,
                fallbackLayout: .stack(.vertical(spacing: 8, alignment: .stretch))
            )

            let dismiss: @MainActor @Sendable () -> Void = {
                guard item.wrappedValue != nil else {
                    return
                }

                item.wrappedValue = nil
                context.invalidate()
            }

            return retainedCompactAdaptivePopoverPresentation(
                base: base,
                popover: popover,
                context: context,
                attachmentAnchor: attachmentAnchor,
                arrowEdge: arrowEdge,
                onInteractiveDismiss: dismiss
            )
        }
    }

    func presentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        return ModifiedView(content: self) { content, context in
            let retainedDetents = retainedPresentationDetents(from: detents)
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasDetentsOverride = true
                node.presentationChrome.detents = retainedDetents
                node.presentationChrome.selectedDetent = retainedDetents.first
                return node
            }
        }
    }

    func presentationDetents(
        _ detents: Set<PresentationDetent>,
        selection: Binding<PresentationDetent>
    ) -> some View {
        return ModifiedView(content: self) { content, context in
            let retainedDetents = retainedPresentationDetents(from: detents)
            let selectedDetent = selection.wrappedValue.retainedDetent
            let retainedSelectedDetent = retainedDetents.contains(selectedDetent)
                ? selectedDetent
                : retainedDetents.first
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasDetentsOverride = true
                node.presentationChrome.detents = retainedDetents
                node.presentationChrome.selectedDetent = retainedSelectedDetent
                return node
            }
        }
    }

    func presentationDragIndicator(_ visibility: Visibility) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasDragIndicatorOverride = true
                node.presentationChrome.showsDragIndicator = visibility == .visible
                return node
            }
        }
    }

    func interactiveDismissDisabled(_ isDisabled: Bool = true) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasInteractiveDismissDisabledOverride = true
                node.presentationChrome.interactiveDismissDisabled = isDisabled
                return node
            }
        }
    }

    func presentationBackground(_ color: Color) -> some View {
        presentationBackgroundStyle(color: color, gradient: nil)
    }

    func presentationBackground(_ color: Color?) -> some View {
        presentationBackgroundStyle(color: color, gradient: nil)
    }

    func presentationBackground(_ style: ForegroundStyle) -> some View {
        let fill = resolvedStyleFill(from: style)
        return presentationBackgroundStyle(color: fill.color, gradient: fill.gradient)
    }

    func presentationBackground(_ gradient: LinearGradient) -> some View {
        presentationBackgroundStyle(color: nil, gradient: gradient)
    }

    func presentationBackground(
        alignment: Alignment = .center,
        @ViewBuilder content background: () -> [AnyView]
    ) -> some View {
        let backgroundViews = background()
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

    func presentationCornerRadius(_ cornerRadius: Double?) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasCornerRadiusOverride = true
                node.presentationChrome.cornerRadius = cornerRadius
                return node
            }
        }
    }

    private func presentationBackgroundStyle(color: Color?, gradient: LinearGradient?) -> some View {
        ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasBackgroundOverride = true
                node.presentationChrome.backgroundColor = color
                node.presentationChrome.backgroundGradient = gradient
                return node
            }
        }
    }

    func presentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasBackgroundInteractionOverride = true
                node.presentationChrome.allowsBackgroundInteraction = interaction.allowsRetainedBackgroundInteraction
                return node
            }
        }
    }

    func presentationContentInteraction(_ behavior: PresentationContentInteraction) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasContentInteractionOverride = true
                node.presentationChrome.contentInteraction = behavior.retainedContentInteraction
                return node
            }
        }
    }

    func presentationCompactAdaptation(_ adaptation: PresentationAdaptation) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            let retainedAdaptation = adaptation.retainedAdaptation
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasCompactAdaptationOverride = true
                node.presentationChrome.horizontalCompactAdaptation = retainedAdaptation
                node.presentationChrome.verticalCompactAdaptation = retainedAdaptation
                return node
            }
        }
    }

    func presentationCompactAdaptation(
        horizontal: PresentationAdaptation,
        vertical: PresentationAdaptation
    ) -> some View {
        return ModifiedView(content: self) { content, context in
            let component = content.makeComponent(context: context)
            let horizontalAdaptation = horizontal.retainedAdaptation
            let verticalAdaptation = vertical.retainedAdaptation
            return Component { runtime in
                let node = component.makeNode(runtime: runtime)
                node.presentationChrome.hasCompactAdaptationOverride = true
                node.presentationChrome.horizontalCompactAdaptation = horizontalAdaptation
                node.presentationChrome.verticalCompactAdaptation = verticalAdaptation
                return node
            }
        }
    }

    func alert(isPresented: Binding<Bool>, content alertContent: @escaping () -> Alert) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedAlertPresentation(
                base: base,
                alert: alertContent(),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func alert<Item>(
        item: Binding<Item?>,
        content alertContent: @escaping (Item) -> Alert
    ) -> some View where Item: Identifiable {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard let selectedItem = item.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard item.wrappedValue != nil else {
                    return
                }

                item.wrappedValue = nil
                context.invalidate()
            }

            return retainedAlertPresentation(
                base: base,
                alert: alertContent(selectedItem),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func alert(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> [AnyView] = { [] },
        @ViewBuilder message: @escaping () -> [AnyView] = { [] }
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedAlertBuilderPresentation(
                base: base,
                title: Text(titleKey),
                messageViews: message(),
                actionViews: actions(),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func alert<S: StringProtocol>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> [AnyView] = { [] },
        @ViewBuilder message: @escaping () -> [AnyView] = { [] }
    ) -> some View {
        alert(
            LocalizedStringKey(String(title)),
            isPresented: isPresented,
            actions: actions,
            message: message
        )
    }

    func alert<Data>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        presenting data: Data?,
        @ViewBuilder actions: @escaping (Data) -> [AnyView],
        @ViewBuilder message: @escaping (Data) -> [AnyView] = { _ in [] }
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue, let presentedData = data else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedAlertBuilderPresentation(
                base: base,
                title: Text(titleKey),
                messageViews: message(presentedData),
                actionViews: actions(presentedData),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func alert<S: StringProtocol, Data>(
        _ title: S,
        isPresented: Binding<Bool>,
        presenting data: Data?,
        @ViewBuilder actions: @escaping (Data) -> [AnyView],
        @ViewBuilder message: @escaping (Data) -> [AnyView] = { _ in [] }
    ) -> some View {
        alert(
            LocalizedStringKey(String(title)),
            isPresented: isPresented,
            presenting: data,
            actions: actions,
            message: message
        )
    }

    func actionSheet(isPresented: Binding<Bool>, content actionSheetContent: @escaping () -> ActionSheet) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedActionSheetPresentation(
                base: base,
                actionSheet: actionSheetContent(),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func actionSheet<Item>(
        item: Binding<Item?>,
        content actionSheetContent: @escaping (Item) -> ActionSheet
    ) -> some View where Item: Identifiable {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard let selectedItem = item.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard item.wrappedValue != nil else {
                    return
                }

                item.wrappedValue = nil
                context.invalidate()
            }

            return retainedActionSheetPresentation(
                base: base,
                actionSheet: actionSheetContent(selectedItem),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func confirmationDialog(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> [AnyView],
        @ViewBuilder message: @escaping () -> [AnyView] = { [] }
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedConfirmationDialogPresentation(
                base: base,
                title: Text(titleKey),
                titleVisibility: titleVisibility,
                messageViews: message(),
                actionViews: actions(),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func confirmationDialog<S: StringProtocol>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> [AnyView],
        @ViewBuilder message: @escaping () -> [AnyView] = { [] }
    ) -> some View {
        confirmationDialog(
            LocalizedStringKey(String(title)),
            isPresented: isPresented,
            titleVisibility: titleVisibility,
            actions: actions,
            message: message
        )
    }

    func confirmationDialog<Data>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        presenting data: Data?,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping (Data) -> [AnyView],
        @ViewBuilder message: @escaping (Data) -> [AnyView] = { _ in [] }
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            guard isPresented.wrappedValue, let presentedData = data else {
                return base
            }

            let dismiss: @MainActor () -> Void = {
                guard isPresented.wrappedValue else {
                    return
                }

                isPresented.wrappedValue = false
                context.invalidate()
            }

            return retainedConfirmationDialogPresentation(
                base: base,
                title: Text(titleKey),
                titleVisibility: titleVisibility,
                messageViews: message(presentedData),
                actionViews: actions(presentedData),
                context: context,
                dismiss: dismiss
            )
        }
    }

    func confirmationDialog<S: StringProtocol, Data>(
        _ title: S,
        isPresented: Binding<Bool>,
        presenting data: Data?,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping (Data) -> [AnyView],
        @ViewBuilder message: @escaping (Data) -> [AnyView] = { _ in [] }
    ) -> some View {
        confirmationDialog(
            LocalizedStringKey(String(title)),
            isPresented: isPresented,
            presenting: data,
            titleVisibility: titleVisibility,
            actions: actions,
            message: message
        )
    }

    func aspectRatio(_ aspectRatio: Double? = nil, contentMode: ContentMode) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let baseSize = childNode.intrinsicContentSize()
                let preferredSize = aspectRatioPreferredSize(
                    baseSize: baseSize,
                    requestedAspectRatio: aspectRatio,
                    contentMode: contentMode
                )
                return Controls.stackPanel(
                    preferredSize: preferredSize,
                    stackLayout: .vertical(padding: .zero, alignment: .center, mainAlignment: .center),
                    isHitTestVisible: false,
                    children: [childNode]
                )
            }
        }
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

    func background(_ color: Color, alignment: Alignment) -> some View {
        _ = alignment
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

    func background(_ color: Color?, alignment: Alignment) -> some View {
        _ = alignment
        return background(color)
    }

    func background(_ style: ForegroundStyle, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        let fill = resolvedStyleFill(from: style)
        return backgroundStyle(color: fill.color, gradient: fill.gradient)
    }

    func background(_ style: ForegroundStyle, alignment: Alignment) -> some View {
        _ = alignment
        return background(style)
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

    func background(_ gradient: LinearGradient, alignment: Alignment) -> some View {
        _ = alignment
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

    func overlay(_ color: Color, alignment: Alignment) -> some View {
        _ = alignment
        return overlay(color)
    }

    func overlay(_ color: Color?, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        return overlayStyle(color: color, gradient: nil)
    }

    func overlay(_ color: Color?, alignment: Alignment) -> some View {
        _ = alignment
        return overlay(color)
    }

    func overlay(_ style: ForegroundStyle, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        _ = edges
        let fill = resolvedStyleFill(from: style)
        return overlayStyle(color: fill.color, gradient: fill.gradient)
    }

    func overlay(_ style: ForegroundStyle, alignment: Alignment) -> some View {
        _ = alignment
        return overlay(style)
    }

    func overlay(_ gradient: LinearGradient) -> some View {
        overlayStyle(color: nil, gradient: gradient)
    }

    func overlay(_ gradient: LinearGradient, ignoresSafeAreaEdges edges: Edge.Set) -> some View {
        _ = edges
        return overlay(gradient)
    }

    func overlay(_ gradient: LinearGradient, alignment: Alignment) -> some View {
        _ = alignment
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

    func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.symbolRenderingMode, mode))
        }
    }

    func symbolVariant(_ variant: SymbolVariants) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.symbolVariants, variant))
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

    func buttonStyle(_ style: DefaultButtonStyle) -> some View {
        buttonStyle(.automatic)
    }

    func buttonStyle(_ style: AccessoryBarButtonStyle) -> some View {
        buttonStyle(.accessoryBar)
    }

    func buttonStyle(_ style: AccessoryBarActionButtonStyle) -> some View {
        buttonStyle(.accessoryBarAction)
    }

    func buttonStyle(_ style: PlainButtonStyle) -> some View {
        buttonStyle(.plain)
    }

    func buttonStyle(_ style: BorderedButtonStyle) -> some View {
        ModifiedView(content: self) { content, context in
            let styledContext = context.withButtonStyle(.bordered)
            if let tint = style.tint {
                return content.makeComponent(context: styledContext.withTint(tint))
            }
            return content.makeComponent(context: styledContext)
        }
    }

    func buttonStyle(_ style: BorderedProminentButtonStyle) -> some View {
        buttonStyle(.borderedProminent)
    }

    func buttonStyle(_ style: BorderlessButtonStyle) -> some View {
        buttonStyle(.borderless)
    }

    func buttonStyle(_ style: CardButtonStyle) -> some View {
        buttonStyle(.card)
    }

    func buttonStyle(_ style: LinkButtonStyle) -> some View {
        buttonStyle(.link)
    }

    func buttonRepeatBehavior(_ behavior: ButtonRepeatBehavior) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.buttonRepeatBehavior, behavior))
        }
    }

    func buttonSizing(_ sizing: ButtonSizing) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.buttonSizing, sizing))
        }
    }

    func buttonBorderShape(_ shape: ButtonBorderShape) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.buttonBorderShape, shape))
        }
    }

    func menuIndicator(_ visibility: Visibility) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.menuIndicatorVisibility, visibility))
        }
    }

    func pickerStyle(_ style: PickerStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withPickerStyle(style))
        }
    }

    func pickerStyle(_ style: DefaultPickerStyle) -> some View {
        pickerStyle(.automatic)
    }

    func pickerStyle(_ style: InlinePickerStyle) -> some View {
        pickerStyle(.inline)
    }

    func pickerStyle(_ style: SegmentedPickerStyle) -> some View {
        pickerStyle(.segmented)
    }

    func pickerStyle(_ style: MenuPickerStyle) -> some View {
        pickerStyle(.menu)
    }

    func pickerStyle(_ style: NavigationLinkPickerStyle) -> some View {
        pickerStyle(.navigationLink)
    }

    func pickerStyle(_ style: PalettePickerStyle) -> some View {
        pickerStyle(.palette)
    }

    func pickerStyle(_ style: RadioGroupPickerStyle) -> some View {
        pickerStyle(.radioGroup)
    }

    func pickerStyle(_ style: WheelPickerStyle) -> some View {
        pickerStyle(.wheel)
    }

    @available(*, deprecated, message: "Use MenuPickerStyle instead.")
    func pickerStyle(_ style: PopUpButtonPickerStyle) -> some View {
        pickerStyle(.popUpButton)
    }

    func labelStyle(_ style: LabelStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.labelStyle, style))
        }
    }

    func labelStyle(_ style: DefaultLabelStyle) -> some View {
        labelStyle(.automatic)
    }

    func labelStyle(_ style: IconOnlyLabelStyle) -> some View {
        labelStyle(.iconOnly)
    }

    func labelStyle(_ style: TitleAndIconLabelStyle) -> some View {
        labelStyle(.titleAndIcon)
    }

    func labelStyle(_ style: TitleOnlyLabelStyle) -> some View {
        labelStyle(.titleOnly)
    }

    func labeledContentStyle(_ style: LabeledContentStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.labeledContentStyle, style))
        }
    }

    func formStyle(_ style: FormStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.formStyle, style))
        }
    }

    func formStyle(_ style: AutomaticFormStyle) -> some View {
        formStyle(.automatic)
    }

    func formStyle(_ style: ColumnsFormStyle) -> some View {
        formStyle(.columns)
    }

    func formStyle(_ style: GroupedFormStyle) -> some View {
        formStyle(.grouped)
    }

    func groupBoxStyle(_ style: GroupBoxStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.groupBoxStyle, style))
        }
    }

    func disclosureGroupStyle(_ style: DisclosureGroupStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.disclosureGroupStyle, style))
        }
    }

    func menuStyle(_ style: MenuStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.menuStyle, style))
        }
    }

    func menuStyle(_ style: ButtonMenuStyle) -> some View {
        menuStyle(.button)
    }

    func menuStyle(_ style: BorderedButtonMenuStyle) -> some View {
        menuStyle(MenuStyle(kind: .borderedButtonStyle(showsMenuIndicator: style.showsMenuIndicator)))
    }

    func menuStyle(_ style: BorderlessButtonMenuStyle) -> some View {
        menuStyle(MenuStyle(kind: .borderlessButtonStyle(showsMenuIndicator: style.showsMenuIndicator)))
    }

    func controlGroupStyle(_ style: ControlGroupStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.controlGroupStyle, style))
        }
    }

    func controlGroupStyle(_ style: AutomaticControlGroupStyle) -> some View {
        controlGroupStyle(.automatic)
    }

    func controlGroupStyle(_ style: CompactMenuControlGroupStyle) -> some View {
        controlGroupStyle(.compactMenu)
    }

    func controlGroupStyle(_ style: MenuControlGroupStyle) -> some View {
        controlGroupStyle(.menu)
    }

    func controlGroupStyle(_ style: NavigationControlGroupStyle) -> some View {
        controlGroupStyle(.navigation)
    }

    func controlGroupStyle(_ style: PaletteControlGroupStyle) -> some View {
        controlGroupStyle(.palette)
    }

    func progressViewStyle(_ style: ProgressViewStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.progressViewStyle, style))
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
            content.makeComponent(context: context.withEnvironmentValue(\.gaugeStyle, style))
        }
    }

    func gaugeStyle(_ style: DefaultGaugeStyle) -> some View {
        gaugeStyle(.automatic)
    }

    func gaugeStyle(_ style: LinearGaugeStyle) -> some View {
        gaugeStyle(.linear)
    }

    func gaugeStyle(_ style: LinearCapacityGaugeStyle) -> some View {
        gaugeStyle(.linearCapacity)
    }

    func gaugeStyle(_ style: AccessoryLinearGaugeStyle) -> some View {
        gaugeStyle(.accessoryLinear)
    }

    func gaugeStyle(_ style: AccessoryLinearCapacityGaugeStyle) -> some View {
        gaugeStyle(.accessoryLinearCapacity)
    }

    func gaugeStyle(_ style: CircularGaugeStyle) -> some View {
        ModifiedView(content: self) { content, context in
            let styledContext = context.withEnvironmentValue(\.gaugeStyle, GaugeStyle.circular)
            if let tint = style.tint {
                return content.makeComponent(context: styledContext.withTint(tint))
            }
            return content.makeComponent(context: styledContext)
        }
    }

    func gaugeStyle(_ style: AccessoryCircularGaugeStyle) -> some View {
        gaugeStyle(.accessoryCircular)
    }

    func gaugeStyle(_ style: AccessoryCircularCapacityGaugeStyle) -> some View {
        gaugeStyle(.accessoryCircularCapacity)
    }

    func datePickerStyle(_ style: DatePickerStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.datePickerStyle, style))
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

    func datePickerStyle(_ style: GraphicalDatePickerStyle) -> some View {
        datePickerStyle(.graphical)
    }

    func datePickerStyle(_ style: StepperFieldDatePickerStyle) -> some View {
        datePickerStyle(.stepperField)
    }

    func datePickerStyle(_ style: WheelDatePickerStyle) -> some View {
        datePickerStyle(.wheel)
    }

    func tabViewStyle(_ style: TabViewStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.tabViewStyle, style))
        }
    }

    func tabViewStyle(_ style: DefaultTabViewStyle) -> some View {
        tabViewStyle(.automatic)
    }

    func tabViewStyle(_ style: SidebarAdaptableTabViewStyle) -> some View {
        tabViewStyle(.sidebarAdaptable)
    }

    func tabViewStyle(_ style: TabBarOnlyTabViewStyle) -> some View {
        tabViewStyle(.tabBarOnly)
    }

    func tabViewStyle(_ style: GroupedTabViewStyle) -> some View {
        tabViewStyle(.grouped)
    }

    func tabViewStyle(_ style: PageTabViewStyle) -> some View {
        tabViewStyle(.page(indexDisplayMode: style.indexDisplayMode))
    }

    func tabViewStyle(_ style: VerticalPageTabViewStyle) -> some View {
        tabViewStyle(.verticalPage(transitionStyle: style.transitionStyle))
    }

    func tabViewStyle(_ style: CarouselTabViewStyle) -> some View {
        tabViewStyle(.carousel)
    }

    func indexViewStyle(_ style: IndexViewStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.indexViewStyle, style))
        }
    }

    func indexViewStyle(_ style: PageIndexViewStyle) -> some View {
        indexViewStyle(.page(backgroundDisplayMode: style.backgroundDisplayMode))
    }

    func toggleStyle(_ style: ToggleStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.toggleStyle, style))
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

    func textFieldStyle(_ style: TextFieldStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textFieldStyle, style))
        }
    }

    func textFieldStyle(_ style: DefaultTextFieldStyle) -> some View {
        textFieldStyle(.automatic)
    }

    func textFieldStyle(_ style: PlainTextFieldStyle) -> some View {
        textFieldStyle(.plain)
    }

    func textFieldStyle(_ style: RoundedBorderTextFieldStyle) -> some View {
        textFieldStyle(.roundedBorder)
    }

    func textFieldStyle(_ style: SquareBorderTextFieldStyle) -> some View {
        textFieldStyle(.squareBorder)
    }

    func listStyle(_ style: ListStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.listStyle, style))
        }
    }

    func listStyle(_ style: DefaultListStyle) -> some View {
        listStyle(.automatic)
    }

    func listStyle(_ style: BorderedListStyle) -> some View {
        listStyle(.bordered)
    }

    func listStyle(_ style: CarouselListStyle) -> some View {
        listStyle(.carousel)
    }

    func listStyle(_ style: EllipticalListStyle) -> some View {
        listStyle(.elliptical)
    }

    func listStyle(_ style: PlainListStyle) -> some View {
        listStyle(.plain)
    }

    func listStyle(_ style: GroupedListStyle) -> some View {
        listStyle(.grouped)
    }

    func listStyle(_ style: InsetListStyle) -> some View {
        listStyle(.inset(alternatesRowBackgrounds: style.alternatesRowBackgrounds))
    }

    func listStyle(_ style: InsetGroupedListStyle) -> some View {
        listStyle(.insetGrouped)
    }

    func listStyle(_ style: SidebarListStyle) -> some View {
        listStyle(.sidebar)
    }

    func textInputAutocapitalization(_ textInputAutocapitalization: TextInputAutocapitalization?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textInputAutocapitalization, textInputAutocapitalization))
        }
    }

    func textSelectionAffinity(_ affinity: TextSelectionAffinity) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textSelectionAffinity, affinity))
        }
    }

    func autocorrectionDisabled(_ disable: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isAutocorrectionDisabled, disable))
        }
    }

    func disableAutocorrection(_ disable: Bool?) -> some View {
        autocorrectionDisabled(disable ?? false)
    }

    func textContentType(_ textContentType: NSTextContentType?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textContentType, textContentType))
        }
    }

    func keyboardType(_ type: UIKeyboardType) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.keyboardType, type))
        }
    }

    func textInputCompletion(_ completion: String) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(
                context: context.withEnvironmentValue(\.textInputCompletion, completion)
            )
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.textInputCompletion = completion
                return childNode
            }
        }
    }

    func textInputSuggestions(@ViewBuilder _ suggestions: () -> [AnyView]) -> some View {
        let suggestionViews = suggestions()
        return ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textInputSuggestions, suggestionViews))
        }
    }

    func textInputSuggestions<Data>(
        _ data: Data,
        @ViewBuilder content: @escaping (Data.Element) -> [AnyView]
    ) -> some View where Data: RandomAccessCollection, Data.Element: Identifiable {
        textInputSuggestions {
            ForEach(data, content: content)
        }
    }

    func textInputSuggestions<Data, ID>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> [AnyView]
    ) -> some View where Data: RandomAccessCollection, ID: Hashable {
        textInputSuggestions {
            ForEach(data, id: id, content: content)
        }
    }

    func writingToolsBehavior(_ behavior: WritingToolsBehavior) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.writingToolsBehavior, Optional(behavior)))
        }
    }

    func writingToolsAffordanceVisibility(_ visibility: Visibility) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.writingToolsAffordanceVisibility, visibility))
        }
    }

    func findDisabled(_ isDisabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isFindDisabled, isDisabled))
        }
    }

    func replaceDisabled(_ isDisabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isReplaceDisabled, isDisabled))
        }
    }

    func findNavigator(isPresented: Binding<Bool>) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.isFindNavigatorPresented, isPresented.wrappedValue))
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

    func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.navigationBarBackButtonHidden = hidesBackButton
        return modified
    }

    func navigationBarHidden(_ hidden: Bool) -> some View {
        var modified = ModifiedView(content: self) { content, context in
            content.makeComponent(context: context)
        }
        modified.navigationBarHidden = hidden
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

    func navigationViewStyle(_ style: NavigationViewStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.navigationViewStyle, style))
        }
    }

    func navigationViewStyle(_ style: DefaultNavigationViewStyle) -> some View {
        navigationViewStyle(.automatic)
    }

    func navigationViewStyle(_ style: StackNavigationViewStyle) -> some View {
        navigationViewStyle(.stack)
    }

    func navigationViewStyle(_ style: DoubleColumnNavigationViewStyle) -> some View {
        navigationViewStyle(.doubleColumn)
    }

    func navigationViewStyle(_ style: ColumnsNavigationViewStyle) -> some View {
        navigationViewStyle(.columns)
    }

    func navigationSplitViewStyle(_ style: NavigationSplitViewStyle) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.navigationSplitViewStyle, style))
        }
    }

    func navigationSplitViewStyle(_ style: AutomaticNavigationSplitViewStyle) -> some View {
        navigationSplitViewStyle(.automatic)
    }

    func navigationSplitViewStyle(_ style: BalancedNavigationSplitViewStyle) -> some View {
        navigationSplitViewStyle(.balanced)
    }

    func navigationSplitViewStyle(_ style: ProminentDetailNavigationSplitViewStyle) -> some View {
        navigationSplitViewStyle(.prominentDetail)
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

    func environmentObject<ObjectType: ObservableObject>(_ object: ObjectType) -> some View {
        ModifiedView(content: self) { content, context in
            var environmentObjects = context.environmentValues.environmentObjects
            environmentObjects.setObject(object, for: ObjectType.self)
            return content.makeComponent(context: context.withEnvironmentValue(\.environmentObjects, environmentObjects))
        }
    }

    func transformEnvironment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        transform: @escaping (inout Value) -> Void
    ) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withTransformedEnvironmentValue(keyPath, transform))
        }
    }

    func focusedValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value?) -> some View {
        ModifiedView(content: self) { content, context in
            var focusedValues = context.environmentValues.focusedValues
            focusedValues[keyPath: keyPath] = value
            return content.makeComponent(context: context.withEnvironmentValue(\.focusedValues, focusedValues))
        }
    }

    func focusedSceneValue<Value>(_ keyPath: WritableKeyPath<FocusedValues, Value?>, _ value: Value?) -> some View {
        focusedValue(keyPath, value)
    }

    func focusedObject<ObjectType: ObservableObject>(_ object: ObjectType?) -> some View {
        ModifiedView(content: self) { content, context in
            var focusedValues = context.environmentValues.focusedValues
            focusedValues.setFocusedObject(object, for: ObjectType.self)
            return content.makeComponent(context: context.withEnvironmentValue(\.focusedValues, focusedValues))
        }
    }

    func focusedSceneObject<ObjectType: ObservableObject>(_ object: ObjectType?) -> some View {
        focusedObject(object)
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
        bold(true)
    }

    func bold(_ isActive: Bool) -> some View {
        fontWeight(isActive ? .bold : .regular)
    }

    func italic(_ isActive: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.fontItalic, isActive))
        }
    }

    func monospaced(_ isActive: Bool = true) -> some View {
        fontDesign(isActive ? .monospaced : .default)
    }

    func monospacedDigit() -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.fontMonospacedDigits, true))
        }
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
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withLineLimit(
                    lineLimit,
                    minimumLineLimit: reservesSpace ? lineLimit : nil,
                    reservesSpace: reservesSpace
                )
            )
        }
    }

    func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withLineLimit(limit.upperBound))
        }
    }

    func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withLineLimit(nil, minimumLineLimit: limit.lowerBound))
        }
    }

    func lineLimit(_ limits: ClosedRange<Int>) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withLineLimit(
                    limits.upperBound,
                    minimumLineLimit: limits.lowerBound
                )
            )
        }
    }

    func lineSpacing(_ lineSpacing: Double) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.lineSpacing, lineSpacing))
        }
    }

    func minimumScaleFactor(_ factor: CGFloat) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(
                    \.minimumScaleFactor,
                    EnvironmentValues.clampedMinimumScaleFactor(factor)
                )
            )
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

    func textSelection(_ selectability: TextSelectability) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.textSelectability, selectability))
        }
    }

    func underline(
        _ isActive: Bool = true,
        pattern: Text.LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(
                    \.underlineStyle,
                    TextDecorationSetting(isActive: isActive, pattern: pattern, color: color)
                )
            )
        }
    }

    func strikethrough(
        _ isActive: Bool = true,
        pattern: Text.LineStyle.Pattern = .solid,
        color: Color? = nil
    ) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(
                    \.strikethroughStyle,
                    TextDecorationSetting(isActive: isActive, pattern: pattern, color: color)
                )
            )
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
                let root = Controls.stackPanel(
                    cornerRadius: radius,
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
                root.clipFillStyle = RetainedClipFillStyle(antialiased: antialiased)
                return root
            }
        }
    }

    func clipped(antialiased: Bool = false) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let root = Controls.stackPanel(
                    clipsToBounds: true,
                    stackLayout: .vertical(alignment: .stretch),
                    isHitTestVisible: false,
                    children: [childNode]
                )
                root.clipFillStyle = RetainedClipFillStyle(antialiased: antialiased)
                return root
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
                root.clipFillStyle = RetainedClipFillStyle(eoFill: style.isEOFilled, antialiased: style.isAntialiased)

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
        let retainedStyle = retainedContentShapeStyle(for: shape)
        let retainedShape = RetainedContentShape(
            kinds: kind.retainedKinds,
            style: retainedStyle,
            eoFill: eoFill
        )
        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.contentShapes.append(retainedShape)
                return childNode
            }
        }
    }

    func border(_ color: Color, width: Double = 1, cornerRadius: Double = 0) -> some View {
        borderStyle(color: color, gradient: nil, width: width, cornerRadius: cornerRadius)
    }

    private func borderStyle(
        color: Color,
        gradient: LinearGradient?,
        width: Double,
        cornerRadius: Double
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                return Controls.stackPanel(
                    borderColor: color,
                    borderGradient: gradient,
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
        let fill = resolvedBorderFill(from: style)
        return borderStyle(color: fill.color, gradient: fill.gradient, width: width, cornerRadius: cornerRadius)
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

    func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isFocusable = true
                childNode.isHitTestVisible = true
                let previousFocusEnter = childNode.onFocusEnter
                let previousFocusExit = childNode.onFocusExit
                childNode.onFocusEnter = {
                    previousFocusEnter?()
                    condition.wrappedValue = true
                }
                childNode.onFocusExit = {
                    previousFocusExit?()
                    condition.wrappedValue = false
                }
                if condition.wrappedValue {
                    runtime.requestFocus(childNode)
                }
                return childNode
            }
        }
    }

    func focused<Value>(
        _ binding: FocusState<Value?>.Binding,
        equals value: Value
    ) -> some View where Value: Hashable {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isFocusable = true
                childNode.isHitTestVisible = true
                let previousFocusEnter = childNode.onFocusEnter
                let previousFocusExit = childNode.onFocusExit
                childNode.onFocusEnter = {
                    previousFocusEnter?()
                    binding.wrappedValue = value
                }
                childNode.onFocusExit = {
                    previousFocusExit?()
                    if binding.wrappedValue == value {
                        binding.wrappedValue = nil
                    }
                }
                if binding.wrappedValue == value {
                    runtime.requestFocus(childNode)
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
            let resolvedContext = context.withEnvironmentValue(
                \.isFocusEffectEnabled,
                context.environmentValues.isFocusEffectEnabled && !disabled
            )
            let child = content.makeComponent(context: resolvedContext)
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

    func onDeleteCommand(perform action: (() -> Void)?) -> some View {
        keyCommandModifier { event in
            switch event.key {
            case .backspace, .deleteForward:
                action?()
                return true

            default:
                return false
            }
        }
    }

    func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View {
        keyCommandModifier { event in
            let direction: MoveCommandDirection
            switch event.key {
            case .upArrow:
                direction = .up
            case .downArrow:
                direction = .down
            case .leftArrow:
                direction = .left
            case .rightArrow:
                direction = .right
            default:
                return false
            }

            action?(direction)
            return true
        }
    }

    func onExitCommand(perform action: (() -> Void)?) -> some View {
        keyCommandModifier { event in
            guard event.key == .escape else {
                return false
            }

            action?()
            return true
        }
    }

    func pageCommand<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V = 1
    ) -> some View where V: BinaryInteger {
        keyCommandModifier { event in
            let currentValue = value.wrappedValue
            let nextValue: V

            switch event.key {
            case .pageUp:
                nextValue = currentValue - step
            case .pageDown:
                nextValue = currentValue + step
            default:
                return false
            }

            if bounds.contains(nextValue) {
                value.wrappedValue = nextValue
            }
            return true
        }
    }

    func onPlayPauseCommand(perform action: (() -> Void)?) -> some View {
        keyCommandModifier { event in
            guard event.key == .mediaPlayPause else {
                return false
            }

            action?()
            return true
        }
    }

    func gesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        gesture._applying(to: self, including: mask)
    }

    func gesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        guard isEnabled else {
            return AnyView(self)
        }

        return AnyView(gesture._applying(to: self, including: .all))
    }

    func gesture<G: Gesture>(_ gesture: G, name: String, isEnabled: Bool = true) -> some View {
        let _ = name
        guard isEnabled else {
            return AnyView(self)
        }

        return AnyView(gesture._applying(to: self, including: .all))
    }

    func highPriorityGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        gesture._applying(to: self, including: mask)
    }

    func highPriorityGesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        guard isEnabled else {
            return AnyView(self)
        }

        return AnyView(gesture._applying(to: self, including: .all))
    }

    func highPriorityGesture<G: Gesture>(_ gesture: G, name: String, isEnabled: Bool = true) -> some View {
        let _ = name
        guard isEnabled else {
            return AnyView(self)
        }

        return AnyView(gesture._applying(to: self, including: .all))
    }

    func simultaneousGesture<G: Gesture>(_ gesture: G, including mask: GestureMask = .all) -> some View {
        gesture._applying(to: self, including: mask)
    }

    func simultaneousGesture<G: Gesture>(_ gesture: G, isEnabled: Bool) -> some View {
        guard isEnabled else {
            return AnyView(self)
        }

        return AnyView(gesture._applying(to: self, including: .all))
    }

    func simultaneousGesture<G: Gesture>(_ gesture: G, name: String, isEnabled: Bool = true) -> some View {
        let _ = name
        guard isEnabled else {
            return AnyView(self)
        }

        return AnyView(gesture._applying(to: self, including: .all))
    }

    private func keyCommandModifier(
        perform handler: @escaping (KeyboardEvent) -> Bool
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isFocusable = true
                childNode.isHitTestVisible = true

                let existingOnKeyDown = childNode.onKeyDown
                childNode.onKeyDown = { event in
                    if handler(event) {
                        return
                    }

                    existingOnKeyDown?(event)
                }
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

    func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityTraits.formUnion(traits.retainedTraits)
                return childNode
            }
        }
    }

    func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityTraits.subtract(traits.retainedTraits)
                return childNode
            }
        }
    }

    func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityChildBehavior = children.retainedBehavior
                return childNode
            }
        }
    }

    func accessibilitySortPriority(_ priority: Double) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilitySortPriority = priority
                return childNode
            }
        }
    }

    func accessibilityAction(_ action: @escaping () -> Void) -> some View {
        accessibilityAction(.default, action)
    }

    func accessibilityAction(_ kind: AccessibilityActionKind, _ action: @escaping () -> Void) -> some View {
        accessibilityAction(kind: kind.retainedKind, name: nil, action)
    }

    func accessibilityAction<S: StringProtocol>(named name: S, _ action: @escaping () -> Void) -> some View {
        accessibilityAction(kind: nil, name: String(name), action)
    }

    func accessibilityAction(named nameKey: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        accessibilityAction(kind: nil, name: nameKey.resolvedString, action)
    }

    func accessibilityAction(named name: Text, _ action: @escaping () -> Void) -> some View {
        accessibilityAction(kind: nil, name: name.plainContent, action)
    }

    private func accessibilityAction(
        kind: RetainedAccessibilityActionKind?,
        name: String?,
        _ action: @escaping () -> Void
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.accessibilityActions.append(
                    RetainedAccessibilityAction(
                        name: name,
                        kind: kind,
                        handler: action
                    )
                )
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

    func flipsForRightToLeftLayoutDirection(_ enabled: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                if enabled && context.layoutDirection == .rightToLeft {
                    if childNode.transform.isIdentity {
                        childNode.transform = .scale(x: -1, y: 1)
                    } else {
                        childNode.transform.scaleX *= -1
                    }
                }
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

    func contentMargins(_ length: CGFloat, for placement: ContentMarginPlacement = .automatic) -> some View {
        contentMargins(.all, length, for: placement)
    }

    func contentMargins(
        _ edges: Edge.Set = .all,
        _ length: CGFloat?,
        for placement: ContentMarginPlacement = .automatic
    ) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withTransformedEnvironmentValue(\.contentMargins) { margins in
                    margins.set(edges, to: length, for: placement)
                }
            )
        }
    }

    func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withTransformedEnvironmentValue(\.defaultScrollAnchors) { anchors in
                    anchors.set(anchor)
                }
            )
        }
    }

    func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withTransformedEnvironmentValue(\.defaultScrollAnchors) { anchors in
                    anchors.set(anchor, for: role)
                }
            )
        }
    }

    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.scrollDismissesKeyboardMode, mode))
        }
    }

    func searchDictationBehavior(_ dictationBehavior: TextInputDictationBehavior) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.searchDictationBehavior, Optional(dictationBehavior)))
        }
    }

    func defaultWheelPickerItemHeight(_ height: CGFloat) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.defaultWheelPickerItemHeight, height))
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
        let taskKey = UUID().uuidString
        return ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                let launch = ViewLifecycleTaskLaunch(
                    key: taskKey,
                    priority: priority,
                    action: action
                )

                let existingOnAppearWithNode = childNode.onAppearWithNode
                childNode.onAppearWithNode = { node in
                    existingOnAppearWithNode?(node)
                    node.launchLifecycleTask(launch)
                }

                let existingOnDisappearWithNode = childNode.onDisappearWithNode
                childNode.onDisappearWithNode = { node in
                    existingOnDisappearWithNode?(node)
                    node.cancelLifecycleTask(key: taskKey)
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
                let launch = ViewLifecycleTaskLaunch(
                    key: key,
                    priority: priority,
                    action: action
                )

                if let launchState, launchState.oldValue != launchState.newValue {
                    childNode.pendingLifecycleTaskLaunches.append(launch)
                }

                let existingOnAppearWithNode = childNode.onAppearWithNode
                childNode.onAppearWithNode = { node in
                    existingOnAppearWithNode?(node)
                    node.launchLifecycleTask(launch)
                }

                let existingOnDisappearWithNode = childNode.onDisappearWithNode
                childNode.onDisappearWithNode = { node in
                    existingOnDisappearWithNode?(node)
                    node.cancelLifecycleTask(key: key)
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

    func renameAction(_ action: @escaping () -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(
                    \.rename,
                    RenameAction(action: action)
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
        return ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.submitLabel, submitLabel))
        }
    }

    func submitScope(_ isBlocking: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isSubmitScopeBoundary = isBlocking
                return childNode
            }
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

    func onContinuousHover(
        coordinateSpace: CoordinateSpace = .local,
        perform action: @escaping (HoverPhase) -> Void
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            let _ = coordinateSpace
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true

                let existingOnPointerMove = childNode.onPointerMove
                childNode.onPointerMove = { point in
                    existingOnPointerMove?(point)
                    action(.active(point))
                }

                let existingOnPointerExit = childNode.onPointerExit
                childNode.onPointerExit = {
                    existingOnPointerExit?()
                    action(.ended)
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

    func onTapGesture(
        count: Int = 1,
        coordinateSpace: CoordinateSpace = .local,
        perform action: @escaping (CGPoint) -> Void
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            let requiredTapCount = max(1, count)
            let _ = coordinateSpace
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true
                var tapProgress = 0

                let existingOnPointerUpInsideAt = childNode.onPointerUpInsideAt
                childNode.onPointerUpInsideAt = { point in
                    existingOnPointerUpInsideAt?(point)
                    tapProgress += 1
                    guard tapProgress >= requiredTapCount else {
                        return
                    }

                    tapProgress = 0
                    action(point)
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

    func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        onLongPressGestureModifier(
            minimumDuration: minimumDuration,
            maximumDistance: maximumDistance,
            action: action,
            pressingChanged: onPressingChanged
        )
    }

    func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        pressing: ((Bool) -> Void)? = nil,
        perform action: @escaping () -> Void
    ) -> some View {
        onLongPressGestureModifier(
            minimumDuration: minimumDuration,
            maximumDistance: maximumDistance,
            action: action,
            pressingChanged: pressing
        )
    }

    func onLongPressGesture(
        minimumDuration: Double = 0.5,
        perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        onLongPressGestureModifier(
            minimumDuration: minimumDuration,
            maximumDistance: 10,
            action: action,
            pressingChanged: onPressingChanged
        )
    }

    func onLongPressGesture(
        minimumDuration: Double = 0.5,
        pressing: ((Bool) -> Void)? = nil,
        perform action: @escaping () -> Void
    ) -> some View {
        onLongPressGestureModifier(
            minimumDuration: minimumDuration,
            maximumDistance: 10,
            action: action,
            pressingChanged: pressing
        )
    }

    private func onLongPressGestureModifier(
        minimumDuration: Double,
        maximumDistance: CGFloat,
        action: @escaping () -> Void,
        pressingChanged: ((Bool) -> Void)?
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            let _ = minimumDuration
            let _ = maximumDistance
            return Component { runtime in
                let childNode = child.makeNode(runtime: runtime)
                childNode.isHitTestVisible = true
                var isPressing = false

                let existingOnPointerDown = childNode.onPointerDown
                childNode.onPointerDown = {
                    existingOnPointerDown?()
                    guard !isPressing else {
                        return
                    }
                    isPressing = true
                    pressingChanged?(true)
                }

                let existingOnPointerUpInside = childNode.onPointerUpInside
                childNode.onPointerUpInside = {
                    existingOnPointerUpInside?()
                    guard isPressing else {
                        return
                    }
                    action()
                    isPressing = false
                    pressingChanged?(false)
                }

                let existingOnPointerUpOutside = childNode.onPointerUpOutside
                childNode.onPointerUpOutside = {
                    existingOnPointerUpOutside?()
                    guard isPressing else {
                        return
                    }
                    isPressing = false
                    pressingChanged?(false)
                }

                let existingOnPointerExit = childNode.onPointerExit
                childNode.onPointerExit = {
                    existingOnPointerExit?()
                    guard isPressing else {
                        return
                    }
                    isPressing = false
                    pressingChanged?(false)
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

    func matchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center,
        isSource: Bool = true
    ) -> some View {
        ModifiedView(content: self) { content, context in
            let child = content.makeComponent(context: context)
            return Component { runtime in
                let node = child.makeNode(runtime: runtime)
                node.matchedGeometryEffect = RetainedMatchedGeometryEffect(
                    namespaceID: namespace.rawValue,
                    elementID: String(describing: id),
                    properties: properties.rawValue,
                    anchor: Point(x: anchor.x, y: anchor.y),
                    isSource: isSource
                )
                return node
            }
        }
    }

    func transition(_ transition: AnyTransition) -> some View {
        ModifiedView(content: self) { content, context in
            _ = transition
            return content.makeComponent(context: context)
        }
    }

    func contentTransition(_ transition: ContentTransition) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(context: context.withEnvironmentValue(\.contentTransition, transition))
        }
    }

    func contentTransitionAddsDrawingGroup(_ addsDrawingGroup: Bool) -> some View {
        ModifiedView(content: self) { content, context in
            content.makeComponent(
                context: context.withEnvironmentValue(
                    \.contentTransitionAddsDrawingGroup,
                    addsDrawingGroup
                )
            )
        }
    }

    func symbolEffect<T: SymbolEffect>(
        _ effect: T,
        options: SymbolEffectOptions = .default,
        isActive: Bool = true
    ) -> some View {
        ModifiedView(content: self) { content, context in
            _ = effect
            _ = options
            _ = isActive
            return content.makeComponent(context: context)
        }
    }

    func symbolEffect<T: SymbolEffect, Value: Equatable>(
        _ effect: T,
        options: SymbolEffectOptions = .default,
        value: Value
    ) -> some View {
        ModifiedView(content: self) { content, context in
            _ = effect
            _ = options
            _ = value
            return content.makeComponent(context: context)
        }
    }

    func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View {
        ModifiedView(content: self) { content, context in
            _ = isEnabled
            return content.makeComponent(context: context)
        }
    }

    func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        ModifiedView(content: self) { content, context in
            _ = feedback
            _ = trigger
            return content.makeComponent(context: context)
        }
    }

    func sensoryFeedback<T: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: T,
        condition: @escaping (T, T) -> Bool
    ) -> some View {
        ModifiedView(content: self) { content, context in
            _ = feedback
            _ = trigger
            _ = condition
            return content.makeComponent(context: context)
        }
    }

    func sensoryFeedback<T: Equatable>(
        trigger: T,
        _ feedback: @escaping (T, T) -> SensoryFeedback?
    ) -> some View {
        ModifiedView(content: self) { content, context in
            _ = trigger
            _ = feedback
            return content.makeComponent(context: context)
        }
    }

    func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        ModifiedView(content: self) { content, context in
            var transaction = Transaction()
            transform(&transaction)
            _ = transaction
            return content.makeComponent(context: context)
        }
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
    invalidate: @escaping () -> Void,
    isRoot: Bool = true
) {
    guard isRoot || !node.isSubmitScopeBoundary else {
        return
    }

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
        attachSubmitHandler(
            to: child,
            triggers: triggers,
            action: action,
            invalidate: invalidate,
            isRoot: false
        )
    }
}
