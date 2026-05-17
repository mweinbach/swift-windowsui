import Foundation

// MARK: - Animation

public enum AnimationEasing: Sendable, Equatable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case spring(response: Double, dampingRatio: Double)
    case timingCurve(c0x: Double, c0y: Double, c1x: Double, c1y: Double)

    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return t * (2 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        case .spring(let response, let dampingRatio):
            let scaledTime = t / max(response, 0.001)
            let damping = max(dampingRatio, 0.001)
            let decay = exp(-damping * scaledTime * 5.0)
            let oscillation = cos(scaledTime * 2.0 * Double.pi)
            let value = 1.0 - decay * oscillation
            return max(0.0, min(1.0, value))
        case .timingCurve(let c0x, let c0y, let c1x, let c1y):
            return cubicBezierValue(t: t, c0x: c0x, c0y: c0y, c1x: c1x, c1y: c1y)
        }
    }

    private func cubicBezierValue(t: Double, c0x: Double, c0y: Double, c1x: Double, c1y: Double) -> Double {
        var start = 0.0
        var end = 1.0
        for _ in 0..<8 {
            let mid = (start + end) / 2
            let x = cubicBezierX(t: mid, c0x: c0x, c1x: c1x)
            if x < t {
                start = mid
            } else {
                end = mid
            }
        }
        let mid = (start + end) / 2
        return cubicBezierY(t: mid, c0y: c0y, c1y: c1y)
    }

    private func cubicBezierX(t: Double, c0x: Double, c1x: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * c0x + 3 * mt * t * t * c1x + t * t * t
    }

    private func cubicBezierY(t: Double, c0y: Double, c1y: Double) -> Double {
        let mt = 1 - t
        return 3 * mt * mt * t * c0y + 3 * mt * t * t * c1y + t * t * t
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

    public static var spring: Animation {
        spring(response: 0.55, dampingRatio: 0.825, blendDuration: 0)
    }

    public static func spring(response: Double = 0.55, dampingRatio: Double = 0.825, blendDuration: Double = 0) -> Animation {
        Animation(duration: response * 5.0, easing: .spring(response: response, dampingRatio: dampingRatio))
    }

    public static func spring(mass: Double = 1.0, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Animation {
        let response = 2.0 * Double.pi / sqrt(max(stiffness / max(mass, 0.001), 0.001))
        let dampingRatio = damping / (2.0 * sqrt(max(mass * stiffness, 0.001)))
        return Animation(duration: response * 5.0, easing: .spring(response: response, dampingRatio: dampingRatio))
    }

    public static func interpolatingSpring(mass: Double = 1.0, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Animation {
        spring(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
    }

    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation {
        spring(response: response, dampingRatio: dampingFraction, blendDuration: blendDuration)
    }

    public static var smooth: Animation {
        spring(response: 0.55, dampingRatio: 0.825, blendDuration: 0)
    }

    public static var snappy: Animation {
        spring(response: 0.35, dampingRatio: 0.7, blendDuration: 0)
    }

    public static var bouncy: Animation {
        spring(response: 0.5, dampingRatio: 0.4, blendDuration: 0)
    }

    public static func spring(duration: Double, bounce: Double = 0) -> Animation {
        spring(response: duration, dampingRatio: 1 - bounce, blendDuration: 0)
    }

    public static func timingCurve(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double, duration: Double = 0.35) -> Animation {
        Animation(duration: duration, easing: .timingCurve(c0x: c0x, c0y: c0y, c1x: c1x, c1y: c1y))
    }

    public func speed(_ speed: Double) -> Animation {
        var copy = self
        copy.duration /= max(speed, 0.001)
        return copy
    }

    public func delay(_ delay: Double) -> Animation {
        var copy = self
        copy.duration += delay
        return copy
    }

    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        self
    }

    public func repeatForever(autoreverses: Bool = true) -> Animation {
        self
    }
}

public struct AnimationCompletionCriteria: Sendable, Equatable {
    private enum Kind: Sendable, Equatable {
        case logicallyComplete
        case removed
    }

    private var kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let logicallyComplete = AnimationCompletionCriteria(kind: .logicallyComplete)
    public static let removed = AnimationCompletionCriteria(kind: .removed)
}

public struct UnitPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = UnitPoint(x: 0.0, y: 0.0)
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

public struct Transaction: Sendable {
    public var animation: Animation?
    public var disablesAnimations: Bool
    public var isContinuous: Bool
    public var scrollTargetAnchor: UnitPoint?
    public var tracksVelocity: Bool

    public init(animation: Animation? = nil) {
        self.animation = animation
        self.disablesAnimations = false
        self.isContinuous = false
        self.scrollTargetAnchor = nil
        self.tracksVelocity = false
    }

    public mutating func addAnimationCompletion(
        criteria: AnimationCompletionCriteria = .logicallyComplete,
        _ completion: @escaping () -> Void
    ) {
        _ = criteria
        completion()
    }
}

@MainActor
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    public init(
        get: @escaping @MainActor () -> Value,
        set: @escaping @MainActor (Value, Transaction) -> Void
    ) {
        self.getValue = get
        self.setValue = { value in
            set(value, Transaction())
        }
    }

    public init<Wrapped>(_ base: Binding<Wrapped>) where Value == Wrapped? {
        self.getValue = {
            base.wrappedValue
        }
        self.setValue = { value in
            guard let value else {
                return
            }
            base.wrappedValue = value
        }
    }

    public init?(_ base: Binding<Value?>) {
        guard let initialValue = base.wrappedValue else {
            return nil
        }

        self.getValue = {
            base.wrappedValue ?? initialValue
        }
        self.setValue = { value in
            base.wrappedValue = value
        }
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

    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(
            get: {
                wrappedValue[keyPath: keyPath]
            },
            set: { newValue in
                var value = wrappedValue
                value[keyPath: keyPath] = newValue
                wrappedValue = value
            }
        )
    }

    public subscript<Element>(position: Value.Index) -> Binding<Element> where Value: MutableCollection, Value.Element == Element {
        Binding<Element>(
            get: {
                wrappedValue[position]
            },
            set: { newValue in
                var value = wrappedValue
                value[position] = newValue
                wrappedValue = value
            }
        )
    }

    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        let _ = transaction
        return self
    }

    public func animation(_ animation: Animation? = .default) -> Binding<Value> {
        let _ = animation
        return self
    }

    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

public struct EditActions: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let delete = EditActions(rawValue: 1 << 0)
    public static let move = EditActions(rawValue: 1 << 1)
    public static let all: EditActions = [.delete, .move]
}

