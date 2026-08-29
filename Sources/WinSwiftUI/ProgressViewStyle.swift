import SwiftWindowsCore
import SwiftWindowsUI

/// Builds the content of a progress indicator using ordinary retained views.
@MainActor
public protocol ProgressViewStyle {
    associatedtype Body: View
    typealias Configuration = ProgressViewStyleConfiguration

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}
/// Source values for one progress view. Labels are built where the style uses them.
public struct ProgressViewStyleConfiguration {
    public let fractionCompleted: Double?
    public var label: Label?
    public var currentValueLabel: CurrentValueLabel?

    // Preserve primitive inputs separately from their normalized public fraction.
    // Mutable public labels, in contrast, are authoritative when delegating.
    let retainedValue: Double?
    let retainedTotal: Double

    @MainActor
    init(value: Double?, total: Double, label: [AnyView], currentValueLabel: [AnyView]) {
        retainedValue = value
        retainedTotal = total
        fractionCompleted = value.map { total > 0 ? min(max($0 / total, 0), 1) : 0 }
        self.label = label.isEmpty ? nil : Label(retainedViews: label)
        self.currentValueLabel = currentValueLabel.isEmpty ? nil : CurrentValueLabel(retainedViews: currentValueLabel)
    }

    @MainActor
    public struct Label: View {
        public typealias Body = Never
        let retainedViews: [AnyView]

        public var body: Never { fatalError("ProgressViewStyleConfiguration.Label has no body") }

        public func makeComponent(context: ViewBuildContext) -> Component {
            composeComponent(
                from: retainedViews, context: context.withViewIdentityRole(.label),
                fallbackLayout: .stack(.vertical(spacing: 0, alignment: .leading)), isHitTestVisible: false)
        }
    }

    @MainActor
    public struct CurrentValueLabel: View {
        public typealias Body = Never
        let retainedViews: [AnyView]

        public var body: Never { fatalError("ProgressViewStyleConfiguration.CurrentValueLabel has no body") }

        public func makeComponent(context: ViewBuildContext) -> Component {
            composeComponent(
                from: retainedViews, context: context.withViewIdentityRole(.value),
                fallbackLayout: .stack(.horizontal(spacing: 0, alignment: .center)), isHitTestVisible: false)
        }
    }
}
/// The preexisting fixed profiles, retained as a Windows environment compatibility API.
/// An inherited custom style is stored separately; this value reports its built-in fallback.
public struct ProgressViewStyleProfile: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case automatic
        case linear
        case circular
        case timer
    }

    nonisolated let kind: Kind

    nonisolated private init(kind: Kind) {
        self.kind = kind
    }

    nonisolated public static let automatic = ProgressViewStyleProfile(kind: .automatic)
    nonisolated public static let linear = ProgressViewStyleProfile(kind: .linear)
    nonisolated public static let circular = ProgressViewStyleProfile(kind: .circular)
    nonisolated public static let timer = ProgressViewStyleProfile(kind: .timer)
}
public struct DefaultProgressViewStyle: Sendable, Equatable {
    nonisolated public init() {}
}
public struct LinearProgressViewStyle: Sendable, Equatable {
    nonisolated public init() {}
}
public struct CircularProgressViewStyle: Sendable, Equatable {
    nonisolated public init() {}
}
/// Windows compatibility profile; this does not add automatic timer updates.
public struct TimerProgressViewStyle: Sendable, Equatable {
    nonisolated public init() {}
}
@MainActor
protocol PrimitiveProgressViewStyle: ProgressViewStyle {
    var retainedProgressViewStyleProfile: ProgressViewStyleProfile { get }
}
extension ProgressViewStyleProfile: PrimitiveProgressViewStyle {
    var retainedProgressViewStyleProfile: ProgressViewStyleProfile { self }

    public func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration, primitiveStyle: self)
    }
}
extension DefaultProgressViewStyle: PrimitiveProgressViewStyle {
    var retainedProgressViewStyleProfile: ProgressViewStyleProfile { .automatic }

    public func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration, primitiveStyle: .automatic)
    }
}
extension LinearProgressViewStyle: PrimitiveProgressViewStyle {
    var retainedProgressViewStyleProfile: ProgressViewStyleProfile { .linear }

    public func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration, primitiveStyle: .linear)
    }
}
extension CircularProgressViewStyle: PrimitiveProgressViewStyle {
    var retainedProgressViewStyleProfile: ProgressViewStyleProfile { .circular }

    public func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration, primitiveStyle: .circular)
    }
}
extension TimerProgressViewStyle: PrimitiveProgressViewStyle {
    var retainedProgressViewStyleProfile: ProgressViewStyleProfile { .timer }

    public func makeBody(configuration: Configuration) -> some View {
        ProgressView(configuration, primitiveStyle: .timer)
    }
}
extension ProgressViewStyle where Self == DefaultProgressViewStyle {
    public static var automatic: DefaultProgressViewStyle { DefaultProgressViewStyle() }
}
extension ProgressViewStyle where Self == LinearProgressViewStyle {
    public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() }
}
extension ProgressViewStyle where Self == CircularProgressViewStyle {
    public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() }
}
extension ProgressViewStyle where Self == TimerProgressViewStyle {
    public static var timer: TimerProgressViewStyle { TimerProgressViewStyle() }
}
/// One immutable style installation. Its address never identifies mounted state.
@MainActor
final class RetainedProgressViewStyleInstallation {
    private let inheritedProfile: ProgressViewStyleProfile
    private let inheritedInstallation: RetainedProgressViewStyleInstallation?
    private let buildBody: (ProgressViewStyleConfiguration, ViewBuildContext) -> Component

    init<Style: ProgressViewStyle>(_ style: Style, context: ViewBuildContext) {
        let values = context.environmentValues
        inheritedProfile = values.progressViewStyle
        inheritedInstallation = values.progressViewStyleInstallation
        buildBody = { configuration, context in
            let styleContext = context.withViewIdentityRole(.modifier).withViewIdentityType(Style.self)
            return withInstalledViewValue(style, context: styleContext) { installed, scopedContext in
                makeViewComponent(
                    installed.makeBody(configuration: configuration),
                    context: scopedContext.withViewIdentityRole(.modifierBody))
            }
        }
    }

    func makeComponent(configuration: ProgressViewStyleConfiguration, context: ViewBuildContext) -> Component {
        // Consume just this installation before invoking authored code. A body
        // that delegates through ProgressView(configuration) sees the remainder.
        // Set the profile first because an explicit profile assignment clears
        // custom installations, including when the profile value is unchanged.
        let bodyContext = context.withEnvironmentValue(\.progressViewStyle, inheritedProfile)
            .withEnvironmentValue(\.progressViewStyleInstallation, inheritedInstallation)
        return buildBody(configuration, bodyContext)
    }
}
extension ViewBuildContext {
    func withProgressViewStyle<Style: ProgressViewStyle>(_ style: Style) -> ViewBuildContext {
        if let primitive = style as? any PrimitiveProgressViewStyle {
            return withEnvironmentValue(\.progressViewStyle, primitive.retainedProgressViewStyleProfile)
        }
        let installation = RetainedProgressViewStyleInstallation(style, context: self)
        return withEnvironmentValue(\.progressViewStyleInstallation, installation)
    }
}