public struct UTType: Sendable, Equatable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var identifier: String

    public init(_ identifier: String) {
        self.identifier = identifier
    }

    public init(filenameExtension: String) {
        self.identifier = "public.filename-extension.\(filenameExtension)"
    }

    public init(mimeType: String) {
        self.identifier = mimeType
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        identifier
    }

    public static let data = UTType("public.data")
    public static let text = UTType("public.text")
    public static let plainText = UTType("public.plain-text")
    public static let utf8PlainText = UTType("public.utf8-plain-text")
    public static let url = UTType("public.url")
    public static let fileURL = UTType("public.file-url")
    public static let image = UTType("public.image")
    public static let png = UTType("public.png")
    public static let jpeg = UTType("public.jpeg")
    public static let json = UTType("public.json")
    public static let movie = UTType("public.movie")
    public static let video = UTType("public.video")
    public static let audio = UTType("public.audio")
    public static let pdf = UTType("com.adobe.pdf")
    public static let zip = UTType("public.zip-archive")
    public static let html = UTType("public.html")
    public static let vCard = UTType("public.vcard")
}

public enum NavigationSplitViewColumn: Sendable, Hashable {
    case sidebar
    case content
    case detail
}

public enum PointerVisibility: Sendable, Equatable, Hashable {
    case automatic
    case hidden
    case visible
}

public enum AccessibilityQuickActionStyle: Sendable, Equatable, Hashable {
    case automatic
    case prompt
}

public enum AccessibilityTextContentType: Sendable, Equatable, Hashable {
    case username
    case password
    case oneTimeCode
    case emailAddress
    case location
    case fullStreetAddress
    case streetAddressLine1
    case streetAddressLine2
    case addressCity
    case addressState
    case addressCityAndState
    case countryName
    case postalCode
    case telephoneNumber
    case creditCardNumber
    case dateTime
    case shipmentTrackingNumber
    case flightNumber
    case dateOfBirth
    case creditCardSecurityCode
    case creditCardName
    case creditCardGivenName
    case creditCardMiddleName
    case creditCardFamilyName
    case creditCardExpiration
    case creditCardExpirationMonth
    case creditCardExpirationYear
    case creditCardType
    case organizationName
    case organizationJobTitle
    case nickname
    case URL
    case name
    case namePrefix
    case givenName
    case middleName
    case familyName
    case nameSuffix
    case newPassword
}

public enum WidgetAccentedRenderingMode: Sendable, Equatable, Hashable {
    case automatic
    case accented
    case fullColor
}

public struct ContainerBackgroundPlacement: Sendable, Equatable, Hashable, CustomStringConvertible {
    private let identifier: String

    private init(_ identifier: String) {
        self.identifier = identifier
    }

    public static let navigation = ContainerBackgroundPlacement("navigation")
    public static let navigationSplitView = ContainerBackgroundPlacement("navigationSplitView")
    public static let tabView = ContainerBackgroundPlacement("tabView")
    public static let widget = ContainerBackgroundPlacement("widget")
    public static let window = ContainerBackgroundPlacement("window")
    public static let subscriptionStore = ContainerBackgroundPlacement("subscriptionStore")
    public static let subscriptionStoreFullHeight = ContainerBackgroundPlacement("subscriptionStoreFullHeight")
    public static let subscriptionStoreHeader = ContainerBackgroundPlacement("subscriptionStoreHeader")

    public var description: String {
        identifier
    }
}

public struct WidgetRelevancy: Sendable, Equatable, Hashable {
    public let value: Double
    public init(_ value: Double) {
        self.value = value
    }
}

public struct PaletteSelectionEffect: Sendable, Equatable, Hashable {
    private enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case highlight
        case custom
    }

    private let kind: Kind

    private init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = PaletteSelectionEffect(kind: .automatic)
    public static let highlight = PaletteSelectionEffect(kind: .highlight)
    public static let custom = PaletteSelectionEffect(kind: .custom)
}

public protocol DynamicProperty {
    mutating func update()
}

public extension DynamicProperty {
    mutating func update() {}
}

public struct NamespaceID: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String = UUID().uuidString) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

public final class AnyShapeStyleBox: @unchecked Sendable {
    public var value: Any?
    public init(_ value: Any? = nil) {
        self.value = value
    }
}

public struct AnyShapeStyle: Sendable, Equatable {
    public var box: AnyShapeStyleBox
    public init() {
        self.box = AnyShapeStyleBox()
    }

    public static func == (lhs: AnyShapeStyle, rhs: AnyShapeStyle) -> Bool {
        lhs.box === rhs.box
    }
}

// MARK: - UIWindowScene Stub

public struct UIWindowScene: Sendable, Equatable {
    public init() {}
}

// MARK: - InspectorPresentationStyle

public struct InspectorPresentationStyle: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case automatic
        case panel
        case sheet
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public static let automatic = InspectorPresentationStyle(kind: .automatic)
    public static let panel = InspectorPresentationStyle(kind: .panel)
    public static let sheet = InspectorPresentationStyle(kind: .sheet)
}
